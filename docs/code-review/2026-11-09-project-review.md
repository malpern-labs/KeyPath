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

## Status (updated 2026-11-21)

Verified against `master` at `4bb160988172c08f564de1b31996a7e7248562e1`, after [#1604](https://github.com/malpern-labs/KeyPath/pull/1604) and [#1605](https://github.com/malpern-labs/KeyPath/pull/1605) merged. The findings below this status section describe the original review.

Key: ✅ done · 🟡 partly done or in progress · ⬜ not started · 🔒 tracked privately

### Progress toward the review goals

Sixteen review-related PRs merged on November 21 (#1589–#1605, excluding the unrelated #1575 and the unmerged #1602). They advance the original review goals as follows:

| Review goal | Progress represented by the overnight merges |
|---|---|
| **Reduce over-engineering (O7)** | #1589 and #1591–#1593 move configuration admission, rule operations, and generation out of the UI framework while retaining the pack gallery, confirmations, dependencies, and rollback. Three CLI files still need AppKit for pack mutations; that boundary remains open pending a shared decision/transaction contract. |
| **Improve localization (P8)** | #1597 and #1598 fix and independently review Japanese strings; #1601 verifies the macOS 27 permission-pane name against Apple’s Japanese system strings. Live onboarding and overlay layout checks remain. |
| **Improve concurrency and CI reliability (P6/P9)** | #1590 and #1603 remove obsolete runtime/test behavior and isolate shared test state; #1605 removes tests against the retired TCP listener. #1593 adds compiler-checked runtime readiness ownership. The full suite was qualified sequentially and with two XCTest workers before these merges; CI still needs the corresponding parallel test configuration and same-process isolation work remains open. |
| **Reduce CI waste and agent friction** | #1594 removes a cache-warm workflow that warmed no PR job’s cache; #1595 and #1596 move worktrees off ephemeral storage and require bounded build slots and isolated tests. |
| **Improve security and release behavior** | #1600 makes Caps Lock conflict attribution depend on verified ownership evidence and states the limits of macOS attribution; #1604 ignores environment log-level overrides in Release builds. |
| **Keep process guidance accurate** | #1599 documents the organization’s merge queue so PRs are tested against current `master` before merge. |

This is measurable progress toward the review: the merged changes reduce UI-framework coupling, correct Japanese content, narrow test side effects, remove stale CI work, and harden release behavior. It does **not** mean the review is complete. The remaining items are listed below with their required evidence; a merged PR or green CI does not substitute for live desktop, release, or lab verification.

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
| **O7** CLI split | 🟡 | Rule and collection operations, backup and restore, simulator, system inspection and logs, layout resources, backup storage, and generation inputs have moved to shared Core targets (#1532, #1543–#1546, #1563–#1569, #1586). A current source scan finds three CLI files importing `KeyPathAppKit`, all for pack install/configure/uninstall. The full executable still links the UI frameworks. No additional extraction is justified until those mutations can share an explicit decision/transaction boundary without changing pack behavior. |
| **O8** Unimplemented flags, wording, public-docs lint | ✅ | #1405. |
| **O8** CLI link and service ownership | ✅ | New links install under `~/.local/bin` and uninstall removes matching links. `AGENTS.md` documents when to use `ServiceContainer` or a singleton (#1429). |
| **O8** Test-mode checks and lint ratchets | ✅ | Retired lint tests and passwordless sudo test mode (#1428). Unified the parser (#1566), scoped keyboard-recognition fixtures (#1570), and required explicit test-host evidence before routing ordinary app launches into fixtures (#1577). A source audit of `TestEnvironment` branches found and fixed real-defaults and real-Keychain fallbacks; the remaining branches redirect file paths or suppress external process, permission, UI, and network side effects. Per-test shared state remains tracked under P9. |
| **B1** Dead view and images | ✅ | #1398. |
| **B2** Scripts | ✅ | #1395. |
| **B3** Dead Swift | ✅ | Deletion pass merged (#1398, #1406). Function-level Periphery scan completed with 3.8.0; retired unregistered CLI commands and their formatter are removed in this follow-up. Candidate diagnostics are not automatically safe deletions. |
| **B4** Tests for removed behaviour | ✅ | Dead tests removed and two stale references refreshed (#1420). The historical General Settings reference was refreshed to the existing Nothing default in #1478, retaining tolerances. The combined gate passed 5,524 tests. |
| **B5** Binary assets | ✅ | Unused assets removed (#1397); help assets compressed/deduplicated (#1422). Metal goldens losslessly recompressed in #1479: 28.7% smaller, identical decoded scanlines, full resolution and tolerances retained. |
| **B6** Root and package stragglers | ✅ | Root cleanup merged (#1395). Process probes moved into Core and the unused wizard screenshot and resource bundle were removed (#1440). Nine unused library product exports removed in #1475; executable products and internal target dependencies remain unchanged. |
| **B7** Docs | 🟡 | Public docs republished and runtime architecture rewritten (#1394, #1399, #1402, #1437). The published macOS 27 permission screenshot matches the verified capture (#1491). The live site labels and links the public 1.0.1 download and pins its setup guide to that version (#1520). |
| **P1** Sparkle | ✅ | See row 5. |
| **P2** Apple Events usage string | ✅ | #1404. Normal KeyPath → System Events prompt and shipped explanation verified on fresh guest cbx_093147ab40fe, signed candidate f2434116a, November 20. This verifies the requested prompt, not the resulting AppleScript action. |
| **P3** Blocking subprocesses | ✅ | `SecCodeCopySelf` replaces the signing shell-out and pipes are drained before waiting (#1404). Migration discovery is async and bounded, with retryable unknown states and tested stop routing (#1480). System probes also drain both output pipes concurrently (#1483); the serialized full gate passed 5,534 tests. Latest-master deployment and live verification remain separate release checks. |
| **P4** Shell-outs with API replacements | ✅ | Hidden flags, editor launch, function key preference writes, and signals use direct APIs. Spotlight search keeps a cancellable subprocess (#1426). |
| **P5** `os.Logger` in `AppLogger` | ✅ | Unified log output added (#1427). File logger state is synchronized and queued writes flush (#1445). |
| **P6** Concurrency leftovers | 🟡 | Feature flags and the app icon cache were synchronized (#1439). Three main-actor service conformances are compiler checked (#1481). Capability caches and several runtime callbacks are compiler checked (#1487, #1571). Duplicate configuration watcher code is gone (#1572). Subprocess launch and cancellation are serialized (#1574). Overlay expiry and view timers now respect their current owners (#1579). This pass serializes the session-worker hard-exit fallback with orderly shutdown and adds a race-ordering test. Live overlay timing and remaining framework handoffs are open. |
| **P7** Liquid Glass | ✅ | System glass in `AppGlassBackground` (#1408), checked on screen in light and dark. |
| **P7** Other idioms | ✅ | Deprecated drawing and activation replaced (#1460, #1508). The window and wrapper audit removed an unused control and records the behavior each remaining bridge supports (#1509). Color conversion stays with individual surface changes. |
| **P8** Localization | 🟡 | English and Japanese share a CI-checked catalog (#1430–#1433). The five overlay translations in #1578 cover the remaining active entries at that revision, verified by Xcode catalog compilation (3,477 of 3,477). Signed builds verified the virtual-key prompt and four Settings screens. An independent review of all 3,679 Japanese strings (ChatGPT, November 21) found 12 blocking issues; 11 are fixed and approved on re-review. The Japanese name of the macOS 27 Accessibility pane matches Apple's (checked November 21). Broader live layout remains. |
| **P9** Test isolation | 🟡 | Migration, approval-storage and script-action tests use isolated stores (#1434, #1478). Task-scoped capability inputs and isolated keyboard-recognition indexes and notification centers are merged (#1564, #1570). CLI collection and import stores, QMK fetch fixtures, and overlay snapshot output are isolated (#1580). The preference fallback now uses a test-only defaults domain, and a test that mutated `UserDefaults.standard` now uses its UUID-scoped fixture. This turn injects notification centers into preferences, reload and collection managers; removes host-Keychain/environment-dependent smoke assertions; gives QMK search tests a fresh database/cache per test; and routes Vallack/runtime mutation tests through the session test bridge. The `AppPaths` test sandbox now has a per-run UUID to avoid stale data after PID reuse, and its suite no longer deletes the shared root during teardown. The sequential full safe suite passed 4,744 XCTest invocations plus 844 Swift Testing checks. The follow-up full safe suite also passed with two XCTest workers: 4,745 invocations plus 844 Swift Testing checks, with zero failures and zero Swift or app warnings/errors. The runner summary does not report XCTest skip totals. Broader same-process shared-state audit remains, and CI still runs one full Swift lane. |

### Also done since the review (not in its list)

- ADR-048 keyboard attribution: spike, matcher, and log-only matcher in the session worker (#1392, #1393, #1396, #1400, #1401).
- The running app answers the CLI's engine commands. Coverage for that path merged (#1388, #1413, #1415).

### Open follow-ups

- B7: The live homepage and setup page send 1.0.1 users to the tag-pinned guide (#1520). Both published pages returned HTTP 200 after the update. The original notarized 1.0.1 installer passed Gatekeeper on a disposable macOS 26.5.2 guest and reached its background-item approval prompt. The active-helper cleanup portion of draft #1507 still needs a rehearsal after approval. When the session-runtime release is live, put macOS 27+ and Apple Silicon alongside its download and link the manual cleanup guide from setup and uninstall. Revisit automatic migration if tester evidence shows the manual path is a recurring barrier. See [ADR-047](../adr/adr-047-pre-release-cleanup.md).

- O7b: Keep the pack gallery, installation, and dependency features. Rules Core owns the read-only rule, collection, and pack catalog paths and the simulator (#1532, #1543, #1546, #1548). The simulator passed 35 focused tests, including four that run the bundled simulator. Seven comparisons against the preceding CLI matched stdout, stderr and exit status. System inspection and logs moved to CLI Support (#1568). Layout resources, backup storage, and generation inputs moved to Rules Core (#1565, #1586). Current source scan finds only three `KeyPathAppKit` imports in CLI commands: pack install, configure and uninstall. These mutations still route through the app's pack installer and its typed errors. Preserve this boundary until pack decisions and transactional side effects can be supplied explicitly by both app and CLI; do not add a broad engine target solely to remove the remaining imports. See the [CLI compile-boundary evaluation](#cli-compile-boundary-evaluation).
- O8c: The installer pack decisions and validator snapshots use scoped test inputs (#1523, #1525). The unused forced test mode was removed (#1528), and its full safe suite passed 5,529 tests. Removing the unused file-validation route and shared validation-host override preserved the real parser path in 165 focused tests (#1547). The audit found a test writing through `PreferenceDefaults.canonical` to the real standard defaults domain; it now uses its UUID-scoped `IsolatedPreferenceDefaults`. Implicit `PreferenceDefaults.canonical` and `PreferencesService` fallbacks now use a unique process-local test domain. Activity-log encryption previously used a separate real Keychain item in tests; it now keeps test keys in memory, with no Keychain calls. Regression tests cover both boundaries. Other `TestEnvironment` branches redirect fixture paths or suppress external process, permission, UI, and network side effects. The focused preference and activity-encryption tests passed on November 21. Same-process fixture sharing remains tracked under P9.
- P6: The mapper cancels delayed resets when the selection changes (#1519, #1540). Stale layer-indicator and tooltip callbacks respect their current window (#1526, #1534). Favicon completion and engine timeout cleanup follow their owning operation (#1538, #1549). In 85 focused tests, the timeout change preserved a replacement connection and its buffer. Capture teardown (#1567) and the overlay window's ownership of sizing and hint work (#1587) merged. The latter passed 51 focused tests and 5,548 full local checks. This pass found that cancelling the owner-exit `DispatchWorkItem` did not serialize an already-enqueued hard exit against orderly shutdown; both paths now share a lock, with four focused tests including the race ordering. Live overlay and capture teardown verification remains. The Layout Tracer compiler trial is recorded below.
- P8: The Japanese virtual-key confirmation and General Settings stable-update label fit in signed macOS 27.2.1 builds. Settings option cards and Status actions use language-independent IDs (#1535). Xcode compiled eight additional Japanese translations (#1536) and localized the Stable and Beta channel labels (#1542). #1578 added the Japanese remap and navigation labels. The signed guest captured General Settings, Status, Home Row Mods and Repair in Japanese. An independent review of all 3,679 Japanese strings and the permission prompts (ChatGPT through the Codex CLI, November 21) found 12 blocking issues: two swapped menu labels, an unnumbered placeholder reorder, two gesture instructions, three uses of ウインドウ for a reporting period, a shared Start key, a stale setup path, a KindaVim term and the Accessibility pane name. Eleven are fixed (the Vim keycap now has its own key, `vim.keycap.line-start`) and the re-review approved them. Its 33 minor suggestions were then applied too: wording, consistent terms (設定, 上段, 受付時間, 修飾キー, オペレータ, スペースバー in prose), numbered placeholders, and own keys for the Vim Open keycap, the Delete key name and the numpad Operators heading. A second review approved all 87 changed strings. Apple's own macOS 27.3 string tables (SecurityPrivacyExtension, TCC and the authorization prompt, key `ACCESSIBILITY`) give that pane as デバイスの制御とデータへのアクセス in Japanese, which KeyPath already uses, so the reviewer's アクセシビリティ (the pre-macOS 27 name) was not applied. Live layout for onboarding and the overlay remains.
- P9: Pack and collection tests, Caps Lock selection, leader recovery, the overlay window and onboarding fixtures use isolated test state (#1514, #1521, #1523, #1527, #1531). A safe-runner qualification on master `c2550766` passed 4,734 XCTest invocations with two worker processes plus 844 Swift Testing checks. A focused media-key test reproduced a comment-parsing error on the baseline and candidate. The fix passed all five media tests locally (#1533). #1580 isolates CLI writes and QMK fetch fixtures and fixes the navigation-layer snapshot setup. Device-selection writes now use their own configuration directory (#1585). At overlay candidate `f51656e5`, 83 scoped CLI, device-selection and rule-write cases passed with two XCTest worker processes, with zero failures or skips in the XML report. Seven Swift Testing rule-mutation checks also passed five repetitions in one process. A November 21 audit found one test mutating `UserDefaults.standard`; it now uses its per-test isolated suite. A follow-up source search found no direct `UserDefaults.standard` references under `Tests/KeyPathTests`; generated temporary paths in the sampled writes use UUIDs. Implicit preference defaults now fall back to a process-local test-only domain, and the focused preference suite passes. The current isolation pass injects notification centers into preference, reload, and collection managers; removes host-Keychain/environment-dependent smoke assertions; and changes the QMK search tests to use a fresh database/cache path per test. Focused coordinator (36), persistence, recovery, notification (10), parallel QMK (33), session-start permission-snapshot tests, and the Vallack/runtime mutation tests pass. The lifecycle permission invalidation test now uses its own `PermissionOracle` and injects only the invalidation action into its coordinator; the snapshot unit tests also use local oracles, and a vacuous host Accessibility-permission smoke test was removed. The `AppPaths` sandbox follow-up passed six focused tests. On November 21, the full safe suite passed sequentially (4,744 XCTest invocations + 844 Swift Testing checks) and again with two XCTest workers (4,745 + 844), with zero failures or skips and zero Swift or app warnings/errors. A Swift Testing-only run with `--maximum-repetitions 3` also exited 0 in the safe runner; the log records 842 cases reaching repetitions 2 and 3, and the runner counted 744 passes with zero failures or warnings/errors. These qualify process parallelism and repeated Swift Testing execution. Remaining: XCTest cases are not repeated in-process by SwiftPM's repetition option, and CI still serializes full-test jobs across the shared host.

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
- Reconcile delayed UI callbacks and timers with their owning view/window
  lifetimes. Convert only callbacks that require cancellation, and test closing
  or replacing the owner while a callback is pending.
- On November 20, Apple Swift 6.4.2 compiled the Layout Tracer module with
  both isolation settings, targeting macOS 27.0. Four existing downstream
  Swift Testing files type-checked with the current setting. Default
  main-actor isolation made synchronous document import and result access
  actor-isolated, and those callers failed to type-check. Keep explicit
  isolation at UI boundaries until the pure layout and file APIs can stay
  nonisolated.
- Live overlay timing and capture teardown still need a desktop guest run;
  the Mini preflight on November 21 found both Parallels lease slots occupied.
  No existing lease was inspected or changed.

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

### P9. Tests

4,651 XCTest methods and 851 Swift Testing tests. New tests are already going
to Swift Testing; do not mass-convert. The real blocker is that tests share
on-disk state (the CI workflow serialises jobs because of it). Fix isolation
before adopting more in-process parallel testing.

---

## Suggested order

1. **Public docs** (B7 "fix first"). Hours.
2. **Deletion pass** (B1–B6, O8, dead code from O5). Low risk, and it removes
   tests and lint ratchets that would otherwise fight the later steps. Split
   by directory so each PR is easy to review.
3. **Security before the first session-runtime release:** S1 and the
   privately tracked findings together, since they share a threat model and a
   design.
4. **Platform quick fixes:** P1 decision, P2, P3 launch path, the three
   deprecated APIs in P7.
5. **Installer collapse** (O1), then **state ownership** (O2, O3), then the
   wizard boundary (O4) and events (O5).
6. **Product decisions**, in no fixed order: plugin system (O6), Metal
   stage, packs, localization, Liquid Glass.

## Not verified

- The engine's TCP command set (submodule not checked out).
- Permission artwork was recaptured on November 20 from a fresh macOS 27 lab
  guest, with KeyPath enabled under Device Control and Data Access. The guide
  identifies the unrelated lab tools visible in the screenshot. Publication to
  gh-pages completed at 99a2200b6; public page and exact image hash verified.
- Parts of the privately tracked findings still need release qualification.
  P2's usage-string prompt was verified on a fresh macOS 27 guest on November 20;
  evidence is retained on the Mini under `~/keypath-final-ui-qa.XIYk30` and the
  guest artifact capture `20261120T051303Z`.
- Deprecation status of specific APIs in the macOS 27 SDK.
- The function-level dead-code estimate and the historical share of `docs/`.
- Build-time effects of any target change.
