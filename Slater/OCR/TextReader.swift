import CoreGraphics

/// Reads a crop twice and reconciles the two readings (ADR 0002).
///
/// The quick reading (raw image, no language correction) is about 2.4× faster and is what the
/// Shot shows first. The corrected reading (preprocessed image, language correction on) rescues
/// small text and poor scans, and verifies the quick reading once it lands. Vision's confidence
/// scores don't reveal either kind of failure, so disagreement between the two is the signal.
enum TextReader {
    /// Raw image, no language correction. Shown first.
    static func quickRead(_ crop: CGImage) async throws -> [Line] {
        try await TextRecognizer.recognize(crop, boundsSize: size(of: crop), languageCorrection: false)
    }

    /// Preprocessed image with language correction. Verifies and corrects the quick reading.
    /// `pixelsPerPoint` is the Capture's scale: 2 on Retina displays, 1 otherwise.
    static func correctedRead(_ crop: CGImage, pixelsPerPoint: CGFloat) async throws -> [Line] {
        try await TextRecognizer.recognize(
            ImagePreprocessor.prepare(crop, pixelsPerPoint: pixelsPerPoint),
            boundsSize: size(of: crop),
            languageCorrection: true
        )
    }

    /// Both readings, reconciled. The app shows the quick reading before the corrected one is
    /// in; this is for tests and for when the quick reading finds no Japanese at all.
    static func read(_ crop: CGImage, pixelsPerPoint: CGFloat) async throws -> [Line] {
        async let corrected = correctedRead(crop, pixelsPerPoint: pixelsPerPoint)
        let quick = try await quickRead(crop)
        return reconcile(quick: quick, corrected: try await corrected)
    }

    /// Pairs up the Lines that cover the same text in each reading. Where the readings agree
    /// the Line is trusted. Where they differ, the longer text wins, because dropped characters
    /// are the usual failure; a tie goes to the corrected reading, whose misreads are rarer.
    /// Either way the Line is marked low-confidence.
    static func reconcile(quick: [Line], corrected: [Line]) -> [Line] {
        let all = quick.map { ($0, true) } + corrected.map { ($0, false) }
        var clusters = UnionFind(count: all.count)
        for i in all.indices {
            for j in all.indices where j > i && coversSameText(all[i].0, all[j].0) {
                clusters.union(i, j)
            }
        }

        return Dictionary(grouping: all.indices, by: { clusters.find($0) }).values.map { members in
            let lines = members.map { all[$0] }
            let quickText = joined(lines.filter { $0.1 }.map(\.0))
            let correctedText = joined(lines.filter { !$0.1 }.map(\.0))
            let bounds = lines.dropFirst().reduce(lines[0].0.bounds) { $0.union($1.0.bounds) }
            let text = quickText.count > correctedText.count ? quickText : correctedText
            return Line(text: text, bounds: bounds, isLowConfidence: quickText != correctedText)
        }
        .sorted { ($0.bounds.minY, $0.bounds.minX) < ($1.bounds.minY, $1.bounds.minX) }
    }

    private static func size(of image: CGImage) -> CGSize {
        CGSize(width: image.width, height: image.height)
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
