"""Render a generated scene in Godot, and lay renders beside concept art for review.

Rendering needs a display and a Vulkan driver. Without DISPLAY it runs under `xvfb-run` (software Vulkan:
`mesa-vulkan-drivers`). The Godot binary is $GODOT, else `godot` on PATH.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import numpy as np
import yaml

from cadkit import library

SHOT_SCENE = "res://tests/scene_shot.tscn"
SHEET_H = 520


def godot() -> str:
    exe = os.environ.get("GODOT") or shutil.which("godot")
    if not exe:
        raise RuntimeError("no Godot: set $GODOT or put `godot` on PATH")
    return exe


def scene_dir(slug: str) -> Path:
    p = library.entry_path(slug)
    if p is None:
        raise FileNotFoundError(f"no generated scene called {slug!r}")
    return p.parent


def _wrap_glb(slug: str, glb: str) -> str:
    """A throwaway scene (build/wrap/<slug>.tscn, not committed) that instances a solid set's one GLB."""
    d = library.REPO / "build" / "wrap"
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{slug}.tscn").write_text(
        f'[gd_scene load_steps=2 format=3]\n\n[ext_resource type="PackedScene" path="{glb}" id="1"]\n\n'
        f'[node name="Wrap" type="Node3D"]\n\n[node name="Solids" parent="." instance=ExtResource("1")]\n')
    return f"res://build/wrap/{slug}.tscn"


def parse_pose(items: list[str]) -> dict[str, tuple[float, float, float]]:
    """`bone=rx,ry,rz` (degrees about X, then Y, then Z) for each item."""
    pose = {}
    for it in items:
        name, _, vals = it.partition("=")
        parts = [float(x) for x in vals.split(",")] if vals else []
        if not name or len(parts) != 3:
            raise ValueError(f"pose {it!r}: expected bone=rx,ry,rz")
        pose[name] = (parts[0], parts[1], parts[2])
    return pose


def rotation_matrix(rx: float, ry: float, rz: float) -> np.ndarray:
    """3x3 rotation for degrees about X, then Y, then Z (the order of `solids.at`)."""
    a, b, c = np.radians([rx, ry, rz])
    mx = np.array([[1, 0, 0], [0, np.cos(a), -np.sin(a)], [0, np.sin(a), np.cos(a)]])
    my = np.array([[np.cos(b), 0, np.sin(b)], [0, 1, 0], [-np.sin(b), 0, np.cos(b)]])
    mz = np.array([[np.cos(c), -np.sin(c), 0], [np.sin(c), np.cos(c), 0], [0, 0, 1]])
    return mz @ my @ mx


def posed_surfaces(glb: Path, pose: dict[str, tuple[float, float, float]]) -> list[tuple]:
    """A skinned GLB's surfaces (role, positions, normals) with the named bones rotated, by linear blend skinning."""
    from cadkit.skeleton import skin_positions
    from cadkit.skin_checks import skeleton_of
    from cadkit.solids import read_skinned
    data = read_skinned(glb)
    skel = skeleton_of(data["bones"])
    unknown = sorted(set(pose) - set(skel.names()))
    if unknown:
        raise ValueError(f"no bone {unknown[0]!r}: {skel.names()}")
    rots = {k: rotation_matrix(*v) for k, v in pose.items()}
    out = []
    for sf in data["surfaces"]:
        pos = skin_positions(skel, sf["joints"].astype(int), sf["weights"].astype(float), sf["pos"] * 1000.0, rots) / 1000.0
        pos = pos.astype(np.float32)
        tri = pos.reshape(-1, 3, 3)
        n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        out.append((sf["role"], pos, np.repeat(n, 3, axis=0).astype(np.float32)))
    return out


def skinned_glb(slug: str) -> Path:
    """The scene's skinned GLB: its entry's `glb`, else the one skinned GLB among its files."""
    from cadkit.solids import read_glb
    folder = scene_dir(slug)
    entry = library.entry(slug)
    names = [Path(entry["glb"]).name] if entry.get("glb") else [f for f in entry.get("files", []) if f.endswith(".glb")]
    for n in names:
        if (folder / n).is_file() and "bones" in read_glb(folder / n):
            return folder / n
    raise ValueError(f"{slug} has no skinned GLB to pose")


def posed_scene(slug: str, pose: dict[str, tuple[float, float, float]]) -> str:
    """A throwaway scene (build/wrap, not committed) of the skinned GLB with `pose` applied, as a static mesh."""
    from cadkit.solids import write_glb
    d = library.REPO / "build" / "wrap"
    d.mkdir(parents=True, exist_ok=True)
    write_glb(d / f"{slug}_posed.glb", f"{slug}_posed", posed_surfaces(skinned_glb(slug), pose))
    return _wrap_glb(f"{slug}_posed", f"res://build/wrap/{slug}_posed.glb")


def render(slug: str, out: Path | None = None, cameras: Path | None = None,
           pose: dict[str, tuple[float, float, float]] | None = None) -> list[Path]:
    """Render the scene from its review cameras (`review/cameras.json`), or from automatic ones. Returns the PNGs.
    With `pose` (bone -> degrees about X, Y, Z) the scene's skinned GLB is rendered alone in that pose, from automatic cameras."""
    entry = library.entry(slug)
    if pose:
        entry = {**entry, "scene": posed_scene(slug, pose)}
        cameras = Path("/nonexistent")
    elif "scene" not in entry:
        if not entry.get("glb"):
            raise ValueError(f"{slug} is a set of solids with no scene of its own; render a scene that uses it")
        entry = {**entry, "scene": _wrap_glb(slug, entry["glb"])}   # a lone GLB: render it in a throwaway scene
    out = out or library.REPO / "build" / "renders" / slug
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    cams = cameras or scene_dir(slug) / "review" / "cameras.json"
    subprocess.run([godot(), "--headless", "--path", str(library.REPO), "--import"], capture_output=True, timeout=900)
    cmd = [godot(), "--path", str(library.REPO), "--rendering-driver", "vulkan", SHOT_SCENE, "--", entry["scene"], str(out)]
    if cams.is_file():
        cmd.append(str(cams))
    elif pose:
        cmd.append("--top")                   # a posed render also gets a top-down view
    if not os.environ.get("DISPLAY"):
        if not shutil.which("xvfb-run"):
            raise RuntimeError("no display and no xvfb-run: install xvfb and mesa-vulkan-drivers")
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 1280x800x24", *cmd]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    shots = sorted(out.glob("*.png"))
    if not shots:
        tail = "\n".join((proc.stdout + proc.stderr).strip().splitlines()[-15:])
        raise RuntimeError(f"Godot rendered nothing (exit {proc.returncode}):\n{tail}")
    return shots


PALETTE_SCENE = "res://tests/palette_sheet.tscn"


def palette_sheets(out: Path | None = None) -> list[Path]:
    """Render the swatch sheets (tests/palette_sheet.tscn): every swatch and role under four white lights and the
    stealth red. Default out: docs/images/palette/."""
    out = out or library.REPO / "docs" / "images" / "palette"
    out.mkdir(parents=True, exist_ok=True)
    subprocess.run([godot(), "--headless", "--path", str(library.REPO), "--import"], capture_output=True, timeout=900)
    cmd = [godot(), "--path", str(library.REPO), "--rendering-driver", "vulkan", PALETTE_SCENE, "--", str(out)]
    if not os.environ.get("DISPLAY"):
        if not shutil.which("xvfb-run"):
            raise RuntimeError("no display and no xvfb-run: install xvfb and mesa-vulkan-drivers")
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 1800x1700x24", *cmd]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=900)
    shots = sorted(out.glob("palette_*.png"))
    if "SHEET" not in proc.stdout:
        tail = "\n".join((proc.stdout + proc.stderr).strip().splitlines()[-15:])
        raise RuntimeError(f"Godot rendered no sheet (exit {proc.returncode}):\n{tail}")
    return shots


def _label(im, text: str):
    from PIL import ImageDraw
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 8 * len(text) + 16, 26], fill=(0, 0, 0))
    d.text((8, 7), text, fill=(255, 255, 255))
    return im


def _fit(path: Path):
    from PIL import Image
    im = Image.open(path).convert("RGB")
    return im.resize((round(im.width * SHEET_H / im.height), SHEET_H))


def sheet(slug: str, renders: Path | None = None, pose: dict[str, tuple[float, float, float]] | None = None) -> list[Path]:
    """Render the scene and write its review sheets into `<scene>/review/`: each concept image beside the render from its camera
    (pairs come from `brief.yaml`: a concept image with a `camera:`), and `views.png` with the other renders."""
    from PIL import Image
    if renders is None:                      # always render afresh: a sheet must show the scene as it is now
        renders = library.REPO / "build" / "renders" / slug
        render(slug, renders)
    folder = scene_dir(slug)
    review = folder / "review"
    review.mkdir(exist_ok=True)
    (review / ".gdignore").touch()
    made, paired = [], set()
    brief = folder / "brief.yaml"
    if brief.is_file():
        for img in (yaml.safe_load(brief.read_text()).get("concept") or {}).get("images", []):
            cam = img.get("camera")
            shot = renders / f"{cam}.png"
            if not cam or not shot.is_file():
                continue
            a = _label(_fit(library.REPO / img["path"]), "concept")
            b = _label(_fit(shot), f"render: {cam}")
            s = Image.new("RGB", (a.width + b.width + 8, SHEET_H), (40, 40, 40))
            s.paste(a, (0, 0))
            s.paste(b, (a.width + 8, 0))
            p = review / f"{cam}_vs_concept.png"
            s.save(p, optimize=True)
            made.append(p)
            paired.add(cam)
    rest = [p for p in sorted(renders.glob("*.png")) if p.stem not in paired]
    if pose:                                  # one extra view: the skinned mesh with the bones rotated
        posed = render(slug, library.REPO / "build" / "renders" / f"{slug}_posed", pose=pose)
        # the three-quarter view, and the top-down one where a bend in the body reads best
        rest += [next((p for p in posed if p.stem == name), posed[0]) for name in ("three_quarter", "top")]
        posed_views = set(rest[-2:])
    if rest:
        tiles = [_label(Image.open(p).convert("RGB").resize((480, 300)), f"posed: {p.stem}" if pose and p in posed_views else p.stem)
                 for p in rest]
        cols = 2
        g = Image.new("RGB", (cols * 480, ((len(tiles) + cols - 1) // cols) * 300))
        for i, t in enumerate(tiles):
            g.paste(t, ((i % cols) * 480, (i // cols) * 300))
        p = review / "views.png"
        g.save(p, optimize=True)
        made.append(p)
    return made
