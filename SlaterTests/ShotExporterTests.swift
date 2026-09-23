import CoreGraphics
import Foundation
import Testing
@testable import Slater

@MainActor
struct ShotExporterTests {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SlaterTests-\(UUID().uuidString)")
    private let image: CGImage = {
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
        return context.makeImage()!
    }()

    init() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func write(_ format: ShotExporter.Format) throws -> [String] {
        try ShotExporter.write(original: image, translated: image, markdown: "# Test\n", pdf: Data("%PDF".utf8), format: format, directory: directory, baseName: "Report")
            .map(\.lastPathComponent)
    }

    @Test func eachFormatWritesOnlyItsFiles() throws {
        #expect(try write(.pdf) == ["Report.pdf"])
        #expect(try write(.image) == ["Report-original.png", "Report-translated.png"])
        #expect(try write(.text) == ["Report.md"])
    }

    @Test func existingFilesAreNeverReplaced() throws {
        _ = try write(.text)
        #expect(try write(.pdf) == ["Report.pdf"])
        #expect(try write(.text) == ["Report 2.md"])
        _ = try write(.image)
        #expect(try write(.image) == ["Report 2-original.png", "Report 2-translated.png"])
    }

    @Test func markdownQuotesTheJapaneseAndFlagsLowConfidence() {
        let blocks = [
            Block(lines: [Line(text: "品番", bounds: CGRect(x: 0, y: 0, width: 10, height: 10))]),
            Block(lines: [Line(text: "AB-1024", bounds: CGRect(x: 0, y: 20, width: 10, height: 10))]),
            Block(lines: [Line(text: "担当者", bounds: CGRect(x: 0, y: 40, width: 10, height: 10), isLowConfidence: true)]),
        ]
        let shot = Shot(image: image, screenRect: .zero, blocks: blocks)
        shot.setTranslation("Item number", for: "品番", model: .fast)
        #expect(shot.markdown(title: "Report") == """
            # Report

            > 品番

            Item number

            > 担当者 ⚠️ Low OCR confidence: check against the original image

            _Not translated_

            """)
    }
}
