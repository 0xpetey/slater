import AppKit
import Observation
import os

private let logger = Logger(subsystem: "com.peterjournell.slater", category: "shots")

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
        let captures = try await ScreenCapturer.captureAllDisplays()
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
        let rules = RuleDetector(image: crop)
        let blocks = BlockGrouper.group(lines, hasRule: rules.hasRule)
        // Never log recognized text: the unified log is written to disk (ADR 0001).
        logger.info("Recognized \(lines.count) lines in \(blocks.count) blocks in \(String(describing: ContinuousClock.now - started), privacy: .public)")
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
            logger.info("Translated \(shot.translations.count) blocks in \(String(describing: ContinuousClock.now - started), privacy: .public)")
        }
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permissions: permissions, translator: translator)
        }
        onboarding?.show()
    }
}
