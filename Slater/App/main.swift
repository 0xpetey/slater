import AppKit

// AppKit's own lifecycle. SwiftUI's `App` was dropped (ADR 0004): the one scene it provided here
// was Settings, now a window of our own, and its setup cost about 50 ms of every launch.
// The log file and the crash handlers come first, so a crash during launch leaves a trace (ADR 0005).
ProblemReporter.start()
LaunchTiming.log("main reached")
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
