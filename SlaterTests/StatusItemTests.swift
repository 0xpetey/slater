import AppKit
import KeyboardShortcuts
import Testing
@testable import Slater

struct StatusItemTests {
    /// The tracking area's owner gets `mouseEntered:`. A Swift method named `mouseEntered(with:)`
    /// on a non-responder silently gets the selector `mouseEnteredWith:` unless spelled out.
    @Test func trackingAreaSelectorsMatchWhatAppKitSends() {
        #expect(NSStringFromSelector(#selector(StatusItemController.mouseEntered(with:))) == "mouseEntered:")
        #expect(NSStringFromSelector(#selector(StatusItemController.mouseExited(with:))) == "mouseExited:")
    }

    /// Live translation is experimental: its items appear once it's opted into, in Settings.
    @Test @MainActor func liveTranslationItemsNeedOptingIn() {
        let appState = AppState()
        let wasEnabled = appState.live.isEnabled
        defer { appState.live.isEnabled = wasEnabled }
        for enabled in [false, true] {
            appState.live.isEnabled = enabled
            let menu = NSMenu()
            StatusItemController(appState: appState).menuNeedsUpdate(menu)
            #expect((menu.item(withTitle: "Start Live Translation") != nil) == enabled)
            #expect((menu.item(withTitle: "Start Live Translation of Front Window") != nil) == enabled)
            #expect(menu.item(withTitle: "Take Shot") != nil)
        }
    }

    /// Each item for a rebindable hotkey shows that hotkey as it is bound now, which is the
    /// default (⌥⇧4, ⌥⇧3, ⌥⇧5, ⌥⇧7) unless this Mac's user has changed it in Settings. Live
    /// translation is opted into for the test, and put back.
    @Test @MainActor func menuItemsShowTheirHotkeys() throws {
        let appState = AppState()
        let wasEnabled = appState.live.isEnabled
        appState.live.isEnabled = true
        defer { appState.live.isEnabled = wasEnabled }
        let menu = NSMenu()
        StatusItemController(appState: appState).menuNeedsUpdate(menu)
        let bound: [(title: String, hotkey: KeyboardShortcuts.Name)] = [
            ("Take Shot", .takeShot),
            ("Take Shot of Front Window", .takeWindowShot),
            ("Start Live Translation", .toggleLiveTranslation),
            ("Start Live Translation of Front Window", .toggleLiveWindowTranslation),
        ]
        for (title, hotkey) in bound {
            let item = try #require(menu.item(withTitle: title), "\(title)")
            guard let shortcut = hotkey.shortcut else {
                #expect(item.keyEquivalent.isEmpty, "\(title) is unbound")
                continue
            }
            #expect(item.keyEquivalentModifierMask == shortcut.modifiers, "\(title) shows \(shortcut)")
            // The shortcut's description ends with its key, capitalized: "⌥⇧4", "⌘T".
            if let key = item.keyEquivalent.first, item.keyEquivalent.count == 1, key.isLetter || key.isNumber {
                #expect(shortcut.description.hasSuffix(item.keyEquivalent.uppercased()), "\(title) shows \(shortcut)")
            } else {
                #expect(!item.keyEquivalent.isEmpty, "\(title) shows \(shortcut)")
            }
        }
    }

    /// Settings… puts a Settings window on screen. The status menu used to send SwiftUI the
    /// `showSettingsWindow:` selector, which macOS 26 still accepts but answers with no window,
    /// so this opens Settings the way the menu does and waits for the window.
    @Test @MainActor func settingsItemOpensTheSettingsWindow() async throws {
        func settingsWindow() -> NSWindow? {
            NSApp.windows.first { $0.isVisible && $0.title == "Slater Settings" }
        }
        try #require(settingsWindow() == nil, "no Settings window is open before the test")
        let controller = StatusItemController(appState: AppState())
        controller.openSettings()
        // SwiftUI makes the scene's window over the next few turns of the run loop.
        let deadline = ContinuousClock.now + .seconds(3)
        var window = settingsWindow()
        while window == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
            window = settingsWindow()
        }
        let opened = try #require(window, "a Settings window is on screen within 3 s")
        opened.close()
    }
}
