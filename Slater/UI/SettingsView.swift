@preconcurrency import KeyboardShortcuts
import SwiftUI
@preconcurrency import Translation

struct SettingsView: View {
    let translator: Translator
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var download: TranslationSession.Configuration?

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Take Shot:", name: .takeShot)
            Toggle("Open Slater when you log in", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    LaunchAtLogin.isEnabled = enabled
                    launchAtLogin = LaunchAtLogin.isEnabled
                }

            Section {
                Picker("Translation model:", selection: Binding(get: { translator.model }, set: { translator.setModel($0) })) {
                    ForEach(Translator.Model.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                if translator.model == .fast {
                    switch translator.fastModel {
                    case .installed:
                        Text("Fast is a smaller model, so check its wording on anything important.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .needsDownload:
                        Text("macOS needs to download the Fast model once. Until then, Accurate is used.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Download…") {
                            download = TranslationSession.Configuration(source: Translator.source, target: Translator.target, preferredStrategy: .lowLatency)
                        }
                    case .checking:
                        Text("Checking…").foregroundStyle(.secondary)
                    case .unsupported:
                        Text("The Fast model isn't available on this Mac, so Accurate is used.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            // Asks macOS to download the model, showing its own confirmation dialog.
            .translationTask(download) { session in
                try? await session.prepareTranslation()
                await translator.refreshLanguagePack()
                translator.warmUp()
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            // Menu bar apps don't come to the front on their own.
            NSApp.activate()
        }
    }
}
