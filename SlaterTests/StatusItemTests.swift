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

    /// Each item for a rebindable hotkey shows that hotkey as it is bound now, which is the
    /// default (⌥⇧4, ⌥⇧3, ⌥⇧5, ⌥⇧7) unless this Mac's user has changed it in Settings.
    @Test @MainActor func menuItemsShowTheirHotkeys() throws {
        let menu = NSMenu()
        StatusItemController(appState: AppState()).menuNeedsUpdate(menu)
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
}
