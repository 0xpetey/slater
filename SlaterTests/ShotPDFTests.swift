import CoreGraphics
import PDFKit
import Testing
@testable import Slater

@MainActor
struct ShotPDFTests {
    @Test func pdfHasThreePagesAndSearchableTextOnEach() throws {
        let context = try #require(CGContext(data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        let image = try #require(context.makeImage())
        let blocks = [
            Block(lines: [Line(text: "品番", bounds: CGRect(x: 20, y: 20, width: 60, height: 30))]),
            Block(lines: [Line(text: "AB-1024", bounds: CGRect(x: 20, y: 80, width: 120, height: 30))]),
            Block(lines: [Line(text: "担当者", bounds: CGRect(x: 20, y: 140, width: 90, height: 30), isLowConfidence: true)]),
        ]
        let shot = Shot(image: image, screenRect: CGRect(x: 0, y: 0, width: 200, height: 100), blocks: blocks)
        shot.setTranslation("Item number", for: "品番", model: .fast)
        shot.setTranslation("Person in charge", for: "担当者", model: .fast)

        let document = try #require(PDFDocument(data: ShotPDF.make(shot: shot, translatedImage: image, title: "Report")))
        #expect(document.pageCount == 3)
        let pages = (0..<3).map { document.page(at: $0)?.string ?? "" }
        #expect(pages[0].contains("Report") && pages[0].contains("Fast model") && pages[0].contains("Item number"))
        #expect(pages[1].contains("Original") && pages[1].contains("品番") && pages[1].contains("担当者"))
        #expect(pages[2].contains("品番") && pages[2].contains("Item number") && pages[2].contains("Person in charge") && pages[2].contains("Low OCR confidence"))
        #expect(!pages[2].contains("AB-1024"))
    }
}
