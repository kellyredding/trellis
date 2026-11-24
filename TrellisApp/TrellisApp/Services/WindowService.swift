import AppKit
import ApplicationServices

/// Private but stable: the `CGWindowID` behind an AX window element, as
/// Rectangle, yabai and AeroSpace use it.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

struct AXWindow {
    let element: AXUIElement
    let pid: pid_t
    let info: WindowInfo
}

/// Reads and moves other apps' windows through the Accessibility API. Every
/// call blocks on the target app, so callers stay off the main thread.
final class WindowService: @unchecked Sendable {
    private static let acceptedSubroles: Set<String> = [
        "AXStandardWindow", "AXDialog", "AXFloatingWindow", "AXSystemDialog",
    ]
    private static let messagingTimeout: Float = 1.0

    private let screens: ScreenService

    init(screens: ScreenService) {
        self.screens = screens
        // Set on the system-wide element, the timeout covers every element,
        // including the window elements an app hands back (default ~6 s).
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), Self.messagingTimeout)
    }

    /// Every window of every regular app.
    func allWindows() -> [AXWindow] {
        let focusedID = focusedWindowID()
        let screenList = screens.screens
        var result: [AXWindow] = []
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isTerminated {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            guard let elements: [AXUIElement] = Self.attribute(appElement, kAXWindowsAttribute) else { continue }
            for element in elements {
                if let window = describe(element, app: app, focusedID: focusedID, screens: screenList) {
                    result.append(window)
                }
            }
        }
        return result
    }

    func focusedWindow() -> AXWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let element: AXUIElement = Self.attribute(appElement, kAXFocusedWindowAttribute),
              let id = Self.windowID(element)
        else { return nil }
        return describe(element, app: app, focusedID: id, screens: screens.screens)
    }

    /// The focused window when that is the target, else a full enumeration.
    func resolve(_ target: WindowTarget) -> Result<AXWindow, RequestError> {
        if target == .focused {
            guard let window = focusedWindow() else { return .failure(.notFound("no window is focused")) }
            return .success(window)
        }
        let all = allWindows()
        return TargetMatcher.match(target, in: all.map(\.info)).flatMap { info in
            guard let window = all.first(where: { $0.info.id == info.id }) else {
                return .failure(.notFound("window \(info.id) went away"))
            }
            return .success(window)
        }
    }

    /// Size, then position, then size again: an app that clamps a size to the
    /// screen it is on gets the second size once it has moved.
    @discardableResult
    func setFrame(_ window: AXWindow, _ frame: Rect) -> Result<WindowInfo, RequestError> {
        let appElement = AXUIElementCreateApplication(window.pid)
        let enhanced = "AXEnhancedUserInterface" as CFString
        let wasEnhanced: Bool = Self.attribute(appElement, enhanced as String) ?? false
        if wasEnhanced { AXUIElementSetAttributeValue(appElement, enhanced, kCFBooleanFalse) }
        defer {
            if wasEnhanced { AXUIElementSetAttributeValue(appElement, enhanced, kCFBooleanTrue) }
        }

        var size = CGSize(width: frame.w, height: frame.h)
        var origin = CGPoint(x: frame.x, y: frame.y)
        guard let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) else {
            return .failure(.internal("could not build AX values"))
        }
        AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue)
        let moved = AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, sizeValue)
        if moved == .apiDisabled { return .failure(.notPermitted) }
        if moved != .success {
            return .failure(.internal("the window refused to move (AX error \(moved.rawValue))"))
        }

        let after = Self.frame(of: window.element) ?? frame
        let info = window.info
        return .success(WindowInfo(
            id: info.id, app: info.app, bundleID: info.bundleID, pid: info.pid, title: info.title,
            frame: after,
            screen: ScreenNeighbor.screen(for: after, among: screens.screens)?.index,
            focused: info.focused, minimized: info.minimized
        ))
    }

    // MARK: - Reading

    private func focusedWindowID() -> Int? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let element: AXUIElement = Self.attribute(appElement, kAXFocusedWindowAttribute) else { return nil }
        return Self.windowID(element)
    }

    private func describe(
        _ element: AXUIElement, app: NSRunningApplication, focusedID: Int?, screens: [ScreenInfo]
    ) -> AXWindow? {
        guard let role: String = Self.attribute(element, kAXRoleAttribute), role == (kAXWindowRole as String),
              let id = Self.windowID(element),
              let frame = Self.frame(of: element)
        else { return nil }
        let subrole: String = Self.attribute(element, kAXSubroleAttribute) ?? ""
        guard Self.acceptedSubroles.contains(subrole) else { return nil }
        let info = WindowInfo(
            id: id,
            app: app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)",
            bundleID: app.bundleIdentifier,
            pid: Int(app.processIdentifier),
            title: Self.attribute(element, kAXTitleAttribute) ?? "",
            frame: frame,
            screen: ScreenNeighbor.screen(for: frame, among: screens)?.index,
            focused: id == focusedID,
            minimized: Self.attribute(element, kAXMinimizedAttribute) ?? false
        )
        return AXWindow(element: element, pid: app.processIdentifier, info: info)
    }

    private static func windowID(_ element: AXUIElement) -> Int? {
        var id: CGWindowID = 0
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return Int(id)
    }

    private static func frame(of element: AXUIElement) -> Rect? {
        guard let positionValue: AXValue = attribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = attribute(element, kAXSizeAttribute)
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue, .cgSize, &size)
        else { return nil }
        return Rect(x: Double(origin.x), y: Double(origin.y), w: Double(size.width), h: Double(size.height))
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else {
            return nil
        }
        if T.self == AXUIElement.self || T.self == AXValue.self {
            return (value as! T)
        }
        return value as? T
    }
}
