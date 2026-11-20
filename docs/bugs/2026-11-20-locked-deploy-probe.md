# Locked-screen deployment probe and pipefail

The staged developer deployment on the Mini installed signed master 7537f7e07
and passed bundle verification, but its runtime check failed while loginwindow
held Secure Input. The script was supposed to distinguish this locked-session
wait from a broken installed app.

Under `set -o pipefail`, `ioreg -l -w0 | grep -q` returned 141: grep found
kCGSSessionSecureInputPID and exited before ioreg finished writing, so ioreg
received SIGPIPE. The conditional incorrectly treated that as no Secure Input.
The same live read with ordinary grep redirected to /dev/null returned zero.
The fix drains all input rather than disabling pipefail or ignoring ioreg errors.

Evidence: Mini deployment log at
`~/keypath-master-final.mhBaV0/deploy-mini.log`; installed executable SHA-256
`dc88b62d078dad6bed504695ea0333d044c24284ebb99d5a74dc5207de8a1f58`.
The log's worker absence is real while locked. Correct classification does not
prove remapping or bypass the need to verify runtime after unlock. No permission,
password or Keychain settings were changed.
