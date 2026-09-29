import CoreGraphics
import Foundation
import Testing
@testable import Slater

@MainActor
private func makeShot(_ texts: [String]) -> Shot {
    let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
    let blocks = texts.enumerated().map { index, text in
        Block(lines: [Line(text: text, bounds: CGRect(x: 0, y: CGFloat(index) * 40, width: 100, height: 30))], source: .japanese)
    }
    return Shot(image: context.makeImage()!, screenRect: .zero, blocks: blocks)
}

@MainActor
struct ShotTests {
    @Test func copyTextSkipsPassthroughBlocks() {
        let shot = makeShot(["品番", "AB-1024", "備考"])
        shot.setTranslation("Item number", for: "品番", model: .fast)
        shot.setTranslation("Remarks", for: "備考", model: .fast)
        #expect(shot.translatedText == "Item number\nRemarks")
        #expect(shot.bilingualText == "品番\nItem number\n\n備考\nRemarks")
    }

    @Test func bilingualTextShowsJapaneseWhileTranslationIsPending() {
        let shot = makeShot(["品番", "備考"])
        shot.setTranslation("Item number", for: "品番", model: .fast)
        #expect(shot.bilingualText == "品番\nItem number\n\n備考")
    }

    @Test func eachModelsTranslationsAreKeptAndTheDisplayedOneIsUsed() {
        let shot = makeShot(["備考"])
        shot.setTranslation("Note", for: "備考", model: .fast)
        shot.setTranslation("Remarks", for: "備考", model: .accurate)
        #expect(shot.translations == [0: "Note"])
        shot.displayedModel = .accurate
        #expect(shot.translations == [0: "Remarks"])
        #expect(shot.translation(for: 0, model: .fast) == "Note")
    }
}

/// Uses the real on-device translator, so it needs a Japanese → English model installed.
@MainActor
struct TranslatorTests {
    @Test func translatesEachJapaneseBlockAndRepeatsOnlyOnce() async throws {
        let translator = Translator(source: Locale.Language(identifier: "ja"), target: Locale.Language(identifier: "en"))
        await translator.refresh()
        try #require(translator.hasInstalledModel, "Install a Japanese → English translation model to run this test")

        let shot = makeShot(["品番", "AB-1024", "品番", "仕様変更のため、再見積もりが必要です。"])
        await translator.translate(shot)

        #expect(shot.state == .translated)
        #expect(Set(shot.translations.keys) == [0, 2, 3])
        #expect(shot.translations[0] == shot.translations[2])
        for translation in shot.translations.values {
            #expect(!translation.isEmpty)
            #expect(!SourceScript.japanese.contains(translation))
        }
    }
}

@MainActor
struct SecondModelTests {
    @Test func translatingWithTheOtherModelKeepsBothSets() async throws {
        let translator = Translator(source: Locale.Language(identifier: "ja"), target: Locale.Language(identifier: "en"))
        await translator.refresh()
        try #require(translator.status(of: .fast) == .installed && translator.status(of: .accurate) == .installed,
                     "Install both translation models to run this test")

        let shot = makeShot(["仕様変更のため、再見積もりが必要です。", "AB-1024"])
        await translator.translate(shot, using: .fast)
        #expect(shot.state(for: .fast) == .translated)
        let fast = try #require(shot.translation(for: 0, model: .fast))

        await translator.translate(shot, using: .accurate)
        #expect(shot.state(for: .accurate) == .translated)
        #expect((shot.pendingTexts[.accurate] ?? []).isEmpty)
        let accurate = try #require(shot.translation(for: 0, model: .accurate))
        #expect(!accurate.isEmpty && !SourceScript.japanese.contains(accurate))
        #expect(shot.translation(for: 0, model: .fast) == fast)
        // The view decides what's shown; translating doesn't switch it.
        #expect(shot.displayedModel == .fast)
    }

    @Test func withoutReplacingNothingIsSentAgain() async throws {
        let translator = Translator(source: Locale.Language(identifier: "ja"), target: Locale.Language(identifier: "en"))
        await translator.refresh()
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
        let english = Locale.Language(identifier: "en")
        #expect(Translator.tidy("a note", source: "備考", target: english) == "Note")
        #expect(Translator.tidy("an item number", source: "品番", target: english) == "Item number")
        #expect(Translator.tidy("the person in charge", source: "担当者", target: english) == "Person in charge")
        #expect(Translator.tidy("quantity", source: "数量", target: english) == "Quantity")
    }

    @Test func sentencesAreLeftAlone() {
        let sentence = "a re-quote is required due to specification changes."
        #expect(Translator.tidy(sentence, source: "仕様変更のため、再見積もりが必要です。", target: Locale.Language(identifier: "en")) == sentence)
    }

    @Test func otherTargetsKeepTheirArticlesAndScripts() {
        // German keeps its article; only the capital is added. Japanese gets neither.
        #expect(Translator.tidy("die Anmerkung", source: "備考", target: Locale.Language(identifier: "de")) == "Die Anmerkung")
        #expect(Translator.tidy("備考", source: "Note", target: Locale.Language(identifier: "ja")) == "備考")
    }
}
