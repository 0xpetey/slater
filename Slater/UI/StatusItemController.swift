import AppKit
import SwiftUI
import Symbols

/// The lizard in the menu bar and its menu. AppKit rather than SwiftUI's `MenuBarExtra`,
/// because that renders its label as a still picture and gets no hover events, and this lizard
/// spins while the pointer is over it.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let appState: AppState
    private let statusItem: NSStatusItem
    /// Symbol effects are an `NSImageView` feature, so the button hosts one instead of an image.
    private let iconView = NSImageView()
    private let menu = NSMenu()
    private var settingsWindow: NSWindow?

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: 28)
        super.init()

        guard let button = statusItem.button else { return }
        let lizard = NSImage(systemSymbolName: "lizard.fill", accessibilityDescription: "Slater")?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        lizard?.isTemplate = true
        iconView.image = lizard
        iconView.imageScaling = .scaleNone
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        button.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil
        ))

        menu.delegate = self
        statusItem.menu = menu
    }

    // AppKit sends the tracking area's owner `mouseEntered:`. Swift would derive
    // `mouseEnteredWith:` from the label on a non-override, so the selectors are spelled out.
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) {
        iconView.addSymbolEffect(.rotate, options: .repeating)
    }

    @objc(mouseExited:) func mouseExited(with event: NSEvent) {
        iconView.removeSymbolEffect(ofType: .rotate)
    }

    /// Rebuilt each time it opens, so the Open Shots list is current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Take Shot", #selector(takeShot)))
        if !appState.isReady {
            menu.addItem(item("Finish Setup…", #selector(finishSetup)))
        }

        let windows = appState.shots.windows
        if !windows.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Open Shots", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for window in windows {
                let shotItem = item(window.shot.summary, #selector(showShot(_:)))
                shotItem.image = window.thumbnail
                shotItem.representedObject = window
                menu.addItem(shotItem)
            }
            menu.addItem(item("Close All Shots", #selector(closeAllShots)))
        }

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit Slater", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func takeShot() {
        appState.takeShot()
    }

    @objc private func finishSetup() {
        appState.showOnboarding()
    }

    @objc private func showShot(_ sender: NSMenuItem) {
        (sender.representedObject as? ShotWindowController)?.show()
    }

    @objc private func closeAllShots() {
        appState.shots.closeAll()
    }

    @objc private func openSettings() {
        NSApp.activate()
        // SwiftUI's Settings scene answers this; if it ever doesn't, host the view ourselves.
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            if settingsWindow == nil {
                let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
                window.title = "Slater Settings"
                window.isReleasedWhenClosed = false
                window.contentViewController = NSHostingController(rootView: SettingsView(translator: appState.translator))
                window.center()
                settingsWindow = window
            }
            settingsWindow?.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
