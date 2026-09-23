import CoreGraphics

/// A single horizontal run of text as OCR read it, before any merging.
struct Line: Equatable, Sendable {
    var text: String
    /// In the crop's pixels, origin top-left.
    var bounds: CGRect
    /// The two OCR readings disagreed, or only one of them found this text (ADR 0002).
    var isLowConfidence = false
}
