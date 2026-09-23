import AppKit

/// Shows each display's frozen Capture full-screen and lets the user drag a box on one of them.
@MainActor
final class SelectionOverlayController {
    struct Selection: Sendable {
        /// Index into the captures passed to `select(from:)`.
        let captureIndex: Int
        /// The selected box in that capture's screen-local points.
        let localRect: CGRect
    }

    private var panels: [KeyablePanel] = []
    private var continuation: CheckedContinuation<Selection?, Never>?

    /// Returns nil when the user cancels with Esc or makes a drag too small to be deliberate.
    func select(from captures: [DisplayCapture]) async -> Selection? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let mouse = NSEvent.mouseLocation
            for (index, capture) in captures.enumerated() {
                let panel = KeyablePanel(contentRect: capture.screen.frame)
                panel.level = .screenSaver
                panel.contentView = SelectionView(image: capture.image) { [weak self] rect in
                    self?.finish(rect.map { Selection(captureIndex: index, localRect: $0) })
                }
                panel.setFrame(capture.screen.frame, display: false)
                panels.append(panel)
                if capture.screen.frame.contains(mouse) {
                    panel.makeKeyAndOrderFront(nil)
                } else {
                    panel.orderFrontRegardless()
                }
            }
            NSCursor.crosshair.set()
        }
    }

    private func finish(_ selection: Selection?) {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        NSCursor.arrow.set()
        continuation?.resume(returning: selection)
        continuation = nil
    }
}

/// The frozen image under a dim layer, with the selected box cut out of the dim.
private final class SelectionView: NSView {
    /// Drags smaller than this, in points, count as a cancel.
    private static let minimumSize: CGFloat = 6

    private let onFinish: (CGRect?) -> Void
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private var dragStart: CGPoint?
    private var selection: CGRect?

    init(image: CGImage, onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
        super.init(frame: .zero)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize

        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.35).cgColor
        dimLayer.fillRule = .evenOdd
        borderLayer.fillColor = nil
        borderLayer.strokeColor = NSColor.white.cgColor
        borderLayer.lineWidth = 1
        layer?.addSublayer(dimLayer)
        layer?.addSublayer(borderLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        updateLayers()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        dragStart = convert(event.locationInWindow, from: nil)
        selection = nil
        updateLayers()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(
            x: min(dragStart.x, point.x), y: min(dragStart.y, point.y),
            width: abs(point.x - dragStart.x), height: abs(point.y - dragStart.y)
        ).intersection(bounds)
        NSCursor.crosshair.set()
        updateLayers()
    }

    override func mouseUp(with event: NSEvent) {
        guard let selection, selection.width >= Self.minimumSize, selection.height >= Self.minimumSize else {
            onFinish(nil)
            return
        }
        onFinish(selection)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onFinish(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    private func updateLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dimLayer.frame = bounds
        borderLayer.frame = bounds
        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)
        if let selection {
            dimPath.addRect(selection)
            borderLayer.path = CGPath(rect: selection.insetBy(dx: -0.5, dy: -0.5), transform: nil)
        } else {
            borderLayer.path = nil
        }
        dimLayer.path = dimPath
        CATransaction.commit()
    }
}
