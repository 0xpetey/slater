import Foundation

/// One text file with everything a GitHub issue needs: how to post it, the app and the Mac,
/// Slater's log and macOS's crash report. It stays on this Mac until the user attaches it to an
/// issue themselves (ADR 0005).
enum ProblemReport {
    static let newIssueURL = URL(string: "https://github.com/0xpetey/slater/issues/new")!

    /// Where macOS keeps crash reports; it moves them to Retired once they've been submitted.
    static var systemReportDirectories: [URL] {
        let reports = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports")
        return [reports, reports.appending(path: "Retired")]
    }

    /// Writes a report and returns it. `crashedSessionStarted` is when the session that didn't
    /// quit cleanly began, or nil for a report the user asked for.
    static func write(
        log: DiagnosticLog = .shared,
        crashedSessionStarted: Date?,
        systemReportDirectories: [URL] = systemReportDirectories,
        now: Date = .now
    ) throws -> URL {
        let files = FileManager.default
        try files.createDirectory(at: log.reportsDirectory, withIntermediateDirectories: true)
        let stamp = now.formatted(.verbatim(
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits)-\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
            timeZone: .current, calendar: .init(identifier: .gregorian)
        ))
        let kind = crashedSessionStarted == nil ? "report" : "crash"
        let file = log.reportsDirectory.appending(path: "Slater-\(kind)-\(stamp).txt")

        // A crash report from before the crashed session is some other crash; a report asked
        // for by hand takes one from the last week.
        let since = crashedSessionStarted ?? now.addingTimeInterval(-7 * 24 * 3600)
        let systemReport = latestSystemReport(in: systemReportDirectories, since: since)

        var text = """
            SLATER \(crashedSessionStarted == nil ? "PROBLEM" : "CRASH") REPORT
            Written \(now.ISO8601Format(.iso8601(timeZone: .current)))
            \(SystemSummary.oneLine)

            HOW TO POST THIS AS A GITHUB ISSUE
            1. Open \(newIssueURL.absoluteString)
            2. Title: what happened, such as "Crash when closing a Shot".
            3. In the description, say what you were doing just before, and whether it happens again.
            4. Drag this file into the description to attach it, then press "Submit new issue".

            What this file holds: Slater's own log (timings, counts and error messages) and macOS's
            crash report for Slater. Neither contains text read off your screen or translations.
            The crash report names the apps and libraries loaded in Slater. Read it before posting.


            """
        text += "======== SLATER'S LOG (most recent \(maximumLogLines) lines) ========\n"
        text += recentLog(log) + "\n\n"
        text += "======== MACOS CRASH REPORT ========\n"
        if let systemReport, let contents = try? String(contentsOf: systemReport, encoding: .utf8) {
            text += "\(systemReport.lastPathComponent)\n\(contents)\n"
        } else {
            text += """
                None found since \(since.ISO8601Format(.iso8601(timeZone: .current))). macOS can take a minute to write one, and \
                writes none after a force quit. Look for Slater-*.ips in ~/Library/Logs/DiagnosticReports \
                (and its Retired folder) and attach it too.\n
                """
        }
        try text.write(to: file, atomically: true, encoding: .utf8)
        prune(log.reportsDirectory)
        return file
    }

    static let maximumLogLines = 600

    private static func recentLog(_ log: DiagnosticLog) -> String {
        let lines = [log.previousLogFile, log.logFile]
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { $0.split(separator: "\n", omittingEmptySubsequences: false) }
        return lines.suffix(maximumLogLines).joined(separator: "\n")
    }

    static func latestSystemReport(in directories: [URL], since: Date) -> URL? {
        var latest: (url: URL, written: Date)?
        for directory in directories {
            let reports = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for url in reports where url.lastPathComponent.hasPrefix("Slater-") && url.pathExtension == "ips" {
                guard let written = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                      written >= since, written > latest?.written ?? .distantPast else { continue }
                latest = (url, written)
            }
        }
        return latest?.url
    }

    /// Keeps the ten newest reports; their names sort by date.
    private static func prune(_ directory: URL) {
        let reports = ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "txt" }
            // "2026-10-03-114500.txt", whichever kind of report it is.
            .sorted { $0.lastPathComponent.suffix(21) > $1.lastPathComponent.suffix(21) }
        for old in reports.dropFirst(10) {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
