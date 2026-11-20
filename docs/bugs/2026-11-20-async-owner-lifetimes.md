# Async watcher ownership — November 20, 2026

## Device-monitor startup and stop

HIDDeviceMonitor published its run loop only after starting its worker thread.
A stop before publication could miss the worker, and a new start could reuse the
single run-loop slot before the old worker cleaned it up. Queued callbacks also
had no originating-session check.

Each start now owns a HIDMonitorSession. Cancellation before attachment is
remembered. Cancellation after attachment queues a stop block and wakes the
run loop; it is effective even before CFRunLoopRun begins. The callback context
stays alive through IOKit teardown. MainActor callbacks and natural worker
retirement act only on the current session, so an old worker cannot overwrite
its replacement. Registry observation remains read-only and requests no new
permission.

The session retains an explicit unchecked boundary for CoreFoundation's
non-Sendable run-loop object; all access to that object's reference and the
cancellation flag is locked. This is an owned framework boundary, not a reason
to replace every existing lock merely to reduce annotation counts.

## Configuration watcher

A comment said all ConfigFileWatcher state was main-thread-owned, but the type
and its asynchronous methods did not enforce that owner. It is now a checked
MainActor type. Explicitly Sendable DispatchSource handlers read only their
source data before hopping through the main queue. The source is weakly
captured, and actor-isolated destruction cancels owned sources and tasks.

A watch generation rejects queued events and delayed work from an earlier
watch. Retries, rebinding and debouncing are cancelled at stop; a stopped watch
also drops its pending internal-content claim. The atomic-write suspension and
in-flight-processing cleanup preserve the same generation. This prevents an
old watch from rebinding or suppressing a new watch's external edit.

## Authentication state

BiometricAuthService's session flag relied on an unenforced single-writer
comment. Settings access, authentication completion and cache invalidation now
share a checked MainActor owner. Immutable preference-key and usage-reason
constants remain nonisolated. This does not change authentication policy or
claim a live Touch ID test.

## Focused evidence

- Four HID session tests exercise cancellation before attachment, cancellation
  after attachment but before the real CFRunLoop starts, retirement, and a
  replacement owner. They do not send keyboard input.
- Fourteen watcher tests include a real background filesystem event asserting
  MainActor delivery, a controlled suspended rebind, and an internal-revision
  claim that must not suppress a different watch's edit.
- Eight KindaVimStateAdapter tests passed after watcher isolation.
- Twenty-five AI configuration tests passed, including disabled authentication
  invoked from a detached caller without a biometric prompt.

The full safe gate and review are recorded with the final change. Physical USB
qualification remains deferred. None of these tests proves a host deployment or
changes the VM base fingerprint contract.

## Final gate evidence

The local review gate passed with no blocking findings. The full safe gate
compiled with zero Swift warnings and passed 4,456 XCTest cases (46 skipped),
then reached the unchanged snapshot target before its shared 240-second test
budget expired. This is a timeout, not a passing full gate. The snapshot class
was subsequently checked separately with rendering explicitly enabled; see the
PR validation record for its result. CI remains required before merge.
