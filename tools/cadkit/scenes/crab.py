"""crab (organics): a static faceted crab about 200 mm across the legs, standing on the floor, claws toward +Z.

Concept #772: assets/models/organics/crab/concept/. A broad oval carapace, an underside plate, two bone claws held
forward (arm segments, palm, fixed and moving finger, built once and mirrored), eight jointed walking legs in two
groups of four (one leg built as a segment chain per slot, mirrored), two eye stalks. Faceted, flat-shaded.
Two palette roles: creature_shell (carapace and legs, rust) and creature_bone (claws, underside, collars, eye stalks).
No script, no behaviour.

Frame (the brief's floor frame, not the origin-centred organics default): Y up, the tips of the legs on Y=0, centred on
X, the carapace centred on Z=0, claws toward +Z. Everything is a solid made of ruled lofts of small polygons (nothing is
boolean-unioned): a leg root runs into the carapace and the carapace hides it.
"""
import json
import math

import build123d as bd
import numpy as np

from cadkit.solids import Solid, expect, bbox_mm, export_solids_glb
from cadkit.library import out_dir, res, write_entry, note
from cadkit.tscn import Scene

SLUG, GROUP = "crab", "organics"
USES: list[str] = []
MAX_TRIANGLES = 8000
SPAN = 200.0                                    # across the legs, X
SHELL, BONE = "creature_shell", "creature_bone"

CARA_X, CARA_Z, CARA_SIDES = 56.0, 44.0, 16     # carapace semi-axes and facets round it
CARA_RINGS = [(28.0, 0.86), (34.0, 1.0), (46.0, 0.9), (55.0, 0.6), (59.0, 0.28)]    # (height, scale)
UNDER_RINGS = [(20.0, 0.70), (29.5, 0.90)]
# legs, front to back: (root z, splay), the joints are built from LEG_JOINTS scaled by splay in Z
LEGS = [(24.0, 1.0), (8.0, 0.5), (-8.0, -0.5), (-24.0, -1.0)]
# joint chain of a leg on +X, (x, y, dz) where dz is the Z travel from the root times the splay, and radius there
LEG_JOINTS = [(0.0, 36.0, 0.0, 6.4), (16.0, 58.0, 8.0, 5.8), (38.0, 46.0, 24.0, 4.8), (48.0, 26.0, 34.0, 3.8), (52.0, 0.0, 42.0, 1.2)]
COLLAR_K, COLLAR_LEN = 1.4, 3.2
# claw on +X: shoulder, elbow, wrist, palm axis, finger roots and tips (mm)
CLAW_ARM = [((36.0, 36.0, 30.0), 8.5), ((62.0, 34.0, 44.0), 9.0), ((52.0, 30.0, 66.0), 8.0)]
PALM_AXIS = ((50.0, 30.0, 66.0), (36.0, 27.0, 98.0))
PALM_R = (19.0, 15.0)
FINGERS = [((32.0, 22.0, 94.0), (16.0, 16.0, 134.0)), ((32.0, 36.0, 94.0), (19.0, 21.0, 130.0))]    # fixed, moving
FINGER_R0, FINGER_R1 = 9.0, 1.4
EYE = [((16.0, 52.0, 34.0), (17.0, 66.0, 38.0), 2.6), ((17.0, 66.0, 38.0), (17.0, 70.5, 39.0), 3.8)]


def v(*a: float) -> np.ndarray:
    return np.array(a, dtype=float)


def poly(pts: list[np.ndarray]) -> bd.Wire:
    return bd.Wire.make_polygon([bd.Vector(*map(float, p)) for p in pts], close=True)


def basis(axis: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    a = np.cross(axis, v(0, 1, 0))
    if np.linalg.norm(a) < 1e-6:
        a = np.cross(axis, v(1, 0, 0))
    a /= np.linalg.norm(a)
    return a, np.cross(axis, a)


def ring(c: np.ndarray, axis: np.ndarray, r: float, sides: int = 6, sx: float = 1.0, sy: float = 1.0) -> bd.Wire:
    a, b = basis(axis / np.linalg.norm(axis))
    return poly([c + r * (sx * math.cos(2 * math.pi * k / sides) * a + sy * math.sin(2 * math.pi * k / sides) * b)
                 for k in range(sides)])


def seg(p0, p1, r0: float, r1: float, sides: int = 6) -> bd.Shape:
    """A tapered hexagonal prism from p0 to p1 (ruled loft of two rings square to the axis)."""
    p0, p1 = v(*p0), v(*p1)
    return bd.Solid.make_loft([ring(p0, p1 - p0, r0, sides), ring(p1, p1 - p0, r1, sides)], ruled=True)


def dome(rings, sx: float, sz: float, cz: float, sides: int) -> bd.Shape:
    """A faceted dome: ruled loft of horizontal elliptical polygons (height, scale)."""
    ws = [poly([v(sc * sx * math.cos(2 * math.pi * (k + 0.5) / sides), h, cz + sc * sz * math.sin(2 * math.pi * (k + 0.5) / sides))
                for k in range(sides)]) for h, sc in rings]
    return bd.Solid.make_loft(ws, ruled=True)


def mirror(s: bd.Shape) -> bd.Shape:
    return s.mirror(bd.Plane.YZ)


def leg_points(z0: float, splay: float) -> list[np.ndarray]:
    """Joints of a leg on +X. The root sits on the carapace edge at its height, then the chain goes out, up, and down."""
    root_x = CARA_X * 0.9 * math.sqrt(max(0.0, 1.0 - (z0 / CARA_Z) ** 2)) - 3.0
    return [v(root_x + x, y, z0 + dz * splay) for x, y, dz, _ in LEG_JOINTS]


def leg(z0: float, splay: float) -> tuple[bd.Shape, list[bd.Shape]]:
    pts = leg_points(z0, splay)
    radii = [j[3] for j in LEG_JOINTS]
    segs = [seg(pts[i], pts[i + 1], radii[i], radii[i + 1]) for i in range(len(pts) - 1)]
    collars = []
    for i in range(1, len(pts) - 1):
        t = (pts[i + 1] - pts[i - 1])
        t = t / np.linalg.norm(t)
        collars.append(seg(pts[i] - t * COLLAR_LEN / 2, pts[i] + t * COLLAR_LEN / 2, radii[i] * COLLAR_K, radii[i] * COLLAR_K))
    return bd.Compound(segs), collars


def claw() -> bd.Shape:
    arm = [seg(CLAW_ARM[i][0], CLAW_ARM[i + 1][0], CLAW_ARM[i][1], CLAW_ARM[i + 1][1]) for i in range(len(CLAW_ARM) - 1)]
    p0, p1 = v(*PALM_AXIS[0]), v(*PALM_AXIS[1])
    ax = p1 - p0
    # the palm is a faceted swelling: ring sizes along its axis; wider than high
    prof = [(0.0, 0.55), (0.3, 1.0), (0.75, 1.0), (1.0, 0.7)]
    palm = bd.Solid.make_loft([ring(p0 + ax * t, ax, 1.0, 8, sx=PALM_R[0] * f, sy=PALM_R[1] * f) for t, f in prof], ruled=True)
    fingers = [seg(a, b, FINGER_R0, FINGER_R1) for a, b in FINGERS]
    return bd.Compound(arm + [palm] + fingers)


def solids() -> tuple[list[Solid], dict]:
    carapace = dome(CARA_RINGS, CARA_X, CARA_Z, 0.0, CARA_SIDES)
    under = dome(UNDER_RINGS, CARA_X, CARA_Z, 0.0, CARA_SIDES)
    legs, collars = [], []
    for z0, splay in LEGS:
        s, c = leg(z0, splay)
        legs += [s, mirror(s)]
        collars += c + [mirror(x) for x in c]
    c1 = claw()
    claws = [c1, mirror(c1)]
    eyes = []
    for a, b, r in EYE:
        e = seg(a, b, r, r * 0.9)
        eyes += [e, mirror(e)]

    allsh = bd.Compound([carapace, under] + legs + collars + claws + eyes)
    lo, hi = bbox_mm(allsh)
    drop = lo[1]                                    # lift or sink so the tips stand on Y=0
    lo, hi = bbox_mm(allsh.moved(bd.Location((0, -drop, 0))))
    move = lambda s: s.moved(bd.Location((0, -drop, 0)))
    carapace, under = move(carapace), move(under)

    expect(abs(lo[1]) <= 0.5, f"min Y {lo[1]:.2f}: the crab stands on the floor")
    expect(abs(hi[0] - lo[0] - SPAN) <= 0.1 * SPAN, f"{hi[0] - lo[0]:.1f} mm across the legs; the brief says {SPAN:.0f} +/-10%")
    expect(abs(hi[0] + lo[0]) <= 0.5, f"left-right symmetry: x {lo[0]:.1f}..{hi[0]:.1f}")
    cl_hi = max(bbox_mm(move(c))[1][2] for c in claws)
    car_hi = bbox_mm(carapace)[1][2]
    expect(cl_hi > car_hi + 20.0, f"claws reach +Z to {cl_hi:.0f} mm, past the carapace at {car_hi:.0f}")
    expect(len(legs) == 8 and len(claws) == 2, f"{len(legs)} legs and {len(claws)} claws; the brief says 8 and 2")
    for side in (1, -1):
        n = sum(1 for s in legs if (bbox_mm(s)[0][0] + bbox_mm(s)[1][0]) * side > 0)
        expect(n == 4, f"{n} legs on the {'+' if side > 0 else '-'}X side; the brief says 4")
    for s in legs + collars + claws + eyes:
        expect(s.is_valid and s.volume > 0.0, "every part is a valid solid")
    # no leg or claw tip inside the carapace volume
    for z0, splay in LEGS:
        for sgn in (1, -1):
            p = leg_points(z0, splay)[-1]
            expect(not carapace.is_inside(bd.Vector(sgn * p[0], p[1] - drop, p[2])), f"leg tip at z {p[2]:.0f} is inside the carapace")
    for a, b in FINGERS:
        for sgn in (1, -1):
            expect(not carapace.is_inside(bd.Vector(sgn * b[0], b[1] - drop, b[2])), "a claw tip is inside the carapace")
    expect(-90.0 < lo[2] < -40.0, f"back legs reach z {lo[2]:.0f}")

    shell = bd.Compound([carapace] + [move(s) for s in legs])
    bone = bd.Compound([under] + [move(s) for s in collars + claws + eyes])
    return [Solid(shell, SHELL), Solid(bone, BONE)], {"bbox": (lo, hi), "legs": len(legs), "claws": len(claws)}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    parts, info = solids()
    rep = export_solids_glb(parts, d / f"{SLUG}.glb", "Crab")
    tris = rep["triangles"]
    expect(tris <= MAX_TRIANGLES, f"{tris} triangles; the arc allows {MAX_TRIANGLES}")
    s = Scene("Crab")
    s.node("Body", instance=rep["glb"])
    s.write(d / f"{SLUG}.tscn")
    _cameras(d)
    lo, hi = info["bbox"]
    write_entry(GROUP, SLUG, {
        "kind": "organic",
        "summary": f"Crab, about 20 cm across the legs, claws toward +Z: a rust faceted carapace, {info['legs']} jointed walking legs, "
                   f"{info['claws']} bone claws, a bone underside plate and two eye stalks. Static; no script.",
        "tags": ["organic", "crab", "creature", "static", "claws", "legs"],
        "scene": res(d / f"{SLUG}.tscn"),
        "footprint_mm": [round(hi[0] - lo[0], 1), round(hi[2] - lo[2], 1)],
        "stand_out_mm": round(hi[1], 1),
        "mount": "stands on Y=0, centred on X, carapace centred on Z=0; claws toward +Z; static, no behaviour",
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}


def _cameras(d) -> None:
    """Review cameras: the five concept viewpoints (primary three-quarter from the front left, above)."""
    c = [0.0, 0.025, 0.03]
    cams = [
        {"name": "concept_primary", "pos": [-0.2, 0.17, 0.3], "look_at": c, "fov": 40.0},
        {"name": "concept_front", "pos": [0.0, 0.03, 1.5], "look_at": c, "ortho": 0.3},
        {"name": "concept_side", "pos": [-1.5, 0.03, 0.02], "look_at": c, "ortho": 0.3},
        {"name": "concept_top", "pos": [0.0, 1.5, 0.0001], "look_at": [0.0, 0.0, 0.02], "ortho": 0.3},
        {"name": "concept_bottom", "pos": [0.0, -1.5, 0.0001], "look_at": [0.0, 0.0, 0.02], "ortho": 0.3},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
