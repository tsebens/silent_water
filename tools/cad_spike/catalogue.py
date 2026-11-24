"""Print the catalogue the breakdown step reads: generated scenes (component.yaml) and existing ones.

    uv run python catalogue.py            # compact table
    uv run python catalogue.py --yaml     # everything
"""
import sys
from pathlib import Path

import yaml

from kitcad import REPO

HERE = Path(__file__).parent


def load() -> dict:
    gen = [yaml.safe_load(p.read_text()) for p in sorted((REPO / "assets/models/spike").glob("**/component.yaml"))]
    existing = yaml.safe_load((HERE / "catalogue/existing.yaml").read_text())
    return {"generated": gen, "existing": existing["scenes"], "behaviours": existing["behaviours"]}


if __name__ == "__main__":
    cat = load()
    if "--yaml" in sys.argv:
        print(yaml.safe_dump(cat, sort_keys=False, width=110))
        sys.exit(0)
    for group in ("generated", "existing"):
        print(f"## {group}")
        for e in cat[group]:
            beh = e.get("behaviour", {}) or {}
            fp = e.get("footprint_mm") or e.get("size") or ""
            print(f"- {e['slug']:<18} {e['kind']:<14} {str(beh.get('script', e.get('script', ''))):<34} {str(fp):<24} {e['summary']}")
    print("## behaviours")
    for b in cat["behaviours"]:
        print(f"- {b['script']:<16} {b['does']}")
