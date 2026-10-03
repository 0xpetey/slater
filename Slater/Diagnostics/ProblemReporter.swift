import AppKit

private let logger = Log(category: "session")

/// Starts the log and the crash handlers, and offers a report: after a session that didn't quit
/// cleanly, or when the user chooses Report a Problem… from the menu.
@MainActor
enum ProblemReporter {
    /// When the previous session started, if it never ended cleanly.
    private(set) static var crashedSessionStarted: Date?

    /// Called first thing in `main`, so that a crash during launch is caught too.
    static func start() {
        guard !DiagnosticLog.isUnderTest else { return }
        crashedSessionStarted = DiagnosticLog.shared.beginSession()
        CrashHandlers.install(log: .shared)
    }

    #if DEBUG
    /// Debug builds only: `SLATER_CRASH_TEST=1` in the environment crashes Slater two seconds
    /// after launch, to check that a crash leaves its trace in the log and a report at the next
    /// launch, then open Slater again.
    static func crashForTestingIfAsked() {
        guard ProcessInfo.processInfo.environment["SLATER_CRASH_TEST"] != nil else { return }
        logger.error("Crashing on purpose: SLATER_CRASH_TEST is set")
        Task {
            try? await Task.sleep(for: .seconds(2))
            let nothing: [Int] = []
            _ = nothing[1]
        }
    }
    #endif

    static func sessionEnded() {
        guard !DiagnosticLog.isUnderTest else { return }
        DiagnosticLog.shared.endSession()
    }

    /// After a crash: writes the report and says where it is.
    static func offerCrashReportIfNeeded() {
        guard let started = crashedSessionStarted else { return }
        crashedSessionStarted = nil
        present(crashedSessionStarted: started)
    }

    static func present(crashedSessionStarted: Date? = nil) {
        let report: URL
        do {
            report = try ProblemReport.write(crashedSessionStarted: crashedSessionStarted)
        } catch {
            logger.error("Couldn't write a report: \(error.localizedDescription)")
            return
        }
        logger.notice("Report written: \(report.lastPathComponent)")

        let alert = NSAlert()
        alert.messageText = crashedSessionStarted == nil ? "A report has been saved" : "Slater quit unexpectedly last time"
        alert.informativeText = """
            A report was saved to \(report.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).

            To send it, open a new issue on GitHub, describe what you were doing, and drag the file \
            into the description. The same steps are at the top of the file.

            It holds Slater's log (timings and counts) and macOS's crash report, never text from your \
            screen. Nothing is sent unless you post it.
            """
        alert.addButton(withTitle: "Open GitHub Issue")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([report])
            NSWorkspace.shared.open(ProblemReport.newIssueURL)
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([report])
        default:
            break
        }
    }
}
