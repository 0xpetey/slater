import SwiftUI

struct MenuContent: View {
    let appState: AppState

    var body: some View {
        Button("Take Shot") { appState.takeShot() }
        if !appState.isReady {
            Button("Finish Setup…") { appState.showOnboarding() }
        }
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit Slater") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
