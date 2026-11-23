"""Folders and moves under assets/models/. A move rewrites every repo path recorded inside the moved assets:
the manifest, the check reports, and the `res://` references in the exported .tscn and .glb.import files."""
from __future__ import annotations

import json
import shutil
from pathlib import Path
from typing import Any

import yaml

from . import paths
from .manifest import Manifest

MODELS = "assets/models"


def _under(s: str, old: str) -> bool:
    return s == old or s.startswith(old + "/")


def _rewrite(node: Any, old: str, new: str) -> Any:
    if isinstance(node, dict):
        return {k: _rewrite(v, old, new) for k, v in node.items()}
    if isinstance(node, list):
        return [_rewrite(v, old, new) for v in node]
    if isinstance(node, str) and _under(node, old):
        return new + node[len(old):]
    return node


def _rewrite_text(text: str, old: str, new: str) -> str:
    return text.replace(f"res://{old}/", f"res://{new}/")


def rewrite_tree(root: Path, where: Path, old: str, new: str) -> list[str]:
    """Rewrite references to the repo path `old` as `new` in every asset under `where` (already moved).
    Returns the repo paths of the files changed."""
    changed: list[str] = []
    for d in ([where] if paths.is_asset_dir(where) else list(_assets_in(where))):
        mpath = d / "asset.yaml"
        raw = yaml.safe_load(mpath.read_text()) or {}
        updated = _rewrite(raw, old, new)
        if updated != raw:
            Manifest.from_dict(updated).save(mpath)
            changed.append(paths.posix_rel(root, mpath))
        for f in sorted(d.rglob("*.json")):
            if "checks" not in f.relative_to(d).parts:
                continue
            doc = json.loads(f.read_text())
            new_doc = _rewrite(doc, old, new)
            if new_doc != doc:
                f.write_text(json.dumps(new_doc, indent=2) + "\n")
                changed.append(paths.posix_rel(root, f))
        for f in sorted([*d.glob("*.tscn"), *d.glob("*.glb.import")]):
            text = f.read_text()
            fixed = _rewrite_text(text, old, new)
            if fixed != text:
                f.write_text(fixed)
                changed.append(paths.posix_rel(root, f))
    return changed


def _assets_in(folder: Path):
    for p in sorted(folder.rglob("asset.yaml")):
        yield p.parent


def _check_new_folder_path(root: Path, folder: str) -> None:
    """The folder must not exist, nest inside an asset, or hide one."""
    if not folder:
        raise ValueError("a folder needs a name")
    target = paths.folder_dir(root, folder)
    if target.exists():
        raise ValueError(f"{folder!r} already exists")
    inside = paths.enclosing_asset(root, folder)
    if inside is not None:
        raise ValueError(f"{folder!r} would nest inside the asset {inside.name!r}")
    for parent in target.parents:  # a file in the way of a parent
        if parent.exists() and not parent.is_dir():
            raise ValueError(f"{paths.posix_rel(root, parent)} is not a folder")
        if parent == paths.models_dir(root):
            break


def create_folder(root: Path, folder: str) -> dict[str, Any]:
    folder = paths.check_folder(folder)
    _check_new_folder_path(root, folder)
    paths.folder_dir(root, folder).mkdir(parents=True)
    return {"folder": folder}


def _destination_folder(root: Path, to: str) -> str:
    """The folder an item is moved into: it may be new, but it must not nest inside an asset."""
    to = paths.check_folder(to)
    inside = paths.enclosing_asset(root, to) if to else None
    if inside is not None:
        raise ValueError(f"{to!r} is inside the asset {inside.name!r}")
    return to


def _relocate(root: Path, src: Path, dst: Path) -> list[str]:
    if dst.exists():
        raise ValueError(f"{paths.posix_rel(root, dst)} already exists")
    old, new = paths.posix_rel(root, src), paths.posix_rel(root, dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(src), str(dst))
    return rewrite_tree(root, dst, old, new)


def move_asset(root: Path, slug: str, to: str) -> dict[str, Any]:
    src = paths.find_asset_dir(root, slug)
    if src is None:
        raise FileNotFoundError(f"no asset {slug!r}")
    to = _destination_folder(root, to)
    dst = paths.folder_dir(root, to) / slug
    if dst == src:
        raise ValueError(f"{slug!r} is already in {to or 'the root'!r}")
    changed = _relocate(root, src, dst)
    return {"slug": slug, "folder": to, "asset_dir": paths.posix_rel(root, dst), "rewritten": changed}


def _folder_src(root: Path, folder: str) -> tuple[str, Path]:
    folder = paths.check_folder(folder)
    if not folder:
        raise ValueError("the root cannot be moved")
    d = paths.folder_dir(root, folder)
    if not d.is_dir() or paths.is_asset_dir(d):
        raise FileNotFoundError(f"no folder {folder!r}")
    return folder, d


def move_folder(root: Path, folder: str, to: str) -> dict[str, Any]:
    folder, src = _folder_src(root, folder)
    to = _destination_folder(root, to)
    if to == folder or to.startswith(folder + "/"):
        raise ValueError(f"cannot move {folder!r} into itself")
    new = f"{to}/{src.name}" if to else src.name
    if new == folder:
        raise ValueError(f"{folder!r} is already in {to or 'the root'!r}")
    changed = _relocate(root, src, paths.folder_dir(root, new))
    return {"folder": new, "rewritten": changed}


def rename_folder(root: Path, folder: str, name: str) -> dict[str, Any]:
    folder, src = _folder_src(root, folder)
    name = paths.check_folder(name)
    if not name or "/" in name:
        raise ValueError("a folder name is a single segment")
    parent = folder.rpartition("/")[0]
    new = f"{parent}/{name}" if parent else name
    if new == folder:
        raise ValueError(f"{folder!r} already has that name")
    changed = _relocate(root, src, paths.folder_dir(root, new))
    return {"folder": new, "rewritten": changed}
