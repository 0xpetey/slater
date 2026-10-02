import AppKit
@preconcurrency import KeyboardShortcuts
import Observation
import os
import ScreenCaptureKit

private let logger = Logger(subsystem: "app.slater", category: "live")

/// Experimental: translates every source-language Block on the whole screen as it changes,
/// built for watching a shared Japanese presentation on a video call.
///
/// Each display gets a low-rate capture stream and a click-through overlay. `ChangeDetector`
/// decides when the screen changed in a way worth a pass (a new slide, not a camera tile) and
/// when the change has settled; a pass is the quick OCR reading, shown at once, then the
/// corrected reading, both grouped as usual and translated with the active model, with
/// translations cached for the session so unchanged text is never sent twice. A hotkey freezes
/// the screen at the frame the patches belong to, so a slide can be read after the presenter
/// has moved on.
@MainActor
@Observable
final class LiveTranslationController {
    static let framesPerSecond = 2
    /// When this much of the screen has moved since the running pass's frame, the pass is
    /// abandoned for the one waiting, since most of what it would show is stale.
    static let restartFraction = 0.1

    private(set) var isRunning = false
    /// Every display is held at a frame, with its patches, until unfrozen.
    private(set) var isFrozen = false
    private let translator: Translator
    private var streams: [ScreenStream] = []
    private var loops: [DisplayLoop] = []
    private var tasks: [Task<Void, Never>] = []
    /// Translations made in this live session. Memory only, and dropped when live translation
    /// stops (ADR 0001).
    @ObservationIgnored private var cache: [String: String] = [:]

    init(translator: Translator) {
        self.translator = translator
    }

    func toggle() {
        if isRunning {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        // The overlays go up first: ScreenCaptureKit lists an app only while it has a window on
        // screen, and the overlays must be excluded from the capture, or their patches would
        // read as change and every pass would trigger the next.
        var loopsByDisplay: [CGDirectDisplayID: DisplayLoop] = [:]
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let overlay = LiveOverlayController(screen: screen)
            overlay.onClick = { [weak self] in
                if self?.isFrozen == true { self?.unfreeze() }
            }
            loopsByDisplay[displayID] = DisplayLoop(screen: screen, overlay: overlay)
        }
        loops = Array(loopsByDisplay.values)
        do {
            let (content, slater) = try await ScreenCapturer.contentListingSlater()
            guard !slater.isEmpty else { throw LiveError.notListed }
            for display in content.displays {
                guard let loop = loopsByDisplay[display.displayID] else { continue }
                let stream = try ScreenStream(display: display, excluding: slater, framesPerSecond: Self.framesPerSecond)
                streams.append(stream)
                tasks.append(Task { await self.run(stream, loop: loop) })
                try await stream.start()
            }
            logger.notice("Live translation started on \(self.streams.count) displays")
        } catch {
            logger.error("Live translation failed to start: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    private enum LiveError: LocalizedError {
        /// ScreenCaptureKit didn't list Slater, so its overlay couldn't be kept out of the capture.
        case notListed

        var errorDescription: String? { "Slater's windows couldn't be excluded from the capture" }
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        let streams = self.streams
        self.streams = []
        Task {
            for stream in streams { await stream.stop() }
        }
        for loop in loops {
            loop.pass?.cancel()
            loop.overlay.close()
        }
        loops = []
        cache.removeAll()
        isRunning = false
        isFrozen = false
        logger.notice("Live translation stopped")
    }

    func toggleFreeze() {
        guard isRunning else { return }
        if isFrozen {
            unfreeze()
        } else {
            freeze()
        }
    }

    /// Holds each display at the frame its patches belong to: the running pass's frame, which
    /// it finishes on; or, if the screen changed since the last pass, the newest frame, read
    /// right away instead of waiting for it to settle; or else the last pass's frame.
    private func freeze() {
        isFrozen = true
        let hint = KeyboardShortcuts.getShortcut(for: .freezeLiveTranslation).map { "Click or \($0) to resume" } ?? "Click to resume"
        for loop in loops {
            let frame: ScreenStream.Frame?
            if loop.pass != nil {
                frame = loop.passFrame
            } else if loop.pending != nil || loop.detector.isPending {
                frame = loop.latest
                loop.pending = frame
            } else {
                frame = loop.passFrame ?? loop.latest
            }
            guard let frame else { continue }
            loop.frozen = (frame, FrameDiff(image: frame.image))
            loop.stale = nil
            loop.overlay.freeze(frame.image, hint: hint)
            // Patches from a pass over this very frame are all good, whatever moved since.
            if loop.overlay.state.shot?.image === frame.image {
                loop.overlay.state.hiddenPatches = []
            }
            startPendingPass(loop)
        }
    }

    /// Lets the live screen through again. Whatever changed under the frozen frame is read at
    /// once; the detector keeps what it learned about video, so a camera tile isn't re-learned.
    private func unfreeze() {
        isFrozen = false
        for loop in loops {
            guard let frozen = loop.frozen else { continue }
            loop.frozen = nil
            loop.overlay.unfreeze()
            guard let latest = loop.latest, latest.image !== frozen.frame.image else { continue }
            let diff = FrameDiff(image: latest.image)
            loop.previous = diff
            let changes = diff.changes(since: frozen.diff).clustered()
            guard changes.fraction >= ChangeDetector.significantFraction else { continue }
            loop.overlay.hide { changes.intersects(Self.pixelFrame(of: $0, scale: latest.scale)) }
            loop.pending = latest
            startPendingPass(loop)
        }
    }

    /// Per-display state: detection runs at frame rate while a pass runs in the background,
    /// so video regions keep being learned and a new slide is noticed during a pass.
    @MainActor
    private final class DisplayLoop {
        let screen: NSScreen
        let overlay: LiveOverlayController
        var previous: FrameDiff?
        var detector = ChangeDetector(framesPerSecond: LiveTranslationController.framesPerSecond)
        var pass: Task<Void, Never>?
        /// The frame the running, or else the last, pass reads.
        var passFrame: ScreenStream.Frame?
        /// A settled frame waiting for the running pass to finish.
        var pending: ScreenStream.Frame?
        /// Cells that moved since the frame the running pass is reading. Patches the pass puts
        /// over them are stale, so they're held back until the next pass.
        var stale: CellMask?
        /// The newest frame, frozen or not.
        var latest: ScreenStream.Frame?
        /// While frozen: the frame on show, and its thumbnail for finding what changed once
        /// unfrozen.
        var frozen: (frame: ScreenStream.Frame, diff: FrameDiff)?

        init(screen: NSScreen, overlay: LiveOverlayController) {
            self.screen = screen
            self.overlay = overlay
        }
    }

    private func run(_ stream: ScreenStream, loop: DisplayLoop) async {
        for await frame in stream.frames {
            if Task.isCancelled { return }
            loop.latest = frame
            if loop.frozen != nil { continue }
            let diff = FrameDiff(image: frame.image)
            let changes = diff.changes(since: loop.previous)
            loop.previous = diff
            let observation = loop.detector.observe(changes)
            if observation.verdict == .changed, loop.overlay.state.status != .updateDetected {
                loop.overlay.state.status = .updateDetected
            }
            if !observation.moved.isEmpty {
                // Patches over what moved come off at once; the rest stay until the next pass lands.
                loop.overlay.hide { observation.moved.intersects(Self.pixelFrame(of: $0, scale: frame.scale)) }
                loop.stale?.formUnion(observation.moved)
                if let stale = loop.stale, stale.fraction >= Self.restartFraction {
                    loop.pass?.cancel()
                }
            }
            if observation.verdict == .settled {
                loop.pending = frame
            }
            startPendingPass(loop)
        }
    }

    /// Starts the pass on the waiting frame, if there is one and none is running.
    private func startPendingPass(_ loop: DisplayLoop) {
        guard loop.pass == nil, let frame = loop.pending else { return }
        loop.pending = nil
        loop.passFrame = frame
        // Nothing moves under a frozen frame.
        loop.stale = loop.frozen == nil ? CellMask.none(for: frame.image) : nil
        loop.overlay.state.status = .processing
        loop.pass = Task { [weak self] in
            let outcome = await self?.process(frame, loop: loop)
            loop.pass = nil
            loop.stale = nil
            // An abandoned pass leaves the badge on the change that abandoned it, and a
            // pending frame means the next pass is about to start.
            guard loop.pending == nil, let self, let outcome else { return }
            switch outcome {
            case .translated: loop.overlay.state.status = .done
            case .nothing: loop.overlay.state.status = .noSource(Translator.name(of: self.translator.source))
            case .abandoned: break
            }
        }
    }

    private enum Outcome {
        case translated
        /// No text in the source language on screen.
        case nothing
        case abandoned
    }

    /// The quick reading first, shown as soon as it's in, then the corrected reading, which
    /// matters more than usual here: shared-screen video is compressed and blurry. Patches over
    /// screen that moved meanwhile are held back; the pass waiting behind this one replaces them.
    private func process(_ frame: ScreenStream.Frame, loop: DisplayLoop) async -> Outcome {
        let started = ContinuousClock.now
        let overlay = loop.overlay
        let image = frame.image
        let size = CGSize(width: image.width, height: image.height)
        let languages = translator.recognitionLanguages
        let script = translator.sourceScript
        let ocrImage = frame.scale >= 2 ? ImagePreprocessor.scaled(image, by: 0.5) : image
        guard let quickLines = try? await TextRecognizer.recognize(ocrImage, boundsSize: size, languageCorrection: false, languages: languages),
              !Task.isCancelled
        else { return .abandoned }
        let rules = RuleDetector(image: image)
        let blocks = BlockGrouper.group(quickLines, source: script, hasRule: rules.hasRule)
        let shot = Shot(image: image, screenRect: loop.screen.frame, blocks: blocks, source: translator.source, target: translator.target)
        let model = translator.activeModel
        shot.displayedModel = model
        let hits = fillFromCache(shot, model: model)
        let isStale: (Patch) -> Bool = { loop.stale?.intersects(Self.pixelFrame(of: $0, scale: frame.scale)) ?? false }
        overlay.show(shot, hiding: isStale)
        await translator.translate(shot, using: model)
        remember(shot, model: model)
        let quickMilliseconds = milliseconds(since: started)

        guard !Task.isCancelled,
              let correctedLines = try? await TextReader.correctedRead(image, pixelsPerPoint: frame.scale, languages: languages),
              !Task.isCancelled
        else {
            logger.notice("Live pass: \(quickLines.count) lines, \(shot.sourceBlockIndices.count) to translate (\(hits) cached), \(quickMilliseconds) ms; abandoned before the corrected reading")
            return .abandoned
        }
        let correctedBlocks = BlockGrouper.group(TextReader.reconcile(quick: quickLines, corrected: correctedLines), source: script, hasRule: rules.hasRule)
        let quickTexts = Set(blocks.map(\.text))
        let changed = correctedBlocks.count { !quickTexts.contains($0.text) }
        shot.update(blocks: correctedBlocks)
        shot.isVerified = true
        _ = fillFromCache(shot, model: model)
        overlay.show(shot, hiding: isStale)
        await translator.translate(shot, using: model)
        remember(shot, model: model)
        let totalMilliseconds = milliseconds(since: started)
        // Counts and timings only, never text (ADR 0001).
        logger.notice("Live pass: \(quickLines.count) lines, \(shot.sourceBlockIndices.count) to translate (\(hits) cached), quick \(quickMilliseconds) ms, corrected \(totalMilliseconds) ms, \(changed) blocks changed")
        return shot.sourceBlockIndices.isEmpty ? .nothing : .translated
    }

    /// A patch's frame in the captured image's pixels.
    private static func pixelFrame(of patch: Patch, scale: CGFloat) -> CGRect {
        CGRect(x: patch.frame.minX * scale, y: patch.frame.minY * scale, width: patch.frame.width * scale, height: patch.frame.height * scale)
    }

    /// Prefills translations this session has already made. Returns how many.
    private func fillFromCache(_ shot: Shot, model: Translator.Model) -> Int {
        var hits = 0
        for index in shot.sourceBlockIndices {
            let text = shot.blocks[index].text
            if shot.translation(for: index, model: model) == nil, let cached = cache[text] {
                shot.setTranslation(cached, for: text, model: model)
                hits += 1
            }
        }
        return hits
    }

    private func remember(_ shot: Shot, model: Translator.Model) {
        for index in shot.sourceBlockIndices {
            if let translation = shot.translation(for: index, model: model) {
                cache[shot.blocks[index].text] = translation
            }
        }
    }

    private func milliseconds(since start: ContinuousClock.Instant) -> Int {
        let elapsed = ContinuousClock.now - start
        return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    }
}
