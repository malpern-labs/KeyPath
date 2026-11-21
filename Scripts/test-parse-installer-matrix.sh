#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARSER="$SCRIPT_DIR/parse-installer-matrix.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

cat > "$TMP_ROOT/passed.log" <<'EOF'
[1/3] Testing KeyPathTests.InstallerEnginePlanTests/testBuildPlan
[2/3] Testing KeyPathTests.InstallerEngineEndToEndTests/testInstall
[3/3] Testing KeyPathTests.InstallerEngineHealthCheckTests/testHealth
EOF

TEST_STATUS=passed INSTALLER_MATRIX_OUT_ROOT="$TMP_ROOT/passed-results" \
  "$PARSER" "$TMP_ROOT/passed.log" >/dev/null

python3 - "$TMP_ROOT/passed-results/latest/matrix-results.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    report = json.load(source)

assert report["overallStatus"] == "pass", report
assert report["failedLaneCount"] == 0, report
assert report["unverifiedLaneCount"] == 0, report
assert [lane["passCount"] for lane in report["lanes"]] == [1, 1, 1], report
PY

cat > "$TMP_ROOT/failed.log" <<'EOF'
[1/1] Testing KeyPathTests.InstallerEngineTests/testInstall
EOF

if TEST_STATUS=failed INSTALLER_MATRIX_OUT_ROOT="$TMP_ROOT/failed-results" \
  "$PARSER" "$TMP_ROOT/failed.log" >/dev/null; then
  echo "Expected a failed test run to fail matrix parsing." >&2
  exit 1
fi

python3 - "$TMP_ROOT/failed-results/latest/matrix-results.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    report = json.load(source)

assert report["overallStatus"] == "fail", report
assert report["unverifiedLaneCount"] == 1, report
assert report["lanes"][0]["status"] == "unverified", report
assert report["lanes"][0]["failCount"] == 0, report
PY

echo "Installer matrix parser parallel-output checks passed."
