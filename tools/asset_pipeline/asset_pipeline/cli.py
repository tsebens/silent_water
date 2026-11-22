"""`asset <command>`: every command prints one JSON object. Exit 0 on ok, 1 on error."""
from __future__ import annotations

import argparse
import getpass
import json
import sys
from pathlib import Path
from typing import Any

from . import paths
from .manifest import CLASSES, DECISIONS, Manifest


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


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="asset", description="Asset Studio backend")
    sub = p.add_subparsers(dest="command", required=True)
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
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if getattr(args, "reviewer", 1) is None:
        args.reviewer = getpass.getuser()
    try:
        paths.check_slug(args.slug)
        result = args.fn(args, paths.repo_root())
    except (ValueError, KeyError, OSError) as e:
        msg = e.args[0] if isinstance(e, KeyError) and e.args else str(e)
        print(json.dumps({"ok": False, "error": msg}))
        return 1
    print(json.dumps({"ok": True, **result}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
