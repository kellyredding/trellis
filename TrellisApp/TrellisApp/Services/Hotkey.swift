import Carbon.HIToolbox
import Foundation

/// The leader as a Carbon hot key, which needs no permission of its own.
@MainActor
final class Hotkey {
    var onPress: (() -> Void)?
    private(set) var registered: KeyToken?
    private(set) var problem: String?
    private(set) var isSuspended = false

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var wanted: KeyToken?

    /// While suspended this only remembers the token; `resume()` registers it.
    func register(_ token: KeyToken) {
        wanted = token
        guard !isSuspended else { return }
        if token == registered, hotKeyRef != nil { return }
        unregister()
        installHandler()
        guard let keyCode = KeyCodes.byKey[token.key] else {
            problem = "\(token) has no key code"
            return
        }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5452_4C53), id: 1)
        let status = RegisterEventHotKey(
            UInt32(keyCode), Self.carbonModifiers(token.modifiers), id,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref {
            hotKeyRef = ref
            registered = token
            problem = nil
            Log.info("leader registered: \(token)")
        } else {
            problem = "could not register \(token.display(uppercased: true)) (error \(status))"
            Log.error(problem ?? "")
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        registered = nil
    }

    /// A registered hot key consumes its key-down before any window sees it,
    /// so recording a new leader needs the old one out of the way.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        unregister()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        if let wanted { register(wanted) }
    }

    private func installHandler() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotkey = Unmanaged<Hotkey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotkey.onPress?() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
    }

    private static func carbonModifiers(_ modifiers: KeyModifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.ctrl) { flags |= controlKey }
        if modifiers.contains(.alt) { flags |= optionKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.cmd) { flags |= cmdKey }
        return UInt32(flags)
    }
}
