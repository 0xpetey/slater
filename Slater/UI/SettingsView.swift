@preconcurrency import KeyboardShortcuts
import SwiftUI
@preconcurrency import Translation

/// Settings in a window of our own, since AppKit's app lifecycle has no SwiftUI Settings scene
/// (ADR 0004). It reopens where it was left, and in the middle of the screen the first time.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    /// `onHelp` opens Slater Help, for the button at the foot of the window.
    init(translator: Translator, live: LiveTranslationController, onHelp: @escaping () -> Void) {
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Slater Settings"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(translator: translator, live: live, onHelp: onHelp))
        if !window.setFrameUsingName("Settings") {
            window.center()
        }
        window.setFrameAutosaveName("Settings")
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct SettingsView: View {
    let translator: Translator
    let live: LiveTranslationController
    let onHelp: () -> Void
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var fastDownload: TranslationSession.Configuration?
    @State private var accurateDownload: TranslationSession.Configuration?

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Take Shot:", name: .takeShot)
            KeyboardShortcuts.Recorder("Shot of Front Window:", name: .takeWindowShot)
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
                    // Wraps, rather than trailing off with an ellipsis.
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Live translation") {
                Toggle("Translate the screen as it changes", isOn: Binding(get: { live.isEnabled }, set: { live.isEnabled = $0 }))
                Text("Experimental: the whole screen, or the front window, translated as it changes, with no box to draw. Adds Start Live Translation to the menu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if live.isEnabled {
                    KeyboardShortcuts.Recorder("Live Screen:", name: .toggleLiveTranslation)
                    KeyboardShortcuts.Recorder("Live Window:", name: .toggleLiveWindowTranslation)
                    KeyboardShortcuts.Recorder("Freeze Live Screen:", name: .freezeLiveTranslation)
                }
            }

            Section("Help") {
                Button("Slater Help", action: onHelp)
                Text("A few pages that walk through what Slater does.")
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
