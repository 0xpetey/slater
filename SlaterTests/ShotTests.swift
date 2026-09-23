import CoreGraphics
import Testing
@testable import Slater

@MainActor
private func makeShot(_ texts: [String]) -> Shot {
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    let blocks = texts.enumerated().map { index, text in
        Block(lines: [Line(text: text, bounds: CGRect(x: 0, y: CGFloat(index) * 40, width: 100, height: 30))])
    }
    return Shot(image: context.makeImage()!, screenRect: .zero, blocks: blocks)
}

@MainActor
struct ShotTests {
    @Test func copyTextSkipsPassthroughBlocks() {
        let shot = makeShot(["品番", "AB-1024", "備考"])
        shot.translations = [0: "Item number", 2: "Remarks"]
        #expect(shot.englishText == "Item number\nRemarks")
        #expect(shot.bilingualText == "品番\nItem number\n\n備考\nRemarks")
    }

    @Test func bilingualTextShowsJapaneseWhileTranslationIsPending() {
        let shot = makeShot(["品番", "備考"])
        shot.translations = [0: "Item number"]
        #expect(shot.bilingualText == "品番\nItem number\n\n備考")
    }
}

/// Uses the real on-device translator, so it needs the Japanese language pack installed.
@MainActor
struct TranslatorTests {
    @Test func translatesEachJapaneseBlockAndRepeatsOnlyOnce() async throws {
        let translator = Translator()
        await translator.refreshLanguagePack()
        try #require(translator.languagePack == .installed, "Install the Japanese language pack to run this test")

        let shot = makeShot(["品番", "AB-1024", "品番", "仕様変更のため、再見積もりが必要です。"])
        await translator.translate(shot)

        #expect(shot.state == .translated)
        #expect(Set(shot.translations.keys) == [0, 2, 3])
        #expect(shot.translations[0] == shot.translations[2])
        for translation in shot.translations.values {
            #expect(!translation.isEmpty)
            #expect(!Block.containsJapanese(translation))
        }
    }
}
