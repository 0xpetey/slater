import CoreGraphics
import Testing
@testable import Slater

struct FrontWindowTests {
    /// A 1680 × 1050 main screen with a 1920 × 1080 screen to its right, bottoms aligned.
    private let screens: [(displayID: CGDirectDisplayID, frame: CGRect)] = [
        (1, CGRect(x: 0, y: 0, width: 1680, height: 1050)),
        (2, CGRect(x: 1680, y: 0, width: 1920, height: 1080)),
    ]

    @Test func windowBoundsAreFlippedIntoTheScreensPoints() throws {
        // 50 points below the main screen's top, in the window server's top-left coordinates.
        let selection = try #require(FrontWindow.selection(forWindowBounds: CGRect(x: 100, y: 50, width: 400, height: 300), screens: screens))
        #expect(selection.displayID == 1)
        #expect(selection.localRect == CGRect(x: 100, y: 700, width: 400, height: 300))
    }

    @Test func aWindowAcrossScreensGoesToTheOneHoldingMostOfItClipped() throws {
        let selection = try #require(FrontWindow.selection(forWindowBounds: CGRect(x: 1500, y: 100, width: 800, height: 400), screens: screens))
        #expect(selection.displayID == 2)
        // Flipped against the main screen's height, whichever screen holds the window; the
        // screens' bottoms are aligned, so that is also the local y.
        #expect(selection.localRect == CGRect(x: 0, y: 1050 - 500, width: 620, height: 400))
    }

    @Test func aWindowOffEveryScreenIsNothing() {
        #expect(FrontWindow.selection(forWindowBounds: CGRect(x: 5000, y: 0, width: 300, height: 300), screens: screens) == nil)
    }

    /// Live translation finds its window again by number on every frame.
    @Test @MainActor func theFrontWindowIsFoundAgainByItsNumber() throws {
        // A bare machine may have no ordinary window on screen at all.
        guard let window = FrontWindow.front() else { return }
        let located = try #require(FrontWindow.locate(window.id))
        #expect(located.bounds == window.bounds)
        #expect(located.isOnScreen)
        #expect(FrontWindow.locate(kCGNullWindowID) == nil)
    }
}
