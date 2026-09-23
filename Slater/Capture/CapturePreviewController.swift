import AppKit

/// Temporary, for milestone 2: shows a cropped Capture exactly where it came from, so the
/// crop can be checked against the screen underneath. Replaced by Shot windows in milestone 5.
/// Kept in memory only (ADR 0001).
@MainActor
final class CapturePreviewController {
    private let panel: KeyablePanel

    init(image: CGImage, globalRect: CGRect, onClose: @escaping (CapturePreviewController) -> Void) {
        panel = KeyablePanel(contentRect: globalRect)
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        let view = PreviewView(image: image)
        panel.contentView = view
        panel.setFrame(globalRect, display: false)
        view.onEscape = { [weak self] in
            guard let self else { return }
            panel.orderOut(nil)
            onClose(self)
        }
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
    }
}

private final class PreviewView: NSView {
    var onEscape: () -> Void = {}

    init(image: CGImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.borderColor = NSColor.systemRed.cgColor
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onEscape()
        } else {
            super.keyDown(with: event)
        }
    }
}
