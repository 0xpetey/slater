import CoreGraphics

/// Finds horizontal rules, such as spreadsheet gridlines and table borders, in the gap between
/// two Lines. Lines separated by a rule are different cells, however close together they are.
struct RuleDetector {
    /// How much darker than the gap's background a pixel row must be to count as a rule, out of 255.
    static let minimumDarkening = 12.0
    /// The share of a row's pixels that must be darker for it to count as a rule rather than a speck.
    static let minimumCoverage = 0.8

    private let width: Int
    private let height: Int
    private let pixels: [UInt8]

    /// `image` must be the crop the Lines' bounds refer to.
    init(image: CGImage) {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// `gap` is in the crop's pixels, origin top-left.
    func hasHorizontalRule(in gap: CGRect) -> Bool {
        let area = gap.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard area.width >= 1, area.height >= 1 else { return false }
        let columns = Int(area.minX)..<Int(area.maxX)
        let rows = Int(area.minY)..<Int(area.maxY)

        // The background is the brightest row's typical value; a rule is a row that's darker almost everywhere.
        let rowMeans = rows.map { row in
            Double(columns.reduce(0) { $0 + Int(pixels[row * width + $1]) }) / Double(columns.count)
        }
        guard let background = rowMeans.max() else { return false }
        return rows.contains { row in
            let dark = columns.count { Double(pixels[row * width + $0]) <= background - Self.minimumDarkening }
            return Double(dark) >= Self.minimumCoverage * Double(columns.count)
        }
    }
}
