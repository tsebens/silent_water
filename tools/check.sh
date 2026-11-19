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
  if grep -qE "SCRIPT ERROR|SHADER ERROR|Parse Error|Failed to load script" "$LOG_DIR/$name.log"; then rc=1; fi
  return $rc
}

step() { # name, rc
  if [ "$2" -eq 0 ]; then echo "PASS  $1"; else echo "FAIL  $1 (log: $LOG_DIR/$1.log)"; status=1; fi
}

run import 120 --import --quit; step import $?

# --fixed-fps runs the simulation as fast as the CPU allows instead of in
# real time, so tests that simulate whole dives finish in seconds.
run unit 600 --fixed-fps 60 res://tests/test_runner.tscn; rc=$?
grep -E "test\(s\) passed|^FAIL|PARSE FAIL" "$LOG_DIR/unit.log" | sed 's/^/      /'
step unit $rc

PORT=$(( 25000 + RANDOM % 5000 ))
run net_host 30 res://tests/net_smoke.tscn -- --host --port "$PORT" & host_pid=$!
sleep 1
run net_client 30 res://tests/net_smoke.tscn -- --join --port "$PORT"; client_rc=$?
wait $host_pid; host_rc=$?
step net_host $host_rc
step net_client $client_rc

# Multi-instance session: 1 host + 2 clients run scripted bots and compare state.
PORT=$(( 25000 + RANDOM % 5000 ))
HEADLESS=1 WAIT_ALL=1 PORT=$PORT GAME_ARGS=--autotest GODOT="$GODOT" \
  timeout 60 tools/launch.sh 3 >"$LOG_DIR/autotest.log" 2>&1; rc=$?
if grep -qE "SCRIPT ERROR|SHADER ERROR|Parse Error" "$LOG_DIR/autotest.log"; then rc=1; fi
python3 tools/compare_autotest.py "$LOG_DIR/autotest.log" 3 || rc=1
step autotest $rc

exit $status
