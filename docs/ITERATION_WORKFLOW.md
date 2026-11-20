# KeyPath development workflow

| Machine | Use it for |
| --- | --- |
| Air | Interactive Swift and UI work in a dedicated worktree. Keep the local SwiftPM cache warm and run focused tests before installing a candidate. |
| Mini | Required macOS CI, signed builds when the Air is busy, and desktop QA in the VM lab. |
| Linux | Documentation, shell and Python checks, and analysis of sanitized test logs. Use Apple hardware for Xcode, SwiftUI/AppKit, Metal, signing, and live remap verification. |

## Air inner loop

Keep one owner for installed-app changes during an iteration. Other agents can
edit and run focused checks in their own worktrees.

1. Pick one concrete defect or small related group. Record the expected behavior and reproduce it before editing. For a bug, add a regression test that fails for the actual defect.
2. Fix through the existing owner. Launcher edits must go through RuleCollectionsManager's configuration transaction, merging into the latest state while holding its lease. Never save RuleCollections.json alone or bypass the handwritten-configuration preservation guard.
3. Run the narrow relevant tests. For tour layout, include scene geometry, the production hero layout, and composed-screen snapshots. Do not repeat broad tests without a new reason.
4. From the Air, use `Scripts/ui-deploy.sh` for a UI-only change and
   `Scripts/quick-deploy.sh` for a normal local app deployment. If you are
   building a signed bundle on the Mini for the Air, use
   `Scripts/air-iterate.sh`. Add `--no-build` to transfer a matching signed
   bundle already in `dist/`. The script preserves a rollback copy, checks the
   installed executable, and verifies the running session. For builds that
   change the Rust engine or host bridge, use a full signed app bundle.
   Keep the Air awake during keyboard checks and record the installed binary
   hash, source revision, and tracked modifications.
5. Use **Help → Preview KeyPath Tour…** for visual iteration. Page buttons jump directly to any of four pages; the State picker selects fresh, installed, app-selected, failed-save, existing-setup, or saved-but-inactive fixtures. Changes stay in memory. Closing the preview does not mark onboarding complete. The real Replay Tour remains the integration check for durable saves.
6. Verify the actual installed UI at a fixed window size, all four pages and the affected state. Compare ordinary key bounds, including after selecting an app and navigating backward. Confirm saves in both metadata and generated config, then remove temporary test mappings through the same UI and verify cleanup in both files.
7. Report what changed, tests and live checks completed, exact installed build, and any remaining blocker. Update the checked-issues list with evidence. “Code tested” and “installed and visually verified” are separate states.

## Mini verification and CI

Use [`vm-lab keypath daily`](testing/remote-installer-lab.md#daily-ui-and-remapping)
for signed swaps and remap checks on a warm guest. Reserve fresh guests for
onboarding, normal consent, installer, reboot, and release qualification.
The recorded run took 13.69 s to swap and 18.22 s to verify remapping after the
build and guest were ready. Its full signed build took 4m 45s and fresh guest
preparation took 9m 32s. A fresh guest and a complete signed build belong on
the path only when the change needs them.

For trusted branches in this repository, the macOS jobs behind the required
`build-and-test` and `code-quality` checks run on the Mini. The
`swiftpm-safe` runner owns the single full Swift test lane. Quality can run
on the other runner, while GitHub-hosted macOS covers fork PRs and the
configured outage fallback. CI runs directly on the Mini. The VM lab
provides separate desktop evidence. The docs-only classifier serves the
required check names without scheduling the full macOS jobs for docs changes.

For parallel agent work, give each agent its own worktree and build directory.
Run focused tests before allocating a full macOS build. Record queue wait,
build time, and test time separately when investigating a slowdown. Keep the
full Swift CI lane serialized until test isolation and measured resource
use justify a second lane. On November 20, 2026, three successful Mini runs
spent 3m 09s to 3m 50s executing the full Swift job. Two waited about 20–22
minutes for the runner. The quality jobs began within two seconds and
finished in 12–13 seconds. These runs show why queue time matters when
several agents open PRs together.

## Portable checks on Linux

The Linux box has a canonical checkout at
`/home/malpern/local-code/keypath-validation` with origin
`malpern-labs/KeyPath`. Refresh master with `git pull --ff-only origin master`
before checking it. Use a separate worktree at the exact revision for a branch
or for concurrent work, and report the revision checked. This checkout needs
neither the Kanata submodule nor signing credentials for the following checks.

```bash
cd /home/malpern/local-code/keypath-validation
export PYTHONDONTWRITEBYTECODE=1
python3 -m unittest Scripts.tests.test_generate_keyboard_detection_index \
  Scripts.tests.test_check_app_intents_metadata Scripts.tests.test_test_deadline
python3 Scripts/lab/tests/scenario-result-tests.py
python3 Scripts/lab/tests/scenario-report-tests.py
bash Scripts/lint-no-sleep.sh
```

Verified on Linux at KeyPath `8d336c5f` on November 20, 2026. All 25 tests
and the shell lint passed. Use these checks during development and keep the
required PR checks as the merge gate.

## Verified shortcut-save defect (2026-10-11)

Deleting a launcher mapping directly saved RuleCollections.json while leaving keypath.kbd unchanged. The next tour save was correctly rejected by the reproducibility guard. `LauncherStoreTransactionTests.testDeleteCommitsGeneratedConfigAndAllowsNextTourSave` failed both assertions before the fix. The store and launcher customization now use the canonical transaction. Queued edits merge into the latest configuration; a rejected write keeps the previous visible mappings and reports an error.

Regression coverage also checks queued delete/add operations and byte-for-byte preservation of an unreproducible config and its JSON. The preview model has no configuration manager, installer, or onboarding-gate dependency; it supplies presentation-only action callbacks to the production dialog.
