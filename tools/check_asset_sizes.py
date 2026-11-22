#!/usr/bin/env python3
"""Fail on any file over 5 MB under assets/ (no Git LFS; see docs/asset_pipeline.md).
Files listed in tools/asset_size_allowlist.txt (already committed when this check was added) are exempt. Usage: check_asset_sizes.py [root]"""
import sys
from pathlib import Path

LIMIT = 5 * 1024 * 1024


def oversize(root: Path) -> list[tuple[str, int]]:
    base = root / "assets"
    allow_file = root / "tools" / "asset_size_allowlist.txt"
    allowed = {l.strip() for l in allow_file.read_text().splitlines() if l.strip() and not l.startswith("#")} if allow_file.is_file() else set()
    return [(str(p.relative_to(root)), p.stat().st_size) for p in sorted(base.rglob("*"))
            if p.is_file() and p.stat().st_size > LIMIT and str(p.relative_to(root)) not in allowed]


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    bad = oversize(root)
    for rel, size in bad:
        print(f"{rel}: {size / 1048576:.1f} MB is over the 5 MB limit")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
