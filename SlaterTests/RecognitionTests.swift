import AppKit
import Testing
@testable import Slater

private final class FixtureBundle {}

private func fixture(_ name: String) throws -> CGImage {
    let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: "png"))
    let image = try #require(NSImage(contentsOf: url))
    return try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
}

/// Read and group a fixture, as the app does.
private func blocks(_ name: String, pixelsPerPoint: CGFloat = 2) async throws -> [Block] {
    let image = try fixture(name)
    let lines = try await TextReader.read(image, pixelsPerPoint: pixelsPerPoint)
    return BlockGrouper.group(lines, hasRule: RuleDetector(image: image).hasHorizontalRule)
}

/// End-to-end OCR on images rendered by scripts/make-fixtures.swift.
struct RecognitionTests {
    @Test func paragraphWrappedMidSentenceIsOneBlock() async throws {
        let texts = try await blocks("paragraph").map(\.text)
        #expect(texts == ["来週の会議は、仕様変更の影響を確認するために延期されました。", "資料は金曜日までに共有してください。"])
    }

    @Test func cleanTextIsNotMarkedLowConfidence() async throws {
        #expect(try await blocks("paragraph").allSatisfy { !$0.isLowConfidence })
    }

    @Test func spreadsheetCellsStaySeparate() async throws {
        let result = try await blocks("table")
        let japanese = Set(result.filter { $0.kind == .japanese }.map(\.text))
        let passthrough = Set(result.filter { $0.kind == .passthrough }.map(\.text))
        #expect(japanese == ["品番", "数量", "単価", "備考", "部品A", "仕様変更のため、再見積もりが必要です。"])
        #expect(passthrough == ["AB-1024", "50", "12", "¥1,200", "¥800", "Rush order"])
    }

    @Test func airyParagraphStillMerges() async throws {
        let texts = try await blocks("airy").map(\.text)
        #expect(texts == ["お問い合わせいただいた件について、担当部署で確認のうえ、改めてご連絡いたします。"])
    }

    @Test func borderedRowsOfJapaneseStayApart() async throws {
        let texts = Set(try await blocks("roster").map(\.text))
        #expect(texts == ["担当者", "田中", "佐藤", "部署", "営業部", "開発部"])
    }

    @Test func smallTextAtOneTimesScaleKeepsEveryCharacter() async throws {
        let texts = try await blocks("small", pixelsPerPoint: 1).map(\.text)
        #expect(texts == ["保存されていない変更があります。"])
    }

    @Test func poorScanIsStillRead() async throws {
        let texts = try await blocks("scan").map(\.text)
        #expect(texts == ["来週の会議は、仕様変更の影響を確認するために延期されました。", "資料は金曜日までに共有してください。"])
    }
}
