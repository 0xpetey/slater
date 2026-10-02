import AppKit
@preconcurrency import KeyboardShortcuts
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
            .withSymbolConfiguration(.init(pointSize: 13.5, weight: .regular))
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
        observeLiveTranslation()
    }

    /// The lizard breathes while live translation runs.
    private func observeLiveTranslation() {
        withObservationTracking {
            if appState.live.isRunning {
                iconView.addSymbolEffect(.breathe, options: .repeating)
            } else {
                iconView.removeSymbolEffect(ofType: .breathe)
            }
        } onChange: {
            Task { @MainActor [weak self] in self?.observeLiveTranslation() }
        }
    }

    // AppKit sends the tracking area's owner `mouseEntered:`. Swift would derive
    // `mouseEnteredWith:` from the label on a non-override, so the selectors are spelled out.
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) {
        iconView.addSymbolEffect(.rotate, options: .repeating)
    }

    @objc(mouseExited:) func mouseExited(with event: NSEvent) {
        iconView.removeSymbolEffect(ofType: .rotate)
    }

    /// Rebuilt each time it opens, so the Open Shots list and the hotkeys are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item("Take Shot", #selector(takeShot), hotkey: .takeShot))
        menu.addItem(item("Take Shot of Front Window", #selector(takeWindowShot), hotkey: .takeWindowShot))
        let live = appState.live
        menu.addItem(item(
            live.isRunning && !live.scope.isWindow ? "Stop Live Translation" : "Start Live Translation",
            #selector(toggleLiveTranslation), hotkey: .toggleLiveTranslation
        ))
        menu.addItem(item(
            live.isRunning && live.scope.isWindow ? "Stop Live Translation of Front Window" : "Start Live Translation of Front Window",
            #selector(toggleLiveWindowTranslation), hotkey: .toggleLiveWindowTranslation
        ))
        if live.isRunning {
            menu.addItem(item(
                appState.live.isFrozen ? "Unfreeze Screen" : "Freeze Screen",
                #selector(toggleFreeze), hotkey: .freezeLiveTranslation
            ))
        }
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

    /// `key` is a fixed ⌘ key; `hotkey` is one the user can rebind in Settings, shown as it is
    /// bound now. The menu is rebuilt on each open, so the item reads the binding once rather than
    /// observing it with `setShortcut(for:)`, whose observer keeps every discarded item alive.
    private func item(_ title: String, _ action: Selector, key: String = "", hotkey: KeyboardShortcuts.Name? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        if let hotkey {
            item.setShortcut(hotkey.shortcut)
        }
        return item
    }

    @objc private func takeShot() {
        appState.takeShot()
    }

    @objc private func takeWindowShot() {
        appState.takeWindowShot()
    }

    @objc private func toggleLiveTranslation() {
        appState.toggleLiveTranslation()
    }

    @objc private func toggleLiveWindowTranslation() {
        appState.toggleLiveWindowTranslation()
    }

    @objc private func toggleFreeze() {
        appState.live.toggleFreeze()
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
