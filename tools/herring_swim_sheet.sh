#!/usr/bin/env bash
# Render the herring swim demo (tests/herring_swim_demo.tscn) as a contact sheet: top-down row over side row, one loop.
# Usage: xvfb-run -a tools/herring_swim_sheet.sh [out.png]   (default: the herring's review folder)
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-assets/models/organics/herring/review/swim_sheet.png}"
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
"${GODOT:-godot}" --path . --rendering-driver vulkan res://tests/herring_swim_shot.tscn -- "$out" 2>&1 | tail -5
test -s "$out"
