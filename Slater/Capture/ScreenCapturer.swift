import AppKit
import os
import ScreenCaptureKit

private let logger = Logger(subsystem: "app.slater", category: "capture")

/// One display's pixels at the moment the hotkey was pressed.
struct DisplayCapture: Sendable {
    let displayID: CGDirectDisplayID
    /// The screen's frame in global AppKit points.
    let frame: CGRect
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

    /// The display list, with Slater among the applications if ScreenCaptureKit lists it: it
    /// does so only while Slater has a window on screen, and a window just ordered front can
    /// take a moment to show up, so this retries briefly before giving up.
    static func contentListingSlater() async throws -> (content: SCShareableContent, slater: [SCRunningApplication]) {
        var content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var slater = content.applications.filter(isSlater)
        var attempts = 0
        while slater.isEmpty, attempts < 10 {
            attempts += 1
            try await Task.sleep(for: .milliseconds(50))
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            slater = content.applications.filter(isSlater)
        }
        return (content, slater)
    }

    private static func isSlater(_ application: SCRunningApplication) -> Bool {
        application.processID == ProcessInfo.processInfo.processIdentifier
    }

    /// Whether a window of Slater's other than the menu bar item is on screen: the selection
    /// overlay, a Shot, onboarding, Settings or a notice, which a capture has to exclude.
    static var hasWindowsOnScreen: Bool {
        NSApp.windows.contains { $0.isVisible && $0.level != .statusBar }
    }

    /// Captures every display at native resolution. Slater's own windows (the selection
    /// overlay, open Shots, onboarding) are excluded, so a new Shot always sees the content
    /// underneath. ScreenCaptureKit lists Slater only while it has a window on screen, and one
    /// just ordered front can take a moment to show up, so while Slater has windows the list is
    /// refetched until it's in it. With none, as for a Shot of the front window, there is nothing
    /// to exclude and nothing to wait for; waiting anyway used to cost such a Shot a second.
    static func captureAllDisplays() async throws -> [DisplayCapture] {
        let content: SCShareableContent
        let mustListSlater = hasWindowsOnScreen
        if let cached = Self.content, !mustListSlater || !cached.applications.filter(isSlater).isEmpty {
            content = cached
        } else if mustListSlater {
            // The cached list may predate Slater's first window; fetch again rather than capture it.
            content = try await contentListingSlater().content
            if content.applications.filter(isSlater).isEmpty {
                logger.error("Slater isn't listed by ScreenCaptureKit; the capture may include its own windows")
            }
        } else {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        }
        let slater = content.applications.filter(isSlater)
        // Windows come and go, which is harmless since the filter is by application, but keep
        // the list fresh for the next Shot anyway.
        defer { warmUp() }

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
            captures.append(DisplayCapture(displayID: display.displayID, frame: screen.frame, image: image))
        }
        return captures
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
