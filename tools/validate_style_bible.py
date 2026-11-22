#!/usr/bin/env python3
"""Validate assets/style_bible/ against the documented field list. Exits non-zero on error."""
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent / "assets" / "style_bible"
CLASSES = ["creature", "prop", "terrain", "architecture"]
ROUTES = {"image-to-3d", "scripted"}
GATES = ["triangle_tolerance", "bbox_tolerance", "max_loose_parts", "max_non_manifold", "silhouette_iou_min"]
FIELDS = ["build_route", "triangle_budget", "scale_range_m", "snap_grid_m", "palette_size", "cleanup_recipe", "gates"]


def num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def class_file_errors(name: str) -> list[str]:
    f = ROOT / "classes" / f"{name}.md"
    if not f.is_file():
        return [f"classes/{name}.md missing"]
    headings: dict[str, list[str]] = {}
    cur = None
    for line in f.read_text().splitlines():
        if line.startswith("## "):
            cur = line[3:].strip()
            headings[cur] = []
        elif cur is not None:
            headings[cur].append(line)
    return [f"classes/{name}.md: missing or empty ## {h} section"
            for h in ("Style", "Avoid") if not "".join(headings.get(h, [])).strip()]


def validate() -> list[str]:
    errs: list[str] = []
    for f in ["style.md", "negative.md", "classes.yaml"]:
        p = ROOT / f
        if not p.is_file() or not p.read_text().strip():
            errs.append(f"{f} missing or empty")
    for c in CLASSES:
        if not (ROOT / "anchors" / c).is_dir():
            errs.append(f"anchors/{c}/ missing")
    if errs:
        return errs
    for c in CLASSES:
        errs += class_file_errors(c)
    data = yaml.safe_load((ROOT / "classes.yaml").read_text())
    classes = (data or {}).get("classes")
    if not isinstance(classes, dict):
        return ["classes.yaml: top-level 'classes' mapping missing"]
    if sorted(classes) != sorted(CLASSES):
        errs.append(f"classes must be exactly {CLASSES}, got {sorted(classes)}")
    for name, c in classes.items():
        p = f"{name}: "
        if not isinstance(c, dict):
            errs.append(p + "not a mapping")
            continue
        for f in FIELDS:
            if f not in c:
                errs.append(p + f"missing field {f}")
        for f in c:
            if f not in FIELDS:
                errs.append(p + f"unknown field {f}")
        if c.get("build_route") not in ROUTES:
            errs.append(p + "build_route must be image-to-3d or scripted")
        if (name == "architecture") != (c.get("build_route") == "scripted"):
            errs.append(p + "only architecture uses the scripted route")
        tb = c.get("triangle_budget")
        if not (isinstance(tb, int) and tb > 0):
            errs.append(p + "triangle_budget must be a positive int")
        sr = c.get("scale_range_m")
        if not (isinstance(sr, list) and len(sr) == 2 and all(num(x) for x in sr) and 0 < sr[0] < sr[1]):
            errs.append(p + "scale_range_m must be [min, max] with 0 < min < max")
        sg = c.get("snap_grid_m")
        if sg is not None and not (num(sg) and sg > 0):
            errs.append(p + "snap_grid_m must be null or positive")
        if name == "architecture" and sg is None:
            errs.append(p + "architecture needs a snap grid")
        ps = c.get("palette_size")
        if not (isinstance(ps, int) and ps > 0):
            errs.append(p + "palette_size must be a positive int")
        cr = c.get("cleanup_recipe")
        if not (isinstance(cr, list) and cr and all(isinstance(s, str) for s in cr)):
            errs.append(p + "cleanup_recipe must be a non-empty list of strings")
        g = c.get("gates")
        if not isinstance(g, dict) or sorted(g) != sorted(GATES):
            errs.append(p + f"gates must have exactly {GATES}")
        elif not all(num(v) and v >= 0 for v in g.values()):
            errs.append(p + "gate thresholds must be non-negative numbers")
        elif g["silhouette_iou_min"] > 1:
            errs.append(p + "silhouette_iou_min must be <= 1")
    return errs


if __name__ == "__main__":
    problems = validate()
    for e in problems:
        print("style bible:", e)
    if not problems:
        print("style bible OK")
    sys.exit(1 if problems else 0)
