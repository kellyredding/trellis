import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Reports the real status afterwards rather than what was asked for.
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.error("launch at login \(enabled ? "on" : "off") failed: \(error.localizedDescription)")
        }
        return isEnabled
    }
}
