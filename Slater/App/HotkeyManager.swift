@preconcurrency import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// ⌥⇧4 echoes the system's ⇧⌘4 screenshot shortcut. The macOS 15+ ban on
    /// Option-only hotkeys applies to sandboxed apps only, and Slater is not sandboxed.
    static let takeShot = Self("takeShot", default: .init(.four, modifiers: [.option, .shift]))
    /// ⌥⇧3, next to it: a Shot of the front window, with no box to draw.
    static let takeWindowShot = Self("takeWindowShot", default: .init(.three, modifiers: [.option, .shift]))
    /// ⌥⇧5, next to Take Shot. Experimental live translation of the whole screen.
    static let toggleLiveTranslation = Self("toggleLiveTranslation", default: .init(.five, modifiers: [.option, .shift]))
    /// ⌥⇧6, next to that: holds the live screen, and its patches, so it can be read.
    static let freezeLiveTranslation = Self("freezeLiveTranslation", default: .init(.six, modifiers: [.option, .shift]))
    /// ⌥⇧7, the next key along: live translation of the front window only. ⌥⇧2 would sit
    /// next to the window Shot, but it types € on a US keyboard.
    static let toggleLiveWindowTranslation = Self("toggleLiveWindowTranslation", default: .init(.seven, modifiers: [.option, .shift]))
}

@MainActor
final class HotkeyManager {
    init(
        onTakeShot: @escaping @MainActor () -> Void,
        onTakeWindowShot: @escaping @MainActor () -> Void,
        onToggleLiveTranslation: @escaping @MainActor () -> Void,
        onToggleLiveWindowTranslation: @escaping @MainActor () -> Void,
        onFreezeLiveTranslation: @escaping @MainActor () -> Void
    ) {
        KeyboardShortcuts.onKeyDown(for: .takeShot) {
            MainActor.assumeIsolated { onTakeShot() }
        }
        KeyboardShortcuts.onKeyDown(for: .takeWindowShot) {
            MainActor.assumeIsolated { onTakeWindowShot() }
        }
        KeyboardShortcuts.onKeyDown(for: .toggleLiveTranslation) {
            MainActor.assumeIsolated { onToggleLiveTranslation() }
        }
        KeyboardShortcuts.onKeyDown(for: .toggleLiveWindowTranslation) {
            MainActor.assumeIsolated { onToggleLiveWindowTranslation() }
        }
        KeyboardShortcuts.onKeyDown(for: .freezeLiveTranslation) {
            MainActor.assumeIsolated { onFreezeLiveTranslation() }
        }
    }

    /// The live translation hotkeys are registered only while the feature is on, so that the
    /// keys type as usual otherwise. The handlers stay; a disabled name just has no hotkey.
    func setLiveTranslationEnabled(_ enabled: Bool) {
        let names: [KeyboardShortcuts.Name] = [.toggleLiveTranslation, .toggleLiveWindowTranslation, .freezeLiveTranslation]
        if enabled {
            KeyboardShortcuts.enable(names)
        } else {
            KeyboardShortcuts.disable(names)
        }
    }
}
