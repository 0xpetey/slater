import CoreGraphics
import Testing
@testable import Slater

struct CoordinateMapperTests {
    @Test func retinaScreenFlipsAndScales() {
        let pixels = CoordinateMapper.pixelRect(
            forLocalRect: CGRect(x: 100, y: 100, width: 200, height: 50),
            screenSize: CGSize(width: 1440, height: 900),
            imageSize: CGSize(width: 2880, height: 1800)
        )
        #expect(pixels == CGRect(x: 200, y: 1500, width: 400, height: 100))
    }

    @Test func nonRetinaScreenOnlyFlips() {
        let pixels = CoordinateMapper.pixelRect(
            forLocalRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            screenSize: CGSize(width: 1920, height: 1080),
            imageSize: CGSize(width: 1920, height: 1080)
        )
        #expect(pixels == CGRect(x: 0, y: 1070, width: 10, height: 10))
    }

    @Test func fractionalPointsRoundOutwardSoNoTextIsClipped() {
        let pixels = CoordinateMapper.pixelRect(
            forLocalRect: CGRect(x: 10.3, y: 20.3, width: 5.2, height: 5.2),
            screenSize: CGSize(width: 100, height: 100),
            imageSize: CGSize(width: 100, height: 100)
        )
        #expect(pixels == CGRect(x: 10, y: 74, width: 6, height: 6))
    }

    @Test func selectionPastTheEdgeIsClampedToTheImage() {
        let pixels = CoordinateMapper.pixelRect(
            forLocalRect: CGRect(x: 1400, y: 880, width: 100, height: 100),
            screenSize: CGSize(width: 1440, height: 900),
            imageSize: CGSize(width: 2880, height: 1800)
        )
        #expect(pixels == CGRect(x: 2800, y: 0, width: 80, height: 40))
    }

    @Test func secondaryScreenOffsetsIntoGlobalSpace() {
        // A screen to the left of and below the main screen.
        let global = CoordinateMapper.globalRect(
            forLocalRect: CGRect(x: 10, y: 20, width: 30, height: 40),
            screenFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        )
        #expect(global == CGRect(x: -1910, y: -180, width: 30, height: 40))
    }
}
