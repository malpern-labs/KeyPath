# Migration process discovery must not block the wizard

The migration page and external-Kanata stop page previously invoked a synchronous
`ps` probe from their appearance callbacks. Reading its pipe before waiting avoided
a pipe-capacity deadlock but still blocked the main actor until the child exited.

Discovery now uses the shared async subprocess runner with a five-second timeout.
The wizard host operations are async, and view-owned `.task` callbacks perform
initial discovery. Cancellation prevents the migration page from publishing an
obsolete discovery result. Failed process execution does not parse partial output.
A failed follow-up probe remains unknown, so it cannot turn a failed stop into
success. Migration actions stay disabled until initial discovery finishes, and a
late discovery cannot overwrite an already chosen config. The existing
external-process priority and config-path parsing are retained.

Regression tests inject subprocess results without spawning real processes or
sleeping. They cover the timeout contract, failed execution, config parsing,
external-process priority and unrelated process rejection.

The stop page completes when its own successful discovery proves no external
process remains. A failed discovery instead keeps Retry available. Three
wizard-operation tests cover verified absence, failed discovery and a live
external process, in addition to the five probe/parser tests.
