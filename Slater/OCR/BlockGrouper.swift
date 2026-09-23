import CoreGraphics

/// Merges Lines into Blocks. Lines merge only when stacked: side-by-side text such as
/// table cells, form fields and columns always stays in separate Blocks. Stacked Lines also
/// stay apart when a rule is drawn between them (table rows) or only one of them is Japanese.
enum BlockGrouper {
    /// Largest vertical gap between stacked Lines, as a fraction of line height. Paragraphs
    /// with a CSS line height of 1.8 measure about 0.5.
    static let maximumGap: CGFloat = 0.8
    /// Lines of very different heights (a heading over body text) don't merge.
    static let heightRatioRange: ClosedRange<CGFloat> = 0.6...1.6
    /// A Line ending in one of these closes its Block, even if the next Line is close.
    static let sentenceEndings: Set<Character> = ["。", "！", "？"]

    /// `hasRule` reports whether a gap between two Lines, in the crop's pixels, contains a
    /// horizontal rule. Use `RuleDetector` for real captures.
    static func group(_ lines: [Line], hasRule: (CGRect) -> Bool = { _ in false }) -> [Block] {
        var blocks: [Block] = []
        let ordered = lines.sorted { ($0.bounds.minY, $0.bounds.minX) < ($1.bounds.minY, $1.bounds.minX) }
        for line in ordered {
            let candidates = blocks.indices.filter { continues(blocks[$0], with: line, hasRule: hasRule) }
            // If several Blocks could continue, the closest one above wins.
            if let index = candidates.min(by: { gap(blocks[$0], line) < gap(blocks[$1], line) }) {
                blocks[index].lines.append(line)
            } else {
                blocks.append(Block(lines: [line]))
            }
        }
        return blocks.sorted { ($0.bounds.minY, $0.bounds.minX) < ($1.bounds.minY, $1.bounds.minX) }
    }

    private static func continues(_ block: Block, with line: Line, hasRule: (CGRect) -> Bool) -> Bool {
        guard let last = block.lines.last else { return false }
        if let ending = last.text.last, sentenceEndings.contains(ending) { return false }
        if Block.containsJapanese(last.text) != Block.containsJapanese(line.text) { return false }

        let height = max(last.bounds.height, line.bounds.height)
        let ratio = line.bounds.height / last.bounds.height
        let overlapsHorizontally = line.bounds.minX < last.bounds.maxX && last.bounds.minX < line.bounds.maxX
        let gap = line.bounds.minY - last.bounds.maxY
        guard heightRatioRange.contains(ratio), overlapsHorizontally,
              gap >= -0.3 * height, gap <= maximumGap * height
        else { return false }

        let sharedMinX = max(last.bounds.minX, line.bounds.minX)
        let sharedMaxX = min(last.bounds.maxX, line.bounds.maxX)
        let between = CGRect(x: sharedMinX, y: last.bounds.maxY, width: sharedMaxX - sharedMinX, height: gap)
        return gap <= 0 || !hasRule(between)
    }

    private static func gap(_ block: Block, _ line: Line) -> CGFloat {
        line.bounds.minY - (block.lines.last?.bounds.maxY ?? 0)
    }
}
