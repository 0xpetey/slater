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
        shot.setTranslation("Item number", for: "品番")
        shot.setTranslation("Remarks", for: "備考")
        #expect(shot.englishText == "Item number\nRemarks")
        #expect(shot.bilingualText == "品番\nItem number\n\n備考\nRemarks")
    }

    @Test func bilingualTextShowsJapaneseWhileTranslationIsPending() {
        let shot = makeShot(["品番", "備考"])
        shot.setTranslation("Item number", for: "品番")
        #expect(shot.bilingualText == "品番\nItem number\n\n備考")
    }
}

/// Uses the real on-device translator, so it needs a Japanese → English model installed.
@MainActor
struct TranslatorTests {
    @Test func translatesEachJapaneseBlockAndRepeatsOnlyOnce() async throws {
        let translator = Translator()
        await translator.refreshModels()
        try #require(translator.hasInstalledModel, "Install a Japanese → English translation model to run this test")

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

@MainActor
struct RerunWithAccurateTests {
    @Test func rerunReplacesFastTranslationsAndRecordsTheModel() async throws {
        let translator = Translator()
        await translator.refreshModels()
        try #require(translator.status(of: .fast) == .installed && translator.status(of: .accurate) == .installed,
                     "Install both translation models to run this test")

        let shot = makeShot(["仕様変更のため、再見積もりが必要です。", "AB-1024"])
        await translator.translate(shot, using: .fast)
        #expect(shot.model == .fast)
        #expect(shot.state == .translated)
        let fast = try #require(shot.translations[0])

        await translator.translate(shot, using: .accurate, replacingExisting: true)
        #expect(shot.model == .accurate)
        #expect(shot.state == .translated)
        #expect(shot.pendingTexts.isEmpty)
        let accurate = try #require(shot.translations[0])
        #expect(!accurate.isEmpty && !Block.containsJapanese(accurate))
        _ = fast
    }

    @Test func withoutReplacingNothingIsSentAgain() async throws {
        let translator = Translator()
        await translator.refreshModels()
        try #require(translator.hasInstalledModel, "Install a Japanese → English translation model to run this test")

        let shot = makeShot(["品番"])
        await translator.translate(shot)
        let first = shot.translations[0]
        await translator.translate(shot)
        #expect(shot.translations[0] == first)
        #expect(shot.state == .translated)
    }
}

struct TranslationTidyingTests {
    @Test func shortLabelsLoseTheirArticle() {
        #expect(Translator.tidy("a note", source: "備考") == "Note")
        #expect(Translator.tidy("an item number", source: "品番") == "Item number")
        #expect(Translator.tidy("the person in charge", source: "担当者") == "Person in charge")
        #expect(Translator.tidy("quantity", source: "数量") == "Quantity")
    }

    @Test func sentencesAreLeftAlone() {
        let sentence = "a re-quote is required due to specification changes."
        #expect(Translator.tidy(sentence, source: "仕様変更のため、再見積もりが必要です。") == sentence)
    }
}
