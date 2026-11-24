import AppKit
import ApplicationServices

/// The Accessibility grant. Checked silently; the system prompt appears only
/// from an explicit user action, since a prompt at launch would fire on every
/// rebuild whose signature lost the grant.
@MainActor
final class Accessibility: ObservableObject {
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private var timer: Timer?
    private var observer: NSObjectProtocol?

    func start() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        refresh()
    }

    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted {
            isTrusted = trusted
            Log.info("accessibility trusted: \(trusted)")
        }
        schedulePolling()
    }

    /// Shows the system prompt (which adds Trellis to the list) and opens the
    /// Accessibility pane.
    func requestFromUser() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSystemSettings()
        refresh()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Fast while untrusted so the blocked state clears as soon as the grant
    /// lands; slow while trusted, since a rebuild can revoke it silently.
    private func schedulePolling() {
        let interval: TimeInterval = isTrusted ? 30 : 2
        if let timer, timer.timeInterval == interval { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }
}
