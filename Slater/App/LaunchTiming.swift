import Darwin
import Foundation
import os

private let logger = Log(category: "launch")

/// Milestones of a launch, logged as time since the kernel started the process, so that a slow
/// launch can be read in Console and launches compared across builds. Timings only (ADR 0001).
enum LaunchTiming {
    /// Milliseconds since the process started, which counts dyld's work before `main`.
    static func millisecondsSinceProcessStart() -> Int {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0 else { return -1 }
        let started = info.kp_proc.p_starttime
        var now = timeval()
        gettimeofday(&now, nil)
        return ((Int(now.tv_sec) - Int(started.tv_sec)) * 1_000_000 + (Int(now.tv_usec) - Int(started.tv_usec))) / 1000
    }

    static func log(_ milestone: String) {
        logger.notice("Launch: \(milestone) \(millisecondsSinceProcessStart()) ms after the process started")
    }

    /// Logs the first time the main thread has nothing left to do: the menu bar item has been
    /// drawn and the hotkeys answer.
    @MainActor
    static func logFirstIdle() {
        let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, false, 0) { _, _ in
            log("Main thread idle")
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
}
