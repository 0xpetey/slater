# Slater

A macOS menu bar app: press a hotkey, drag a box over any Japanese text on screen, and get an in-place English translation. Everything runs on-device. See `plan.md` for the design, `CONTEXT.md` for the glossary and `docs/adr/` for decisions.

## Build and run

Requires macOS 26 and Xcode 26. The Xcode project is generated from `project.yml` by XcodeGen, which is pinned in `mise.toml`.

```sh
mise install                 # installs xcodegen
mise exec -- xcodegen generate
xcodebuild -project Slater.xcodeproj -scheme Slater -configuration Release -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/Slater.app
```

Use the Release configuration for day-to-day use: Debug builds skip Swift's optimizer, which makes the pixel sampling and text grouping several times slower. Or open `Slater.xcodeproj` in Xcode after generating it.

Tests:

```sh
xcodebuild -project Slater.xcodeproj -scheme Slater -derivedDataPath build/DerivedData test
```

## Screen Recording permission

Slater needs Screen Recording permission to read the screen. macOS ties this permission to the app's code signature. If it stops working after a rebuild or a signing change, reset it and grant it again:

```sh
tccutil reset ScreenCapture com.peterjournell.slater
```
