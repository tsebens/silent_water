"""Build spike scenes: uv run python build.py [slug ...]  (default: all).

Two phases. First every scene's checks run (each module's `solids()`, which raises on a failed `expect`); only if all
pass does anything get written. A change to a shared part (the control base) is therefore checked against every scene
that uses it before Godot can see it: Godot propagates geometry through instancing instantly, but not the checks.
Building everything takes a few seconds and unchanged scenes come out byte-identical, so the default is the whole tree.
"""
import importlib
import json
import sys

from kitcad import GeometryError

ORDER = ["control_base", "push_button", "guarded_toggle", "trackball", "map_keypad", "operator_seat", "sonar_console"]


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
    for m in mods:
        print(json.dumps(m.build()))
