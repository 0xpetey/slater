# Slater: drag a box on screen, translate the Japanese in it

## Context
A macOS utility that works like the ⇧⌘4 screenshot tool. You press a hotkey, drag a box over any part of the screen, and English appears on top of the Japanese text inside it, the way Google Translate's camera mode works. It's for work. The main content is web pages, PDFs, documents and spreadsheets, with occasional poor-quality photos or scans and, rarely, stylized fonts. Domain terms (**Line**, **Block**, **Shot**) are defined in `CONTEXT.md`.

Decisions made so far:
- **Translation engine:** Apple's on-device frameworks only, because the content is confidential (`docs/adr/0001-on-device-translation-only.md`).
- **Display:** each Shot is a floating window that opens directly over its source text and can be dragged anywhere to keep for reference. Several can be open at once.
- **Storage:** Shots exist only in memory. Nothing is written to disk unless you explicitly save a Shot (ADR 0001).
- **Translation model:** the Fast on-device model by default; Accurate is optional and any Shot can be rerun with it (ADR 0003).
- **Blocks:** Lines merge only when they're stacked vertically. Table cells, form fields and columns stay separate.

Environment: macOS 26.6, Xcode 26.6, Swift 6.3. The app **requires macOS 26.4**: 26 lets us create a `TranslationSession` directly in code instead of going through SwiftUI's `.translationTask`, and 26.4 adds the choice of translation model (`TranslationSession.Strategy`).

## How it works (user flow)
0. **First run (onboarding):** grant Screen Recording, download the Fast translation model if it's missing, optionally also download the Accurate model, and set launch at login (a checkbox, on by default).
1. Slater runs as a **menu bar app** with no Dock icon.
2. You press the global hotkey. The default is **⌥⇧4**, chosen to echo ⇧⌘4 (fall back to ⌃⇧⌘J if it clashes), and you can change it in Settings.
3. The dimmed selection layer and crosshair appear **immediately** over the live screen, and Slater captures every display underneath; the capture replaces the live screen about 80 ms later, which is invisible unless something was moving. Slater's own windows (open Shots and the selection UI) are **excluded from the Capture**, so a new Shot always sees the real content underneath. Existing Shots are never closed or replaced by a new one.
4. You drag a rectangle. It's limited to the screen where you started dragging. Esc cancels, and a very small drag counts as a cancel.
5. Slater crops the capture to your box and reads it twice with Vision: a quick reading that opens the Shot, and a corrected reading that verifies it a moment later (ADR 0002).
6. It groups the Lines into Blocks and translates all the **Japanese Blocks** in one batch. **Passthrough Blocks** (numbers, part codes, English) are left exactly as captured, with no patch drawn over them. If there are no Japanese Blocks, no Shot is created. A "No Japanese text found" notice appears briefly near the cursor instead.
7. A **Shot window** opens exactly over the box. Each Block is covered with a patch in its background color, with the English text sized to fit.
   - **Drag** the window anywhere to keep it for reference. Any number of Shots can be open, and they float above other windows.
   - **Space** (tap to toggle, hold to peek): hide the English and show the Shot's original Japanese image.
   - **Hover** over a truncated translation to see all of it.
   - **Low-confidence Blocks** have an amber dotted underline. Hovering shows "Low OCR confidence", and the details panel highlights that row's recognized Japanese so you can check it against the original.
   - **A**, or the **Accurate** hover button: translate the Shot again with the Accurate model. The Fast translations stay until each Accurate one replaces it. If Accurate isn't downloaded yet, macOS asks to download it first.
   - **D**: open the Shot's **details panel**, a Japanese ↔ English list with a copy button on each row, plus **Copy English** and **Copy Japanese + English** for the whole Shot. It names the model used and has a **Rerun with Accurate** button.
   - **⌘S** or the save button: open a save dialog with a format dropdown: **Image + Text** (the default), Image, or Text. The dropdown remembers your last choice. Image saves `<name>-original.png` and `<name>-translated.png`. Text saves `<name>.md`, with the Japanese and English for each Block. Everything is saved side by side using the name you chose.
   - **Esc** (on the focused Shot) or the hover ✕: close it. Clicking or scrolling elsewhere does *not* close it.
8. The **menu bar dropdown** has an "Open Shots" section listing every open Shot, with a thumbnail and the first bit of its translation. Clicking one brings it to the front. It also has **Close All Shots**.

## Architecture (Swift, SwiftUI plus AppKit)

| Component | Responsibility | Key APIs |
|---|---|---|
| `SlaterApp` | App entry point, `MenuBarExtra` (including the Open Shots section), Settings scene, `LSUIElement = YES` | SwiftUI `MenuBarExtra`, `SMAppService` (launch at login) |
| `HotkeyManager` | Registers the global shortcut | [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) package (includes a recorder UI for Settings) |
| `ScreenCapturer` | Captures each display at native resolution, excluding Slater's own windows. Keeps the display list fetched ahead of time and makes a throwaway capture at launch, because the first capture in a process costs about 70 ms more. | ScreenCaptureKit: `SCShareableContent`, `SCContentFilter(display:excludingApplications: [Slater], exceptingWindows: [])`, `SCScreenshotManager.captureImage(contentFilter:configuration:)` |
| `SelectionOverlayController` | One borderless, transparent `NSPanel` per screen at `.screenSaver` level, shown the instant the hotkey is pressed; frozen with the Captures when they land; draws the rectangle as you drag. A box finished before the capture lands is kept and used once it does. | `NSPanel`, `NSView` mouse events, `NSCursor.crosshair` |
| `CoordinateMapper` | Converts between AppKit points (origin bottom-left, spans all screens), capture pixels (origin top-left, Retina scale) and Vision's normalized boxes (origin bottom-left) | Pure functions, unit-tested |
| `ImagePreprocessor` | Makes the second OCR copy: upscales to about 3 px per point and applies grayscale plus contrast. No straightening: Vision read 2–3° rotated scans correctly. | Core Image (`CILanczosScaleTransform`, `CIColorControls`) |
| `TextRecognizer` | One OCR pass over an image, returning Lines | Vision `RecognizeTextRequest`: `.accurate`, `recognitionLanguages = [ja-JP, en-US]`, language correction on (turning it off caused 未/末 misreads) |
| `TextReader` | Two readings, started together: the *quick* reading (raw image, no language correction, about 2.4× faster) opens the Shot; the *corrected* reading (preprocessed, language correction on) verifies it once it lands. Agreement means trusted; disagreement means the longer text wins, ties go to the corrected reading, and the Line is marked Low-confidence (ADR 0002). Also rejoins a Line that one reading split in two. | `async let`, union-find over overlapping Lines |
| `RuleDetector` | Finds horizontal rules (gridlines, table borders) in the gap between two Lines | 8-bit grayscale pixel scan of the crop |
| `BlockGrouper` | Merges Lines into Blocks. Lines merge only when they are stacked: the vertical gap is at most 0.8 line heights, they overlap horizontally, their heights are similar, both are Japanese or both are not, and no rule is drawn between them. Text side by side never merges. A Line ending in 。！？ closes its Block. Each Block is classified as Japanese (it contains any character in the Hiragana, Katakana or Han Unicode scripts) or Passthrough. | Pure logic, unit-tested with table, form and paragraph fixtures |
| `Translator` | ja → en on-device translation. The target language is a single constant (English); there's no setting in version 1. Warms up the model at launch, on wake and when the hotkey is pressed; translates each distinct text once per Shot, in reading order, streaming results into the Shot as each finishes; can be called again after the corrected reading changes some Blocks and sends only the new texts. Two on-device models: **Fast** (`.lowLatency`, the default, ADR 0003) and **Accurate** (macOS's default, `.highFidelity`, optional). `translate(_:using:replacingExisting:)` reruns a Shot with a different model, keeping the old translations visible until each new one lands. | `LanguageAvailability(preferredStrategy:)`, `TranslationSession(installedSource:target:preferredStrategy:)`, streamed `translate(batch:)` with `clientIdentifier` to map results back |
| `Shot` (model) | The frozen image, Blocks, patches, translations and the original screen rect. Each distinct Japanese text has its own observable translation slot, so a translation arriving re-renders only its own patch. Blocks can be replaced by the corrected reading, keeping translations for unchanged text. | `@Observable` class with nested `@Observable` slots |
| `ShotStore` | The open Shots; feeds the menu bar list, Close All, and focus | `@Observable`, owned by `AppState` |
| `ShotWindowController` | A floating window for one Shot: opens at the original rect, can be dragged, Space toggle, Esc/✕ to close, D for details | `NSPanel` (`.nonactivatingPanel`, `.floating` level, `isMovableByWindowBackground`) hosting a SwiftUI view. The background color comes from the pixels around each Block's edge. The font size is found by binary search, down to a 10pt minimum; below that the text is truncated with "…" and the full translation appears on hover. A patch may extend rightward into empty background, stopping at the next text, gridline or window edge, but never covers other content. |
| `ShotExporter` | Writes a Shot to disk in the format you chose: the original PNG, the translated PNG rendered from the Shot view, and a Markdown file with Japanese ↔ English per Block | `NSSavePanel` with an accessory view for the format dropdown, `ImageRenderer`, `UserDefaults` for the last format used (the format only, never any content) |
| `DetailsPanel` | Japanese ↔ English list for a Shot, with copy buttons | SwiftUI, `NSPasteboard` |
| `PermissionsManager` | Screen Recording permission check and prompt; first-run onboarding | `CGPreflightScreenCaptureAccess`, `CGRequestScreenCaptureAccess`, a link to System Settings |

The pipeline is a single `async` function started by the hotkey:
`capture → select → crop → quick read → group → open Shot → translate`, with the corrected reading running alongside from the crop onward and then `reconcile → regroup → update Shot → translate what changed`
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
- **Translation time:** with the Accurate model macOS translates one text at a time, about 0.38 s each (18 texts: 6.9 s), and batching, joining texts or parallel sessions don't help; loading it costs 1.8 s cold. The **Fast model is about 19× faster: ~20 ms per text (18 texts: 0.34–0.4 s), 62 ms cold**, with comparable wording on business text (sometimes better, occasionally more awkward). Both are warmed up at launch, on wake and while you drag, and results stream in reading order either way.
- **OCR time:** Vision's language correction costs about 2.4× (a 20-line crop: 0.5 s without, 1.2 s with). The Shot opens after the quick, uncorrected reading; the corrected reading verifies it about 0.7 s later on such a crop. Vision's `.fast` recognition level returns nothing for Japanese, so it can't be used.
- **OCR accuracy, open issue:** across five Japanese fonts at 13pt and 11pt (180 rendered lines), the quick and corrected readings were equally accurate overall (167 and 167 right) but failed on different lines: 5 only the quick reading got right, 5 only the corrected one, 8 neither. In every disagreement inspected, the wrong reading had dropped a character, so the reconciliation rule (longer text wins, ties to the corrected reading) chose the right text; that's why the corrected reading changes about one Block per Shot on real screens, briefly visible as a swapped translation with an orange underline. The remaining errors are one character, 当 (担当者, 当社, 該当), dropped by *both* readings in Hiragino Sans (macOS's default Japanese font) and Tsukushi Gothic, which the disagreement signal can't catch. Vision's results also vary slightly between runs on the same image. Needs its own investigation (fonts, sizes, Vision revisions).
- **Vertical Japanese text:** Vision on macOS 26 reads vertical columns natively. `BlockGrouper` merges a column into the one to its left, reads right to left, and keeps columns apart across a vertical rule. A narrow column's English is turned sideways when that fits larger text. Only tested on rendered text so far; real scans of vertical documents are untested.
- **Multiple monitors or mixed scaling:** the selection is limited to the screen where the drag starts. `CoordinateMapper` tests cover mixed scaling between screens.
- **Stale permission after a rebuild:** document `tccutil reset ScreenCapture <bundle-id>` in the README.

## Milestones
1. **Skeleton:** menu bar app, hotkey, Screen Recording permission flow.
2. **Capture and select:** frozen-screen selection. The crop is shown in a temporary preview window placed exactly where it came from, so you can check it lines up with the screen underneath. It's kept in memory only, per ADR 0001, and replaced by Shot windows in milestone 5.
3. **OCR:** two readings (raw and preprocessed) reconciled by `TextReader`, then `RuleDetector` and `BlockGrouper`. The temporary preview outlines Blocks: blue for Japanese, orange for Low-confidence, grey for Passthrough. Block text goes to stdout in Debug builds only, never the system log.
4. **Translate:** Translator with the language-pack check and download in onboarding; the `Shot` model; the details panel (D on the preview) shows Japanese ↔ English as translations stream in, with Copy English and Copy Japanese + English.
5. **Shot windows:** in-place window, background sampling, patches extending into empty space, fitted and truncated text, hover popover (full text and Low-confidence note), orange dotted underline for Low-confidence Blocks, Space toggle and peek, drag, Esc/✕, D for details. Short labels lose a leading article (備考 → "Note", not "a note").
6. **Shot management and polish:** ShotStore, Open Shots menu section (thumbnail and the start of the translation), Close All, save to disk with ⌘S or the hover save button (`ShotExporter`; existing files are never replaced, a number is added instead), Settings (hotkey, launch at login, translation model), onboarding (permission, Fast model required, Accurate optional, launch at login on by default), the "No Japanese text found" notice, per-Shot rerun with Accurate, and reading order that treats slightly misaligned table cells as one row.
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
- **Timing check:** the log (`log show --predicate 'subsystem == "com.peterjournell.slater"'`) records, per Shot: capture time after the hotkey, selection overlay time, quick reading and Shot-open time after selection, when the corrected reading was applied and how many Blocks it changed, and translation first-result and total times with the model used. Counts and milliseconds only, never text. Target: Shot open under 0.5 s for a paragraph-sized box, first translation within 1 s.
