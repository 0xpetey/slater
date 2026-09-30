import CoreGraphics
import CoreImage

/// Where a frame differs from the one before it, from the captured pixels themselves. The
/// capture excludes Slater's windows, so the overlay's own updates never register as change,
/// which ScreenCaptureKit's dirty rectangles couldn't promise.
struct FrameDiff: Sendable {
    /// One thumbnail pixel covers this many captured pixels on each axis.
    static let cell = 16
    /// How far a thumbnail pixel must move, out of 255, to count as changed.
    static let threshold = 24
    private static let context = CIContext()

    /// Grayscale thumbnail, row-major, `columns × rows`.
    let pixels: [UInt8]
    let columns: Int
    let rows: Int

    init(image: CGImage) {
        let columns = max(1, image.width / Self.cell)
        let rows = max(1, image.height / Self.cell)
        var pixels = [UInt8](repeating: 0, count: columns * rows)
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: columns, height: rows, bitsPerComponent: 8,
                bytesPerRow: columns, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
            context?.interpolationQuality = .low
            context?.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        }
        self.columns = columns
        self.rows = rows
        self.pixels = pixels
    }

    /// The thumbnail pixels that differ from `previous`, as a mask in the same layout, and the
    /// share of the frame they cover.
    func changes(since previous: FrameDiff?) -> (mask: [Bool], fraction: Double) {
        guard let previous, previous.columns == columns, previous.rows == rows else {
            return (Array(repeating: true, count: pixels.count), 1)
        }
        var mask = [Bool](repeating: false, count: pixels.count)
        var changed = 0
        for index in pixels.indices where abs(Int(pixels[index]) - Int(previous.pixels[index])) > Self.threshold {
            mask[index] = true
            changed += 1
        }
        return (mask, Double(changed) / Double(pixels.count))
    }

    /// Whether any changed thumbnail pixel lies within `frame`, given in the image's pixels
    /// with a top-left origin (the thumbnail is drawn bottom-up, so rows are flipped).
    static func mask(_ mask: [Bool], columns: Int, rows: Int, intersects frame: CGRect) -> Bool {
        let minColumn = max(0, Int(frame.minX) / cell), maxColumn = min(columns - 1, Int(frame.maxX) / cell)
        let minRow = max(0, Int(frame.minY) / cell), maxRow = min(rows - 1, Int(frame.maxY) / cell)
        guard minColumn <= maxColumn, minRow <= maxRow else { return false }
        for row in minRow...maxRow {
            let flippedRow = rows - 1 - row
            for column in minColumn...maxColumn where mask[flippedRow * columns + column] {
                return true
            }
        }
        return false
    }
}
