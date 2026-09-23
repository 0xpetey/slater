import AppKit

/// Where each Japanese Block's translation patch goes in a Shot window, and what color it is.
struct Patch: Identifiable, Equatable {
    /// Index into the Shot's Blocks.
    let index: Int
    /// In the Shot window's points, origin top-left.
    let frame: CGRect
    /// The size of the Block's original characters, in points: a Line's height, or a
    /// column's width for vertical writing.
    let lineHeight: CGFloat
    let background: ColorSampler.RGB
    /// Vertical writing: the translation may be turned sideways to fit a narrow column.
    let isVertical: Bool

    var id: Int { index }
}

enum ShotLayout {
    /// Patches extend this far past the OCR bounds, in points, to cover glyph edges.
    static let outset: CGFloat = 1.5

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
            // Vertical columns are already long, and the space beside them is the next column.
            let extra = block.isVertical ? 0 : CGFloat(clearWidth(bounds, color))
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
                lineHeight: (block.isVertical ? block.lines[0].bounds.width : block.lines[0].bounds.height) * pointsPerPixel,
                background: color,
                isVertical: block.isVertical
            )
        }
    }
}
