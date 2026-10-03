# Slater

"It's slop, but it is MY slop"

A macOS menu bar app: press a hotkey, drag a box over text on screen, and get an in-place translation. Built and tested for Japanese → English, which is the default; any other pair macOS can translate on-device and read with Vision can be chosen in Settings, as-is. Everything runs on-device. See `plan.md` for the design, `CONTEXT.md` for the glossary and `docs/adr/` for decisions.

## Build and run

Requires macOS 26 and Xcode 26. The Xcode project is generated from `project.yml` by XcodeGen, which is pinned in `mise.toml`.

Signing needs your Apple developer team ID, which isn't committed. Put it in a `mise.local.toml` next to `mise.toml` (git-ignored):

```toml
[env]
DEVELOPMENT_TEAM = "XXXXXXXXXX"
```

Then:

```sh
mise install                 # installs xcodegen
mise exec -- xcodegen generate
xcodebuild -project Slater.xcodeproj -scheme Slater -configuration Release -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/Slater.app
```

Use the Release configuration for day-to-day use: Debug builds skip Swift's optimizer, which makes the pixel sampling and text grouping several times slower. Or open `Slater.xcodeproj` in Xcode after generating it.

Tests (run them in Debug, the default; `xcodebuild test` in Release embeds the test frameworks into the app it builds):

```sh
xcodebuild -project Slater.xcodeproj -scheme Slater -derivedDataPath build/DerivedData test
```

## Screen Recording permission

Slater needs Screen Recording permission to read the screen. macOS ties this permission to the app's code signature. If it stops working after a rebuild or a signing change, reset it and grant it again:

```sh
tccutil reset ScreenCapture app.slater
```

## Logs and crash reports

Slater keeps a log at `~/Library/Logs/Slater/Slater.log`: timings, counts and error messages, never text from your screen. After a crash, the next launch saves a report in `~/Library/Logs/Slater/Reports/` and offers to open a GitHub issue; **Report a Problem…** in the menu saves one at any time. The report is a text file that starts with the steps for posting it: open a [new issue](https://github.com/0xpetey/slater/issues/new), describe what you were doing, and drag the file into the description. Nothing is sent on its own (ADR 0005).

## License

MIT. See `LICENSE`.
