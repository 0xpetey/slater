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

    /// Captures every display at native resolution. Slater's own windows (open Shots, menus,
    /// onboarding) are excluded, so a new Shot always sees the content underneath.
    static func captureAllDisplays() async throws -> [DisplayCapture] {
        let content: SCShareableContent
        let slater: [SCRunningApplication]
        if let cached = Self.content, !cached.applications.filter(isSlater).isEmpty {
            content = cached
            slater = cached.applications.filter(isSlater)
        } else {
            // The cached list may predate Slater's first window; the selection overlay is up
            // now, so fetch again rather than capture it.
            (content, slater) = try await contentListingSlater()
        }
        // Windows come and go, which is harmless since the filter is by application, but keep
        // the list fresh for the next Shot anyway.
        defer { warmUp() }
        if slater.isEmpty {
            logger.error("Slater isn't listed by ScreenCaptureKit; the capture may include the selection overlay")
        }

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
