import CoreGraphics
import Testing
@testable import Slater

private func line(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 200, height: CGFloat = 30) -> Line {
    Line(text: text, bounds: CGRect(x: x, y: y, width: width, height: height))
}

struct BlockGrouperTests {
    @Test func sentenceWrappedAcrossLinesIsOneBlock() {
        let blocks = BlockGrouper.group([
            line("来週の会議は、仕様変更の影響を確認するため", x: 30, y: 28, width: 590),
            line("に延期されました。", x: 32, y: 68, width: 240),
        ])
        #expect(blocks.map(\.text) == ["来週の会議は、仕様変更の影響を確認するために延期されました。"])
    }

    @Test func sideBySideCellsNeverMerge() {
        let blocks = BlockGrouper.group([
            line("品番", x: 30, y: 28, width: 56),
            line("数量", x: 230, y: 28, width: 56),
            line("単価", x: 350, y: 28, width: 56),
        ])
        #expect(blocks.map(\.text) == ["品番", "数量", "単価"])
    }

    @Test func tableRowsStayApartAndAWrappedCellMerges() {
        // Rows are close together, but a cell ending in 。 or a new row's cell must not
        // pull in the cell below it unless it wraps.
        let blocks = BlockGrouper.group([
            line("備考", x: 530, y: 28, width: 56),
            line("仕様変更のため、", x: 532, y: 130, width: 199),
            line("再見積もりが必要です。", x: 532, y: 166, width: 274),
            line("12", x: 228, y: 132, width: 42),
        ])
        #expect(Set(blocks.map(\.text)) == ["備考", "12", "仕様変更のため、再見積もりが必要です。"])
    }

    @Test func ruleBetweenRowsKeepsThemApart() {
        let blocks = BlockGrouper.group(
            [line("担当者", x: 10, y: 10, width: 90), line("田中", x: 10, y: 45, width: 60)],
            hasRule: { _ in true }
        )
        #expect(blocks.count == 2)
    }

    @Test func japaneseAndPassthroughLinesDoNotMerge() {
        let blocks = BlockGrouper.group([line("数量", x: 10, y: 10, width: 56), line("50", x: 10, y: 45, width: 42)])
        #expect(blocks.count == 2)
    }

    @Test func sentenceEndingClosesTheBlock() {
        let blocks = BlockGrouper.group([
            line("資料を確認しました。", x: 10, y: 10),
            line("問題ありません。", x: 10, y: 45),
        ])
        #expect(blocks.count == 2)
    }

    @Test func headingOverBodyTextDoesNotMerge() {
        let blocks = BlockGrouper.group([
            line("会議のお知らせ", x: 10, y: 10, height: 60),
            line("来週の会議は延期されました", x: 10, y: 75, height: 30),
        ])
        #expect(blocks.count == 2)
    }

    @Test func englishLinesJoinWithASpace() {
        let blocks = BlockGrouper.group([
            line("Please confirm the", x: 10, y: 10),
            line("delivery date", x: 10, y: 45),
        ])
        #expect(blocks.map(\.text) == ["Please confirm the delivery date"])
    }
}

struct BlockKindTests {
    @Test(arguments: ["品番", "部品A", "AB-1024の在庫", "カタカナ", "ひらがな", "日々"])
    func japaneseTextIsTranslated(_ text: String) {
        #expect(Block(lines: [line(text, x: 0, y: 0)]).kind == .japanese)
    }

    @Test(arguments: ["AB-1024", "50", "¥1,200", "Rush order", "10/15", "—"])
    func textWithoutJapaneseIsPassthrough(_ text: String) {
        #expect(Block(lines: [line(text, x: 0, y: 0)]).kind == .passthrough)
    }
}
