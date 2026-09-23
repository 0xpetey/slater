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
    let onClose: () -> Void
    @State private var isHovering = false

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
        .overlay(alignment: .topTrailing) {
            if !isExporting { controls }
        }
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
            await translator.refreshModels()
            if let model, translator.status(of: model) == .installed {
                onSelect(ShotDisplay(model: model))
            }
        }
    }

    private var selection: ShotDisplay {
        state.showsOriginal ? .original : ShotDisplay(model: shot.displayedModel)
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
            if isHovering {
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
    }
}

/// One Block's patch. It observes only its own translation slot, so a translation arriving
/// for another Block doesn't re-render it.
private struct PatchView: View {
    let patch: Patch
    let slot: Shot.TranslationSlot
    let model: Translator.Model
    let isLowConfidence: Bool

    var body: some View {
        if let translation = slot.text(for: model) {
            TranslatedPatch(patch: patch, translation: translation, isLowConfidence: isLowConfidence)
        }
    }
}

/// One Block's translation, on a patch of its background color.
private struct TranslatedPatch: View {
    let patch: Patch
    let translation: String
    let isLowConfidence: Bool
    @State private var showsFullText = false

    var body: some View {
        let size = patch.frame.size
        let across = FitText.fit(translation, in: size, lineHeight: patch.lineHeight)
        // A narrow column of vertical writing often fits more legible English turned sideways,
        // reading top to bottom as Latin text does in Japanese vertical layouts.
        let sideways = patch.isVertical
            ? FitText.fit(translation, in: CGSize(width: size.height, height: size.width), lineHeight: patch.lineHeight)
            : nil
        let turn = sideways.map { $0.fontSize > across.fontSize || ($0.fontSize == across.fontSize && across.isTruncated && !$0.isTruncated) } ?? false
        let fit = turn ? sideways! : across
        let background = patch.background
        label(fit: fit, background: background)
            .frame(width: turn ? size.height : size.width, height: turn ? size.width : size.height)
            .rotationEffect(.degrees(turn ? 90 : 0))
            .frame(width: size.width, height: size.height)
            .background(Color(red: background.red, green: background.green, blue: background.blue))
            .overlay {
                // A dashed orange box marks a Block whose OCR may be wrong.
                if isLowConfidence {
                    Rectangle()
                        .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                }
            }
            .clipped()
            .onHover { hovering in
                showsFullText = hovering && (fit.isTruncated || isLowConfidence)
            }
            .popover(isPresented: $showsFullText, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    if isLowConfidence {
                        Label("Low OCR confidence", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(translation)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: 320, alignment: .leading)
            }
    }

    private func label(fit: FitText.Fit, background: ColorSampler.RGB) -> some View {
        Text(translation)
            .font(.system(size: fit.fontSize))
            .lineLimit(fit.lineLimit)
            .truncationMode(.tail)
            .minimumScaleFactor(0.9)
            .foregroundStyle(background.luminance > 0.5 ? Color.black : Color.white)
            .padding(.horizontal, FitText.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
