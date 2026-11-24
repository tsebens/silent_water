"""cadkit: one JSON object on stdout per command (catalogue prints a table unless --json).

    cadkit catalogue [word ...] [--json]   the asset library, read fresh: generated scenes, hand-built ones, behaviours
    cadkit check                           build everything in a staging folder; write nothing
    cadkit build                           the same, then write the result if every scene passed (all or nothing)
    cadkit verify                          the same, then report generated files that are stale or hand-edited
    cadkit render <slug> [--out DIR] [--cameras FILE]    PNGs of a scene (default out: build/renders/<slug>/)
    cadkit sheet <slug>                    render afresh, then write review sheets in <scene>/review/

The process these serve is docs/asset_process.md.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from cadkit import library


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="cadkit", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("catalogue")
    c.add_argument("words", nargs="*")
    c.add_argument("--json", action="store_true")
    for name in ("check", "build", "verify"):
        sub.add_parser(name)
    r = sub.add_parser("render")
    r.add_argument("slug")
    r.add_argument("--out", type=Path)
    r.add_argument("--cameras", type=Path)
    s = sub.add_parser("sheet")
    s.add_argument("slug")
    args = p.parse_args(argv)

    if args.cmd == "catalogue":
        from cadkit import catalogue
        cat = catalogue.load()
        if args.words:
            cat = catalogue.search(cat, args.words)
        print(json.dumps(cat, indent=1) if args.json else catalogue.table(cat))
        return 0
    if args.cmd in ("check", "build", "verify"):
        from cadkit import build
        out = build.run(args.cmd)
        print(json.dumps(out, indent=1))
        return 0 if out["ok"] else 1
    from cadkit import render
    rel = lambda paths: [Path(x).resolve().relative_to(library.REPO).as_posix() for x in paths]
    try:
        if args.cmd == "render":
            shots = render.render(args.slug, args.out.resolve() if args.out else None, args.cameras)
            print(json.dumps({"ok": True, "slug": args.slug, "renders": [str(x) for x in shots]}, indent=1))
        else:
            print(json.dumps({"ok": True, "slug": args.slug, "sheets": rel(render.sheet(args.slug))}, indent=1))
    except (RuntimeError, FileNotFoundError, ValueError) as e:
        print(json.dumps({"ok": False, "slug": args.slug, "error": str(e)}, indent=1))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
