import CoreGraphics
import Foundation
import Observation

/// The result of one hotkey press and drag: a frozen image of the selected box, its Blocks
/// and their translations. Kept in memory only (ADR 0001).
@MainActor
@Observable
final class Shot {
    enum State { case notStarted, translating, translated, failed }

    /// The translations of one distinct Japanese text, one per model. Blocks with the same
    /// text share a slot, so the text is translated once per model, and each patch re-renders
    /// only when its own slot changes.
    @MainActor
    @Observable
    final class TranslationSlot {
        let source: String
        private(set) var texts: [Translator.Model: String] = [:]

        init(source: String) {
            self.source = source
        }

        func text(for model: Translator.Model) -> String? {
            texts[model]
        }

        func set(_ text: String, for model: Translator.Model) {
            texts[model] = text
        }
    }

    let image: CGImage
    /// Where the box was, in global AppKit points.
    let screenRect: CGRect
    let createdAt = Date.now
    private(set) var blocks: [Block] = []
    private(set) var patches: [Patch] = []
    /// Keyed by the Japanese text.
    private(set) var slots: [String: TranslationSlot] = [:]
    /// Texts sent to the translator, per model, that haven't come back yet.
    var pendingTexts: [Translator.Model: Set<String>] = [:]
    private(set) var states: [Translator.Model: State] = [:]
    /// Which model's translations the Shot shows, copies and saves (ADR 0003). The other
    /// model's translations, if any, are kept for switching back.
    var displayedModel = Translator.Model.fast
    /// The corrected OCR reading has been applied (or wasn't needed), so the text is final.
    var isVerified = false
    private let sampler: ColorSampler

    init(image: CGImage, screenRect: CGRect, blocks: [Block]) {
        self.image = image
        self.screenRect = screenRect
        sampler = ColorSampler(image: image)
        update(blocks: blocks)
    }

    /// Replaces the Blocks, keeping the translations of texts that are still present.
    func update(blocks newBlocks: [Block]) {
        blocks = newBlocks
        let texts = Set(japaneseBlockIndices.map { blocks[$0].text })
        slots = slots.filter { texts.contains($0.key) }
        for text in texts where slots[text] == nil {
            slots[text] = TranslationSlot(source: text)
        }
        for model in pendingTexts.keys {
            pendingTexts[model]?.formIntersection(texts)
        }
        patches = ShotLayout.patches(
            for: blocks,
            indices: japaneseBlockIndices,
            pointsPerPixel: screenRect.width / CGFloat(image.width),
            windowSize: screenRect.size,
            background: sampler.background(around:),
            clearWidth: sampler.clearWidth(rightOf:background:)
        )
    }

    var japaneseBlockIndices: [Int] {
        blocks.indices.filter { blocks[$0].kind == .japanese }
    }

    func slot(for blockIndex: Int) -> TranslationSlot? {
        slots[blocks[blockIndex].text]
    }

    func setTranslation(_ translation: String, for source: String, model: Translator.Model) {
        slots[source]?.set(translation, for: model)
    }

    func state(for model: Translator.Model) -> State {
        states[model] ?? .notStarted
    }

    func setState(_ state: State, for model: Translator.Model) {
        states[model] = state
    }

    /// The displayed model's translation state.
    var state: State {
        state(for: displayedModel)
    }

    func translation(for blockIndex: Int, model: Translator.Model? = nil) -> String? {
        slot(for: blockIndex)?.text(for: model ?? displayedModel)
    }

    /// The displayed model's English for each translated Japanese Block, keyed by index into `blocks`.
    var translations: [Int: String] {
        Dictionary(uniqueKeysWithValues: japaneseBlockIndices.compactMap { index in
            translation(for: index).map { (index, $0) }
        })
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
        let translations = translations
        let entries = japaneseBlockIndices.map { index in
            let block = blocks[index]
            let warning = block.isLowConfidence ? " ⚠️ Low OCR confidence: check against the original image" : ""
            return "> \(block.text)\(warning)\n\n\(translations[index] ?? "_Not translated_")"
        }
        return (["# \(title)"] + entries).joined(separator: "\n\n") + "\n"
    }

    /// Each Japanese Block followed by its translation, for quoting or asking a colleague to check.
    var bilingualText: String {
        let translations = translations
        return japaneseBlockIndices.map { index in
            [blocks[index].text, translations[index]].compactMap { $0 }.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }
}
