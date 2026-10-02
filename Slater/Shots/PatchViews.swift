import SwiftUI

/// One Block's patch. It observes only its own translation slot, so a translation arriving
/// for another Block doesn't re-render it.
struct PatchView: View {
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
struct TranslatedPatch: View {
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
