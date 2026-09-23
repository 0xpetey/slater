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
    @State private var download: TranslationSession.Configuration?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Slater translates the Japanese text in any part of your screen. Everything stays on this Mac.")
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
                    switch translator.languagePack {
                    case .checking:
                        Label("Checking the Japanese language pack…", systemImage: "hourglass")
                    case .installed:
                        Label("Japanese language pack installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .needsDownload:
                        Label("Japanese language pack needed", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text("Translation runs on this Mac, so macOS needs to download the Japanese ↔ English language pack once.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Download…") {
                            download = TranslationSession.Configuration(source: Translator.source, target: Translator.target)
                        }
                    case .unsupported:
                        Label("Japanese to English isn't available on this Mac", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }
            // Asks macOS to download the pack, showing its own confirmation dialog.
            .translationTask(download) { session in
                try? await session.prepareTranslation()
                await translator.refreshLanguagePack()
            }

            if let shortcut = KeyboardShortcuts.getShortcut(for: .takeShot) {
                Text("Press **\(shortcut.description)** to take a Shot. You can change this in Settings.")
            }

            HStack {
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!permissions.hasScreenRecording || translator.languagePack != .installed)
            }
        }
        .padding(20)
        .frame(width: 420)
        .task {
            // Picks up the grant if macOS reports it without a restart.
            while !Task.isCancelled && !permissions.hasScreenRecording {
                try? await Task.sleep(for: .seconds(1))
                permissions.refresh()
            }
        }
    }
}
