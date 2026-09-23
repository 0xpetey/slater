import CoreGraphics
import Testing
@testable import Slater

private func line(_ text: String, x: CGFloat, y: CGFloat = 10, width: CGFloat = 200) -> Line {
    Line(text: text, bounds: CGRect(x: x, y: y, width: width, height: 30))
}

struct TextReaderTests {
    @Test func agreeingReadingsAreTrusted() {
        let lines = TextReader.reconcile([line("担当者", x: 10)], [line("担当者", x: 11)])
        #expect(lines.map(\.text) == ["担当者"])
        #expect(lines.map(\.isLowConfidence) == [false])
    }

    @Test func droppedCharacterLosesToTheLongerReading() {
        let lines = TextReader.reconcile([line("担者", x: 10)], [line("担当者", x: 10)])
        #expect(lines.map(\.text) == ["担当者"])
        #expect(lines.map(\.isLowConfidence) == [true])
    }

    @Test func aLineSplitInOneReadingIsJoined() {
        let raw = [line("未確認の項目は、担当者が確認する", x: 10, width: 300), line("まで出荷できません。", x: 320, width: 150)]
        let prepared = [line("未確認の項目は、担当者が確認するまで出荷できません。", x: 10, width: 460)]
        let lines = TextReader.reconcile(raw, prepared)
        #expect(lines.map(\.text) == ["未確認の項目は、担当者が確認するまで出荷できません。"])
        #expect(lines.map(\.isLowConfidence) == [false])
    }

    @Test func textOnlyOneReadingFoundIsKeptButMarked() {
        let lines = TextReader.reconcile([], [line("資料", x: 10)])
        #expect(lines.map(\.text) == ["資料"])
        #expect(lines.map(\.isLowConfidence) == [true])
    }

    @Test func sideBySideCellsStaySeparateLines() {
        let lines = TextReader.reconcile(
            [line("品番", x: 10, width: 56), line("数量", x: 200, width: 56)],
            [line("品番", x: 10, width: 56), line("数量", x: 200, width: 56)]
        )
        #expect(lines.map(\.text) == ["品番", "数量"])
    }
}
