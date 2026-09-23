import CoreImage

/// Makes the image for the corrected OCR reading, which has to fail differently from the raw
/// one so that reconciling the two catches what either misses (ADR 0002).
enum ImagePreprocessor {
    /// On Retina captures, the second reading is the crop at half scale. Measured across six
    /// Japanese fonts and three sizes, Vision reads gothic fonts' 当 correctly at 1 px per point
    /// where it glues it to a neighbor at 2 px per point, and downscaling also crispens blur.
    static let retinaScale: CGFloat = 0.5
    /// On 1× captures, text is too small to shrink, so the second reading is upscaled to about
    /// this many pixels per point instead; that stopped Vision dropping characters in small text.
    static let targetPixelsPerPoint: CGFloat = 3

    private static let context = CIContext()

    /// `pixelsPerPoint` is the Capture's scale: 2 on Retina displays, 1 otherwise.
    static func prepare(_ image: CGImage, pixelsPerPoint: CGFloat) -> CGImage {
        var output = CIImage(cgImage: image)
        if pixelsPerPoint >= 2 {
            output = output.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: retinaScale])
        } else {
            output = output.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: targetPixelsPerPoint / pixelsPerPoint])
            // Grayscale and contrast rescued blurry scans at this scale.
            output = output.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 1.3,
            ])
        }
        return context.createCGImage(output, from: output.extent) ?? image
    }
}
