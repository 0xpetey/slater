import SwiftUI

/// The Shot's frozen image with an English patch over each Japanese Block.
struct ShotView: View {
    let shot: Shot
    let state: ShotViewState
    let patches: [Patch]
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: shot.image, scale: 1)
                .resizable()
                .interpolation(.high)
                .gesture(WindowDragGesture())

            if !state.showsOriginal {
                ForEach(patches) { patch in
                    if let translation = shot.translations[patch.index] {
                        PatchView(patch: patch, translation: translation, isLowConfidence: shot.blocks[patch.index].isLowConfidence)
                            .frame(width: patch.frame.width, height: patch.frame.height)
                            .offset(x: patch.frame.minX, y: patch.frame.minY)
                    }
                }
            }
        }
        .frame(width: shot.screenRect.width, height: shot.screenRect.height)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 4) {
                if shot.state == .translating {
                    ProgressView().controlSize(.small)
                } else if shot.state == .failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Translation failed")
                }
                if isHovering {
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
        .overlay(alignment: .bottomLeading) {
            if state.showsOriginal {
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
    }
}

/// One Block's translation, on a patch of its background color.
private struct PatchView: View {
    let patch: Patch
    let translation: String
    let isLowConfidence: Bool
    @State private var showsFullText = false

    var body: some View {
        let fit = FitText.fit(translation, in: patch.frame.size, lineHeight: patch.lineHeight)
        let background = patch.background
        Text(translation)
            .font(.system(size: fit.fontSize))
            .lineLimit(fit.lineLimit)
            .truncationMode(.tail)
            .minimumScaleFactor(0.9)
            .foregroundStyle(background.luminance > 0.5 ? Color.black : Color.white)
            .padding(.horizontal, FitText.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Color(red: background.red, green: background.green, blue: background.blue))
            .overlay(alignment: .bottom) {
                if isLowConfidence {
                    HorizontalLine()
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .frame(height: 1.5)
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
}

private struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}
