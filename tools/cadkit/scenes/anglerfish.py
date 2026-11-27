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
from scipy.interpolate import PchipInterpolator
from scipy.spatial import ConvexHull

from cadkit.solids import Solid, expect, bbox_mm, export_solids_glb
from cadkit.library import note, out_dir, res, write_entry
from cadkit.tscn import Scene

SLUG, GROUP = "anglerfish", "organics"
USES: list[str] = []
LENGTH_MM = 200.0
BODY, CAVITY, FIN, TOOTH = "interior_dark", "trim_black", "infra_metal", "concrete"

# body profile stations (z, half width, half height, centre y): one continuous teardrop from the tail root to the snout
PZ = [0.0, 22.0, 48.0, 76.0, 104.0, 132.0, 158.0, 184.0, 206.0, 222.0]
PRX = [6.0, 8.0, 13.0, 25.0, 38.0, 48.0, 52.0, 48.0, 36.0, 18.0]
PRY = [9.0, 12.0, 20.0, 36.0, 56.0, 70.0, 74.0, 68.0, 52.0, 28.0]
PCY = [3.0, 3.0, 3.0, 5.0, 7.0, 8.0, 8.0, 6.0, 3.0, 0.0]
HEAD_Z = 120.0                         # where the head starts (the head is about half the length)
YL = 14.0                              # the upper lip's underside
ZB = 150.0                             # the underside flattens to the lip from here forward
SLANT = 0.45                           # the upper face's backward lean per mm of height above the lip
TEETH_UP, TEETH_LO = 14, 13


def prof(z: float) -> tuple[float, float, float]:
    return (float(PchipInterpolator(PZ, PRX)(z)), float(PchipInterpolator(PZ, PRY)(z)), float(PchipInterpolator(PZ, PCY)(z)))


def lip_y(z: float) -> float:
    """The upper lip's underside: sloping down toward the front, so the gape is a wedge, wide at the back and nearly shut at the tip."""
    return 24.0 - 0.10 * (z - 150.0)


def floor_y(z: float) -> float:
    """The lower jaw's top surface: rising toward the tip, so the jaw is upturned."""
    return -28.0 + 0.25 * max(0.0, z - 120.0)


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


def loft(zs, rx_of, ry_of, cy_of, segs: int, jitter: float, seed: int) -> np.ndarray:
    """Elliptical rings at the stations `zs`, each ring offset half a step from the last, jittered along the radius."""
    rng = np.random.default_rng(seed)
    pts = []
    for i, z in enumerate(zs):
        for j in range(segs):
            th = 2 * math.pi * (j + 0.5 * (i % 2)) / segs
            k = 1.0 + jitter * rng.uniform(-1, 1)
            pts.append((rx_of(z) * k * math.cos(th), cy_of(z) + ry_of(z) * k * math.sin(th), z))
    return np.array(pts)


def chunks(pts: np.ndarray, segs: int, size: int, step: int) -> list[bd.Solid]:
    """Hulls of overlapping runs of `size` consecutive rings, so the surface can be concave along its length (the neck
    between head and tail) while each solid stays convex."""
    rings = len(pts) // segs
    out = []
    i = 0
    while True:
        j = min(i + size, rings)
        k = i
        while True:                    # a run squashed flat by the mouth cuts is widened until it is a solid
            try:
                out.append(hull(pts[k * segs:j * segs]))
                break
            except Exception:
                k = max(0, k - 2)
        if j >= rings:
            return out
        i += step


def teeth(upper: np.ndarray, lower: np.ndarray) -> list[bd.Solid]:
    """Rows of teeth round the front of each jaw rim, pointing across the mouth. Spacing and length vary a little."""
    out = []
    for is_up, rim, n in ((True, upper, TEETH_UP), (False, lower, TEETH_LO)):
        xz = rim[:, [0, 2]]
        hv = xz[ConvexHull(xz).vertices]
        c = hv.mean(axis=0)
        ang = np.arctan2(hv[:, 0] - c[0], hv[:, 1] - c[1])         # 0 = straight ahead (+Z)
        order = np.argsort(ang)
        arc = [(a, p) for a, p in zip(ang[order], hv[order]) if abs(a) <= math.radians(82)]
        a_arr = np.array([a for a, _ in arc])
        p_arr = np.array([p for _, p in arc])
        for k in range(n):
            t = math.radians(-78 + 156 * k / (n - 1))
            x = float(np.interp(t, a_arr, p_arr[:, 0]))
            z = float(np.interp(t, a_arr, p_arr[:, 1]))
            x, z = x * 0.93, c[1] + (z - c[1]) * 0.93                  # a little inside the rim
            if is_up:
                ln = 15.0 + 6.0 * (1 + math.cos(k * 1.9)) / 2
                y0 = lip_y(z) + 1.0
                out.append(cone((x, y0, z), (x * 0.95, lip_y(z) - ln, z - 3.0), 2.3 if k % 2 else 2.0, 4, phase=0.4 * k))
            else:
                ln = 12.0 + 7.0 * (1 + math.cos(k * 2.3 + 1)) / 2
                y0 = floor_y(z) - 1.0
                out.append(cone((x, y0, z), (x * 0.95, floor_y(z) + ln, z + 3.0), 2.4 if k % 2 else 2.1, 4, phase=0.4 * k))
    return out


def raw_solids() -> tuple[list[tuple[str, bd.Solid]], dict]:
    """Every part, as (role, solid), in the modelling frame (Z from the tail tip up to the mouth)."""
    rx_of = lambda z: prof(z)[0]
    ry_of = lambda z: prof(z)[1]
    cy_of = lambda z: prof(z)[2]
    parts: list[tuple[str, bd.Solid]] = []

    # body and head: one continuous teardrop loft, denser over the head. The mouth end is cut by a slanted face (the upper
    # lip projects furthest at the bottom and the forehead leans back) and the underside is flattened to the lip plane.
    zs = list(np.linspace(0.0, 112.0, 30)) + list(np.linspace(118.0, 222.0, 44))
    bp = loft(zs, rx_of, ry_of, cy_of, 40, 0.02, seed=3)
    lipv = np.array([lip_y(z) for z in bp[:, 2]])
    bp[:, 1] = np.where(bp[:, 2] >= ZB, np.maximum(bp[:, 1], lipv), bp[:, 1])
    z_lip = 216.0                                                     # the lip tip's z, at the lip plane
    zcut = z_lip - SLANT * (bp[:, 1] - YL)
    bp[:, 1] = np.maximum(bp[:, 1], np.where(bp[:, 2] >= ZB, lipv, -1e9))
    bp[:, 2] = np.minimum(bp[:, 2], zcut)
    upper_rim = bp[(bp[:, 1] <= np.array([lip_y(z) for z in bp[:, 2]]) + 0.01) & (bp[:, 2] >= ZB)]
    parts += [(BODY, h) for h in chunks(bp, 40, 6, 5)]

    # lower jaw: an upturned scoop that reaches past the lip, its top following the rising floor
    jz = list(np.linspace(100.0, 240.0, 44))
    jrx = lambda z: float(PchipInterpolator([100.0, 150.0, 200.0, 240.0], [36.0, 48.0, 40.0, 17.0])(z))
    jbot = lambda z: float(PchipInterpolator([100.0, 150.0, 200.0, 240.0], [-56.0, -60.0, -50.0, -30.0])(z))   # the chin line, rising to the tip
    jtop = lambda z: floor_y(z)
    jp = loft(jz, jrx, lambda z: (jtop(z) - jbot(z)) / 2, lambda z: (jtop(z) + jbot(z)) / 2, 24, 0.03, seed=5)
    lower_rim = np.array([(x, y, z) for (x, y, z) in jp if y > jtop(z) - 0.8 and z >= 150.0])
    parts += [(BODY, h) for h in chunks(jp, 36, 6, 5)]

    # the dark inside of the mouth
    cz = 170.0
    cav = np.array([(sx * w, y, z) for sx in (-1, 1) for (w, y, z) in
                    ((30.0, lip_y(140.0) + 2.0, 140.0), (26.0, lip_y(196.0) + 2.0, 196.0), (30.0, floor_y(140.0) - 1.0, 140.0), (26.0, floor_y(196.0) - 1.0, 196.0))])
    parts.append((CAVITY, hull(cav)))

    # fins: tail (fan), dorsal, ventral, a pectoral on each side
    parts.append((FIN, disc((0.0, 3.0, 8.0), 0, 30.0, 40.0, 5.0, 10)))
    zd = 78.0
    parts.append((FIN, disc((0.0, cy_of(zd) + ry_of(zd) + 8.0, zd), 0, 26.0, 24.0, 5.0, 10)))
    zv = 70.0
    parts.append((FIN, disc((0.0, cy_of(zv) - ry_of(zv) - 4.0, zv), 0, 14.0, 12.0, 5.0, 8)))
    zp = 132.0
    for sx in (-1, 1):
        parts.append((FIN, disc((sx * (rx_of(zp) + 5.0), -6.0, zp), 0, 22.0, 26.0, 5.0, 10)))

    # lure: a stalk up from the forehead, bent forward over the mouth, ending in a bulb
    def stick(a, b, r):
        a, b = np.array(a, float), np.array(b, float)
        ax = (b - a) / np.linalg.norm(b - a)
        u = np.cross(ax, (1.0, 0.0, 0.0)); u /= np.linalg.norm(u)
        v = np.cross(ax, u)
        ring_a = [a + r * (math.cos(2 * math.pi * k / 5) * u + math.sin(2 * math.pi * k / 5) * v) for k in range(5)]
        ring_b = [b + (r * 0.8) * (math.cos(2 * math.pi * k / 5) * u + math.sin(2 * math.pi * k / 5) * v) for k in range(5)]
        return hull(np.array(ring_a + ring_b))
    zf = 176.0
    forehead = (0.0, cy_of(zf) + ry_of(zf) - 4.0, zf)
    knee = (0.0, forehead[1] + 40.0, zf + 12.0)
    end = (0.0, knee[1] + 8.0, zf + 52.0)
    parts.append((BODY, stick(forehead, knee, 3.6)))
    parts.append((BODY, stick(knee, end, 3.0)))
    parts.append((FIN, hull(ellipsoid((end[0], end[1] - 2.0, end[2] + 4.0), (7.0, 8.0, 10.0), 2, 6, 0.0))))

    # eyes: small facets on each side of the upper head
    ze = 192.0
    for sx in (-1, 1):
        parts.append((FIN, hull(ellipsoid((sx * rx_of(ze) * 0.78, cy_of(ze) + ry_of(ze) * 0.45, ze), (4.5, 4.5, 4.5), 2, 5, 0.0))))

    tooth = [(TOOTH, t) for t in teeth(upper_rim, lower_rim)]
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
    # one continuous body: the main solid runs from the tail root to the snout, with its girth peak (the head) about half way
    bzs = [bbox_mm(b.shape) for b in out if b.role == BODY]
    expect((max(b[1][2] for b in bzs) - min(b[0][2] for b in bzs)) / length >= 0.7, "the body does not run the length of the fish")
    expect(0.45 <= (HEAD_Z + 0.5 * (PZ[-1] - HEAD_Z) - PZ[0]) / PZ[-1] <= 0.85, "the head is not about half the length")

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
