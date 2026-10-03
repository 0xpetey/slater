import AppKit
import Testing
@testable import Slater

struct ScreenCapturerTests {
    /// The menu bar item is a window too, at the status bar level, and mustn't count as one of
    /// Slater's windows on screen; any other visible window does.
    @Test @MainActor func windowsOnScreenIgnoreTheMenuBarItem() throws {
        let controller = StatusItemController(appState: AppState())
        let statusBarWindow = try #require(NSApp.windows.first { $0.level == .statusBar && $0.isVisible })
        #expect(statusBarWindow.level == .statusBar)
        let window = NSWindow(contentRect: CGRect(x: -10000, y: -10000, width: 10, height: 10), styleMask: .borderless, backing: .buffered, defer: false)
        // A window releases itself on close unless told not to, which with ARC's own release crashes.
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        #expect(ScreenCapturer.hasWindowsOnScreen)
        window.close()
        _ = controller
    }

    /// With nothing of Slater's on screen there is nothing to exclude, so a capture doesn't wait
    /// for ScreenCaptureKit to list Slater; waiting used to cost a Shot of the front window a
    /// second (ten retries of 50 ms plus a fetch each). Needs the test host's Screen Recording
    /// permission, which it shares with the app's.
    @Test @MainActor func captureWithoutOwnWindowsDoesNotWait() async throws {
        let started = ContinuousClock.now
        let captures = try await ScreenCapturer.captureAllDisplays()
        let elapsed = ContinuousClock.now - started
        #expect(!captures.isEmpty)
        #expect(elapsed < .milliseconds(900), "captured in \(elapsed)")
    }
}
