// Renders the app icon: a green macOS squircle with a white circle in it.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let outputDirectory = URL(fileURLWithPath: "Slater/Assets.xcassets/AppIcon.appiconset")
let canvas: CGFloat = 1024

func renderMaster() -> CGImage {
    let context = CGContext(
        data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    // macOS icon geometry: the squircle is inset about 10% on each side, corner radius ≈ 22.4%.
    let inset = canvas * 0.1
    let square = CGRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
    let squircle = NSBezierPath(roundedRect: square, xRadius: square.width * 0.224, yRadius: square.height * 0.224)

    // Shadow, as macOS draws under its icons.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -canvas * 0.01), blur: canvas * 0.03, color: NSColor.black.withAlphaComponent(0.3).cgColor)
    NSColor(red: 0.18, green: 0.62, blue: 0.43, alpha: 1).setFill()
    squircle.fill()
    context.restoreGState()

    // A white circle, centered, half the squircle's width.
    let diameter = square.width * 0.5
    let circle = NSBezierPath(ovalIn: CGRect(x: square.midX - diameter / 2, y: square.midY - diameter / 2, width: diameter, height: diameter))
    NSColor.white.setFill()
    circle.fill()

    NSGraphicsContext.current = nil
    return context.makeImage()!
}

func scaled(_ image: CGImage, to pixels: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    return context.makeImage()!
}

let master = renderMaster()
var entries: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let image = scaled(master, to: points * scale)
        let rep = NSBitmapImageRep(cgImage: image)
        try! rep.representation(using: .png, properties: [:])!.write(to: outputDirectory.appendingPathComponent(name))
        entries.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: outputDirectory.appendingPathComponent("Contents.json"))
print("wrote \(entries.count) icon sizes to \(outputDirectory.path)")
