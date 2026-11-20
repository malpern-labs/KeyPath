#!/bin/bash
# Return 0 when a live test process reaches its wall-clock deadline, 1 if it exits.
# Check elapsed time after waking: counting sleep iterations ignores host sleep.
keypath_wait_for_test_deadline() {
  local test_pid="$1" timeout_seconds="$2" started_at="$3"
  local now
  while kill -0 "$test_pid" 2>/dev/null; do
    now="$(date +%s)"
    if [ "$((now - started_at))" -ge "$timeout_seconds" ]; then
      return 0
    fi
    sleep 1
  done
  return 1
}
