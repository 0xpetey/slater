import AppKit

/// Where each Japanese Block's translation patch goes in a Shot window, and what color it is.
struct Patch: Identifiable, Equatable {
    /// Index into the Shot's Blocks.
    let index: Int
    /// In the Shot window's points, origin top-left.
    let frame: CGRect
    /// The height of one of the Block's original Lines, in points.
    let lineHeight: CGFloat
    let background: ColorSampler.RGB

    var id: Int { index }
}

enum ShotLayout {
    /// Patches extend this far past the OCR bounds, in points, to cover glyph edges.
    static let outset: CGFloat = 1.5

    @MainActor
    static func patches(for shot: Shot) -> [Patch] {
        let sampler = ColorSampler(image: shot.image)
        return patches(
            for: shot.blocks,
            indices: shot.japaneseBlockIndices,
            pointsPerPixel: shot.screenRect.width / CGFloat(shot.image.width),
            windowSize: shot.screenRect.size,
            background: sampler.background(around:),
            clearWidth: sampler.clearWidth(rightOf:background:)
        )
    }

    static func patches(
        for blocks: [Block],
        indices: [Int],
        pointsPerPixel: CGFloat,
        windowSize: CGSize,
        background: (CGRect) -> ColorSampler.RGB,
        clearWidth: (CGRect, ColorSampler.RGB) -> Int = { _, _ in 0 }
    ) -> [Patch] {
        let window = CGRect(origin: .zero, size: windowSize)
        let minimumHeight = ceil(NSFont.systemFont(ofSize: FitText.minimumSize).boundingRectForFont.height)
        return indices.map { index in
            let block = blocks[index]
            let bounds = block.bounds
            let color = background(bounds)
            // English is usually about twice as wide as the Japanese, so use any empty space to
            // the right. It stops at the next text or gridline, so no neighbor is covered.
            let extra = CGFloat(clearWidth(bounds, color))
            var frame = CGRect(
                x: bounds.minX * pointsPerPixel, y: bounds.minY * pointsPerPixel,
                width: (bounds.width + extra) * pointsPerPixel, height: bounds.height * pointsPerPixel
            ).insetBy(dx: -outset, dy: -outset)
            // Tiny text still gets one readable line at the minimum font size.
            if frame.height < minimumHeight {
                frame = frame.insetBy(dx: 0, dy: -(minimumHeight - frame.height) / 2)
                // Shift rather than clip, so the line stays whole at the window's edges.
                frame.origin.y = min(max(frame.minY, 0), windowSize.height - frame.height)
            }
            return Patch(
                index: index,
                frame: frame.intersection(window),
                lineHeight: (block.lines.first?.bounds.height ?? bounds.height) * pointsPerPixel,
                background: color
            )
        }
    }
}
