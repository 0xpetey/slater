import Foundation

/// Which characters mark a Block as written in the source language, so it gets translated.
/// Japanese is any hiragana, katakana or kanji; Korean any hangul; languages written in the
/// Latin alphabet count any Latin letter, since English and German can't be told apart by
/// script alone (the translator passes through what's already in the target language).
struct SourceScript: Sendable, Equatable {
    let language: Locale.Language
    /// Unicode script names, as in `\p{Script=…}`.
    let scripts: [String]

    init(language: Locale.Language) {
        self.language = language
        scripts = Self.scripts(for: language)
    }

    /// The language's writing system(s).
    static func scripts(for language: Locale.Language) -> [String] {
        switch language.languageCode?.identifier {
        case "ja": ["Hiragana", "Katakana", "Han"]
        case "zh", "yue": ["Han", "Bopomofo"]
        case "ko": ["Hangul", "Han"]
        case "th": ["Thai"]
        case "ar", "ars": ["Arabic"]
        case "he": ["Hebrew"]
        case "hi", "mr", "ne": ["Devanagari"]
        case "ru", "uk", "bg", "sr", "kk": ["Cyrillic"]
        case "el": ["Greek"]
        default: ["Latin"]
        }
    }

    /// Whether `text` contains at least one character of the source language's script.
    func contains(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in Self.matches(scalar, scripts: scripts) }
    }

    /// Writing in these scripts runs in vertical columns (縦書き) as well as rows.
    var canBeVertical: Bool {
        scripts.contains("Han") || scripts.contains("Hangul")
    }

    static let japanese = SourceScript(language: Locale.Language(identifier: "ja"))

    private static func matches(_ scalar: Unicode.Scalar, scripts: [String]) -> Bool {
        let value = scalar.value
        for script in scripts {
            let inScript = switch script {
            case "Hiragana": (0x3041...0x309F).contains(value)
            case "Katakana": (0x30A0...0x30FF).contains(value) || (0x31F0...0x31FF).contains(value) || (0xFF66...0xFF9F).contains(value)
            case "Han": (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value) || (0xF900...0xFAFF).contains(value) || (0x20000...0x2FA1F).contains(value) || value == 0x3005 || value == 0x3007
            case "Bopomofo": (0x3100...0x312F).contains(value) || (0x31A0...0x31BF).contains(value)
            case "Hangul": (0xAC00...0xD7AF).contains(value) || (0x1100...0x11FF).contains(value) || (0x3130...0x318F).contains(value)
            case "Thai": (0x0E00...0x0E7F).contains(value)
            case "Arabic": (0x0600...0x06FF).contains(value) || (0x0750...0x077F).contains(value) || (0xFB50...0xFDFF).contains(value) || (0xFE70...0xFEFF).contains(value)
            case "Hebrew": (0x0590...0x05FF).contains(value)
            case "Devanagari": (0x0900...0x097F).contains(value)
            case "Cyrillic": (0x0400...0x04FF).contains(value) || (0x0500...0x052F).contains(value)
            case "Greek": (0x0370...0x03FF).contains(value)
            case "Latin": scalar.properties.isAlphabetic && (value < 0x0250 || (0x1E00...0x1EFF).contains(value))
            default: false
            }
            if inScript { return true }
        }
        return false
    }
}
