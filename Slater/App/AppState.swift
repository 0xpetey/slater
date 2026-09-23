import AppKit
import Observation
import os

private let logger = Logger(subsystem: "com.peterjournell.slater", category: "shots")

@MainActor
@Observable
final class AppState {
    let permissions = PermissionsManager()
    @ObservationIgnored private var hotkeys: HotkeyManager?
    @ObservationIgnored private var onboarding: OnboardingWindowController?
    @ObservationIgnored private let selectionOverlay = SelectionOverlayController()
    @ObservationIgnored private var isTakingShot = false
    @ObservationIgnored private var previews: [CapturePreviewController] = []

    func start() {
        hotkeys = HotkeyManager { [weak self] in self?.takeShot() }
        if !permissions.hasScreenRecording {
            showOnboarding()
        }
    }

    func takeShot() {
        guard !isTakingShot else { return }
        permissions.refresh()
        guard permissions.hasScreenRecording else {
            showOnboarding()
            return
        }
        isTakingShot = true
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
        let blocks = BlockGrouper.group(lines, hasRule: rules.hasHorizontalRule)
        // Never log recognized text: the unified log is written to disk (ADR 0001).
        logger.info("Recognized \(lines.count) lines in \(blocks.count) blocks in \(String(describing: ContinuousClock.now - started), privacy: .public)")
        #if DEBUG
        for block in blocks {
            print("[\(block.kind)\(block.isLowConfidence ? ", low confidence" : "")] \(block.text)")
        }
        #endif

        // Milestone 4 onwards: translate and open a Shot. For now, show the crop in place with its Blocks outlined.
        let preview = CapturePreviewController(image: crop, blocks: blocks, globalRect: globalRect) { [weak self] closed in
            self?.previews.removeAll { $0 === closed }
        }
        previews.append(preview)
        preview.show()
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permissions: permissions)
        }
        onboarding?.show()
    }
}
