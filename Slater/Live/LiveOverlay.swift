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

@MainActor
@Observable
final class LiveOverlayState {
    /// The latest pass over the display, or nil while the overlay is cleared.
    var shot: Shot?
    /// Patches hidden because the screen under them changed since the pass.
    var hiddenPatches: Set<Int> = []
    /// The first frame always reads as a change, so this is right from the start.
    var status: LiveStatus = .updateDetected
    /// The frame the display is held at while frozen, shown in place of the live screen.
    var frozenImage: CGImage?
    /// How to resume, for the badge.
    var frozenHint: String?
}

/// A transparent, click-through panel over one display carrying the live patches and the
/// status badge, so the user keeps working underneath it.
@MainActor
final class LiveOverlayController {
    let state = LiveOverlayState()
    private let panel: NSPanel

    init(screen: NSScreen) {
        panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // The badge sits in the top-right corner, clear of the menu bar and a Dock on that side.
        let insets = EdgeInsets(
            top: screen.frame.maxY - screen.visibleFrame.maxY, leading: 0,
            bottom: 0, trailing: screen.frame.maxX - screen.visibleFrame.maxX
        )
        panel.contentView = NSHostingView(rootView: LiveOverlayView(state: state, insets: insets))
        panel.setFrame(screen.frame, display: false)
        panel.orderFrontRegardless()
    }

    /// Shows a pass's patches, except those over screen that changed since the pass read it.
    func show(_ shot: Shot, hiding stale: (Patch) -> Bool) {
        state.shot = shot
        state.hiddenPatches = Set(shot.patches.filter(stale).map(\.index))
    }

    /// Hides the patches whose screen area changed, keeping the rest until the next pass lands.
    func hide(where changed: (Patch) -> Bool) {
        guard let shot = state.shot else { return }
        state.hiddenPatches.formUnion(shot.patches.filter(changed).map(\.index))
    }

    func clear() {
        state.shot = nil
        state.hiddenPatches = []
    }

    /// Holds the display at `image`. The panel takes the mouse meanwhile: a click on a frozen
    /// picture of the screen must not land on whatever is under it now.
    func freeze(_ image: CGImage, hint: String?) {
        state.frozenImage = image
        state.frozenHint = hint
        panel.ignoresMouseEvents = false
    }

    func unfreeze() {
        state.frozenImage = nil
        panel.ignoresMouseEvents = true
    }

    func close() {
        panel.orderOut(nil)
    }
}

/// The patches of the latest pass, over nothing: the live screen shows through, unless the
/// display is frozen, when the held frame shows instead, inside a blue border. The status
/// badge stays in the corner whatever the pass found.
struct LiveOverlayView: View {
    let state: LiveOverlayState
    let insets: EdgeInsets

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let frozen = state.frozenImage {
                Image(decorative: frozen, scale: 1)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The real menu bar is translucent; the captured one would show through it.
                    .mask {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: insets.top)
                            Color.black
                        }
                    }
            } else {
                Color.clear
            }
            if let shot = state.shot {
                ForEach(shot.patches) { patch in
                    if !state.hiddenPatches.contains(patch.index), let slot = shot.slot(for: patch.index) {
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
            LiveStatusBadge(status: state.status, frozenHint: state.frozenImage == nil ? nil : (state.frozenHint ?? ""))
                .padding(.top, insets.top + 16)
                .padding(.trailing, insets.trailing + 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A large icon with the status spelled out under it, readable from across a video call.
/// While frozen, a snowflake strip says so, with the way to resume.
struct LiveStatusBadge: View {
    let status: LiveStatus
    /// Nil while live; while frozen, the resume hint (possibly empty).
    let frozenHint: String?

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
