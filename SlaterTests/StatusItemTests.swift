import AppKit
import Testing
@testable import Slater

struct StatusItemTests {
    /// The tracking area's owner gets `mouseEntered:`. A Swift method named `mouseEntered(with:)`
    /// on a non-responder silently gets the selector `mouseEnteredWith:` unless spelled out.
    @Test func trackingAreaSelectorsMatchWhatAppKitSends() {
        #expect(NSStringFromSelector(#selector(StatusItemController.mouseEntered(with:))) == "mouseEntered:")
        #expect(NSStringFromSelector(#selector(StatusItemController.mouseExited(with:))) == "mouseExited:")
    }
}
