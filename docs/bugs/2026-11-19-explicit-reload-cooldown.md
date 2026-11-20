# Explicit CLI reload can fail during a healthy runtime cooldown

Observed on the owned macOS 27 warm guest after a guarded signed replacement
of KeyPath `3fcbbc812f6d2381cb8f3201192bfbd5660298c1`.

The baseline `q → q` apply and independent input capture succeeded. The next
`rule ensure q a --apply --json` persisted the rule but exited 6, reporting
“Could not connect to Kanata TCP server.” The guest log showed a healthy
runtime and `Reload cooldown - 1.2s remaining` at the CLI request. A later
file-watcher/deferred reload connected to the worker socket and received a
successful `ReloadResult`. This was a throttle disposition, not an observed
socket outage. The test stopped at the failure; it did not pass remapping.

The runtime-control handler had treated the coordinator's pending cooldown
result as a final failed CLI reload. The coordinator already correctly deferred
ordinary watcher reloads and retained crash-loop and runtime-intent guards.

The fix under validation lets explicit CLI requests wait for a short cooldown,
bounded to three waits of at most three seconds each, then rechecks safety
before asking the engine. A manual Stop, changed runtime intent, or cancelled
wait must not issue another reload. Background watcher behavior stays deferred.
An exhausted budget remains pending/failure; it is never relabelled applied.

Deterministic tests use an injected safety-monitor clock and wait closure.
Required live acceptance is the same signed guest, independent baseline and
remapped capture, then a remapped capture after app/worker relaunch. Record any
failed attempts; a later successful retry does not erase them.

Mini evidence: `/Users/malpern/keypath-master-qa.OoDDNH/` contains exact build
provenance, `signed-swap.log`, `remap-repeatable-1.log`, and
`guest-runtime-after-failure.log`. A separate earlier harness failure was an
existing capture-app path; the lab change gives each run a unique path and
establishes its baseline explicitly. That fix does not fix the product reload.

## Candidate acceptance

The committed fix `f2434116a810b172ab4da20ee4a44c64c37f4395` built and
Developer ID signed in 169.59 s through the Mini GUI session. Its guarded
replacement on the same warm guest took 23.80 s and verified archive/executable
hashes and unchanged boot identity. Two independent harness runs passed all
three captures in 20.86 s and 22.44 s, with no retry inside either run.
The old failures remain in the earlier evidence folder. Current evidence:
`/Users/malpern/keypath-reload-qa.qPovh4/` on the Mini.

These are candidate functional results, not a clean-consent test, host deployment,
or a notarized release qualification. Full safe-gate and merge results must be
recorded separately. Physical USB was not used.

The full safe gate subsequently passed 5,530 tests with zero Swift warnings
(215 s build, 229 s tests, 447 s total). Guest artifacts downloaded and the VM
was deleted; cleanup emitted a hydration-stop-marker warning. Do not describe
that cleanup as warning-free. Splash show/overlay/hide events were retained in
`splash-log.log`; these are timing logs, not a new visual screenshot test.
