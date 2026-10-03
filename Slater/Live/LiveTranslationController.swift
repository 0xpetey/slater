import AppKit
@preconcurrency import KeyboardShortcuts
import Observation
import os
import ScreenCaptureKit

private let logger = Log(category: "live")

/// Experimental: translates every source-language Block on the whole screen, or in one window,
/// as it changes, built for watching a shared Japanese presentation on a video call.
///
/// Each display gets a low-rate capture stream and a click-through overlay; a window gets one
/// stream of its own pixels, whatever is over it on screen, and an overlay on every display,
/// since it can straddle them. `ChangeDetector` decides when the content changed in a way
/// worth a pass (a new slide, not a camera tile) and when the change has settled; a pass is the
/// quick OCR reading, shown at once, then the corrected reading, both grouped as usual and
/// translated with the active model, with translations cached for the session so unchanged
/// text is never sent twice. A hotkey freezes the screen at the frame the patches belong to, so
/// a slide can be read after the presenter has moved on.
@MainActor
@Observable
final class LiveTranslationController {
    static let framesPerSecond = 2
    /// When this much of the frame has moved since the running pass's frame, the pass is
    /// abandoned for the one waiting, since most of what it would show is stale.
    static let restartFraction = 0.1
    /// ScreenCaptureKit needn't send a frame while nothing changes, so a change that was the
    /// last thing to move could wait forever for the quiet frame that settles it. After this
    /// long without a frame, stillness is taken as read.
    static let stillness: Duration = .seconds(1)

    /// What live translation covers.
    enum Scope: Equatable {
        /// Every display, whole.
        case screen
        /// One window, followed as it moves and resizes, wherever it is on screen.
        case window(CGWindowID)

        var isWindow: Bool {
            if case .window = self { return true }
            return false
        }
    }

    /// Off until the user opts in, in Settings, the feature being experimental: the menu items
    /// and the hotkeys come and go with it. Turning it off ends a running session.
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            if !isEnabled { stop() }
        }
    }
    private static let enabledKey = "liveTranslationEnabled"

    private(set) var isRunning = false
    /// What's being translated while running; the last scope otherwise.
    private(set) var scope: Scope = .screen
    /// Every loop is held at a frame, with its patches, until unfrozen.
    private(set) var isFrozen = false
    private let translator: Translator
    private var streams: [ScreenStream] = []
    private var loops: [Loop] = []
    private var tasks: [Task<Void, Never>] = []
    /// Translations made in this live session. Memory only, and dropped when live translation
    /// stops (ADR 0001).
    @ObservationIgnored private var cache: [String: String] = [:]

    init(translator: Translator) {
        self.translator = translator
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Starts live translation of `scope`, or stops it if that's what's running. The screen's
    /// hotkey while a window is live, or the other way round, switches over.
    func toggle(_ scope: Scope) {
        if isRunning {
            let same = self.scope.isWindow == scope.isWindow
            stop()
            if same { return }
        }
        Task { await start(scope) }
    }

    func start(_ scope: Scope) async {
        guard !isRunning else { return }
        isRunning = true
        self.scope = scope
        do {
            switch scope {
            case .screen:
                try await startOnScreen()
            case .window(let id):
                try await start(onWindow: id)
            }
        } catch {
            logger.error("Live translation failed to start: \(error.localizedDescription)")
            stop()
        }
    }

    /// The overlays go up first: ScreenCaptureKit lists an app only while it has a window on
    /// screen, and the overlays must be excluded from the capture, or their patches would
    /// read as change and every pass would trigger the next.
    private func startOnScreen() async throws {
        let mainHeight = Self.mainScreenHeight
        var loopsByDisplay: [CGDirectDisplayID: Loop] = [:]
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let loop = Loop(rect: CoordinateMapper.flippedGlobalRect(screen.frame, mainScreenHeight: mainHeight))
            loop.state.region = loop.rect
            attach(loop, to: [screen])
            loopsByDisplay[displayID] = loop
        }
        loops = Array(loopsByDisplay.values)
        let (content, slater) = try await ScreenCapturer.contentListingSlater()
        guard !slater.isEmpty else { throw LiveError.notListed }
        for display in content.displays {
            guard let loop = loopsByDisplay[display.displayID] else { continue }
            let stream = try ScreenStream(display: display, excluding: slater, framesPerSecond: Self.framesPerSecond)
            try await launch(stream, loop: loop)
        }
        logger.notice("Live translation started on \(self.streams.count) displays")
    }

    /// The window's own pixels, so nothing over it is ever read.
    private func start(onWindow id: CGWindowID) async throws {
        guard let window = FrontWindow.locate(id) else { throw LiveError.windowClosed }
        let loop = Loop(rect: window.bounds)
        attach(loop, to: NSScreen.screens)
        loops = [loop]
        guard track(id, loop: loop) else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let shareable = content.windows.first(where: { $0.windowID == id }) else { throw LiveError.windowNotShareable }
        try await launch(try ScreenStream(window: shareable, framesPerSecond: Self.framesPerSecond), loop: loop)
        logger.notice("Live translation started on a window")
    }

    private func launch(_ stream: ScreenStream, loop: Loop) async throws {
        streams.append(stream)
        tasks.append(Task { await self.run(stream, loop: loop) })
        tasks.append(Task { await self.tick(loop) })
        try await stream.start()
    }

    /// A loop's overlays, one per screen, and its badge above them, all drawing its state. The
    /// badge says how to end live translation, and a click on it does.
    private func attach(_ loop: Loop, to screens: [NSScreen]) {
        loop.overlays = screens.map { screen in
            let overlay = LiveOverlayController(screen: screen, state: loop.state)
            overlay.onClick = { [weak self] in
                if self?.isFrozen == true { self?.unfreeze() }
            }
            return overlay
        }
        let hotkey = KeyboardShortcuts.getShortcut(for: scope.isWindow ? .toggleLiveWindowTranslation : .toggleLiveTranslation)
        loop.state.endHint = hotkey.map { "Click or \($0) to end" } ?? "Click to end"
        let badge = LiveBadgeController(state: loop.state)
        badge.onClick = { [weak self] in self?.stop() }
        loop.badge = badge
    }

    /// The window server's coordinates are measured from the main screen's top-left corner.
    private static var mainScreenHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private enum LiveError: LocalizedError {
        /// ScreenCaptureKit didn't list Slater, so its overlay couldn't be kept out of the capture.
        case notListed
        /// The live window is gone.
        case windowClosed
        /// ScreenCaptureKit doesn't list the window.
        case windowNotShareable

        var errorDescription: String? {
            switch self {
            case .notListed: "Slater's windows couldn't be excluded from the capture"
            case .windowClosed: "The window closed"
            case .windowNotShareable: "The window can't be captured"
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        tasks.forEach { $0.cancel() }
        tasks = []
        let streams = self.streams
        self.streams = []
        Task {
            for stream in streams { await stream.stop() }
        }
        for loop in loops {
            loop.pass?.cancel()
            loop.overlays.forEach { $0.close() }
            loop.badge?.close()
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

    /// Holds each loop at the frame its patches belong to: the running pass's frame, which it
    /// finishes on; or, if the content changed since the last pass, the newest frame, read
    /// right away instead of waiting for it to settle; or else the last pass's frame.
    private func freeze() {
        isFrozen = true
        // The badge ends live translation even now, so the screen is the thing to click.
        let hint = KeyboardShortcuts.getShortcut(for: .freezeLiveTranslation).map { "Click the screen or \($0) to resume" } ?? "Click the screen to resume"
        for loop in loops {
            let frame: Loop.Frame?
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
            loop.state.freeze(frame.image, hint: hint)
            for overlay in loop.overlays { overlay.takesClicks = true }
            // Patches from a pass over this very frame are all good, whatever moved since.
            if loop.state.shot?.image === frame.image {
                loop.state.hiddenPatches = []
            }
            startPendingPass(loop)
        }
    }

    /// Lets the live content through again. Whatever changed under the frozen frame is read at
    /// once; the detector keeps what it learned about video, so a camera tile isn't re-learned.
    private func unfreeze() {
        isFrozen = false
        for loop in loops {
            guard let frozen = loop.frozen else { continue }
            loop.frozen = nil
            loop.state.unfreeze()
            for overlay in loop.overlays { overlay.takesClicks = false }
            guard let latest = loop.latest, latest.image !== frozen.frame.image else { continue }
            let diff = FrameDiff(image: latest.image)
            loop.previous = diff
            let changes = diff.changes(since: frozen.diff).clustered()
            guard changes.fraction >= ChangeDetector.significantFraction else { continue }
            loop.state.hide { changes.intersects(Self.pixelFrame(of: $0, scale: latest.scale)) }
            loop.pending = latest
            startPendingPass(loop)
        }
    }

    /// One stream's state: detection runs at frame rate while a pass runs in the background,
    /// so video regions keep being learned and a new slide is noticed during a pass.
    @MainActor
    private final class Loop {
        /// A captured frame and where its content is.
        struct Frame: Sendable {
            let image: CGImage
            /// Pixels per point.
            let scale: CGFloat
            /// The content's top-left corner, in the window server's coordinates.
            let origin: CGPoint

            /// Where the content is, in the window server's coordinates. A window's frame can be
            /// a different size from the window for a moment after a resize: cropped or padded,
            /// never scaled, so its pixels still sit at their points from the corner.
            var rect: CGRect {
                CGRect(origin: origin, size: CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
            }
        }

        let state = LiveOverlayState()
        /// One per display: a display's loop uses its own, a window's loop all of them.
        var overlays: [LiveOverlayController] = []
        var badge: LiveBadgeController?
        /// Where the content is now: the display, or the live window as last seen.
        var rect: CGRect
        /// The stream is being refitted to the window's new size.
        var isResizing = false
        var lastFrameAt = ContinuousClock.now
        var previous: FrameDiff?
        var detector = ChangeDetector(framesPerSecond: LiveTranslationController.framesPerSecond)
        var pass: Task<Void, Never>?
        /// The frame the running, or else the last, pass reads.
        var passFrame: Frame?
        /// A settled frame waiting for the running pass to finish.
        var pending: Frame?
        /// Cells that moved since the frame the running pass is reading. Patches the pass puts
        /// over them are stale, so they're held back until the next pass.
        var stale: CellMask?
        /// The newest frame, frozen or not.
        var latest: Frame?
        /// While frozen: the frame on show, and its thumbnail for finding what changed once
        /// unfrozen.
        var frozen: (frame: Frame, diff: FrameDiff)?

        init(rect: CGRect) {
            self.rect = rect
        }
    }

    /// Follows the live window: where it is now, what other windows are over it, and whether
    /// it's still there. Patches are laid out relative to the window, so they ride along when it
    /// moves. Returns false once it has closed, which stops live translation.
    private func track(_ id: CGWindowID, loop: Loop) -> Bool {
        guard let window = FrontWindow.locate(id) else {
            logger.notice("Live translation stopped: the window closed")
            NoticePanel.show("The window closed")
            stop()
            return false
        }
        loop.rect = window.bounds
        // Set only on change: the overlay and badge redraw on every set.
        let region = window.isOnScreen ? window.bounds : nil
        if loop.state.region != region { loop.state.region = region }
        let occluded = window.isOnScreen
            ? FrontWindow.occluders(above: id).map { $0.offsetBy(dx: -window.bounds.minX, dy: -window.bounds.minY) }
            : []
        if loop.state.occluded != occluded { loop.state.occluded = occluded }
        return true
    }

    private func run(_ stream: ScreenStream, loop: Loop) async {
        for await captured in stream.frames {
            if Task.isCancelled { return }
            if case .window(let id) = scope {
                guard track(id, loop: loop) else { return }
                if !loop.isResizing, !Self.matches(captured, points: loop.rect.size) {
                    loop.isResizing = true
                    let size = loop.rect.size
                    Task {
                        await stream.resize(toPoints: size, scale: captured.scale)
                        loop.isResizing = false
                    }
                }
            }
            let frame = Loop.Frame(image: captured.image, scale: captured.scale, origin: loop.rect.origin)
            loop.latest = frame
            loop.lastFrameAt = .now
            if loop.frozen != nil { continue }
            let diff = FrameDiff(image: frame.image)
            let changes = diff.changes(since: loop.previous)
            loop.previous = diff
            observe(changes, frame: frame, loop: loop)
        }
    }

    /// Whether a frame has the pixels of `points` at its scale, give or take a rounding pixel.
    private static func matches(_ frame: ScreenStream.Frame, points: CGSize) -> Bool {
        abs(CGFloat(frame.image.width) - points.width * frame.scale) <= 1
            && abs(CGFloat(frame.image.height) - points.height * frame.scale) <= 1
    }

    /// Twice a frame interval: follows the live window even while its content is still, and
    /// treats a long gap between frames as a quiet frame, so a change that was the last thing
    /// to move settles (see `stillness`).
    private func tick(_ loop: Loop) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.stillness / 2)
            guard !Task.isCancelled else { return }
            if case .window(let id) = scope, !track(id, loop: loop) { return }
            guard loop.frozen == nil, loop.detector.isPending, let latest = loop.latest,
                  loop.lastFrameAt.duration(to: .now) >= Self.stillness
            else { continue }
            observe(CellMask.none(for: latest.image), frame: latest, loop: loop)
        }
    }

    /// Feeds a frame's changes to the detector, takes down patches over what moved, and starts
    /// a pass once the content has settled.
    private func observe(_ changes: CellMask, frame: Loop.Frame, loop: Loop) {
        let observation = loop.detector.observe(changes)
        if observation.verdict == .changed, loop.state.status != .updateDetected {
            loop.state.status = .updateDetected
        }
        if !observation.moved.isEmpty {
            // Patches over what moved come off at once; the rest stay until the next pass lands.
            loop.state.hide { observation.moved.intersects(Self.pixelFrame(of: $0, scale: frame.scale)) }
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

    /// Starts the pass on the waiting frame, if there is one and none is running.
    private func startPendingPass(_ loop: Loop) {
        guard loop.pass == nil, let frame = loop.pending else { return }
        loop.pending = nil
        loop.passFrame = frame
        // Nothing moves under a frozen frame.
        loop.stale = loop.frozen == nil ? CellMask.none(for: frame.image) : nil
        loop.state.status = .processing
        loop.pass = Task { [weak self] in
            let outcome = await self?.process(frame, loop: loop)
            loop.pass = nil
            loop.stale = nil
            // An abandoned pass leaves the badge on the change that abandoned it, and a
            // pending frame means the next pass is about to start.
            guard loop.pending == nil, let self, let outcome else { return }
            switch outcome {
            case .translated: loop.state.status = .done
            case .nothing: loop.state.status = .noSource(Translator.name(of: self.translator.source))
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
    /// content that moved meanwhile are held back; the pass waiting behind this one replaces them.
    private func process(_ frame: Loop.Frame, loop: Loop) async -> Outcome {
        let started = ContinuousClock.now
        let state = loop.state
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
        let screenRect = CoordinateMapper.flippedGlobalRect(frame.rect, mainScreenHeight: Self.mainScreenHeight)
        let shot = Shot(image: image, screenRect: screenRect, blocks: blocks, source: translator.source, target: translator.target)
        let model = translator.activeModel
        shot.displayedModel = model
        let hits = fillFromCache(shot, model: model)
        let isStale: (Patch) -> Bool = { loop.stale?.intersects(Self.pixelFrame(of: $0, scale: frame.scale)) ?? false }
        state.show(shot, hiding: isStale)
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
        state.show(shot, hiding: isStale)
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
