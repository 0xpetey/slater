import AppKit
import Observation
import os

private let logger = Logger(subsystem: "com.peterjournell.slater", category: "shots")

private func milliseconds(since start: ContinuousClock.Instant) -> Int {
    let elapsed = ContinuousClock.now - start
    return Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
}

@MainActor
@Observable
final class AppState {
    let permissions = PermissionsManager()
    let translator = Translator()
    let shots = ShotStore()
    @ObservationIgnored private var hotkeys: HotkeyManager?
    @ObservationIgnored private var onboarding: OnboardingWindowController?
    @ObservationIgnored private let selectionOverlay = SelectionOverlayController()
    @ObservationIgnored private var isTakingShot = false

    func start() {
        hotkeys = HotkeyManager { [weak self] in self?.takeShot() }
        Task {
            await translator.refreshLanguagePack()
            if !isReady {
                showOnboarding()
            }
            // A cold translation model took about 8 s to load on the first Shot after a launch;
            // loading it now means the first Shot only pays the usual per-text time.
            translator.warmUp()
        }
        // macOS may unload the model while the Mac sleeps.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.translator.warmUp() }
        }
    }

    /// Screen Recording is granted and the Japanese language pack is installed.
    var isReady: Bool {
        permissions.hasScreenRecording && translator.languagePack == .installed
    }

    func takeShot() {
        guard !isTakingShot else { return }
        permissions.refresh()
        guard isReady else {
            showOnboarding()
            return
        }
        isTakingShot = true
        translator.warmUp()
        Task {
            defer { isTakingShot = false }
            do {
                try await captureAndSelect()
            } catch {
                logger.error("Capture failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func captureAndSelect() async throws {
        let captureStarted = ContinuousClock.now
        let captures = try await ScreenCapturer.captureAllDisplays()
        logger.notice("Captured \(captures.count) displays in \(milliseconds(since: captureStarted)) ms")
        guard let selection = await selectionOverlay.select(from: captures) else { return }

        let capture = captures[selection.captureIndex]
        let pixelRect = CoordinateMapper.pixelRect(
            forLocalRect: selection.localRect,
            screenSize: capture.screen.frame.size,
            imageSize: CGSize(width: capture.image.width, height: capture.image.height)
        )
        guard let crop = capture.image.cropping(to: pixelRect) else { return }
        let globalRect = CoordinateMapper.globalRect(forLocalRect: selection.localRect, screenFrame: capture.screen.frame)

        let started = ContinuousClock.now
        let pixelsPerPoint = CGFloat(capture.image.width) / capture.screen.frame.width
        let lines = try await TextReader.read(crop, pixelsPerPoint: pixelsPerPoint)
        let readTime = milliseconds(since: started)
        let rules = RuleDetector(image: crop)
        let blocks = BlockGrouper.group(lines, hasRule: rules.hasRule)
        // Timings and counts only. Never log recognized text: the log is written to disk (ADR 0001).
        logger.notice("""
            Read \(crop.width)×\(crop.height) px: \(lines.count) lines (\(lines.count { $0.isVertical }) vertical) \
            in \(readTime) ms; \(blocks.count) blocks (\(blocks.count { $0.kind == .japanese }) Japanese, \
            \(blocks.count { $0.isVertical }) vertical, longest \(blocks.map(\.text.count).max() ?? 0) characters) \
            after \(milliseconds(since: started)) ms
            """)
        #if DEBUG
        for block in blocks {
            print("[\(block.kind)\(block.isLowConfidence ? ", low confidence" : "")] \(block.text)")
        }
        #endif

        let shot = Shot(image: crop, screenRect: globalRect, blocks: blocks)
        guard !shot.japaneseBlockIndices.isEmpty else {
            NoticePanel.show("No Japanese text found")
            return
        }

        shots.open(shot)
        Task {
            await translator.translate(shot)
            logger.notice("Shot complete \(milliseconds(since: started)) ms after selection")
        }
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permissions: permissions, translator: translator)
        }
        onboarding?.show()
    }
}
