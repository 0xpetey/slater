import Foundation
import Observation
import os
@preconcurrency import Translation

private let logger = Logger(subsystem: "app.slater", category: "translation")

/// On-device translation between the languages macOS can translate and Vision can read (ADR 0001).
@MainActor
@Observable
final class Translator {
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
    }

    /// The language read off the screen.
    private(set) var source: Locale.Language
    /// The language it's translated into.
    private(set) var target: Locale.Language
    /// Languages macOS can translate on-device, one entry per language and script.
    private(set) var supportedLanguages: [Locale.Language] = []
    /// The subset Vision can also read, so they can be sources.
    private(set) var readableLanguages: [Locale.Language] = []
    /// The Fast model for the current pair. Required, so onboarding downloads it.
    private(set) var fastModel = ModelStatus.checking
    /// The Accurate model for the current pair. Optional, downloaded from Settings.
    private(set) var accurateModel = ModelStatus.checking
    /// The model the user chose. Only the choice is remembered, never any content.
    private(set) var model = Model(rawValue: UserDefaults.standard.string(forKey: "translationModel") ?? "") ?? .fast
    @ObservationIgnored private var sessions: [String: TranslationSession] = [:]

    /// Languages can be given for tests; otherwise the saved choice, defaulting to Japanese →
    /// English, the pair Slater is built and tested around. Other pairs are offered as macOS
    /// supports them and are only exercised through use.
    init(source: Locale.Language? = nil, target: Locale.Language? = nil) {
        let defaults = UserDefaults.standard
        let savedSource = defaults.string(forKey: "sourceLanguage").map(Locale.Language.init(identifier:))
        let savedTarget = defaults.string(forKey: "targetLanguage").map(Locale.Language.init(identifier:))
        self.source = source ?? savedSource ?? Locale.Language(identifier: "ja")
        self.target = target ?? savedTarget ?? Locale.Language(identifier: "en")
    }

    var sourceScript: SourceScript {
        SourceScript(language: source)
    }

    /// What Vision should look for: the source language, plus the target so words already in it
    /// are read correctly.
    var recognitionLanguages: [Locale.Language] {
        TextRecognizer.visionLanguages(for: [source, target])
    }

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

    func setLanguages(source newSource: Locale.Language, target newTarget: Locale.Language) {
        source = newSource
        target = newTarget
        UserDefaults.standard.set(newSource.minimalIdentifier, forKey: "sourceLanguage")
        UserDefaults.standard.set(newTarget.minimalIdentifier, forKey: "targetLanguage")
        fastModel = .checking
        accurateModel = .checking
        Task {
            await refresh()
            warmUp()
        }
    }

    /// For SwiftUI's `translationTask`, which shows macOS's download prompt for the pair.
    func downloadConfiguration(for model: Model) -> TranslationSession.Configuration {
        TranslationSession.Configuration(source: source, target: target, preferredStrategy: model.strategy)
    }

    /// Reloads the language list and both models' status for the current pair.
    func refresh() async {
        let all = await LanguageAvailability().supportedLanguages
        supportedLanguages = Self.representatives(of: all)
        let vision = TextRecognizer.visionLanguages(for: supportedLanguages)
        readableLanguages = supportedLanguages.filter { language in vision.contains { Self.sameLanguage($0, language) } }
        // A saved regional variant maps onto its representative.
        if let match = supportedLanguages.first(where: { Self.sameLanguage($0, source) }) { source = match }
        if let match = supportedLanguages.first(where: { Self.sameLanguage($0, target) }) { target = match }
        fastModel = await availability(of: .fast)
        accurateModel = await availability(of: .accurate)
        sessions = [:]
    }

    private func availability(of model: Model) async -> ModelStatus {
        switch await LanguageAvailability(preferredStrategy: model.strategy).status(from: source, to: target) {
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
        let session = session(for: model, source: source, target: target)
        let sample = Self.name(of: source, in: source)
        Task { _ = try? await session.translate(sample) }
    }

    /// Translates the Shot's source-language Blocks with one model, in reading order and each
    /// distinct text once, filling in the Shot as results arrive. Only texts that model hasn't
    /// translated yet are sent, so it's safe to call again after the corrected reading changes
    /// some Blocks, or when the user switches the Shot to the other model (ADR 0003). Defaults
    /// to the model the Shot displays.
    func translate(_ shot: Shot, using requested: Model? = nil) async {
        let model = requested ?? (status(of: shot.displayedModel) == .installed ? shot.displayedModel : activeModel)
        guard status(of: model) == .installed else {
            shot.setState(.failed, for: model)
            logger.error("No \(model.title, privacy: .public) model installed")
            return
        }
        let pending = shot.pendingTexts[model] ?? []
        var texts: [String] = []
        for index in shot.sourceBlockIndices {
            let text = shot.blocks[index].text
            if shot.slots[text]?.text(for: model) == nil, !pending.contains(text), !texts.contains(text) {
                texts.append(text)
            }
        }
        guard !texts.isEmpty else {
            if pending.isEmpty { shot.setState(.translated, for: model) }
            return
        }
        shot.pendingTexts[model, default: []].formUnion(texts)
        shot.setState(.translating, for: model)

        let requests = texts.enumerated().map { number, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(number))
        }
        let started = ContinuousClock.now
        var firstResult: Duration?

        do {
            for try await response in session(for: model, source: shot.source, target: shot.target).translate(batch: requests) {
                firstResult = firstResult ?? ContinuousClock.now - started
                guard let identifier = response.clientIdentifier, let number = Int(identifier) else { continue }
                let text = texts[number]
                shot.setTranslation(Self.tidy(response.targetText, source: text, target: shot.target), for: text, model: model)
                shot.pendingTexts[model]?.remove(text)
            }
            if (shot.pendingTexts[model] ?? []).isEmpty { shot.setState(.translated, for: model) }
        } catch {
            shot.pendingTexts[model]?.subtract(texts)
            shot.setState(.failed, for: model)
            logger.error("Translation failed: \(error.localizedDescription, privacy: .public)")
            await refresh()
        }
        // Counts and timings only, never text (ADR 0001).
        let lengths = texts.map(\.count)
        logger.notice("""
            Translated \(texts.count) texts (\(lengths.reduce(0, +)) characters, longest \(lengths.max() ?? 0)) with the \
            \(model.title, privacy: .public) model: first result after \(firstResult.map { milliseconds($0) } ?? -1) ms, \
            all after \(milliseconds(ContinuousClock.now - started)) ms
            """)
    }

    /// Short labels such as 備考 or 単価 come back in English as "a note" or "a unit price". An
    /// article reads oddly on a table header or form label, so drop it; and capitalize, for
    /// targets written in the Latin alphabet.
    nonisolated static func tidy(_ translation: String, source: String, target: Locale.Language) -> String {
        guard source.count <= 6, !source.contains(where: { "。、！？.!?,".contains($0) }) else { return translation }
        var result = Substring(translation)
        if target.languageCode?.identifier == "en" {
            for article in ["a ", "an ", "the "] where result.lowercased().hasPrefix(article) {
                result = result.dropFirst(article.count)
                break
            }
        }
        guard SourceScript.scripts(for: target) == ["Latin"] else { return String(result) }
        return result.prefix(1).uppercased() + result.dropFirst()
    }

    /// The language's name for display, in the current locale: "Japanese", "Chinese, Traditional".
    /// The script is named only where it distinguishes, since `Locale.Language.script` infers
    /// one for every language ("Japanese (Japanese)"): when it isn't the language's usual
    /// script, and for Chinese, whose two scripts both need naming.
    nonisolated static func name(of language: Locale.Language, in locale: Locale = .current) -> String {
        let full = Locale.Language(identifier: language.maximalIdentifier)
        let code = full.languageCode?.identifier ?? language.minimalIdentifier
        let usualScript = Locale.Language(identifier: code).script
        if let script = full.script?.identifier, script != usualScript?.identifier || code == "zh",
           let name = locale.localizedString(forIdentifier: "\(code)-\(script)") {
            return name
        }
        return locale.localizedString(forLanguageCode: code) ?? language.minimalIdentifier
    }

    nonisolated static func name(of language: Locale.Language, in other: Locale.Language) -> String {
        name(of: language, in: Locale(identifier: other.minimalIdentifier))
    }

    /// Same language and script, ignoring region: `en-GB` is `en`, but `zh-TW` isn't `zh`.
    nonisolated static func sameLanguage(_ a: Locale.Language, _ b: Locale.Language) -> Bool {
        let a = Locale.Language(identifier: a.maximalIdentifier), b = Locale.Language(identifier: b.maximalIdentifier)
        return a.languageCode == b.languageCode && a.script == b.script
    }

    /// One entry per language and script, keeping the plainest identifier (`en` over `en-GB`),
    /// with the script spelled out where a language has more than one (`zh-Hans`, `zh-Hant`).
    nonisolated static func representatives(of languages: [Locale.Language]) -> [Locale.Language] {
        var groups: [String: [Locale.Language]] = [:]
        for language in languages {
            let full = Locale.Language(identifier: language.maximalIdentifier)
            groups["\(full.languageCode?.identifier ?? "")-\(full.script?.identifier ?? "")", default: []].append(language)
        }
        let scriptsPerCode = Dictionary(grouping: groups.keys) { String($0.split(separator: "-")[0]) }
        return groups.map { key, variants in
            let plainest = variants.min { $0.minimalIdentifier.count < $1.minimalIdentifier.count }!
            let code = String(key.split(separator: "-")[0])
            let full = Locale.Language(identifier: plainest.maximalIdentifier)
            if (scriptsPerCode[code]?.count ?? 0) > 1, let script = full.script?.identifier {
                return Locale.Language(identifier: "\(code)-\(script)")
            }
            return plainest
        }
        .sorted { name(of: $0) < name(of: $1) }
    }

    private func session(for model: Model, source: Locale.Language, target: Locale.Language) -> TranslationSession {
        let key = "\(model.rawValue)|\(source.minimalIdentifier)|\(target.minimalIdentifier)"
        if let session = sessions[key] { return session }
        let session = TranslationSession(installedSource: source, target: target, preferredStrategy: model.strategy)
        sessions[key] = session
        return session
    }
}

private func milliseconds(_ duration: Duration) -> Int {
    Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
}
