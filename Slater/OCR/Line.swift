import CoreGraphics

/// A single run of text as OCR read it, horizontal or vertical (縦書き), before any merging.
struct Line: Equatable, Sendable {
    var text: String
    /// In the crop's pixels, origin top-left.
    var bounds: CGRect
    /// The two OCR readings disagreed, or only one of them found this text (ADR 0002).
    var isLowConfidence = false
    /// One character's box is far wider than its neighbors', which is how Vision reading two
    /// glyphs as one shows up (当 glued to the character beside it in gothic fonts; ADR 0002).
    var hasSuspectedMerge = false

    /// A column of vertical writing: much taller than wide, and more than one character, since a
    /// single character's box is square whichever way it's written.
    var isVertical: Bool {
        text.count > 1 && bounds.height > 1.5 * bounds.width
    }
}
