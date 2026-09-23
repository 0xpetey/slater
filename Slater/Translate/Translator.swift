import Observation
@preconcurrency import Translation

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

    /// Loading the model takes about 1.5 s on the first translation, so start it while
    /// the user is still dragging a box.
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

        do {
            for try await response in currentSession().translate(batch: requests) {
                guard let identifier = response.clientIdentifier, let text = textsByIdentifier[identifier] else { continue }
                for index in indicesByText[text] ?? [] {
                    shot.translations[index] = response.targetText
                }
            }
            shot.state = .translated
        } catch {
            shot.state = .failed
            await refreshLanguagePack()
        }
    }

    private func currentSession() -> TranslationSession {
        if let session { return session }
        let session = TranslationSession(installedSource: Self.source, target: Self.target)
        self.session = session
        return session
    }
}
