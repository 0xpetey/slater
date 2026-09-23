import AppKit
import SwiftUI

/// The Japanese ↔ English list for one Shot, with copy buttons.
@MainActor
final class DetailsPanelController {
    private let panel: NSPanel

    init(shot: Shot, onRerunWithAccurate: @escaping () -> Void) {
        panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Shot Details"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentViewController = NSHostingController(rootView: DetailsView(shot: shot, onRerunWithAccurate: onRerunWithAccurate))
        // Open beside the Shot rather than over it, so the two can be compared.
        panel.setFrameTopLeftPoint(CGPoint(x: shot.screenRect.maxX + 12, y: shot.screenRect.maxY))
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.close()
    }
}

private struct DetailsView: View {
    let shot: Shot
    let onRerunWithAccurate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if shot.state == .translating {
                    ProgressView().controlSize(.small)
                    Text("Translating…").foregroundStyle(.secondary)
                } else if shot.state == .failed {
                    Label("Translation failed", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else {
                    Text("\(shot.model.title) model").foregroundStyle(.secondary)
                }
                if shot.model == .fast {
                    Button("Rerun with Accurate", action: onRerunWithAccurate)
                        .disabled(shot.state == .translating)
                }
                Spacer()
                Button("Copy English") { copy(shot.englishText) }
                Button("Copy Japanese + English") { copy(shot.bilingualText) }
            }
            .padding(10)
            Divider()
            List(shot.japaneseBlockIndices, id: \.self) { index in
                DetailsRow(block: shot.blocks[index], translation: shot.translations[index])
            }
        }
        .frame(minWidth: 380, minHeight: 200)
    }
}

private struct DetailsRow: View {
    let block: Block
    let translation: String?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(block.text)
                    .textSelection(.enabled)
                    .padding(block.isLowConfidence ? 2 : 0)
                    .background(block.isLowConfidence ? Color.orange.opacity(0.25) : .clear, in: .rect(cornerRadius: 3))
                if block.isLowConfidence {
                    Text("Low OCR confidence: check against the original")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let translation {
                    Text(translation).textSelection(.enabled).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            Spacer()
            Button {
                copy(translation ?? "")
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .disabled(translation == nil)
            .help("Copy English")
        }
        .padding(.vertical, 4)
    }
}

/// Copying only happens when the user asks, so it's allowed under ADR 0001.
private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
