import AppKit

/// Temporary, for milestones 2–4: shows a Shot's image exactly where it came from, with its
/// Blocks outlined, so the crop and grouping can be checked. D opens the details panel.
/// Replaced by Shot windows in milestone 5.
/// Kept in memory only (ADR 0001).
@MainActor
final class CapturePreviewController {
    private let panel: KeyablePanel
    private let shot: Shot
    private var details: DetailsPanelController?

    init(shot: Shot, onClose: @escaping (CapturePreviewController) -> Void) {
        self.shot = shot
        let globalRect = shot.screenRect
        panel = KeyablePanel(contentRect: globalRect)
        panel.level = .floating
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        let view = PreviewView(image: shot.image, blocks: shot.blocks, pointsPerPixel: globalRect.width / CGFloat(shot.image.width))
        panel.contentView = view
        panel.setFrame(globalRect, display: false)
        view.onEscape = { [weak self] in
            guard let self else { return }
            details?.close()
            panel.orderOut(nil)
            onClose(self)
        }
        view.onDetails = { [weak self] in self?.showDetails() }
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
    }

    private func showDetails() {
        if details == nil {
            details = DetailsPanelController(shot: shot)
        }
        details?.show()
    }
}

private final class PreviewView: NSView {
    var onEscape: () -> Void = {}
    var onDetails: () -> Void = {}

    init(image: CGImage, blocks: [Block], pointsPerPixel: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.borderColor = NSColor.systemRed.cgColor
        layer?.borderWidth = 1

        // Block bounds use a top-left origin, so draw them in a flipped layer.
        let outlines = CALayer()
        outlines.isGeometryFlipped = true
        outlines.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        for block in blocks {
            let outline = CALayer()
            let bounds = block.bounds
            outline.frame = CGRect(
                x: bounds.minX * pointsPerPixel, y: bounds.minY * pointsPerPixel,
                width: bounds.width * pointsPerPixel, height: bounds.height * pointsPerPixel
            )
            outline.borderWidth = 1
            outline.borderColor = switch (block.kind, block.isLowConfidence) {
            case (.japanese, true): NSColor.systemOrange.cgColor
            case (.japanese, false): NSColor.systemBlue.cgColor
            case (.passthrough, _): NSColor.systemGray.cgColor
            }
            outlines.addSublayer(outline)
        }
        layer?.addSublayer(outlines)
    }

    override func layout() {
        super.layout()
        layer?.sublayers?.forEach { $0.frame = bounds }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onEscape()
        } else if event.charactersIgnoringModifiers == "d" {
            onDetails()
        } else {
            super.keyDown(with: event)
        }
    }
}
