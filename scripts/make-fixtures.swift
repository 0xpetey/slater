// Generates the OCR test images in SlaterTests/Fixtures.
// Run from the repo root: swift scripts/make-fixtures.swift
import AppKit
import CoreImage
import CoreText

let outputDirectory = URL(fileURLWithPath: "SlaterTests/Fixtures")

func render(_ name: String, size: CGSize, scale: CGFloat = 2, draw: (CGContext) -> Void) -> CGImage {
    let context = CGContext(
        data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: scale, y: scale)
    // Flip so drawing code uses a top-left origin, like a screen.
    context.translateBy(x: 0, y: size.height)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(.white)
    context.fill(CGRect(origin: .zero, size: size))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    draw(context)
    NSGraphicsContext.current = nil
    return context.makeImage()!
}

func text(_ string: String, at point: CGPoint, size: CGFloat = 14, weight: NSFont.Weight = .regular) {
    let font = NSFont(name: weight == .bold ? "HiraginoSans-W6" : "HiraginoSans-W3", size: size)!
    (string as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: NSColor.black])
}

func save(_ image: CGImage, _ name: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: outputDirectory.appendingPathComponent(name))
    print("wrote \(name) \(image.width)×\(image.height)")
}

// A paragraph wrapped mid-sentence, then a second paragraph.
let paragraph = render("paragraph", size: CGSize(width: 420, height: 120)) { _ in
    text("来週の会議は、仕様変更の影響を確認するため", at: CGPoint(x: 16, y: 14))
    text("に延期されました。", at: CGPoint(x: 16, y: 34))
    text("資料は金曜日までに共有してください。", at: CGPoint(x: 16, y: 70))
}
save(paragraph, "paragraph.png")

// A spreadsheet: side-by-side cells, a wrapped cell, numbers and English.
let table = render("table", size: CGSize(width: 520, height: 130)) { context in
    let columns: [CGFloat] = [10, 110, 170, 260, 510]
    let rows: [CGFloat] = [10, 36, 62, 106]
    context.setStrokeColor(NSColor.gray.cgColor)
    context.setLineWidth(0.5)
    for x in columns { context.stroke(CGRect(x: x, y: rows.first!, width: 0, height: rows.last! - rows.first!)) }
    for y in rows { context.stroke(CGRect(x: columns.first!, y: y, width: columns.last! - columns.first!, height: 0)) }
    let cells: [[String]] = [
        ["品番", "数量", "単価", "備考"],
        ["AB-1024", "50", "¥1,200", "Rush order"],
        ["部品A", "12", "¥800", "仕様変更のため、"],
    ]
    for (row, values) in cells.enumerated() {
        for (column, value) in values.enumerated() {
            text(value, at: CGPoint(x: columns[column] + 6, y: rows[row] + 5), size: 13, weight: row == 0 ? .bold : .regular)
        }
    }
    text("再見積もりが必要です。", at: CGPoint(x: columns[3] + 6, y: rows[2] + 23), size: 13)
}
save(table, "table.png")

// A web-style paragraph with a generous line height (1.8), which must still merge.
let airy = render("airy", size: CGSize(width: 360, height: 90)) { _ in
    text("お問い合わせいただいた件について、担当部署で", at: CGPoint(x: 12, y: 12))
    text("確認のうえ、改めてご連絡いたします。", at: CGPoint(x: 12, y: 12 + 14 * 1.8))
}
save(airy, "airy.png")

// A bordered list where every cell is Japanese, so only the gridlines keep rows apart.
let roster = render("roster", size: CGSize(width: 260, height: 90)) { context in
    let rows: [CGFloat] = [8, 30, 52, 74]
    context.setStrokeColor(NSColor.lightGray.cgColor)
    context.setLineWidth(0.5)
    for y in rows { context.stroke(CGRect(x: 8, y: y, width: 240, height: 0)) }
    for x: CGFloat in [8, 110, 248] { context.stroke(CGRect(x: x, y: 8, width: 0, height: 66)) }
    for (row, values) in [["担当者", "部署"], ["田中", "営業部"], ["佐藤", "開発部"]].enumerated() {
        text(values[0], at: CGPoint(x: 14, y: rows[row] + 4), size: 13)
        text(values[1], at: CGPoint(x: 116, y: rows[row] + 4), size: 13)
    }
}
save(roster, "roster.png")

// Vertical writing (縦書き): columns read top to bottom, right to left. The first sentence
// wraps across three columns; the fourth column is a separate sentence.
func verticalText(_ columns: [String], in rect: CGRect, context: CGContext, fontSize: CGFloat = 16) {
    let attributed = NSAttributedString(string: columns.joined(separator: "\n"), attributes: [
        .font: CTFontCreateWithName("HiraginoSans-W3" as CFString, fontSize, nil),
        .verticalGlyphForm: true,
        .foregroundColor: NSColor.black.cgColor,
    ])
    let framesetter = CTFramesetterCreateWithAttributedString(attributed)
    let frame = CTFramesetterCreateFrame(
        framesetter, CFRange(), CGPath(rect: rect, transform: nil),
        [kCTFrameProgressionAttributeName: CTFrameProgression.rightToLeft.rawValue] as CFDictionary
    )
    // Core Text draws with a bottom-left origin, so undo the top-left flip for this call.
    context.saveGState()
    context.translateBy(x: 0, y: rect.maxY + rect.minY)
    context.scaleBy(x: 1, y: -1)
    CTFrameDraw(frame, context)
    context.restoreGState()
}

let vertical = render("vertical", size: CGSize(width: 140, height: 260)) { context in
    verticalText(["本契約の内容は、両当事者の", "書面による合意なしに変更", "できないものとする。", "納期は十月十五日です。"],
                 in: CGRect(x: 10, y: 10, width: 120, height: 240), context: context)
}
save(vertical, "vertical.png")

// Gothic fonts' 当: Vision glues it to a neighbor at Retina scale (ADR 0002).
let tou = render("tou", size: CGSize(width: 340, height: 100)) { _ in
    text("担当者は営業部の田中です。", at: CGPoint(x: 12, y: 12), size: 13)
    text("当社の該当製品は本日出荷済みです。", at: CGPoint(x: 12, y: 40), size: 13)
    text("本当に当日中に対応します。", at: CGPoint(x: 12, y: 68), size: 13)
}
save(tou, "tou.png")

// Small UI text at 1× scale.
let small = render("small", size: CGSize(width: 300, height: 40), scale: 1) { _ in
    text("保存されていない変更があります。", at: CGPoint(x: 8, y: 12), size: 11)
}
save(small, "small.png")

// A poor scan: the paragraph rotated 2°, blurred, noisy and low contrast on grey paper.
let ciContext = CIContext()
var scan = CIImage(cgImage: paragraph)
scan = scan.transformed(by: CGAffineTransform(rotationAngle: 2 * .pi / 180))
scan = scan.applyingGaussianBlur(sigma: 1.4)
scan = scan.applyingFilter("CIColorControls", parameters: ["inputContrast": 0.45, "inputBrightness": -0.08])
let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
    .applyingFilter("CIColorControls", parameters: ["inputSaturation": 0, "inputContrast": 0.25])
    .cropped(to: scan.extent)
scan = noise.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: scan])
let background = CIImage(color: CIColor(red: 0.86, green: 0.85, blue: 0.82)).cropped(to: scan.extent)
scan = scan.composited(over: background)
save(ciContext.createCGImage(scan, from: scan.extent)!, "scan.png")
