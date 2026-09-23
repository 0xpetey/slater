import CoreGraphics

/// Reads a crop twice, raw and preprocessed, and reconciles the two readings (ADR 0002).
/// Preprocessing rescues small text and poor scans but makes Vision drop characters from
/// clean text, and Vision's confidence scores don't reveal either failure.
enum TextReader {
    /// `pixelsPerPoint` is the Capture's scale: 2 on Retina displays, 1 otherwise.
    static func read(_ crop: CGImage, pixelsPerPoint: CGFloat) async throws -> [Line] {
        let size = CGSize(width: crop.width, height: crop.height)
        async let raw = TextRecognizer.recognize(crop, boundsSize: size)
        async let prepared = TextRecognizer.recognize(
            ImagePreprocessor.prepare(crop, pixelsPerPoint: pixelsPerPoint),
            boundsSize: size
        )
        return try await reconcile(raw, prepared)
    }

    /// Pairs up the Lines that cover the same text in each reading. Where the readings agree
    /// the Line is trusted. Where they differ, the longer text wins, because dropped characters
    /// are the usual failure, and the Line is marked low-confidence.
    static func reconcile(_ raw: [Line], _ prepared: [Line]) -> [Line] {
        let all = raw.map { ($0, true) } + prepared.map { ($0, false) }
        var clusters = UnionFind(count: all.count)
        for i in all.indices {
            for j in all.indices where j > i && coversSameText(all[i].0, all[j].0) {
                clusters.union(i, j)
            }
        }

        return Dictionary(grouping: all.indices, by: { clusters.find($0) }).values.map { members in
            let lines = members.map { all[$0] }
            let rawText = joined(lines.filter { $0.1 }.map(\.0))
            let preparedText = joined(lines.filter { !$0.1 }.map(\.0))
            let bounds = lines.dropFirst().reduce(lines[0].0.bounds) { $0.union($1.0.bounds) }
            let text = preparedText.count > rawText.count ? preparedText : rawText
            return Line(text: text, bounds: bounds, isLowConfidence: rawText != preparedText)
        }
        .sorted { ($0.bounds.minY, $0.bounds.minX) < ($1.bounds.minY, $1.bounds.minX) }
    }

    /// On the same row (overlapping by at least half the shorter height) and overlapping horizontally.
    private static func coversSameText(_ a: Line, _ b: Line) -> Bool {
        let verticalOverlap = min(a.bounds.maxY, b.bounds.maxY) - max(a.bounds.minY, b.bounds.minY)
        let horizontalOverlap = min(a.bounds.maxX, b.bounds.maxX) - max(a.bounds.minX, b.bounds.minX)
        return verticalOverlap >= 0.5 * min(a.bounds.height, b.bounds.height) && horizontalOverlap > 0
    }

    /// One reading sometimes splits a line in two; join the pieces left to right.
    private static func joined(_ lines: [Line]) -> String {
        lines.sorted { $0.bounds.minX < $1.bounds.minX }.map(\.text).joined()
    }
}

private struct UnionFind {
    private var parent: [Int]

    init(count: Int) { parent = Array(0..<count) }

    mutating func find(_ i: Int) -> Int {
        if parent[i] != i { parent[i] = find(parent[i]) }
        return parent[i]
    }

    mutating func union(_ a: Int, _ b: Int) {
        parent[find(a)] = find(b)
    }
}
