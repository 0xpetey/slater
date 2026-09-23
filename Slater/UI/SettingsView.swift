@preconcurrency import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Take Shot:", name: .takeShot)
            Toggle("Open Slater when you log in", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    LaunchAtLogin.isEnabled = enabled
                    launchAtLogin = LaunchAtLogin.isEnabled
                }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            // Menu bar apps don't come to the front on their own.
            NSApp.activate()
        }
    }
}
