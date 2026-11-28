"""octopus_arm: one arm of the octopus, a shared static solid set (no scene) the octopus instances eight times (#775).

Brief: a flattened tapering form that leaves the body with a gentle rise, lies along the seabed and curls at the tip,
with a row of small flat-topped suckers along its underside. Modelled in its own frame: root at the origin end, running
along +X, Y up, the floor at Y=0. The root-to-tip chord is 0.17 to 0.19 m so eight arms span about 0.40 m with the body.
The tip curl is in plan (toward +Z) and stays within 0.04 m of the floor. Nothing goes below Y=0.

Built by a ruled loft through octagonal cross-sections placed along a spine (faceted, low-poly), the experiment of M20.
"""
import math

import build123d as bd

from cadkit.solids import Solid, at, expect, bbox_mm, export_solids_glb
from cadkit.library import out_dir, write_entry

SLUG, GROUP = "octopus_arm", "organics"
USES: list[str] = []
SECTIONS = 16
LENGTH = 204.0                                  # spine arc length, mm
W_ROOT, H_ROOT = 36.0, 26.0                     # root section: width (Z) and thickness (Y)
W_TIP, H_TIP = 3.0, 3.0
TAPER = 0.8                                     # shape of the taper: t ** TAPER
RISE, RISE_END = 14.0, 0.35                     # extra lift at the root, gone by this fraction of the length
CURL_START, CURL_TOTAL = 0.55, 120.0            # plan-view curl: starts here, total turn in degrees
SUCKER_H, SUCKER_N = 2.0, 11
SUCKER_R0, SUCKER_R1 = 4.5, 1.2
SUCKER_FROM, SUCKER_TO = 0.12, 0.88
CHORD_MIN, CHORD_MAX = 170.0, 190.0
FLOOR_BAND = 40.0
MAX_TRIANGLES = 1000


def _lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def _size(t: float) -> tuple[float, float]:
    u = t ** TAPER
    return _lerp(W_ROOT, W_TIP, u), _lerp(H_ROOT, H_TIP, u)


def _spine() -> list[tuple[tuple[float, float, float], tuple[float, float, float]]]:
    """Points (x, y, z) in mm and unit tangents, from root to tip, by small steps along the heading."""
    steps = 400
    ds = LENGTH / steps
    x = z = 0.0
    pts = []
    for i in range(steps + 1):
        t = i / steps
        heading = math.radians(CURL_TOTAL) * max(0.0, (t - CURL_START) / (1 - CURL_START)) ** 2
        w, h = _size(t)
        lift = RISE * max(0.0, 1.0 - t / RISE_END) ** 2
        y = h / 2 + SUCKER_H + 1.5 + lift
        pts.append((x, y, z, heading, lift))
        x += ds * math.cos(heading)
        z += ds * math.sin(heading)
    out = []
    for i in range(SECTIONS):
        p = pts[round(i * steps / (SECTIONS - 1))]
        q = pts[min(steps, round(i * steps / (SECTIONS - 1)) + 1)]
        r = pts[max(0, round(i * steps / (SECTIONS - 1)) - 1)]
        out.append(((p[0], p[1], p[2]), (q[0] - r[0], q[1] - r[1], q[2] - r[2])))
    return out


def _unit(v):
    n = math.sqrt(sum(c * c for c in v))
    return tuple(c / n for c in v)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _frame(tangent):
    """Unit tangent, horizontal width axis, and the thickness axis (up) perpendicular to both."""
    t = _unit(tangent)
    w = _unit(_cross((0.0, 1.0, 0.0), t))
    n = _cross(t, w)
    return t, w, n


def _section(p, tangent, width: float, height: float) -> bd.Wire:
    t, w, n = _frame(tangent)
    pts = []
    for k in range(8):
        a = math.radians(22.5 + 45.0 * k)
        c, s = width / 2 * math.cos(a), height / 2 * math.sin(a)
        pts.append(bd.Vector(*(p[i] + c * w[i] + s * n[i] for i in range(3))))
    return bd.Wire.make_polygon(pts, close=True)


def solids() -> list[Solid]:
    spine = _spine()
    wires = []
    for i, (p, tan) in enumerate(spine):
        w, h = _size(i / (SECTIONS - 1))
        wires.append(_section(p, tan, w, h))
    arm = bd.Solid.make_loft(wires, ruled=True)

    suckers = []
    for k in range(SUCKER_N):
        f = _lerp(SUCKER_FROM, SUCKER_TO, k / (SUCKER_N - 1))
        i = f * (SECTIONS - 1)
        i0 = min(int(i), SECTIONS - 2)
        fr = i - i0
        p0, t0 = spine[i0]
        p1, t1 = spine[i0 + 1]
        p = tuple(_lerp(p0[c], p1[c], fr) for c in range(3))
        tan = tuple(_lerp(t0[c], t1[c], fr) for c in range(3))
        w, h = _size(f)
        _, wd, n = _frame(tan)
        # a flat-topped hexagonal stud, standing from the underside, its flat face down
        r = _lerp(SUCKER_R0, SUCKER_R1, (k / (SUCKER_N - 1)) ** 0.8)
        r = min(r, w * 0.35)
        base = bd.Plane(origin=bd.Vector(*(p[c] - n[c] * (h / 2 - 0.5) for c in range(3))),
                        x_dir=bd.Vector(*wd), z_dir=bd.Vector(*(-n[c] for c in range(3))))
        with bd.BuildPart() as b:
            with bd.BuildSketch(base):
                bd.RegularPolygon(r, 6)
            bd.extrude(amount=SUCKER_H + 0.5)
        suckers.append(Solid(b.part, "octopus_sucker"))

    lo, hi = bbox_mm(arm)
    first, last = spine[0][0], spine[-1][0]
    chord = math.dist(first, last)
    expect(CHORD_MIN <= chord <= CHORD_MAX, f"arm chord {chord:.1f} mm; the brief says {CHORD_MIN:.0f} to {CHORD_MAX:.0f}")
    expect(last[1] + H_TIP / 2 <= FLOOR_BAND, f"tip curl reaches {last[1] + H_TIP / 2:.1f} mm above the floor; the brief allows {FLOOR_BAND:.0f}")
    expect(lo[1] >= -0.01, f"arm reaches {lo[1]:.2f} mm below the floor")
    for s in suckers:
        slo, _ = bbox_mm(s.shape)
        expect(slo[1] >= -0.01, f"a sucker reaches {slo[1]:.2f} mm below the floor")
    expect(lo[0] >= -10.0 and hi[0] > 100.0, "arm runs from the root along +X")
    return [Solid(arm, "octopus_skin")] + suckers


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    sol = solids()
    rep = export_solids_glb(sol, d / f"{SLUG}.glb", "OctopusArm")
    expect(rep["triangles"] <= MAX_TRIANGLES, f"{rep['triangles']} triangles; the brief allows {MAX_TRIANGLES}")
    lo, hi = rep["bbox_m"]
    write_entry(GROUP, SLUG, {
        "kind": "solid_set",
        "summary": "One octopus arm: flattened, tapering, rises from the body, lies on the seabed, curls at the tip; suckers underneath.",
        "tags": ["octopus", "arm", "creature", "organic"],
        "glb": rep["glb"],
        "mount": "root at the origin end, running along +X, Y up, floor at Y=0; tip curls toward +Z",
        "extent_m": [round(hi[c] - lo[c], 4) for c in range(3)],
        "triangles": rep["triangles"],
    })
    return {"slug": SLUG, "triangles": rep["triangles"]}
