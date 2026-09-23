import AppKit
import Observation
import SwiftUI
@preconcurrency import Translation

/// A floating window for one Shot. It opens exactly over the text it came from and can be
/// dragged anywhere to keep for reference.
@MainActor
final class ShotWindowController: Identifiable {
    let shot: Shot
    /// A small copy of the original image for the menu bar's Open Shots list.
    let thumbnail: NSImage
    private let translator: Translator
    private let panel: KeyablePanel
    private let viewState = ShotViewState()
    private var details: DetailsPanelController?
    private var spaceDownAt: TimeInterval?
    private let onClose: (ShotWindowController) -> Void

    /// A Space press held longer than this is a peek: the English comes back on release.
    private static let peekThreshold: TimeInterval = 0.35

    init(shot: Shot, translator: Translator, onClose: @escaping (ShotWindowController) -> Void) {
        self.shot = shot
        self.translator = translator
        self.onClose = onClose
        let thumbnailHeight: CGFloat = 18
        let aspect = CGFloat(shot.image.width) / CGFloat(shot.image.height)
        thumbnail = NSImage(cgImage: shot.image, size: CGSize(width: min(thumbnailHeight * aspect, 64), height: thumbnailHeight))
        panel = KeyablePanel(contentRect: shot.screenRect)
        panel.level = .floating
        panel.hasShadow = true

        let container = ShotContainerView(rootView: ShotView(
            shot: shot,
            state: viewState,
            translator: translator,
            onSave: { [weak self] in self?.save() },
            onSelect: { [weak self] display in self?.select(display) },
            onClose: { [weak self] in self?.close() }
        ))
        container.onKeyDown = { [weak self] event in self?.keyDown(event) ?? false }
        container.onKeyUp = { [weak self] event in self?.keyUp(event) ?? false }
        panel.contentView = container
        panel.setFrame(shot.screenRect, display: false)
        panel.makeFirstResponder(container)
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        details?.close()
        panel.orderOut(nil)
        onClose(self)
    }

    /// Shows the original, or one model's translations, translating with that model first if
    /// this Shot hasn't used it yet. If the model isn't installed, asks macOS to download it.
    func select(_ display: ShotDisplay) {
        guard let model = display.model else {
            viewState.showsOriginal = true
            return
        }
        switch translator.status(of: model) {
        case .installed:
            viewState.showsOriginal = false
            shot.displayedModel = model
            Task { await translator.translate(shot, using: model) }
        case .needsDownload:
            NSApp.activate()
            viewState.downloadModel = model
            viewState.downloadConfiguration = model.downloadConfiguration
        case .checking, .unsupported:
            break
        }
    }

    private func keyDown(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            guard event.charactersIgnoringModifiers == "s" else { return false }
            save()
            return true
        }
        switch event.keyCode {
        case 53: // Esc
            close()
        case 49: // Space: tap to toggle the original, hold to peek at it
            if !event.isARepeat {
                viewState.showsOriginal.toggle()
                spaceDownAt = event.timestamp
            }
        default:
            switch event.charactersIgnoringModifiers {
            case "d": showDetails()
            case "o": select(.original)
            case "f": select(.fast)
            case "a": select(.accurate)
            default: return false
            }
        }
        return true
    }

    private func keyUp(_ event: NSEvent) -> Bool {
        guard event.keyCode == 49, let spaceDownAt else { return false }
        if event.timestamp - spaceDownAt > Self.peekThreshold {
            viewState.showsOriginal.toggle()
        }
        self.spaceDownAt = nil
        return true
    }

    /// Asks where to save, in which format, then writes the files (ADR 0001: only on request).
    func save() {
        let choice = FormatChoice()
        let savePanel = NSSavePanel()
        savePanel.title = "Save Shot"
        savePanel.nameFieldStringValue = shot.defaultName
        savePanel.canCreateDirectories = true
        savePanel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        let picker = NSHostingView(rootView: FormatPicker(choice: choice))
        picker.frame.size = picker.fittingSize
        savePanel.accessoryView = picker
        NSApp.activate()

        savePanel.begin { [weak self] response in
            guard let self, response == .OK, let url = savePanel.url else { return }
            MainActor.assumeIsolated {
                ShotExporter.Format.lastUsed = choice.format
                let name = ["pdf", "png", "md"].contains(url.pathExtension.lowercased()) ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
                do {
                    let translated = renderTranslatedImage() ?? shot.image
                    try ShotExporter.write(
                        original: shot.image,
                        translated: translated,
                        markdown: shot.markdown(title: name),
                        pdf: choice.format == .pdf ? ShotPDF.make(shot: shot, translatedImage: translated, title: name) : Data(),
                        format: choice.format,
                        directory: url.deletingLastPathComponent(),
                        baseName: name
                    )
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    /// The Shot as it looks with the displayed model's translations, at the original image's resolution.
    private func renderTranslatedImage() -> CGImage? {
        let renderer = ImageRenderer(content: ShotView(shot: shot, state: viewState, translator: translator, isExporting: true, onClose: {}))
        renderer.scale = CGFloat(shot.image.width) / shot.screenRect.width
        return renderer.cgImage
    }

    private func showDetails() {
        if details == nil {
            details = DetailsPanelController(shot: shot, translator: translator, onSelectModel: { [weak self] model in
                self?.select(ShotDisplay(model: model))
            })
        }
        details?.show()
    }
}

@MainActor
@Observable
final class ShotViewState {
    var showsOriginal = false
    /// Set to ask macOS to download a model; the Shot view runs the download, then shows it.
    var downloadModel: Translator.Model?
    var downloadConfiguration: TranslationSession.Configuration?
}

@MainActor
@Observable
private final class FormatChoice {
    var format = ShotExporter.Format.lastUsed
}

private struct FormatPicker: View {
    @Bindable var choice: FormatChoice

    var body: some View {
        Picker("Format:", selection: $choice.format) {
            ForEach(ShotExporter.Format.allCases) { Text($0.title).tag($0) }
        }
        .fixedSize()
        .padding(10)
    }
}

/// Hosts the SwiftUI Shot view and receives its key presses.
private final class ShotContainerView: NSView {
    var onKeyDown: (NSEvent) -> Bool = { _ in false }
    var onKeyUp: (NSEvent) -> Bool = { _ in false }

    init(rootView: some View) {
        super.init(frame: .zero)
        let hosting = NSHostingView(rootView: rootView)
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if !onKeyDown(event) { super.keyDown(with: event) }
    }

    override func keyUp(with event: NSEvent) {
        if !onKeyUp(event) { super.keyUp(with: event) }
    }
}
