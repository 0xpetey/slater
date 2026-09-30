import AppKit
import Observation
import os
import ScreenCaptureKit

private let logger = Logger(subsystem: "app.slater", category: "live")

/// Experimental: translates every source-language Block on the whole screen as it changes.
///
/// Each display gets a low-rate capture stream and a click-through overlay. A pass over a frame
/// is the quick OCR reading only (a corrected pass would double a cost that's already about a
/// second per screen), grouped as usual, translated with the active model, with translations
/// cached for the session so unchanged text is never sent twice.
@MainActor
@Observable
final class LiveTranslationController {
    static let framesPerSecond = 2
    /// Changes smaller than this share of the display (a clock, a blinking caret) don't trigger
    /// a pass.
    static let ignoredChange = 0.002

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
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let slater = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            for display in content.displays {
                guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { continue }
                let stream = try ScreenStream(display: display, excluding: slater, framesPerSecond: Self.framesPerSecond)
                let overlay = LiveOverlayController(screen: screen)
                streams.append(stream)
                overlays.append(overlay)
                tasks.append(Task { await self.run(stream, screen: screen, overlay: overlay) })
                try await stream.start()
            }
            logger.notice("Live translation started on \(self.streams.count) displays")
        } catch {
            logger.error("Live translation failed to start: \(error.localizedDescription, privacy: .public)")
            stop()
        }
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

    private func run(_ stream: ScreenStream, screen: NSScreen, overlay: LiveOverlayController) async {
        var previous: FrameDiff?
        for await frame in stream.frames {
            if Task.isCancelled { return }
            let diff = FrameDiff(image: frame.image)
            let (mask, fraction) = diff.changes(since: previous)
            if fraction < Self.ignoredChange { continue }
            // Patches over what changed come off at once; the rest stay until the pass lands.
            let pixelsPerPoint = CGFloat(frame.image.width) / screen.frame.width
            overlay.hide { patch in
                let frameInPixels = CGRect(
                    x: patch.frame.minX * pixelsPerPoint, y: patch.frame.minY * pixelsPerPoint,
                    width: patch.frame.width * pixelsPerPoint, height: patch.frame.height * pixelsPerPoint
                )
                return FrameDiff.mask(mask, columns: diff.columns, rows: diff.rows, intersects: frameInPixels)
            }
            previous = diff
            await process(frame, screen: screen, overlay: overlay, change: fraction)
        }
    }

    private func process(_ frame: ScreenStream.Frame, screen: NSScreen, overlay: LiveOverlayController, change: Double) async {
        let started = ContinuousClock.now
        let image = frame.image
        let size = CGSize(width: image.width, height: image.height)
        let ocrImage = frame.scale >= 2 ? ImagePreprocessor.scaled(image, by: 0.5) : image
        guard let lines = try? await TextRecognizer.recognize(ocrImage, boundsSize: size, languageCorrection: false, languages: translator.recognitionLanguages),
              !Task.isCancelled
        else { return }
        let blocks = BlockGrouper.group(lines, source: translator.sourceScript, hasRule: RuleDetector(image: image).hasRule)
        let shot = Shot(image: image, screenRect: screen.frame, blocks: blocks, source: translator.source, target: translator.target)
        shot.isVerified = true
        let model = translator.activeModel
        shot.displayedModel = model

        var hits = 0
        for index in shot.sourceBlockIndices {
            let text = shot.blocks[index].text
            if let cached = cache[text] {
                shot.setTranslation(cached, for: text, model: model)
                hits += 1
            }
        }
        overlay.show(shot)
        await translator.translate(shot, using: model)
        for index in shot.sourceBlockIndices {
            if let translation = shot.translation(for: index, model: model) {
                cache[shot.blocks[index].text] = translation
            }
        }
        let elapsed = ContinuousClock.now - started
        let milliseconds = elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000
        // Counts and timings only, never text (ADR 0001).
        logger.notice("Live pass: \(lines.count) lines, \(shot.sourceBlockIndices.count) to translate (\(hits) cached), \(milliseconds) ms, change \(Int(change * 100))%")
    }
}
