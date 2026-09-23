import AppKit
import ScreenCaptureKit

/// One display's pixels at the moment the hotkey was pressed.
struct DisplayCapture {
    let screen: NSScreen
    let image: CGImage
}

@MainActor
enum ScreenCapturer {
    /// The display list, fetched ahead of time: it costs 20–30 ms, which would otherwise be
    /// paid between the hotkey press and the frozen screen appearing.
    private static var content: SCShareableContent?

    /// Fetches the display list, and makes one throwaway capture, because the first capture in
    /// a process costs about 70 ms more than the rest. Called at launch, after each Shot, and
    /// when displays change.
    static func warmUp() {
        Task {
            content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
        Task {
            _ = try? await SCScreenshotManager.captureImage(in: CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    /// Captures every display at native resolution. Slater's own windows (open Shots, menus,
    /// onboarding) are excluded, so a new Shot always sees the content underneath.
    static func captureAllDisplays() async throws -> [DisplayCapture] {
        let content: SCShareableContent
        if let cached = Self.content {
            content = cached
        } else {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
        // Windows come and go, which is harmless since the filter is by application, but keep
        // the list fresh for the next Shot anyway.
        defer { warmUp() }
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
