#!/usr/bin/env bash
# Launch a local crew: one host and N-1 clients, tiled on screen.
# Usage: tools/launch.sh [N=2] [extra godot args...]
#   N        total instances, 1-4 (default 2)
# Env:
#   GODOT     Godot binary (default: godot)
#   PORT      port to use (default 24550)
#   HEADLESS  set to 1 to run without windows (for CI or smoke checks)
#   GAME_ARGS extra game arguments for every instance (e.g. "--tilt-test")
#   WAIT_ALL  set to 1 to wait for every instance to exit (default: stop all
#             when the first one exits)
# Ctrl+C stops every instance.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
N="${1:-2}"; shift || true
PORT="${PORT:-24550}"
if ! [[ "$N" =~ ^[1-4]$ ]]; then echo "N must be 1-4" >&2; exit 2; fi

W=960; H=540
pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

window_args() { # index -> godot window args
  local i="$1"
  if [ "${HEADLESS:-0}" = "1" ]; then echo "--headless"; return; fi
  echo "--windowed --resolution ${W}x${H} --position $(( (i % 2) * W )),$(( (i / 2) * H ))"
}

# shellcheck disable=SC2046
"$GODOT" --path . $(window_args 0) "$@" -- --host --port "$PORT" --name "Crew1" ${GAME_ARGS:-} & pids+=($!)
sleep 1
for (( i = 1; i < N; i++ )); do
  # shellcheck disable=SC2046
  "$GODOT" --path . $(window_args "$i") "$@" -- --join --port "$PORT" --name "Crew$((i + 1))" ${GAME_ARGS:-} & pids+=($!)
done
if [ "${WAIT_ALL:-0}" = "1" ]; then wait "${pids[@]}"; else wait -n "${pids[@]}"; fi
