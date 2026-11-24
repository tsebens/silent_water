"""Shared conventions for the scene-assembly spike (#345).

Every scene is built by one script in `components/` that (1) makes its CAD solids, (2) checks them against its brief
with `expect`, (3) writes one GLB per rigid set, (4) writes the Godot scene that assembles its solids and the scenes it
reuses, and (5) writes its catalogue entry, `component.yaml`. Nothing is written unless every check passes.

Frames (metres in Godot, millimetres in CAD): X right, Y up, Z out of the mount face. A panel component's back sits on
Z=0, centred on the origin. Furniture and stations stand on the floor at Y=0; a station's back is on Z=0 and its
front, where the operator is, is +Z; a seated occupant faces -Z.
"""
from __future__ import annotations

from pathlib import Path

import yaml

from kitcad import REPO

OUT = REPO / "assets" / "models" / "spike"
MODULE_MM = 60.0          # the control-panel module: bases come in whole modules
BASE_GAP_MM = 4.0         # a base is a module minus this, so neighbouring bases never touch
PLATE_T_MM = 6.0          # base plate thickness: components mount their parts at Z = PLATE_T_MM


def out_dir(group: str, slug: str) -> Path:
    return OUT / group / slug


def res(path: Path) -> str:
    return "res://" + path.resolve().relative_to(REPO).as_posix()


def base_size_mm(cols: int, rows: int) -> tuple[float, float]:
    return cols * MODULE_MM - BASE_GAP_MM, rows * MODULE_MM - BASE_GAP_MM


def base_glb(cols: int, rows: int) -> str:
    return res(out_dir("kit", "control_base") / f"control_base_{cols}x{rows}.glb")


def scene_path(group: str, slug: str) -> str:
    return res(out_dir(group, slug) / f"{slug}.tscn")


def write_entry(group: str, slug: str, entry: dict) -> Path:
    p = out_dir(group, slug) / "component.yaml"
    p.parent.mkdir(parents=True, exist_ok=True)
    body = {"slug": slug, **entry, "built_by": f"tools/cad_spike/components/{slug}.py"}
    p.write_text(yaml.safe_dump(body, sort_keys=False, width=110))
    return p


def entry(group: str, slug: str) -> dict:
    p = out_dir(group, slug) / "component.yaml"
    if not p.is_file():
        raise FileNotFoundError(f"{slug} has no catalogue entry: build it first")
    return yaml.safe_load(p.read_text())


def quiet_noise(scene, max_intensity: float = 0.02, clank_rate: float = 1.0) -> object:
    """A NoiseProfile sub-resource for a control (handling noise, linear intensity)."""
    script = scene.ext("Script", "res://src/interact/noise_profile.gd")
    return scene.sub("Resource", "noise", {"script": script, "idle_intensity": 0.0, "max_intensity": max_intensity,
                                           "clank_rate": clank_rate, "exponent": 2.0})
