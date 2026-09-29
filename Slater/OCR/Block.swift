import CoreGraphics

/// One or more Lines that continue one another and are translated together: stacked for
/// horizontal writing, side by side from right to left for vertical writing.
struct Block: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Contains the source language's script, so it's translated.
        case source
        /// None of it (numbers, part codes, text already in another language), so it's shown
        /// exactly as captured.
        case passthrough
    }

    var lines: [Line]
    let kind: Kind

    init(lines: [Line], kind: Kind) {
        self.lines = lines
        self.kind = kind
    }

    /// Classified by whether any character is in the source language's script.
    init(lines: [Line], source: SourceScript) {
        self.lines = lines
        kind = source.contains(lines.map(\.text).joined()) ? .source : .passthrough
    }

    var isVertical: Bool { lines[0].isVertical }

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

    private static func isLatinWordCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}
