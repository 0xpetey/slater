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

    private(set) var languagePack = LanguagePack.checking
    @ObservationIgnored private var session: TranslationSession?

    func refreshLanguagePack() async {
        languagePack = switch await LanguageAvailability().status(from: Self.source, to: Self.target) {
        case .installed: .installed
        case .supported: .needsDownload
        default: .unsupported
        }
        if languagePack != .installed { session = nil }
    }

    /// Loading the model takes 1.5–8 s on the first translation, so Slater warms it up at
    /// launch, on wake and when the hotkey is pressed, while the user is still dragging a box.
    func warmUp() {
        guard languagePack == .installed else { return }
        let session = currentSession()
        Task { _ = try? await session.translate("準備") }
    }

    /// Translates each Japanese Block, filling in `shot` as results arrive. The system
    /// translates one text at a time, so streaming lets early Blocks appear sooner.
    func translate(_ shot: Shot) async {
        let indicesByText = Dictionary(grouping: shot.japaneseBlockIndices) { shot.blocks[$0].text }
        let requests = indicesByText.keys.enumerated().map { number, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(number))
        }
        let textsByIdentifier = Dictionary(uniqueKeysWithValues: requests.map { ($0.clientIdentifier!, $0.sourceText) })
        let started = ContinuousClock.now
        var firstResult: Duration?

        do {
            for try await response in currentSession().translate(batch: requests) {
                firstResult = firstResult ?? ContinuousClock.now - started
                guard let identifier = response.clientIdentifier, let text = textsByIdentifier[identifier] else { continue }
                for index in indicesByText[text] ?? [] {
                    shot.translations[index] = Self.tidy(response.targetText, source: text)
                }
            }
            shot.state = .translated
        } catch {
            shot.state = .failed
            logger.error("Translation failed: \(error.localizedDescription, privacy: .public)")
            await refreshLanguagePack()
        }
        // Counts and timings only, never text (ADR 0001).
        let lengths = requests.map(\.sourceText.count)
        logger.notice("""
            Translated \(requests.count) texts (\(lengths.reduce(0, +)) characters, longest \(lengths.max() ?? 0)): \
            first result after \(firstResult.map { "\($0.components.seconds * 1000 + $0.components.attoseconds / 1_000_000_000_000_000)" } ?? "–", privacy: .public) ms, \
            all after \((ContinuousClock.now - started).components.seconds * 1000 + (ContinuousClock.now - started).components.attoseconds / 1_000_000_000_000_000) ms
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
        let session = TranslationSession(installedSource: Self.source, target: Self.target)
        self.session = session
        return session
    }
}
