// Renders the app icon: a macOS squircle with a green gradient and the white lizard.
// Run from the repo root: swift scripts/make-icon.swift
//
// Note: Apple's SF Symbols license permits the symbols in app UI but not in app icons or
// logos, so this lizard is fine for a personal build and should be replaced with an original
// drawing before Slater is distributed.
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
    NSColor(red: 0.16, green: 0.55, blue: 0.40, alpha: 1).setFill()
    squircle.fill()
    context.restoreGState()

    // Gradient: lighter at the top, like a lizard's back in the sun.
    squircle.addClip()
    NSGradient(colors: [
        NSColor(red: 0.40, green: 0.80, blue: 0.58, alpha: 1),
        NSColor(red: 0.12, green: 0.52, blue: 0.38, alpha: 1),
    ])!.draw(in: square, angle: -90)

    // The lizard, rendered white by the symbol configuration, filling about 66% of the squircle.
    let configuration = NSImage.SymbolConfiguration(pointSize: square.width * 0.62, weight: .regular)
        .applying(.init(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "lizard.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(configuration)!
    let size = symbol.size
    let scale = min(square.width * 0.66 / size.width, square.height * 0.66 / size.height)
    let drawn = CGSize(width: size.width * scale, height: size.height * scale)
    let origin = CGPoint(x: square.midX - drawn.width / 2, y: square.midY - drawn.height / 2)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -canvas * 0.006), blur: canvas * 0.012, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    symbol.draw(in: CGRect(origin: origin, size: drawn))
    context.restoreGState()

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
