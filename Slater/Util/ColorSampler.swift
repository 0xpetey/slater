import CoreGraphics

/// Finds the background color around each Block, so its patch blends into the original.
struct ColorSampler {
    struct RGB: Equatable, Sendable {
        var red, green, blue: Double

        /// Relative luminance, 0 (black) to 1 (white).
        var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
    }

    /// How far outside the Block's bounds to sample, in pixels. Just clear of the glyphs.
    static let margin = 3

    private let width: Int
    private let height: Int
    private let pixels: [UInt8]

    init(image: CGImage) {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The median color of a thin ring just outside `bounds` (in pixels, origin top-left).
    /// The median ignores stray glyph edges and gridlines that touch the ring.
    func background(around bounds: CGRect) -> RGB {
        let ring = bounds.integral.insetBy(dx: -CGFloat(Self.margin), dy: -CGFloat(Self.margin))
        let minX = max(0, Int(ring.minX)), maxX = min(width - 1, Int(ring.maxX) - 1)
        let minY = max(0, Int(ring.minY)), maxY = min(height - 1, Int(ring.maxY) - 1)
        guard minX <= maxX, minY <= maxY else { return RGB(red: 1, green: 1, blue: 1) }

        var samples: [(Int, Int)] = []
        for x in minX...maxX { samples += [(x, minY), (x, maxY)] }
        for y in minY...maxY { samples += [(minX, y), (maxX, y)] }

        func median(_ channel: Int) -> Double {
            let values = samples.map { pixels[($0.1 * width + $0.0) * 4 + channel] }.sorted()
            return Double(values[values.count / 2]) / 255
        }
        return RGB(red: median(0), green: median(1), blue: median(2))
    }

    /// How many pixels of empty background lie to the right of `bounds` before the next text,
    /// gridline or image edge. Patches extend into this space instead of shrinking their text.
    func clearWidth(rightOf bounds: CGRect, background: RGB) -> Int {
        let firstRow = max(0, Int(bounds.minY))
        let endRow = min(height, Int(bounds.maxY.rounded(.up)))
        let start = Int(bounds.maxX.rounded(.up)) + Self.margin
        guard firstRow < endRow, start < width else { return 0 }
        let rows = firstRow..<endRow
        let target = [background.red, background.green, background.blue].map { $0 * 255 }

        for x in start..<width {
            let blocked = rows.contains { y in
                let offset = (y * width + x) * 4
                return (0..<3).contains { abs(Double(pixels[offset + $0]) - target[$0]) > Self.clearTolerance }
            }
            if blocked { return max(0, x - start) }
        }
        return width - start
    }

    /// How far a pixel may differ from the background, per channel out of 255, and still count
    /// as empty. Loose enough for scan noise, tight enough to stop at light gridlines.
    static let clearTolerance = 50.0
}
