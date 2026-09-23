import CoreGraphics
import Testing
@testable import Slater

private func line(_ text: String, x: CGFloat, y: CGFloat = 10, width: CGFloat = 200) -> Line {
    Line(text: text, bounds: CGRect(x: x, y: y, width: width, height: 30))
}

struct TextReaderTests {
    @Test func agreeingReadingsAreTrusted() {
        let lines = TextReader.reconcile(quick: [line("担当者", x: 10)], corrected: [line("担当者", x: 11)])
        #expect(lines.map(\.text) == ["担当者"])
        #expect(lines.map(\.isLowConfidence) == [false])
    }

    @Test func droppedCharacterLosesToTheLongerReading() {
        let lines = TextReader.reconcile(quick: [line("担当者", x: 10)], corrected: [line("担者", x: 10)])
        #expect(lines.map(\.text) == ["担当者"])
        #expect(lines.map(\.isLowConfidence) == [true])

        let reversed = TextReader.reconcile(quick: [line("担者", x: 10)], corrected: [line("担当者", x: 10)])
        #expect(reversed.map(\.text) == ["担当者"])
    }

    @Test func aTieGoesToTheCorrectedReading() {
        // The quick reading, without language correction, misreads 末 as 未 on blurry scans.
        let lines = TextReader.reconcile(quick: [line("未尾の数字", x: 10)], corrected: [line("末尾の数字", x: 10)])
        #expect(lines.map(\.text) == ["末尾の数字"])
        #expect(lines.map(\.isLowConfidence) == [true])
    }

    @Test func aLineSplitInOneReadingIsJoined() {
        let quick = [line("未確認の項目は、担当者が確認する", x: 10, width: 300), line("まで出荷できません。", x: 320, width: 150)]
        let corrected = [line("未確認の項目は、担当者が確認するまで出荷できません。", x: 10, width: 460)]
        let lines = TextReader.reconcile(quick: quick, corrected: corrected)
        #expect(lines.map(\.text) == ["未確認の項目は、担当者が確認するまで出荷できません。"])
        #expect(lines.map(\.isLowConfidence) == [false])
    }

    @Test func textOnlyOneReadingFoundIsKeptButMarked() {
        let lines = TextReader.reconcile(quick: [], corrected: [line("資料", x: 10)])
        #expect(lines.map(\.text) == ["資料"])
        #expect(lines.map(\.isLowConfidence) == [true])
    }

    @Test func sideBySideCellsStaySeparateLines() {
        let lines = TextReader.reconcile(
            quick: [line("品番", x: 10, width: 56), line("数量", x: 200, width: 56)],
            corrected: [line("品番", x: 10, width: 56), line("数量", x: 200, width: 56)]
        )
        #expect(lines.map(\.text) == ["品番", "数量"])
    }
}
