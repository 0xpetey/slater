import SwiftUI
@preconcurrency import Translation

/// What a Shot window shows: the original Japanese, or one model's translations.
enum ShotDisplay: Hashable {
    case original, fast, accurate

    init(model: Translator.Model) {
        self = model == .fast ? .fast : .accurate
    }

    var model: Translator.Model? {
        switch self {
        case .original: nil
        case .fast: .fast
        case .accurate: .accurate
        }
    }
}

/// The Shot's frozen image with an English patch over each Japanese Block.
struct ShotView: View {
    let shot: Shot
    let state: ShotViewState
    let translator: Translator
    /// Rendering for a saved image: translations only, no controls.
    var isExporting = false
    var onSave: () -> Void = {}
    var onSelect: (ShotDisplay) -> Void = { _ in }
    /// Shows the controls bar without hovering, for previews and snapshots.
    var alwaysShowsControls = false
    let onClose: () -> Void
    @State private var isHovering = false

    /// How far the bar's shading extends down from the top edge, in points.
    private static let barHeight: CGFloat = 40

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: shot.image, scale: 1)
                .resizable()
                .interpolation(.high)
                .gesture(WindowDragGesture())

            if isExporting || !state.showsOriginal {
                ForEach(shot.patches) { patch in
                    if let slot = shot.slot(for: patch.index) {
                        PatchView(patch: patch, slot: slot, model: shot.displayedModel, isLowConfidence: shot.blocks[patch.index].isLowConfidence)
                            .frame(width: patch.frame.width, height: patch.frame.height)
                            .offset(x: patch.frame.minX, y: patch.frame.minY)
                    }
                }
            }
        }
        .frame(width: shot.screenRect.width, height: shot.screenRect.height)
        .overlay(alignment: .top) {
            // Shading behind the bar, so its white labels read on a white page.
            if !isExporting && showsControls {
                LinearGradient(colors: [.black.opacity(0.65), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.barHeight)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !isExporting { controls }
        }
        .animation(.easeInOut(duration: 0.15), value: showsControls)
        .overlay(alignment: .bottomLeading) {
            if state.showsOriginal && !isExporting {
                Text("Original")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: .capsule)
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
        .onHover { isHovering = $0 }
        // Asks macOS to download a model, showing its own confirmation dialog, then shows the
        // Shot with it.
        .translationTask(state.downloadConfiguration) { session in
            try? await session.prepareTranslation()
            let model = state.downloadModel
            state.downloadConfiguration = nil
            state.downloadModel = nil
            await translator.refresh()
            if let model, translator.status(of: model) == .installed {
                onSelect(ShotDisplay(model: model))
            }
        }
    }

    private var selection: ShotDisplay {
        state.showsOriginal ? .original : ShotDisplay(model: shot.displayedModel)
    }

    private var showsControls: Bool {
        isHovering || alwaysShowsControls
    }

    private var controls: some View {
        HStack(spacing: 4) {
            // Busy until the displayed model's translations are in and the corrected OCR
            // reading has been applied.
            if shot.state == .translating || !shot.isVerified {
                ProgressView().controlSize(.small)
            } else if shot.state == .failed {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Translation failed")
            }
            if showsControls {
                Picker("View", selection: Binding(get: { selection }, set: { onSelect($0) })) {
                    Text("Original").tag(ShotDisplay.original)
                    if translator.status(of: .fast) != .unsupported {
                        Text("Fast").tag(ShotDisplay.fast)
                    }
                    if translator.status(of: .accurate) != .unsupported {
                        Text("Accurate").tag(ShotDisplay.accurate)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
                .help("Show the original (O), or the Fast (F) or Accurate (A) translation")
                Button(action: onSave) {
                    Image(systemName: "square.and.arrow.down.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 16, height: 16)
                        .background(.black.opacity(0.6), in: .circle)
                }
                .buttonStyle(.plain)
                .help("Save (⌘S)")
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
            }
        }
        .padding(4)
        // The bar sits on dark shading, so its controls use their dark-appearance styling.
        .colorScheme(.dark)
    }
}
