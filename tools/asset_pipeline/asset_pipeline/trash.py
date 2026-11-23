"""Rename and delete assets, and the trash. Everything is a working-tree change; committing is up to the user.

Deleted assets go to `.asset_work/_trash/<slug>-<timestamp>/` (git-ignored) as `asset/` (the asset folder), `work/`
(the scratch dir) and `meta.json`. A running backend command is recorded by a lock file in `.asset_work/_locks/`,
which rename and delete refuse to work around."""
from __future__ import annotations

import contextlib
import json
import os
import shutil
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

import yaml

from . import cost, folders, paths
from .manifest import Manifest, RenameRecord, now

# ---- the "a command is running on this asset" lock ---------------------------------------------


def _locks_dir(root: Path) -> Path:
    return root / ".asset_work" / "_locks"


def _alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except OSError:  # PermissionError: it exists, owned by someone else
        return True
    return True


@contextlib.contextmanager
def hold(root: Path, slug: str) -> Iterator[None]:
    """Mark `slug` as having a command running for the duration of the block."""
    d = _locks_dir(root)
    d.mkdir(parents=True, exist_ok=True)
    f = d / f"{slug}.{os.getpid()}.{uuid.uuid4().hex[:8]}"
    f.write_text(str(os.getpid()))
    try:
        yield
    finally:
        f.unlink(missing_ok=True)


def running(root: Path, slug: str) -> bool:
    """True while a live command holds `slug`. Locks left by a dead process are cleaned up."""
    d = _locks_dir(root)
    if not d.is_dir():
        return False
    live = False
    for f in d.glob(f"{slug}.*"):
        try:
            pid = int(f.read_text().strip())
        except (OSError, ValueError):
            pid = -1
        if pid > 0 and _alive(pid):
            live = True
        else:
            f.unlink(missing_ok=True)
    return live


def _refuse_if_running(root: Path, slugs: list[str]) -> None:
    for s in slugs:
        if running(root, s):
            raise ValueError(f"a command is running on {s!r}: wait for it to finish")


# ---- summary -----------------------------------------------------------------------------------


def summary(root: Path, slug: str) -> dict[str, Any]:
    """What a confirmation dialog shows: class, stage, lineage counts, ledger cost and exported files present."""
    d = paths.find_asset_dir(root, slug)
    if d is None:
        raise FileNotFoundError(f"no asset {slug!r}")
    m = Manifest.load(d / "asset.yaml")
    kinds = [e.kind for e in m.lineage]
    exported = sorted(f for f in (m.exports[-1].files if m.exports else []) if (root / f).is_file())
    on_disk = {n: (d / f"{slug}{ext}").is_file() for n, ext in (("glb", ".glb"), ("import", ".glb.import"), ("tscn", ".tscn"))}
    return {"slug": slug, "class": m.asset_class, "stage": m.stage,
            "variants": kinds.count("concept"), "turnaround_views": kinds.count("turnaround"), "meshes": kinds.count("mesh"),
            "cost_usd": cost.total_usd(m), "exported": any(on_disk.values()), "exported_present": on_disk,
            "exported_files": exported, "folder": _folder_of(root, d), "asset_dir": paths.posix_rel(root, d)}


def _folder_of(root: Path, d: Path) -> str:
    f = d.parent.relative_to(paths.models_dir(root)).as_posix()
    return "" if f == "." else f


# ---- rename ------------------------------------------------------------------------------------


def _map_paths(node: Any, pairs: list[tuple[str, str]], exact: dict[str, str]) -> Any:
    if isinstance(node, dict):
        return {k: _map_paths(v, pairs, exact) for k, v in node.items()}
    if isinstance(node, list):
        return [_map_paths(v, pairs, exact) for v in node]
    if isinstance(node, str):
        if node in exact:
            return exact[node]
        for old, new in pairs:
            if node == old or node.startswith(old + "/"):
                return new + node[len(old):]
    return node


def rename_asset(root: Path, slug: str, new_slug: str) -> dict[str, Any]:
    paths.check_slug(slug)
    paths.check_slug(new_slug)
    src = paths.find_asset_dir(root, slug)
    if src is None:
        raise FileNotFoundError(f"no asset {slug!r}")
    if new_slug == slug:
        raise ValueError(f"{slug!r} already has that name")
    if paths.find_asset_dir(root, new_slug) is not None:
        raise ValueError(f"asset {new_slug!r} already exists")
    dst = src.parent / new_slug
    work_old, work_new = paths.work_dir(root, slug), paths.work_dir(root, new_slug)
    if dst.exists():
        raise ValueError(f"{paths.posix_rel(root, dst)} already exists")
    if work_new.exists():
        raise ValueError(f"{paths.posix_rel(root, work_new)} already exists")
    _refuse_if_running(root, [slug, new_slug])

    old_dir, new_dir = paths.posix_rel(root, src), paths.posix_rel(root, dst)
    shutil.move(str(src), str(dst))
    if work_old.is_dir():
        shutil.move(str(work_old), str(work_new))
    # Exported files carry the slug in their names: <slug>.glb, <slug>.glb.import, <slug>.tscn.
    for f in sorted(dst.glob(f"{slug}.*")):
        if f.is_file():
            f.rename(dst / (new_slug + f.name[len(slug):]))
    pairs = [(old_dir, new_dir), (paths.posix_rel(root, work_old), paths.posix_rel(root, work_new))]
    # File names are matched after the directory prefix has been rewritten, so key them by the new directory.
    old_names = {f"{new_dir}/{slug}{ext}": f"{new_dir}/{new_slug}{ext}" for ext in (".glb", ".glb.import", ".tscn", ".tscn.uid")}

    def fix(node: Any) -> Any:
        mapped = _map_paths(node, pairs, {})
        return _map_paths(mapped, [], old_names)

    changed: list[str] = []
    mpath = dst / "asset.yaml"
    raw = yaml.safe_load(mpath.read_text()) or {}
    m = Manifest.from_dict(fix(raw))
    m.slug = new_slug
    m.renames.append(RenameRecord(old=slug, new=new_slug))
    m.save(mpath)
    changed.append(paths.posix_rel(root, mpath))
    jsons = [f for f in sorted(dst.rglob("*.json")) if "checks" in f.relative_to(dst).parts]
    if work_new.is_dir():
        jsons += sorted(work_new.rglob("*.json"))
    for f in jsons:
        doc = json.loads(f.read_text())
        updated = fix(doc)
        if isinstance(updated, dict) and updated.get("slug") == slug:
            updated["slug"] = new_slug
        if updated != doc:
            f.write_text(json.dumps(updated, indent=2) + "\n")
            changed.append(paths.posix_rel(root, f))
    from .godot_stage import pascal
    for f in sorted([*dst.glob("*.tscn"), *dst.glob("*.glb.import")]):
        text = f.read_text()
        fixed = text.replace(f"res://{old_dir}/", f"res://{new_dir}/")
        for ext in (".glb", ".tscn"):
            fixed = fixed.replace(f"/{new_slug}/{slug}{ext}", f"/{new_slug}/{new_slug}{ext}")
        fixed = fixed.replace(f'[node name="{pascal(slug)}" type="Node3D"]', f'[node name="{pascal(new_slug)}" type="Node3D"]')
        if fixed != text:
            f.write_text(fixed)
            changed.append(paths.posix_rel(root, f))
    return {"slug": new_slug, "old_slug": slug, "asset_dir": new_dir, "folder": _folder_of(root, dst),
            "rewritten": changed, "summary": summary(root, new_slug)}


# ---- trash -------------------------------------------------------------------------------------


def trash_dir(root: Path) -> Path:
    return root / ".asset_work" / "_trash"


def _stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _trash_one(root: Path, slug: str) -> dict[str, Any]:
    src = paths.find_asset_dir(root, slug)
    assert src is not None
    info = summary(root, slug)
    base = f"{slug}-{_stamp()}"
    name, n = base, 1
    while (trash_dir(root) / name).exists():
        n += 1
        name = f"{base}-{n}"
    entry = trash_dir(root) / name
    entry.mkdir(parents=True)
    work = paths.work_dir(root, slug)
    has_work = work.is_dir()
    shutil.move(str(src), str(entry / "asset"))
    if has_work:
        shutil.move(str(work), str(entry / "work"))
    meta = {"slug": slug, "folder": info["folder"], "deleted": now(), "work": has_work, "summary": info}
    (entry / "meta.json").write_text(json.dumps(meta, indent=2) + "\n")
    return {"entry": name, **meta}


def delete_asset(root: Path, slug: str) -> dict[str, Any]:
    paths.check_slug(slug)
    info = summary(root, slug)  # raises if missing
    _refuse_if_running(root, [slug])
    return {"slug": slug, "summary": info, "trashed": [_trash_one(root, slug)]}


def delete_folder(root: Path, folder: str) -> dict[str, Any]:
    folder, d = folders._folder_src(root, folder)
    slugs = [p.name for p in folders._assets_in(d)]
    for p in d.rglob("*"):
        if p.is_file() and paths.enclosing_asset(root, p.parent.relative_to(paths.models_dir(root)).as_posix()) is None:
            raise ValueError(f"{paths.posix_rel(root, p)} is not part of an asset: remove it by hand first")
    _refuse_if_running(root, slugs)
    trashed = [_trash_one(root, s) for s in slugs]
    shutil.rmtree(d)  # only empty folders are left
    return {"folder": folder, "trashed": trashed}


def trash_list(root: Path) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    base = trash_dir(root)
    if base.is_dir():
        for e in sorted(p for p in base.iterdir() if (p / "meta.json").is_file()):
            entries.append({"entry": e.name, **json.loads((e / "meta.json").read_text())})
    return {"entries": entries}


def _entry_dir(root: Path, entry: str) -> Path:
    if not entry or "/" in entry or "\\" in entry or entry.startswith("."):
        raise ValueError(f"invalid trash entry {entry!r}")
    d = trash_dir(root) / entry
    if not (d / "meta.json").is_file():
        raise FileNotFoundError(f"no trash entry {entry!r}")
    return d


def trash_restore(root: Path, entry: str) -> dict[str, Any]:
    d = _entry_dir(root, entry)
    meta = json.loads((d / "meta.json").read_text())
    slug, folder = meta["slug"], meta["folder"]
    if paths.find_asset_dir(root, slug) is not None:
        raise ValueError(f"the slug {slug!r} has been reused: rename or delete that asset first")
    dst = paths.folder_dir(root, folder) / slug
    work = paths.work_dir(root, slug)
    if dst.exists():
        raise ValueError(f"{paths.posix_rel(root, dst)} already exists")
    if work.exists():
        raise ValueError(f"{paths.posix_rel(root, work)} already exists")
    inside = paths.enclosing_asset(root, folder) if folder else None
    if inside is not None:
        raise ValueError(f"{folder!r} is now inside the asset {inside.name!r}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(d / "asset"), str(dst))
    if (d / "work").is_dir():
        work.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(d / "work"), str(work))
    shutil.rmtree(d)
    return {"slug": slug, "entry": entry, "folder": folder, "asset_dir": paths.posix_rel(root, dst)}


def trash_empty(root: Path) -> dict[str, Any]:
    base = trash_dir(root)
    count = len([p for p in base.iterdir() if p.is_dir()]) if base.is_dir() else 0
    if base.is_dir():
        shutil.rmtree(base)
    return {"removed": count}
