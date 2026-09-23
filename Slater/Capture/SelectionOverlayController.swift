import AppKit
import os

private let logger = Logger(subsystem: "com.peterjournell.slater", category: "shots")

/// The full-screen selection: a dim layer with a crosshair, on which the user drags a box.
///
/// It appears the instant the hotkey is pressed, over the live screen, and is frozen with the
/// Captures when they land about 80 ms later. The swap is invisible unless something on screen
/// was moving, and the crosshair never waits for the capture.
@MainActor
final class SelectionOverlayController {
    struct Selection: Sendable {
        let displayID: CGDirectDisplayID
        /// The selected box in that screen's local points.
        let localRect: CGRect
    }

    private var panels: [CGDirectDisplayID: KeyablePanel] = [:]
    private var views: [CGDirectDisplayID: SelectionView] = [:]
    private var continuation: CheckedContinuation<Selection?, Never>?
    /// A selection made (or cancelled) before `select()` was awaited.
    private var earlyResult: Selection??

    /// Shows the overlay on every screen right away.
    func show() {
        let started = ContinuousClock.now
        earlyResult = nil
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            guard let displayID = screen.displayID else { continue }
            let panel = KeyablePanel(contentRect: screen.frame)
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            let view = SelectionView { [weak self] rect in
                self?.finish(rect.map { Selection(displayID: displayID, localRect: $0) })
            }
            panel.contentView = view
            panel.setFrame(screen.frame, display: false)
            panels[displayID] = panel
            views[displayID] = view
            if screen.frame.contains(mouse) {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
        }
        NSCursor.crosshair.set()
        let elapsed = ContinuousClock.now - started
        logger.notice("Selection overlay shown in \(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000) ms")
    }

    /// Replaces the live screen under the dim layer with the frozen Captures.
    func freeze(with captures: [DisplayCapture]) {
        for capture in captures {
            views[capture.displayID]?.image = capture.image
        }
    }

    /// Waits for the user's box. Returns nil when they cancel with Esc or make a drag too
    /// small to be deliberate.
    func select() async -> Selection? {
        if let earlyResult {
            self.earlyResult = nil
            return earlyResult
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    private func finish(_ selection: Selection?) {
        panels.values.forEach { $0.orderOut(nil) }
        panels = [:]
        views = [:]
        NSCursor.arrow.set()
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: selection)
        } else {
            earlyResult = .some(selection)
        }
    }
}

/// The dim layer with the selected box cut out of it, over the live screen at first and the
/// frozen image once it arrives.
private final class SelectionView: NSView {
    /// Drags smaller than this, in points, count as a cancel.
    private static let minimumSize: CGFloat = 6

    private let onFinish: (CGRect?) -> Void
    private let dimLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private var dragStart: CGPoint?
    private var selection: CGRect?

    var image: CGImage? {
        didSet {
            layer?.contents = image
        }
    }

    init(onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
        super.init(frame: .zero)
        wantsLayer = true
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
