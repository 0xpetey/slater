@preconcurrency import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// ⌥⇧4 echoes the system's ⇧⌘4 screenshot shortcut. The macOS 15+ ban on
    /// Option-only hotkeys applies to sandboxed apps only, and Slater is not sandboxed.
    static let takeShot = Self("takeShot", default: .init(.four, modifiers: [.option, .shift]))
}

@MainActor
final class HotkeyManager {
    init(onTakeShot: @escaping @MainActor () -> Void) {
        KeyboardShortcuts.onKeyDown(for: .takeShot) {
            MainActor.assumeIsolated { onTakeShot() }
        }
    }
}
