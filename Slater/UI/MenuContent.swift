import SwiftUI

struct MenuContent: View {
    let appState: AppState

    var body: some View {
        Button("Take Shot") { appState.takeShot() }
        if !appState.permissions.hasScreenRecording {
            Button("Grant Screen Recording…") { appState.showOnboarding() }
        }
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit Slater") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
