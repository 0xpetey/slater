import AppKit
import Testing
@testable import Slater

struct FitTextTests {
    @Test func shortTranslationIsCappedByTheOriginalLineHeight() {
        let fit = FitText.fit("Remarks", in: CGSize(width: 300, height: 100), lineHeight: 15)
        #expect(fit.fontSize == 12)
        #expect(!fit.isTruncated)
    }

    @Test func longerTranslationShrinksToFit() {
        let fit = FitText.fit("Due to changes in specifications, a re-quote is required.", in: CGSize(width: 140, height: 44), lineHeight: 15)
        #expect(fit.fontSize >= FitText.minimumSize && fit.fontSize < 12)
        #expect(!fit.isTruncated)
    }

    @Test func translationThatCannotFitAtTheMinimumIsTruncated() {
        let fit = FitText.fit("Due to changes in specifications, a re-quote is required.", in: CGSize(width: 60, height: 14), lineHeight: 13)
        #expect(fit == .init(fontSize: FitText.minimumSize, isTruncated: true, lineLimit: 1))
    }
}

struct ColorSamplerTests {
    @Test func samplesTheBackgroundAroundText() throws {
        // Dark text on a light yellow cell, with a dark gridline touching one edge of the ring.
        let context = try #require(CGContext(
            data: nil, width: 100, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 40))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 20, y: 12, width: 60, height: 16))  // the "text"
        context.fill(CGRect(x: 0, y: 8, width: 100, height: 1))    // a gridline
        let image = try #require(context.makeImage())

        let color = ColorSampler(image: image).background(around: CGRect(x: 20, y: 12, width: 60, height: 16))
        #expect(color == .init(red: 1, green: 1, blue: 0.8))
        #expect(color.luminance > 0.5)
    }

    @Test func clearWidthStopsAtTheNextTextOrGridline() throws {
        // Text at x 10–30, then empty cell until a light gridline at x 70.
        let context = try #require(CGContext(
            data: nil, width: 100, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 20))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 10, y: 5, width: 20, height: 10))
        context.setFillColor(CGColor(gray: 0.75, alpha: 1))
        context.fill(CGRect(x: 70, y: 0, width: 1, height: 20))
        let sampler = ColorSampler(image: try #require(context.makeImage()))

        let text = CGRect(x: 10, y: 5, width: 20, height: 10)
        #expect(sampler.clearWidth(rightOf: text, background: .init(red: 1, green: 1, blue: 1)) == 70 - 30 - ColorSampler.margin)
    }
}

struct ShotLayoutTests {
    private let white = ColorSampler.RGB(red: 1, green: 1, blue: 1)

    private func block(_ text: String, _ bounds: CGRect) -> Block {
        Block(lines: [Line(text: text, bounds: bounds)])
    }

    @Test func patchCoversTheBlockInWindowPoints() {
        let patches = ShotLayout.patches(
            for: [block("品番", CGRect(x: 20, y: 40, width: 100, height: 30))],
            indices: [0], pointsPerPixel: 0.5, windowSize: CGSize(width: 200, height: 100),
            background: { _ in white }
        )
        #expect(patches.map(\.frame) == [CGRect(x: 8.5, y: 18.5, width: 53, height: 18)])
        #expect(patches.map(\.lineHeight) == [15])
    }

    @Test func tinyTextGetsOneReadableLineAndStaysInsideTheWindow() throws {
        let patch = try #require(ShotLayout.patches(
            for: [block("保存", CGRect(x: 0, y: 0, width: 40, height: 8))],
            indices: [0], pointsPerPixel: 1, windowSize: CGSize(width: 100, height: 30),
            background: { _ in white }
        ).first)
        #expect(patch.frame.minY == 0)
        #expect(patch.frame.height >= 11)
    }

    @Test func patchExtendsIntoEmptySpaceToTheRight() {
        let patches = ShotLayout.patches(
            for: [block("品番", CGRect(x: 20, y: 40, width: 100, height: 30))],
            indices: [0], pointsPerPixel: 0.5, windowSize: CGSize(width: 200, height: 100),
            background: { _ in white }, clearWidth: { _, _ in 60 }
        )
        #expect(patches.map(\.frame.width) == [83])
    }

    @Test func onlyJapaneseBlocksGetPatches() {
        let patches = ShotLayout.patches(
            for: [block("品番", CGRect(x: 0, y: 0, width: 10, height: 10)), block("AB-1024", CGRect(x: 0, y: 20, width: 10, height: 10))],
            indices: [0], pointsPerPixel: 1, windowSize: CGSize(width: 100, height: 100),
            background: { _ in white }
        )
        #expect(patches.map(\.index) == [0])
    }
}
