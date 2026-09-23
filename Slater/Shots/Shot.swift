import CoreGraphics
import Foundation
import Observation

/// The result of one hotkey press and drag: a frozen image of the selected box, its Blocks
/// and their translations. Kept in memory only (ADR 0001).
@MainActor
@Observable
final class Shot {
    enum State { case translating, translated, failed }

    let image: CGImage
    /// Where the box was, in global AppKit points.
    let screenRect: CGRect
    let blocks: [Block]
    let createdAt = Date.now
    /// English for each Japanese Block, keyed by index into `blocks`. Filled in as results arrive.
    var translations: [Int: String] = [:]
    var state = State.translating

    init(image: CGImage, screenRect: CGRect, blocks: [Block]) {
        self.image = image
        self.screenRect = screenRect
        self.blocks = blocks
    }

    var japaneseBlockIndices: [Int] {
        blocks.indices.filter { blocks[$0].kind == .japanese }
    }

    /// Every translation, one Block per line, for pasting into an email or reply.
    var englishText: String {
        japaneseBlockIndices.compactMap { translations[$0] }.joined(separator: "\n")
    }

    /// A short line for the menu bar's Open Shots list: the start of the first translation,
    /// or of the Japanese while it's still translating.
    var summary: String {
        guard let first = japaneseBlockIndices.first else { return "" }
        let text = translations[first] ?? blocks[first].text
        return text.count > 40 ? text.prefix(40) + "…" : text
    }

    /// The suggested name when saving, in the style of macOS screenshots.
    var defaultName: String {
        "Shot " + createdAt.formatted(.verbatim(
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) at \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
            timeZone: .current, calendar: .current
        ))
    }

    /// The saved text file: each Japanese Block quoted, then its translation.
    func markdown(title: String) -> String {
        let entries = japaneseBlockIndices.map { index in
            let block = blocks[index]
            let warning = block.isLowConfidence ? " ⚠️ Low OCR confidence: check against the original image" : ""
            return "> \(block.text)\(warning)\n\n\(translations[index] ?? "_Not translated_")"
        }
        return (["# \(title)"] + entries).joined(separator: "\n\n") + "\n"
    }

    /// Each Japanese Block followed by its translation, for quoting or asking a colleague to check.
    var bilingualText: String {
        japaneseBlockIndices.map { index in
            [blocks[index].text, translations[index]].compactMap { $0 }.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }
}
