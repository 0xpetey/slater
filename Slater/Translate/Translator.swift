import Foundation
import Observation
import os
@preconcurrency import Translation

private let logger = Logger(subsystem: "com.peterjournell.slater", category: "translation")

/// Japanese → English, on-device only (ADR 0001).
@MainActor
@Observable
final class Translator {
    static let source = Locale.Language(identifier: "ja")
    /// English only for now; a setting can replace this constant later.
    static let target = Locale.Language(identifier: "en")

    enum LanguagePack: Equatable {
        case checking, installed, needsDownload, unsupported
    }

    /// Which of macOS's on-device models to use. Both stay on this Mac.
    enum Model: String, CaseIterable, Identifiable {
        /// macOS's default model. Translates one text at a time, about 0.3–0.5 s each.
        case accurate
        /// A smaller model that macOS downloads on request. Returns results sooner.
        case fast

        var id: Self { self }

        var title: String {
            switch self {
            case .accurate: "Accurate"
            case .fast: "Fast"
            }
        }

        var strategy: TranslationSession.Strategy {
            self == .fast ? .lowLatency : .highFidelity
        }
    }

    /// The Accurate model. Required, so onboarding downloads it.
    private(set) var languagePack = LanguagePack.checking
    /// The Fast model. Optional, downloaded from Settings.
    private(set) var fastModel = LanguagePack.checking
    /// The model the user chose. Only the choice is remembered, never any content.
    private(set) var model = Model(rawValue: UserDefaults.standard.string(forKey: "translationModel") ?? "") ?? .accurate
    @ObservationIgnored private var session: TranslationSession?

    /// The model translations actually use: Fast only when chosen and installed.
    var activeModel: Model {
        model == .fast && fastModel == .installed ? .fast : .accurate
    }

    func setModel(_ newModel: Model) {
        model = newModel
        UserDefaults.standard.set(newModel.rawValue, forKey: "translationModel")
        session = nil
        warmUp()
    }

    func refreshLanguagePack() async {
        languagePack = await status(of: .accurate)
        fastModel = await status(of: .fast)
        session = nil
    }

    private func status(of model: Model) async -> LanguagePack {
        switch await LanguageAvailability(preferredStrategy: model.strategy).status(from: Self.source, to: Self.target) {
        case .installed: .installed
        case .supported: .needsDownload
        default: .unsupported
        }
    }

    /// Loading a model takes 1.5–8 s on the first translation, so Slater warms it up at
    /// launch, on wake and when the hotkey is pressed, while the user is still dragging a box.
    func warmUp() {
        guard languagePack == .installed else { return }
        let session = currentSession()
        Task { _ = try? await session.translate("準備") }
    }

    /// Translates the Shot's Japanese Blocks that aren't translated yet, in reading order and
    /// each distinct text once, filling in the Shot as results arrive. macOS translates one text
    /// at a time, so streaming lets the top of the page appear first. Safe to call again after
    /// the Shot's Blocks change: only new texts are sent.
    func translate(_ shot: Shot) async {
        var texts: [String] = []
        for index in shot.japaneseBlockIndices {
            let text = shot.blocks[index].text
            if shot.slots[text]?.text == nil, !shot.pendingTexts.contains(text), !texts.contains(text) {
                texts.append(text)
            }
        }
        guard !texts.isEmpty else {
            if shot.pendingTexts.isEmpty { shot.state = .translated }
            return
        }
        shot.pendingTexts.formUnion(texts)
        shot.state = .translating

        let requests = texts.enumerated().map { number, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(number))
        }
        let model = activeModel
        let started = ContinuousClock.now
        var firstResult: Duration?

        do {
            for try await response in currentSession().translate(batch: requests) {
                firstResult = firstResult ?? ContinuousClock.now - started
                guard let identifier = response.clientIdentifier, let number = Int(identifier) else { continue }
                let text = texts[number]
                shot.setTranslation(Self.tidy(response.targetText, source: text), for: text)
                shot.pendingTexts.remove(text)
            }
            if shot.pendingTexts.isEmpty { shot.state = .translated }
        } catch {
            shot.pendingTexts.subtract(texts)
            shot.state = .failed
            logger.error("Translation failed: \(error.localizedDescription, privacy: .public)")
            await refreshLanguagePack()
        }
        // Counts and timings only, never text (ADR 0001).
        let lengths = texts.map(\.count)
        logger.notice("""
            Translated \(texts.count) texts (\(lengths.reduce(0, +)) characters, longest \(lengths.max() ?? 0)) with the \
            \(model.title, privacy: .public) model: first result after \(firstResult.map { milliseconds($0) } ?? -1) ms, \
            all after \(milliseconds(ContinuousClock.now - started)) ms
            """)
    }

    /// Short labels such as 備考 or 単価 come back as "a note" or "a unit price". An article
    /// reads oddly on a table header or form label, so drop it and capitalize.
    nonisolated static func tidy(_ translation: String, source: String) -> String {
        guard source.count <= 6, !source.contains(where: { "。、！？".contains($0) }) else { return translation }
        for article in ["a ", "an ", "the "] where translation.lowercased().hasPrefix(article) {
            let rest = translation.dropFirst(article.count)
            return rest.prefix(1).uppercased() + rest.dropFirst()
        }
        return translation.prefix(1).uppercased() + translation.dropFirst()
    }

    private func currentSession() -> TranslationSession {
        if let session { return session }
        let session = TranslationSession(installedSource: Self.source, target: Self.target, preferredStrategy: activeModel.strategy)
        self.session = session
        return session
    }
}

private func milliseconds(_ duration: Duration) -> Int {
    Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
}
