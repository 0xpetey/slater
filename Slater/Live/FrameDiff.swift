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

    /// Grayscale thumbnail, row-major, `columns × rows`, row 0 at the top.
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

    /// The thumbnail pixels that differ from `previous`. Everything, if there is no comparable
    /// previous frame.
    func changes(since previous: FrameDiff?) -> CellMask {
        guard let previous, previous.columns == columns, previous.rows == rows else {
            return CellMask(cells: Array(repeating: true, count: pixels.count), columns: columns, rows: rows)
        }
        var cells = [Bool](repeating: false, count: pixels.count)
        for index in pixels.indices where abs(Int(pixels[index]) - Int(previous.pixels[index])) > Self.threshold {
            cells[index] = true
        }
        return CellMask(cells: cells, columns: columns, rows: rows)
    }
}

/// A yes or no per thumbnail cell, in `FrameDiff`'s layout.
struct CellMask: Equatable, Sendable {
    var cells: [Bool]
    let columns: Int
    let rows: Int

    static func none(like other: CellMask) -> CellMask {
        CellMask(cells: Array(repeating: false, count: other.cells.count), columns: other.columns, rows: other.rows)
    }

    /// Nothing marked, in the layout `FrameDiff` gives `image`.
    static func none(for image: CGImage) -> CellMask {
        let columns = max(1, image.width / FrameDiff.cell), rows = max(1, image.height / FrameDiff.cell)
        return CellMask(cells: Array(repeating: false, count: columns * rows), columns: columns, rows: rows)
    }

    var count: Int { cells.count { $0 } }
    var isEmpty: Bool { !cells.contains(true) }
    /// The share of the frame marked.
    var fraction: Double { Double(count) / Double(max(1, cells.count)) }

    mutating func formUnion(_ other: CellMask) {
        guard other.cells.count == cells.count else { return }
        for index in cells.indices where other.cells[index] {
            cells[index] = true
        }
    }

    /// Whether any marked cell lies within `frame`, given in the image's pixels with a top-left
    /// origin, like the thumbnail.
    func intersects(_ frame: CGRect) -> Bool {
        let cell = FrameDiff.cell
        let minColumn = max(0, Int(frame.minX) / cell), maxColumn = min(columns - 1, Int(frame.maxX) / cell)
        let minRow = max(0, Int(frame.minY) / cell), maxRow = min(rows - 1, Int(frame.maxY) / cell)
        guard minColumn <= maxColumn, minRow <= maxRow else { return false }
        for row in minRow...maxRow {
            for column in minColumn...maxColumn where cells[row * columns + column] {
                return true
            }
        }
        return false
    }

    /// The marked cells with at least two marked neighbors. Text comes in clusters; capture
    /// noise, a caret or a clock's digit is a cell or two on its own.
    func clustered() -> CellMask {
        var result = CellMask.none(like: self)
        for index in cells.indices where cells[index] {
            let row = index / columns, column = index % columns
            var neighbors = 0
            for dr in -1...1 {
                for dc in -1...1 where dr != 0 || dc != 0 {
                    let r = row + dr, c = column + dc
                    if r >= 0, r < rows, c >= 0, c < columns, cells[r * columns + c] { neighbors += 1 }
                }
            }
            if neighbors >= 2 { result.cells[index] = true }
        }
        return result
    }
}
