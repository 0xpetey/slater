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
        logger.info("Selected \(String(describing: globalRect), privacy: .public) as \(crop.width)×\(crop.height) px")

        // Milestone 3 onwards: recognize, translate and open a Shot. For now, show the crop in place.
        let preview = CapturePreviewController(image: crop, globalRect: globalRect) { [weak self] closed in
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
