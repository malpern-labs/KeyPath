# Manual cleanup rehearsal: public KeyPath 1.0.1

The in-app migration and automatic removal path described by the original
version of this test was withdrawn in [ADR-047](../adr/adr-047-pre-release-cleanup.md).
This plan now verifies the **manual cleanup instructions published in**
[`guides/upgrading-from-1-0-1.md`](../../guides/upgrading-from-1-0-1.md).
It does not test or imply automatic migration support.

**Status: blocked before UI rehearsal (November 22, 2026).** The official
1.0.1 ZIP was downloaded and matched its release digest. The current Parallels
lease (`cbx_67d82d322f17`) boots macOS 26.5.2 and has KeyPath 1.0.1 installed;
both facts were confirmed with read-only guest commands through the installed
`vm-lab` launcher. At 2026-11-22 11:38 UTC, the documented UI preflight reached
the guest in 0.654 seconds and found that Peekaboo 3.10.0 lacks Screen Recording
and Accessibility in the guest's console account; optional Event Synthesizing
is also off. Preflight stopped before UI interaction. No cleanup command, rule
mutation, or reboot was attempted. The owned lease remains `ready` with cleanup
pending. Resume only after enabling the normal UI permissions for Peekaboo in
that guest account; do not bypass the lab admission path or use a developer Mac.
Keep the lab's base fingerprint check.

## Rehearsal

1. Create a fresh desktop guest using the current lab admission procedure in
   [`remote-installer-lab.md`](remote-installer-lab.md). Install the public
   KeyPath 1.0.1 release from its official GitHub release asset and complete
   its setup. Do not install or update the session-runtime build yet.
2. Add a harmless sample rule and verify it works. Back up
   `~/.config/keypath` outside the app's install directory; record its file
   names and hashes without exposing any rule contents.
3. Capture the legacy service state before cleanup:

   ```bash
   sudo launchctl print system/com.keypath.kanata
   sudo launchctl print system/com.keypath.helper
   sudo launchctl print system/com.keypath.karabiner-vhiddaemon
   sudo launchctl print system/com.keypath.karabiner-vhidmanager
   sudo launchctl print system/com.keypath.logrotate
   ls -l /Library/PrivilegedHelperTools/com.keypath.helper
   find /Library/LaunchDaemons -maxdepth 1 -name 'com.keypath.*.plist' -print
   ```

   Record which expected items exist. A missing item is not a reason to create
   it; the guide is for cleanup of components actually installed by 1.0.1.
4. Follow the public guide literally, including its stop-and-check step before
   deleting files. Do not run a broad `rm -rf`, remove the Karabiner driver, or
   remove anything not named in the guide. Capture command output and any
   unexpected prompt or error.
5. Re-run the service and file checks. Confirm each named launchd service is
   absent, the listed KeyPath helper/plists are gone, and the backed-up user
   rules still match the original hashes.
6. Reboot the disposable guest and repeat the checks. This detects services
   that were unloaded temporarily but remain configured to return at login or
   boot.
7. Install the current session-runtime build only when a valid signed artifact
   is available. Complete its normal permission flow, restore/import the sample
   rule, and verify one remap. If the current artifact cannot be installed,
   record the cleanup rehearsal separately and leave the runtime-remap result
   unverified.

## Acceptance

- The cleanup guide's exact commands complete without undocumented changes.
- No listed 1.0.1 service or file returns after reboot.
- User rules remain intact.
- If step 7 is completed, the current runtime starts with normal consent and
  remaps the sample key.
- The guest is destroyed through `vm-lab`; the base fingerprint is unchanged.

## Results

| Date | 1.0.1 asset digest | macOS | Lease | Cleanup | Rule preservation | Reboot | Current runtime | Notes |
| ---- | ------------------ | ----- | ----- | ------- | ----------------- | ------ | ---------------- | ----- |
| 2026-11-21 | `cf4797c97b82e04081057bb7688389ab8f681d51e1e8b084a6887f8a68614296` | — | `cbx_af9cbb9f9e31` | not run | not run | not run | not run | Tart clone failed before guest creation (`utimes` permission error); vm-lab cleanup completed; no Parallels lease was touched. |
| 2026-11-21 | `cf4797c97b82e04081057bb7688389ab8f681d51e1e8b084a6887f8a68614296` | 26 | `cbx_7d9285bef732` | not run | not run | not run | not run | Parallels failed during lease SSH-key installation (`PrlJob_GetResult: Invalid argument`); vm-lab destroyed the owned lease and confirmed cleanup complete; no guest-side steps ran. |
| 2026-11-22 | `cf4797c97b82e04081057bb7688389ab8f681d51e1e8b084a6887f8a68614296` | 26.5.2 | `cbx_67d82d322f17` | blocked | not run | not run | not run | Guest booted and the installed app reports 1.0.1. UI preflight found Peekaboo Screen Recording and Accessibility ungranted in the guest console account; stopped before UI or cleanup. Lease is still ready; cleanup is pending. |
