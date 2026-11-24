"""Build spike scenes: uv run python build.py [slug ...]  (default: all).

All or nothing. First every scene's own checks run (each module's `solids()`, which raises on a failed `expect`).
Then the scenes are built in dependency order; a scene's checks against the scenes it uses read their catalogue
entries as just rebuilt. If anything fails at either stage, the output tree is put back exactly as it was. A change
to a shared part (the control base, the gauge) therefore reaches Godot only if every scene that uses it still passes:
Godot propagates geometry through instancing instantly, but not the checks.
Building everything takes a few seconds and unchanged scenes come out byte-identical, so the default is the whole tree.
"""
import importlib
import json
import shutil
import sys
import tempfile
from pathlib import Path

from kitcad import GeometryError
from spike import OUT

ORDER = ["control_base", "gauge", "push_button", "guarded_toggle", "trackball", "map_keypad", "operator_seat", "sonar_console"]


def _check(mod) -> None:
    if mod.SLUG == "control_base":
        for size in mod.SIZES:
            mod.solids(*size)
    else:
        mod.solids()


if __name__ == "__main__":
    wanted = sys.argv[1:] or ORDER
    unknown = set(wanted) - set(ORDER)
    if unknown:
        sys.exit(f"unknown: {sorted(unknown)}; known: {ORDER}")
    mods = [importlib.import_module(f"components.{s}") for s in ORDER if s in wanted]
    failed = []
    for m in mods:
        try:
            _check(m)
        except GeometryError as e:
            failed.append(f"{m.SLUG}: {e}")
    if failed:
        sys.exit("checks failed, nothing written:\n  " + "\n  ".join(failed))
    with tempfile.TemporaryDirectory() as tmp:
        snapshot = Path(tmp) / "tree"
        if OUT.exists():
            shutil.copytree(OUT, snapshot)
        done = []
        try:
            for m in mods:
                done.append(json.dumps(m.build()))
        except GeometryError as e:
            if OUT.exists():
                shutil.rmtree(OUT)
            if snapshot.exists():
                shutil.copytree(snapshot, OUT)
            sys.exit(f"checks failed, nothing written (tree restored):\n  {m.SLUG}: {e}")
        print("\n".join(done))
