import Observation

/// The open Shots, newest last. Feeds the menu bar's Open Shots list and Close All.
@MainActor
@Observable
final class ShotStore {
    private(set) var windows: [ShotWindowController] = []

    func open(_ shot: Shot) {
        let window = ShotWindowController(shot: shot) { [weak self] closed in
            self?.windows.removeAll { $0 === closed }
        }
        windows.append(window)
        window.show()
    }

    func closeAll() {
        windows.forEach { $0.close() }
    }
}
