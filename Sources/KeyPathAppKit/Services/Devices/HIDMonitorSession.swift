import Foundation

/// One registry-watcher lifetime. CFRunLoop is not Sendable, so the boundary
/// stays unchecked; every access to its cancellation state and loop is locked.
/// A retired session can never publish or clear another worker's loop.
final class HIDMonitorSession: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var runLoop: CFRunLoop?

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func attach(_ loop: CFRunLoop) -> Bool {
        lock.withLock {
            guard !cancelled, runLoop == nil else { return false }
            runLoop = loop
            return true
        }
    }

    func cancel() {
        lock.withLock {
            guard !cancelled else { return }
            cancelled = true
            guard let runLoop else { return }
            // CFRunLoopStop before CFRunLoopRun can be lost. A queued block
            // also runs when cancellation lands between attach and run.
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(runLoop)
        }
    }

    func finish() {
        lock.withLock {
            cancelled = true
            runLoop = nil
        }
    }
}
