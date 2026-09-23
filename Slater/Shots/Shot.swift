import CoreGraphics
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

    /// Each Japanese Block followed by its translation, for quoting or asking a colleague to check.
    var bilingualText: String {
        japaneseBlockIndices.map { index in
            [blocks[index].text, translations[index]].compactMap { $0 }.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }
}
