@preconcurrency import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Take Shot:", name: .takeShot)
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            // Menu bar apps don't come to the front on their own.
            NSApp.activate()
        }
    }
}
