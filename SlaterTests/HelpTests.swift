import AppKit
import Testing
@testable import Slater

struct HelpTests {
    /// Back and Next stop at the first and last pages rather than wrapping round.
    @Test @MainActor func pagerStopsAtTheEnds() {
        let pager = HelpPager()
        #expect(pager.isFirst)
        pager.back()
        #expect(pager.page == .welcome)
        pager.next()
        #expect(pager.page == .takeShot)
        for _ in HelpPage.allCases { pager.next() }
        #expect(pager.page == .settings)
        #expect(pager.isLast)
    }

    /// Slater Help lives in Settings, not in the lizard's menu. Opened the way the button in
    /// Settings does, it puts the Help window on screen.
    @Test @MainActor func helpOpensFromSettingsNotTheMenu() throws {
        func helpWindow() -> NSWindow? {
            NSApp.windows.first { $0.isVisible && $0.title == "Slater Help" }
        }
        try #require(helpWindow() == nil, "no Help window is open before the test")
        let appState = AppState()
        let menu = NSMenu()
        StatusItemController(appState: appState).menuNeedsUpdate(menu)
        #expect(menu.item(withTitle: "Slater Help") == nil)
        appState.showHelp()
        let opened = try #require(helpWindow(), "a Help window is on screen")
        opened.close()
    }
}
