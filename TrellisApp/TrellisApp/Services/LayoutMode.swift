import AppKit
import CoreGraphics

/// Layout mode: an active keyDown event tap, installed only while the mode is
/// open, that swallows every key and feeds it to the chord resolver.
@MainActor
final class LayoutMode: ObservableObject {
    @Published private(set) var isActive = false
    /// The keys typed so far in the current chord.
    @Published private(set) var typed: [KeyToken] = []
    /// The last chord that named no binding, shown until the next key.
    @Published private(set) var missed: [KeyToken]?

    var onRun: ((ResolverBinding) -> Void)?

    private var resolver: ChordResolver?
    private var leader: KeyToken?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var lastLeaderExit: TimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    /// Key codes whose key-down the tap swallowed; only their key-ups are
    /// swallowed too. Swallowing the leader's key-up (its key-down went to the
    /// Carbon hot key, not the tap) left the hot key believing it was still
    /// held, so the next leader press after Esc was ignored.
    private var swallowedDowns: Set<UInt16> = []

    /// Closes the mode when the session goes away (user switch, display
    /// sleep, screen lock), so the tap never swallows keys on return.
    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let sources: [(NotificationCenter, Notification.Name, String)] = [
            (workspace, NSWorkspace.sessionDidResignActiveNotification, "session inactive"),
            (workspace, NSWorkspace.screensDidSleepNotification, "screens slept"),
            (distributed, Notification.Name("com.apple.screenIsLocked"), "screen locked"),
        ]
        for (center, name, reason) in sources {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.exit(reason: reason) }
            })
        }
    }

    /// A reload that changes the leader would otherwise leave the old one as
    /// the tap's exit key.
    func leaderChanged(to leader: KeyToken) {
        guard isActive, leader != self.leader else { return }
        exit(reason: "leader changed")
    }

    /// The leader hot key toggles the mode. The tap may also see the same
    /// ⌃S and close the mode first; the guard keeps that press from reopening it.
    func leaderPressed(config: TrellisConfig?, leader: KeyToken) {
        if isActive {
            exit(reason: "leader")
            lastLeaderExit = ProcessInfo.processInfo.systemUptime
            return
        }
        guard ProcessInfo.processInfo.systemUptime - lastLeaderExit > 0.3 else { return }
        enter(config: config, leader: leader)
    }

    func enter(config: TrellisConfig?, leader: KeyToken) {
        guard !isActive else { return }
        guard AXIsProcessTrusted() else {
            Log.error("layout mode needs the Accessibility permission")
            NSSound.beep()
            return
        }
        guard installTap() else {
            Log.error("could not install the layout-mode event tap")
            NSSound.beep()
            return
        }
        let waitMs = config?.settings.chordWaitMs ?? Settings.defaultChordWaitMs
        resolver = ChordResolver(
            bindings: config?.resolverBindings ?? [],
            wait: Double(waitMs) / 1000,
            clock: { ProcessInfo.processInfo.systemUptime }
        )
        self.leader = leader
        swallowedDowns = []
        typed = []
        missed = nil
        isActive = true
    }

    func exit(reason: String) {
        guard isActive else { return }
        removeTap()
        timer?.invalidate()
        timer = nil
        resolver = nil
        typed = []
        missed = nil
        isActive = false
        Log.info("layout mode closed: \(reason)")
    }

    // MARK: - The tap

    private func installTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: layoutModeTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    private func removeTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap, isActive { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyUp:
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            return swallowedDowns.remove(keyCode) != nil ? nil : Unmanaged.passUnretained(event)
        case .keyDown:
            guard isActive else { return Unmanaged.passUnretained(event) }
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            swallowedDowns.insert(keyCode)
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return nil }
            guard let token = KeyCodes.token(keyCode: keyCode, modifiers: Self.modifiers(event.flags)) else {
                return nil
            }
            key(token)
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func key(_ token: KeyToken) {
        if token.key == "escape" {
            exit(reason: "escape")
            return
        }
        if token == leader {
            exit(reason: "leader")
            lastLeaderExit = ProcessInfo.processInfo.systemUptime
            return
        }
        guard var resolver else { return }
        let outcome = resolver.feed(token)
        self.resolver = resolver
        apply(outcome)
    }

    private func apply(_ outcome: ChordResolver.Outcome) {
        timer?.invalidate()
        timer = nil
        switch outcome {
        case .idle:
            break
        case .waiting(let buffer, let deadline):
            typed = buffer
            missed = nil
            let delay = max(deadline - ProcessInfo.processInfo.systemUptime, 0)
            let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.expire() }
            }
            // Common modes, so the chord still expires while a menu is tracking.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        case .run(let binding):
            exit(reason: "ran \(KeyToken.chordDescription(binding.chord))")
            onRun?(binding)
        case .unrecognized(let keys):
            typed = []
            missed = keys
            Log.info("unrecognized chord: \(KeyToken.chordDescription(keys))")
        }
    }

    private func expire() {
        guard var resolver else { return }
        let outcome = resolver.expire()
        self.resolver = resolver
        apply(outcome)
    }

    private static func modifiers(_ flags: CGEventFlags) -> KeyModifiers {
        var modifiers = KeyModifiers()
        if flags.contains(.maskControl) { modifiers.insert(.ctrl) }
        if flags.contains(.maskAlternate) { modifiers.insert(.alt) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskCommand) { modifiers.insert(.cmd) }
        return modifiers
    }
}

private func layoutModeTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let mode = Unmanaged<LayoutMode>.fromOpaque(userInfo).takeUnretainedValue()
    return MainActor.assumeIsolated { mode.handle(type: type, event: event) }
}
