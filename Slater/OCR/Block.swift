import CoreGraphics

/// One or more Lines that continue one another and are translated together: stacked for
/// horizontal writing, side by side from right to left for vertical writing.
struct Block: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Contains Japanese, so it's translated.
        case japanese
        /// No Japanese (numbers, part codes, English), so it's shown exactly as captured.
        case passthrough
    }

    var lines: [Line]

    var isVertical: Bool { lines[0].isVertical }

    var kind: Kind { Self.containsJapanese(text) ? .japanese : .passthrough }

    /// OCR may have misread part of this Block, so its translation should be checked (ADR 0002).
    var isLowConfidence: Bool { lines.contains(where: \.isLowConfidence) }

    var bounds: CGRect {
        lines.dropFirst().reduce(lines[0].bounds) { $0.union($1.bounds) }
    }

    /// Lines joined without spaces, as Japanese is written, except between two Latin words.
    var text: String {
        lines.dropFirst().reduce(lines[0].text) { joined, line in
            let needsSpace = joined.last.map(Self.isLatinWordCharacter) == true
                && line.text.first.map(Self.isLatinWordCharacter) == true
            return joined + (needsSpace ? " " : "") + line.text
        }
    }

    static func containsJapanese(_ text: String) -> Bool {
        text.contains(/[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Han}]/)
    }

    private static func isLatinWordCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}
