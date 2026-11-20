# Subprocess output must be drained while the child runs

`SubprocessRunner` read stdout and stderr only from its termination handler.
A child writing more than a pipe buffer could block waiting for a reader, so
it never exited and never invoked that handler. A healthy command then appeared
to time out. Sequentially reading the streams is also insufficient when the
child writes both.

A reproduction using the production runner with a no-op logger wrote 262,144
bytes to stdout followed by the same amount to stderr. Before the fix, the
runner timed out at two seconds. With concurrent draining, it exited zero and
returned exactly 262,144 bytes from each stream. A real subprocess regression
in `SubprocessRunnerTests` covers that case with a five-second bound.

Both pipes now drain on dispatch workers while the child runs. The termination
handler waits for those readers and assembles the result. The timeout stays
active until output collection completes, so an inherited pipe held open by a
descendant cannot silently remove the caller's timeout. This does not introduce
a process-tree kill policy or a limit on captured output size.

The migration process probe still has a separate synchronous `/bin/ps` path.
Move its callers to bounded async execution in a follow-up after validating
this shared runner; do not route it through a runner that waits for exit before
draining output.

## SystemProbeClient follow-up

The synchronous system-probe helper had the same wait-before-read ordering.
A standalone reproduction using the production implementation and a Python
child writing 262,144 bytes on each stream returned exit 15, only 65,536 bytes
of stdout and no stderr at a 0.5-second deadline. It was killed while blocked
on the full stdout pipe. Process discovery could therefore look empty under
a large listing even though the command itself was healthy.

The probe now uses the same internal ProcessOutputCapture as SubprocessRunner.
The identical reproduction returns exit zero and all 262,144 bytes on both
streams. Launch failure explicitly abandons the reserved readers. Regression
tests cover both cases. No public API, subprocess arguments, parsing rules or
probe timeout policy changes. This does not add a process-tree timeout policy
for arbitrary descendants holding inherited pipe descriptors.
