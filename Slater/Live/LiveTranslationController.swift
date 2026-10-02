import AppKit
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
/// translations cached for the session so unchanged text is never sent twice.
@MainActor
@Observable
final class LiveTranslationController {
    static let framesPerSecond = 2

    private(set) var isRunning = false
    private let translator: Translator
    private var streams: [ScreenStream] = []
    private var overlays: [LiveOverlayController] = []
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
        var overlaysByDisplay: [CGDirectDisplayID: (NSScreen, LiveOverlayController)] = [:]
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            overlaysByDisplay[displayID] = (screen, LiveOverlayController(screen: screen))
        }
        overlays = overlaysByDisplay.values.map(\.1)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let slater = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            guard !slater.isEmpty else { throw LiveError.notListed }
            for display in content.displays {
                guard let (screen, overlay) = overlaysByDisplay[display.displayID] else { continue }
                let stream = try ScreenStream(display: display, excluding: slater, framesPerSecond: Self.framesPerSecond)
                streams.append(stream)
                tasks.append(Task { await self.run(stream, screen: screen, overlay: overlay) })
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
        overlays.forEach { $0.close() }
        overlays = []
        cache.removeAll()
        isRunning = false
        logger.notice("Live translation stopped")
    }

    /// Per-display state: detection runs at frame rate while a pass runs in the background,
    /// so video regions keep being learned and a new slide is noticed during a pass.
    @MainActor
    private final class DisplayLoop {
        var previous: FrameDiff?
        var detector = ChangeDetector(framesPerSecond: LiveTranslationController.framesPerSecond)
        var pass: Task<Void, Never>?
        /// A settled frame waiting for the running pass to finish.
        var pending: ScreenStream.Frame?
        /// Cells that moved since the frame the running pass is reading. Patches the pass puts
        /// over them are stale, so they're held back until the next pass.
        var stale: CellMask?
    }

    /// When this much of the screen has moved since the running pass's frame, the pass is
    /// abandoned for the one waiting, since most of what it would show is stale.
    static let restartFraction = 0.1

    private func run(_ stream: ScreenStream, screen: NSScreen, overlay: LiveOverlayController) async {
        let loop = DisplayLoop()
        defer { loop.pass?.cancel() }
        for await frame in stream.frames {
            if Task.isCancelled { return }
            let diff = FrameDiff(image: frame.image)
            let changes = diff.changes(since: loop.previous)
            loop.previous = diff
            let observation = loop.detector.observe(changes)
            if !observation.moved.isEmpty {
                // Patches over what moved come off at once; the rest stay until the next pass lands.
                overlay.hide { observation.moved.intersects(Self.pixelFrame(of: $0, scale: frame.scale)) }
                loop.stale?.formUnion(observation.moved)
                if let stale = loop.stale, stale.fraction >= Self.restartFraction {
                    loop.pass?.cancel()
                }
            }
            if observation.settled {
                loop.pending = frame
            }
            if loop.pass == nil, let settled = loop.pending {
                loop.pending = nil
                loop.stale = CellMask.none(like: changes)
                loop.pass = Task { [weak self] in
                    await self?.process(settled, screen: screen, overlay: overlay, loop: loop)
                    loop.pass = nil
                    loop.stale = nil
                }
            }
        }
    }

    /// The quick reading first, shown as soon as it's in, then the corrected reading, which
    /// matters more than usual here: shared-screen video is compressed and blurry. Patches over
    /// screen that moved meanwhile are held back; the pass waiting behind this one replaces them.
    private func process(_ frame: ScreenStream.Frame, screen: NSScreen, overlay: LiveOverlayController, loop: DisplayLoop) async {
        let started = ContinuousClock.now
        let image = frame.image
        let size = CGSize(width: image.width, height: image.height)
        let languages = translator.recognitionLanguages
        let script = translator.sourceScript
        let ocrImage = frame.scale >= 2 ? ImagePreprocessor.scaled(image, by: 0.5) : image
        guard let quickLines = try? await TextRecognizer.recognize(ocrImage, boundsSize: size, languageCorrection: false, languages: languages),
              !Task.isCancelled
        else { return }
        let rules = RuleDetector(image: image)
        let blocks = BlockGrouper.group(quickLines, source: script, hasRule: rules.hasRule)
        let shot = Shot(image: image, screenRect: screen.frame, blocks: blocks, source: translator.source, target: translator.target)
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
            return
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
