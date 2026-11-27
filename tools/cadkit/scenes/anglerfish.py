"""anglerfish: a deep-sea anglerfish as a faceted static model (organics; the M20 CAD experiment).

Brief (#771, concept anglerfish_primary.png and four views): about 20 cm mouth to tail, centred on the origin, Y up, mouth
toward +Z. A bulky, densely faceted head about half the body length, a wide mouth slightly open with a lower jaw, long thin
teeth as separate solids, a bent lure stalk from the forehead ending in a bulb, small eyes, rounded pectoral, dorsal, ventral
and tail fins, and a tapering sparse-facet body. A static mesh: no script, no behaviour (the lure does not light).

Every part is a convex hull of a deterministic point set (flat facets by construction); the head and jaw are ellipsoid
point clouds with a little jitter so the facets are uneven, as in the concept. Modelled in millimetres with the tail tip at
Z=0 and the mouth toward +Z, then shifted so the bounding box is centred on the origin.

Palette: there is no umber role, so the body is `interior_dark`, the mouth cavity `trim_black`, the fins, eyes and lure bulb
`infra_metal` (grey) and the teeth `concrete` (pale).
"""
import json
import math

import build123d as bd
import numpy as np
from scipy.spatial import ConvexHull

from cadkit.solids import Solid, expect, bbox_mm, export_solids_glb
from cadkit.library import note, out_dir, res, write_entry
from cadkit.tscn import Scene

SLUG, GROUP = "anglerfish", "organics"
USES: list[str] = []
LENGTH_MM = 200.0
BODY, CAVITY, FIN, TOOTH = "interior_dark", "trim_black", "infra_metal", "concrete"

HEAD_C = (0.0, 6.0, 138.0)             # head ellipsoid centre and radii
HEAD_R = (44.0, 50.0, 62.0)
MOUTH_UP_Y, MOUTH_LO_Y = 0.0, -22.0   # the upper lip's underside and the lower jaw's top, at the front; the gap is the open mouth
TEETH_UP, TEETH_LO = 13, 11


def hull(points) -> bd.Solid:
    """A convex polyhedron from a point set: one triangular face per hull facet."""
    pts = np.asarray(points, float)
    h = ConvexHull(pts)
    faces = []
    for tri, eq in zip(h.simplices, h.equations):
        a, b, c = pts[tri]
        if np.dot(np.cross(b - a, c - a), eq[:3]) < 0:     # wind outward
            b, c = c, b
        faces.append(bd.Face(bd.Wire.make_polygon([bd.Vector(*a), bd.Vector(*b), bd.Vector(*c)], close=True)))
    return bd.Solid(bd.Shell(faces))


def ellipsoid(centre, radii, rings: int, segs: int, jitter: float = 0.0, seed: int = 0) -> np.ndarray:
    """Points on an ellipsoid in `rings` latitude bands of `segs` points, plus the poles, jittered along the radius."""
    rng = np.random.default_rng(seed)
    cx, cy, cz = centre
    rx, ry, rz = radii
    pts = [(cx, cy, cz + rz), (cx, cy, cz - rz)]                       # poles on Z
    for i in range(1, rings + 1):
        phi = math.pi * i / (rings + 1)
        for j in range(segs):
            th = 2 * math.pi * (j + 0.5 * (i % 2)) / segs
            k = 1.0 + jitter * rng.uniform(-1, 1)
            pts.append((cx + rx * k * math.sin(phi) * math.cos(th), cy + ry * k * math.sin(phi) * math.sin(th),
                        cz + rz * k * math.cos(phi)))
    return np.array(pts)


def disc(centre, axis_dir: int, ru: float, rv: float, thick: float, n: int, tilt_deg: float = 0.0) -> bd.Solid:
    """A rounded fin: an n-gon of radii (ru, rv) in the plane normal to axis `axis_dir` (0 = X), `thick` mm thick."""
    cx, cy, cz = centre
    pts = []
    for k in range(n):
        a = 2 * math.pi * k / n
        u, v = ru * math.cos(a), rv * math.sin(a)
        for s in (-thick / 2, thick / 2):
            if axis_dir == 0:       # plane YZ (a fin standing in the body's mid-plane's side), u along Z, v along Y
                pts.append((cx + s, cy + v, cz + u))
            else:                   # axis_dir 1: plane XZ (a horizontal fin), u along Z, v along X
                pts.append((cx + v, cy + s, cz + u))
    p = np.array(pts)
    if tilt_deg:
        t = math.radians(tilt_deg)
        c = np.array(centre)
        q = p - c
        rot = np.array([[math.cos(t), 0, math.sin(t)], [0, 1, 0], [-math.sin(t), 0, math.cos(t)]])
        p = q @ rot.T + c
    return hull(p)


def cone(base_c, tip, r: float, sides: int = 4, phase: float = 0.0) -> bd.Solid:
    """A thin pyramid from a base centre to a tip (a tooth)."""
    base_c, tip = np.array(base_c, float), np.array(tip, float)
    ax = tip - base_c
    ax /= np.linalg.norm(ax)
    u = np.cross(ax, (1.0, 0.0, 0.0) if abs(ax[0]) < 0.9 else (0.0, 1.0, 0.0))
    u /= np.linalg.norm(u)
    v = np.cross(ax, u)
    ring = [base_c + r * (math.cos(phase + 2 * math.pi * k / sides) * u + math.sin(phase + 2 * math.pi * k / sides) * v)
            for k in range(sides)]
    return hull(np.array(ring + [tip]))


def teeth(upper: bool) -> list[bd.Solid]:
    """A row of teeth round the front of a jaw, pointing across the mouth. Spacing and length vary a little."""
    n = TEETH_UP if upper else TEETH_LO
    out = []
    cz = HEAD_C[2] - 8.0
    for k in range(n):
        t = math.radians(-78 + 156 * k / (n - 1))        # round the front: -78 to +78 degrees from straight ahead
        rx = (HEAD_R[0] - 7.0) if upper else (HEAD_R[0] - 4.0)
        rz = (HEAD_R[2] - 7.0) if upper else (HEAD_R[2] - 4.0)
        x, z = rx * math.sin(t), cz + rz * math.cos(t)
        if upper:
            ln = 15.0 + 5.0 * (1 + math.cos(k * 1.9)) / 2          # 12 to 16 mm
            base = (x, MOUTH_UP_Y + 1.0, z)
            tip = (x * 0.96, MOUTH_UP_Y - ln, z - 1.5)
        else:
            ln = 12.0 + 6.0 * (1 + math.cos(k * 2.3 + 1)) / 2        # 9 to 14 mm
            base = (x, MOUTH_LO_Y - 1.0, z + 3.0)
            tip = (x * 0.96, MOUTH_LO_Y + ln, z + 1.5)
        out.append(cone(base, tip, 2.3 if k % 2 else 2.0, 4, phase=0.4 * k))
    return out


def raw_solids() -> tuple[list[tuple[str, bd.Solid]], dict]:
    """Every part, as (role, solid), in the modelling frame (Z from the tail tip up to the mouth)."""
    cx, cy, cz = HEAD_C
    rx, ry, rz = HEAD_R
    parts: list[tuple[str, bd.Solid]] = []

    # head: an ellipsoid cloud, flattened onto the upper lip plane below and jittered into uneven facets
    hp = ellipsoid(HEAD_C, HEAD_R, 6, 11, 0.04, seed=3)
    upper = hp.copy()
    upper[:, 1] = np.maximum(upper[:, 1], MOUTH_UP_Y)
    # lower jaw: a shallower ellipsoid that sits lower and pokes further forward than the lip, flat on top
    lp = ellipsoid((0.0, MOUTH_LO_Y - 10.0, cz + 6.0), (rx - 1.0, 36.0, rz + 2.0), 4, 9, 0.05, seed=5)
    lower = lp.copy()
    lower[:, 1] = np.minimum(lower[:, 1], MOUTH_LO_Y)
    # the cavity: the dark inside of the mouth, shrunk so it shows only as the gap's depth
    cav = ellipsoid((0.0, (MOUTH_UP_Y + MOUTH_LO_Y) / 2, cz - 6.0), (rx - 8.0, 10.0, rz - 8.0), 3, 8, 0.0)
    cav[:, 1] = np.clip(cav[:, 1], MOUTH_LO_Y - 1.0, MOUTH_UP_Y + 1.0)
    parts += [(BODY, hull(upper)), (BODY, hull(lower)), (CAVITY, hull(cav))]

    # body: three rings tapering from the head back to the tail root; sparse facets
    ring = lambda z, x_r, y_r, n=7, off=0.0: [(x_r * math.cos(2 * math.pi * k / n + off), 4.0 + y_r * math.sin(2 * math.pi * k / n + off), z)
                                              for k in range(n)]
    body = ring(118.0, 40.0, 42.0) + ring(82.0, 30.0, 33.0, off=0.2) + ring(46.0, 12.0, 14.0)
    parts.append((BODY, hull(np.array(body))))

    # fins: tail (fan), dorsal, ventral, a pectoral on each side
    parts.append((FIN, disc((0.0, 4.0, 22.0), 0, 26.0, 34.0, 5.0, 9)))
    parts.append((FIN, disc((0.0, 38.0, 82.0), 0, 22.0, 18.0, 5.0, 8)))
    parts.append((FIN, disc((0.0, -22.0, 70.0), 0, 14.0, 11.0, 5.0, 7)))
    for sx in (-1, 1):
        stub = hull(np.array([(sx * 30.0, -4.0 + dy, 98.0 + dz) for dy in (-4.0, 4.0) for dz in (-4.0, 4.0)]
                             + [(sx * 44.0, -4.0 + dy, 98.0 + dz) for dy in (-3.0, 3.0) for dz in (-3.0, 3.0)]))
        parts.append((BODY, stub))
        parts.append((FIN, disc((sx * 47.0, -4.0, 94.0), 0, 18.0, 20.0, 5.0, 9)))

    # lure: a stalk up from the forehead, bent forward over the mouth, ending in a bulb
    def stick(a, b, r):
        a, b = np.array(a, float), np.array(b, float)
        ax = (b - a) / np.linalg.norm(b - a)
        u = np.cross(ax, (1.0, 0.0, 0.0)); u /= np.linalg.norm(u)
        v = np.cross(ax, u)
        ring_a = [a + r * (math.cos(2 * math.pi * k / 5) * u + math.sin(2 * math.pi * k / 5) * v) for k in range(5)]
        ring_b = [b + (r * 0.8) * (math.cos(2 * math.pi * k / 5) * u + math.sin(2 * math.pi * k / 5) * v) for k in range(5)]
        return hull(np.array(ring_a + ring_b))
    forehead = (0.0, cy + ry - 6.0, cz + 4.0)
    knee = (0.0, 108.0, cz - 14.0)
    end = (0.0, 112.0, cz + 18.0)
    parts.append((BODY, stick(forehead, knee, 4.2)))
    parts.append((BODY, stick(knee, end, 3.4)))
    parts.append((FIN, hull(ellipsoid((end[0], end[1] - 4.0, end[2] + 4.0), (8.0, 9.0, 10.0), 2, 6, 0.0))))

    # eyes: small facets on each side of the upper head
    for sx in (-1, 1):
        parts.append((FIN, hull(ellipsoid((sx * 31.0, 28.0, cz + 38.0), (4.5, 4.5, 4.5), 2, 5, 0.0))))

    tooth = [(TOOTH, t) for t in teeth(True) + teeth(False)]
    return parts + tooth, {"teeth": len(tooth)}


def solids() -> list[Solid]:
    parts, info = raw_solids()
    # the parts are drawn at a convenient size; scale them all so mouth to tail is LENGTH_MM, then centre the bounding box
    zs = [bbox_mm(s) for _, s in parts]
    k = LENGTH_MM / (max(b[1][2] for b in zs) - min(b[0][2] for b in zs))
    parts = [(role, s.scale(k)) for role, s in parts]
    los, his = zip(*(bbox_mm(s) for _, s in parts))
    lo = np.min(np.array(los), axis=0)
    hi = np.max(np.array(his), axis=0)
    c = (lo + hi) / 2
    out = [Solid(s.moved(bd.Location((-c[0], -c[1], -c[2]))), role) for role, s in parts]

    blo = np.min([bbox_mm(s.shape)[0] for s in out], axis=0)
    bhi = np.max([bbox_mm(s.shape)[1] for s in out], axis=0)
    length = bhi[2] - blo[2]
    expect(abs(length - LENGTH_MM) <= 0.05 * LENGTH_MM, f"{length:.1f} mm mouth to tail along Z; the brief says 200 +/- 5%")
    expect(all(abs(blo[i] + bhi[i]) < 0.1 for i in range(3)), f"bounding box not centred: {blo} to {bhi}")

    # the mouth is toward +Z: the teeth and the lower jaw lie in the +Z half, the tail fin in the -Z half
    tooth_z = np.mean([bbox_mm(s.shape)[1][2] for s in out if s.role == TOOTH])
    tail = next(s for s in out if s.role == FIN)
    expect(tooth_z > 0, "the teeth are not toward +Z")
    expect(bbox_mm(tail.shape)[1][2] < 0.0, "the tail fin is not in the -Z half")
    # the head is about half the body length: the head solid spans its share of the Z length
    head = out[0]
    hz = bbox_mm(head.shape)
    expect(0.40 <= (hz[1][2] - hz[0][2]) / length <= 0.65, f"head is {(hz[1][2] - hz[0][2]) / length:.2f} of the length; the brief says about half")

    teeth_solids = [s for s in out if s.role == TOOTH]
    expect(len(teeth_solids) >= 16, f"{len(teeth_solids)} teeth; the concept shows about twenty")
    expect(all(len(s.shape.solids()) == 1 for s in teeth_solids), "each tooth is its own solid")
    for s in teeth_solids:
        lo_t, hi_t = bbox_mm(s.shape)
        expect(max(hi_t[i] - lo_t[i] for i in range(3)) <= 24.0, "a tooth is longer than 24 mm")
    for s in out:
        expect(s.shape.is_valid, f"a {s.role} solid is not a valid solid")
    roles = {s.role for s in out}
    expect(roles <= {BODY, CAVITY, FIN, TOOTH}, f"unexpected roles {roles}")
    return out


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body = solids()
    rep = export_solids_glb(body, d / f"{SLUG}_body.glb", "AnglerfishBody")
    s = Scene("Anglerfish")
    s.node("Body", instance=rep["glb"])
    s.write(d / f"{SLUG}.tscn")
    _cameras(d, rep["bbox_m"])
    write_entry(GROUP, SLUG, {
        "kind": "organic",
        "summary": "A faceted static anglerfish about 20 cm long: bulky head, open mouth with separate teeth, lure stalk and bulb, fins.",
        "tags": ["organic", "creature", "anglerfish", "static", "faceted"],
        "scene": res(d / f"{SLUG}.tscn"),
        "size_m": [round(rep["bbox_m"][1][i] - rep["bbox_m"][0][i], 4) for i in range(3)],
        "frame": "centred on the origin, Y up, mouth toward +Z",
        "mount": "none: free-standing, centred on the origin (no mount face)",
        "triangles": rep["triangles"],
        "teeth": sum(1 for s in body if s.role == TOOTH)})
    return {"slug": SLUG, "triangles": rep["triangles"]}


def _cameras(d, bbox_m) -> None:
    """Review cameras, one per concept view (the camera names are in brief.yaml), the fish ~0.2 m long at the origin."""
    cams = [
        {"name": "concept_primary", "pos": [-0.24, 0.13, 0.27], "look_at": [0.0, 0.0, 0.01], "fov": 40.0},
        {"name": "concept_front", "pos": [0.0, 0.02, 0.9], "look_at": [0.0, 0.02, 0.0], "ortho": 0.27},
        {"name": "concept_side", "pos": [-0.9, 0.02, 0.0], "look_at": [0.0, 0.02, 0.0], "ortho": 0.27},
        {"name": "concept_top", "pos": [0.0, 0.3, 0.26], "look_at": [0.0, 0.0, 0.01], "fov": 40.0},
        {"name": "three_quarter_right", "pos": [0.24, 0.1, 0.27], "look_at": [0.0, 0.0, 0.01], "fov": 40.0},
        {"name": "rear", "pos": [0.12, 0.08, -0.4], "look_at": [0.0, 0.0, 0.0], "fov": 40.0},
        {"name": "concept_bottom", "pos": [0.0, -0.9, 0.0], "look_at": [0.0, 0.0, 0.0], "ortho": 0.27},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
