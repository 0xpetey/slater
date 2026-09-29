@preconcurrency import KeyboardShortcuts
import SwiftUI
@preconcurrency import Translation

struct SettingsView: View {
    let translator: Translator
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var fastDownload: TranslationSession.Configuration?
    @State private var accurateDownload: TranslationSession.Configuration?

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Take Shot:", name: .takeShot)
            Toggle("Open Slater when you log in", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    LaunchAtLogin.isEnabled = enabled
                    launchAtLogin = LaunchAtLogin.isEnabled
                }

            Section("Languages") {
                LanguagePickers(translator: translator)
                ModelStatusRows(translator: translator, fastDownload: $fastDownload, accurateDownload: $accurateDownload)
                    .font(.callout)
            }

            Section("Translation model") {
                Picker("Translation model:", selection: Binding(get: { translator.model }, set: { translator.setModel($0) })) {
                    ForEach(Translator.Model.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text(translator.model == .fast
                     ? "About 20 ms per text. Any Shot can be translated again with Accurate (press A on it)."
                     : "About half a second per text, sometimes better wording.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
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
        .padding(20)
        .frame(width: 460)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            // Menu bar apps don't come to the front on their own.
            NSApp.activate()
        }
    }
}
