"""The asset library: where generated scenes live, their catalogue entries, and the conventions they share.

Every generated scene has a folder `assets/models/<group>/<slug>/` holding its GLBs, its `.tscn` and its catalogue
entry `component.yaml`, all written by one build script, `tools/cadkit/scenes/<slug>.py`. Groups: `kit` (controls,
displays and their shared parts), `furniture`, `stations`.

Frames (metres in Godot, millimetres in CAD): X right, Y up, Z out of the mount face. A panel part's back sits on
Z=0, centred on the origin. Furniture and stations stand on the floor at Y=0; a station's back is on Z=0 and its
front, where the operator is, is +Z; a seated occupant faces -Z.

A build never writes into the repository directly: it stages the whole tree under a temporary root (`set_root`) and
the files are promoted only if every scene passes (cadkit/build.py). This module imports nothing heavy, so reading
the catalogue does not load the CAD kernel.
"""
from __future__ import annotations

from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[3]
MODELS = REPO / "assets" / "models"
MODELS_RES = "res://assets/models"
PALETTE_FILE = REPO / "assets" / "style_bible" / "kit_palette.yaml"
GROUPS = ("kit", "furniture", "stations")

MODULE_MM = 60.0          # the control-panel module: bases come in whole modules
BASE_GAP_MM = 4.0         # a base is a module minus this, so neighbouring bases never touch
PLATE_T_MM = 6.0          # base plate thickness: controls mount their parts at Z = PLATE_T_MM

_root: Path = MODELS
_written: list[Path] = []
_modules: dict = {}


def set_root(path: Path) -> None:
    """Where scene folders are written and read (the repository's models folder, or a staging copy of it)."""
    global _root
    _root = Path(path)


def root() -> Path:
    return _root


def note(path: Path) -> None:
    """Record a file a build wrote, so the build knows exactly what each scene generates."""
    _written.append(Path(path))


def take_written() -> list[Path]:
    out = list(_written)
    _written.clear()
    return out


def register(modules: dict) -> None:
    global _modules
    _modules = modules


def scene_module(slug: str):
    """Another scene's build module, for the helpers it exposes (declare the slug in USES)."""
    return _modules[slug]


def out_dir(group: str, slug: str) -> Path:
    return _root / group / slug


def res(path: Path) -> str:
    return f"{MODELS_RES}/{Path(path).resolve().relative_to(_root.resolve()).as_posix()}"


def entry_path(slug: str) -> Path | None:
    hits = sorted(_root.glob(f"*/{slug}/component.yaml"))
    return hits[0] if hits else None


def entry(slug: str) -> dict:
    """A generated scene's catalogue entry. During a build this is the entry as just rebuilt."""
    p = entry_path(slug)
    if p is None:
        raise FileNotFoundError(f"{slug} has no catalogue entry: is it in this scene's USES?")
    return yaml.safe_load(p.read_text())


def scene_path(slug: str) -> str:
    return entry(slug)["scene"]


def write_entry(group: str, slug: str, body: dict) -> Path:
    """Write a scene's catalogue entry. Call it last: it lists the files the build wrote."""
    p = out_dir(group, slug) / "component.yaml"
    p.parent.mkdir(parents=True, exist_ok=True)
    files = sorted({f.name if f.parent == p.parent else f.relative_to(p.parent).as_posix() for f in _written
                    if p.parent in f.parents} | {"component.yaml"})
    full = {"slug": slug, "group": group, **body, "built_by": f"tools/cadkit/scenes/{slug}.py", "files": files}
    p.write_text(yaml.safe_dump(full, sort_keys=False, width=110))
    note(p)
    return p


def base_size_mm(cols: int, rows: int) -> tuple[float, float]:
    return cols * MODULE_MM - BASE_GAP_MM, rows * MODULE_MM - BASE_GAP_MM


def base_glb(cols: int, rows: int) -> str:
    return res(out_dir("kit", "control_base") / f"control_base_{cols}x{rows}.glb")


def quiet_noise(scene, max_intensity: float = 0.02, clank_rate: float = 1.0) -> object:
    """A NoiseProfile sub-resource for a control (handling noise, linear intensity)."""
    script = scene.ext("Script", "res://src/interact/noise_profile.gd")
    return scene.sub("Resource", "noise", {"script": script, "idle_intensity": 0.0, "max_intensity": max_intensity,
                                           "clank_rate": clank_rate, "exponent": 2.0})


def palette() -> dict[str, tuple[float, float, float]]:
    """The kit palette by role, as the style bible gives it (sRGB, 0..1)."""
    doc = yaml.safe_load(PALETTE_FILE.read_text())
    return {role: tuple(float(c) for c in rgb[:3]) for role, rgb in doc["colours"].items()}
