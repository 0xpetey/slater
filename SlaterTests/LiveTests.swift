import CoreGraphics
import Foundation
import Testing
@testable import Slater

struct ChangeDetectorTests {
    /// A 50 × 20 grid of cells.
    private let columns = 50
    private let rows = 20

    private func mask(rows range: Range<Int> = 0..<0, columns columnRange: Range<Int> = 0..<0) -> CellMask {
        CellMask(cells: (0..<(columns * rows)).map { range.contains($0 / columns) && columnRange.contains($0 % columns) }, columns: columns, rows: rows)
    }

    private func union(_ a: CellMask, _ b: CellMask) -> CellMask {
        var result = a
        result.formUnion(b)
        return result
    }

    private var slide: CellMask { mask(rows: 2..<12, columns: 5..<45) }
    private var tile: CellMask { mask(rows: 0..<6, columns: 0..<10) }
    private var bullet: CellMask { mask(rows: 15..<17, columns: 10..<40) }

    @Test func aSlideChangeIsReadOnTheFirstQuietFrame() {
        var detector = ChangeDetector(framesPerSecond: 2)
        #expect(detector.observe(mask()) == .init(verdict: .quiet, moved: mask()))
        let observation = detector.observe(slide)
        #expect(observation.verdict == .changed)
        #expect(observation.moved.cells[5 * columns + 10] && !observation.moved.cells[0])
        #expect(detector.observe(mask()).verdict == .settled)
        #expect(detector.observe(mask()).verdict == .quiet)
    }

    @Test func aTransitionWaitsUntilItStops() {
        var detector = ChangeDetector(framesPerSecond: 2)
        _ = detector.observe(mask())
        for _ in 0..<2 {
            #expect(detector.observe(slide).verdict == .changed)
        }
        #expect(detector.observe(mask()).verdict == .settled)
    }

    @Test func videoStopsCountingButStillMarksStalePatches() {
        var detector = ChangeDetector(framesPerSecond: 2)
        _ = detector.observe(mask())
        // A camera tile changes every frame: a pass once it's noticed, then nothing.
        var settled = 0
        for _ in 0..<10 {
            let observation = detector.observe(tile)
            if observation.verdict == .settled { settled += 1 }
            #expect(observation.moved == tile)
        }
        #expect(settled == 1)
        // A bullet appearing elsewhere still counts while the tile keeps moving.
        let observation = detector.observe(union(tile, bullet))
        #expect(observation.verdict == .changed)
        #expect(observation.moved == union(tile, bullet))
        #expect(detector.observe(tile).verdict == .settled)
    }

    @Test func aCameraTileStaysVideoThroughAStillMoment() {
        var detector = ChangeDetector(framesPerSecond: 2)
        _ = detector.observe(mask())
        for _ in 0..<60 { _ = detector.observe(tile) }
        // Ten seconds of stillness, then movement again: nothing to read.
        for _ in 0..<20 { #expect(detector.observe(mask()).verdict == .quiet) }
        #expect(detector.observe(tile).verdict == .quiet)
        #expect(detector.observe(mask()).verdict == .quiet)
    }

    @Test func aLongScrollIsReadSoonAfterItStops() {
        var detector = ChangeDetector(framesPerSecond: 2)
        _ = detector.observe(mask())
        // Scrolling for ten frames: read once when it turns into video, then ignored.
        var passes = 0
        for _ in 0..<10 where detector.observe(slide).verdict == .settled { passes += 1 }
        #expect(passes == 1)
        // Once it stops, the final position is read within a few seconds.
        var settledAfter: Int?
        for quietFrame in 1...30 where detector.observe(mask()).verdict == .settled {
            settledAfter = quietFrame
            break
        }
        #expect(settledAfter.map { $0 <= 10 } == true)
        // And only once.
        for _ in 0..<30 { #expect(detector.observe(mask()).verdict == .quiet) }
    }

    @Test func scatteredNoiseAndTinyChangesAreQuiet() {
        var detector = ChangeDetector(framesPerSecond: 2)
        _ = detector.observe(mask())
        // A caret or a clock: one cell, which doesn't even mark a patch stale.
        let caret = detector.observe(mask(rows: 3..<4, columns: 7..<8))
        #expect(caret == .init(verdict: .quiet, moved: mask()))
        // Capture noise: many cells, none next to each other.
        let noise = CellMask(cells: (0..<(columns * rows)).map { $0 % 7 == 0 && ($0 / columns) % 2 == 0 }, columns: columns, rows: rows)
        #expect(detector.observe(noise) == .init(verdict: .quiet, moved: mask()))
        #expect(detector.observe(mask()).verdict == .quiet)
    }
}

struct LiveStatusTests {
    @Test func captionsNameTheSourceLanguage() {
        #expect(LiveStatus.noSource("Japanese").caption == "No Japanese Detected")
        #expect(LiveStatus.updateDetected.caption == "Screen Update Detected")
        #expect(LiveStatus.processing.caption == "Processing")
        #expect(LiveStatus.done.caption == "Done")
    }
}

struct FrameDiffTests {
    private func image(topWhite: Bool) -> CGImage {
        let size = 64
        var data = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<(size / 2) where topWhite {
            for x in 0..<size {
                let offset = (y * size + x) * 4
                data[offset] = 255; data[offset + 1] = 255; data[offset + 2] = 255; data[offset + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
    }

    @Test func changesKeepTheImagesOrientation() {
        let changes = FrameDiff(image: image(topWhite: true)).changes(since: FrameDiff(image: image(topWhite: false)))
        #expect(changes.columns == 4 && changes.rows == 4)
        #expect(changes.fraction == 0.5)
        // The top half changed, in the image's own top-left coordinates.
        #expect(changes.intersects(CGRect(x: 0, y: 0, width: 64, height: 16)))
        #expect(!changes.intersects(CGRect(x: 0, y: 40, width: 64, height: 24)))
    }

    @Test func clustersDropLoneCells() {
        var mask = CellMask(cells: Array(repeating: false, count: 16), columns: 4, rows: 4)
        // A lone cell in the top-left corner and a three-cell line two rows below it.
        mask.cells[0] = true
        mask.cells[9] = true; mask.cells[10] = true; mask.cells[11] = true
        let clustered = mask.clustered()
        #expect(!clustered.cells[0] && !clustered.cells[9] && clustered.cells[10] && !clustered.cells[11])
    }
}
