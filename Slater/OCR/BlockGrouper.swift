import CoreGraphics

/// Merges Lines into Blocks. Lines merge only when stacked: side-by-side text such as
/// table cells, form fields and columns always stays in separate Blocks. Stacked Lines also
/// stay apart when a rule is drawn between them (table rows) or only one of them is Japanese.
/// Vertical writing is the same turned on its side: a column continues in the one to its left.
enum BlockGrouper {
    /// Largest gap between Lines that continue one another, as a fraction of line height (or
    /// column width). Paragraphs with a CSS line height of 1.8 measure about 0.5.
    static let maximumGap: CGFloat = 0.8
    /// Lines of very different sizes (a heading over body text) don't merge.
    static let heightRatioRange: ClosedRange<CGFloat> = 0.6...1.6
    /// A Line ending in one of these closes its Block, even if the next Line is close.
    static let sentenceEndings: Set<Character> = ["。", "！", "？"]

    /// `hasRule` reports whether a gap between two Lines, in the crop's pixels, contains a
    /// rule across it. Use `RuleDetector` for real captures.
    static func group(_ lines: [Line], hasRule: (CGRect) -> Bool = { _ in false }) -> [Block] {
        var blocks: [Block] = []
        // Visit Lines in reading order, so each one can only continue a Block that came before it:
        // top to bottom for horizontal writing, right to left for vertical columns.
        let ordered = lines.sorted { a, b in
            if a.isVertical && b.isVertical { return a.bounds.maxX > b.bounds.maxX }
            return (a.bounds.minY, a.bounds.minX) < (b.bounds.minY, b.bounds.minX)
        }
        for line in ordered {
            let candidates = blocks.indices.filter { continues(blocks[$0], with: line, hasRule: hasRule) }
            // If several Blocks could continue, the closest one wins.
            if let index = candidates.min(by: { gap(blocks[$0], line) < gap(blocks[$1], line) }) {
                blocks[index].lines.append(line)
            } else {
                blocks.append(Block(lines: [line]))
            }
        }
        return readingOrder(blocks)
    }

    /// Top to bottom, then left to right within a row. Blocks whose tops are within half a
    /// line of each other share a row, since table cells in one row rarely align exactly.
    /// Mostly vertical writing reads column by column instead, right to left.
    static func readingOrder(_ blocks: [Block]) -> [Block] {
        if blocks.filter(\.isVertical).count * 2 > blocks.count {
            return blocks.sorted { ($0.bounds.maxX, -$0.bounds.minY) > ($1.bounds.maxX, -$1.bounds.minY) }
        }
        var rows: [[Block]] = []
        for block in blocks.sorted(by: { $0.bounds.minY < $1.bounds.minY }) {
            if let first = rows.last?.first,
               block.bounds.minY - first.bounds.minY < 0.5 * (first.lines.first?.bounds.height ?? first.bounds.height) {
                rows[rows.count - 1].append(block)
            } else {
                rows.append([block])
            }
        }
        return rows.flatMap { $0.sorted { $0.bounds.minX < $1.bounds.minX } }
    }

    private static func continues(_ block: Block, with line: Line, hasRule: (CGRect) -> Bool) -> Bool {
        guard let last = block.lines.last else { return false }
        if let ending = last.text.last, sentenceEndings.contains(ending) { return false }
        if Block.containsJapanese(last.text) != Block.containsJapanese(line.text) { return false }
        guard last.isVertical == line.isVertical else { return false }
        return last.isVertical ? continuesColumn(last, line, hasRule: hasRule) : continuesRow(last, line, hasRule: hasRule)
    }

    /// Horizontal writing continues on the next line down.
    private static func continuesRow(_ last: Line, _ line: Line, hasRule: (CGRect) -> Bool) -> Bool {
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

    /// Vertical writing continues in the next column to the left.
    private static func continuesColumn(_ last: Line, _ line: Line, hasRule: (CGRect) -> Bool) -> Bool {
        let width = max(last.bounds.width, line.bounds.width)
        let ratio = line.bounds.width / last.bounds.width
        let overlapsVertically = line.bounds.minY < last.bounds.maxY && last.bounds.minY < line.bounds.maxY
        let gap = last.bounds.minX - line.bounds.maxX
        guard heightRatioRange.contains(ratio), overlapsVertically,
              gap >= -0.3 * width, gap <= maximumGap * width
        else { return false }

        let sharedMinY = max(last.bounds.minY, line.bounds.minY)
        let sharedMaxY = min(last.bounds.maxY, line.bounds.maxY)
        let between = CGRect(x: line.bounds.maxX, y: sharedMinY, width: gap, height: sharedMaxY - sharedMinY)
        return gap <= 0 || !hasRule(between)
    }

    private static func gap(_ block: Block, _ line: Line) -> CGFloat {
        guard let last = block.lines.last else { return 0 }
        return last.isVertical ? last.bounds.minX - line.bounds.maxX : line.bounds.minY - last.bounds.maxY
    }
}
