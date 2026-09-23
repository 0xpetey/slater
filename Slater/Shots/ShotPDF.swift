import AppKit
import CoreText

/// One PDF for a Shot: the translated view, the original, and the Japanese ↔ English text.
/// Both images carry an invisible text layer, so the English is selectable and searchable over
/// the translated page and the Japanese over the original, as in a scanned, OCR'd document.
@MainActor
enum ShotPDF {
    /// US Letter, in points.
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 36

    private static let titleFont = NSFont.boldSystemFont(ofSize: 16)
    private static let subtitleFont = NSFont.systemFont(ofSize: 11)
    private static let bodyFont = NSFont.systemFont(ofSize: 11)

    static func make(shot: Shot, translatedImage: CGImage, title: String) -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return Data() }
        let pointsPerPixel = shot.screenRect.width / CGFloat(shot.image.width)
        let translations = shot.translations

        // Page 1: the translation as shown, with the English selectable over each patch.
        imagePage(context, title: title, subtitle: "Translated with the \(shot.displayedModel.title) model", image: translatedImage) { drawnWidth, origin in
            let scale = drawnWidth / shot.screenRect.width
            for patch in shot.patches {
                guard let english = translations[patch.index] else { continue }
                invisibleText(english, in: patch.frame, scale: scale, origin: origin, imageHeight: shot.screenRect.height, context: context)
            }
        }

        // Page 2: the original, with the Japanese selectable over each Block.
        imagePage(context, title: title, subtitle: "Original", image: shot.image) { drawnWidth, origin in
            let scale = drawnWidth / shot.screenRect.width
            for index in shot.japaneseBlockIndices {
                let bounds = shot.blocks[index].bounds
                let frame = CGRect(x: bounds.minX * pointsPerPixel, y: bounds.minY * pointsPerPixel, width: bounds.width * pointsPerPixel, height: bounds.height * pointsPerPixel)
                invisibleText(shot.blocks[index].text, in: frame, scale: scale, origin: origin, imageHeight: shot.screenRect.height, context: context)
            }
        }

        // Pages 3 and on: the text, flowing across as many pages as it needs.
        textPages(context, title: title, text: textBody(shot: shot, translations: translations))

        context.closePDF()
        return data as Data
    }

    /// A page with a heading and the image scaled to fit, then `overlay` for its text layer,
    /// given the scale from Shot points to page points and the image's bottom-left corner.
    /// `overlay` receives the drawn image's width in page points and its bottom-left corner.
    private static func imagePage(_ context: CGContext, title: String, subtitle: String, image: CGImage, overlay: (CGFloat, CGPoint) -> Void) {
        context.beginPDFPage(nil)
        let headingBottom = drawHeading(context, title: title, subtitle: subtitle)
        let available = CGRect(x: margin, y: margin, width: pageSize.width - 2 * margin, height: headingBottom - 12 - margin)
        let imageSize = CGSize(width: image.width, height: image.height)
        let fit = min(available.width / imageSize.width, available.height / imageSize.height, 1)
        let drawn = CGRect(x: available.minX, y: available.maxY - imageSize.height * fit, width: imageSize.width * fit, height: imageSize.height * fit)
        context.draw(image, in: drawn)
        // The overlay's frames are in Shot points (the image's pixels ÷ its pixels per point), so
        // hand it the scale from those to page points, which the caller computes from the Shot.
        overlay(drawn.width, drawn.origin)
        context.endPDFPage()
    }

    /// Draws `text` so it can't be seen but can be selected and searched, sized to span `frame`
    /// (in Shot points, origin top-left) on a page where the image occupies `scale` × Shot points
    /// from `origin`.
    private static func invisibleText(_ text: String, in frame: CGRect, scale: CGFloat, origin: CGPoint, imageHeight: CGFloat, context: CGContext) {
        let target = CGRect(
            x: origin.x + frame.minX * scale,
            y: origin.y + (imageHeight - frame.maxY) * scale,
            width: frame.width * scale,
            height: frame.height * scale
        )
        let probe = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 10)]))
        let probeWidth = max(1, CTLineGetTypographicBounds(probe, nil, nil, nil))
        let fontSize = max(2, min(10 * target.width / probeWidth, target.height * 0.9))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: fontSize)]))
        context.saveGState()
        context.setTextDrawingMode(.invisible)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: target.minX, y: target.minY + (target.height - fontSize) / 2 + fontSize * 0.2)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Japanese, then English, for every Japanese Block.
    private static func textBody(shot: Shot, translations: [Int: String]) -> NSAttributedString {
        let body = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 4
        for index in shot.japaneseBlockIndices {
            let block = shot.blocks[index]
            if block.isLowConfidence {
                body.append(NSAttributedString(string: "⚠︎ Low OCR confidence: check against the original\n", attributes: [.font: bodyFont, .foregroundColor: NSColor.orange, .paragraphStyle: paragraph]))
            }
            body.append(NSAttributedString(string: block.text + "\n", attributes: [.font: bodyFont, .foregroundColor: NSColor.black, .paragraphStyle: paragraph]))
            let spaced = NSMutableParagraphStyle()
            spaced.paragraphSpacing = 14
            body.append(NSAttributedString(string: (translations[index] ?? "Not translated") + "\n", attributes: [.font: bodyFont, .foregroundColor: NSColor.darkGray, .paragraphStyle: spaced]))
        }
        return body
    }

    private static func textPages(_ context: CGContext, title: String, text: NSAttributedString) {
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        var start = 0
        repeat {
            context.beginPDFPage(nil)
            let headingBottom = drawHeading(context, title: title, subtitle: "Japanese and English")
            let path = CGPath(rect: CGRect(x: margin, y: margin, width: pageSize.width - 2 * margin, height: headingBottom - 12 - margin), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
            context.textMatrix = .identity
            CTFrameDraw(frame, context)
            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            start = visible.location + visible.length
        } while start < text.length
    }

    /// The title and subtitle at the top of a page; returns the y below them.
    private static func drawHeading(_ context: CGContext, title: String, subtitle: String) -> CGFloat {
        var y = pageSize.height - margin
        context.textMatrix = .identity
        for (string, font) in [(title, titleFont), (subtitle, subtitleFont)] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: font == titleFont ? NSColor.black : NSColor.darkGray]))
            y -= font.ascender
            context.textPosition = CGPoint(x: margin, y: y)
            CTLineDraw(line, context)
            y += font.descender - 4
        }
        return y
    }
}
