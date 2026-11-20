# Remote KeyPath Installer Lab

`vm-lab keypath` is the supported controller for disposable installer
testing on the existing Mac mini lab. It defaults to
`clawd@keypath-lab-mini`; use `--host` or `KEYPATH_LAB_HOST` for another SSH
alias that exposes the same lab contract. Daily desktop work uses the Mini
console account (`ssh malpern@mini`); the daily command selects it automatically.
Other controller/CI operations may still use the clawd route.

The controller does not modify disk layout, the host's main drive, the stopped
Parallels base VM, or the Tart OCI base image. Destructive commands require an
exact `keypath-installer-lab-v1` ownership manifest under:

`/Volumes/KeyPath Lab/CrabBox/KeyPathInstallerLab/leases/<lease-id>/`

Only disposable leases created by this interface can be destroyed or swept.
Logs, manifests, commands, results, screenshots, and collected test artifacts
remain beneath `KeyPathInstallerLab` on the external volume after cleanup.

## Pre-run iteration policy

Before creating a VM, read `docs/iteration-workflow.md` in the Mini's
`/Users/malpern/local-code/vm-lab-prepared` checkout. Plan scenarios and pass conditions, check which actions the lab supports,
and batch tests on the owned lease. Use the guarded replacement process below
for a new signed build. A cancelled permission prompt does not prove that a
grant can be revoked and granted again. Collect evidence and destroy the lease
when the batch ends.

## Prerequisites

- SSH access to `malpern@mini` for the Mini console-owned desktop workflow.
- `/Volumes/KeyPath Lab/CrabBox/keypath15`, `keypath26`, and `keypath27` executable.
- The installed `vm-lab` launcher; confirm its checkout and commit with
  `vm-lab --version`. Do not infer the controller binary from a shell
  `crabbox --version`: shell and controller installations may differ.
- A full 40-character KeyPath commit SHA present in the local repository.
- A signed installer artifact whose SHA-256 checksum can be recorded.

`--ttl` defaults to `2h` and accepts values from one second through two hours,
matching the maximum lifecycle exposed by the existing launchers.

## Desktop smoke checklist

1. Run `vm-lab keypath preflight` and `vm-lab keypath list`. Build and sign once
   for the selected commit, record the installer SHA-256, and reuse that exact
   ZIP across retries. Admission can reuse an existing archive for that pair.
2. Admit a fresh `unmanaged-ui` desktop lease. Record the guest OS build and
   confirm KeyPath is absent before installing it. Run
   `vm-lab keypath ui LEASE -- preflight`, then verify a visible, unlocked
   desktop independently. A working accessibility bridge and the correct
   console username can coexist with a locked screen. Keep the guest awake
   for the bounded test session after verifying unlock.
3. Install through the lab. Start capture before first launch to observe the
   poster and its dismissal. Follow KeyPath's setup wizard and normal macOS
   consent, then verify the installed CLI reports a running worker.
4. Verify virtual keyboard input against a known baseline, apply a test remap,
   and verify the changed output before and after quitting and reopening
   KeyPath. Label this as virtual input coverage. Run the physical USB test
   separately after verifying the fixture is present and in silent mode.
5. Record time to ready, install, consent and remap separately. Save the
   screenshots and results with the lease artifacts, then destroy the lease.

Use Apple Setup Assistant when qualifying OS provisioning. A prepared base
for routine product tests should have macOS setup complete and a working lab
observer. Qualify KeyPath's initial permission state, first launch and remap
on a disposable child before using a new shared base.

### Daily UI and remapping

On the Mini, run `vm-lab keypath daily` as the console account. It reuses the
verified warm guest or prepares a new guest when the previous lease has
expired or been destroyed. Use `--ready-only` to require an existing guest.

```bash
vm-lab keypath daily
vm-lab keypath daily --installer /absolute/KeyPath.zip --source-identity /absolute/source.json
vm-lab keypath daily --close
```

The signed build swap uses the lab's guarded replacement workflow and preserves
the guest's configuration and grant. Verify the behavior under test and save
the revision receipt with the results. `--close` collects artifacts and releases
the daily lease at the end of the batch.

#### Verified signed development run

Run these commands in the Mini's `malpern` console account. From the Air,
connect with `ssh malpern@mini`. Use a dedicated KeyPath worktree, fetch
`origin/master`, and record its full SHA. Keep signing keys on the host.
Build using the project's signed development workflow. For an app-only UI
change, prefer the inner-loop build; the measured full candidate used
`Scripts/build-and-sign.sh` with `SKIP_DEPLOY=1 SKIP_NOTARIZE=1
SKIP_SNAPSHOTS=1 SKIP_SPARKLE=1 SKIP_WEBSITE=1`. Signing may require the
existing GUI-session signing route; do not repeatedly attempt locked SSH
Keychain signing or store its password. Notarization is a separate release gate.

Do not edit or switch the worktree between building and recording provenance.
Run the following immediately after the build, from that same worktree. Keep
the ZIP and source JSON outside the worktree (or beneath ignored `dist/`) so
writing the receipt does not itself change the dirty-state measurement.
After signature verification, archive the complete app and write provenance
from the exact ZIP and executable that will be installed:

```bash
codesign --verify --deep --strict /absolute/dist/KeyPath.app
ditto -c -k --keepParent /absolute/dist/KeyPath.app /absolute/KeyPath.zip
python3 - /absolute/KeyPath.zip /absolute/dist/KeyPath.app/Contents/MacOS/KeyPath \
  "$(git rev-parse HEAD)" > /absolute/source.json <<'PYTHON'
import hashlib, json, subprocess, sys

def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

archive, executable, commit = sys.argv[1:]
dirty = bool(subprocess.check_output(["git", "status", "--porcelain",
    "--untracked-files=all"], text=True).strip())
print(json.dumps(dict(commit=commit, dirty=dirty,
    archiveSHA256=sha(archive), executableSHA256=sha(executable))))
PYTHON
vm-lab --version
vm-lab keypath daily
vm-lab keypath daily --ready-only --installer /absolute/KeyPath.zip \
  --source-identity /absolute/source.json
bash /Users/malpern/local-code/vm-lab-prepared/rig/check-virtual-remap.sh <lease>
```

Check the daily replacement `build.json` receipt for `verified: true` and
matching ZIP/executable hashes. Admission's original commit alone does not
identify a swapped build. The installed harness captures `q → q`, adds
`q → a`, then captures `a` before and after restarting KeyPath on the same
guest. It uses lease-bound explicit key press/release and independent capture.
It writes a test rule, so use only the owned disposable test guest. A retry or
another guest is separate evidence. Record splash observation separately;
a remap pass alone does not prove the splash appeared.

On November 17, launcher `7597eef` swapped signed KeyPath master `049aaeb`
on lease `cbx_8f186b766fd6` in **13.69 s**. The installed harness passed once
in **18.22 s**, including all three captures. The full signed build took
**285.13 s** and ran alongside one-time guest preparation, **571.76 s**.
These are observations, not time guarantees. Warm reuse in the natural-expiry
qualification took **4.70 s**. Closing the guest means the next daily call
must prepare another one; retain it during the iteration batch.

Evidence on the Mini is `/Users/malpern/vm-lab-dev-run.yA2YkP` and
`/Users/malpern/vm-lab-natural-expiry.GpWW0s`. Both completed cleanup with the
qualified base fingerprint unchanged. PRs [18](https://github.com/malpern/vm-lab/pull/18)
and [19](https://github.com/malpern/vm-lab/pull/19) are merged. Do not repeat
the two-hour expiry test for ordinary development. At batch completion run
`vm-lab keypath daily --close` and check `cleanup_status` is `complete`.

For onboarding or permission changes and release qualification, start a
fresh clone, confirm KeyPath starts without effective permission, and exercise
the normal Settings flow. A warm build replacement is functional evidence
for that specific revision.

### Concurrency qualification — November 19, 2026

A bounded two-guest fresh-preparation run on installed lab `7597eef` did
**not** qualify concurrent readiness. Both guests passed keyboard calibration
but stopped at normal Settings consent with `unique enabled KeyPath toggle
unavailable`, before loading credentials. The actions were not replayed.
Concurrent remapping was therefore not executed. This does not establish
whether concurrency caused the consent failure; inspect the retained journals
before attempting a repair.

Admission/settling took 143.96 s for the first guest and 290.32 s for the
second, measured from simultaneous dispatch. The complete experiment and
cleanup took 572.58 s. Both leases ended `destroyed` with `cleanup_status`
`complete`, and the qualified base fingerprint was identical before and after.
Evidence is on the Mini at `/Users/malpern/vm-lab-concurrency.IsqIK7`.

Filesystem probes confirmed separate guest writes and no visibility of a
synthetic host file or the host's credential-file path. Network and integration
checks identified isolation gaps requiring follow-up. Treat the current lab as
trusted-code testing infrastructure. Two admission slots are a capacity limit;
parallel fresh preparation remains unqualified. Keep fresh consent testing
separate from ordinary signed swaps on an already-ready guest. Physical USB
qualification remains deferred.

### Candidate isolation qualification — November 19, 2026

The later candidate in [VM lab PR #20](https://github.com/malpern/vm-lab/pull/20)
passed two fresh guests through normal consent, signed master swaps, and the
baseline/remapped/relaunch captures. Exact host and sibling network probes
passed with a working management positive control. Both guests cleaned up
completely, and the base fingerprint was unchanged. Swaps took 11.61/12.60 s;
remap checks took 19.86/20.80 s. Evidence:
`/Users/malpern/vm-lab-peer-filter-pair.3rdrwh5y` on the Mini.

The same candidate prepared a daily guest in 608.64 s, then reused it in
13.59 s with filter reapplication/verification. Its remap harness passed on
that guest. Evidence: `/Users/malpern/vm-lab-filtered-daily.abss6_c5`.
These candidate results supersede the earlier consent failure for those exact
runs; they do not erase the failed journals or establish unlimited concurrency.

The installed launcher was still clean main `7597eef` when checked. Host-filter
service installation/restart qualification and candidate rollout remain pending.
Do not describe PR #20 as the deployed default until those postconditions pass.
Guest filtering is defense in depth, and guest root can undo it: run trusted
code only. Keep the source-base fingerprint check intact. Physical USB testing
remains deferred, and may run only after verifying the fixture is silent.

### macOS 27.2.1 lab observations

- Allow roughly two minutes for a warm-archive Parallels lease on the Mini.
  One measured run took 2m 16s from provisioning dispatch to ready, including
  the 90-second Parallels Tools stability window. The reused ZIP installed in
  two seconds. Record both timings before tuning the readiness window.
- Start the bounded wake assertion promptly after confirming console login and
  unlock. A provider capture can return a black frame while a signed UI bridge
  reports ready. Verify the guest lock state and a visible window before
  launching KeyPath. If it already launched behind the lock screen, use a fresh
  clone to capture first launch.
- For the public-account workflow, open a Finder window and run
  `rig/public_awake.py --verify-desktop` with the same account journal, wake
  journal, boot UUID, and signed window probe used to hold the guest awake.
  Continue only after the command reports `desktopReady: true`.
- The prepared-base attempt on build 26B131 completed Apple Setup Assistant
  and verified the signed lab Observer's access. The passive KeyPath report
  had Accessibility denied and keyboard listening and posting unknown.
  Functional qualification retains those raw statuses and requires both
  effective access flags to be false. A candidate still needs child
  qualification, normal consent, and a remap before it can become the
  shared default. The November 15 runs below met those requirements.
- Prepared-base publication should register a verified copy of the stopped
  source. Child provisioning should make a full clone from its own temporary
  staging image. If the source manifest changes or staging cleanup fails,
  preserve the journals and inspect the recorded image identities through the
  lab before retrying.
- With `--prepared-functional-base BASE_ID`, admit the test build by commit
  and signed installer SHA-256. The child qualification must match its own
  admitted artifact. The live macOS 27.2.1 child inherited the account and
  passed its passive KeyPath check. macOS reopened Apple Account and FileVault
  setup after login. After completing those screens, the child passed the
  splash, normal KeyPath consent, and virtual remap before and after reopening.
  Installation took 1 second, consent submission to worker readiness took
  12 seconds, and the remap and reopen check took 20 seconds on that run.
  Check the desktop before installing KeyPath and record any OS setup that
  reappears on the clone. This earlier candidate was opt-in.
- On the Mini, use `/Users/malpern/local-code/vm-lab-prepared/bin/vm-lab`
  for the prepared controller and pass `--host malpern@localhost` before
  `keypath`. Two fresh children qualified a different signed build and
  reached an unlocked desktop without manual input. The startup runner handled
  the recurring macOS screens. The first child also passed splash, consent
  and virtual remapping before and after reopening.

- The November 15 qualification passed on `cbx_1e17c8e26277` and
  `cbx_0a4242e0bc29` using macOS 27.2.1 (26B131), prepared image
  `observer-a3f3a048c65eb973f071f57778e09cef`, and KeyPath commit
  `45f09b16307a78db7f19a951af5f72be1ac6f304`. Both runs logged poster load
  and dismissal about 1.3 seconds apart, completed normal Settings consent,
  and captured the same virtual remap after relaunch. A separate attempt
  stopped before submitting authentication and was retired.
- On the Mini, the prepared controller selects the qualified image for
  `keypath create --macos 27 --lane unmanaged-ui --desktop` using the
  console-owner route. Invoke
  `/Users/malpern/local-code/vm-lab-prepared/bin/vm-lab --host malpern@localhost`
  for that workflow. Use `--standard-desktop-base` for an explicit run against
  the standard desktop template.

## Host disk reserve

The Mini keeps a 90 GiB internal-data-volume reserve for runner builds,
indexing, and host OS work. `create` checks this reserve after taking the
provider admission lock and exits 75 with `disk_reserve_busy` when admitting a
new lease would be unsafe. It is an infrastructure wait, not a product failure.
`preflight` reports the current reserve evidence. Set
`KEYPATH_MIN_FREE_DISK_GIB` only for a deliberately different host policy.

The self-hosted CI, cache-warm and coverage workflows run
`Scripts/lab/host-disk-reserve` before expensive compilation with a lower
40 GiB threshold (`KEYPATH_MIN_FREE_DISK_GIB: "40"` in each workflow), and exit
75 below it. A build needs far less than a VM clone, and the 90 GiB bar stopped
CI on 2026-10-19 with 78 GiB free. VM admission keeps the 90 GiB default.

Check the non-mutating host/provider contract:

```bash
vm-lab keypath preflight
```

## Concurrent agents and provider admission

Agents may prepare code, artifacts, and local contract tests concurrently, but
VM creation is admitted centrally on the mini. The default host limits are one
active Tart lease and two active Parallels leases. `create` takes an atomic
provider-specific host-side admission lock, counts unexpired owned lease
manifests, and reserves capacity before another creator for that provider can
enter. Tart and Parallels provisioning can proceed in parallel. The lock is
held only during provisioning; each resulting manifest remains the capacity
reservation until the lease is destroyed or expires.

When a pool is full, `create` exits 75 and prints `capacity_busy` plus every
owning lease, OS, lane, expiry, commit, and slug. This is an infrastructure wait,
not a KeyPath failure. Agents should continue non-VM work or retry after the
reported lease is destroyed; they must not stop or adopt that lease. A dead
creator's admission lock is reclaimed automatically, while a live creator gets
a five-minute bounded window to finish provisioning.

The limits can be tuned on the mini with `KEYPATH_LAB_CAPACITY_TART` and
`KEYPATH_LAB_CAPACITY_PARALLELS`. Provider capacity and managed identity
admission are independent: raising Tart capacity permits concurrent randomized,
freshly enrolled macOS 15 managed clones, while macOS 26 managed clones remain
serialized on their shared enrollment identity even when Parallels has spare
capacity. Keep Tart at one by default until repeated concurrent Tart runs prove
that host resources and provider inventory remain isolated.

## Lifecycle

Creation never syncs the current worktree. It exports the explicit commit with
`git archive`, adds the installer and source metadata, uploads that immutable
payload, and atomically initializes a clean synthetic archive on the external
lab volume. Each lease receives its own clean checkout cloned from that archive.
CrabBox's claim therefore binds one disposable lease to one stable repository
root, and every run, download, and destructive stop executes from that exact
claimed checkout. The interface refuses to sync if Git reports tracked or
nonignored untracked changes.

Uploads use a host-generated, owner-only `mktemp` ticket rather than a
commit-derived `/tmp` filename. Publishing the immutable archive is protected by
a per-key lock, so concurrent requests either publish once or validate and reuse
the completed archive.

```bash
SHA=$(git rev-parse HEAD)
vm-lab keypath create \
  --macos 27 \
  --lane unmanaged-ui \
  --commit "$SHA" \
  --installer dist/KeyPath.zip \
  --ttl 2h \
  --desktop

vm-lab keypath list
vm-lab keypath status cbx_example
vm-lab keypath install-app cbx_example
vm-lab keypath nameplate cbx_example enable
vm-lab keypath run cbx_example -- sw_vers
vm-lab keypath secure-dialog-input cbx_example \
  --app 'System Settings' --field Password --submit 'Modify Settings'
vm-lab keypath artifacts cbx_example
vm-lab keypath destroy cbx_example
vm-lab keypath cleanup --dry-run
vm-lab keypath cleanup
```

Every manifest records the source commit, macOS product version and build,
provider, installer name and checksum, expiration, commands/results, artifact
collection, and cleanup state. `destroy` is idempotent after successful cleanup.
Artifact collection packages scenario output inside the guest and retrieves the
single archive with CrabBox's native, owner-only `run --download` path. It does
not parse private SSH-key locations or invoke `scp`. CrabBox 0.36's provider
`cp` command is not supported by these providers, and its aggregate desktop
artifact workflow requires a desktop-enabled lease. Controller screenshots use
CrabBox for Tart leases and Parallels' read-only `prlctl capture` for Parallels
leases; CrabBox's generic screenshot command expects a VNC endpoint that the
Parallels desktop base intentionally does not expose.

Pass `--desktop` when approval interaction or screenshots are required. The
controller mirrors the existing provider launcher configuration while adding
CrabBox's desktop capability; ordinary creation continues to use the launchers
unchanged. Artifact collection captures a screenshot for desktop leases and
records an explicit unavailable status otherwise.

### Verify expired lease cleanup on the Mini

From the Mini's console account, run `vm-lab --version` to record the checkout
and commit. Use a disposable Parallels lease you created with the installed
launcher. The prepared macOS 27 desktop completed provisioning with
`--ttl 4m` in this check. Collect artifacts while the lease is ready and record its
`expires_epoch` and `provider_resource` from `status`. The latter is the VM's
Parallels UUID.

```bash
LEASE=cbx_example
vm-lab --host malpern@localhost keypath status "$LEASE"
vm-lab --host malpern@localhost keypath artifacts "$LEASE"
```

Let the lease expire naturally, then check which leases the cleanup would target.

```bash
vm-lab --host malpern@localhost keypath cleanup --dry-run
```

Run the timed cleanup only if the dry run lists exactly one `would_destroy`
entry and it matches your lease. If other leases are listed, wait and repeat
the dry run, or release your lease with
`vm-lab --host malpern@localhost keypath destroy "$LEASE"` and skip the timed
cleanup check. If the lease already shows `destroyed`, skip timing.

```bash
/usr/bin/time -p vm-lab --host malpern@localhost keypath cleanup
vm-lab --host malpern@localhost keypath status "$LEASE"
```

Cleanup of one expired lease on the Mini took **16.12 seconds** through the
installed launcher at `bf5cb3b` on November 16, 2026. Use **15–20 seconds**
as a rough guide, excluding the TTL wait and artifact collection. Confirm
the command reports deleting only your lease before using the timing. Check that cleanup exits with code 0 and emits no warnings or
errors, including the GitHub Actions hydration stop-marker warning. In
`status`, verify `status=destroyed`, `cleanup_status=complete`, and
`cleanup_result=0`.

From the same Mini account that owns the lease, check the full Parallels
inventory, which includes stopped VMs.
The inventory command must succeed and the recorded `provider_resource` UUID
must be absent from its output.

```bash
"/Applications/Parallels Desktop.app/Contents/MacOS/prlctl" list -a
```

### Desktop-base admission

`--desktop` reserves a display-capable lease; it does not by itself prove that
the guest is ready for semantic UI automation. Before a scenario relies on
System Settings, admit the base through these postconditions:

> `peekaboo-ui` moved to the vm-lab repository and is no longer shipped into
> the guest with this repo. The desktop base provides `peekaboo` itself at
> `/usr/local/bin/peekaboo`; call it directly, or see vm-lab's
> `docs/ui-automation.md` for the targeting contract.

- a real console user is logged in (not merely an SSH account);
- the guest has a Python runtime for the scenario drivers; and
- `peekaboo-ui preflight` succeeds for that console session.

If any condition is absent, record an `environment-precondition-failure`,
collect artifacts, and destroy the lease. Do not fall back to raw provider
commands or treat the result as a KeyPath failure. The macOS 26 Parallels base
observed on July 13, 2026 was SSH-ready but had no logged-in console user and
no Python runtime; it needs a new clean base checkpoint after automatic login
and desktop-tool provisioning before selector scenarios can run.

The macOS 27 Parallels base is intentionally preserved at `loginwindow`. Before
running `desktop-bootstrap`, establish its disposable clone's console session
through the owned controller:

```bash
vm-lab keypath console-login cbx_example
```

This command is macOS-27/Parallels-only. It streams
`KEYPATH_LAB_GUEST_PASSWORD` from
the encrypted host secrets over the lease-owned SSH channel into a root-owned
FIFO in the disposable guest. The command first verifies that the credential
authenticates the `keypathqa` account. The value is held briefly in an
owner-only controller temp file so it can be streamed and checked for accidental
log disclosure; that file is removed before the guest reboots. The value never
appears in controller arguments or logs. Inside the disposable guest, macOS's
noninteractive `dscl` authentication and `sysadminctl` automatic-login commands
briefly receive the value in their process arguments because neither command
offers a noninteractive stdin form. Do not enable process-argument capture
during `console-login`; destroy the clone after collecting the normal lab
artifacts.

The guest opens the FIFO read/write and applies a bounded credential-read
timeout. The controller applies the same bound with a watchdog around the SSH
writer, so a failed or stalled stream cannot leave either side blocked forever.
Stream transport failures, credential-authentication failures, and detected
credential disclosure have distinct fail-closed statuses. If disclosure is
detected, the controller log is immediately redacted.

The command asks `sysadminctl` to enable automatic login first. macOS 27 build
`26A5378j` can return success while logging `SACSetAutoLoginPassword error:22`
and leaving automatic login disabled. When the postcondition catches that
false success, the disposable clone falls back to writing the same
login-window state, including the reversible `/etc/kcpassword` representation.
That credential-bearing file exists only inside the disposable clone and is
removed with the lease. It also aligns CrabBox's mode-0600 guest credential
file with the verified account password so ARD authentication uses the same
known credential; that credential-bearing file is likewise confined to the
disposable clone. The command then reboots and does not succeed until
`/dev/console` is owned by `keypathqa`. This avoids relying on
pre-login RFB delivery, which macOS 27 can acknowledge without applying the
input, while preserving RFB for post-login UI interaction. The controller also
checks that automatic login names `keypathqa` before it reboots; a zero exit
from `sysadminctl` alone is not accepted as proof. A credential mismatch is
reported explicitly and does not mutate the guest account.

After console login, verify that the RFB path delivers input instead of merely
acknowledging the protocol write:

```bash
vm-lab keypath rfb-pointer-probe cbx_example --x 160 --y 120
```

The probe reads the guest cursor location, sends one CrabBox RFB click, and
requires the cursor location to change. It refuses to run until
`console-login` has established and verified the `keypathqa` console session.

On macOS 27 build `26A5378j`, ordinary Screen Sharing initially acknowledges
RFB input without delivering it. Unified logs report that the console agent has
event posting disabled. Apple's supported command-line setup is view-only, so
enable Remote Management control through the real logged-in System Settings UI
before classifying the lease as agent-drivable.

For the Parallels lane, operate that one-time prerequisite through the lease's
real Parallels console. When the authorization sheet has its password field
focused, submit the encrypted guest credential without exposing it to argv,
logs, screenshots, or the pasteboard:

```bash
vm-lab keypath secure-console-submit cbx_example
vm-lab keypath rfb-pointer-probe cbx_example --x 160 --y 120
```

`secure-console-submit` emits one Parallels key event at a time with a bounded
inter-key delay. Parallels can drop characters when a complete credential is
sent as one unpaced event batch. The command deliberately reports credential
transport only; the RFB probe is the required independent postcondition.

On July 16, 2026, the supported UI flow enabled Remote Management and VNC
control for `keypathqa`, and the probe moved the guest cursor from
`684.703125 141.1875` to `80 60`. That proves event posting for this disposable
clone and OS build. Repeat the UI approval and probe for a fresh clone or beta
seed; do not infer delivery from the visible toggle alone.

For a console-ready candidate base, run `desktop-bootstrap --install-tools`
once before capturing its checkpoint. It installs Python 3 as well as
Peekaboo and mcporter, then records the console-user and Peekaboo evidence.
This is base provisioning, not a per-scenario setup step.

### Disposable desktop identity with Nameplate

Nameplate can label an owned desktop lease without modifying its base image:

```bash
vm-lab keypath nameplate cbx_example enable
vm-lab keypath nameplate cbx_example status
vm-lab keypath nameplate cbx_example hide
vm-lab keypath nameplate cbx_example show
```

`enable` is accepted only for a desktop-enabled lease. It downloads the pinned
Nameplate `0.2.5` archive in the guest, verifies its SHA-256 checksum, Developer
ID signature, and Gatekeeper acceptance, and installs it beneath the console
user's `~/Applications`. The generated tag names the macOS lane, test lane,
provider, lease, and its disposable status. The version, checksum, visibility,
and last-change time are recorded in the owned lease manifest.

Nameplate's launch-at-login setting stays disabled because it registers an
`SMAppService` login item and would pollute the Background Items state that
KeyPath tests inspect. After a reboot, explicitly run `nameplate ... show`.
Automatic updates, watermarks, and connection-triggered splashes are also
disabled so a two-hour lease stays pinned and visually quiet.

Nameplate is operator instrumentation, not KeyPath evidence. `artifacts`
therefore hides a visible Nameplate before the controller screenshot and
restores it afterward. If hiding fails, the controller refuses to capture that
screenshot and records `unavailable:nameplate-hide-failed` instead of silently
producing contaminated evidence. Scenario scripts that take their own
screenshots should bracket them with `nameplate ... hide` and `show` as well.

### Semantic UI automation with Peekaboo 3

For the current capability matrix, security boundaries, and agent handoff
sequence, see
[`installer-gui-automation-capabilities.md`](installer-gui-automation-capabilities.md).

Desktop guests can use `peekaboo-ui` to discover and operate
KeyPath and System Settings without framebuffer coordinate assumptions. The
adapter provides typed commands for snapshots, semantic clicks, dialog
inspection, file selection, and Retina screenshots. Every command writes JSON
evidence alongside the scenario output so it is included by `artifacts`.

```bash
OUT=.keypath-lab/scenario-output/approvals/peekaboo

vm-lab keypath run cbx_example -- \
  peekaboo-ui preflight
vm-lab keypath run cbx_example -- \
  peekaboo-ui snapshot \
  --app 'System Settings' --output "$OUT/input-monitoring.json"
vm-lab keypath run cbx_example -- \
  permission-drag \
  --path /Applications/KeyPath.app/Contents/Library/KeyPath/kanata-launcher \
  --target-identifier KeyPath_Title \
  --output "$OUT/permission-drag.json"
```

The Accessibility and Input Monitoring plus-button panels filter the raw
`kanata-launcher` executable and leave Open disabled. `permission-drag` uses
the supported KeyPath flow instead: reveal the exact binary in Finder, derive
the current source and permission-list target geometry from fresh AX snapshots,
and drag between the two arranged windows. It succeeds only when macOS presents
an authorization sheet or the expected permission row appears. If authorization
is requested, follow it with `secure-dialog-input` and verify the new
`kanata-launcher_Title` row before continuing. The adapter records both windows'
original geometry and restores it on every exit path, so a failed attempt does
not leave later UI targeting in a modified coordinate space.

The July 12 macOS 15 unmanaged spike confirmed that the authenticated synthetic
drag still did not create a `kanata-launcher` row. Treat the drag adapter as an
evidence-producing experiment, not a solved registration path, until its row
and canonical permission postconditions pass. See
[`p01-unmanaged-input-monitoring-spike.md`](p01-unmanaged-input-monitoring-spike.md).

Peekaboo click success means that it delivered an action to the selected UI
element. It is not proof that macOS accepted a protected change. Background App
Activity, Driver Extensions, Accessibility, and Input Monitoring must be
verified through the canonical CLI/system/runtime postcondition after every
click. Driver Extension activation on macOS 15 may still require CrabBox's
native RFB click delivery. Use fresh Peekaboo geometry to locate the control
and compare it with the current CrabBox desktop viewport before clicking. In
the Tart 1024x768 desktop lane, Peekaboo's Accessibility bounds already match
the 1024x768 VNC viewport even though the backing display reports 2048x1536;
doubling those coordinates targets the wrong pixel. Never infer a scale from
the backing display alone, and never preserve raw coordinates between runs.

For a macOS 15 Tart desktop lease, `secure-dialog-input` handles an
authentication sheet without putting its password in a command line. It focuses
the named field with Peekaboo, decrypts only `KEYPATH_TART_ADMIN_PASSWORD` on
the mini, and streams it over the lease-specific CrabBox SSH connection to
Peekaboo's supported MCP `type` tool. Peekaboo and `mcporter` must be installed
in the guest (`brew install steipete/tap/peekaboo steipete/tap/mcporter`).

The command suppresses the complete MCP response because Peekaboo's `type`
result contains the value it typed. The secret is never an argument, never
written to `commands.tsv`, and never retained as an artifact. Only the app,
field label, optional submit button, and pass/fail result are recorded. Do not
use the generic `run` command to improvise password entry. macOS 26 and 27
Parallels guests remain unsupported until they have an equally constrained
lease-specific transport.

On macOS 15 authentication sheets, use an explicit submit selector when the
button is available:

```bash
vm-lab keypath secure-dialog-input cbx_example \
  --app 'System Settings' --field Password --submit 'Modify Settings'
```

The controller must strip the encrypted dotenv record's terminating newline
before sending the password. A newline passed to Peekaboo's type transport can
become part of the secure-field value rather than a Return key. Always confirm
success by checking that the protected state changed. When `--submit` is used,
`secure_dialog_input passed` proves the secret transport completed and both the
named password field and submit control disappeared; it still does not prove
that macOS accepted the underlying protected-state change.

Driver-extension authorization is owned by `SecurityAgent`, whose secure
window is not available to Peekaboo snapshots. When a fresh framebuffer image
proves that its password field is already focused, use the constrained focused
mode without a submit selector:

```bash
vm-lab keypath secure-dialog-input cbx_example \
  --app SecurityAgent --field Password --already-focused
```

This mode skips AX discovery but uses the same stdin-only encrypted secret
transport. It is valid only after current visual evidence shows the focused
secure field, and success still requires the corresponding system-extension
postcondition.

When an authorization sheet exposes an `AXSecureTextField`, prefer the stricter
role-based path with a submit label. This covers both standalone SecurityAgent
windows and sheets hosted by System Settings. The controller writes the
streamed password to a mode-0600 guest temporary file long enough for
AppleScript to set the protected field in the named app, derives the submit button's
current center from AX geometry, and delivers a synthesized foreground pointer
click. The file is removed by an exit trap, the clipboard is never used, and
the helper succeeds only after that secure field disappears. It does not use
`sudo` as a password oracle because the disposable Tart image intentionally has
passwordless sudo.

For a protected control that requires native RFB delivery, use the lease-owned
guard instead of invoking CrabBox directly:

```bash
vm-lab keypath protected-click cbx_example \
  --app 'System Settings' \
  --window Accessibility \
  --ax-x 402 --ax-y 247
```

With `--ax-x` and `--ax-y`, the command measures the current display's logical
and native dimensions and converts Accessibility coordinates to framebuffer
coordinates. Raw native coordinates remain available as `--x` and `--y` for
diagnostics. The command snapshots the named app before and after delivery and fails
if either window title differs from the declared page. When the click is
expected to open another page or dialog, declare that explicitly with
`--after-window`. This guard detects a delivered click that landed on the wrong
System Settings surface; it does not replace the permission's canonical product
or system postcondition.

For ordinary text or single-key input on a macOS 15 desktop lease, use the
lease-owned VNC path rather than calling CrabBox directly:

```bash
vm-lab keypath desktop-type cbx_example --text q
```

The controller verifies ownership, desktop capability, OS lane, and the exact
provider resource before invoking CrabBox `desktop type`. On macOS this is an
RFB key event (`method=vnc-key`), not guest-side AppleScript or CGEvent
injection. The command proves delivery only; the scenario must separately
observe its expected application or runtime postcondition. P01 used a captured
key chip in KeyPath's Input Capture Experiment as that postcondition.

`install-app` expands the staged ZIP into `/Applications` on the disposable
guest. Tart uses the base image's noninteractive sudo contract. Parallels uses
the same passwordless `prlctl exec` guest-control channel CrabBox already uses
to prepare the disposable clone, scoped to the exact provider resource recorded
in the owned lease manifest. Neither path changes the base image or stores a
guest password.

## Installer scenarios

Run a named scenario after creating a lease:

```bash
vm-lab keypath scenario cbx_example clean-install
vm-lab keypath scenario cbx_example approvals
vm-lab keypath scenario cbx_example helper-daemon-health
vm-lab keypath scenario cbx_example launch
vm-lab keypath scenario cbx_example repair-reinstall
vm-lab keypath scenario cbx_example reboot-persistence-before
# Reboot the disposable guest through the approved lab workflow.
vm-lab keypath scenario cbx_example reboot-persistence-after
vm-lab keypath scenario cbx_example uninstall
vm-lab keypath scenario cbx_example cancellation-failure
vm-lab keypath scenario cbx_example artifact-capture
vm-lab keypath scenario cbx_example macos-27-regression
vm-lab keypath artifacts cbx_example
```

The scenario set covers clean installation, every macOS approval gate,
helper/daemon and TCP health, launch, repair/reinstall, reboot persistence,
uninstall, cancellation/failure rendering, and final artifact capture. Approval
and cancellation cases intentionally give an operator a controlled observation
point rather than attempting to bypass macOS security UI. Never place Apple IDs,
passwords, private keys, TCC databases, or other credentials in a scenario or
artifact bundle. CrabBox does not redact collected files automatically; inspect
every bundle before sharing or publishing it.

### macOS 27 beta regression capture

On every significant macOS 27 beta seed, run the non-destructive evidence
capture on an installed signed and notarized build:

```bash
Scripts/qa-macos-27-regression.sh
```

For a disposable macOS 27 desktop lease, run the same capture after installing
the app:

```bash
vm-lab keypath scenario cbx_example macos-27-regression
vm-lab keypath artifacts cbx_example
```

The command records the exact OS build, canonical CLI system snapshot,
VirtualHID extension state, KeyPath-owned launchd jobs, signatures, Gatekeeper
and stapling results, processes, TCP readiness, and relevant logs. It also emits
an operator checklist for Accessibility, Input Monitoring, Background App
Activity, Driver Extension approval, overlay behavior, and reboot persistence.
Those interactions must use the real logged-in System Settings UI. They may be
driven by Peekaboo or CrabBox RFB automation; directly modifying TCC or
bypassing macOS approval UI would invalidate the regression test. Every
automated interaction still requires the corresponding system/runtime
postcondition.

Distribution trust checks are required by default. For harness development
against a locally signed debug deployment only, set
`KEYPATH_MACOS27_QA_REQUIRE_DISTRIBUTION_TRUST=0`; never use that override for a
release or beta-seed result.

## Failure and recovery

- If creation reports a lease but guest verification fails, preserve the lease
  ID and logs, inspect it with `status`, collect artifacts, then `destroy` it.
- If cleanup fails, the manifest remains `cleanup-failed`; the interface does
  not discard evidence or pretend the provider object was deleted.
- `cleanup` considers only expired manifests owned by this interface. It never
  invokes a provider-wide cleanup and never deletes archive caches or base
  images. The final `crabbox stop` runs from the exact checkout recorded in the
  lease manifest so CrabBox's own repository claim remains an additional
  destructive-operation guard.
- To test a different SSH endpoint, pass `--host user@host`; do not edit the
  launchers or embed host credentials in the repository.

## Local contract tests

The shell tests use fake launchers and a temporary lab root; they never contact
the mini or provision a VM:

```bash
Scripts/lab/tests/keypath-lab-tests.sh
```
