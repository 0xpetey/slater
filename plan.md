# Slater: drag a box on screen, translate the Japanese in it

## Context
A macOS utility that works like the ⇧⌘4 screenshot tool. You press a hotkey, drag a box over any part of the screen, and English appears on top of the Japanese text inside it, the way Google Translate's camera mode works. It's for work. The main content is web pages, PDFs, documents and spreadsheets, with occasional poor-quality photos or scans and, rarely, stylized fonts. Domain terms (**Line**, **Block**, **Shot**) are defined in `CONTEXT.md`.

Decisions made so far:
- **Translation engine:** Apple's on-device frameworks only, because the content is confidential (`docs/adr/0001-on-device-translation-only.md`).
- **Display:** each Shot is a floating window that opens directly over its source text and can be dragged anywhere to keep for reference. Several can be open at once.
- **Storage:** Shots exist only in memory. Nothing is written to disk unless you explicitly save a Shot (ADR 0001).
- **Blocks:** Lines merge only when they're stacked vertically. Table cells, form fields and columns stay separate.

Environment: macOS 26.6, Xcode 26.6, Swift 6.3. The app will **require macOS 26**. This lets us create a `TranslationSession` directly in code instead of going through SwiftUI's `.translationTask`.

## How it works (user flow)
0. **First run (onboarding):** grant Screen Recording, download the Japanese language pack if it's missing, and set launch at login (a checkbox, on by default).
1. Slater runs as a **menu bar app** with no Dock icon.
2. You press the global hotkey. The default is **⌥⇧4**, chosen to echo ⇧⌘4 (fall back to ⌃⇧⌘J if it clashes), and you can change it in Settings.
3. Slater **captures every display first**, then shows the frozen image full-screen with a dim layer and a crosshair cursor. Slater's own windows (open Shots and the selection UI) are **excluded from the Capture**, so a new Shot always sees the real content underneath. Existing Shots are never closed or replaced by a new one.
4. You drag a rectangle. It's limited to the screen where you started dragging. Esc cancels, and a very small drag counts as a cancel.
5. Slater crops the capture to your box, cleans it up for OCR, and reads the Japanese text with Vision OCR.
6. It groups the Lines into Blocks and translates all the **Japanese Blocks** in one batch. **Passthrough Blocks** (numbers, part codes, English) are left exactly as captured, with no patch drawn over them. If there are no Japanese Blocks, no Shot is created. A "No Japanese text found" notice appears briefly near the cursor instead.
7. A **Shot window** opens exactly over the box. Each Block is covered with a patch in its background color, with the English text sized to fit.
   - **Drag** the window anywhere to keep it for reference. Any number of Shots can be open, and they float above other windows.
   - **Space** (tap to toggle, hold to peek): hide the English and show the Shot's original Japanese image.
   - **Hover** over a truncated translation to see all of it.
   - **Low-confidence Blocks** have an amber dotted underline. Hovering shows "Low OCR confidence", and the details panel highlights that row's recognized Japanese so you can check it against the original.
   - **D**: open the Shot's **details panel**, a Japanese ↔ English list with a copy button on each row, plus **Copy English** and **Copy Japanese + English** for the whole Shot.
   - **⌘S** or the save button: open a save dialog with a format dropdown: **Image + Text** (the default), Image, or Text. The dropdown remembers your last choice. Image saves `<name>-original.png` and `<name>-translated.png`. Text saves `<name>.md`, with the Japanese and English for each Block. Everything is saved side by side using the name you chose.
   - **Esc** (on the focused Shot) or the hover ✕: close it. Clicking or scrolling elsewhere does *not* close it.
8. The **menu bar dropdown** has an "Open Shots" section listing every open Shot, with a thumbnail and the first bit of its translation. Clicking one brings it to the front. It also has **Close All Shots**.

## Architecture (Swift, SwiftUI plus AppKit)

| Component | Responsibility | Key APIs |
|---|---|---|
| `SlaterApp` | App entry point, `MenuBarExtra` (including the Open Shots section), Settings scene, `LSUIElement = YES` | SwiftUI `MenuBarExtra`, `SMAppService` (launch at login) |
| `HotkeyManager` | Registers the global shortcut | [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) package (includes a recorder UI for Settings) |
| `ScreenCapturer` | Captures each display at native resolution, excluding Slater's own windows | ScreenCaptureKit: `SCShareableContent`, `SCContentFilter(display:excludingApplications: [Slater], exceptingWindows: [])`, `SCScreenshotManager.captureImage(contentFilter:configuration:)` |
| `SelectionOverlayController` | One borderless `NSPanel` per screen at `.screenSaver` level; shows the frozen image and draws the rectangle as you drag | `NSPanel`, `NSView` mouse events, `NSCursor.crosshair` |
| `CoordinateMapper` | Converts between AppKit points (origin bottom-left, spans all screens), capture pixels (origin top-left, Retina scale) and Vision's normalized boxes (origin bottom-left) | Pure functions, unit-tested |
| `ImagePreprocessor` | Makes the second OCR copy: upscales to about 3 px per point and applies grayscale plus contrast. No straightening: Vision read 2–3° rotated scans correctly. | Core Image (`CILanczosScaleTransform`, `CIColorControls`) |
| `TextRecognizer` | One OCR pass over an image, returning Lines | Vision `RecognizeTextRequest`: `.accurate`, `recognitionLanguages = [ja-JP, en-US]`, language correction on (turning it off caused 未/末 misreads) |
| `TextReader` | Reads the crop twice in parallel, raw and preprocessed, and reconciles the readings: agreement means trusted; disagreement means the longer text wins and the Line is marked Low-confidence (ADR 0002). Also rejoins a Line that one reading split in two. | `async let`, union-find over overlapping Lines |
| `RuleDetector` | Finds horizontal rules (gridlines, table borders) in the gap between two Lines | 8-bit grayscale pixel scan of the crop |
| `BlockGrouper` | Merges Lines into Blocks. Lines merge only when they are stacked: the vertical gap is at most 0.8 line heights, they overlap horizontally, their heights are similar, both are Japanese or both are not, and no rule is drawn between them. Text side by side never merges. A Line ending in 。！？ closes its Block. Each Block is classified as Japanese (it contains any character in the Hiragana, Katakana or Han Unicode scripts) or Passthrough. | Pure logic, unit-tested with table, form and paragraph fixtures |
| `Translator` | ja → en on-device translation. The target language is a single constant (English); there's no setting in version 1. Warms up the model when the hotkey is pressed, translates repeated text once per Shot, and streams results into the Shot as each finishes. | `LanguageAvailability().status(from:to:)`, `TranslationSession(installedSource:target:)` with the default strategy (`.lowLatency` needs a model that isn't installed), streamed `translate(batch:)` with `clientIdentifier` to map results back to Blocks |
| `Shot` (model) | The frozen image, Blocks, translations and the original screen rect | `@Observable` class |
| `ShotStore` | The open Shots; feeds the menu bar list, Close All, and focus | `@Observable`, owned by `AppState` |
| `ShotWindowController` | A floating window for one Shot: opens at the original rect, can be dragged, Space toggle, Esc/✕ to close, D for details | `NSPanel` (`.nonactivatingPanel`, `.floating` level, `isMovableByWindowBackground`) hosting a SwiftUI view. The background color comes from the pixels around each Block's edge. The font size is found by binary search, down to a 10pt minimum; below that the text is truncated with "…" and the full translation appears on hover. A patch may extend rightward into empty background, stopping at the next text, gridline or window edge, but never covers other content. |
| `ShotExporter` | Writes a Shot to disk in the format you chose: the original PNG, the translated PNG rendered from the Shot view, and a Markdown file with Japanese ↔ English per Block | `NSSavePanel` with an accessory view for the format dropdown, `ImageRenderer`, `UserDefaults` for the last format used (the format only, never any content) |
| `DetailsPanel` | Japanese ↔ English list for a Shot, with copy buttons | SwiftUI, `NSPasteboard` |
| `PermissionsManager` | Screen Recording permission check and prompt; first-run onboarding | `CGPreflightScreenCaptureAccess`, `CGRequestScreenCaptureAccess`, a link to System Settings |

The pipeline is a single `async` function started by the hotkey:
`capture → select → crop → read (raw ∥ preprocessed, reconciled) → group → translate → open Shot`
The Shot window opens as soon as the box is chosen and shows a "translating…" spinner until the translations arrive.

## Project layout
```
slater/
  CONTEXT.md, docs/adr/
  Slater.xcodeproj
  Slater/
    App/        SlaterApp.swift, AppState.swift, Info.plist, Slater.entitlements
    Capture/    ScreenCapturer.swift, SelectionOverlayController.swift, SelectionView.swift
    OCR/        ImagePreprocessor.swift, TextRecognizer.swift, BlockGrouper.swift
    Translate/  Translator.swift
    Shots/      Shot.swift, ShotStore.swift, ShotWindowController.swift, ShotView.swift, DetailsPanel.swift, ShotExporter.swift
    UI/         MenuContent.swift, SettingsView.swift, OnboardingView.swift
    Util/       CoordinateMapper.swift, ColorSampler.swift, FitText.swift
  SlaterTests/  BlockGrouperTests, CoordinateMapperTests, fixture images (web, PDF, spreadsheet, poor scan)
```
**Distribution:** version 1 is only for you, but it's set up so it can be shared with coworkers later:
- Bundle ID `com.peterjournell.slater`. Settle this before milestone 1, because changing it later resets everyone's Screen Recording permission.
- Local builds are signed with the personal team's Apple Development certificate (team QCXUWE7EEH, manual signing). To share, switch `project.yml` to the paid team (RQB2E9KNQB) with a Developer ID certificate. Xcode must be signed in to that account first.
- Hardened Runtime is on from the start, so Developer ID signing and notarization can be added later without code changes.
- No App Sandbox. It's not needed outside the App Store.
- Sharing with coworkers will likely need IT approval for Screen Recording on company-managed Macs.

This Mac is not enrolled in device management (MDM). If your work Mac is a different machine, check it with `profiles status -type enrollment`.

## Risks and how to handle them
- **Language pack not installed:** the pack is downloaded during onboarding. If it's deleted later, the first Shot checks `LanguageAvailability`. If it reports `.supported` but the pack isn't installed, show a prompt that triggers the system download through SwiftUI `.translationTask` with `prepareTranslation()`.
- **Poor-quality scans:** the preprocessed reading handles moderate blur. Very heavy blur returns no text at all, so Slater shows the "No Japanese text found" notice.
- **Borderless tables where every cell is Japanese** and rows are spaced like body text can still merge rows into one Block, because nothing in the image separates them. Gridlines, a Passthrough cell or wider row spacing all keep rows apart.
- **Translation time:** macOS translates one text at a time, about 0.25–0.35 s each, and batching or parallel sessions don't help. Loading the model adds about 1.5 s to the first call, so it's warmed up while you drag. A 20-cell spreadsheet takes several seconds, so results are streamed and each Block fills in as it's ready.
- **OCR time:** two readings run in parallel. A paragraph takes about 0.2–0.3 s; a full dense page takes about 2 s.
- **Vertical Japanese text:** Vision on macOS 26 reads vertical columns natively. `BlockGrouper` merges a column into the one to its left, reads right to left, and keeps columns apart across a vertical rule. A narrow column's English is turned sideways when that fits larger text. Only tested on rendered text so far; real scans of vertical documents are untested.
- **Multiple monitors or mixed scaling:** the selection is limited to the screen where the drag starts. `CoordinateMapper` tests cover mixed scaling between screens.
- **Stale permission after a rebuild:** document `tccutil reset ScreenCapture <bundle-id>` in the README.

## Milestones
1. **Skeleton:** menu bar app, hotkey, Screen Recording permission flow.
2. **Capture and select:** frozen-screen selection. The crop is shown in a temporary preview window placed exactly where it came from, so you can check it lines up with the screen underneath. It's kept in memory only, per ADR 0001, and replaced by Shot windows in milestone 5.
3. **OCR:** two readings (raw and preprocessed) reconciled by `TextReader`, then `RuleDetector` and `BlockGrouper`. The temporary preview outlines Blocks: blue for Japanese, orange for Low-confidence, grey for Passthrough. Block text goes to stdout in Debug builds only, never the system log.
4. **Translate:** Translator with the language-pack check and download in onboarding; the `Shot` model; the details panel (D on the preview) shows Japanese ↔ English as translations stream in, with Copy English and Copy Japanese + English.
5. **Shot windows:** in-place window, background sampling, patches extending into empty space, fitted and truncated text, hover popover (full text and Low-confidence note), orange dotted underline for Low-confidence Blocks, Space toggle and peek, drag, Esc/✕, D for details. Short labels lose a leading article (備考 → "Note", not "a note").
6. **Shot management and polish:** ShotStore, Open Shots menu section (thumbnail and the start of the translation), Close All, save to disk with ⌘S or the hover save button (`ShotExporter`; existing files are never replaced, a number is added instead), Settings (hotkey, launch at login), onboarding (permission, language pack, launch at login on by default), the "No Japanese text found" notice, and reading order that treats slightly misaligned table cells as one row.
7. **Later (optional):**
   - **Vertical text: done.** Columns group and read right to left, and a narrow column's English can be turned sideways.
   - **Cloud translation mode: not started.** It's blocked until management approves a specific service (ADR 0001).

## Verification
- **Unit tests** (`xcodebuild test`):
  - `CoordinateMapper` round-trips with 1× and 2× scaling and offset screens.
  - `BlockGrouper`, `TextReader.reconcile` and Block kind on synthetic Lines.
  - End-to-end OCR plus grouping on fixture PNGs generated by `scripts/make-fixtures.swift`: paragraph, airy paragraph, spreadsheet, bordered all-Japanese list, small 1× text and a poor scan.
- **Manual end-to-end checks:**
  - A Japanese web page in Safari, a PDF in Preview, a Numbers or Excel sheet, and a poor-quality scan.
  - Take a Shot over an area an existing Shot covers: the new Shot translates the document underneath, and the old Shot stays open.
  - Five Shots open at once: drag, toggle and close each, and check the menu bar list stays in sync.
  - On a second monitor, if you have one.
  - With Screen Recording permission denied, and with the Japanese language pack removed.
- **Timing check:** measure the time from releasing the drag to the translated text appearing; the target is under 1 second for a paragraph-sized box.
