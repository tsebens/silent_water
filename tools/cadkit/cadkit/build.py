"""Discover, build, check and verify the generated scenes.

One build script per scene, `tools/cadkit/scenes/<slug>.py`, each declaring:

    SLUG   the scene's name (the file's name)
    GROUP  kit | furniture | stations
    USES   slugs of generated scenes it instances or reads (its dependencies)
    build() -> dict   make the solids, check them (cadkit.solids.expect), write GLBs, the .tscn and the entry

There is no list of scenes anywhere: adding a scene adds files and edits none. The build order comes from USES.

A build is all or nothing. The whole tree is always built, into a staging folder; a scene's checks against the scenes
it uses read their entries as just rebuilt. Files reach the repository only if every scene passes, so a change to a
shared part that breaks one of its users is never written. It takes a few seconds, and unchanged scenes come out
byte-identical.
"""
from __future__ import annotations

import importlib.util
import shutil
import tempfile
from pathlib import Path

import yaml

from cadkit import library
from cadkit.solids import GeometryError

SCENES_DIR = Path(__file__).resolve().parents[1] / "scenes"
TEXT_SUFFIXES = {".tscn", ".yaml", ".json", ".md", ".gdignore", ""}


class BuildFailed(Exception):
    def __init__(self, slug: str, message: str):
        super().__init__(f"{slug}: {message}")
        self.slug, self.message = slug, message


def discover(scenes_dir: Path = SCENES_DIR) -> dict:
    """Every build script in the folder, by slug."""
    modules = {}
    for path in sorted(scenes_dir.glob("*.py")):
        if path.name.startswith("_"):
            continue
        spec = importlib.util.spec_from_file_location(f"cadkit_scene_{path.stem}", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        for attr in ("SLUG", "GROUP", "USES", "build"):
            if not hasattr(mod, attr):
                raise BuildFailed(path.stem, f"{path.name} does not define {attr}")
        if mod.SLUG != path.stem:
            raise BuildFailed(path.stem, f"SLUG {mod.SLUG!r} must match the file name")
        if mod.GROUP not in library.GROUPS:
            raise BuildFailed(path.stem, f"GROUP {mod.GROUP!r} is not one of {library.GROUPS}")
        modules[mod.SLUG] = mod
    return modules


def order(modules: dict) -> list[str]:
    """Slugs with every scene after the scenes it uses (alphabetical among equals, so the order is stable)."""
    out: list[str] = []
    state: dict[str, int] = {}

    def visit(slug: str, chain: tuple[str, ...]) -> None:
        if state.get(slug) == 2:
            return
        if state.get(slug) == 1:
            raise BuildFailed(slug, "dependency cycle: " + " -> ".join((*chain, slug)))
        state[slug] = 1
        for dep in sorted(modules[slug].USES):
            if dep not in modules:
                raise BuildFailed(slug, f"USES names {dep!r}, which has no build script")
            visit(dep, (*chain, slug))
        state[slug] = 2
        out.append(slug)

    for slug in sorted(modules):
        visit(slug, ())
    return out


def stage(staging: Path, scenes_dir: Path = SCENES_DIR) -> dict:
    """Build the whole tree under `staging`. Returns {slug: {"result": build()'s dict, "files": [Path, ...]}}."""
    modules = discover(scenes_dir)
    library.set_root(staging)
    library.register(modules)
    library.take_written()
    built = {}
    try:
        for slug in order(modules):
            try:
                result = modules[slug].build()
            except GeometryError as e:
                raise BuildFailed(slug, str(e)) from e
            except FileNotFoundError as e:
                raise BuildFailed(slug, str(e)) from e
            built[slug] = {"result": result, "files": library.take_written(), "group": modules[slug].GROUP}
    finally:
        library.set_root(library.MODELS)
    return built


def _rel(built: dict, staging: Path) -> dict[str, list[str]]:
    """{slug: [paths relative to the models folder]} of what a staged build generated."""
    return {slug: sorted(f.relative_to(staging).as_posix() for f in b["files"]) for slug, b in built.items()}


def _previous_files(models: Path, group: str, slug: str) -> set[str]:
    p = models / group / slug / "component.yaml"
    if not p.is_file():
        return set()
    doc = yaml.safe_load(p.read_text()) or {}
    return {f"{group}/{slug}/{name}" for name in doc.get("files", [])}


def promote(built: dict, staging: Path, models: Path = library.MODELS) -> list[str]:
    """Copy a passing staged build into the repository. Returns the paths that changed (relative to the models folder)."""
    changed = []
    for slug, files in _rel(built, staging).items():
        group = built[slug]["group"]
        for stale in sorted(_previous_files(models, group, slug) - set(files)):
            for victim in (models / stale, models / (stale + ".import")):
                if victim.is_file():
                    victim.unlink()
                    changed.append(stale)
        for rel in files:
            src, dst = staging / rel, models / rel
            if not dst.is_file() or dst.read_bytes() != src.read_bytes():
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(src, dst)
                changed.append(rel)
            imp_src, imp_dst = Path(str(src) + ".import"), Path(str(dst) + ".import")
            if imp_src.is_file() and not imp_dst.is_file():      # Godot owns an import file once it exists
                shutil.copyfile(imp_src, imp_dst)
    return sorted(set(changed))


def _same_mesh(a: Path, b: Path) -> bool:
    """Two GLBs that are the same model: equal bytes, or equal triangle count, bounds and colours."""
    if a.read_bytes() == b.read_bytes():
        return True
    import numpy as np
    import trimesh
    ma, mb = trimesh.load(a, force="mesh"), trimesh.load(b, force="mesh")
    if len(ma.faces) != len(mb.faces) or not np.allclose(ma.bounds, mb.bounds, atol=1e-5):
        return False
    ca = {tuple(c) for c in np.asarray(ma.visual.vertex_colors)}
    cb = {tuple(c) for c in np.asarray(mb.visual.vertex_colors)}
    return ca == cb


def compare(built: dict, staging: Path, models: Path = library.MODELS) -> list[str]:
    """What differs between a staged build and the repository: the generated files are stale or were edited by hand."""
    problems = []
    for slug, files in _rel(built, staging).items():
        group = built[slug]["group"]
        for rel in files:
            src, dst = staging / rel, models / rel
            if not dst.is_file():
                problems.append(f"{rel}: missing; run `cadkit build`")
            elif src.suffix == ".glb":
                if not _same_mesh(src, dst):
                    problems.append(f"{rel}: differs from what its build script makes")
            elif dst.read_text() != src.read_text():
                problems.append(f"{rel}: differs from what its build script makes (generated files are never edited by hand)")
        for stale in sorted(_previous_files(models, group, slug) - set(files)):
            problems.append(f"{stale}: no longer generated; run `cadkit build`")
    for entry in sorted(models.glob("*/*/component.yaml")):
        if entry.parent.name not in built:
            problems.append(f"{entry.relative_to(models).as_posix()}: no build script for this scene in tools/cadkit/scenes/")
    return problems


def run(mode: str, scenes_dir: Path = SCENES_DIR, models: Path = library.MODELS) -> dict:
    """mode: check (build in staging, write nothing), build (and promote), verify (and compare with the repository)."""
    with tempfile.TemporaryDirectory(prefix="cadkit-") as tmp:
        staging = Path(tmp) / "models"
        staging.mkdir()
        try:
            built = stage(staging, scenes_dir)
        except BuildFailed as e:
            return {"ok": False, "failed": e.slug, "error": e.message,
                    "note": "nothing was written" if mode == "build" else ""}
        out = {"ok": True, "scenes": {slug: b["result"] for slug, b in built.items()}}
        if mode == "build":
            out["changed"] = promote(built, staging, models)
        elif mode == "verify":
            out["problems"] = compare(built, staging, models)
            out["ok"] = not out["problems"]
        return out
