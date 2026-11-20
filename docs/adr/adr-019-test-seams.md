# ADR-019: Test Seams via TestEnvironment Checks

**Status:** Accepted
**Date:** November 2025

## Context

Production code has side effects that would disrupt test execution:
- Process spawning (`pgrep`)
- CGEvent taps
- Sound playback
- TCP connections
- Modal alerts
- Notification Center
- File watchers

Full dependency injection would require injecting many services for marginal benefit.

## Decision

Use `TestEnvironment.isRunningTests` checks (37 occurrences) to disable side effects during testing.

## What's Protected

| Side Effect | Why Disabled in Tests |
|-------------|----------------------|
| `pgrep` spawning | Deadlocks in parallel tests |
| CGEvent taps | No system access in CI |
| Sound playback | Annoying, slow |
| TCP connections | No Kanata in tests |
| Modal alerts | Block test execution |
| Notification Center | System integration |
| File watchers | Race conditions |

## Why Not Full DI?

Would require injecting: SoundManager, NotificationService, EventTapController, SafetyAlertPresenter, shell runners, TCP clients, etc. Massive refactoring for marginal benefit.

## Why This Is Safe

These checks guard **side effects**, not business logic. Core logic still executes and is tested.

## System Validation

`SystemValidator` captures system evidence by default. Tests that need
synthetic evidence pass a snapshot provider or a `WizardSystemValidating`
stub. Run `TEST_FILTER=SystemValidatorTests ./Scripts/run-tests-safe.sh` to
exercise the real capture path with a test runtime probe and verify the
timeout and cancellation contracts.

## For New Code

Inject dependencies when they control a decision or return synthetic
evidence. Use test-host checks where needed to prevent real system side
effects during tests.
