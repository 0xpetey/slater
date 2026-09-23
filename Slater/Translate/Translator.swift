import Foundation
import Observation
import os
@preconcurrency import Translation

private let logger = Logger(subsystem: "com.peterjournell.slater", category: "translation")

/// Japanese → English, on-device only (ADR 0001).
@MainActor
@Observable
final class Translator {
    nonisolated static let source = Locale.Language(identifier: "ja")
    /// English only for now; a setting can replace this constant later.
    nonisolated static let target = Locale.Language(identifier: "en")

    enum ModelStatus: Equatable {
        case checking, installed, needsDownload, unsupported
    }

    /// Which of macOS's on-device models to use. Both stay on this Mac (ADR 0003).
    enum Model: String, CaseIterable, Identifiable {
        /// A smaller model: about 20 ms per text. The default.
        case fast
        /// macOS's default model: about 0.4 s per text, sometimes better wording.
        case accurate

        var id: Self { self }

        var title: String {
            switch self {
            case .fast: "Fast"
            case .accurate: "Accurate"
            }
        }

        var strategy: TranslationSession.Strategy {
            self == .fast ? .lowLatency : .highFidelity
        }

        /// For SwiftUI's `translationTask`, which shows macOS's download prompt.
        var downloadConfiguration: TranslationSession.Configuration {
            TranslationSession.Configuration(source: Translator.source, target: Translator.target, preferredStrategy: strategy)
        }
    }

    private(set) var fastModel = ModelStatus.checking
    private(set) var accurateModel = ModelStatus.checking
    /// The model the user chose. Only the choice is remembered, never any content.
    private(set) var model = Model(rawValue: UserDefaults.standard.string(forKey: "translationModel") ?? "") ?? .fast
    @ObservationIgnored private var sessions: [Model: TranslationSession] = [:]

    func status(of model: Model) -> ModelStatus {
        model == .fast ? fastModel : accurateModel
    }

    var hasInstalledModel: Bool {
        fastModel == .installed || accurateModel == .installed
    }

    /// The chosen model when it's installed, otherwise whichever one is.
    var activeModel: Model {
        if status(of: model) == .installed { return model }
        let other: Model = model == .fast ? .accurate : .fast
        return status(of: other) == .installed ? other : model
    }

    func setModel(_ newModel: Model) {
        model = newModel
        UserDefaults.standard.set(newModel.rawValue, forKey: "translationModel")
        warmUp()
    }

    func refreshModels() async {
        fastModel = await availability(of: .fast)
        accurateModel = await availability(of: .accurate)
        sessions = [:]
    }

    private func availability(of model: Model) async -> ModelStatus {
        switch await LanguageAvailability(preferredStrategy: model.strategy).status(from: Self.source, to: Self.target) {
        case .installed: .installed
        case .supported: .needsDownload
        default: .unsupported
        }
    }

    /// Loading a model takes 60 ms (Fast) to 8 s (Accurate, cold) on the first translation, so
    /// Slater warms the active one up at launch, on wake and when the hotkey is pressed, while
    /// the user is still dragging a box.
    func warmUp() {
        let model = activeModel
        guard status(of: model) == .installed else { return }
        let session = session(for: model)
        Task { _ = try? await session.translate("準備") }
    }

    /// Translates the Shot's Japanese Blocks, in reading order and each distinct text once,
    /// filling in the Shot as results arrive. Normally only untranslated texts are sent, so it's
    /// safe to call again after the corrected reading changes some Blocks. With
    /// `replacingExisting`, every text is sent again, which is how a Shot translated with Fast
    /// is rerun with Accurate: the old translations stay visible until each new one lands.
    func translate(_ shot: Shot, using requested: Model? = nil, replacingExisting: Bool = false) async {
        let model = requested ?? activeModel
        guard status(of: model) == .installed else {
            shot.state = .failed
            logger.error("No \(model.title, privacy: .public) model installed")
            return
        }
        var texts: [String] = []
        for index in shot.japaneseBlockIndices {
            let text = shot.blocks[index].text
            let wanted = replacingExisting || (shot.slots[text]?.text == nil && !shot.pendingTexts.contains(text))
            if wanted, !texts.contains(text) { texts.append(text) }
        }
        shot.model = model
        guard !texts.isEmpty else {
            if shot.pendingTexts.isEmpty { shot.state = .translated }
            return
        }
        shot.pendingTexts.formUnion(texts)
        shot.state = .translating

        let requests = texts.enumerated().map { number, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(number))
        }
        let started = ContinuousClock.now
        var firstResult: Duration?

        do {
            for try await response in session(for: model).translate(batch: requests) {
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
            await refreshModels()
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

    private func session(for model: Model) -> TranslationSession {
        if let session = sessions[model] { return session }
        let session = TranslationSession(installedSource: Self.source, target: Self.target, preferredStrategy: model.strategy)
        sessions[model] = session
        return session
    }
}

private func milliseconds(_ duration: Duration) -> Int {
    Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
}
