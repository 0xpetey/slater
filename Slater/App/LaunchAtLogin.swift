import os
import ServiceManagement

private let logger = Logger(subsystem: "app.slater", category: "setup")

/// Opens Slater when the user logs in, so the hotkey always works.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                logger.error("Couldn't change launch at login: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
