import AppKit
import SwiftUI

/// Not app-modal: an accessory app has no main window to protect, and under
/// `runModal` Conduit's pop-up menus would not open.
@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: PreferencesWindowController?
    private var escapeMonitor: Any?

    static func show(model: AppModel) {
        if shared == nil { shared = PreferencesWindowController(model: model) }
        guard let controller = shared, let window = controller.window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        controller.watchForEscape()
    }

    private init(model: AppModel) {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.backgroundColor = .windowBackgroundColor
        window.title = "Settings"
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// NSHostingView swallows Escape before the responder chain sees it.
    private func watchForEscape() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true, event.keyCode == 53 else { return event }
            self.dismiss()
            return nil
        }
    }

    private func dismiss() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
    }
}
