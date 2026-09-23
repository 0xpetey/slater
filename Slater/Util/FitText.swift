import AppKit

/// Picks the largest font size that fits a translation into its Block's box. Below the
/// minimum size the text is truncated instead, and the full translation is shown on hover.
enum FitText {
    static let minimumSize: CGFloat = 10
    static let maximumSize: CGFloat = 28
    /// Horizontal padding inside a patch, per side, in points.
    static let padding: CGFloat = 2

    struct Fit: Equatable {
        var fontSize: CGFloat
        /// The text doesn't fit even at the minimum size, so it's cut off with "…".
        var isTruncated: Bool
        /// How many lines fit in the box at `fontSize`.
        var lineLimit: Int
    }

    /// `lineHeight` is the height of one of the Block's original Lines, which caps the font
    /// size so a short translation doesn't balloon to fill a tall box.
    static func fit(_ text: String, in size: CGSize, lineHeight: CGFloat) -> Fit {
        let width = max(1, size.width - 2 * padding)
        let largest = min(maximumSize, max(minimumSize, lineHeight * 0.8))

        var low = minimumSize, high = largest
        guard fits(text, width: width, height: size.height, fontSize: low) else {
            let lines = max(1, Int(size.height / lineHeightOf(fontSize: minimumSize)))
            return Fit(fontSize: minimumSize, isTruncated: true, lineLimit: lines)
        }
        // Binary search to the nearest half point.
        while high - low > 0.5 {
            let middle = (low + high) / 2
            if fits(text, width: width, height: size.height, fontSize: middle) { low = middle } else { high = middle }
        }
        if fits(text, width: width, height: size.height, fontSize: high) { low = high }
        let lines = max(1, Int(size.height / lineHeightOf(fontSize: low)))
        return Fit(fontSize: low, isTruncated: false, lineLimit: lines)
    }

    static func font(ofSize size: CGFloat) -> NSFont {
        .systemFont(ofSize: size)
    }

    private static func fits(_ text: String, width: CGFloat, height: CGFloat, fontSize: CGFloat) -> Bool {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font(ofSize: fontSize)]
        )
        return ceil(bounds.height) <= height && ceil(bounds.width) <= width
    }

    private static func lineHeightOf(fontSize: CGFloat) -> CGFloat {
        let font = font(ofSize: fontSize)
        return ceil(font.ascender - font.descender + font.leading)
    }
}
