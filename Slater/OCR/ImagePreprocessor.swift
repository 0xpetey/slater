import CoreImage

/// Prepares a crop for OCR. Measured against the test fixtures: upscaling stops Vision
/// dropping characters in small text, and grayscale plus contrast rescues blurry scans.
enum ImagePreprocessor {
    /// Upscale until text has about this many pixels per point.
    static let targetPixelsPerPoint: CGFloat = 3

    private static let context = CIContext()

    /// `pixelsPerPoint` is the Capture's scale: 2 on Retina displays, 1 otherwise.
    static func prepare(_ image: CGImage, pixelsPerPoint: CGFloat) -> CGImage {
        var output = CIImage(cgImage: image)
        let scale = max(1, targetPixelsPerPoint / pixelsPerPoint)
        if scale > 1 {
            output = output.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale])
        }
        output = output.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0,
            kCIInputContrastKey: 1.3,
        ])
        return context.createCGImage(output, from: output.extent) ?? image
    }
}
