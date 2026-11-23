"""`asset <command>`: every command prints one JSON object. Exit 0 on ok, 1 on error."""
from __future__ import annotations

import argparse
import getpass
import json
import os
import shutil
import sys
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any

import yaml

from . import check, cleanup, cost, doctor, godot_stage, paths, providers
from .manifest import (CLASSES, DECISIONS, BriefRecord, CheckRecord, CleanupRecord, ExportRecord, GodotCheckRecord,
                       LineageEntry, Manifest)
from .writers import PromptWriterError

VIEWS = ("front", "left", "back", "right")
TURNAROUND_PX = 2048
MAX_ANCHORS = 4
ANCHOR_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp")


def style_dir(root: Path) -> Path:
    return root / "assets" / "style_bible"


def read_block(root: Path, name: str) -> str:
    f = style_dir(root) / name
    return f.read_text().strip() if f.is_file() else ""


def anchors_for(root: Path, asset_class: str) -> list[Path]:
    """Two to four approved anchor images for the class, passed as references on every concept call."""
    d = style_dir(root) / "anchors" / asset_class
    found = sorted(p for p in d.iterdir() if p.suffix.lower() in ANCHOR_SUFFIXES) if d.is_dir() else []
    return found[:MAX_ANCHORS]


def next_id(m: Manifest, prefix: str) -> str:
    k = 1
    while any(e.id == f"{prefix}{k}" for e in m.lineage):
        k += 1
    return f"{prefix}{k}"


def abspath(root: Path, rel: str) -> Path:
    return root / rel


def class_section(root: Path, asset_class: str, heading: str) -> str:
    """The body of one `## <heading>` section of the class file, or "" when absent."""
    f = style_dir(root) / "classes" / f"{asset_class}.md"
    if not f.is_file():
        return ""
    out: list[str] = []
    inside = False
    for line in f.read_text().splitlines():
        if line.startswith("## "):
            inside = line[3:].strip().lower() == heading.lower()
        elif inside:
            out.append(line)
    return "\n".join(out).strip()


def style_block(root: Path, asset_class: str) -> str:
    """Shared style, then the class style."""
    return "\n\n".join(x for x in (read_block(root, "style.md"), class_section(root, asset_class, "Style")) if x)


def negative_block(root: Path, asset_class: str) -> str:
    """Shared negative list, then the class's Avoid list."""
    return "\n".join(x for x in (read_block(root, "negative.md"), class_section(root, asset_class, "Avoid")) if x)


def full_prompt(root: Path, asset_class: str, body: str) -> str:
    """Shared style, class style, the writer's prompt, shared negative, class negative."""
    neg = negative_block(root, asset_class)
    parts = [style_block(root, asset_class), body]
    if neg:
        parts.append("Avoid:\n" + neg)
    return "\n\n".join(x for x in parts if x)


@contextmanager
def _ledger_guard(mpath: Path, m: Manifest):
    """If a command fails part-way, the manifest is not saved, but money already spent still counts:
    write the cost entries added so far onto the manifest on disk, then let the error through."""
    n0 = len(m.costs)
    try:
        yield
    except BaseException:
        if len(m.costs) > n0:
            disk = Manifest.load(mpath)
            disk.costs.extend(m.costs[n0:])
            disk.save(mpath)
        raise


def cmd_concept(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    mpath = paths.manifest_path(root, args.slug)
    m = Manifest.load(mpath)
    if args.brief is not None:
        m.description = args.brief
    if args.refine and not args.notes:
        raise ValueError("--refine needs --notes")
    if args.notes and not args.refine:
        raise ValueError("--notes only applies with --refine")
    if not m.description:
        raise ValueError("no concept brief: pass --brief \"...\", or set it with `asset describe` or `asset new --description`")
    if args.n < 1:
        raise ValueError("--n must be at least 1")
    cfg = providers.load_config()
    writer = providers.select("prompt_writer", cfg, args.prompt_writer)
    img = providers.select("image", cfg, args.image_provider)
    anchors = anchors_for(root, m.asset_class)
    parent = None
    refs = list(anchors)
    if args.refine:
        parent = m.entry(args.refine)
        if parent.kind != "concept":
            raise ValueError(f"{args.refine!r} is a {parent.kind}, only concept variants can be refined")
        refs.append(abspath(root, parent.path))
    prices = cost.load_prices()
    stage = "refine" if args.refine else "concept"
    out_dir = paths.work_dir(root, args.slug) / "concept"
    made = []
    with _ledger_guard(mpath, m):
        try:
            bodies = cost.paid_call(
                m, writer, "prompt_writer", prices, command="concept", stage=stage,
                fn=lambda: writer.write_prompts(m.description, style_block(root, m.asset_class), args.notes or "", refs, args.n))
        except PromptWriterError as e:
            raise ValueError(f"prompt writer failed: {e}") from e
        for body in bodies:
            vid = next_id(m, "v")
            prompt = full_prompt(root, m.asset_class, body)
            rel = (out_dir / f"{vid}.png").relative_to(root)
            cost.paid_call(m, img, "image", prices, lambda: img.generate(prompt, refs, root / rel),
                           command="concept", stage=stage, lineage=vid)
            m.add(LineageEntry(id=vid, kind="concept", path=rel.as_posix(), provider=img.name, model=img.model,
                               prompt=prompt, parent=parent.id if parent else None,
                               writer=f"{writer.name}:{writer.model}", references=[_rel(root, r) for r in refs]))
            made.append({"id": vid, "path": rel.as_posix(), "parent": parent.id if parent else None})
    if m.stage in ("new", "concept"):
        m.stage = "concept"
    m.save(mpath)
    return {"slug": m.slug, "stage": m.stage, "variants": made, "anchors": [_rel(root, a) for a in anchors],
            "prompt_writer": f"{writer.name}:{writer.model}", "image_provider": f"{img.name}:{img.model}"}


def _rel(root: Path, p: Path) -> str:
    try:
        return p.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return str(p)


def cmd_turnaround(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    mpath = paths.manifest_path(root, args.slug)
    m = Manifest.load(mpath)
    if m.locked is None:
        raise ValueError("no locked concept: run `asset lock` first")
    src = m.entry(m.locked.variant)
    src_path = abspath(root, src.path)
    img = providers.select("image", providers.load_config(), args.image_provider)
    out_dir = paths.asset_dir(root, args.slug) / "concept"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / ".gdignore").touch()
    n = 1
    while any(e.id.startswith(f"t{n}_") for e in m.lineage):
        n += 1
    only = getattr(args, "view", None)
    prev: dict[str, LineageEntry] = {}
    if only:
        old = _latest_turnaround(m)
        prev = {e.id[len(old):]: e for e in m.lineage if e.kind == "turnaround" and e.id.startswith(old)}
        missing = [v for v in VIEWS if v not in prev]
        if missing:
            raise ValueError(f"--view needs a complete turnaround to start from: run `asset turnaround` first "
                             f"(missing {', '.join(missing)})")
    views = []
    prices = cost.load_prices()
    with _ledger_guard(mpath, m):
        _turnaround_views(args, root, m, img, src, src_path, out_dir, n, only, prev, views, prices)
    if m.stage in ("new", "concept", "locked", "turnaround"):
        m.stage = "turnaround"
    m.save(mpath)
    return {"slug": m.slug, "stage": m.stage, "views": views, "image_provider": f"{img.name}:{img.model}"}


def _turnaround_views(args, root, m, img, src, src_path, out_dir, n, only, prev, views, prices) -> None:
    for view in VIEWS:
        if only and view != only:
            # carry the view over so the new set is complete: copy the file, keep prompt and provenance
            old_e = prev[view]
            rel = (out_dir / f"turnaround_t{n}_{view}.png").relative_to(root)
            shutil.copyfile(abspath(root, old_e.path), root / rel)
            eid = f"t{n}_{view}"
            m.add(LineageEntry(id=eid, kind="turnaround", path=rel.as_posix(), provider=old_e.provider,
                               model=old_e.model, prompt=old_e.prompt, parent=old_e.parent,
                               references=list(old_e.references)))
            views.append({"id": eid, "view": view, "path": rel.as_posix(), "parent": old_e.parent, "carried_from": old_e.id})
            continue
        body = (f"Orthographic {view} view of this exact asset, flat neutral lighting, no perspective, "
                f"centred, on a transparent or plain removed background, {TURNAROUND_PX}x{TURNAROUND_PX} px. "
                "Keep every proportion and detail of the source image unchanged.")
        prompt = full_prompt(root, m.asset_class, body)
        rel = (out_dir / f"turnaround_t{n}_{view}.png").relative_to(root)
        eid = f"t{n}_{view}"
        cost.paid_call(m, img, "image", prices, lambda: img.edit(prompt, src_path, [], root / rel),
                       command="turnaround", stage="turnaround", lineage=eid)
        m.add(LineageEntry(id=eid, kind="turnaround", path=rel.as_posix(), provider=img.name, model=img.model,
                           prompt=prompt, parent=src.id, references=[src.path]))
        views.append({"id": eid, "view": view, "path": rel.as_posix(), "parent": src.id})


def cmd_brief(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    mpath = paths.manifest_path(root, args.slug)
    m = Manifest.load(mpath)
    if m.locked is None:
        raise ValueError("no locked concept: run `asset lock` first")
    locked = m.entry(m.locked.variant)
    views = [e for e in m.lineage if e.kind == "turnaround" and e.id.startswith(_latest_turnaround(m))]
    profile: dict[str, Any] = {}
    cf = style_dir(root) / "classes.yaml"
    if cf.is_file():
        profile = (yaml.safe_load(cf.read_text()) or {}).get("classes", {}).get(m.asset_class, {})
    style = style_block(root, m.asset_class)
    context = (f"Asset: {m.slug} ({m.asset_class})\nDescription: {m.description}\n"
               + (f"Style:\n{style}\n" if style else "") +
               f"Locked concept prompt: {locked.prompt}\nClass profile:\n{yaml.safe_dump(profile)}")
    images = [abspath(root, locked.path)] + [abspath(root, e.path) for e in views]
    writer = providers.select("prompt_writer", providers.load_config(), args.prompt_writer)
    with _ledger_guard(mpath, m):
        try:
            text = cost.paid_call(m, writer, "prompt_writer", cost.load_prices(), lambda: writer.write_brief(context, images),
                                  command="brief", stage="brief")
        except PromptWriterError as e:
            raise ValueError(f"prompt writer failed: {e}") from e
    out = paths.asset_dir(root, args.slug) / "concept" / "brief.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    (out.parent / ".gdignore").touch()
    out.write_text(text)
    m.brief = BriefRecord(path=paths.posix_rel(root, out), writer=writer.name, model=writer.model,
                          images=[_rel(root, i) for i in images])
    if m.stage in ("new", "concept", "locked", "turnaround", "brief"):
        m.stage = "brief"
    m.save(mpath)
    return {"slug": m.slug, "stage": m.stage, "brief": paths.posix_rel(root, out),
            "prompt_writer": f"{writer.name}:{writer.model}"}


def _wait_for(prov: Any, job: str, interval: float, timeout: float) -> None:
    """Poll until the job is done; raise on failure or timeout."""
    deadline = time.monotonic() + timeout
    while True:
        state = prov.poll(job)
        if state == "done":
            return
        if state == "failed":
            why = prov.failure_reason(job)
            raise ValueError(f"{prov.name} job {job} failed" + (f": {why}" if why else ""))
        if state not in ("pending", "running"):
            raise ValueError(f"{prov.name} job {job} reported unknown state {state!r}")
        if time.monotonic() >= deadline:
            raise ValueError(f"{prov.name} job {job} timed out after {timeout:g}s")
        time.sleep(interval)


def cmd_to3d(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    """Send the latest turnaround to each named 3D provider (several is the bake-off) and record each run.
    A provider that fails is reported under `errors` and does not stop the others."""
    mpath = paths.manifest_path(root, args.slug)
    m = Manifest.load(mpath)
    tid = _latest_turnaround(m)
    by_view = {e.id[len(tid):]: e for e in m.lineage if e.kind == "turnaround" and e.id.startswith(tid)}
    if not by_view:
        raise ValueError("no turnaround: run `asset turnaround` first")
    ordered = [by_view[v] for v in VIEWS if v in by_view]
    views = [abspath(root, e.path) for e in ordered]
    cfg = providers.load_config()
    names = list(dict.fromkeys(args.three_d_provider or [None]))
    built = [providers.select("three_d", cfg, n) for n in names]  # fail on a bad name before any spend
    out_dir = paths.work_dir(root, args.slug) / "to3d"
    prices = cost.load_prices()
    runs: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    for prov in built:
        prov.last_usage = None
        job = ""
        try:
            job = prov.submit(views)
            _wait_for(prov, job, args.poll_interval, args.timeout)
            k = 1
            while any(e.id == f"r{k}_{prov.name}" for e in m.lineage):
                k += 1
            rid = f"r{k}_{prov.name}"
            rel = (out_dir / f"{rid}.glb").relative_to(root)
            prov.download(job, root / rel)
        except (ValueError, OSError) as e:
            errors.append({"provider": prov.name, "error": str(e)})
            if prov.last_usage is not None:  # the job was accepted, so it is billed even though it failed
                m.costs.append(cost.entry_for(prov, "three_d", prices, command="to3d", stage="to3d", error=str(e)[:300]))
                m.save(mpath)
            continue
        m.costs.append(cost.entry_for(prov, "three_d", prices, command="to3d", stage="to3d", lineage=rid))
        m.add(LineageEntry(id=rid, kind="mesh", path=rel.as_posix(), provider=prov.name, model=prov.model,
                           parent=ordered[0].id, references=[e.path for e in ordered], task_id=job))
        m.save(mpath)  # per run, so a later provider's crash keeps this one
        runs.append({"id": rid, "provider": prov.name, "model": prov.model, "task_id": job, "path": rel.as_posix()})
    if runs and m.stage in ("new", "concept", "locked", "turnaround", "brief", "to3d"):
        m.stage = "to3d"
        m.save(mpath)
    return {"ok": not errors, "slug": m.slug, "stage": m.stage, "runs": runs, "errors": errors}


def cmd_cleanup(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    """Clean a raw mesh (a `mesh` lineage entry from `to3d`) with the class profile's recipe, in headless Blender."""
    mpath = paths.manifest_path(root, args.slug)
    m = Manifest.load(mpath)
    src = m.entry(args.source)
    if src.kind != "mesh":
        raise ValueError(f"{args.source!r} is a {src.kind}, cleanup needs a mesh run (see `asset to3d`)")
    profile = cleanup.class_profile(root, m.asset_class)
    brief = abspath(root, m.brief.path) if m.brief else None
    if args.size_m is not None:
        size_m, size_from = args.size_m, "--size-m"
    else:
        size_m, size_from = cleanup.brief_size_m(brief, profile)
    lo, hi = profile["scale_range_m"]
    if not lo <= size_m <= hi:
        raise ValueError(f"size {size_m:g} m is outside the {m.asset_class} scale range [{lo:g}, {hi:g}] m")
    budget = args.triangle_budget or profile["triangle_budget"]
    recipe = list(profile["cleanup_recipe"])
    cleanup.find_blender()  # fail before any work when Blender is missing
    k = 1
    while any(e.id == f"c{k}" for e in m.lineage):
        k += 1
    cid = f"c{k}"
    rel = (paths.work_dir(root, args.slug) / "cleanup" / f"{cid}.glb").relative_to(root)
    params = {"source": str(abspath(root, src.path)), "output": str(root / rel), "slug": m.slug,
              "asset_class": m.asset_class, "recipe": recipe, "triangle_budget": budget, "size_m": size_m,
              "palette_size": profile["palette_size"], "snap_grid_m": profile.get("snap_grid_m"),
              "max_loose_parts": profile["gates"]["max_loose_parts"]}
    (root / rel).parent.mkdir(parents=True, exist_ok=True)
    result = cleanup.run_blender(params, root / rel.parent)
    m.add(LineageEntry(id=cid, kind="mesh", path=rel.as_posix(), provider="blender",
                       model=result.get("blender_version", ""), parent=src.id))
    recorded = {k2: v for k2, v in params.items() if k2 in ("triangle_budget", "size_m", "palette_size", "snap_grid_m")}
    recorded["size_from"] = size_from
    m.cleanups.append(CleanupRecord(id=cid, source=src.id, recipe=recipe, params=recorded,
                                    commit=cleanup.code_commit(root), script_sha256=cleanup.script_digest(),
                                    blender=result.get("blender_version", ""), result=result))
    m.stage = "cleanup"
    m.save(mpath)
    return {"slug": m.slug, "stage": m.stage, "id": cid, "source": src.id, "path": rel.as_posix(), "recipe": recipe,
            "triangle_budget": budget, "result": result}


def cmd_check(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    """Gate a cleaned mesh (the latest cleanup, or --source) and write the JSON report. `ok` is false when any gate
    fails; the failing gates are listed and recorded in the manifest."""
    mpath = paths.manifest_path(root, args.slug)
    m = Manifest.load(mpath)
    if args.source:
        src = m.entry(args.source)
    elif m.cleanups:
        src = m.entry(m.cleanups[-1].id)
    else:
        raise ValueError("nothing to check: run `asset cleanup` first, or pass --source <mesh id>")
    if src.kind != "mesh":
        raise ValueError(f"{src.id!r} is a {src.kind}, check needs a mesh")
    profile = cleanup.class_profile(root, m.asset_class)
    brief = abspath(root, m.brief.path) if m.brief else None
    if args.size_m is not None:
        size_m, size_from = args.size_m, "--size-m"
    else:
        size_m, size_from = cleanup.brief_size_m(brief, profile)
    budget = args.triangle_budget or profile["triangle_budget"]
    prefix = _latest_turnaround(m)
    views = {v: abspath(root, e.path) for v in VIEWS for e in m.lineage if e.id == f"{prefix}{v}"}
    mesh = check.load_mesh(abspath(root, src.path))
    gates = check.run_gates(mesh, profile, size_m, size_from, budget, views)
    failed = [g["name"] for g in gates if not g["ok"]]
    rel = (paths.asset_dir(root, args.slug) / "checks" / f"{src.id}.json").relative_to(root)
    report = {"slug": m.slug, "class": m.asset_class, "mesh": src.id, "mesh_path": src.path,
              "turnaround": prefix.rstrip("_") if views else None, "ok": not failed, "failed": failed,
              "thresholds": profile["gates"], "triangle_budget": budget, "size_m": size_m, "size_from": size_from,
              "collision_helpers_ignored": mesh["skipped_collision"], "gates": gates}
    (root / rel).parent.mkdir(parents=True, exist_ok=True)
    (root / rel).write_text(json.dumps(report, indent=2) + "\n")
    m.checks.append(CheckRecord(id=src.id, report=rel.as_posix(), ok=not failed, failed=failed))
    if not failed and m.stage in ("cleanup", "checked"):
        m.stage = "checked"
    m.save(mpath)
    return {"ok": not failed, "slug": m.slug, "stage": m.stage, "id": src.id, "report": rel.as_posix(), "failed": failed,
            "gates": {g["name"]: g["value"] for g in gates}}


def _pick_mesh(m: Manifest, source: str | None) -> LineageEntry:
    """The mesh to import or export: --source, else the latest cleanup."""
    if source:
        src = m.entry(source)
    elif m.cleanups:
        src = m.entry(m.cleanups[-1].id)
    else:
        raise ValueError("nothing to use: run `asset cleanup` first, or pass --source <mesh id>")
    if src.kind != "mesh":
        raise ValueError(f"{src.id!r} is a {src.kind}, this needs a mesh")
    return src


def cmd_godot_check(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    """Import the cleaned GLB headless through the shared post-import script, check the vertex-colour material flag,
    and render it in game lighting (fog; white light; red light) into the log dir."""
    mpath = paths.manifest_path(root, args.slug)
    m = Manifest.load(mpath)
    src = _pick_mesh(m, args.source)
    log_dir = Path(args.log_dir or os.environ.get("LOG_DIR") or root / "logs").resolve()
    res = godot_stage.godot_check(root, m.slug, abspath(root, src.path), log_dir, render=not args.no_render)
    m.godot_checks.append(GodotCheckRecord(id=src.id, ok=res["ok"], material=res["material"],
                                           renders=res["renders"], error=res.get("render_error", "")))
    m.save(mpath)
    return {"ok": res["ok"], "slug": m.slug, "stage": m.stage, "id": src.id, "log_dir": str(log_dir),
            **{k: v for k, v in res.items() if k != "ok"}}


def cmd_export(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    """Write the committed deliverable into assets/models/<slug>/: <slug>.glb (+ its import settings), <slug>.tscn,
    concept/ (with .gdignore; images at most 2048 px) and asset.yaml. Needs a mesh that passed `check`."""
    mpath = paths.manifest_path(root, args.slug)
    m = Manifest.load(mpath)
    src = _pick_mesh(m, args.source)
    gate = next((c for c in reversed(m.checks) if c.id == src.id), None)
    if gate is None or not gate.ok:
        why = "never checked" if gate is None else "failed: " + ", ".join(gate.failed)
        raise ValueError(f"{src.id!r} has not passed `asset check` ({why})")
    out = paths.asset_dir(root, m.slug)
    files: set[str] = set()

    def put(p: Path) -> None:
        files.add(paths.posix_rel(root, p))

    glb = out / f"{m.slug}.glb"
    shutil.copy(abspath(root, src.path), glb)
    put(glb)
    imp = out / f"{m.slug}.glb.import"
    imp.write_text(godot_stage.import_stub(f"res://assets/models/{m.slug}", m.slug))
    put(imp)
    scene = out / f"{m.slug}.tscn"
    scene.write_text(godot_stage.tscn(m.slug))
    put(scene)
    concept = out / "concept"
    concept.mkdir(parents=True, exist_ok=True)
    (concept / ".gdignore").write_text("")
    put(concept / ".gdignore")
    resized: list[str] = []
    if m.locked is not None:
        lp = abspath(root, m.entry(m.locked.variant).path)
        dst = concept / f"locked{lp.suffix.lower()}"
        if godot_stage.downscale_png(lp, dst):
            resized.append(paths.posix_rel(root, dst))
        put(dst)
    for e in m.lineage:
        if e.kind == "turnaround":
            f = abspath(root, e.path)
            if godot_stage.shrink_in_place(f):
                resized.append(e.path)
            put(f)
    if m.brief is not None and abspath(root, m.brief.path).is_file():
        put(abspath(root, m.brief.path))
    m.exports.append(ExportRecord(id=src.id, files=sorted(files), commit=cleanup.code_commit(root)))
    m.stage = "exported"
    m.save(mpath)
    put(mpath)
    return {"slug": m.slug, "stage": m.stage, "id": src.id, "dir": paths.posix_rel(root, out),
            "files": sorted(files), "resized": resized}


def _latest_turnaround(m: Manifest) -> str:
    ids = [e.id for e in m.lineage if e.kind == "turnaround"]
    if not ids:
        return "t0_"
    return max((i.split("_")[0] for i in ids), key=lambda x: int(x[1:])) + "_"


def cmd_new(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    mpath = paths.manifest_path(root, args.slug)
    if mpath.exists():
        raise FileExistsError(f"asset {args.slug!r} already exists at {mpath}")
    m = Manifest(slug=args.slug, asset_class=args.asset_class, issue=args.issue,
                 description=(args.description or "").strip())
    m.save(mpath)
    work = paths.work_dir(root, args.slug)
    work.mkdir(parents=True, exist_ok=True)
    return {"slug": m.slug, "class": m.asset_class, "issue": m.issue, "stage": m.stage, "description": m.description,
            "manifest": paths.posix_rel(root, mpath), "asset_dir": paths.posix_rel(root, mpath.parent),
            "work_dir": paths.posix_rel(root, work)}


def cmd_describe(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    """Set or replace the asset's description: the concept brief `concept` reads."""
    mpath = paths.manifest_path(root, args.slug)
    m = Manifest.load(mpath)
    text = args.text.strip()
    if not text:
        raise ValueError("the description is empty")
    m.description = text
    m.save(mpath)
    return {"slug": m.slug, "stage": m.stage, "description": m.description}


def cmd_lock(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    mpath = paths.manifest_path(root, args.slug)
    m = Manifest.load(mpath)
    rec = m.lock(args.variant, reviewer=args.reviewer, decision=args.decision, notes=args.notes)
    m.save(mpath)
    return {"slug": m.slug, "stage": m.stage, "variant": rec.variant, "decision": rec.decision,
            "reviewer": rec.reviewer, "locked": m.locked is not None}


def cmd_list(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    """Every manifest as JSON (the Godot plugin cannot read YAML), sorted by slug."""
    assets: list[dict[str, Any]] = []
    for mpath in sorted((root / "assets" / "models").glob("*/asset.yaml")):
        m = Manifest.load(mpath)
        # The effective soft budget (the manifest's, else its class's) so the Godot plugin need not read classes.yaml.
        assets.append(m.to_dict() | {"budget_usd": cost.budget_for(root, m)})
    cfg = providers.load_config()
    names = {kind: sorted(cfg["providers"].get(kind) or {}) for kind in ("image", "three_d", "prompt_writer")}
    return {"assets": assets, "providers": names, "selected": dict(cfg["selection"]),
            "selected_source": dict(cfg.get("selection_source", {}))}


def cmd_cost(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    """What an asset has cost so far (or every asset, with --all), read from the manifests' ledgers."""
    if args.all:
        return cost.summary_all(root)
    if not args.slug:
        raise ValueError("name an asset, or pass --all")
    return cost.summary(root, Manifest.load(paths.manifest_path(root, args.slug)))


def cmd_estimate(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    """`--estimate`: the cost of a paid command from prices.yaml and the request. Calls nothing and writes nothing."""
    cfg = providers.load_config()
    name = args.command
    reqs: list[tuple[Any, str, int]] = []
    if name == "concept":
        if args.n < 1:
            raise ValueError("--n must be at least 1")
        reqs = [(providers.select("prompt_writer", cfg, args.prompt_writer), "prompt_writer", 1),
                (providers.select("image", cfg, args.image_provider), "image", args.n)]
    elif name == "turnaround":
        reqs = [(providers.select("image", cfg, args.image_provider), "image", 1 if args.view else len(VIEWS))]
    elif name == "brief":
        reqs = [(providers.select("prompt_writer", cfg, args.prompt_writer), "prompt_writer", 1)]
    elif name == "to3d":
        names = list(dict.fromkeys(args.three_d_provider or [None]))
        reqs = [(providers.select("three_d", cfg, n), "three_d", 1) for n in names]
    else:
        raise ValueError(f"{name} has no estimate")
    return {"slug": args.slug, "command": name, "estimate": cost.estimate(reqs, cost.load_prices())}


def cmd_doctor(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    return doctor.run(providers.load_config(), live=args.live)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="asset", description="Asset Studio backend")
    sub = p.add_subparsers(dest="command", required=True)
    ls = sub.add_parser("list", help="every asset manifest as JSON (used by the Asset Studio plugin)")
    ls.set_defaults(fn=cmd_list)

    d = sub.add_parser("doctor", help="check Blender, Godot, the Claude CLI and API keys (--live adds one call per provider)")
    d.add_argument("--live", action="store_true", help="make one cheap real call per configured provider")
    d.set_defaults(fn=cmd_doctor)
    n = sub.add_parser("new", help="create an asset's manifest and folders")
    n.add_argument("slug")
    n.add_argument("--class", dest="asset_class", required=True, choices=CLASSES)
    n.add_argument("--issue", type=int)
    n.add_argument("--description", default=None, metavar="TEXT", help="what the asset is; the concept brief (saved in the manifest)")
    n.set_defaults(fn=cmd_new)
    ds = sub.add_parser("describe", help="set or replace an asset's description (the concept brief)")
    ds.add_argument("slug")
    ds.add_argument("text")
    ds.set_defaults(fn=cmd_describe)

    lk = sub.add_parser("lock", help="record the chosen concept variant and a reviewer decision")
    lk.add_argument("slug")
    lk.add_argument("variant")
    lk.add_argument("--decision", choices=DECISIONS, default="approved")
    lk.add_argument("--reviewer", default=None)
    lk.add_argument("--notes", default="")
    lk.set_defaults(fn=cmd_lock)
    c = sub.add_parser("concept", help="generate concept variants (or refine one with --refine and --notes)")
    c.add_argument("slug")
    c.add_argument("--n", type=int, default=3)
    c.add_argument("--brief", default=None, help="what the asset is; saved in the manifest")
    c.add_argument("--image-provider", default=None)
    c.add_argument("--prompt-writer", default=None)
    c.add_argument("--refine", default=None, metavar="VARIANT")
    c.add_argument("--notes", default=None)
    c.add_argument("--estimate", action="store_true", help="print what this would cost from prices.yaml and the request, and call nothing")
    c.set_defaults(fn=cmd_concept)
    ESTIMATE = "print what this would cost from prices.yaml and the request, and call nothing"
    t = sub.add_parser("turnaround", help="front, left, back, right views of the locked concept")
    t.add_argument("slug")
    t.add_argument("--image-provider", default=None)
    t.add_argument("--view", choices=VIEWS, default=None,
                   help="regenerate one view into a new complete set (the other three are copied from the latest)")
    t.add_argument("--estimate", action="store_true", help=ESTIMATE)
    t.set_defaults(fn=cmd_turnaround)
    b = sub.add_parser("brief", help="draft brief.md from the locked concept and views")
    b.add_argument("slug")
    b.add_argument("--prompt-writer", default=None)
    b.add_argument("--estimate", action="store_true", help=ESTIMATE)
    b.set_defaults(fn=cmd_brief)
    t3 = sub.add_parser("to3d", help="image-to-3D from the turnaround; several providers is a bake-off")
    t3.add_argument("slug")
    t3.add_argument("--3d-provider", dest="three_d_provider", nargs="+", default=None, metavar="P")
    t3.add_argument("--poll-interval", type=float, default=5.0, help="seconds between polls")
    t3.add_argument("--timeout", type=float, default=1800.0, help="give up on a provider after this many seconds")
    t3.add_argument("--estimate", action="store_true", help=ESTIMATE)
    t3.set_defaults(fn=cmd_to3d)
    co = sub.add_parser("cost", help="what an asset has cost so far, by stage and provider (--all: every asset)")
    co.add_argument("slug", nargs="?", default=None)
    co.add_argument("--all", action="store_true", help="per-asset totals and a grand total over every manifest")
    co.set_defaults(fn=cmd_cost)
    cl = sub.add_parser("cleanup", help="headless Blender cleanup of a raw mesh per the class profile")
    cl.add_argument("slug")
    cl.add_argument("--source", required=True, metavar="RUN", help="mesh run id from `to3d`, e.g. r1_tripo")
    cl.add_argument("--size-m", type=float, default=None, help="largest dimension in metres (default: brief.md size_m, else class range)")
    cl.add_argument("--triangle-budget", type=int, default=None, help="override the class profile's budget")
    cl.set_defaults(fn=cmd_cleanup)
    ck = sub.add_parser("check", help="numeric gates on a cleaned mesh, written as a JSON report")
    ck.add_argument("slug")
    ck.add_argument("--source", default=None, metavar="MESH", help="mesh id to gate (default: the latest cleanup)")
    ck.add_argument("--size-m", type=float, default=None, help="largest dimension in metres (default: brief.md size_m, else class range)")
    ck.add_argument("--triangle-budget", type=int, default=None, help="override the class profile's budget")
    ck.set_defaults(fn=cmd_check)
    gc = sub.add_parser("godot-check", help="import the cleaned GLB in Godot and render it in game lighting")
    gc.add_argument("slug")
    gc.add_argument("--source", default=None, metavar="MESH", help="mesh id (default: the latest cleanup)")
    gc.add_argument("--log-dir", default=None, help="where the renders and Godot logs go (default: $LOG_DIR, else ./logs)")
    gc.add_argument("--no-render", action="store_true", help="import and verify only; skip the renders")
    gc.set_defaults(fn=cmd_godot_check)
    ex = sub.add_parser("export", help="write the deliverable into assets/models/<slug>/")
    ex.add_argument("slug")
    ex.add_argument("--source", default=None, metavar="MESH", help="mesh id (default: the latest cleanup)")
    ex.set_defaults(fn=cmd_export)
    return p


def load_env() -> None:
    """Load KEY=VALUE lines from the git-ignored tools/asset_pipeline/.env; real env vars win."""
    f = Path(__file__).resolve().parent.parent / ".env"
    if not f.is_file():
        return
    for line in f.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip("\"'"))


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    load_env()
    if getattr(args, "reviewer", 1) is None:
        args.reviewer = getpass.getuser()
    try:
        if getattr(args, "slug", None) is not None:
            paths.check_slug(args.slug)
        result = (cmd_estimate if getattr(args, "estimate", False) else args.fn)(args, paths.repo_root())
    except (ValueError, KeyError, OSError, yaml.YAMLError) as e:
        msg = e.args[0] if isinstance(e, KeyError) and e.args else str(e)
        print(json.dumps({"ok": False, "error": msg}))
        return 1
    print(json.dumps({"ok": True, **result}))
    return 0 if result.get("ok", True) else 1


if __name__ == "__main__":
    sys.exit(main())
