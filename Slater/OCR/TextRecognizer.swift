import AppKit
import CoreGraphics
import Vision

enum TextRecognizer {
    /// A character box this many times wider than the line's median counts as two glyphs read
    /// as one. Measured on 288 rendered lines: 101 correct flags, 1 false one.
    static let mergeRatio: CGFloat = 1.6

    /// Reads the Lines in `image`, with bounds in `boundsSize` pixels (origin top-left).
    /// Pass the original crop's size when `image` is a scaled copy of it.
    ///
    /// Language correction is the single most expensive step in the pipeline: on a 20-line
    /// crop it takes a pass from about 0.5 s to 1.2 s. It stays on for the corrected reading,
    /// because turning it off caused misreads such as 未 for 末 on blurry scans (ADR 0002).
    static func recognize(_ image: CGImage, boundsSize: CGSize, languageCorrection: Bool) async throws -> [Line] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "ja-JP"), Locale.Language(identifier: "en-US")]
        request.usesLanguageCorrection = languageCorrection

        return try await request.perform(on: image).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            var line = Line(text: candidate.string, bounds: observation.boundingBox.toImageCoordinates(boundsSize, origin: .upperLeft))
            line.hasSuspectedMerge = hasSuspectedMerge(candidate, line: line, boundsSize: boundsSize)
            return line
        }
    }

    /// Japanese characters all take the same advance, so a box far wider than the line's
    /// median (or taller, in a vertical column) held two glyphs. Latin text is skipped, since its
    /// widths vary anyway.
    private static func hasSuspectedMerge(_ candidate: RecognizedText, line: Line, boundsSize: CGSize) -> Bool {
        let text = candidate.string
        var extents: [CGFloat] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if isFullWidth(text[index]), let box = candidate.boundingBox(for: index..<next) {
                let rect = box.boundingBox.toImageCoordinates(boundsSize, origin: .upperLeft)
                extents.append(line.isVertical ? rect.height : rect.width)
            }
            index = next
        }
        guard extents.count >= 3 else { return false }
        let sorted = extents.sorted()
        return sorted[sorted.count - 1] > mergeRatio * sorted[sorted.count / 2]
    }

    private static func isFullWidth(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0x3000...0x9FFF).contains($0.value) || (0xFF00...0xFF60).contains($0.value) }
    }

    /// Loads Vision's recognition models, so the first Shot doesn't pay for it.
    static func warmUp() async {
        guard let image = await MainActor.run(body: { sampleImage() }) else { return }
        let size = CGSize(width: image.width, height: image.height)
        async let quick = recognize(image, boundsSize: size, languageCorrection: false)
        async let corrected = recognize(ImagePreprocessor.prepare(image, pixelsPerPoint: 2), boundsSize: size, languageCorrection: true)
        _ = try? await (quick, corrected)
    }

    /// A small image with a word of Japanese in it, so the warm-up exercises the real models.
    @MainActor
    private static func sampleImage() -> CGImage? {
        let size = CGSize(width: 120, height: 40)
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(.white)
        context.fill(CGRect(origin: .zero, size: size))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        ("準備中" as NSString).draw(at: CGPoint(x: 8, y: 8), withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black])
        NSGraphicsContext.current = nil
        return context.makeImage()
    }
}
