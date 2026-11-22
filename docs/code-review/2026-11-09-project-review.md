# KeyPath project review — 2026-11-09

Reviewed at `master` a20de9c3 (#1391). Four areas: bloat, over-engineering,
macOS best practices, security.

**How this was done.** Static reading and grep only. Nothing was built, run or
connected to. Each area was read by a separate reviewer; the claims in the
"Top recommendations" table and every security finding rated Medium or higher
were then re-checked against the code by hand. Unfixed security findings other
than the already public S1 are tracked privately (see section 1). Items not re-checked, or that
need a running system to confirm, are marked *unconfirmed*. `External/kanata`
was not checked out, so statements about the engine's TCP command set come from
ADR-046 and the Swift client, not the fork's source.

## Status (updated 2026-11-22)

The latest tracked follow-ups include [#1613](https://github.com/malpern-labs/KeyPath/pull/1613) and [#1615](https://github.com/malpern-labs/KeyPath/pull/1615), both merged. The findings below this status section describe the original review.

Key: ✅ done · 🟡 partly done or in progress · ⬜ not started · 🔒 tracked privately

### Progress toward the review goals

Twenty-three review-related PRs have merged (#1589–#1605, #1607, #1608, #1610, #1611, #1613, and #1615; excludes unrelated #1575). This count includes #1602, #1613, and #1615, which GitHub confirms are merged. Since then #1623 (two-lane CI measurement), #1624 (P6) and #1625 (Japanese mapper label) have merged. The section table below has 29 tracked rows: 28 complete and one partial (B7). Other security findings remain separately tracked in private. Row counts are not a claim that 90% of the engineering effort or risk is gone.

### Progress toward the outcomes

| Outcome we wanted | Evidence of progress | What is still needed |
|---|---|---|
| **Ship a smaller, less tangled app** | The dead-view/assets and cleanup passes removed about 34,000 lines of obsolete scripts, docs, tests and code; the unused BehaviorStatePicker assets removed about 15 MB from the app. The CLI now shares core rule/config work while preserving the Metal onboarding and pack gallery the owner chose to keep. | O7's remaining pack mutations still depend on AppKit. Keep that boundary unless a concrete shared transaction contract makes extraction safe; this is a deliberate stopping point, not a mandate to remove features. |
| **Make routine changes safer and easier to validate** | P9 is complete: the full safe suite passed with two XCTest workers, 4,729 XCTest cases and 847 Swift Testing cases, zero failures, skips or Swift/module-cache/app warnings. The Swift Testing subset also passed three repetitions. Tests now isolate mutable defaults, stores, loggers, notification centers, caches, temporary files, and runtime bridges. | SwiftPM does not offer same-process XCTest repetition. This tooling limitation does not leave P9 open. Concurrent CI throughput is a separate performance qualification. |
| **Reduce CI and agent wasted work** | The no-op cache-warm job was removed; worktrees were moved off ephemeral storage; build slots cap concurrent heavy builds; stale automation harnesses were deleted. Earlier Mini CI runs showed a two-worker lane at 308 s (339 s full job) and two four-worker lanes at 195 s and 180 s (209 s and 244 s full jobs); the latter passed 4,729 XCTest and 849 Swift Testing cases without warnings. A repeat of the exact `test-lane.sh full` command on the Mini then passed at two workers in 255 s and at four workers in 152 s and 148 s, with zero failures or Swift/module-cache/app warnings. That matched-command comparison cut lane time by about 41%; `.github/workflows/ci.yml` now uses four XCTest workers and six Swift build jobs on the Mini. #1615 lets either Mini runner take `test-full`. Two full GitHub job windows overlapped briefly in runs [3134](https://github.com/malpern-labs/KeyPath/actions/runs/44965218473) and [3135](https://github.com/malpern-labs/KeyPath/actions/runs/44965469829), and both passed. Inspecting the job logs shows this did **not** exercise concurrent Swift builds or tests: the first `swift test` launched at 00:10:44 UTC and ran for 189 s; the second launched at 00:14:07 UTC and ran for 281 s. The second lane's setup/build began only after the first test command had finished. | Done November 22: run [45038843588](https://github.com/malpern-labs/KeyPath/actions/runs/45038843588) on master `c8eb8ce5` ran both full lanes at the same time, one per runner, with test windows 15:33:22–15:38:17 UTC. Both passed. Test phases took 241 s and 237 s against a 167 s single-lane baseline (#1619), about 1.4× slower each, but the pair finished in about 241 s instead of 334 s back to back. Host samples every 15 s: memory free never below 85%, swap flat, load peaking at 39.5, at most 10 Swift processes. This is one run, not a long series; on it, two concurrent full test jobs are qualified. |
| **Keep the runtime secure and release behavior understandable** | ADR-046's unauthenticated TCP listener is gone; engine control uses a private Unix socket with PID and signature checks. Release logging ignores environment overrides, and Caps Lock diagnostics now state the limits of process attribution. | Other security findings remain in private tracking. The public review doc intentionally does not enumerate them. |
| **Make Japanese and public guidance trustworthy** | The Japanese catalog received a 3,679-string independent review; all 87 changed strings passed re-review. Current organization-hosted setup/privacy/uninstall/migration pages were verified after publishing. On November 21, both the organization and legacy 1.0.1 migration URLs returned HTTP 200 from the Mini. | Live Japanese layout is checked (see P8). The 1.0.1 cleanup rehearsal remains. |

This is the outcome accounting for the review, separate from the PR count: improvements are recorded only where the doc has concrete evidence. A passing test suite measures test behavior, not customer reliability; merged code does not by itself prove a live macOS flow or published page.

The merged work advances the original review goals as follows:

| Review goal | Progress represented by the overnight merges |
|---|---|
| **Reduce over-engineering (O7)** | #1589 and #1591–#1593 move configuration admission, rule operations, and generation out of the UI framework while retaining the pack gallery, confirmations, dependencies, and rollback. #1609 adds checked CLI pack-install admission, so conflicts are refused without changing the user's configuration. The remaining AppKit use for pack mutations is a deliberate boundary: extraction is deferred unless a shared transaction contract offers measurable build savings without changing behavior. |
| **Improve localization (P8)** | #1597 and #1598 fix and independently review Japanese strings; #1601 verifies the macOS 27 permission-pane name against Apple’s Japanese system strings. On November 22 every onboarding, tour, overlay, drawer and mapper screen was checked live in Japanese on a signed build; the one Japanese-only clipping it found is fixed by #1625. |
| **Improve concurrency and CI reliability (P6/P9)** | #1590 and #1603 remove obsolete runtime/test behavior and isolate shared test state; #1605 removes tests against the retired TCP listener. #1593 adds compiler-checked runtime readiness ownership. #1608 retained one full-test CI lane; #1615 now allows either Mini runner to run it. P9 is complete: the full safe suite passed with two XCTest workers (4,729 XCTest invocations and 847 Swift Testing cases), with zero failures, skips or Swift/module-cache/app warnings; Swift Testing also passed three repetitions. The separate four-worker Mini benchmark passed twice and was faster. P6 is complete: the last delayed-callback audit bound the drag-to-authorize overlay's work to its presentation, and live overlay timing and capture teardown passed on signed builds (November 20 and 22). |
| **Reduce CI waste and agent friction** | #1594 removes a cache-warm workflow that warmed no PR job’s cache; #1595 and #1596 move worktrees off ephemeral storage and require bounded build slots. #1615 enables the second Mini runner for full tests and lowers build parallelism to 6 per job. Two-vs-four worker comparison is complete, and two simultaneous full test jobs on the two daemon runners passed on November 22 with ample memory headroom. |
| **Improve security and release behavior** | #1600 makes Caps Lock conflict attribution depend on verified ownership evidence and states the limits of macOS attribution; #1604 ignores environment log-level overrides in Release builds. |
| **Keep process guidance accurate** | #1599 documents the organization’s merge queue so PRs are tested against current `master` before merge. |

This ledger tracks outcomes toward the review goals: less unnecessary framework coupling and dead code, accurate install guidance, macOS-correct behavior, usable Japanese screens, isolated/reliable tests, and closed security findings. A merged PR or green CI alone is not acceptance evidence for live desktop, release or lab items.

### Top recommendations

| # | Item | Status | Where |
|---|---|---|---|
| 1 | ADR-046 (S1) | ✅ The TCP port is gone. The private Unix socket checks the app PID and its code signature. CLI coverage and design docs merged. | #1412–#1416 |
| — | Other security findings | 🔒 Tracked privately | — |
| 2 | Public docs | ✅ Fixed on master and republished to the website, including `getting-started/` and `migration/`. | #1394, #1402 |
| 3 | `BehaviorStatePicker` + 15 MB of PNGs | ✅ Deleted. | #1398 |
| 4 | Deletion pass (~34k lines) | ✅ Done. Remaining asset and package follow-ups are listed below. | #1395, #1397, #1398, #1399, #1406 |
| 5 | Update story | ✅ Sparkle is re-enabled. The managed Caps Lock gate passed on notarized builds after a worker-exit fix. | #1409, #1418, #1419 |
| 6 | Installer collapse (O1) | ✅ Planner indirection removed. One repair action remains: Start Remapping Engine. | #1410, #1421 |
| 7 | `NSAppleEventsUsageDescription` | ✅ Added; the normal System Events consent prompt and usage explanation were captured on a fresh macOS 27 guest with signed candidate f2434116a. | #1404 |

### By section

| Item | Status | Notes |
|---|---|---|
| **O1** Installer planner | ✅ | See row 6. |
| **O2** Four copies of UI state | ✅ | The UI reads status and dialogs from their owners. Settled collections and custom rules are observed directly. `KanataUIState`, `StatePublisherService`, and manual UI refresh calls were removed (#1435, #1436, #1443, #1447). |
| **O3** Forwarding layers on the rule path | ✅ | Rule toggles and custom rules use the settled rule state. `RuleCollectionsCoordinator` was removed, and reloads use one result and transport seam (#1435, #1436, #1441, #1444). |
| **O4** Wizard module boundary | ✅ | Kept the module for the CLI. Removed dead boundary code, unified runtime status, and replaced `WizardDependencies` with environment-provided `InstallerServices` (#1423–#1425). |
| **O5** Events, health polling, stacked caches | ✅ | Removed the dead router and drove app validation from lifecycle health changes (#1406, #1442). Migrated key input, activation and resolution, and the remaining engine events to typed messages ([#1448](https://github.com/malpern-labs/KeyPath/pull/1448), [#1450](https://github.com/malpern-labs/KeyPath/pull/1450), [#1451](https://github.com/malpern-labs/KeyPath/pull/1451)). Made `PermissionOracle` the sole validation permission cache ([#1452](https://github.com/malpern-labs/KeyPath/pull/1452)) and consolidated async timeout helpers in `KeyPathCore` ([#1453](https://github.com/malpern-labs/KeyPath/pull/1453)). |
| **O6** Plugin system | ✅ | Downloads removed (#1407); Insights linked into the app (#1411). |
| **O7** Metal stage and first-run onboarding | ✅ | Keep the full Metal onboarding experience. Implementation simplifications can proceed when they preserve the first-run visuals and interactions. |
| **O7** Packs | ✅ | Owner decision: keep the gallery and pack installation/dependency features. Remove only proven dead code around them; do not replace packs with built-in presets. |
| **O7** CLI split | ✅ | Rule and collection operations, backup and restore, simulator, system inspection and logs, layout resources, backup storage, and generation inputs moved to shared Core targets (#1532, #1543–#1546, #1563–#1569, #1586). Three CLI files still import `KeyPathAppKit` for pack install/configure/uninstall. Checked admission prevents unsafe CLI mutations; guided onboarding retains its explicit path. The remaining operations intentionally share pack decision/transaction behavior with the UI. No measurable build benefit justifies extracting that contract now, so the boundary is closed by design and should be revisited only with concrete evidence. |
| **O8** Unimplemented flags, wording, public-docs lint | ✅ | #1405. |
| **O8** CLI link and service ownership | ✅ | New links install under `~/.local/bin` and uninstall removes matching links. `AGENTS.md` documents when to use `ServiceContainer` or a singleton (#1429). |
| **O8** Test-mode checks and lint ratchets | ✅ | Retired lint tests and passwordless sudo test mode (#1428). Unified the parser (#1566), scoped keyboard-recognition fixtures (#1570), and required explicit test-host evidence before routing ordinary app launches into fixtures (#1577). A source audit of `TestEnvironment` branches found and fixed real-defaults and real-Keychain fallbacks; the remaining branches redirect file paths or suppress external process, permission, UI, and network side effects. Per-test shared state was completed under P9. |
| **B1** Dead view and images | ✅ | #1398. |
| **B2** Scripts | ✅ | #1395. |
| **B3** Dead Swift | ✅ | Deletion pass merged (#1398, #1406). Function-level Periphery scan completed with 3.8.0; retired unregistered CLI commands and their formatter are removed in this follow-up. Candidate diagnostics are not automatically safe deletions. |
| **B4** Tests for removed behaviour | ✅ | Dead tests removed and two stale references refreshed (#1420). The historical General Settings reference was refreshed to the existing Nothing default in #1478, retaining tolerances. The combined gate passed 5,524 tests. |
| **B5** Binary assets | ✅ | Unused assets removed (#1397); help assets compressed/deduplicated (#1422). Metal goldens losslessly recompressed in #1479: 28.7% smaller, identical decoded scanlines, full resolution and tolerances retained. |
| **B6** Root and package stragglers | ✅ | Root cleanup merged (#1395). Process probes moved into Core and the unused wizard screenshot and resource bundle were removed (#1440). Nine unused library product exports removed in #1475; executable products and internal target dependencies remain unchanged. |
| **B7** Docs | 🟡 | Public docs republished and runtime architecture rewritten (#1394, #1399, #1402, #1437). The live organization Pages setup, privacy, uninstall, and 1.0.1 cleanup pages returned HTTP 200; setup links macOS 27+ and the version-pinned 1.0.1 path. [malpern.github.io#1](https://github.com/malpern/malpern.github.io/pull/1) is merged. Its hourly Pages workflow asserts the generated route and expected title before deployment; run #27 on `main` succeeded at commit `245a246` on November 21. Both organization and legacy 1.0.1 migration URLs returned HTTP 200 from the Mini on November 21. The cleanup rehearsal plan tests the supported manual guide, not withdrawn in-app migration. The official 1.0.1 ZIP matched its published digest. A fresh Parallels lease subsequently booted macOS 26.5.2 with KeyPath 1.0.1 installed, confirmed read-only through the installed lab launcher on November 22. UI preflight then blocked because Peekaboo lacks Screen Recording and Accessibility grants in the guest console account; no UI interaction or cleanup ran. That lease and a later macOS 26 guest were destroyed on November 22. The rehearsal remains incomplete: setting up 1.0.1 needs an administrator password for the helper and the driver-extension and background-item approvals, which the lab's consent tool cannot give (it grants only Accessibility), so it needs a person at the guest. Getting Started and the docs index on the site described the retired driver and service stack, gave macOS 15 / Intel requirements and linked missing pages; #1626 corrected them on November 22. #1628 makes `release.sh` update the homepage button's version text with its link, and draft #1627 changes the homepage requirements line for release day. |
| **P1** Sparkle | ✅ | See row 5. |
| **P2** Apple Events usage string | ✅ | #1404. Normal KeyPath → System Events prompt and shipped explanation verified on fresh guest cbx_093147ab40fe, signed candidate f2434116a, November 20. This verifies the requested prompt, not the resulting AppleScript action. |
| **P3** Blocking subprocesses | ✅ | `SecCodeCopySelf` replaces the signing shell-out and pipes are drained before waiting (#1404). Migration discovery is async and bounded, with retryable unknown states and tested stop routing (#1480). System probes also drain both output pipes concurrently (#1483); the serialized full gate passed 5,534 tests. Latest-master deployment and live verification remain separate release checks. |
| **P4** Shell-outs with API replacements | ✅ | Hidden flags, editor launch, function key preference writes, and signals use direct APIs. Spotlight search keeps a cancellable subprocess (#1426). |
| **P5** `os.Logger` in `AppLogger` | ✅ | Unified log output added (#1427). File logger state is synchronized and queued writes flush (#1445). |
| **P6** Concurrency leftovers | ✅ | **Complete.** Feature flags and the app icon cache were synchronized (#1439). Three main-actor service conformances are compiler checked (#1481). Capability caches and several runtime callbacks are compiler checked (#1487, #1571). Duplicate configuration watcher code is gone (#1572). Subprocess launch and cancellation are serialized (#1574). Overlay expiry and view timers now respect their current owners (#1579), and the overlay window owns its sizing and hint work (#1587). The session-worker hard-exit fallback is serialized with orderly shutdown. The final audit of delayed UI callbacks found one owner that could act on stale state, the drag-to-authorize overlay; its delayed work is now bound to the presentation that scheduled it, with seven owner-close tests. Live overlay hide/show timing passed 8 of 8 on signed master `94c96336` (November 22); capture teardown passed on `7b6c369e` (November 20). |
| **P7** Liquid Glass | ✅ | System glass in `AppGlassBackground` (#1408), checked on screen in light and dark. |
| **P7** Other idioms | ✅ | Deprecated drawing and activation replaced (#1460, #1508). The window and wrapper audit removed an unused control and records the behavior each remaining bridge supports (#1509). Color conversion stays with individual surface changes. |
| **P8** Localization | ✅ | English and Japanese share a CI-checked catalog (#1430–#1433). The five overlay translations in #1578 cover the remaining active entries at that revision, verified by Xcode catalog compilation (3,477 of 3,477). Signed builds verified the virtual-key prompt and four Settings screens. An independent review of all 3,679 Japanese strings (ChatGPT, November 21) found 12 blocking issues; 11 are fixed and approved on re-review. The Japanese name of the macOS 27 Accessibility pane matches Apple's (checked November 21). Live layout passed on November 22 on signed master `ec71256` in a macOS 27 guest: Welcome, the first-run permission page, tour steps 1–4, the overlay, its drawer and the mapper fit in Japanese. The mapper's output-type label was cut to キースト…; #1625 lets it shrink before truncating, and a signed build showed the full キーストローク. The tour's left column overflows in both languages, so step 3's picker starts below the fold; that is a layout decision, not a translation defect. |
| **P9** Test isolation | ✅ | **Complete.** The remaining shared fixture and logger state was removed, and the repository-wide audit found no test-side mutation of shared defaults, logger, preferences, or rule stores. The full safe suite passed with two XCTest workers: 4,729 XCTest invocations plus 847 Swift Testing cases, with zero failures, skips, or Swift/module-cache/app warnings (224 seconds). Swift Testing also passed three repetitions. SwiftPM does not repeat XCTest cases in-process; that is a tooling limit, not unfinished P9 work. The separate CI throughput experiment (more XCTest workers or concurrent full-test jobs) is tracked under CI performance, not test isolation. |

P9 follow-up (November 21): `UtilitiesTests` now uses a UUID-scoped `AppLogger` and log directory for each test, flushing before teardown and deleting only its owned directory. Clear-log coverage verifies that pre-clear messages are removed and post-clear messages remain; the assertion-only singleton cleanup test was removed. The merged version retains the stronger cleanup assertion from master. The existing `UnitTestSuite.testLoggerConfiguration` path typo is corrected. The merged focused qualification passes all 18 Utilities tests under `--parallel` and the logger-configuration test (1 test). The merged safe suite passed 4,701 XCTest and 846 Swift Testing cases (27 expected skips), with zero failures or Swift, module-cache, or app warnings/errors. The focused Utilities suite also passes all 18 cases under parallel XCTest workers.

The test base no longer mutates `AppLogger.shared` during setup and teardown. Console verbosity is selected once from the test-run environment when a logger is constructed, with explicit instance configuration taking precedence; focused tests cover quiet/verbose test runs and debug/release defaults. This removes another order-dependent process-global setting.

### Also done since the review (not in its list)

- ADR-048 keyboard attribution: spike, matcher, and log-only matcher in the session worker (#1392, #1393, #1396, #1400, #1401).
- The running app answers the CLI's engine commands. Coverage for that path merged (#1388, #1413, #1415).

### Open follow-ups

- B7: The live homepage and setup page send 1.0.1 users to the tag-pinned guide (#1520). Both published pages returned HTTP 200 after the update. The original notarized 1.0.1 installer passed Gatekeeper on a disposable macOS 26.5.2 guest and reached its background-item approval prompt. The active helper cleanup path is now documented as a manual public-guide rehearsal in [`upgrade-from-1-0-1.md`](../testing/upgrade-from-1-0-1.md); the withdrawn in-app cleanup flow is explicitly out of scope. The legacy-host route guard merged in `malpern/malpern.github.io#1`; the workflow confirmed the generated route and deployment on November 21. When the session-runtime release is live, put macOS 27+ and Apple Silicon alongside its download and link the manual cleanup guide from setup and uninstall. Revisit automatic migration if tester evidence shows the manual path is a recurring barrier. See [ADR-047](../adr/adr-047-pre-release-cleanup.md).

- O7b: Keep the pack gallery, installation, and dependency features. Rules Core owns the read-only rule, collection, and pack catalog paths and the simulator (#1532, #1543, #1546, #1548). The simulator passed 35 focused tests, including four that run the bundled simulator. Seven comparisons against the preceding CLI matched stdout, stderr and exit status. System inspection and logs moved to CLI Support (#1568). Layout resources, backup storage, and generation inputs moved to Rules Core (#1565, #1586). Current source scan finds only three `KeyPathAppKit` imports in CLI commands: pack install, configure and uninstall. CLI pack installation now uses checked admission: if the app would ask what existing rule or pack to disable, the CLI refuses without changing state and points the user to the Packs gallery. Guided onboarding retains its explicit unchecked path. Keep the remaining UI-backed mutations together until an explicit, shared decision/transaction API can preserve that behavior; do not add a broad engine target solely to remove imports. See the [CLI compile-boundary evaluation](#cli-compile-boundary-evaluation).
- O8c: The installer pack decisions and validator snapshots use scoped test inputs (#1523, #1525). The unused forced test mode was removed (#1528), and its full safe suite passed 5,529 tests. Removing the unused file-validation route and shared validation-host override preserved the real parser path in 165 focused tests (#1547). The audit found a test writing through `PreferenceDefaults.canonical` to the real standard defaults domain; it now uses its UUID-scoped `IsolatedPreferenceDefaults`. Implicit `PreferenceDefaults.canonical` and `PreferencesService` fallbacks now use a unique process-local test domain. Activity-log encryption previously used a separate real Keychain item in tests; it now keeps test keys in memory, with no Keychain calls. Regression tests cover both boundaries. Other `TestEnvironment` branches redirect fixture paths or suppress external process, permission, UI, and network side effects. The focused preference and activity-encryption tests passed on November 21. The final P9 audit found no remaining test-side mutation of these shared fallbacks; same-process XCTest repetition remains a SwiftPM limitation, not an open isolation task.
- P6: The mapper cancels delayed resets when the selection changes (#1519, #1540). Stale layer-indicator and tooltip callbacks respect their current window (#1526, #1534). Favicon completion and engine timeout cleanup follow their owning operation (#1538, #1549). In 85 focused tests, the timeout change preserved a replacement connection and its buffer. Capture teardown (#1567) and the overlay window's ownership of sizing and hint work (#1587) merged. The latter passed 51 focused tests and 5,548 full local checks. An earlier pass found that cancelling the owner-exit `DispatchWorkItem` did not serialize an already-enqueued hard exit against orderly shutdown; both paths now share a lock, with four focused tests including the race ordering. The final timer and framework-handoff audit (November 22) bound the drag-to-authorize overlay's delayed work to its presentation and judged the remaining callbacks safe; see the P6 section. Live overlay timing and capture teardown passed on signed builds. P6 is complete. The Layout Tracer compiler trial is recorded below.
- P8: The Japanese virtual-key confirmation and General Settings stable-update label fit in signed macOS 27.2.1 builds. Settings option cards and Status actions use language-independent IDs (#1535). Xcode compiled eight additional Japanese translations (#1536) and localized the Stable and Beta channel labels (#1542). #1578 added the Japanese remap and navigation labels. The signed guest captured General Settings, Status, Home Row Mods and Repair in Japanese. An independent review of all 3,679 Japanese strings and the permission prompts (ChatGPT through the Codex CLI, November 21) found 12 blocking issues: two swapped menu labels, an unnumbered placeholder reorder, two gesture instructions, three uses of ウインドウ for a reporting period, a shared Start key, a stale setup path, a KindaVim term and the Accessibility pane name. Eleven are fixed (the Vim keycap now has its own key, `vim.keycap.line-start`) and the re-review approved them. Its 33 minor suggestions were then applied too: wording, consistent terms (設定, 上段, 受付時間, 修飾キー, オペレータ, スペースバー in prose), numbered placeholders, and own keys for the Vim Open keycap, the Delete key name and the numpad Operators heading. A second review approved all 87 changed strings. Apple's own macOS 27.3 string tables (SecurityPrivacyExtension, TCC and the authorization prompt, key `ACCESSIBILITY`) give that pane as デバイスの制御とデータへのアクセス in Japanese, which KeyPath already uses, so the reviewer's アクセシビリティ (the pre-macOS 27 name) was not applied. On November 22 live layout passed for onboarding, the tour, the overlay, its drawer and the mapper on signed master `ec71256`; the one clipped label is fixed by #1625.
- P9: Pack and collection tests, Caps Lock selection, leader recovery, the overlay window and onboarding fixtures use isolated test state (#1514, #1521, #1523, #1527, #1531). A safe-runner qualification on master `c2550766` passed 4,734 XCTest invocations with two worker processes plus 844 Swift Testing checks. A focused media-key test reproduced a comment-parsing error on the baseline and candidate. The fix passed all five media tests locally (#1533). #1580 isolates CLI writes and QMK fetch fixtures and fixes the navigation-layer snapshot setup. Device-selection writes now use their own configuration directory (#1585). At overlay candidate `f51656e5`, 83 scoped CLI, device-selection and rule-write cases passed with two XCTest worker processes, with zero failures or skips in the XML report. Seven Swift Testing rule-mutation checks also passed five repetitions in one process. A November 21 audit found one test mutating `UserDefaults.standard`; it now uses its per-test isolated suite. A follow-up source search found no direct `UserDefaults.standard` references under `Tests/KeyPathTests`; generated temporary paths in the sampled writes use UUIDs. Implicit preference defaults now fall back to a process-local test-only domain, and the focused preference suite passes. The current isolation pass injects notification centers into preference, reload, and collection managers; removes host-Keychain/environment-dependent smoke assertions; and changes the QMK search tests to use a fresh database/cache path per test. Focused coordinator (36), persistence, recovery, notification (10), parallel QMK (33), session-start permission-snapshot tests, and the Vallack/runtime mutation tests pass. The lifecycle permission invalidation test now uses its own `PermissionOracle` and injects only the invalidation action into its coordinator; the snapshot unit tests also use local oracles, and a vacuous host Accessibility-permission smoke test was removed. The `AppPaths` sandbox follow-up passed six focused tests. On November 21, the full safe suite passed sequentially (4,744 XCTest invocations + 844 Swift Testing checks) and again with two XCTest workers (4,745 + 844), with zero failures or skips and zero Swift or app warnings/errors. A Swift Testing-only run with `--maximum-repetitions 3` also exited 0 in the safe runner; the log records 842 cases reaching repetitions 2 and 3, and the runner counted 744 passes with zero failures or warnings/errors. These qualify process parallelism and repeated Swift Testing execution. Remaining: SwiftPM's repetition option repeats Swift Testing cases but not XCTest cases in-process. CI intentionally runs one full-test job at a time on the shared host, while each job uses two XCTest workers; parallel jobs would compete for the runner's shared SwiftPM scratch and memory.

P9 follow-up details (November 21): `UnitTestSuite.testLoggerConfiguration` now uses a private logger, waits for its queued log-level change, writes to a UUID temporary directory, flushes it, and removes only that directory. The former `testSoundManagerSharedInstance` was removed because XCTest suppresses sound and the test's only observable effect was writing through `AppLogger.shared`. The focused suite passed all 8 tests with parallel XCTest workers. The full safe suite then passed 5,545 tests with 26 skips and no failures, warnings, or errors (525 seconds, including a cold test build). This closes those shared-logger writes in `UnitTestSuite`; the repository-wide P9 audit and final two-worker qualification documented below close the remaining isolation work. The initial full run also demonstrated why the explicit flush matters: without waiting for the asynchronous level update, the logger assertion could race under CI's warning-level environment. The runner's normal 240-second limit expired during snapshots, so the successful qualification used a 600-second test budget.

P9 follow-up (November 21, PR #1613): `KeyPathTestCase` no longer calls a test-wide setup hook that changed `AppLogger.shared` before and after every case. The now-unused `GlobalTestSetup.swift` was removed. New logger instances choose quiet console output from the test environment at construction, while explicit instance configuration still takes precedence; focused tests cover quiet and verbose test runs plus debug and release defaults. The Utilities tests pass in parallel (19 tests), the logger-configuration test passes independently, and the merged-branch full safe suite reports 5,490 passes with no failures or Swift, module-cache, app warnings or errors (276 seconds). The review gate selected the remote route, so GitHub `claude-review` remains required before merge. This removes another process-global test mutation; the subsequent repository-wide fixture audit and two-worker qualification below close P9. SwiftPM's lack of same-process XCTest repetition remains a tool limitation, not an open defect.

P9 follow-up (November 21): `RuntimeCoordinator` now accepts its Settings-tab opener as a dependency. The two prerequisite-resolution tests assert the requested tab through a private closure rather than clearing `SettingsNavigationCoordinator.shared` during teardown, so parallel cases cannot consume or erase each other's pending navigation. All seven `KanataViewModelTests` pass sequentially and with two XCTest workers. The later shared-fixture audit below completed the remaining P9 work.

P9 follow-up (November 21): `RuleCollectionsManagerDependentResolutionTests` now injects a per-test defaults suite, installed-pack tracker, temporary stores, and the test session bridge. This removes shared-preference/tracker state and prevents environment-specific fallback to an installed Xcode bridge. `RuleCollectionStoreTests` and `KindaVimStateAdapterTests` now remove their UUID temporary directories during teardown. The affected three suites pass together (25 tests, 0 failures); the alternate-provider test also passes alone through the safe runner. Direct `swift test` without the safe runner initially failed because this worktree has no installed bridge at `/Applications/Xcode.app/Contents/Library/KeyPath/`; the safe runner built and selected the worktree bridge as intended. The later repository-wide audit and full two-worker run close P9; same-process XCTest repetition is unavailable in SwiftPM.

P9 follow-up (November 21): The pure collection API and conflict-detection suites no longer construct managers with `.shared` stores or a production `ConfigurationService`. Each case gets its own config directory, stores, tracker, defaults suite and notification center, with the test session bridge. All 30 affected XCTest cases pass with two workers; no Swift, module-cache, or app warnings/errors were emitted. The later audit below closes P9.

P9 follow-up (November 21): A shared `RuleCollectionsManagerTestFixture` now gives the four remaining rule-collection suites that constructed managers with process-wide stores their own temporary config, file-backed stores, defaults suite, installed-pack tracker and notification center. The conflict, prerequisite, toggle-parity and verdict-presenter suites passed all 53 XCTest cases with two workers; no Swift, module-cache, or app warnings/errors were emitted. The remaining audit found the other direct `AppLogger.shared`, `UserDefaults.standard`, and preference-singleton references are source-pattern assertions, sandbox safety checks, singleton identity checks, or read-only path guards; no additional test-side mutation was identified in that pass. Same-process XCTest repetition is still unsupported by SwiftPM, so process-parallel full-suite qualification remains the available XCTest isolation check.

The full safe suite on this branch passed again with two XCTest workers after the Settings-navigation isolation fix (November 21): 4,729 XCTest invocations and 847 Swift Testing cases passed; zero failures and no Swift, module-cache, or app warnings/errors (372 seconds total, including a 70-second build). This qualifies full-suite worker-process concurrency. SwiftPM's built-in repetition covers Swift Testing but not XCTest; this tooling limit does not leave P9 open. Comparing worker counts and overlapping full CI jobs is a separate performance qualification.

P2's normal usage prompt passed on a fresh macOS 27 guest. B7's current permission
screenshot is published at gh-pages `99a2200b6`: the public guide returned HTTP
200 with the new caption, and the downloaded PNG hash matched the verified
capture. Final host deployment and release qualification are separate gates.

---

## Summary

The core is in good shape. The session runtime, the journaled config write, the
permission oracle and the signing posture are careful work, and the retired
privileged stack is almost entirely gone from `Sources`. The language-level
modernisation is done: Swift 6 mode on every target, full `@Observable`
migration, no dead availability checks.

The problems are around the core:

- **Security.** The engine's control port is unauthenticated (already tracked
  as #1354 / ADR-046). Other unfixed findings are tracked privately and are
  not described here.
- **Over-engineering.** The installer's plan/recipe/state-matrix machinery now
  encodes a single `if`. UI state is copied through four layers by hand.
- **Bloat.** About 34,000 lines of scripts, docs, tests and dead Swift can be
  deleted with low risk, plus about 30 MB of binary assets, 15 MB of which
  ships inside the app for a view that is never shown.
- **Public docs were wrong.** `PRIVACY.md`, `SECURITY.md`, `CONTRIBUTING.md` and
  `getting-started/installation.md` described Input Monitoring, Full Disk
  Access and the privileged helper as current. They are corrected in the same
  change as this review, but the published website (`gh-pages`) still carries
  the old pages; see B7.

## Top recommendations

| # | Recommendation | Area | Effort | Why now |
|---|---|---|---|---|
| 1 | Land ADR-046, together with the privately tracked security fixes | Security | L | Any local process can read keystrokes and inject input |
| 2 | Rewrite `PRIVACY.md`, `SECURITY.md`, `CONTRIBUTING.md`, `getting-started/installation.md` | Docs | S | Public, and contradicted the shipped product; master is fixed, the website is not |
| 3 | Delete the dead `BehaviorStatePicker` view and its 15 MB of bundled PNGs | Bloat | S | Shrinks the shipped app |
| 4 | Deletion pass: `Scripts/archive`, `Scripts/test-scripts`, dead Swift, dead tests, `docs/archive` | Bloat | S | ~34k lines, low risk, makes everything after it easier |
| 5 | Decide the update story: re-enable Sparkle or add a version check | Platform | M | The app ships Sparkle but never checks for updates |
| 6 | Collapse `InstallerEngine` planning to inspect / start-and-verify / uninstall | Over-eng. | M | Scaffolding for a stack that no longer exists |
| 7 | Add `NSAppleEventsUsageDescription` | Platform | S | AppleScript actions may be silently denied (*unconfirmed*) |

---

## 1. Security

Threat model: another process running as the same user without Accessibility;
a web page or document invoking `keypath://`; a malicious config or import;
the update and build supply chain; leakage of typed text.

Some exposure is inherent to any remapper: an unsandboxed process that holds
Accessibility and sees every key, and a user-editable config that defines
macros. The findings below are the parts that can be fixed.

### S1. Engine control port has no authentication — High (tracked: #1354, ADR-046)

> **Since this review:** ADR-046 is Accepted and phases 1–3 have shipped. The TCP port is gone; see Status above. The text below describes the code as reviewed.

`127.0.0.1:37001` is fixed and unauthenticated. The code's own comment at
`Sources/KeyPathAppKit/Services/Networking/KanataTCPClient.swift:59-71` says
any local process, including other users' processes and sandboxed apps with
network-client, can receive every `KeyInput` event and the config text, press
virtual keys, move the mouse and load any readable file as the config.

ADR-046 describes the attack scenarios. One documentation item to add: correct
`docs/adr/adr-013` and any user-facing text that says the port only handles
config reloads.

**Fix:** ADR-046 options C and A together. This should block the first
session-runtime release.

### Further findings, reported privately

Other security findings from this review are not described in this public
document, following [`SECURITY.md`](../../SECURITY.md). They are tracked
privately and will be published once fixed. Plan the ADR-046 change with
them in view.

### Already done well

- The engine is built without kanata's `cmd` feature, so no config can run
  shell commands in the engine.
- Hardened runtime on every component with **no** exception entitlements.
- Sparkle feed is HTTPS, EdDSA-signed, verified before extraction.
- The worker refuses to run as root and exits on Secure Input.
- Insights data is AES-GCM encrypted with a Keychain key; the Anthropic API
  key is in the Keychain.
- No analytics or crash-reporting SDK. No TCC database access. No secrets in
  the repository.
- `Package.resolved` and `Cargo.lock` are committed.
- ADR-046 is itself a candid and largely correct threat model.

---

## 2. Over-engineering

### O1. The installer planner encodes one `if`

`InstallerEngine.swift` (762 lines), `InstallerEngineTypes.swift` (500),
`InstallerStateMatrix.swift`, `InstallerDecisionPipeline.swift` and
`InstallerEngine+Recipes.swift` were built to order helper, daemon and driver
steps. What is left:

- `AutoFixAction` has two cases (`WizardTypes.swift:153-158`); one is never
  planned.
- Install and repair both reduce to `isReady ? [] : [.restartCommServer]`.
- The state matrix has two rows and one action.
- `orderRecipes` returns its input. `actionNeedsPrompt` and
  `requiresManualApproval` return `false`. Two report states are unreachable.

Net behaviour of repair: if the runtime is not ready, start it and re-check.

**Recommendation:** collapse to `inspect()`, `startAndVerify()` and
`uninstall()`. Keep the transaction gate and the fresh re-capture before
reporting success; those are the valuable parts. Keep the CLI's JSON field
names stable. About 4.5k lines of tests pin the current shapes, so this is a
deliberate PR, in the spirit of the ADR-047 exception.

### O2. One UI state, four copies

`RuleCollectionsManager` owns the state. `RuntimeCoordinator` mirrors it,
builds a `KanataUIState` snapshot, `StatePublisherService` pushes it down a
single-subscriber `AsyncStream`, and `KanataViewModel.updateUI` copies about
20 fields. There are 69 manual `notifyStateChanged()` calls. Of
`KanataViewModel`'s 47 methods, 33 are one-line forwards, and the
`underlyingManager` escape hatch is used 65 times, so the layer isolates
nothing. `MainAppStateController` holds a third copy of health state.

The codebase already uses `@Observable` in 59 places.

**Recommendation:** make the owner observable, delete `KanataUIState` and
`StatePublisherService`, shrink `KanataViewModel` to dialog and toast state.
`AGENTS.md` says `RuntimeCoordinator` is "not an `ObservableObject`"; revisit
that line. Large, medium risk.

### O3. Forwarding layers on the rule path

Toggling a rule passes through about 15 calls. `RuleCollectionsCoordinator`
(274 lines) and `RuntimeCoordinator+RuleCollections` (170) only log and
forward. The reload result is re-wrapped five times
(`TCPReloadResult → EngineReloadResult → TCPReloadResult → ReloadResult →
SaveResult → Bool`). `ConfigReloadCoordinator` takes 20 injected closures and
has three parallel test seams for one reload call.

**Recommendation:** delete the two forwarding files (falls out of O2; ADR-043
sanctions it). In `ConfigReloadCoordinator`, drop `EngineClient` (one
conformer) and keep one seam. Leave its Caps restart logic alone.

### O4. The wizard module boundary

The wizard was split out for incremental compilation. The cost is
`WizardDependencies`, a static container of ten mutable globals, five
protocols that exist only to cross the boundary, and a `WizardRuntimeStatus`
that copies `RuntimeStatus` case for case. Three wizard pages still live in
AppKit. The wizard now has two real steps across about 10.7k lines.

**Recommendation:** after O1, either fold the wizard back into AppKit or keep
the module for views only.

### O5. Events and health: untyped bus, polling, stacked caches

- Kanata events arrive typed, are repacked as `[String: Any]`, posted through
  `NotificationCenter` per keystroke, and parsed again by observers
  (`RuleCollectionsManager+EventMonitoring.swift`). The rule-storage manager
  owns the TCP listener. There are about 80 notification names in total.
- `MainAppStateController.subscribeToServiceHealth` (`:214`) polls every two
  seconds although `ServiceLifecycleCoordinator.onStateChanged` exists.
- A permission answer passes three cache-and-dedup layers (Oracle, validator,
  state controller). The validator's snapshot is about 20 lines of work
  wrapped in a TTL cache and a 90-line timeout race.
- Four separate timeout helpers with four error types.

**Recommendation:** a small typed event hub owned by the lifecycle side; drive
revalidation from `onStateChanged`; keep only the Oracle's cache; one timeout
helper in `KeyPathCore`.

### O6. Plugin system for one first-party plugin

`PluginManager` (469 lines), a downloader, a catalog card, an `@objc` protocol
and a dynamic-library product exist to load `KeyPathInsights` (1,792 lines).
Loading downloaded code is also a trust surface.

**Recommendation:** compile Insights in behind a preference, or ship it only
inside the app bundle and drop the downloader. Product decision.

### O7. Footprint worth a product decision

| Feature | Size | Note |
|---|---|---|
| Metal keyboard stage | 6,022 lines Swift + 1,190-line shader + build plugin | Keep the full Metal experience. Review shared scene state and fallback behavior for duplication, and verify visual and interaction parity before changing the implementation. |
| First-success onboarding | 3,549 lines | Preserve the complete first-run flow when simplifying its implementation. |
| Packs | ~8,000 lines (services, gallery, facade) | Owner decision (November 19): retain the gallery, installation and dependency features. Keep their behavior while removing proven unused surrounding code. |
| `keypath-cli` | imports AppKit in 57 files | Links SwiftUI and the Metal renderer. A `KeyPathEngine` target (config, rules, session runtime, networking) would be the split that pays |

The Karabiner converter, QMK import and layout tracer are proportionate.

#### CLI compile-boundary evaluation

At master `4ee44aa72`, 54 Swift files under `Sources/KeyPathCLI` import
`KeyPathAppKit`. SwiftPM already separates help and command presentation
into `KeyPathCLIHelp` and `KeyPathCLICommon`. The executable still depends
on the app library through `KeyPathCLI`. On a local Debug build containing
the scoped routing change, `otool -L` listed AppKit, SwiftUI, Metal,
MetalKit, and Sparkle. This shows the link boundary. It does not measure
release binary size, launch time, or incremental build savings.

A follow-up measured the signed arm64 release candidate at `945753e3` on the
Air. The installed-layout CLI executable was 63,032,528 bytes and directly
linked AppKit, SwiftUI, WebKit, Metal, MetalKit, and Sparkle. The first
`--help` invocation took 1,292 ms, and the median of five immediately repeated
invocations was 18.6 ms. These are comparison measurements from one build and
one machine. The first sample may include operating-system work on the new
binary, and the run did not measure incremental compilation.

The Air Debug comparison at master `7e781f8f` used Xcode 27.2 (27B52),
four build jobs and separate SwiftPM scratch directories. Package resolution
completed before timing. These are individual wall-clock samples.

| Build target | Clean | Warm, no changes | Warm, CLI source edit |
|---|---:|---:|---:|
| Complete `keypath-cli` product | 114.48 s | 2.52 s | 2.97 s |
| Existing `KeyPathCLIHelp` target | 22.84 s | 2.76 s | — |

The edit was a comment in the CLI config-path command, reverted after timing.
Those measurements predate the Core extractions listed in the current status.
The current CLI source scan finds three direct `KeyPathAppKit` imports, in
pack install/configure/uninstall. The full Debug executable still directly
links AppKit, SwiftUI, Metal, MetalKit, Sparkle, and WebKit. The help target shows what a much smaller
dependency graph costs to build. A future split needs to demonstrate which
of the difference it can recover while keeping the full command surface.

Keep the existing commands and pack features. A new umbrella engine target
would still pull in app code if it carried the current facades wholesale.
`ConfigFacade` combines generation, transactional writes, and runtime
routing. `PacksFacade` reaches the pack installer, which still presents some
decisions through AppKit alerts. CLI setup and runtime activation also have
legitimate AppKit calls of their own.

Start with read-only config and rule operations that can use the existing
Core targets. Keep consent, UI presentation, and live session control at
their existing boundaries. Extract pack mutations only after the app and CLI
can supply explicit decisions to a shared transaction. Before moving a
target, compare clean and incremental CLI-only builds on the same machine
and toolchain, and inspect the resulting release binary's dependencies.
Verify CLI output and exit codes, dry-run behavior, and rollback and
dependency handling before replacing the existing path.

### O8. Smaller items

- Nothing guards the public docs against drifting back to the retired
  stack. A lint that fails when `README.md`, `PRIVACY.md`, `guides/`,
  `getting-started/` or `docs.md` describe Input Monitoring, Full Disk
  Access, a privileged helper or a LaunchDaemon as current would be cheap.
- Uninstall leaves the root-owned `/usr/local/bin/keypath-cli` link behind;
  `SessionUninstallCoordinator` never references it. The docs now say so;
  the cleaner fix is to install the link somewhere user-writable.

- Two feature flags marked "NOT YET IMPLEMENTED"
  (`FeatureFlags.swift:223-242`) are consulted in three places; `PermissionGate`
  exists only behind one. Delete.
- `TestEnvironment.*` is checked in production code 56 times.
- 90 `static let shared` singletons coexist with a half-adopted
  `ServiceContainer`. Pick one.
- User-visible strings still say "Restart Service with Authentication";
  `restartCommServer` means "start the session runtime".
- 36 source-grepping lint tests (3,394 lines). Several guard the retired
  stack or are finished migration ratchets (`W6DeletionPassLintTests`). They
  pin file paths and make every cleanup above noisier. Retire the finished
  ones.

### Leave alone

- `RecoverableRuleWrite` and `ConfigurationOperationGate`: a journaled
  multi-file write with a cross-process lock. Earned, because the CLI is a
  second writer.
- The session runtime worker, lifecycle and `SessionCaps*`. Dense, but each
  piece answers a specific incident or OS limit.
- `PermissionOracle`.
- `KeyPathRulesCore` and the pure decision functions (`WizardRouter`,
  `SystemInspector`).
- `release-doctor`, `verify-installed-app`, `review-gate`.

---

## 3. Bloat

Verified deletable: about 34,000 lines of text and 30 MB of binaries.
Suspected on top: about 30,000 lines, and 45–50 MB from recompressing images.

### B1. Dead view with 15 MB of bundled images

`BehaviorStatePicker` and its cell views
(`Sources/KeyPathAppKit/UI/Overlay/BehaviorStatePicker.swift`, 413 lines) are
never instantiated. They are the only loader for
`Resources/BehaviorIcons/`: twelve 2048×2048 PNGs, 15 MB, shipped in the app.
Keep `enum BehaviorSlot`, delete the rest. Its `imageName` and
`selectedImageName` properties live in the same file and name the PNGs, so
drop them with the assets.

### B2. Scripts

`Scripts/` holds 293 tracked files.

| What | Size | Status |
|---|---|---|
| `Scripts/archive/` | 57 files, 4,584 lines | Retired-stack; nothing references it |
| `Scripts/test-scripts/`, `test-fixtures/` | 51 files, ~2,900 lines | Scratch files; check one fixture used by `build-kanata-host-bridge.sh` |
| Keyboard image slicing one-offs | 13 Python files, ~2,450 lines | Five generations of the same script |
| `Scripts/ui-tests/` | 19 files, 2,595 lines | Peekaboo suites nothing invokes |
| Other unreferenced scripts | ~1,500 lines clear, ~3,500 docs-only | `test-installer.sh` and `test-hot-reload.sh` test the LaunchDaemon |

The `qa-*-smoke.sh` scripts may be manual release tools; confirm before
deleting.

### B3. Dead Swift

About 3,900 lines of views and files with no references, including
`AboutView.swift` (638; the menu uses the standard About panel),
`WindowResizeHandle.swift` (372), `ActiveRulesView.swift` (363),
`AIKeyRequiredDialog.swift` (348), `KeyPathCLI/Utilities/UpdateChecker.swift`
(no callers) and `KanataBehaviorParser.swift` (255,
tests only). Also, with zero production callers:

- `StartupCoordinator` (never started)
- `EventRouter`, `DefaultEventProcessor`, `EventProcessing` (~570 lines;
  `setEventRouter` is only ever passed `nil`)
- most of `ServiceHealthMonitor` (495 lines; restart cooldown and crash-loop
  logic kept alive by a 419-line test file)
- the `launchctl` probe chain in `KeyPathSystemProbes` and `SystemStateProvider`
- about 20 VirtualHID and legacy-path members of `WizardSystemPaths.swift`
- nine notification names with no post and no observer

A name-based scan suggests another 1,500–2,500 lines at function level.
Run Periphery for that layer rather than trusting grep.

### B4. Tests for removed behaviour

About 1,300 lines verified: tests for `ServiceHealthMonitor`'s dead paths,
`KanataBehaviorParser`, `TransientStartupWindowEvaluator`,
`SafetyTimeoutService`, `WordlistStore`, `WizardTelemetry`. Also:

- `Tests/Experiments/` (899 lines) is in no package target.
- Six `*.actual.kbd` files are committed test output; add to `.gitignore`.
- Three snapshot references have no matching test; two are byte-identical.

### B5. Binary assets

| What | Size | Action |
|---|---|---|
| `images/help/` | 60 MB | Headers are 1–7 MB PNGs; recompress. 36 files (7.5 MB) are byte-duplicated in `Sources/…/Resources`; copy at build time. 12 are unreferenced |
| `dev-tools/dmg/` | 16 MB | ~12 MB are rejected design iterations |
| Snapshot references | 19 MB | Five Metal frames account for 8.6 MB; render at lower scale |
| `Resources/BehaviorIcons` | 15 MB | Delete (B1) |

One 153 KB screenshot is committed six times under three names; the wrong
image was probably copied over three slots.

### B6. Root and package stragglers

- Delete: `test.sh`, root `build-and-sign.sh` shim, `default.profraw`,
  `.watchman-cookie-…`, `design-qa.md`, `ScrollTest/`,
  `External/.github`, `External/.devcontainer`.
- `KeyPathSystemProbes` (one file, one importer): fold into `KeyPathCore`.
- Nine library products nothing outside the package consumes (*unconfirmed*
  that no build script names them).
- The wizard target's only resource is an unreferenced Karabiner driver
  screenshot.

### B7. Docs

`docs/` is 418 files and about 61,600 lines. Roughly 55–65% is historical
record (an estimate from directory purpose, not a file-by-file read):
`archive` (13k lines), `bugs`, `planning`, `analysis`, `code-review`, half of
`testing`.

**Wrong and public — fixed on master in the same change as this review:**

- `PRIVACY.md:20,38` says Input Monitoring is required and asks for Full Disk
  Access. `guides/privacy.md` says the opposite.
- `SECURITY.md:41` says KeyPath "includes privileged helper and LaunchDaemon
  flows".
- `CONTRIBUTING.md:101` says Kanata starts as a LaunchDaemon.
- `getting-started/installation.md:50` documents "Step 1: Privileged Helper
  Installation" and asks for an admin password.
- `migration/karabiner-users.md` said KeyPath uses the Karabiner VirtualHID
  driver; `migration/kanata-users.md` said setup asks for Input Monitoring,
  installs that driver and configures a LaunchDaemon.
- `README.md` said "No kernel extensions — uses Apple's modern driver
  framework" and "works completely offline".

**The website still shows the old pages.** The site is served from the
`gh-pages` branch, which keeps its own copies. There,
`getting-started/installation.md` and `guides/privacy.md` still describe the
privileged helper, Input Monitoring and Full Disk Access, although master's
`guides/privacy.md` is already correct. `Scripts/publish-guides.sh` publishes
only `guides/`, `docs.md`, `images/help/` and `offline-help/`, so
`getting-started/` and `migration/` have no publishing path at all. Run the publish script, and
either extend it to `getting-started/` and `migration/` or stop keeping a master copy that
cannot be published.

**Stale developer docs:** `docs/architecture/xpc-architecture.html`,
`runtime-architecture.html`, `docs/troubleshooting/debugging-kanata.md`,
`docs/guides/kanata-macos-setup-guide.md`,
`docs/process/new-developer-guide.md`, `docs/KEYPATH_GUIDE.adoc`.

`AGENTS.md`, `CONTRIBUTING.md`, `.swiftlint.yml` and
`docs/testing/accessibility-enforcement.md` cited
`ACCESSIBILITY_COVERAGE.md`, which was archived earlier (0e8d6c59); the
citations are removed in this change. `AGENTS.md` still names
`KEYPATH_USE_INSTALLER_ENGINE`, which looks vestigial.

`docs.md`, which is published, linked "Privileged Helper & XPC"
(`xpc-architecture.html`); the link is removed in this change. The
"Runtime & Service Lifecycle" page it also links is stale and needs a
rewrite.

**Recommendation:** delete `docs/archive`; git history is the archive. Stop
committing generated dashboards.

---

## 4. macOS best practices

Platform guidance below is from general knowledge of current Apple practice
and was not checked against the macOS 27 SDK. Nothing was compiled, so
deprecation-warning counts are not measured; a `swift build` would turn
several of these from recalled to confirmed.

### Already current

- Swift 6 language mode on every target, tests included.
- Observation fully migrated: 59 `@Observable`, zero `ObservableObject` or
  `@Published`.
- Zero `#available` checks; no `NavigationView`, no old alert APIs.
- Launch at login through `SMAppService.mainApp` behind an off-main provider.
- App Intents, `UNUserNotificationCenter`, `NSWorkspace.OpenConfiguration`.
- Hardened runtime, no exceptions; private CGS symbols bound by `dlsym` with a
  fallback.
- Accessibility identifiers: `check-accessibility.py` passes on 381 files.
- The AppKit window management for overlay, HUD and palette panels is
  justified; SwiftUI scenes do not express non-activating multi-Space panels.

### P1. Sparkle is configured as automatic and disabled in code — do now

`Info.plist` sets `SUEnableAutomaticChecks` and `SUAutomaticallyUpdate`.
`UpdateService.usesManualDownloads`
(`Sources/KeyPathAppKit/Services/UpdateService.swift:93`) is hardcoded `true`,
so the updater is never constructed and "check for updates" opens the GitHub
releases page. The app embeds and signs Sparkle but has no update check. For
software that sees every keystroke, users not learning about a security fix
is a real cost.

**Recommendation:** finish qualifying updater shutdown and re-enable Sparkle,
or add a lightweight "new version available" notice. Host the appcast on
Pages or Releases, not a raw branch file.

### P2. Apple Events entitlement with no usage string — do now

`KeyPath.entitlements` declares `automation.apple-events`. The only usage
string in `Info.plist` is `NSAccessibilityUsageDescription`, which macOS does
not read. Apple Events are sent from `ActionDispatcher.swift:855,875,959` and
`WizardWindowManager.swift:69,106`. Without `NSAppleEventsUsageDescription`
the consent prompt may not appear and sends are denied (*unconfirmed*; test on
a clean VM). The wizard's "quit System Settings" could use
`NSRunningApplication.terminate()` and need no consent.

### P3. Blocking subprocesses on the main actor — do now for the launch path

- `WizardSignatureHealthCheck.isRunningAdHoc()`
  (`KeyPathWizardCore/WizardServiceProtocols.swift:103-113`) runs
  `codesign -dvvv` synchronously at launch. Use `SecCodeCopySelf` and
  `SecCodeCopySigningInformation`.
- `detectRunningKanataProcess()` runs `ps` synchronously; the repo already
  reads the process table directly in `SessionWorkerSweep.swift:138`.
- `ExternalKanataService.swift:148-159` waits for exit before reading the
  pipes, which can deadlock on large output.

### P4. Other shell-outs with direct API replacements

`mdfind` → `NSMetadataQuery`; `defaults` → `UserDefaults(suiteName:)`;
`chflags` → `URLResourceValues.isHidden`; `open -t` → `NSWorkspace`;
`/bin/kill` → `kill(2)`. `hidutil`, `tccutil` and `ditto` have no good
replacement; keep. `ExternalKanataService` still calls `launchctl unload`,
which contradicts the `AGENTS.md` rule; either note the exception there or
move to `bootout`.

### P5. Logging is a custom file logger only

1,824 `AppLogger` calls, one `os.Logger`. The file log is useful for user
diagnostics and QA scripts. Make `AppLogger` also emit to `os.Logger` with a
subsystem and category; no call sites change. That gives Console filtering
and, later, privacy annotations for anything that could reveal typed keys.

### P6. Concurrency leftovers

Verified follow-up, November 19: `RuntimeCoordinator`, `SystemValidator`, and
`PermissionRequestService` now use checked main-actor isolation (#1481).
`FeatureFlags` is checked `Sendable` with mutex-protected startup and override
state. `AppIconResolver` is main-actor isolated, including its static icon cache.
The original examples of unsynchronised caches below are therefore resolved;
they must not be counted as outstanding defects.

Remaining work:

- The remaining `@unchecked Sendable` declarations were audited against their
  use sites on November 21. Locked state protects the event-tap and HID
  monitor sessions, process-output capture, notification observer storage,
  session termination/shutdown guards, Metal renderer state, and atlas cache.
  The other declarations are narrow framework/C interop boundaries: immutable
  Metal snapshots and callback wrappers, `SMAppService` calls sent to a
  detached task, the main-actor Sparkle continuation wrapper, main-actor SwiftUI
  popover preference values, and the session worker's opaque C runtime handle.
  Their Sendable escape hatches remain intentional; do not replace a valid
  actor or framework boundary with a mutex merely to reduce the count. Revisit
  if the owner or call sites change.
- `BackendCapabilityProfile` uses checked mutex-backed state after #1487.
  Its full gate passed 5,525 tests and six post-integration regressions passed.
  BuildInfo now protects its once-only fetch reservation and cached version with
  checked mutex state; no lock is held across asynchronous process execution.
- Done November 22: delayed UI callbacks and timers were reconciled with their
  owning view or window. The audit covered `DispatchQueue.main.asyncAfter`,
  `Timer`, `Task.sleep` followed by UI work, `perform(_:afterDelay:)` (none),
  NotificationCenter and `NSEvent` monitors, and AppKit animation completions
  under `Sources/`. One owner could act on stale state: the drag-to-authorize
  overlay (`DragToAuthorizeController`), a singleton, so `[weak self]` never
  released its work. Dismissing before the panel was due still created the
  panel, polling and Settings tracker on an idle controller, which a later
  `dismiss` then ignored. Presenting again during the animated fade let the old
  teardown remove the new panel, and an entrance animation finishing after a
  dismissal set the overlay back to `.visible`. Its panel creation, fade-out
  teardown, present retry, retry reset, success dismissal, entrance-animation
  completion and permission-poll result now carry the presentation generation
  that scheduled them and do nothing once it is dismissed or replaced. Seven
  owner-close tests use a manual scheduler. Callbacks left alone are safe for
  one of these reasons: they only write a SwiftUI view's own `@State`, which is
  discarded with the view; they post a notification that has no effect without
  a listener; they are already cancelled or token-checked by their owner
  (mapper, inspector, layer reveal, wizard resize, hint windows, overlay
  timers); or their owner is a service that outlives the UI.
- On November 20, Apple Swift 6.4.2 compiled the Layout Tracer module with
  both isolation settings, targeting macOS 27.0. Four existing downstream
  Swift Testing files type-checked with the current setting. Default
  main-actor isolation made synchronous document import and result access
  actor-isolated, and those callers failed to type-check. Keep explicit
  isolation at UI boundaries until the pure layout and file APIs can stay
  nonisolated.
- Live verification is done. On November 22 a disposable macOS 27 desktop
  guest (daily lease `cbx_400b4b88a423`) ran signed master
  `94c963364838a9da005a1e50f0e446d1641d1d5a`. Overlay hide/show timing passed
  8 of 8: `keypath://overlay/hide` and `show` were sent in one guest shell with
  gaps of 0.05, 0.15, 0.30 and 1.00 s, in both orders, and each time the overlay
  window ended in the last requested state and stayed there across three
  samples about 1.5 s apart. Capture teardown passed on `7b6c369e`
  (November 20): no event tap at idle, one enabled tap while the mapper
  recorded, none after the overlay hid, and none after it reopened. Between
  `7b6c369e` and `94c96336` the capture and mapper code changed only in one
  localized key name. Capture teardown was not re-run on the `94c96336` guest,
  because no UI click tool was available there. Earlier attempts on
  November 21 did not reach a guest (occupied Parallels slots, a Rust helper
  codesigning failure, and a Tart clone timestamp error).

### P7. SwiftUI and AppKit idioms

The main glass surface uses system glass (#1408), and the deprecated image
drawing was replaced (#1460). The source scan found no assignment to
`Process.launchPath`. Cooperative activation merged in #1508. On a macOS
27.2.1 guest, the signed candidate showed both external confirmation prompts
above Terminal. The uninstall prompt closed on disconnect, the hidden
launcher overlay reopened, and the virtual remap worked after restarting.

| Surface | Current behavior and decision |
|---|---|
| Help | Keep the controller. It restores the overlay on close only when it was previously visible by choice, and it can position Help beside an overlay that stays visible. A scene migration needs to preserve both paths and help-topic selection. |
| Simulator | This is the simplest candidate for a scene. Its controller keeps the simulator alive across close and reopen, restores the saved frame, and opens from Settings. A conversion should preserve those behaviors and show a clear reduction in lifecycle code. |
| Recent Keypresses | Keep the floating AppKit window with all-Spaces and full-screen auxiliary behavior. Verify both Spaces behaviors before considering a scene conversion. |
| About | Keep the platform's standard About panel, which already supports the build information KeyPath displays. |

SwiftUI provides singleton [Window scenes](https://developer.apple.com/documentation/swiftui/window)
and controls for [window interactions](https://developer.apple.com/documentation/swiftui/windowinteractionbehavior).
KeyPath's main window and overlay are AppKit-owned, and its SwiftUI app declares
a Settings scene. Evaluate scene changes through the actual menu, overlay and
Settings entry points.

Of the 14 AppKit view and view-controller bridges inspected in KeyPathAppKit,
the private icon segmented control had no callers and was removed. Function
Keys already uses SwiftUI settings cards. The remaining bridges serve these
roles:

- The keyboard stage uses an MTKView and two probes for native first-frame
  evidence and window coordinate mapping. Retain the Metal onboarding path.
- Web Help owns WKWebView navigation and its offline content store.
- The overlay uses a hosted inspector mask, first-click window dragging,
  mouse and scroll activity tracking, and first-responder focus for the
  separate popover host. A SwiftUI replacement needs to preserve those
  behaviors. Hover entry and exit alone would miss scroll activity.
- The integer and search fields supply AppKit editing behavior. The integer
  field also handles accessibility value updates. The remaining visual-effects
  bridge and onboarding window-background bridge control window materials
  and colors outside the reusable glass background.
- The plugin settings card hosts the view controller supplied by a plugin.

The source scan found 660 `foregroundColor` uses and 855 `foregroundStyle`
uses. Convert these during surface work and compare snapshots in light and
dark appearances. A bulk rewrite across these views solely to reduce the count
would make regressions harder to isolate.

### P8. Localization needs a decision

One String Catalog (433 keys, English and Japanese) against 764 literal
`Text("…")` call sites, and no catalog in the wizard, Insights or tracer
targets. With SwiftPM there is no extraction step, so the catalog drifts.
Either commit to localization (add a lint for literals and bundle routing) or
stop carrying partial Japanese.

### P9. Tests — original finding, now closed

At the original review, 4,651 XCTest methods and 851 Swift Testing tests shared
on-disk state; that was the reason to serialize CI and the risk to address before
raising test parallelism. The follow-up work above isolates the mutable fixtures
identified in the audit and passed the full safe suite with two XCTest workers.
SwiftPM still cannot repeat XCTest cases in one process, but that tooling limit
is not an open defect. Keep adding per-test temporary paths, defaults suites,
stores and injected dependencies to new tests; do not mass-convert existing
XCTest tests solely for framework consistency.

---

## Suggested order

The original implementation order above is superseded. The remaining tracked
work is verification, plus private security follow-up:

1. Complete B7's manual 1.0.1 cleanup rehearsal on a fresh macOS 26 guest,
   preserving and checking the user's rules and verifying no legacy services
   return after reboot. Setting up 1.0.1 needs a person at the guest for the
   administrator password and the driver-extension and background-item
   approvals; the lab's consent tool grants only Accessibility.
2. On release day, merge the homepage requirements change (#1627) with the
   release; `release.sh` updates the download link and button text.
3. Retrieve the private security tracker, then close its remaining remediation
   and release-qualification items without copying those findings into this
   public review.

## Verification notes

- Permission artwork was recaptured on November 20 from a fresh macOS 27 lab
  guest, with KeyPath enabled under Device Control and Data Access. The guide
  identifies the unrelated lab tools visible in the screenshot. Publication to
  gh-pages completed at 99a2200b6; public page and exact image hash verified.
- P2's usage-string prompt was verified on a fresh macOS 27 guest on November
  20; evidence is retained on the Mini under `~/keypath-final-ui-qa.XIYk30` and
  the guest artifact capture `20261120T051303Z`.
- November 22 Mini lab check: the installed launcher reports the prepared
  checkout at `e96593e` with no dirty files. The owned macOS 26.5.2 lease
  `cbx_67d82d322f17` remains `ready`, with cleanup pending; KeyPath 1.0.1 is
  installed and the base fingerprint check passes. At 11:38 UTC, the
  documented `vm-lab --host malpern@localhost keypath ui ... -- preflight`
  reached the guest in 0.654 s. Peekaboo 3.10.0 reported Screen Recording and
  Accessibility ungranted for the guest console account; optional Event
  Synthesizing is also ungranted. The command stopped before UI interaction.
  A direct invocation without `--host malpern@localhost` could read lease
  metadata but could not access the Parallels guest (`.crabbox` permission
  denied); using the documented host mode resolved that routing issue. No
  grant or cleanup command ran. That lease was later destroyed; see B7 for
  why the rehearsal still needs a person at the guest.
- November 22 Mini CI capacity snapshot: both KeyPath runner LaunchDaemons were
  `running`; the Mini has 64 GiB RAM, 67% system memory free, and 2.7 TiB free
  on `/`. This was an idle snapshot, not telemetry during overlapping CI jobs,
  and does not close the sustained-overlap qualification. The sustained-overlap
  run on November 22 does; see the CI row in the outcomes table.
- PR #1619's November 22 Actions run provides a fresh single-test-job baseline:
  `quality-full` ran on `keypath-mini` while `test-full` ran on
  `keypath-mini-2`. The full test lane completed in 244 s (77 s build, 167 s
  test), with a warm SwiftPM cache and zero recorded Swift, module-cache, or
  app warnings/errors. This verifies current routing and one full lane, but it
  did not run two full-test jobs concurrently and logged no resource samples.
- The installed `vm-lab keypath daily --ready-only` check returned `no ready
  daily guest` on November 22. The ready lease above was the separate macOS
  26.5.2 1.0.1 rehearsal guest, not a daily remap guest; it has since been
  destroyed.
- November 22 release checks on master `ec71256`: a fresh macOS 27 admission
  installed, passed normal Settings consent and remapped q to a before and after
  relaunch; a lab Sparkle update from 9001 to 9002 was staged, survived
  `kill -9`, installed and relaunched with the engine running, and the remap
  still passed.
- November 22 screenshot: the overlay health card showed one issue and disabled
  quick remapping. On the Air at 05:29, KeyPath observed `com.apple.loginwindow`
  and its worker exited in `secureInput` state. The app's CLI reported the
  runtime stopped and keyboard access unverified (not denied). The overlay
  observer moved to `checking` while still displaying its previous healthy
  state. At 05:39 the worker restarted with `Session runtime ready (Secure
  typing ended)`; validation completed with zero blocking issues, and a second
  validation at 05:52 also found zero. Key-layer events continued through
  05:53. This supports the diagnosis that macOS Secure Input temporarily
  pauses remapping and that the runtime recovered after it ended. It does not
  verify the overlay's visual transition or capture teardown; P6's live
  timing and teardown evidence is recorded in its ledger row. The screenshot's generic issue card does not identify its underlying
  issue. Do not reset or re-grant permissions based on the CLI's `unverified`
  result. A separate Mini inspection at 02:22 reported no issues. No
  `output-queue-overrun` markers were found in the Air's current or rotated
  logs, so that hypothesis remains unsupported.
- Parts of the privately tracked findings still need release qualification;
  see the private tracker before declaring security work complete.
- The function-level dead-code estimate and historical share of `docs/` were
  approximate measures from the original review, not acceptance criteria.
- Build-time effects of target changes were not benchmarked as part of the
  original static review; no target change is currently proposed.


P9 completion (November 21): The remaining four rule-collection manager suites now receive per-test temporary config directories, stores, defaults suites, pack trackers, and notification centers. All 53 focused cases passed with two XCTest workers. The full safe suite then passed 4,729 XCTest invocations plus 847 Swift Testing cases under two workers with zero failures or warnings/errors. The targeted audit of shared defaults, logger, preferences and rule-store references found only read-only safety checks, singleton identity tests, and source text fixtures; no additional mutation of those shared fixtures was found.
