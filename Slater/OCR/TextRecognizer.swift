import CoreGraphics
import Vision

enum TextRecognizer {
    /// Reads the Lines in `image`, with bounds in `boundsSize` pixels (origin top-left).
    /// Pass the original crop's size when `image` is an upscaled copy of it.
    static func recognize(_ image: CGImage, boundsSize: CGSize) async throws -> [Line] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "ja-JP"), Locale.Language(identifier: "en-US")]
        // Slower, but turning it off caused misreads such as 未 for 末 on blurry scans.
        request.usesLanguageCorrection = true

        return try await request.perform(on: image).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return Line(text: candidate.string, bounds: observation.boundingBox.toImageCoordinates(boundsSize, origin: .upperLeft))
        }
    }
}
