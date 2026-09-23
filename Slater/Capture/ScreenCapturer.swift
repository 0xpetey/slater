import AppKit
import ScreenCaptureKit

/// One display's pixels at the moment the hotkey was pressed.
struct DisplayCapture {
    let screen: NSScreen
    let image: CGImage
}

@MainActor
enum ScreenCapturer {
    /// Captures every display at native resolution. Slater's own windows (open Shots,
    /// menus, onboarding) are excluded, so a new Shot always sees the content underneath.
    static func captureAllDisplays() async throws -> [DisplayCapture] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let slater = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }

        var captures: [DisplayCapture] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: slater, exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
            configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
            configuration.captureResolution = .best
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            captures.append(DisplayCapture(screen: screen, image: image))
        }
        return captures
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
