"""`asset <command>`: every command prints one JSON object. Exit 0 on ok, 1 on error."""
from __future__ import annotations

import argparse
import getpass
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

import yaml

from . import doctor, paths, providers
from .manifest import CLASSES, DECISIONS, BriefRecord, LineageEntry, Manifest
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


def full_prompt(root: Path, body: str) -> str:
    """The style bible's canonical block, the writer's prompt, then the negative block."""
    neg = read_block(root, "negative.md")
    parts = [read_block(root, "style.md"), body]
    if neg:
        parts.append("Avoid:\n" + neg)
    return "\n\n".join(x for x in parts if x)


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
        raise ValueError("no concept brief: pass --brief \"...\" (it is saved in the manifest)")
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
    try:
        bodies = writer.write_prompts(m.description, read_block(root, "style.md"), args.notes or "", refs, args.n)
    except PromptWriterError as e:
        raise ValueError(f"prompt writer failed: {e}") from e
    out_dir = paths.work_dir(root, args.slug) / "concept"
    made = []
    for body in bodies:
        vid = next_id(m, "v")
        prompt = full_prompt(root, body)
        rel = (out_dir / f"{vid}.png").relative_to(root)
        img.generate(prompt, refs, root / rel)
        m.add(LineageEntry(id=vid, kind="concept", path=str(rel), provider=img.name, model=img.model,
                           prompt=prompt, parent=parent.id if parent else None,
                           writer=f"{writer.name}:{writer.model}", references=[_rel(root, r) for r in refs]))
        made.append({"id": vid, "path": str(rel), "parent": parent.id if parent else None})
    if m.stage in ("new", "concept"):
        m.stage = "concept"
    m.save(mpath)
    return {"slug": m.slug, "stage": m.stage, "variants": made, "anchors": [_rel(root, a) for a in anchors],
            "prompt_writer": f"{writer.name}:{writer.model}", "image_provider": f"{img.name}:{img.model}"}


def _rel(root: Path, p: Path) -> str:
    try:
        return str(p.resolve().relative_to(root.resolve()))
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
    style = read_block(root, "style.md")
    views = []
    for view in VIEWS:
        body = (f"Orthographic {view} view of this exact asset, flat neutral lighting, no perspective, "
                f"centred, on a transparent or plain removed background, {TURNAROUND_PX}x{TURNAROUND_PX} px. "
                "Keep every proportion and detail of the source image unchanged.")
        prompt = (style + "\n\n" + body) if style else body
        rel = (out_dir / f"turnaround_t{n}_{view}.png").relative_to(root)
        img.edit(prompt, src_path, [], root / rel)
        eid = f"t{n}_{view}"
        m.add(LineageEntry(id=eid, kind="turnaround", path=str(rel), provider=img.name, model=img.model,
                           prompt=prompt, parent=src.id, references=[src.path]))
        views.append({"id": eid, "view": view, "path": str(rel), "parent": src.id})
    if m.stage in ("new", "concept", "locked", "turnaround"):
        m.stage = "turnaround"
    m.save(mpath)
    return {"slug": m.slug, "stage": m.stage, "views": views, "image_provider": f"{img.name}:{img.model}"}


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
    context = (f"Asset: {m.slug} ({m.asset_class})\nDescription: {m.description}\n"
               f"Locked concept prompt: {locked.prompt}\nClass profile:\n{yaml.safe_dump(profile)}")
    images = [abspath(root, locked.path)] + [abspath(root, e.path) for e in views]
    writer = providers.select("prompt_writer", providers.load_config(), args.prompt_writer)
    try:
        text = writer.write_brief(context, images)
    except PromptWriterError as e:
        raise ValueError(f"prompt writer failed: {e}") from e
    out = paths.asset_dir(root, args.slug) / "concept" / "brief.md"
    out.parent.mkdir(parents=True, exist_ok=True)
    (out.parent / ".gdignore").touch()
    out.write_text(text)
    m.brief = BriefRecord(path=str(out.relative_to(root)), writer=writer.name, model=writer.model,
                          images=[_rel(root, i) for i in images])
    if m.stage in ("new", "concept", "locked", "turnaround", "brief"):
        m.stage = "brief"
    m.save(mpath)
    return {"slug": m.slug, "stage": m.stage, "brief": str(out.relative_to(root)),
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
    runs: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    for prov in built:
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
            continue
        m.add(LineageEntry(id=rid, kind="mesh", path=str(rel), provider=prov.name, model=prov.model,
                           parent=ordered[0].id, references=[e.path for e in ordered], task_id=job))
        m.save(mpath)  # per run, so a later provider's crash keeps this one
        runs.append({"id": rid, "provider": prov.name, "model": prov.model, "task_id": job, "path": str(rel)})
    if runs and m.stage in ("new", "concept", "locked", "turnaround", "brief", "to3d"):
        m.stage = "to3d"
        m.save(mpath)
    return {"ok": not errors, "slug": m.slug, "stage": m.stage, "runs": runs, "errors": errors}


def _latest_turnaround(m: Manifest) -> str:
    ids = [e.id for e in m.lineage if e.kind == "turnaround"]
    if not ids:
        return "t0_"
    return max((i.split("_")[0] for i in ids), key=lambda x: int(x[1:])) + "_"


def cmd_new(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    mpath = paths.manifest_path(root, args.slug)
    if mpath.exists():
        raise FileExistsError(f"asset {args.slug!r} already exists at {mpath}")
    m = Manifest(slug=args.slug, asset_class=args.asset_class, issue=args.issue)
    m.save(mpath)
    work = paths.work_dir(root, args.slug)
    work.mkdir(parents=True, exist_ok=True)
    return {"slug": m.slug, "class": m.asset_class, "issue": m.issue, "stage": m.stage,
            "manifest": str(mpath.relative_to(root)), "asset_dir": str(mpath.parent.relative_to(root)),
            "work_dir": str(work.relative_to(root))}


def cmd_lock(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    mpath = paths.manifest_path(root, args.slug)
    m = Manifest.load(mpath)
    rec = m.lock(args.variant, reviewer=args.reviewer, decision=args.decision, notes=args.notes)
    m.save(mpath)
    return {"slug": m.slug, "stage": m.stage, "variant": rec.variant, "decision": rec.decision,
            "reviewer": rec.reviewer, "locked": m.locked is not None}


def cmd_doctor(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    return doctor.run(providers.load_config(), live=args.live)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="asset", description="Asset Studio backend")
    sub = p.add_subparsers(dest="command", required=True)
    d = sub.add_parser("doctor", help="check Blender, Godot, the Claude CLI and API keys (--live adds one call per provider)")
    d.add_argument("--live", action="store_true", help="make one cheap real call per configured provider")
    d.set_defaults(fn=cmd_doctor)
    n = sub.add_parser("new", help="create an asset's manifest and folders")
    n.add_argument("slug")
    n.add_argument("--class", dest="asset_class", required=True, choices=CLASSES)
    n.add_argument("--issue", type=int)
    n.set_defaults(fn=cmd_new)
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
    c.set_defaults(fn=cmd_concept)
    t = sub.add_parser("turnaround", help="front, left, back, right views of the locked concept")
    t.add_argument("slug")
    t.add_argument("--image-provider", default=None)
    t.set_defaults(fn=cmd_turnaround)
    b = sub.add_parser("brief", help="draft brief.md from the locked concept and views")
    b.add_argument("slug")
    b.add_argument("--prompt-writer", default=None)
    b.set_defaults(fn=cmd_brief)
    t3 = sub.add_parser("to3d", help="image-to-3D from the turnaround; several providers is a bake-off")
    t3.add_argument("slug")
    t3.add_argument("--3d-provider", dest="three_d_provider", nargs="+", default=None, metavar="P")
    t3.add_argument("--poll-interval", type=float, default=5.0, help="seconds between polls")
    t3.add_argument("--timeout", type=float, default=1800.0, help="give up on a provider after this many seconds")
    t3.set_defaults(fn=cmd_to3d)
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
        if hasattr(args, "slug"):
            paths.check_slug(args.slug)
        result = args.fn(args, paths.repo_root())
    except (ValueError, KeyError, OSError, yaml.YAMLError) as e:
        msg = e.args[0] if isinstance(e, KeyError) and e.args else str(e)
        print(json.dumps({"ok": False, "error": msg}))
        return 1
    print(json.dumps({"ok": True, **result}))
    return 0 if result.get("ok", True) else 1


if __name__ == "__main__":
    sys.exit(main())
