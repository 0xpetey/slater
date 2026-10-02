import AppKit
import Observation
import os

private let logger = Logger(subsystem: "app.slater", category: "shots")

private func milliseconds(since start: ContinuousClock.Instant) -> Int {
    let elapsed = ContinuousClock.now - start
    return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
}

@MainActor
@Observable
final class AppState {
    let permissions = PermissionsManager()
    let translator: Translator
    let shots: ShotStore
    /// Experimental whole-screen live translation.
    let live: LiveTranslationController
    @ObservationIgnored private var hotkeys: HotkeyManager?
    @ObservationIgnored private var onboarding: OnboardingWindowController?
    @ObservationIgnored private let selectionOverlay = SelectionOverlayController()
    @ObservationIgnored private var isTakingShot = false

    init() {
        let translator = Translator()
        self.translator = translator
        shots = ShotStore(translator: translator)
        live = LiveTranslationController(translator: translator)
    }

    func start() {
        hotkeys = HotkeyManager(
            onTakeShot: { [weak self] in self?.takeShot() },
            onTakeWindowShot: { [weak self] in self?.takeWindowShot() },
            onToggleLiveTranslation: { [weak self] in self?.toggleLiveTranslation() },
            onToggleLiveWindowTranslation: { [weak self] in self?.toggleLiveWindowTranslation() },
            onFreezeLiveTranslation: { [weak self] in self?.live.toggleFreeze() }
        )
        Task {
            await translator.refresh()
            if !isReady {
                showOnboarding()
            }
            // A cold translation model took about 8 s to load on the first Shot after a launch;
            // loading it now means the first Shot only pays the usual per-text time.
            translator.warmUp()
            await TextRecognizer.warmUp(languages: translator.recognitionLanguages)
        }
        ScreenCapturer.warmUp()
        // macOS may unload the models while the Mac sleeps.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.translator.warmUp()
                ScreenCapturer.warmUp()
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { ScreenCapturer.warmUp() }
        }
    }

    /// Screen Recording is granted and a translation model is installed.
    var isReady: Bool {
        permissions.hasScreenRecording && translator.hasInstalledModel
    }

    /// Live translation of every display: stops it if that's running, or takes over from a window.
    func toggleLiveTranslation() {
        guard isReady else {
            showOnboarding()
            return
        }
        live.toggle(.screen)
    }

    /// Live translation of the front window, the one a Shot of Front Window would take: stops
    /// it if a window is live, or takes over from the whole screen.
    func toggleLiveWindowTranslation() {
        guard isReady else {
            showOnboarding()
            return
        }
        if live.isRunning, live.scope.isWindow {
            live.stop()
            return
        }
        guard let window = FrontWindow.front() else {
            NoticePanel.show("No window in front")
            return
        }
        live.toggle(.window(window.id))
    }

    /// Takes over from live translation, if it's running.
    func takeShot() {
        guard !isTakingShot else { return }
        permissions.refresh()
        guard isReady else {
            showOnboarding()
            return
        }
        live.stop()
        isTakingShot = true
        translator.warmUp()
        let pressed = ContinuousClock.now
        Task {
            defer { isTakingShot = false }
            do {
                try await captureAndSelect(pressedAt: pressed)
            } catch {
                logger.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A Shot of the front window, with no box to draw. Takes over from live translation, if
    /// it's running.
    func takeWindowShot() {
        guard !isTakingShot else { return }
        permissions.refresh()
        guard isReady else {
            showOnboarding()
            return
        }
        live.stop()
        guard let selection = FrontWindow.selection() else {
            NoticePanel.show("No window in front")
            return
        }
        isTakingShot = true
        translator.warmUp()
        let pressed = ContinuousClock.now
        Task {
            defer { isTakingShot = false }
            do {
                let captures = try await ScreenCapturer.captureAllDisplays()
                logger.notice("Captured \(captures.count) displays \(milliseconds(since: pressed)) ms after the window hotkey")
                try await makeShot(of: selection, in: captures)
            } catch {
                logger.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func captureAndSelect(pressedAt pressed: ContinuousClock.Instant) async throws {
        // The overlay goes up over the live screen at once; the capture freezes it ~80 ms later.
        selectionOverlay.show()
        let captureTask = Task { try await ScreenCapturer.captureAllDisplays() }
        Task {
            let captures = try await captureTask.value
            selectionOverlay.freeze(with: captures)
            logger.notice("Captured \(captures.count) displays \(milliseconds(since: pressed)) ms after the hotkey")
        }
        guard let selection = await selectionOverlay.select() else {
            captureTask.cancel()
            return
        }
        let captures = try await captureTask.value
        try await makeShot(of: selection, in: captures)
    }

    /// Crops the selection out of its display's Capture, reads it twice (ADR 0002) and opens
    /// the Shot.
    private func makeShot(of selection: SelectionOverlayController.Selection, in captures: [DisplayCapture]) async throws {
        guard let capture = captures.first(where: { $0.displayID == selection.displayID }) else { return }

        let pixelRect = CoordinateMapper.pixelRect(
            forLocalRect: selection.localRect,
            screenSize: capture.frame.size,
            imageSize: CGSize(width: capture.image.width, height: capture.image.height)
        )
        guard let crop = capture.image.cropping(to: pixelRect) else { return }
        let globalRect = CoordinateMapper.globalRect(forLocalRect: selection.localRect, screenFrame: capture.frame)

        let started = ContinuousClock.now
        let pixelsPerPoint = CGFloat(capture.image.width) / capture.frame.width
        let languages = translator.recognitionLanguages
        let script = translator.sourceScript
        // The corrected reading takes about 2.4× as long as the quick one, so it starts now and
        // verifies the Shot once it's already on screen (ADR 0002).
        async let correctedLines = TextReader.correctedRead(crop, pixelsPerPoint: pixelsPerPoint, languages: languages)
        let quickLines = try await TextReader.quickRead(crop, languages: languages)
        let quickTime = milliseconds(since: started)
        let rules = RuleDetector(image: crop)
        var blocks = BlockGrouper.group(quickLines, source: script, hasRule: rules.hasRule)
        var isVerified = false

        if !blocks.contains(where: { $0.kind == .source }) {
            // Rare: the quick reading may have missed faint text, so wait for the corrected one
            // before deciding there's nothing to translate.
            blocks = BlockGrouper.group(TextReader.reconcile(quick: quickLines, corrected: try await correctedLines), source: script, hasRule: rules.hasRule)
            isVerified = true
            guard blocks.contains(where: { $0.kind == .source }) else {
                logger.notice("No source text found \(milliseconds(since: started)) ms after selection")
                NoticePanel.show("No \(Translator.name(of: translator.source)) text found")
                return
            }
        }

        let shot = Shot(image: crop, screenRect: globalRect, blocks: blocks, source: translator.source, target: translator.target)
        shot.isVerified = isVerified
        shot.displayedModel = translator.activeModel
        shots.open(shot)
        // Timings and counts only. Never log recognized text: the log is written to disk (ADR 0001).
        logger.notice("""
            Quick reading of \(crop.width)×\(crop.height) px: \(quickLines.count) lines \
            (\(quickLines.count { $0.isVertical }) vertical) in \(quickTime) ms; Shot open \(milliseconds(since: started)) ms \
            after selection with \(blocks.count) blocks (\(blocks.count { $0.kind == .source }) to translate, \
            longest \(blocks.map(\.text.count).max() ?? 0) characters)
            """)
        #if DEBUG
        for block in blocks {
            print("[\(block.kind)] \(block.text)")
        }
        #endif
        Task { await translator.translate(shot) }
        guard !isVerified else { return }

        do {
            let lines = TextReader.reconcile(quick: quickLines, corrected: try await correctedLines)
            let correctedBlocks = BlockGrouper.group(lines, source: script, hasRule: rules.hasRule)
            let quickTexts = Set(blocks.map(\.text))
            let changed = correctedBlocks.count { !quickTexts.contains($0.text) }
            shot.update(blocks: correctedBlocks)
            shot.isVerified = true
            logger.notice("""
                Corrected reading applied \(milliseconds(since: started)) ms after selection: \
                \(changed) of \(correctedBlocks.count) blocks changed, \(correctedBlocks.count(where: \.isLowConfidence)) low-confidence
                """)
            #if DEBUG
            for block in correctedBlocks where !quickTexts.contains(block.text) {
                print("[corrected, \(block.kind)\(block.isLowConfidence ? ", low confidence" : "")] \(block.text)")
            }
            #endif
            await translator.translate(shot)
        } catch {
            shot.isVerified = true
            logger.error("Corrected reading failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permissions: permissions, translator: translator)
        }
        onboarding?.show()
    }
}
