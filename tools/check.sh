#!/usr/bin/env bash
# Headless project check: import, unit tests, and a two-process network smoke test.
# Usage: tools/check.sh            (exits non-zero on any failure)
# Env:   GODOT  path to the Godot binary (default: godot)
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
LOG_DIR="${LOG_DIR:-$(mktemp -d)}"
status=0

run() { # name, timeout, args...
  local name="$1" t="$2"; shift 2
  timeout "$t" "$GODOT" --headless --path . "$@" >"$LOG_DIR/$name.log" 2>&1
  local rc=$?
  if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$LOG_DIR/$name.log"; then rc=1; fi
  return $rc
}

step() { # name, rc
  if [ "$2" -eq 0 ]; then echo "PASS  $1"; else echo "FAIL  $1 (log: $LOG_DIR/$1.log)"; status=1; fi
}

run import 120 --import --quit; step import $?

run unit 120 res://tests/test_runner.tscn; rc=$?
grep -E "test\(s\) passed|^FAIL|PARSE FAIL" "$LOG_DIR/unit.log" | sed 's/^/      /'
step unit $rc

PORT=$(( 25000 + RANDOM % 5000 ))
run net_host 30 res://tests/net_smoke.tscn -- --host --port "$PORT" & host_pid=$!
sleep 1
run net_client 30 res://tests/net_smoke.tscn -- --join --port "$PORT"; client_rc=$?
wait $host_pid; host_rc=$?
step net_host $host_rc
step net_client $client_rc

exit $status
