"""sketch: render macro terrain for seeds and report the viability gate.
  uv run sketch render --seeds 1 2 3 --out <dir>      hillshade per seed, with placements and the log
  uv run sketch stats --seeds 1..50                    how many seeds pass the gate, and why the rest fail"""
from __future__ import annotations
import argparse, json, sys, time
from pathlib import Path
import numpy as np
from .grid import MapPreset
from .landforms import build_macro
from .erosion import run_macro_erosion
from .stations import place, DEFAULT_STATIONS
from .render import render, hypsometry


def _seeds(args: list[str]) -> list[int]:
    out: list[int] = []
    for a in args:
        if ".." in a:
            lo, hi = a.split("..")
            out.extend(range(int(lo), int(hi) + 1))
        else:
            out.append(int(a))
    return out


def generate(preset: MapPreset, seed: int, erode: bool = True):
    t0 = time.perf_counter()
    macro = build_macro(preset, seed)
    t1 = time.perf_counter()
    h = macro.h
    macro.sediment = None
    if erode:
        h, acc, sed = run_macro_erosion(h, preset.cell_m, macro.log)
        macro.sediment = sed
    t2 = time.perf_counter()
    v = place(h, preset, DEFAULT_STATIONS, seed)
    t3 = time.perf_counter()
    macro.log.append(f"timing: landforms {1000*(t1-t0):.0f} ms, erosion {1000*(t2-t1):.0f} ms, gate {1000*(t3-t2):.0f} ms")
    return h, macro, v


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="sketch")
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render"); r.add_argument("--seeds", nargs="+", default=["1"]); r.add_argument("--out", required=True)
    r.add_argument("--no-erode", action="store_true"); r.add_argument("--scale", type=int, default=3)
    r.add_argument("--outlines", action="store_true", help="draw landform footprints")
    s = sub.add_parser("stats"); s.add_argument("--seeds", nargs="+", default=["1..30"])
    args = ap.parse_args(argv)
    preset = MapPreset()
    if args.cmd == "render":
        out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
        for seed in _seeds(args.seeds):
            h, macro, v = generate(preset, seed, erode=not args.no_erode)
            title = f"seed {seed}  {'VIABLE' if v.ok else 'REJECT'}  y {h.min():.0f}..{h.max():.0f}"
            img = render(h, preset, scale=args.scale, placements=v.placements, landforms=macro.landforms if args.outlines else None,
                         candidates=v.candidates, title=title, sediment=getattr(macro, 'sediment', None))
            img.save(out / f"seed_{seed:03d}.png")
            print(f"== seed {seed}: {'viable' if v.ok else 'reject'}")
            for line in macro.log: print("   " + line)
            for line in v.reasons: print("   gate: " + line)
            if v.metrics: print("   metrics: " + json.dumps({k: round(float(x), 2) for k, x in v.metrics.items()}))
            print(hypsometry(h, preset))
        return 0
    if args.cmd == "stats":
        okc = 0; reasons: dict[str, int] = {}; n = 0; t0 = time.perf_counter()
        for seed in _seeds(args.seeds):
            n += 1
            _, _, v = generate(preset, seed)
            okc += v.ok
            for rr in v.reasons:
                key = rr.split(":")[0]
                reasons[key] = reasons.get(key, 0) + 1
        print(f"{okc}/{n} seeds viable  ({(time.perf_counter()-t0)/n:.2f} s per seed)")
        for k, c in sorted(reasons.items(), key=lambda kv: -kv[1]): print(f"  {c:3d}  {k}")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
