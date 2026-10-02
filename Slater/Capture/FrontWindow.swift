import AppKit

/// The window the user is looking at, for a Shot taken without drawing a box: the frontmost
/// normal window of the active app, or of any app but Slater when Slater itself is active
/// (a Shot window can be key).
enum FrontWindow {
    /// The window's on-screen part, as a selection on the screen holding most of it.
    @MainActor
    static func selection() -> SelectionOverlayController.Selection? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else {
            return nil
        }
        let own = ProcessInfo.processInfo.processIdentifier
        let active = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Front to back. Layer 0 is ordinary windows; panels, menus and the Dock sit above it.
        let windows = list.compactMap { info -> (pid: pid_t, bounds: CGRect)? in
            guard info[kCGWindowLayer] as? Int == 0,
                  let pid = info[kCGWindowOwnerPID] as? pid_t, pid != own,
                  (info[kCGWindowAlpha] as? Double ?? 1) > 0,
                  let dictionary = info[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  bounds.width >= 50, bounds.height >= 50
            else { return nil }
            return (pid, bounds)
        }
        guard let window = windows.first(where: { $0.pid == active }) ?? windows.first else { return nil }
        let screens = NSScreen.screens.compactMap { screen in screen.displayID.map { (displayID: $0, frame: screen.frame) } }
        return selection(forWindowBounds: window.bounds, screens: screens)
    }

    /// `bounds` is in the window server's coordinates: origin at the main screen's top-left,
    /// y down. `screens` are AppKit frames, the first being the main screen, whose bottom-left
    /// is the global origin.
    static func selection(forWindowBounds bounds: CGRect, screens: [(displayID: CGDirectDisplayID, frame: CGRect)]) -> SelectionOverlayController.Selection? {
        guard let main = screens.first else { return nil }
        let global = CGRect(x: bounds.minX, y: main.frame.height - bounds.maxY, width: bounds.width, height: bounds.height)
        let onScreen = screens.map { ($0, $0.frame.intersection(global)) }.filter { !$0.1.isEmpty }
        guard let (screen, visible) = onScreen.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }) else { return nil }
        return SelectionOverlayController.Selection(
            displayID: screen.displayID,
            localRect: visible.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        )
    }
}
