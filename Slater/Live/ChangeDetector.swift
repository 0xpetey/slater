import Foundation

/// Decides, from frame-to-frame change masks, when the screen has changed in a way worth a
/// new pass. Built for watching a shared Japanese presentation on a video call: the camera
/// tiles change every frame and must not count, a new slide (or a bullet appearing on one)
/// must, and the pass should wait for the slide's transition to settle.
struct ChangeDetector {
    struct Observation: Equatable {
        /// The screen has settled after a change worth reading: time for a pass.
        var settled: Bool
        /// Cells whose content moved this frame, in text-sized clusters or as video. Patches
        /// over them are stale.
        var moved: CellMask
    }

    /// A cell whose activity passes this is video: it changed in most recent frames. Changing
    /// every frame reaches it in three frames; every other frame in six.
    static let activeThreshold: Float = 0.4
    /// How quickly activity forgets: each frame keeps this much of the previous value.
    static let memory: Float = 0.8
    /// After video stops, its cells stay video for half as long as it played, up to this long,
    /// so a camera tile stays video through a still moment while a scroll that stopped is read
    /// a few seconds later.
    static let longestRest: Duration = .seconds(20)
    /// The share of the frame's cells that must be involved for a change to count. About a
    /// bullet line's worth at 16-pixel cells.
    static let significantFraction = 0.002

    private let longestRestFrames: Int
    private var activity: [Float] = []
    /// The first frame of the current stretch of video, per cell.
    private var videoSince: [Int] = []
    /// A cell is video before this frame.
    private var videoUntil: [Int] = []
    /// Whether the cell changed while it was video, since the last pass was called for. When
    /// such video stops, the pass it was hiding from is due.
    private var movedAsVideo: [Bool] = []
    private var frame = 0
    private(set) var isPending = false

    init(framesPerSecond: Int) {
        longestRestFrames = Int(Self.longestRest.components.seconds) * framesPerSecond
    }

    mutating func observe(_ changes: CellMask) -> Observation {
        frame += 1
        if activity.count != changes.cells.count {
            activity = Array(repeating: 0, count: changes.cells.count)
            videoSince = Array(repeating: 0, count: changes.cells.count)
            videoUntil = Array(repeating: 0, count: changes.cells.count)
            movedAsVideo = Array(repeating: false, count: changes.cells.count)
        }
        var fresh = CellMask.none(like: changes)
        var video = CellMask.none(like: changes)
        var stopped = CellMask.none(like: changes)
        for index in changes.cells.indices {
            let isVideo = videoUntil[index] > frame
            let changed = changes.cells[index]
            activity[index] = activity[index] * Self.memory + (changed ? 1 - Self.memory : 0)
            if activity[index] > Self.activeThreshold {
                if !isVideo { videoSince[index] = frame }
                videoUntil[index] = frame + 2 + min(longestRestFrames, (frame - videoSince[index]) / 2)
            } else if videoUntil[index] == frame, movedAsVideo[index] {
                stopped.cells[index] = true
            }
            if changed, isVideo {
                video.cells[index] = true
                movedAsVideo[index] = true
            } else if changed {
                fresh.cells[index] = true
            }
        }
        let significant = fresh.clustered()
        var moved = video.clustered()
        moved.formUnion(significant)

        if significant.fraction >= Self.significantFraction {
            isPending = true
            return Observation(settled: false, moved: moved)
        }
        if isPending {
            isPending = false
            return settle(moved: moved)
        }
        if stopped.clustered().fraction >= Self.significantFraction {
            return settle(moved: moved)
        }
        return Observation(settled: false, moved: moved)
    }

    private mutating func settle(moved: CellMask) -> Observation {
        for index in movedAsVideo.indices { movedAsVideo[index] = false }
        return Observation(settled: true, moved: moved)
    }
}
