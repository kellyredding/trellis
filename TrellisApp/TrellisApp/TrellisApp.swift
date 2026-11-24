import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory at runtime rather than LSUIElement, which would also hide
        // the app from Launch Services.
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            let model = AppModel()
            guard model.start() else {
                NSApp.terminate(nil)
                return
            }
            self.model = model
            statusItem = StatusItemController(model: model)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { model?.stop() }
    }
}

@main
@MainActor
enum TrellisMain {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
