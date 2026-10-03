import Foundation
import os

/// Slater's own log file, `~/Library/Logs/Slater/Slater.log`, kept so that a crash leaves
/// something to read (ADR 0005). Every line is written straight to the file, unbuffered, so the
/// lines before a crash are on disk when it happens. Timings and counts only, never recognized
/// text or translations (ADR 0001).
final class DiagnosticLog: Sendable {
    static let shared = DiagnosticLog(directory: defaultDirectory)

    /// Unit tests use the app as their host: their log goes to a temporary folder, so a test run
    /// neither writes to the user's log nor looks like a crash at the next launch.
    static var isUnderTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static var defaultDirectory: URL {
        isUnderTest
            ? FileManager.default.temporaryDirectory.appending(path: "SlaterTests-\(getpid())/Logs")
            : FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Slater")
    }

    let directory: URL
    /// Open for appending for the life of the process; the crash handlers write to it too.
    let fileDescriptor: Int32

    var logFile: URL { directory.appending(path: "Slater.log") }
    /// The log before the last rotation, so a report still has history just after one.
    var previousLogFile: URL { directory.appending(path: "Slater.previous.log") }
    /// Exists while Slater runs, and holds its process ID. One left behind by a process that is
    /// gone means the last session didn't quit cleanly.
    var sessionMarker: URL { directory.appending(path: "session-running") }
    var reportsDirectory: URL { directory.appending(path: "Reports") }

    /// Rotates the log once it has passed `maximumBytes`, so two files of at most about that
    /// size are ever kept.
    init(directory: URL, maximumBytes: Int = 1_000_000) {
        self.directory = directory
        let files = FileManager.default
        try? files.createDirectory(at: directory, withIntermediateDirectories: true)
        let log = directory.appending(path: "Slater.log")
        let previous = directory.appending(path: "Slater.previous.log")
        if let size = try? log.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumBytes {
            try? files.removeItem(at: previous)
            try? files.moveItem(at: log, to: previous)
        }
        fileDescriptor = open(log.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
    }

    deinit {
        if fileDescriptor >= 0 { close(fileDescriptor) }
    }

    func append(level: String, category: String, _ message: String) {
        guard fileDescriptor >= 0 else { return }
        let time = Date.now.ISO8601Format(.iso8601(timeZone: .current, includingFractionalSeconds: true))
        var line = "\(time) [\(category)] \(level): \(message)\n"
        line.withUTF8 { _ = write(fileDescriptor, $0.baseAddress, $0.count) }
    }

    /// Starts a session. Returns when the previous session started if it never ended cleanly:
    /// a crash, a force quit or a power loss.
    @discardableResult
    func beginSession() -> Date? {
        let files = FileManager.default
        var unfinished = (try? files.attributesOfItem(atPath: sessionMarker.path))?[.modificationDate] as? Date
        // A second copy of Slater running, such as a Debug build beside the Release one, isn't a crash.
        // EPERM: the process exists but isn't ours to signal.
        if let owner = markerOwner, owner != getpid(), kill(owner, 0) == 0 || errno == EPERM {
            unfinished = nil
        }
        try? Data("\(getpid())".utf8).write(to: sessionMarker)
        if unfinished != nil {
            append(level: "error", category: "session", "The previous session didn't quit cleanly")
        }
        append(level: "notice", category: "session", "Session started: \(SystemSummary.oneLine)")
        return unfinished
    }

    func endSession() {
        append(level: "notice", category: "session", "Session ended")
        // Another copy that started later has taken the marker over; it's theirs to remove.
        guard markerOwner == nil || markerOwner == getpid() else { return }
        try? FileManager.default.removeItem(at: sessionMarker)
    }

    private var markerOwner: pid_t? {
        (try? String(contentsOf: sessionMarker, encoding: .utf8)).flatMap { pid_t($0) }
    }
}

/// Logs to the unified log, as before, and to Slater's log file. Messages are plain strings and
/// public in the unified log: timings, counts and error descriptions, never text read off the
/// screen (ADR 0001).
struct Log: Sendable {
    private let logger: Logger
    private let category: String

    init(category: String) {
        self.category = category
        logger = Logger(subsystem: "app.slater", category: category)
    }

    func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        DiagnosticLog.shared.append(level: "notice", category: category, message)
    }

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        DiagnosticLog.shared.append(level: "error", category: category, message)
    }
}

/// What a report says about the app and the Mac.
enum SystemSummary {
    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    static var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    static var oneLine: String {
        "Slater \(version), macOS \(ProcessInfo.processInfo.operatingSystemVersionString), \(hardwareModel)"
    }
}
