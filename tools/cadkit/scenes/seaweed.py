"""seaweed: a static faceted seaweed clump (organics, M20 experiment). No script, no behaviour.

Brief (#776, #785): about 0.50 m tall, standing on the floor at Y=0, fronds leaning toward +X. An umber chamfered
holdfast disc, 6 tapered hexagonal stipes bent in a plane each, 6 strap-like dark olive fronds with ruffled edges
(thin thickened ruled lofts, so they are valid solids) and 4 small faceted spherical bladders on the stipes.
Faceted, flat-shaded. Three palette roles: seaweed_stipe (holdfast and stipes), seaweed_frond, seaweed_bladder.

Frame (the brief's, not the organics default): base on Y=0, the holdfast centred on X/Z at the origin; the clump leans
toward +X, so its bounds straddle the origin rather than centre on it. Modelled Z-up and turned into Y-up at the end.

Parametric: STIPES lists (azimuth, base offset, base tilt, end tilt, length) per plant. Every length is scaled by one
factor so the tallest tip lands on HEIGHT.
"""
import math

import build123d as bd
import numpy as np

from cadkit.solids import Solid, at, expect, bbox_mm, export_solids_glb, prism, tessellate
from cadkit.library import out_dir, res, write_entry, note
from cadkit.tscn import Scene

SLUG, GROUP = "seaweed", "organics"
USES: list[str] = []

HEIGHT = 500.0
HOLD_SIDES, HOLD_R, HOLD_H, HOLD_CHAMFER = 10, 30.0, 9.0, 4.0
STIPE_SIDES, STIPE_R0, STIPE_R1 = 6, 4.6, 2.0          # hexagonal, to the corners, tapering from base to top
STIPE_STEPS, FROND_STEPS = 6, 16
FROND_T = 1.4                                          # sheet thickness
FROND_W = 58.0                                         # widest point of a frond
RUFFLE = 0.22                                          # edge ruffle: each edge swings this fraction of the width, alternating
BLADDER_R, BLADDER_SIDES = 11.0, 8
BLADDER_LATS = [-72, -42, 0, 42, 72]                   # rings of the faceted sphere, in degrees of latitude
# per plant: (azimuth of its bend plane in degrees from +X, base offset (x, y) mm, tilt at base, tilt at stipe top,
#             tilt at frond tip (all from vertical), stipe length, frond length, frond twist in degrees, bladder fractions)
PLANTS = [
    (-38, (-9, -8), 10, 22, 48, 150, 340, 70, (0.55,)),
    (-12, (-3, -11), 6, 18, 42, 190, 330, 100, (0.45, 0.75)),
    (14, (6, -4), 4, 20, 46, 210, 300, 55, ()),
    (40, (9, 7), 8, 24, 52, 170, 320, 110, (0.6,)),
    (-5, (-10, 8), 12, 26, 40, 120, 290, 80, ()),
    (28, (4, 11), 14, 30, 56, 100, 250, 120, (0.7,)),
]
FROND_RANGE, BLADDER_RANGE = (5, 7), (3, 6)


def vec(*a: float) -> np.ndarray:
    return np.array(a, dtype=float)


def centreline(base: np.ndarray, az: float, tilts: list[float], length: float, steps: int, start: np.ndarray | None = None):
    """Points of a bent line in the vertical plane at azimuth az (degrees from +X), tilt interpolated through `tilts`
    (from vertical, toward +u) over `steps` equal segments. Returns the points and the tangent of each segment."""
    u = vec(math.cos(math.radians(az)), math.sin(math.radians(az)), 0.0)
    pts, tans = [base.copy()], []
    for i in range(steps):
        s = (i + 0.5) / steps
        # piecewise linear through the tilt list
        f = s * (len(tilts) - 1)
        k = min(int(f), len(tilts) - 2)
        th = math.radians(tilts[k] + (tilts[k + 1] - tilts[k]) * (f - k))
        t = math.sin(th) * u + math.cos(th) * vec(0, 0, 1)
        tans.append(t)
        pts.append(pts[-1] + t * length / steps)
    return pts, tans


def frame(t: np.ndarray, az: float, twist_deg: float) -> tuple[np.ndarray, np.ndarray]:
    """Width and normal directions for a strip travelling along t in the plane at azimuth az, twisted by twist_deg."""
    v = vec(-math.sin(math.radians(az)), math.cos(math.radians(az)), 0.0)    # horizontal, across the bend plane
    b = np.cross(t, v)
    b /= np.linalg.norm(b)
    w = v * math.cos(math.radians(twist_deg)) + b * math.sin(math.radians(twist_deg))
    n = np.cross(t, w)
    return w / np.linalg.norm(w), n / np.linalg.norm(n)


def wire(points: list[np.ndarray]) -> bd.Wire:
    return bd.Wire.make_polygon([bd.Vector(*map(float, p)) for p in points], close=True)


def stipe(pts: list[np.ndarray], tans: list[np.ndarray]) -> bd.Shape:
    """A tapered hexagonal stipe along the points: ruled loft of hexagons square to the line."""
    wires = []
    for i, p in enumerate(pts):
        t = tans[min(i, len(tans) - 1)] if i == 0 else tans[i - 1] if i == len(tans) else (tans[i - 1] + tans[i]) / 2
        t = t / np.linalg.norm(t)
        a = np.cross(t, vec(0, 1, 0))
        a /= np.linalg.norm(a)
        b = np.cross(t, a)
        r = STIPE_R0 + (STIPE_R1 - STIPE_R0) * i / (len(pts) - 1)
        ring = [p + r * (math.cos(math.radians(60 * k)) * a + math.sin(math.radians(60 * k)) * b) for k in range(STIPE_SIDES)]
        wires.append(wire(ring))
    return bd.Solid.make_loft(wires, ruled=True)


def frond(pts: list[np.ndarray], tans: list[np.ndarray], az: float, twist: float) -> bd.Shape:
    """A strap frond: a ruled loft of thin rectangles along the line, width tapering to both ends, edges ruffled."""
    n = len(pts)
    wires = []
    for i, p in enumerate(pts):
        s = i / (n - 1)
        t = tans[min(i, len(tans) - 1)] if i < len(tans) else tans[-1]
        w, nrm = frame(t, az, twist * s)
        width = max(2.0, FROND_W * (math.sin(math.pi * (0.04 + 0.96 * s ** 0.8)) ** 0.5) * (1.0 - 0.35 * s ** 2))
        sign = 1.0 if i % 2 == 0 else -1.0
        left = width / 2 * (1.0 + sign * RUFFLE)
        right = width / 2 * (1.0 - sign * RUFFLE)
        h = FROND_T / 2
        quad = [p - left * w - h * nrm, p + right * w - h * nrm, p + right * w + h * nrm, p - left * w + h * nrm]
        wires.append(wire(quad))
    return bd.Solid.make_loft(wires, ruled=True)


def bladder(centre: np.ndarray) -> bd.Shape:
    """A faceted sphere: ruled loft of octagons at BLADDER_LATS."""
    wires = []
    for lat in BLADDER_LATS:
        r = BLADDER_R * math.cos(math.radians(lat))
        z = BLADDER_R * math.sin(math.radians(lat))
        wires.append(wire([centre + vec(r * math.cos(math.radians(360.0 / BLADDER_SIDES * (k + 0.5))),
                                        r * math.sin(math.radians(360.0 / BLADDER_SIDES * (k + 0.5))), z)
                           for k in range(BLADDER_SIDES)]))
    return bd.Solid.make_loft(wires, ruled=True)


def up(shape: bd.Shape) -> bd.Shape:
    """Z-up modelling frame to Y-up: +Z becomes +Y."""
    return shape.rotate(axis=bd.Axis.X, angle=-90)


def plants(scale: float):
    out = []
    for az, (bx, by), t0, t1, t2, ls, lf, tw, bl in PLANTS:
        base = vec(bx, by, HOLD_H - 3.0)
        sp, st = centreline(base, az, [t0, t1], ls * scale, STIPE_STEPS)
        fp, ft = centreline(sp[-1], az, [t1, (t1 + t2) / 2, t2], lf * scale, FROND_STEPS)
        out.append((az, tw, sp, st, fp, ft, bl))
    return out


def fit() -> float:
    """The length scale that puts the tallest frond tip at HEIGHT (the strip is thin, so the tip centre is its top)."""
    lo, hi = 0.3, 3.0
    for _ in range(40):
        mid = (lo + hi) / 2
        top = max(p[4][-1][2] for p in plants(mid))
        lo, hi = (mid, hi) if top < HEIGHT - 4.0 else (lo, mid)
    return (lo + hi) / 2


def solids() -> tuple[list[Solid], dict]:
    scale = fit()
    holdfast = prism(HOLD_SIDES, HOLD_R, HOLD_H, chamfer_top=HOLD_CHAMFER, rotation_deg=180.0 / HOLD_SIDES)
    stipes, fronds, bladders = [], [], []
    for az, tw, sp, st, fp, ft, bl in plants(scale):
        stipes.append(stipe(sp, st))
        fronds.append(frond(fp, ft, az, tw))
        for f in bl:
            i = min(int(f * STIPE_STEPS), STIPE_STEPS - 1)
            p = sp[i] + (sp[i + 1] - sp[i]) * (f * STIPE_STEPS - i)
            w, nrm = frame(st[i], az, 0.0)
            bladders.append(bladder(p + nrm * (BLADDER_R + 2.0)))
    stipe_all = bd.Compound([holdfast] + stipes)
    parts = [Solid(up(stipe_all), "seaweed_stipe"), Solid(up(bd.Compound(fronds)), "seaweed_frond"),
             Solid(up(bd.Compound(bladders)), "seaweed_bladder")]

    whole = up(bd.Compound([stipe_all, bd.Compound(fronds), bd.Compound(bladders)]))
    lo, hi = bbox_mm(whole)
    hlo, hhi = bbox_mm(up(holdfast))
    expect(abs(lo[1]) < 0.01, f"base on Y=0, not {lo[1]:.2f}")
    expect(HEIGHT * 0.95 <= hi[1] <= HEIGHT * 1.05, f"seaweed {hi[1]:.1f} mm tall; the brief says 500 +/-5%")
    expect(abs(hlo[0] + hhi[0]) <= 1.0 and abs(hlo[2] + hhi[2]) <= 1.0, "holdfast centred on X/Z")
    expect(lo[0] < 0.0 < hi[0] and lo[2] < 0.0 < hi[2], f"bounds enclose the holdfast: x {lo[0]:.0f}..{hi[0]:.0f}, z {lo[2]:.0f}..{hi[2]:.0f}")
    expect(abs(lo[2] + hi[2]) <= 0.15 * (hi[2] - lo[2]), f"bounds centred on Z, not {(lo[2] + hi[2]) / 2:.1f}")
    v, _ = tessellate(whole)
    v = v * 1000.0
    upper = v[v[:, 1] > HEIGHT / 2]
    expect(len(upper) > 0 and upper[:, 0].mean() > 0.0, "the upper half leans toward +X")
    expect(FROND_RANGE[0] <= len(fronds) <= FROND_RANGE[1], f"{len(fronds)} fronds; the brief says 5-7")
    expect(FROND_RANGE[0] <= len(stipes) <= FROND_RANGE[1], f"{len(stipes)} stipes; the brief says 5-7")
    expect(BLADDER_RANGE[0] <= len(bladders) <= BLADDER_RANGE[1], f"{len(bladders)} bladders; the brief says 3-6")
    for s in fronds + stipes + bladders:
        expect(s.is_valid and s.volume > 0.0, "every frond, stipe and bladder is a valid solid")
    return parts, {"fronds": len(fronds), "stipes": len(stipes), "bladders": len(bladders), "bbox": (lo, hi),
                   "upper_x": float(upper[:, 0].mean())}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    parts, info = solids()
    rep = export_solids_glb(parts, d / f"{SLUG}.glb", "Seaweed")
    tris = rep["triangles"]
    expect(tris <= 8000, f"{tris} triangles; the arc allows 8000")
    s = Scene("Seaweed")
    s.node("Body", instance=rep["glb"])
    s.write(d / f"{SLUG}.tscn")
    _cameras(d)
    lo, hi = info["bbox"]
    write_entry(GROUP, SLUG, {
        "kind": "organic",
        "summary": f"Seaweed clump, 50 cm tall, leaning toward +X: an umber holdfast disc, {info['stipes']} tapered stipes, "
                   f"{info['fronds']} strap-like dark olive ruffled fronds and {info['bladders']} faceted bladders. Static; no script.",
        "tags": ["organic", "seaweed", "kelp", "flora", "static", "fronds"],
        "scene": res(d / f"{SLUG}.tscn"),
        "footprint_mm": [round(hi[0] - lo[0], 1), round(hi[2] - lo[2], 1)],
        "stand_out_mm": round(hi[1], 1),
        "mount": "holdfast on Y=0, centred on X/Z at the origin; fronds lean toward +X; static, no behaviour",
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}


def _cameras(d) -> None:
    """Review cameras: the five concept viewpoints."""
    import json
    c = [0.05, 0.25, 0.0]
    cams = [
        {"name": "concept_primary", "pos": [0.3, 0.3, 0.8], "look_at": c, "fov": 40.0},
        {"name": "concept_front", "pos": [0.05, 0.25, 1.5], "look_at": c, "ortho": 0.6},
        {"name": "concept_side", "pos": [1.5, 0.25, 0.0], "look_at": c, "ortho": 0.6},
        {"name": "concept_top", "pos": [0.05, 1.5, 0.0001], "look_at": [0.05, 0.0, 0.0], "ortho": 0.6},
        {"name": "concept_bottom", "pos": [0.05, -1.5, 0.0001], "look_at": [0.05, 0.0, 0.0], "ortho": 0.6},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
