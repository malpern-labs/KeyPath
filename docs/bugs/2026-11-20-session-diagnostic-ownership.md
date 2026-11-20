# Session diagnostic callback ownership

The HID transport's diagnostic callback was a mutable static closure marked
`nonisolated(unsafe)`. The worker normally installs its logger before doing HID
work, but the public setter did not enforce that ordering or prevent concurrent
replacement. The closure is now Sendable and stored behind a Mutex. A getter
copies it while locked; the caller invokes the copy after the lock is released.
Logging can reenter without holding the storage lock. This does not change HID
selection, command execution, permission checks, or mapping policy.

The existing service-group tests exercise injected HID responses rather than
host devices. Physical USB testing remains deferred.

## Audit limits

This change closes one unchecked callback-storage boundary, not the whole
concurrency review. PreferencesService still stores observable mutable Swift
properties in addition to its UserDefaults backing; its existing claim that all
mutable state is UserDefaults-backed is insufficient as a concurrency argument.
It needs caller and actor-isolation review before the broader item can close.
NotificationObserverManager protects observer storage with an NSLock and removes
notifications outside that lock. Its setup-only safety comment is outdated; a
lock-backed framework token boundary is not itself a reason for a rewrite.

## Validation

Sixteen injected HID service-group checks passed with zero Swift warnings.
The local review gate passed, and accessibility, no-sleep lint and string-catalog
checks passed. The full safe gate compiled without warnings and passed its
4,452-case main XCTest target (46 skipped), then exceeded the shared 240-second
test budget in the snapshot run. This is retained as a timeout, not a full pass.
Master's owner-lifetime changes were subsequently merged normally; integrated
focused validation and required CI remain the merge acceptance gates.
