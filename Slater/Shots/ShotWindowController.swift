import AppKit
import Observation
import SwiftUI

/// A floating window for one Shot. It opens exactly over the text it came from and can be
/// dragged anywhere to keep for reference.
@MainActor
final class ShotWindowController {
    let shot: Shot
    private let panel: KeyablePanel
    private let viewState = ShotViewState()
    private var details: DetailsPanelController?
    private var spaceDownAt: TimeInterval?
    private let onClose: (ShotWindowController) -> Void

    /// A Space press held longer than this is a peek: the English comes back on release.
    private static let peekThreshold: TimeInterval = 0.35

    init(shot: Shot, onClose: @escaping (ShotWindowController) -> Void) {
        self.shot = shot
        self.onClose = onClose
        panel = KeyablePanel(contentRect: shot.screenRect)
        panel.level = .floating
        panel.hasShadow = true

        let container = ShotContainerView(rootView: ShotView(
            shot: shot,
            state: viewState,
            patches: ShotLayout.patches(for: shot),
            onClose: { [weak self] in self?.close() }
        ))
        container.onKeyDown = { [weak self] event in self?.keyDown(event) ?? false }
        container.onKeyUp = { [weak self] event in self?.keyUp(event) ?? false }
        panel.contentView = container
        panel.setFrame(shot.screenRect, display: false)
        panel.makeFirstResponder(container)
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        details?.close()
        panel.orderOut(nil)
        onClose(self)
    }

    private func keyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Esc
            close()
        case 49: // Space: tap to toggle, hold to peek
            if !event.isARepeat {
                viewState.showsOriginal.toggle()
                spaceDownAt = event.timestamp
            }
        default:
            guard event.charactersIgnoringModifiers == "d" else { return false }
            showDetails()
        }
        return true
    }

    private func keyUp(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49, let spaceDownAt else { return false }
        if event.timestamp - spaceDownAt > Self.peekThreshold {
            viewState.showsOriginal.toggle()
        }
        self.spaceDownAt = nil
        return true
    }

    private func showDetails() {
        if details == nil {
            details = DetailsPanelController(shot: shot)
        }
        details?.show()
    }
}

@MainActor
@Observable
final class ShotViewState {
    var showsOriginal = false
}

/// Hosts the SwiftUI Shot view and receives its key presses.
private final class ShotContainerView: NSView {
    var onKeyDown: (NSEvent) -> Bool = { _ in false }
    var onKeyUp: (NSEvent) -> Bool = { _ in false }

    init(rootView: some View) {
        super.init(frame: .zero)
        let hosting = NSHostingView(rootView: rootView)
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !onKeyDown(event) { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        if !onKeyUp(event) { super.keyUp(with: event) }
    }
}
