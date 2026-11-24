import AppKit

/// The screens in contract form (global top-left points, indexed left to
/// right). Read from `NSScreen` on the main thread and cached, so the socket
/// and window work can read them from any queue.
final class ScreenService: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: [ScreenInfo] = []
    private var displayIDs: [Int: CGDirectDisplayID] = [:]
    private var observer: NSObjectProtocol?

    @MainActor
    func start(onChange: @escaping @MainActor () -> Void) {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                onChange()
            }
        }
    }

    var screens: [ScreenInfo] {
        lock.lock()
        defer { lock.unlock() }
        return cached
    }

    @MainActor
    func nsScreen(forIndex index: Int) -> NSScreen? {
        lock.lock()
        let id = displayIDs[index]
        lock.unlock()
        guard let id else { return nil }
        return NSScreen.screens.first { Self.displayID(of: $0) == id }
    }

    /// The screen at AppKit's origin, which carries the menu bar.
    @MainActor
    var primary: NSScreen? { NSScreen.screens.first }

    @MainActor
    func refresh() {
        let all = NSScreen.screens
        guard let primary = all.first else { return }
        let primaryHeight = Double(primary.frame.height)
        let frames = all.map { Geometry.globalFromAppKit(Self.rect($0.frame), primaryHeight: primaryHeight) }
        let indexes = ScreenNeighbor.order(frames)
        var infos: [ScreenInfo] = []
        var ids: [Int: CGDirectDisplayID] = [:]
        for (position, screen) in all.enumerated() {
            let id = Self.displayID(of: screen)
            ids[indexes[position]] = id
            infos.append(ScreenInfo(
                index: indexes[position],
                uuid: Self.uuid(of: id),
                name: screen.localizedName,
                frame: frames[position],
                visibleFrame: Geometry.globalFromAppKit(Self.rect(screen.visibleFrame), primaryHeight: primaryHeight),
                scale: Double(screen.backingScaleFactor),
                main: position == 0
            ))
        }
        infos.sort { $0.index < $1.index }
        lock.lock()
        cached = infos
        displayIDs = ids
        lock.unlock()
    }

    static func rect(_ r: CGRect) -> Rect {
        Rect(x: Double(r.origin.x), y: Double(r.origin.y), w: Double(r.width), h: Double(r.height))
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return CGDirectDisplayID(number?.uint32Value ?? 0)
    }

    private static func uuid(of id: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "" }
        return (CFUUIDCreateString(nil, uuid) as String?) ?? ""
    }
}
