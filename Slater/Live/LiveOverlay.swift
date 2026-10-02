import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class LiveOverlayState {
    /// The latest pass over the display, or nil while the overlay is cleared.
    var shot: Shot?
    /// Patches hidden because the screen under them changed since the pass.
    var hiddenPatches: Set<Int> = []
}

/// A transparent, click-through panel over one display carrying the live patches, so the user
/// keeps working underneath it.
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
        panel.contentView = NSHostingView(rootView: LiveOverlayView(state: state))
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

    func close() {
        panel.orderOut(nil)
    }
}

/// The patches of the latest pass, over nothing: the live screen shows through.
struct LiveOverlayView: View {
    let state: LiveOverlayState

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let shot = state.shot {
                ForEach(shot.patches) { patch in
                    if !state.hiddenPatches.contains(patch.index), let slot = shot.slot(for: patch.index) {
                        PatchView(patch: patch, slot: slot, model: shot.displayedModel, isLowConfidence: false)
                            .frame(width: patch.frame.width, height: patch.frame.height)
                            .offset(x: patch.frame.minX, y: patch.frame.minY)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
