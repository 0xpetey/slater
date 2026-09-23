import SwiftUI

struct MenuContent: View {
    let appState: AppState

    var body: some View {
        Button("Take Shot") { appState.takeShot() }
        if !appState.isReady {
            Button("Finish Setup…") { appState.showOnboarding() }
        }
        if !appState.shots.windows.isEmpty {
            Divider()
            Section("Open Shots") {
                ForEach(appState.shots.windows) { window in
                    Button {
                        window.show()
                    } label: {
                        Image(nsImage: window.thumbnail)
                        Text(window.shot.summary)
                    }
                }
                Button("Close All Shots") { appState.shots.closeAll() }
            }
        }
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Button("Quit Slater") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
