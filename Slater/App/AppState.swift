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

    func start() {
        hotkeys = HotkeyManager { [weak self] in self?.takeShot() }
        if !permissions.hasScreenRecording {
            showOnboarding()
        }
    }

    func takeShot() {
        permissions.refresh()
        guard permissions.hasScreenRecording else {
            showOnboarding()
            return
        }
        // Milestone 2: Capture every display and show the selection overlay.
        logger.info("Take Shot requested")
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = OnboardingWindowController(permissions: permissions)
        }
        onboarding?.show()
    }
}
