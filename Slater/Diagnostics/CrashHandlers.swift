import Darwin
import Foundation

// Set once at launch, before the handlers are installed, and only read after that: a signal
// handler can't take a lock or capture anything.
nonisolated(unsafe) private var crashLogDescriptor: Int32 = -1
nonisolated(unsafe) private var sessionMarkerPath: UnsafeMutablePointer<CChar>?
nonisolated(unsafe) private var previousPreprocessor: objc_exception_preprocessor?
nonisolated(unsafe) private let frames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: 128)

private func writeToLog(_ text: StaticString) {
    _ = write(crashLogDescriptor, text.utf8Start, text.utf8CodeUnitCount)
}

/// Writes what the process can still say about its own death to the log file: the signal and the
/// crashing thread's backtrace, and each Objective-C exception's name, reason and backtrace as
/// it is thrown. macOS's own crash report is still written, since the crash is handed back to
/// the system.
enum CrashHandlers {
    private static let crashSignals = [SIGTRAP, SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE]
    /// Asked to quit from outside (`kill`, a rebuild): not a crash, so the session marker goes.
    private static let quitSignals = [SIGTERM, SIGINT, SIGHUP]

    static func install(log: DiagnosticLog) {
        crashLogDescriptor = log.fileDescriptor
        sessionMarkerPath = strdup(log.sessionMarker.path)

        // Every Objective-C exception, as it is thrown. An uncaught-exception handler isn't
        // enough: AppKit catches an exception thrown in a layout pass and crashes the app itself
        // (`_crashOnException:`), without that handler ever running and without the reason in
        // macOS's crash report. The previous preprocessor is Foundation's, which records the
        // backtrace, so it runs first.
        previousPreprocessor = objc_setExceptionPreprocessor { thrown in
            let exception = previousPreprocessor?(thrown) ?? thrown
            if let exception = exception as? NSException {
                var text = """
                    \n*** Exception thrown (a crash follows unless something catches it): \
                    \(exception.name.rawValue): \(exception.reason ?? "no reason given")
                    \(exception.callStackSymbols.joined(separator: "\n"))
                    *** End of exception\n
                    """
                text.withUTF8 { _ = write(crashLogDescriptor, $0.baseAddress, $0.count) }
            }
            return exception
        }

        for signal in crashSignals {
            var action = sigaction()
            sigemptyset(&action.sa_mask)
            action.sa_flags = SA_SIGINFO
            action.__sigaction_u.__sa_sigaction = { signal, _, _ in
                Darwin.signal(signal, SIG_DFL)
                writeToLog("\n*** Slater crashed: ")
                switch signal {
                case SIGTRAP: writeToLog("SIGTRAP (a Swift runtime failure or an AppKit exception)")
                case SIGABRT: writeToLog("SIGABRT (abort)")
                case SIGSEGV: writeToLog("SIGSEGV (bad memory access)")
                case SIGBUS: writeToLog("SIGBUS (bad memory access)")
                case SIGILL: writeToLog("SIGILL (illegal instruction)")
                default: writeToLog("SIGFPE (arithmetic error)")
                }
                writeToLog("\nBacktrace of the crashing thread:\n")
                backtrace_symbols_fd(frames, backtrace(frames, 128), crashLogDescriptor)
                writeToLog("*** End of backtrace\n")
                // The handler just returns. A fault then happens again, and `abort` raises its
                // signal again, each now with the default action, so macOS's crash report shows
                // the real stack and the real fault rather than this handler.
            }
            sigaction(signal, &action, nil)
        }

        for signal in quitSignals {
            Darwin.signal(signal) { signal in
                if let sessionMarkerPath { unlink(sessionMarkerPath) }
                writeToLog("Session ended by a signal\n")
                Darwin.signal(signal, SIG_DFL)
                raise(signal)
            }
        }
    }
}
