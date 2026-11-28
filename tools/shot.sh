#!/usr/bin/env bash
# Render a review shot of the game: one camera, one depth (or a sheet of depths), single player, no networking.
# Usage: tools/shot.sh <camera> [--depth <m>] [--light day|night] [--out <png>] [--size WxH] [--sheet <d1,d2,..>]
#                      [--frames <n>] [--renderer forward_plus|mobile|gl_compatibility] [--timeout <s>]
# Cameras: the program's ids (midships_forward, pilot_view, ...), pilot_eye, outside_<bow|stern|port|starboard|top|bottom>.
# Needs a display: on a headless runner use `xvfb-run -a tools/shot.sh ...` after the setup-render action.
# Env:   GODOT  Godot binary (default: godot).  SHOT_TIMEOUT  hard timeout in seconds (default 240, --timeout wins).
# Output: the PNG at --out (default .asset_work/shots/<camera>_<depth>m.png) and the Godot log beside it as <png>.log.
# Exits 0 only when the PNG was written; 124 on timeout. A sheet's captions say which renderer drew it.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
TIMEOUT="${SHOT_TIMEOUT:-240}"
RENDERER=""
args=()
out=""
size="1280x720"
while [ $# -gt 0 ]; do
  case "$1" in
    --renderer) RENDERER="${2:?--renderer needs a value}"; shift 2 ;;
    --timeout) TIMEOUT="${2:?--timeout needs seconds}"; shift 2 ;;
    --out) out="${2:?--out needs a path}"; shift 2 ;;
    --size) size="${2:?--size needs WxH}"; args+=(--size "$size"); shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) args+=("$1"); shift ;;
  esac
done
camera="${args[0]:-shot}"
if [ -z "$out" ]; then
  mkdir -p .asset_work/shots
  out=".asset_work/shots/${camera}.png"
fi
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
mkdir -p "$(dirname "$out")"
log="${out%.png}.log"
rm -f "$out"
gargs=(--path . --resolution "$size")
[ -n "$RENDERER" ] && gargs+=(--rendering-method "$RENDERER")
# The scene is res://tests/world_shot.tscn; user args follow `--`. It starts no networking and reads no input.
timeout --kill-after=10 "$TIMEOUT" "$GODOT" "${gargs[@]}" res://tests/world_shot.tscn -- "${args[@]}" --out "$out" >"$log" 2>&1
rc=$?
if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then echo "shot: timed out after ${TIMEOUT}s (log: $log)" >&2; exit 124; fi
if grep -qE "SCRIPT ERROR|SHADER ERROR|Parse Error|Failed to load script" "$log"; then
  echo "shot: Godot reported errors (log: $log)" >&2; grep -E "SCRIPT ERROR|SHADER ERROR|Parse Error" "$log" | head -5 >&2; exit 1
fi
if [ $rc -ne 0 ] || [ ! -s "$out" ]; then echo "shot: failed, rc=$rc (log: $log)" >&2; exit 1; fi
grep -E "^\[shot\]" "$log"
echo "$out"
