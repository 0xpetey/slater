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
        try ShotExporter.write(original: image, translated: image, markdown: "# Test\n", format: format, directory: directory, baseName: "Report")
            .map(\.lastPathComponent)
    }

    @Test func imageAndTextWritesThreeFilesSideBySide() throws {
        #expect(try write(.imageAndText) == ["Report-original.png", "Report-translated.png", "Report.md"])
    }

    @Test func eachFormatWritesOnlyItsFiles() throws {
        #expect(try write(.image) == ["Report-original.png", "Report-translated.png"])
        #expect(try write(.text) == ["Report.md"])
    }

    @Test func existingFilesAreNeverReplaced() throws {
        _ = try write(.text)
        #expect(try write(.imageAndText) == ["Report 2-original.png", "Report 2-translated.png", "Report 2.md"])
    }

    @Test func markdownQuotesTheJapaneseAndFlagsLowConfidence() {
        let blocks = [
            Block(lines: [Line(text: "品番", bounds: CGRect(x: 0, y: 0, width: 10, height: 10))]),
            Block(lines: [Line(text: "AB-1024", bounds: CGRect(x: 0, y: 20, width: 10, height: 10))]),
            Block(lines: [Line(text: "担当者", bounds: CGRect(x: 0, y: 40, width: 10, height: 10), isLowConfidence: true)]),
        ]
        let shot = Shot(image: image, screenRect: .zero, blocks: blocks)
        shot.setTranslation("Item number", for: "品番")
        #expect(shot.markdown(title: "Report") == """
            # Report

            > 品番

            Item number

            > 担当者 ⚠️ Low OCR confidence: check against the original image

            _Not translated_

            """)
    }
}
