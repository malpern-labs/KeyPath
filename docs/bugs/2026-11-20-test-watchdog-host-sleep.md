# Test watchdog deadline across host sleep

The safe test runner counted one-second ticks to enforce its 240-second test
budget. Host sleep suspends those ticks. A full run on the Air reported 1,645
seconds of test wall time before the watchdog fired.

The watchdog now compares elapsed wall time against the existing budget. After
the host resumes, it cancels an overdue process on the next check using the
existing cleanup and exit code 124. A system clock adjustment can affect this
deadline, as it can the runner's duration reporting. The runner also waits
for the watchdog to finish before removing its exit and timeout files.

Run the deterministic regression with
`python3 -m unittest Scripts.tests.test_test_deadline`. It covers a simulated
sleep jump, normal expiry, early exit, and an already exited process.
