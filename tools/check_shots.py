#!/usr/bin/env python3
"""Check the world-shot CI artifacts: every PNG exists, is not one flat colour, and the two shots differ.

Usage: tools/check_shots.py <surface.png> <deep.png> [--min-diff 6.0]
The difference is the mean absolute per-pixel, per-channel difference on a 0-255 scale. Needs Pillow
(`uv run --with pillow tools/check_shots.py ...`). Exits non-zero with a reason when a check fails.
"""
import argparse
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageStat


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("surface")
    ap.add_argument("deep")
    ap.add_argument("--min-diff", type=float, default=6.0, help="least mean per-pixel difference between the shots (0-255)")
    a = ap.parse_args()
    imgs = []
    for p in (a.surface, a.deep):
        f = Path(p)
        if not f.is_file() or f.stat().st_size == 0:
            print(f"FAIL {p}: missing or empty")
            return 1
        im = Image.open(f).convert("RGB")
        spread = max(hi - lo for lo, hi in im.getextrema())
        stdev = max(ImageStat.Stat(im).stddev)
        print(f"{p}: {im.size[0]}x{im.size[1]}, channel spread {spread}, stddev {stdev:.1f}")
        if spread < 8 or stdev < 2.0:
            print(f"FAIL {p}: all one colour")
            return 1
        imgs.append(im)
    if imgs[0].size != imgs[1].size:
        print("FAIL: the two shots are different sizes")
        return 1
    diff = sum(ImageStat.Stat(ImageChops.difference(*imgs)).mean) / 3.0
    print(f"mean per-pixel difference {diff:.2f} (needs > {a.min_diff})")
    if diff <= a.min_diff:
        print("FAIL: the shots are not visibly different")
        return 1
    print("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
