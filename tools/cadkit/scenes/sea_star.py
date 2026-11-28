"""Sea star (organics): a static faceted sea star about 25 cm across, lying on the floor, one arm toward +Z.

Concept #774: assets/models/organics/sea_star/concept/. A small domed disc and five tapered arms, one arm built once
and repeated at 72 degrees, tips curled up, low tubercles on the upper surface and a ridge down the underside of each
arm. Ochre on top, umber below. No script, no behaviour.

The solids are open shells of triangles (nothing is boolean-unioned): the arms run into the disc and the disc's dome
covers their roots. Frame (organics, asset_process.md section 1): Y up, floor at Y=0, centred on X/Z, arm 0 on +Z.
"""
import json
import math

import build123d as bd
import numpy as np

from cadkit.solids import Solid, expect, bbox_mm, export_solids_glb
from cadkit.library import out_dir, res, write_entry, note
from cadkit.tscn import Scene

SLUG, GROUP = "sea_star", "organics"
USES: list[str] = []
MAX_TRIANGLES = 8000
ARMS = 5
R_TIP = 130.0                       # tip distance from the centre; tip to tip across two arms = 2 * R_TIP * sin 72 = 247
SPAN = 2 * R_TIP * math.sin(math.radians(72))
TOP, UNDER = "organic_ochre", "organic_umber"
# arm stations: radius, half-width, height (all mm). The root is hidden under the disc.
STATIONS = [(10, 30, 16), (45, 25, 16), (75, 17, 13), (100, 11, 10), (118, 8, 8), (130, 4, 5)]
CURL_FROM, CURL_RISE = 88.0, 20.0   # the tip lifts by CURL_RISE over the last stretch, quadratically
# ring section of an arm, (lateral fraction of half-width, height fraction): keel, right foot, right shoulder, crest, ...
RING = [(0.0, 0.0), (1.0, 0.3), (0.8, 0.75), (0.0, 1.0), (-0.8, 0.75), (-1.0, 0.3)]
UNDER_EDGES = {0, 5}                # ring edges (i -> i+1) that belong to the underside: foot-keel and keel-foot
# disc: (radius, height) rings of a 10-gon, then the apex; the underside closes at BOTTOM_Y
DISC = [(52.0, 9.0), (44.0, 18.0), (28.0, 26.0)]
APEX_Y, BOTTOM_Y, DISC_SIDES = 30.0, 3.0, 10
TUBERCLE_R = (5.5, 2.8)
TUBERCLE_H = 3.5
TUBERCLES_ON_ARM = (45.0, 70.0, 95.0)


def lift(r: float) -> float:
    return CURL_RISE * ((r - CURL_FROM) / (R_TIP - CURL_FROM)) ** 2 if r > CURL_FROM else 0.0


def station(r: float) -> tuple[float, float]:
    """Half-width and height at radius r, interpolated between stations."""
    for (r0, w0, h0), (r1, w1, h1) in zip(STATIONS, STATIONS[1:]):
        if r0 <= r <= r1:
            t = (r - r0) / (r1 - r0)
            return w0 + t * (w1 - w0), h0 + t * (h1 - h0)
    raise ValueError(r)


def arm_point(k: int, r: float, x: float, y: float) -> np.ndarray:
    """A point of arm k: radius r along it, x to its side, y up (curl included)."""
    a = math.radians(72.0 * k)
    d, l = np.array([math.sin(a), 0.0, math.cos(a)]), np.array([math.cos(a), 0.0, -math.sin(a)])
    return r * d + x * l + np.array([0.0, y + lift(r), 0.0])


def face(a, b, c, inside) -> bd.Face:
    """A triangle wound so its normal points away from `inside` (a point within the solid it bounds)."""
    a, b, c = (np.asarray(p, float) for p in (a, b, c))
    n = np.cross(b - a, c - a)
    if np.dot(n, (a + b + c) / 3.0 - np.asarray(inside, float)) < 0:
        b, c = c, b
    return bd.Face(bd.Wire.make_polygon([bd.Vector(*a), bd.Vector(*b), bd.Vector(*c)], close=True))


def arm_faces(k: int) -> tuple[list[bd.Face], list[bd.Face]]:
    """(top, underside) triangles of arm k: rings at each station, joined edge to edge, the tip fanned shut."""
    top, under = [], []
    rings = []
    for r, w, h in STATIONS:
        rings.append([arm_point(k, r, fx * w, fy * h) for fx, fy in RING])
    axis = [arm_point(k, r, 0.0, h / 2) for r, _, h in STATIONS]
    for s in range(len(rings) - 1):
        for i in range(len(RING)):
            j = (i + 1) % len(RING)
            inside = axis[s] / 2 + axis[s + 1] / 2
            dst = under if i in UNDER_EDGES else top
            a, b, c, d = rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i]
            dst += [face(a, b, c, inside), face(a, c, d, inside)]
    tip = rings[-1]
    centre = np.mean(tip, axis=0)
    for i in range(len(RING)):
        j = (i + 1) % len(RING)
        (under if i in UNDER_EDGES else top).append(face(tip[i], tip[j], centre, axis[-1]))
    return top, under


def disc_faces() -> tuple[list[bd.Face], list[bd.Face]]:
    top, under = [], []
    inside = np.array([0.0, 12.0, 0.0])

    def ring(radius: float, y: float) -> list[np.ndarray]:
        return [np.array([radius * math.sin(math.radians(360.0 / DISC_SIDES * i)), y,
                          radius * math.cos(math.radians(360.0 / DISC_SIDES * i))]) for i in range(DISC_SIDES)]
    rings = [ring(r, y) for r, y in DISC]
    for s in range(len(rings) - 1):
        for i in range(DISC_SIDES):
            j = (i + 1) % DISC_SIDES
            a, b, c, d = rings[s][i], rings[s][j], rings[s + 1][j], rings[s + 1][i]
            top += [face(a, b, c, inside), face(a, c, d, inside)]
    apex = np.array([0.0, APEX_Y, 0.0])
    for i in range(DISC_SIDES):
        top.append(face(rings[-1][i], rings[-1][(i + 1) % DISC_SIDES], apex, inside))
    bottom = np.array([0.0, BOTTOM_Y, 0.0])
    for i in range(DISC_SIDES):
        under.append(face(rings[0][i], rings[0][(i + 1) % DISC_SIDES], bottom, inside))
    return top, under


def tubercle(base: np.ndarray, phase: float) -> list[bd.Face]:
    """A low hexagonal frustum standing on `base`: a rounded bump at this budget."""
    r0, r1 = TUBERCLE_R
    low = [base + np.array([r0 * math.cos(phase + i * math.pi / 3), -1.0, r0 * math.sin(phase + i * math.pi / 3)]) for i in range(6)]
    high = [base + np.array([r1 * math.cos(phase + i * math.pi / 3), TUBERCLE_H, r1 * math.sin(phase + i * math.pi / 3)]) for i in range(6)]
    inside = base + np.array([0.0, 1.0, 0.0])
    out = []
    for i in range(6):
        j = (i + 1) % 6
        out += [face(low[i], low[j], high[j], inside), face(low[i], high[j], high[i], inside)]
    cap = base + np.array([0.0, TUBERCLE_H, 0.0])
    out += [face(high[i], high[(i + 1) % 6], cap, inside) for i in range(6)]
    return out


def tubercles() -> list[bd.Face]:
    out: list[bd.Face] = []
    for k in range(ARMS):
        for n, r in enumerate(TUBERCLES_ON_ARM):
            _, h = station(r)
            out += tubercle(arm_point(k, r, 0.0, h), phase=0.3 * n)
        a = math.radians(72.0 * k + 36.0)       # between the arms, on the dome
        out += tubercle(np.array([30.0 * math.sin(a), 22.0, 30.0 * math.cos(a)]), phase=0.5)
    out += tubercle(np.array([0.0, APEX_Y - 2.0, 0.0]), phase=0.0)
    return out


def solids() -> list[Solid]:
    top, under = disc_faces()
    for k in range(ARMS):
        t, u = arm_faces(k)
        top += t
        under += u
    top += tubercles()
    star_top, star_under = bd.Compound(top), bd.Compound(under)

    lo, hi = bbox_mm(bd.Compound(top + under))
    tips = [arm_point(k, R_TIP, 0.0, STATIONS[-1][2] / 2) for k in range(ARMS)]
    expect(abs(lo[1]) < 0.01, f"star rests on Y=0, lowest point {lo[1]:.2f} mm")
    expect(abs(hi[0] + lo[0]) < 0.5, f"star is centred in X: {lo[0]:.1f}..{hi[0]:.1f}")
    expect(abs(np.mean([t[0] for t in tips])) < 0.01 and abs(np.mean([t[2] for t in tips])) < 0.01, "arm tips centre on X/Z origin")
    expect(abs((hi[0] - lo[0]) - 247.0) < 8.0, f"across-arm span {hi[0] - lo[0]:.0f} mm; the brief says about 250")
    expect(abs(hi[2] - R_TIP) < 8.0, f"an arm tip lies on +Z at {hi[2]:.0f} mm, expected about {R_TIP:.0f}")
    radii = [math.hypot(t[0], t[2]) for t in tips]
    expect(max(radii) - min(radii) < 0.01, f"five-fold symmetry: arm tips at radii {min(radii):.2f}..{max(radii):.2f}")
    expect(hi[1] < 0.2 * SPAN, f"low profile: {hi[1]:.0f} mm tall against a {SPAN:.0f} mm span")
    mid_top = arm_point(0, 75.0, 0.0, station(75.0)[1])[1]
    tip_top = arm_point(0, R_TIP, 0.0, STATIONS[-1][2])[1]
    expect(tip_top > mid_top + 5.0, f"curled tip ({tip_top:.1f} mm) above the arm's mid-length ({mid_top:.1f} mm)")
    return [Solid(star_top, TOP), Solid(star_under, UNDER)]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    rep = export_solids_glb(solids(), d / f"{SLUG}.glb", "SeaStar")
    tris = rep["triangles"]
    expect(tris <= MAX_TRIANGLES, f"{tris} triangles; the organics budget is {MAX_TRIANGLES}")
    s = Scene("SeaStar")
    s.node("Body", instance=rep["glb"])
    s.write(d / f"{SLUG}.tscn")
    _cameras(d)
    write_entry(GROUP, SLUG, {
        "kind": "element",
        "summary": "Sea star: a static faceted creature about 25 cm across, domed disc, five tapered arms with curled tips, "
                   "tubercles on the ochre top and a ridged umber underside. Lies on the floor, one arm toward +Z. No script.",
        "tags": ["sea star", "starfish", "organic", "creature", "seabed", "static"],
        "scene": res(d / f"{SLUG}.tscn"),
        "footprint_mm": [round(SPAN), round(SPAN)],
        "stand_out_mm": round(rep["bbox_m"][1][1] * 1000),
        "mount": "lies on the floor at Y=0, centred on X/Z, one arm toward +Z",
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}


def _cameras(d) -> None:
    """Review cameras: the concept's five views (three-quarter, front, side, top, bottom)."""
    cams = [
        {"name": "concept_primary", "pos": [0.28, 0.3, 0.38], "look_at": [0.0, 0.01, 0.0], "fov": 40.0},
        {"name": "concept_front", "pos": [0.0, 0.03, 0.6], "look_at": [0.0, 0.015, 0.0], "ortho": 0.3},
        {"name": "concept_side", "pos": [0.6, 0.03, 0.0], "look_at": [0.0, 0.015, 0.0], "ortho": 0.3},
        {"name": "concept_top", "pos": [0.0, 0.6, 0.0001], "look_at": [0.0, 0.0, 0.0], "ortho": 0.3},
        {"name": "concept_bottom", "pos": [0.0, -0.6, 0.0001], "look_at": [0.0, 0.0, 0.0], "ortho": 0.3},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
