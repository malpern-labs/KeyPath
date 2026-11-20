# Scoped app-control routing and retired restart helper

ConfigFacade's fake app endpoint and engine routing were process-wide unsafe
mutable variables. Tests saved/restored them, so independent requests could use
another test's endpoint. An internal initializer now binds one fake endpoint
and via-app mode to one facade value. The normal app/CLI routing default retains
its public API and is protected by a Mutex; production facades still consult the
current default, including facades constructed before app composition finishes.
The socket path is copied from the instance before the detached IPC call.

A same-process async-let regression creates two live fake apps, sends both
requests concurrently, and verifies each response and request record belongs to
its own endpoint. The tests no longer change or restore process-wide routing.

The caller audit also found AppRestarter had no production callers. Its helper,
unsafe test defaults override and eleven retired-behavior tests were removed.
The app's legacy WizardRestorePoint/WizardRestoreTime reader remains unchanged
for older installations. The full onboarding implementation is unchanged.
Logger-only tests remain, and no active system-operation safeguard was removed.
The testing-improvement plan no longer proposes mocking the deleted helper.

## Evidence

Eight IPC checks and seventeen remaining logger checks passed with zero Swift
warnings. A fresh two-worker run listed all 25 unique cases and exited zero in
eight seconds under a renewed bounded agent-awake lease. The runner's summary
counter does not parse parallel output; the complete selection list and zero
exit were checked directly in
`/private/tmp/keypath-scoped-routing-parallel.log`.

Earlier long elapsed times are not performance evidence: pmset recorded repeated
maintenance sleeps from 02:03 onward while the bounded wake lease was expired.
The agent refreshed the lease before the fresh qualification. The earlier logs
are retained rather than relabeled as fast runs. No host runtime or physical
USB verification is claimed by these tests. Final full-gate/review and CI
acceptance are recorded in the PR.
