import AppKit
import Observation
import SwiftUI

/// What live translation is doing on a display, for the badge that's always on screen.
enum LiveStatus: Equatable {
    /// The last pass found no text in the source language, named here.
    case noSource(String)
    /// The screen changed in a way worth reading; waiting for it to settle.
    case updateDetected
    /// A pass is reading and translating the screen. Patches appear part-way through, when the
    /// quick reading is in; the corrected reading may still adjust them.
    case processing
    /// The last pass's translations are on screen.
    case done

    var caption: String {
        switch self {
        case .noSource(let language): "No \(language) Detected"
        case .updateDetected: "Screen Update Detected"
        case .processing: "Processing"
        case .done: "Done"
        }
    }

    var symbol: String {
        switch self {
        case .noSource: "text.magnifyingglass"
        case .updateDetected: "rectangle.dashed"
        case .processing: "gearshape.fill"
        case .done: "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .noSource: .gray
        case .updateDetected: .orange
        case .processing: .blue
        case .done: .green
        }
    }
}

/// What the overlay shows for one live loop: a display, or a window, whose state every
/// display's panel shares, since a window can straddle displays.
@MainActor
@Observable
final class LiveOverlayState {
    /// The latest pass, or nil while the overlay is cleared.
    var shot: Shot?
    /// Patches hidden because what's under them changed since the pass.
    var hiddenPatches: Set<Int> = []
    /// The first frame always reads as a change, so this is right from the start.
    var status: LiveStatus = .updateDetected
    /// The frame held while frozen, shown in place of the live screen.
    var frozenImage: CGImage?
    /// How to resume, for the badge.
    var frozenHint: String?
    /// How to end live translation, for the badge.
    var endHint = "Click to end"
    /// Where the patches go: the display, or the live window, in the window server's
    /// coordinates (origin at the main screen's top-left, y down). Nil while the live window is
    /// off screen, when nothing is shown.
    var region: CGRect?
    /// Parts of the region under other windows, relative to its top-left. Patches there aren't
    /// drawn while live, so a window over the live one isn't painted with its translations.
    var occluded: [CGRect] = []

    /// Shows a pass's patches, except those over content that changed since the pass read it.
    func show(_ shot: Shot, hiding stale: (Patch) -> Bool) {
        self.shot = shot
        hiddenPatches = Set(shot.patches.filter(stale).map(\.index))
    }

    /// Hides the patches whose content changed, keeping the rest until the next pass lands.
    func hide(where changed: (Patch) -> Bool) {
        guard let shot else { return }
        hiddenPatches.formUnion(shot.patches.filter(changed).map(\.index))
    }

    func clear() {
        shot = nil
        hiddenPatches = []
    }

    /// Holds the overlay at `image`.
    func freeze(_ image: CGImage, hint: String?) {
        frozenImage = image
        frozenHint = hint
    }

    func unfreeze() {
        frozenImage = nil
    }
}

/// A transparent, click-through panel over one display carrying the live patches, so the user
/// keeps working underneath it. While frozen it takes the mouse, over the whole display, and a
/// click unfreezes.
@MainActor
final class LiveOverlayController {
    /// Called on a click while the panel takes them.
    var onClick: (() -> Void)?
    private let panel: NSPanel

    init(screen: NSScreen, state: LiveOverlayState) {
        panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Where the display sits in the window server's coordinates, and how far the menu bar
        // reaches down it, for the view to place things by.
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let origin = CoordinateMapper.flippedGlobalRect(screen.frame, mainScreenHeight: mainHeight).origin
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let content = ClickableHostingView(rootView: LiveOverlayView(state: state, origin: origin, menuBarHeight: menuBarHeight))
        content.onClick = { [weak self] in self?.onClick?() }
        panel.contentView = content
        panel.setFrame(screen.frame, display: false)
        panel.orderFrontRegardless()
    }

    /// A click on a frozen picture of the screen must not land on whatever is under it now, so
    /// while frozen the panel takes the mouse, and a click unfreezes instead.
    var takesClicks: Bool {
        get { !panel.ignoresMouseEvents }
        set { panel.ignoresMouseEvents = !newValue }
    }

    func close() {
        panel.orderOut(nil)
    }
}

/// Reports clicks, including the first one in a window that isn't key, which is this panel's
/// normal state.
private final class ClickableHostingView<Content: View>: NSHostingView<Content> {
    var onClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// The patches of the latest pass, over nothing: the live screen shows through, unless the
/// display is frozen, when the held frame shows instead, inside a blue border. All of it is
/// drawn within the region being translated, the whole display or a window.
struct LiveOverlayView: View {
    let state: LiveOverlayState
    /// The display's top-left corner in the window server's coordinates.
    let origin: CGPoint
    let menuBarHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let region = state.region {
                let local = region.offsetBy(dx: -origin.x, dy: -origin.y)
                content(in: local)
                    .frame(width: local.width, height: local.height)
                    .offset(x: local.minX, y: local.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func content(in region: CGRect) -> some View {
        // How far the region reaches under the menu bar.
        let top = max(0, menuBarHeight - region.minY)
        // A frozen picture sits over whatever covers the window now, patches and all.
        let occluded = state.frozenImage == nil ? state.occluded : []
        return ZStack(alignment: .topLeading) {
            if let frozen = state.frozenImage {
                Image(decorative: frozen, scale: 1)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The real menu bar is translucent; the captured one would show through it.
                    .mask {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: top)
                            Color.black
                        }
                    }
            } else {
                Color.clear
            }
            if let shot = state.shot {
                ForEach(shot.patches) { patch in
                    if !state.hiddenPatches.contains(patch.index),
                       !occluded.contains(where: { $0.intersects(patch.frame) }),
                       let slot = shot.slot(for: patch.index) {
                        PatchView(patch: patch, slot: slot, model: shot.displayedModel, isLowConfidence: false)
                            .frame(width: patch.frame.width, height: patch.frame.height)
                            .offset(x: patch.frame.minX, y: patch.frame.minY)
                    }
                }
            }
            if state.frozenImage != nil {
                Rectangle()
                    .strokeBorder(.cyan.opacity(0.8), lineWidth: 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// The status badge, in a small panel of its own so that a click on it can end live
/// translation while the overlay around it stays click-through. It sits at the region's
/// top-right corner, clear of the menu bar and the Dock, follows the region, and grows and
/// shrinks with what it says.
@MainActor
final class LiveBadgeController {
    /// The badge's distance from the region's corner.
    static let inset: CGFloat = 16
    /// Called on a click.
    var onClick: (() -> Void)?
    private let state: LiveOverlayState
    private let panel: NSPanel
    private let content: ClickableHostingView<LiveBadgeView>

    init(state: LiveOverlayState) {
        self.state = state
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        content = ClickableHostingView(rootView: LiveBadgeView(state: state))
        content.onClick = { [weak self] in self?.onClick?() }
        panel.contentView = content
        observe()
    }

    /// Placed again whenever the region, or anything that changes the badge's size, changes.
    private func observe() {
        withObservationTracking {
            place()
        } onChange: {
            Task { @MainActor [weak self] in self?.observe() }
        }
    }

    private func place() {
        // Read here so a change to any of them places the badge again.
        let region = state.region
        _ = (state.status, state.frozenImage, state.frozenHint, state.endHint)
        guard let region else {
            panel.orderOut(nil)
            return
        }
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let global = CoordinateMapper.flippedGlobalRect(region, mainScreenHeight: mainHeight)
        let corner = CGPoint(x: global.maxX - 1, y: global.maxY - 1)
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.frame.contains(corner) })
            ?? screens.max(by: { Self.area($0.frame.intersection(global)) < Self.area($1.frame.intersection(global)) })
        else {
            panel.orderOut(nil)
            return
        }
        let visible = screen.visibleFrame
        let size = content.fittingSize
        let right = min(global.maxX, visible.maxX) - Self.inset + LiveBadgeView.margin
        let top = min(global.maxY, visible.maxY) - Self.inset + LiveBadgeView.margin
        panel.setFrame(CGRect(x: right - size.width, y: top - size.height, width: size.width, height: size.height), display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    func close() {
        panel.orderOut(nil)
    }
}

/// The badge with room around it for its shadow: the panel's transparent margin.
struct LiveBadgeView: View {
    static let margin: CGFloat = 20
    let state: LiveOverlayState

    var body: some View {
        LiveStatusBadge(
            status: state.status,
            frozenHint: state.frozenImage == nil ? nil : (state.frozenHint ?? ""),
            endHint: state.endHint
        )
        .padding(Self.margin)
    }
}

/// A large icon with the status spelled out under it, readable from across a video call, and
/// how to end live translation in small print at the bottom. While frozen, a snowflake strip
/// says so, with the way to resume.
struct LiveStatusBadge: View {
    let status: LiveStatus
    /// Nil while live; while frozen, the resume hint (possibly empty).
    let frozenHint: String?
    let endHint: String

    var body: some View {
        VStack(spacing: 8) {
            if let frozenHint {
                HStack(spacing: 5) {
                    Image(systemName: "snowflake")
                    Text("Frozen")
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.cyan)
                if !frozenHint.isEmpty {
                    Text(frozenHint)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
            }
            Image(systemName: status.symbol)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(status.color)
                .frame(height: 52)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: status == .processing)
                .symbolEffect(.pulse, options: .repeat(.continuous), isActive: status == .updateDetected)
            Text(status.caption)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(height: 34)
                // The symbol morphs; the words just switch, or they'd overlap mid-fade.
                .contentTransition(.identity)
            Text(endHint)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(width: 136)
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .animation(.default, value: status)
        .animation(.default, value: frozenHint)
    }
}
