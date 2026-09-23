import AppKit
import CoreGraphics
import Vision

enum TextRecognizer {
    /// Reads the Lines in `image`, with bounds in `boundsSize` pixels (origin top-left).
    /// Pass the original crop's size when `image` is an upscaled copy of it.
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
            return Line(text: candidate.string, bounds: observation.boundingBox.toImageCoordinates(boundsSize, origin: .upperLeft))
        }
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
