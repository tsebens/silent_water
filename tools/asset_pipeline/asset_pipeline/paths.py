"""Repository layout: where manifests, deliverables and scratch work live."""
from __future__ import annotations

import os
import re
from pathlib import Path

SLUG_RE = re.compile(r"^[a-z][a-z0-9_]*$")


def repo_root() -> Path:
    """The repo root: $ASSET_PIPELINE_ROOT, else the nearest parent holding project.godot."""
    env = os.environ.get("ASSET_PIPELINE_ROOT")
    if env:
        return Path(env).resolve()
    for p in [Path.cwd().resolve(), *Path.cwd().resolve().parents]:
        if (p / "project.godot").is_file():
            return p
    return Path(__file__).resolve().parents[3]


def check_slug(slug: str) -> str:
    if not SLUG_RE.match(slug):
        raise ValueError(f"invalid slug {slug!r}: use lowercase letters, digits and underscores, starting with a letter")
    return slug


def asset_dir(root: Path, slug: str) -> Path:
    """Committed deliverables: manifest, locked concept, turnaround, brief, final GLB."""
    return root / "assets" / "models" / check_slug(slug)


def work_dir(root: Path, slug: str) -> Path:
    """Git-ignored scratch: rejected variants and raw provider meshes."""
    return root / ".asset_work" / check_slug(slug)


def manifest_path(root: Path, slug: str) -> Path:
    return asset_dir(root, slug) / "asset.yaml"
