import AppKit
import SwiftUI

/// The selected tab, held outside the view so the menu can open a given tab.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selected: SettingsTab = .general
}

/// Not app-modal: an accessory app has no main window to protect, and under
/// `runModal` Conduit's pop-up menus would not open.
@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: PreferencesWindowController?
    private var escapeMonitor: Any?
    private let model: AppModel
    private let navigation: SettingsNavigation
    private var top: CGFloat?

    static func show(model: AppModel, tab: SettingsTab? = nil) {
        if shared == nil { shared = PreferencesWindowController(model: model) }
        guard let controller = shared, let window = controller.window else { return }
        if let tab { controller.navigation.selected = tab }
        window.center()
        controller.top = window.frame.maxY
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.watchForEscape()
    }

    private init(model: AppModel) {
        let navigation = SettingsNavigation()
        let hosting = NSHostingController(rootView: SettingsView(model: model, navigation: navigation))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.backgroundColor = .windowBackgroundColor
        window.title = "Settings"
        self.model = model
        self.navigation = navigation
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// NSHostingView swallows Escape before the responder chain sees it. While
    /// the leader recorder is armed, Escape is its cancel key instead.
    private func watchForEscape() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true, event.keyCode == 53,
                  !self.model.isCapturingLeader
            else { return event }
            self.dismiss()
            return nil
        }
    }

    private func dismiss() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        window?.orderOut(nil)
    }

    func windowDidMove(_ notification: Notification) {
        top = window?.frame.maxY
    }

    /// Each tab sizes the window to its content, and AppKit keeps the bottom
    /// edge; keep the title bar in place instead, and the window on screen.
    func windowDidResize(_ notification: Notification) {
        guard let window, let top, let visible = window.screen?.visibleFrame else { return }
        let y = max(visible.minY, min(top, visible.maxY) - window.frame.height)
        guard y != window.frame.minY else { return }
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: y))
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
    }
}
