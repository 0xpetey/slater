import CoreGraphics

/// Converts between the coordinate spaces Slater works in:
/// - screen-local AppKit points: origin at the screen's bottom-left
/// - global AppKit points: origin at the main screen's bottom-left, spanning all screens
/// - Capture pixels: origin at the top-left, at the display's native scale
enum CoordinateMapper {
    /// The pixels in a screen's Capture that cover `rect`, rounded outward to whole pixels
    /// and clamped to the image.
    static func pixelRect(forLocalRect rect: CGRect, screenSize: CGSize, imageSize: CGSize) -> CGRect {
        let scaleX = imageSize.width / screenSize.width
        let scaleY = imageSize.height / screenSize.height
        let flipped = CGRect(
            x: rect.minX * scaleX,
            y: (screenSize.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        return flipped.integral.intersection(CGRect(origin: .zero, size: imageSize))
    }

    static func globalRect(forLocalRect rect: CGRect, screenFrame: CGRect) -> CGRect {
        rect.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
    }
}
