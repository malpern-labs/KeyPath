#!/bin/bash
# Sample host resource pressure while a CI job runs, for the manually
# dispatched two-lane qualification on the Mini (ci.yml, workflow_dispatch).
#
#   record-host-resources.sh OUT.tsv [INTERVAL_SECONDS]
#
# Appends one row per interval until killed. Read-only: it runs vm_stat,
# sysctl, df and memory_pressure and never changes the machine. Each row is
# UTC time, load averages, free memory %, swap used MiB, free disk GiB on the
# volume holding the runner workspace, and the count of swift-build /
# swift-test / xctest processes (both runners included, since they share the
# host). A sample that fails writes "na" rather than stopping the loop.

set -uo pipefail

out=${1:?usage: record-host-resources.sh OUT.tsv [INTERVAL_SECONDS]}
interval=${2:-15}
workspace=${GITHUB_WORKSPACE:-$PWD}

printf 'utc\tload1\tload5\tload15\tmem_free_pct\tswap_used_mib\tdisk_free_gib\tswift_procs\n' > "$out"

while :; do
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  load=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1"\t"$2"\t"$3}')
  [[ -n "$load" ]] || load=$'na\tna\tna'
  mem=$(memory_pressure 2>/dev/null | awk -F': ' '/free percentage/ {gsub("%","",$2); print $2}')
  swap=$(sysctl -n vm.swapusage 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="used") {v=$(i+2); sub("M","",v); print v}}')
  disk=$(df -Pk "$workspace" 2>/dev/null | awk 'NR==2 {printf "%.1f", $4/1048576}')
  procs=$(pgrep -f 'swift-build|swift-test|xctest' 2>/dev/null | wc -l | tr -d ' ')
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ts" "$load" "${mem:-na}" "${swap:-na}" "${disk:-na}" "${procs:-na}" >> "$out"
  sleep "$interval"
done
