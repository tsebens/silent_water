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


FOLDER_SEGMENT_RE = re.compile(r"^[a-z0-9][a-z0-9_-]*$")


def models_dir(root: Path) -> Path:
    return root / "assets" / "models"


def check_folder(folder: str | None) -> str:
    """A folder under assets/models/ as a normalised POSIX string; "" is the root."""
    text = (folder or "").replace("\\", "/").strip("/")
    if text in ("", "."):
        return ""
    for seg in text.split("/"):
        if not FOLDER_SEGMENT_RE.match(seg):
            raise ValueError(f"invalid folder {folder!r}: segments use lowercase letters, digits, _ and -")
    return text


def folder_dir(root: Path, folder: str) -> Path:
    f = check_folder(folder)
    return models_dir(root) / f if f else models_dir(root)


def is_asset_dir(d: Path) -> bool:
    return (d / "asset.yaml").is_file()


def asset_dirs(root: Path) -> dict[str, Path]:
    """Every asset directory under assets/models/ (any depth), by slug. The walk does not descend into an asset."""
    found: dict[str, Path] = {}
    base = models_dir(root)
    if not base.is_dir():
        return found
    stack = [base]
    while stack:
        d = stack.pop()
        for sub in sorted(p for p in d.iterdir() if p.is_dir()):
            if is_asset_dir(sub):
                found.setdefault(sub.name, sub)
            else:
                stack.append(sub)
    return dict(sorted(found.items()))


def find_asset_dir(root: Path, slug: str) -> Path | None:
    return asset_dirs(root).get(check_slug(slug))


def all_manifest_paths(root: Path) -> list[Path]:
    """Every asset.yaml, sorted by slug."""
    return [d / "asset.yaml" for d in asset_dirs(root).values()]


def all_folders(root: Path) -> list[str]:
    """Every folder under assets/models/ that is not an asset (empty ones included), as sorted POSIX strings."""
    out: list[str] = []
    base = models_dir(root)
    if not base.is_dir():
        return out
    stack = [base]
    while stack:
        d = stack.pop()
        for sub in d.iterdir():
            if sub.is_dir() and not is_asset_dir(sub):
                out.append(sub.relative_to(base).as_posix())
                stack.append(sub)
    return sorted(out)


def enclosing_asset(root: Path, folder: str) -> Path | None:
    """The asset directory that `folder` is, or is inside, if any."""
    d = folder_dir(root, folder)
    base = models_dir(root)
    while d != base and base in d.parents:
        if is_asset_dir(d):
            return d
        d = d.parent
    return None


def asset_dir(root: Path, slug: str) -> Path:
    """Committed deliverables: manifest, locked concept, turnaround, brief, final GLB. Found wherever it lives under
    assets/models/; an asset that does not exist yet is placed at the root."""
    return find_asset_dir(root, slug) or models_dir(root) / check_slug(slug)


def work_dir(root: Path, slug: str) -> Path:
    """Git-ignored scratch: rejected variants and raw provider meshes."""
    return root / ".asset_work" / check_slug(slug)


def manifest_path(root: Path, slug: str) -> Path:
    return asset_dir(root, slug) / "asset.yaml"


def posix_rel(root: Path, p: Path) -> str:
    """`p` relative to `root`, forward slashes on every OS: the one form stored or printed."""
    return p.relative_to(root).as_posix()

