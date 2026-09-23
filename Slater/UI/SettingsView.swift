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
                switch translator.status(of: translator.model) {
                case .installed:
                    Text(translator.model == .fast
                         ? "About 20 ms per text. Any Shot can be translated again with Accurate (press A on it)."
                         : "About half a second per text, sometimes better wording.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .needsDownload:
                    Text("macOS needs to download the \(translator.model.title) model once. Until then, \(translator.activeModel.title) is used.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Download…") { download = translator.model.downloadConfiguration }
                case .checking:
                    Text("Checking…").foregroundStyle(.secondary)
                case .unsupported:
                    Text("The \(translator.model.title) model isn't available on this Mac, so \(translator.activeModel.title) is used.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            // Asks macOS to download the model, showing its own confirmation dialog.
            .translationTask(download) { session in
                try? await session.prepareTranslation()
                await translator.refreshModels()
                translator.warmUp()
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            // Menu bar apps don't come to the front on their own.
            NSApp.activate()
        }
    }
}
