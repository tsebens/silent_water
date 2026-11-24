"""Render a generated scene in Godot, and lay renders beside concept art for review.

Rendering needs a display and a Vulkan driver. Without DISPLAY it runs under `xvfb-run` (software Vulkan:
`mesa-vulkan-drivers`). The Godot binary is $GODOT, else `godot` on PATH.
"""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

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


def render(slug: str, out: Path | None = None, cameras: Path | None = None) -> list[Path]:
    """Render the scene from its review cameras (`review/cameras.json`), or from automatic ones. Returns the PNGs."""
    entry = library.entry(slug)
    if "scene" not in entry:
        raise ValueError(f"{slug} is a set of solids with no scene of its own; render a scene that uses it")
    out = out or library.REPO / "build" / "renders" / slug
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    cams = cameras or scene_dir(slug) / "review" / "cameras.json"
    subprocess.run([godot(), "--headless", "--path", str(library.REPO), "--import"], capture_output=True, timeout=900)
    cmd = [godot(), "--path", str(library.REPO), "--rendering-driver", "vulkan", SHOT_SCENE, "--", entry["scene"], str(out)]
    if cams.is_file():
        cmd.append(str(cams))
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


def sheet(slug: str, renders: Path | None = None) -> list[Path]:
    """Write the scene's review sheets into `<scene>/review/`: each concept image beside the render from its camera
    (pairs come from `brief.yaml`: a concept image with a `camera:`), and `views.png` with the other renders."""
    from PIL import Image
    renders = renders or library.REPO / "build" / "renders" / slug
    if not renders.is_dir() or not list(renders.glob("*.png")):
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
    if rest:
        tiles = [_label(Image.open(p).convert("RGB").resize((480, 300)), p.stem) for p in rest]
        cols = 2
        g = Image.new("RGB", (cols * 480, ((len(tiles) + cols - 1) // cols) * 300))
        for i, t in enumerate(tiles):
            g.paste(t, ((i % cols) * 480, (i // cols) * 300))
        p = review / "views.png"
        g.save(p, optimize=True)
        made.append(p)
    return made
