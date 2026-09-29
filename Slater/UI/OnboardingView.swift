@preconcurrency import KeyboardShortcuts
import SwiftUI
@preconcurrency import Translation

@MainActor
final class OnboardingWindowController {
    private let window: NSWindow

    init(permissions: PermissionsManager, translator: Translator) {
        window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Slater"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: OnboardingView(permissions: permissions, translator: translator) { [weak window] in window?.close() }
        )
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct OnboardingView: View {
    let permissions: PermissionsManager
    let translator: Translator
    let onDone: () -> Void
    @State private var fastDownload: TranslationSession.Configuration?
    @State private var accurateDownload: TranslationSession.Configuration?
    @State private var launchAtLogin = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Slater translates the text in any part of your screen. Everything stays on this Mac.")
                .fixedSize(horizontal: false, vertical: true)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label(
                        permissions.hasScreenRecording ? "Screen Recording allowed" : "Screen Recording needed",
                        systemImage: permissions.hasScreenRecording ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(permissions.hasScreenRecording ? .green : .orange)

                    if !permissions.hasScreenRecording {
                        Text("Slater needs to see your screen to read the text you select.")
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Allow…") { permissions.requestScreenRecording() }
                            Button("Open System Settings") { permissions.openScreenRecordingSettings() }
                        }
                        Text("Already switched it on? macOS may need Slater to restart first.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Restart Slater") { permissions.relaunch() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    LanguagePickers(translator: translator)
                    Divider()
                    ModelStatusRows(translator: translator, fastDownload: $fastDownload, accurateDownload: $accurateDownload)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            // Asks macOS to download a model, showing its own confirmation dialog.
            .translationTask(fastDownload) { session in
                try? await session.prepareTranslation()
                await translator.refresh()
                translator.warmUp()
            }
            .translationTask(accurateDownload) { session in
                try? await session.prepareTranslation()
                await translator.refresh()
            }

            if let shortcut = KeyboardShortcuts.getShortcut(for: .takeShot) {
                Text("Press **\(shortcut.description)** to take a Shot. You can change this in Settings.")
            }

            Toggle("Open Slater when you log in", isOn: $launchAtLogin)

            HStack {
                Spacer()
                Button("Done") {
                    if launchAtLogin != LaunchAtLogin.isEnabled {
                        LaunchAtLogin.isEnabled = launchAtLogin
                    }
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!permissions.hasScreenRecording || translator.fastModel != .installed)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            // Picks up the grant if macOS reports it without a restart.
            while !Task.isCancelled && !permissions.hasScreenRecording {
                try? await Task.sleep(for: .seconds(1))
                permissions.refresh()
            }
        }
    }
}

/// "Translate from [Japanese] to [English]". Sources are the languages Vision can read.
struct LanguagePickers: View {
    let translator: Translator

    var body: some View {
        HStack {
            Text("Translate from")
            Picker("Translate from", selection: Binding(get: { translator.source }, set: { translator.setLanguages(source: $0, target: translator.target) })) {
                ForEach(translator.readableLanguages, id: \.minimalIdentifier) { language in
                    Text(Translator.name(of: language)).tag(language)
                }
            }
            .labelsHidden()
            Text("to")
            Picker("to", selection: Binding(get: { translator.target }, set: { translator.setLanguages(source: translator.source, target: $0) })) {
                ForEach(translator.supportedLanguages, id: \.minimalIdentifier) { language in
                    Text(Translator.name(of: language)).tag(language)
                }
            }
            .labelsHidden()
        }
        .disabled(translator.supportedLanguages.isEmpty)
    }
}

/// The Fast model (required) and the Accurate model (optional) for the chosen pair (ADR 0003).
struct ModelStatusRows: View {
    let translator: Translator
    @Binding var fastDownload: TranslationSession.Configuration?
    @Binding var accurateDownload: TranslationSession.Configuration?

    private var pair: String {
        "\(Translator.name(of: translator.source)) → \(Translator.name(of: translator.target))"
    }

    var body: some View {
        switch translator.fastModel {
        case .checking:
            Label("Checking the translation model…", systemImage: "hourglass")
        case .installed:
            Label("\(pair) model installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needsDownload:
            Label("\(pair) model needed", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text("Translation runs on this Mac, so macOS needs to download the model for this pair once.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Download…") { fastDownload = translator.downloadConfiguration(for: .fast) }
        case .unsupported:
            Label("\(pair) isn't available on this Mac", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }

        switch translator.accurateModel {
        case .checking:
            EmptyView()
        case .installed:
            Label("Accurate model installed (optional)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needsDownload:
            Label("Accurate model (optional)", systemImage: "arrow.down.circle")
            Text("A larger model that's slower but sometimes words things better. You can translate any Shot again with it, or make it the default in Settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Also download…") { accurateDownload = translator.downloadConfiguration(for: .accurate) }
        case .unsupported:
            Label("The Accurate model isn't available for this pair", systemImage: "minus.circle")
                .foregroundStyle(.secondary)
        }
    }
}
