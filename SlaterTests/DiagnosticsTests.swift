import AppKit
import Foundation
import Testing
@testable import Slater

/// The log file, the unclean-exit check and the report, each in a temporary folder of its own.
struct DiagnosticsTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "SlaterDiagnosticsTests-\(UUID().uuidString)")
    }

    @Test func linesReachTheFileAtOnce() throws {
        let log = DiagnosticLog(directory: temporaryDirectory())
        log.append(level: "notice", category: "shots", "Captured 2 displays 81 ms after the hotkey")
        let text = try String(contentsOf: log.logFile, encoding: .utf8)
        #expect(text.hasSuffix("[shots] notice: Captured 2 displays 81 ms after the hotkey\n"))
    }

    @Test func aSessionThatNeverEndedIsNoticedAtTheNextLaunch() throws {
        let directory = temporaryDirectory()
        #expect(DiagnosticLog(directory: directory).beginSession() == nil, "nothing ran before")
        // No endSession: the process died. Its marker names a process that is gone.
        let marker = DiagnosticLog(directory: directory).sessionMarker
        try "999999".write(to: marker, atomically: true, encoding: .utf8)
        #expect(DiagnosticLog(directory: directory).beginSession() != nil)
        // A marker held by a process that is still running is a second copy, not a crash.
        try "\(getppid())".write(to: marker, atomically: true, encoding: .utf8)
        #expect(DiagnosticLog(directory: directory).beginSession() == nil)
        let clean = DiagnosticLog(directory: directory)
        clean.endSession()
        #expect(DiagnosticLog(directory: directory).beginSession() == nil, "the last session ended cleanly")
    }

    @Test func aLogPastItsLimitIsRotated() throws {
        let directory = temporaryDirectory()
        let first = DiagnosticLog(directory: directory, maximumBytes: 100)
        first.append(level: "notice", category: "test", String(repeating: "x", count: 200))
        let second = DiagnosticLog(directory: directory, maximumBytes: 100)
        second.append(level: "notice", category: "test", "after rotation")
        #expect(try String(contentsOf: second.previousLogFile, encoding: .utf8).contains("xxxx"))
        #expect(try String(contentsOf: second.logFile, encoding: .utf8).contains("xxxx") == false)
    }

    @Test func aCrashReportHoldsTheStepsTheLogAndTheSystemReport() throws {
        let directory = temporaryDirectory()
        let log = DiagnosticLog(directory: directory)
        log.append(level: "error", category: "live", "Live translation failed to start")
        let systemReports = directory.appending(path: "DiagnosticReports")
        try FileManager.default.createDirectory(at: systemReports, withIntermediateDirectories: true)
        try "{\"bug_type\":\"309\"}".write(to: systemReports.appending(path: "Slater-2026-10-03-092345.ips"), atomically: true, encoding: .utf8)
        try "other".write(to: systemReports.appending(path: "Finder-2026-10-03-092345.ips"), atomically: true, encoding: .utf8)

        let report = try ProblemReport.write(log: log, crashedSessionStarted: .now.addingTimeInterval(-60), systemReportDirectories: [systemReports])
        let text = try String(contentsOf: report, encoding: .utf8)
        #expect(report.lastPathComponent.hasPrefix("Slater-crash-"))
        #expect(text.contains("HOW TO POST THIS AS A GITHUB ISSUE"))
        #expect(text.contains("https://github.com/0xpetey/slater/issues/new"))
        #expect(text.contains("Live translation failed to start"))
        #expect(text.contains("Slater-2026-10-03-092345.ips\n{\"bug_type\":\"309\"}"))
        #expect(!text.contains("other"))
    }

    /// A crash report older than the crashed session belongs to some earlier crash.
    @Test func anOlderSystemReportIsLeftOut() throws {
        let directory = temporaryDirectory()
        let log = DiagnosticLog(directory: directory)
        let systemReports = directory.appending(path: "DiagnosticReports")
        try FileManager.default.createDirectory(at: systemReports, withIntermediateDirectories: true)
        try "old".write(to: systemReports.appending(path: "Slater-2026-09-28-201215.ips"), atomically: true, encoding: .utf8)
        let report = try ProblemReport.write(log: log, crashedSessionStarted: .now.addingTimeInterval(60), systemReportDirectories: [systemReports])
        #expect(try String(contentsOf: report, encoding: .utf8).contains("None found since"))
    }

    @Test @MainActor func theMenuOffersToReportAProblem() {
        let menu = NSMenu()
        StatusItemController(appState: AppState()).menuNeedsUpdate(menu)
        #expect(menu.item(withTitle: "Report a Problem…") != nil)
    }
}
