# Pack persistence isolation

GenericPackConfigTests and VallackSystemPackTests previously backed up the shared
installed-pack tracker and restored it at teardown. Reconciliation tests also
modified that shared tracker, sometimes restoring it from an unawaited Task.
Legacy managed snapshots used AppPaths even when the command's rule files lived
in an explicitly supplied configuration directory. Independent tests could
therefore overwrite or remove another test's state.

RuleCollectionsManager now takes its installed-pack tracker as a dependency;
bootstrap reconciliation and ownership admission read that owner. Production
construction retains the shared default. CLI-created scoped managers use their
existing command-owned tracker. Legacy snapshot reads and cleanup use the same
configuration directory as the manager; ordinary production defaults and the
snapshot/record formats are unchanged.

Generic, Vallack and reconciliation fixtures own private tracker files and
preference domains. The system-pack transaction fixture also seeds its legacy
snapshot in its private directory. No fixture restores an app-global tracker.
A failed first reconciliation run exposed assertions still reading the shared
preference owner; those now assert against the manager's injected owner. The
initial failure log is retained at
`/private/tmp/keypath-pack-persistence-RuleCollectionsManagerTests.log`.

## Focused qualification

Serial checks passed with zero Swift warnings:

- 46 Generic pack checks.
- 30 Vallack checks.
- 37 collection-manager checks after correcting the preference assertion target.
- Nine system-pack transaction checks, including older snapshot restore and
  corrupt-data refusal.
- 27 CLI pack CRUD checks and 14 pack-ownership checks.
- Two new cross-directory regressions: the same pack ID has independent modern
  snapshots, and corrupt legacy data/cleanup cannot reach a second directory.

The same seven suites then ran with two XCTest workers: SwiftPM listed 165
unique selected cases and completed with exit zero in 27 seconds (29 total).
The safe runner's pretty counter does not parse parallel progress and printed
“0 passed”; the individual SwiftPM selection list and successful process exit,
not that counter, establish the scope of this qualification. Runner log:
`/private/tmp/keypath-pack-parallel-runner.log`.

This qualifies this subset, not unrestricted in-process parallelism. Other
TestEnvironment and dialog override globals remain separate audit work. Full
safe-gate, review and CI acceptance are recorded with the PR. No physical input
was sent and the VM base fingerprint contract is unchanged.
