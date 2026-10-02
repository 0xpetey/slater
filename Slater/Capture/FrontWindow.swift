import AppKit

/// The window the user is looking at, for a Shot or live translation without drawing a box:
/// the frontmost normal window of the active app, or of any app but Slater when Slater itself
/// is active (a Shot window can be key).
enum FrontWindow {
    struct Window: Equatable {
        let id: CGWindowID
        /// In the window server's coordinates: origin at the main screen's top-left, y down.
        let bounds: CGRect
    }

    @MainActor
    static func front() -> Window? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] else {
            return nil
        }
        let own = ProcessInfo.processInfo.processIdentifier
        let active = NSWorkspace.shared.frontmostApplication?.processIdentifier
        // Front to back. Layer 0 is ordinary windows; panels, menus and the Dock sit above it.
        let windows = list.compactMap { info -> (pid: pid_t, window: Window)? in
            guard info[kCGWindowLayer] as? Int == 0,
                  let pid = info[kCGWindowOwnerPID] as? pid_t, pid != own,
                  let number = info[kCGWindowNumber] as? Int,
                  (info[kCGWindowAlpha] as? Double ?? 1) > 0,
                  let bounds = bounds(of: info),
                  bounds.width >= 50, bounds.height >= 50
            else { return nil }
            return (pid, Window(id: CGWindowID(number), bounds: bounds))
        }
        return (windows.first(where: { $0.pid == active }) ?? windows.first)?.window
    }

    /// The front window's on-screen part, as a selection on the screen holding most of it.
    @MainActor
    static func selection() -> SelectionOverlayController.Selection? {
        front().flatMap { selection(forWindowBounds: $0.bounds, screens: screens) }
    }

    /// Where a window is now: nil once it has closed; off screen while it's minimized, hidden
    /// or on another Space.
    static func locate(_ id: CGWindowID) -> (bounds: CGRect, isOnScreen: Bool)? {
        // The array holds the window numbers themselves as its elements, not CFNumbers; given
        // numbers, the API returns nothing.
        var element = UnsafeRawPointer(bitPattern: UInt(id))
        guard let ids = CFArrayCreate(nil, &element, 1, nil),
              let info = (CGWindowListCreateDescriptionFromArray(ids) as? [[CFString: Any]])?.first,
              let bounds = bounds(of: info)
        else { return nil }
        return (bounds, info[kCGWindowIsOnscreen] as? Bool ?? false)
    }

    /// What other apps have over a window: their on-screen windows above it, in the window
    /// server's coordinates. Slater's own overlay covers the whole screen and doesn't count.
    static func occluders(above id: CGWindowID) -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenAboveWindow, .excludeDesktopElements], id) as? [[CFString: Any]] else {
            return []
        }
        let own = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard info[kCGWindowOwnerPID] as? pid_t != own,
                  (info[kCGWindowAlpha] as? Double ?? 1) > 0
            else { return nil }
            return bounds(of: info)
        }
    }

    private static func bounds(of info: [CFString: Any]) -> CGRect? {
        guard let dictionary = info[kCGWindowBounds] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }

    /// AppKit frames, the first being the main screen, whose bottom-left is the global origin.
    @MainActor
    static var screens: [(displayID: CGDirectDisplayID, frame: CGRect)] {
        NSScreen.screens.compactMap { screen in screen.displayID.map { (displayID: $0, frame: screen.frame) } }
    }

    /// `bounds` is in the window server's coordinates: origin at the main screen's top-left,
    /// y down. `screens` are AppKit frames, the first being the main screen, whose bottom-left
    /// is the global origin.
    static func selection(forWindowBounds bounds: CGRect, screens: [(displayID: CGDirectDisplayID, frame: CGRect)]) -> SelectionOverlayController.Selection? {
        guard let main = screens.first else { return nil }
        let global = CoordinateMapper.flippedGlobalRect(bounds, mainScreenHeight: main.frame.height)
        let onScreen = screens.map { ($0, $0.frame.intersection(global)) }.filter { !$0.1.isEmpty }
        guard let (screen, visible) = onScreen.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height }) else { return nil }
        return SelectionOverlayController.Selection(
            displayID: screen.displayID,
            localRect: visible.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        )
    }
}
