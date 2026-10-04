@preconcurrency import KeyboardShortcuts
import Observation
import SwiftUI

/// The pages of Slater Help, in the order they are shown.
enum HelpPage: Int, CaseIterable, Identifiable {
    case welcome, takeShot, readShot, checkTranslation, models, save, live, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .welcome: "Welcome to Slater"
        case .takeShot: "Take a Shot"
        case .readShot: "Read a Shot"
        case .checkTranslation: "Check a translation"
        case .models: "Fast and Accurate"
        case .save: "Save a Shot"
        case .live: "Live translation"
        case .settings: "Make it yours"
        }
    }
}

/// Which page Slater Help is on. Back and Next stop at the ends.
@MainActor
@Observable
final class HelpPager {
    private(set) var page = HelpPage.welcome

    var isFirst: Bool { page == HelpPage.allCases.first }
    var isLast: Bool { page == HelpPage.allCases.last }

    func back() {
        page = HelpPage(rawValue: page.rawValue - 1) ?? page
    }

    func next() {
        page = HelpPage(rawValue: page.rawValue + 1) ?? page
    }

    func go(to page: HelpPage) {
        self.page = page
    }
}

/// Slater Help: a window of pages that walk through what Slater does. A window of our own, like
/// Settings (ADR 0004). It opens on the first page each time.
@MainActor
final class HelpWindowController {
    private let window: HelpWindow
    private let pager = HelpPager()

    init(live: LiveTranslationController, onOpenSettings: @escaping () -> Void) {
        window = HelpWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Slater Help"
        window.isReleasedWhenClosed = false
        window.pager = pager
        window.contentViewController = NSHostingController(rootView: HelpView(
            pager: pager,
            live: live,
            onOpenSettings: { [weak window] in
                window?.close()
                onOpenSettings()
            },
            onDone: { [weak window] in window?.close() }
        ))
    }

    func show() {
        if !window.isVisible {
            pager.go(to: .welcome)
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

/// The arrow keys page, and Esc closes, whichever control has the focus.
private final class HelpWindow: NSWindow {
    var pager: HelpPager?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: pager?.back() // Left arrow
        case 124: pager?.next() // Right arrow
        case 53: close() // Esc
        default: super.keyDown(with: event)
        }
    }
}

struct HelpView: View {
    let pager: HelpPager
    let live: LiveTranslationController
    let onOpenSettings: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            illustration
                .frame(maxWidth: .infinity)
                .frame(height: 190)
                .background(Color.accentColor.opacity(0.12))
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(pager.page.title)
                        .font(.title.bold())
                    if pager.page == .live {
                        Text("Experimental")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.25), in: .capsule)
                    }
                }
                text
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            footer
        }
        .frame(width: 640, height: 540)
    }

    private var footer: some View {
        HStack {
            Button("Back") { pager.back() }
                .disabled(pager.isFirst)
            Spacer()
            HStack(spacing: 8) {
                ForEach(HelpPage.allCases) { page in
                    Button { pager.go(to: page) } label: {
                        Circle()
                            .fill(page == pager.page ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                            .frame(width: 8, height: 8)
                            // The whole of the gap around a dot is its button.
                            .padding(4)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Page \(page.rawValue + 1) of \(HelpPage.allCases.count): \(page.title)")
                }
            }
            Spacer()
            Button(pager.isLast ? "Done" : "Next") {
                if pager.isLast {
                    onDone()
                } else {
                    pager.next()
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: The words

    @ViewBuilder private var text: some View {
        switch pager.page {
        case .welcome:
            Paragraph("Slater translates the text in any part of your screen, right where it sits. Everything stays on this Mac.")
            Paragraph("It lives in the menu bar: look for the lizard. The next few pages walk through what it can do.")
        case .takeShot:
            Paragraph("Press the hotkey, then drag a box over the text you want to read. The translation appears in place, in a floating window called a Shot.")
            KeyRows([
                ([hotkey(.takeShot)], "Take a Shot: drag a box"),
                ([hotkey(.takeWindowShot)], "Take a Shot of the front window, with no box to draw"),
                (["Esc"], "Cancel while dragging"),
            ])
        case .readShot:
            Paragraph("A Shot stays open until you close it. Drag it anywhere; move the pointer over it for its controls. Open Shots are listed in the lizard's menu.")
            KeyRows([
                (["Space"], "Tap to switch to the original and back; hold to peek at it"),
                (["O", "F", "A"], "Show the original, or the Fast or Accurate translation"),
                (["Esc"], "Close the Shot"),
            ])
        case .checkTranslation:
            Paragraph("A dashed orange box marks text Slater may have misread. Point at it to see the whole translation, and check it against the original.")
            KeyRows([
                (["D"], "Open Shot Details: each original next to its translation, with buttons to copy the translation or both"),
            ])
            Footnote("Numbers, part codes and text already in your language are left exactly as they were.")
        case .models:
            Paragraph("Slater has two translation models. Fast is nearly instant. Accurate is a larger model that's slower but sometimes words things better.")
            KeyRows([
                (["A"], "Translate the Shot again with Accurate"),
                (["F"], "Go back to Fast"),
            ])
            Footnote("To use Accurate every time, choose it under Translation model in Settings.")
        case .save:
            Paragraph("Keep a Shot as a PDF, as a pair of images (original and translated), or as text in a Markdown file. Slater remembers the format you chose last.")
            KeyRows([
                (["⌘S"], "Save the Shot"),
            ])
            Footnote("Nothing from your screen is written to disk unless you save it.")
        case .live:
            Paragraph("The whole screen, or the front window, translated as it changes, with no box to draw.\(live.isEnabled ? "" : " Turn it on in Settings first.") The lizard breathes while it runs.")
            KeyRows([
                ([hotkey(.toggleLiveTranslation)], "Start or stop on the whole screen"),
                ([hotkey(.toggleLiveWindowTranslation)], "Start or stop on the front window"),
                ([hotkey(.freezeLiveTranslation)], "Freeze the screen so you can read it"),
            ])
        case .settings:
            Paragraph("In Settings you can change every hotkey, pick the languages to translate from and to, and choose the default model. Slater is built and tested for Japanese → English; other pairs work as macOS supports them.")
            Footnote("Something went wrong? Choose Report a Problem… in the lizard's menu. It saves a report you can post; nothing is sent on its own.")
            Button("Open Settings…", action: onOpenSettings)
        }
    }

    /// A rebindable hotkey as it is bound now.
    private func hotkey(_ name: KeyboardShortcuts.Name) -> String {
        name.shortcut?.description ?? "Not set"
    }

    // MARK: The pictures

    @ViewBuilder private var illustration: some View {
        switch pager.page {
        case .welcome:
            HStack(spacing: 20) {
                Text("本日の営業は終了しました")
                    .font(.title3)
                    .frame(width: 170, alignment: .leading)
                    .card()
                Image(systemName: "arrow.right")
                    .font(.title2.weight(.semibold))
                Text("We are closed for today")
                    .font(.title3)
                    .frame(width: 170, alignment: .leading)
                    .card()
            }
        case .takeShot:
            VStack(alignment: .leading, spacing: 10) {
                Text("お知らせ")
                Text("本日の営業は終了しました。")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12))
                    .overlay {
                        Rectangle().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }
                    .padding(.horizontal, -8)
                    .padding(.vertical, -5)
                Text("またのご来店をお待ちしております。")
            }
            .font(.title3)
            .frame(width: 340, alignment: .leading)
            .card()
        case .readShot:
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Spacer()
                    HStack(spacing: 0) {
                        Text("Original").padding(.horizontal, 8).padding(.vertical, 2)
                        Text("Fast").padding(.horizontal, 8).padding(.vertical, 2).background(.white.opacity(0.3))
                        Text("Accurate").padding(.horizontal, 8).padding(.vertical, 2)
                    }
                    .font(.caption)
                    .clipShape(.rect(cornerRadius: 5))
                    .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.5)) }
                    Image(systemName: "square.and.arrow.down.fill")
                    Image(systemName: "xmark.circle.fill")
                }
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.75))
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notice")
                    Text("We are closed for today.")
                    Text("We look forward to your next visit.")
                }
                .font(.title3)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .frame(width: 380, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        case .checkTranslation:
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Closing time: 18:00")
                        .font(.title3)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(nsColor: .textBackgroundColor))
                        .overlay {
                            // As a Shot marks a Low-confidence Block.
                            Rectangle().strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Low OCR confidence", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Closing time: 18:00")
                    }
                    .card(padding: 10)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Shot Details")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("お知らせ")
                        Text("Notice").foregroundStyle(.secondary)
                    }
                    .padding(10)
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("閉店時間：18:00")
                            .padding(2)
                            .background(Color.orange.opacity(0.25), in: .rect(cornerRadius: 3))
                        Text("Closing time: 18:00").foregroundStyle(.secondary)
                    }
                    .padding(10)
                }
                .frame(width: 230, alignment: .leading)
                .card(padding: 0)
            }
        case .models:
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fast").font(.title3.bold())
                    Text("About 20 ms per text").foregroundStyle(.secondary)
                    Text("The default").font(.callout.weight(.semibold))
                }
                .frame(width: 180, alignment: .leading)
                .card()
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2) }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Accurate").font(.title3.bold())
                    Text("About half a second per text").foregroundStyle(.secondary)
                    Text("Optional download").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                }
                .frame(width: 180, alignment: .leading)
                .card()
            }
        case .save:
            HStack(alignment: .top, spacing: 16) {
                ForEach(ShotExporter.Format.allCases) { format in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(format.title).font(.title3.bold())
                        Text(format.exampleFiles)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 150, height: 64, alignment: .topLeading)
                    .card(padding: 14)
                }
            }
        case .live:
            VStack(alignment: .leading, spacing: 10) {
                Text("Notice").patch()
                Text("We are closed for today.").patch()
                Text("Next page").patch()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(14)
            .frame(width: 300, height: 130, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
            .padding(6)
            .background(.black.opacity(0.8), in: .rect(cornerRadius: 10))
        case .settings:
            VStack(spacing: 0) {
                SettingRow("Translate from", "Japanese to English")
                Divider()
                SettingRow("Take Shot", hotkey(.takeShot))
                Divider()
                SettingRow("Translation model", "Fast")
                Divider()
                SettingRow("Open Slater when you log in", "On")
            }
            .frame(width: 380)
            .card(padding: 0)
        }
    }
}

private extension ShotExporter.Format {
    /// The files a Shot saved as "notice" would make, for the Save page.
    var exampleFiles: String {
        switch self {
        case .pdf: "notice.pdf"
        case .image: "notice-original.png\nnotice-translated.png"
        case .text: "notice.md"
        }
    }
}

private struct Paragraph: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.title3)
            .lineSpacing(3)
            // Wraps, rather than trailing off with an ellipsis.
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Footnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Keys on the left, what they do on the right.
private struct KeyRows: View {
    let rows: [(keys: [String], action: String)]

    init(_ rows: [(keys: [String], action: String)]) {
        self.rows = rows
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            ForEach(rows, id: \.action) { row in
                GridRow {
                    HStack(spacing: 4) {
                        ForEach(row.keys, id: \.self) { Keycap($0) }
                    }
                    Text(row.action)
                        .fixedSize(horizontal: false, vertical: true)
                        // The column takes the rest of the width, so a long line wraps at the edge.
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct Keycap: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.body.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(minWidth: 28)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 6))
            .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.tertiary) }
    }
}

private struct SettingRow: View {
    let name: String
    let value: String

    init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private extension View {
    /// A white card for a picture's sample text.
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary) }
    }

    /// A translation as live translation lays it over the screen.
    func patch() -> some View {
        self
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.15))
    }
}
