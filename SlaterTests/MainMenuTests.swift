import AppKit
import Testing
@testable import Slater

/// The main menu is never shown by a menu bar app, but its key equivalents work in Slater's
/// windows, so the menu is built as the app builds it and checked for the ones that matter there.
struct MainMenuTests {
    @Test @MainActor func keyEquivalentsForSlatersWindows() throws {
        let target = NSObject()
        let main = MainMenu.make(settingsAction: #selector(NSApplication.terminate(_:)), target: target)
        let items = main.items.compactMap(\.submenu).flatMap(\.items)
        func item(_ key: String) -> NSMenuItem? {
            items.first { $0.keyEquivalent == key && $0.keyEquivalentModifierMask == .command }
        }
        #expect(item(",")?.title == "Settings…")
        #expect(item(",")?.target === target)
        #expect(item("q")?.action == #selector(NSApplication.terminate(_:)))
        #expect(item("w")?.action == #selector(NSWindow.performClose(_:)))
        #expect(item("c")?.action == #selector(NSText.copy(_:)))
        #expect(item("v")?.action == #selector(NSText.paste(_:)))
        #expect(item("a")?.action == #selector(NSText.selectAll(_:)))
        #expect(item("z")?.title == "Undo")
        #expect(NSApp.windowsMenu?.title == "Window")
    }

    /// The app installs its main menu the first time one of its windows becomes key, with
    /// Settings… wired to the app delegate. The notification is posted here by hand, since the
    /// test host's windows don't become key while it isn't the active app.
    @Test @MainActor func mainMenuIsInstalledOnceAWindowIsKey() throws {
        let delegate = try #require(NSApp.delegate as? AppDelegate)
        NSApp.mainMenu = nil
        delegate.installMainMenuOnceAWindowIsKey()
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: nil)
        let settings = try #require(NSApp.mainMenu?.items.first?.submenu?.items.first { $0.keyEquivalent == "," })
        #expect(settings.target === delegate)
    }
}
