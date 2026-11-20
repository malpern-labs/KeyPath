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
