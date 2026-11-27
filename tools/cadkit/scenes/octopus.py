"""octopus: the finished octopus, a static scene (no script) of one body GLB and eight `octopus_arm` instances (#775).

Brief: a rounded faceted mantle raised and set back from the arms' root, two eyes on short bulges facing +Z with a
pupil slit, eight arms at even angles curling at the tips, a few small flat teal spots on the mantle and arms.
About 0.40 m across, resting on the floor at Y=0, centred, eyes toward +Z.
"""
import math

import build123d as bd

from cadkit.solids import Solid, at, box, prism, expect, bbox_mm, export_solids_glb
from cadkit import library
from cadkit.library import out_dir, res, write_entry
from cadkit.tscn import Scene, Xform, rot_y

SLUG, GROUP = "octopus", "organics"
USES: list[str] = ["octopus_arm"]
ARMS = 8
ARM_RADIUS = 12.0                       # where each arm's root sits from the centre, mm
MAX_ACROSS, MAX_TRIANGLES = 400.0, 8000
# mantle: octagonal sections (y, radius to the flats' corners, centre z), lofted ruled; leans back and rises
MANTLE = [(26.0, 36.0, -8.0), (48.0, 47.0, -20.0), (72.0, 45.0, -30.0), (92.0, 30.0, -38.0), (104.0, 9.0, -42.0)]
EYE_X, EYE_Y, EYE_Z0, EYE_R, EYE_L = 25.0, 58.0, 12.0, 11.0, 18.0
IRIS_R, PUPIL_W, PUPIL_H = 7.0, 2.6, 12.0
HUB_R, HUB_Y0, HUB_Y1 = 30.0, 16.0, 44.0
SPOT_R, SPOT_T = 4.5, 1.6
ARM_SPOT_ARMS = (0, 2, 4, 6)
ARM_SPOT_FRACS = (0.22, 0.45)


def _octagon(y: float, r: float, cz: float) -> bd.Wire:
    pts = [bd.Vector(r * math.cos(math.radians(22.5 + 45 * k)), y, cz + r * math.sin(math.radians(22.5 + 45 * k)))
           for k in range(8)]
    return bd.Wire.make_polygon(pts, close=True)


def _disc(origin, normal, x_dir, r: float) -> bd.Shape:
    """A flat hexagonal disc standing SPOT_T out of a surface at `origin` with outward `normal`, sunk 0.6 mm in."""
    base = bd.Plane(origin=bd.Vector(*(origin[c] - normal[c] * 0.6 for c in range(3))),
                    x_dir=bd.Vector(*x_dir), z_dir=bd.Vector(*normal))
    with bd.BuildPart() as b:
        with bd.BuildSketch(base):
            bd.RegularPolygon(r, 6)
        bd.extrude(amount=SPOT_T + 0.6)
    return b.part


def _unit(v):
    n = math.sqrt(sum(c * c for c in v))
    return tuple(c / n for c in v)


def _mantle_spots() -> list[bd.Shape]:
    """Four spots on the sloping facets between the two upper sections, at the back and sides (clear of the eyes)."""
    (_, _, _), (_, _, _), (y2, r2, c2), (y3, r3, c3), _ = MANTLE
    out = []
    for deg in (0.0, 180.0, 90.0, 225.0):
        a = math.radians(deg)
        # facet whose flat faces azimuth `deg`: apothem = r cos(22.5), radial direction (cos a, sin a) in X, Z
        ap = math.cos(math.radians(22.5))
        d = (math.cos(a), 0.0, math.sin(a))
        A = (d[0] * r2 * ap, y2, c2 + d[2] * r2 * ap)
        B = (d[0] * r3 * ap, y3, c3 + d[2] * r3 * ap)
        M = tuple((A[c] + B[c]) / 2 for c in range(3))
        t = (-d[2], 0.0, d[0])
        ab = tuple(B[c] - A[c] for c in range(3))
        n = _unit((t[1] * ab[2] - t[2] * ab[1], t[2] * ab[0] - t[0] * ab[2], t[0] * ab[1] - t[1] * ab[0]))
        if n[0] * d[0] + n[2] * d[2] < 0:
            n = tuple(-c for c in n)
        out.append(_disc(M, n, t, SPOT_R))
    return out


def _place(shape: bd.Shape, k: int) -> bd.Shape:
    """An arm-frame shape moved to where arm k stands (the same transform the instance has)."""
    th = 360.0 * k / ARMS
    c = (ARM_RADIUS * math.cos(math.radians(th)), 0.0, -ARM_RADIUS * math.sin(math.radians(th)))
    return shape.rotate(bd.Axis.Y, th).moved(bd.Location(c))


def _arm_spots(arm) -> list[bd.Shape]:
    spine = arm._spine()
    out = []
    for k in ARM_SPOT_ARMS:
        for f in ARM_SPOT_FRACS:
            i = f * (arm.SECTIONS - 1)
            i0 = int(i)
            fr = i - i0
            p0, t0 = spine[i0]
            p1, t1 = spine[i0 + 1]
            p = tuple(p0[c] + (p1[c] - p0[c]) * fr for c in range(3))
            tan = tuple(t0[c] + (t1[c] - t0[c]) * fr for c in range(3))
            w, h = arm._size(f)
            tt, wd, n = arm._frame(tan)
            top = tuple(p[c] + n[c] * h / 2 * 0.924 for c in range(3))
            out.append(_place(_disc(top, n, wd, min(SPOT_R * 0.7, w * 0.14)), k))
    return out


def solids() -> tuple[list[Solid], dict]:
    arm = library.scene_module("octopus_arm")
    mantle = bd.Solid.make_loft([_octagon(*s) for s in MANTLE], ruled=True)
    hub = at(prism(8, HUB_R, HUB_Y1 - HUB_Y0), y=HUB_Y1, rx=90)       # +Z of the prism points down; rises to HUB_Y1
    bulges = [at(prism(8, EYE_R, EYE_L), x=sx * EYE_X, y=EYE_Y, z=EYE_Z0) for sx in (-1, 1)]
    irises = [at(prism(8, IRIS_R, 1.2), x=sx * EYE_X, y=EYE_Y, z=EYE_Z0 + EYE_L - 0.3) for sx in (-1, 1)]
    pupils = [at(box(PUPIL_W, PUPIL_H, 1.0), x=sx * EYE_X, y=EYE_Y, z=EYE_Z0 + EYE_L + 0.7) for sx in (-1, 1)]
    spots = _mantle_spots() + _arm_spots(arm)

    parts = ([Solid(mantle, "octopus_skin"), Solid(hub, "octopus_skin")] + [Solid(b, "octopus_skin") for b in bulges]
             + [Solid(i, "octopus_sucker") for i in irises] + [Solid(p, "octopus_eye") for p in pupils]
             + [Solid(s, "octopus_spot") for s in spots])

    # measure the whole octopus: the body and every placed arm
    arm_sols = arm.solids()
    lo = [1e9] * 3
    hi = [-1e9] * 3
    shapes = [p.shape for p in parts] + [_place(s.shape, k) for k in range(ARMS) for s in arm_sols]
    for sh in shapes:
        a, b = bbox_mm(sh)
        lo = [min(lo[c], a[c]) for c in range(3)]
        hi = [max(hi[c], b[c]) for c in range(3)]
    width, depth = hi[0] - lo[0], hi[2] - lo[2]
    expect(width <= MAX_ACROSS and depth <= MAX_ACROSS, f"octopus {width:.0f} x {depth:.0f} mm; the brief allows {MAX_ACROSS:.0f}")
    expect(width > 0.8 * MAX_ACROSS or depth > 0.8 * MAX_ACROSS, f"octopus only {width:.0f} x {depth:.0f} mm: about 400 mm across")
    expect(lo[1] >= -0.01, f"something reaches {lo[1]:.2f} mm below the floor")
    mc = mantle.center()
    eye_c = [b.center() for b in bulges]
    expect(all(e.Z > mc.Z + 20.0 for e in eye_c), f"eyes (z {eye_c[0].Z:.0f}) must be forward of the mantle (z {mc.Z:.0f}), toward +Z")
    expect(eye_c[0].X < 0 < eye_c[1].X, "one eye either side of the centre line")
    angs = sorted(360.0 * k / ARMS for k in range(ARMS))
    gaps = {round(angs[(i + 1) % ARMS] - angs[i], 6) % 360 for i in range(ARMS)}
    expect(gaps == {360.0 / ARMS}, f"arms must be evenly spaced, got gaps {gaps}")
    return parts, {"footprint": (width, depth), "stand_out": hi[1] - max(lo[1], 0.0), "top": hi[1], "arm": arm}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    parts, info = solids()
    rep = export_solids_glb(parts, d / f"{SLUG}.glb", "OctopusBody")
    arm_entry = library.entry("octopus_arm")
    total = rep["triangles"] + ARMS * arm_entry["triangles"]
    expect(total <= MAX_TRIANGLES, f"{total} triangles including the arms; the brief allows {MAX_TRIANGLES}")
    s = Scene("Octopus", script=None)
    s.node("Body", instance=rep["glb"])
    for k in range(ARMS):
        th = 360.0 * k / ARMS
        c = (ARM_RADIUS * math.cos(math.radians(th)) / 1000, 0.0, -ARM_RADIUS * math.sin(math.radians(th)) / 1000)
        s.node(f"Arm{k}", instance=arm_entry["glb"], props={"transform": Xform(rot_y(th), c)})
    s.write(d / f"{SLUG}.tscn")
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    library.note(review / ".gdignore")
    _cameras(review)
    w, dep = info["footprint"]
    write_entry(GROUP, SLUG, {
        "kind": "element",
        "summary": "The octopus: a rounded faceted mantle raised and set back from the arms' root, two eyes on short bulges "
                   "facing +Z with pupil slits, eight curling octopus_arm instances at even angles, small flat teal spots. "
                   "Static; no script. About 0.40 m across.",
        "tags": ["octopus", "creature", "organic", "static"],
        "scene": res(d / f"{SLUG}.tscn"),
        "footprint_mm": [round(w, 1), round(dep, 1)],
        "stand_out_mm": round(info["top"], 1),
        "mount": "floor at Y=0, centred; eyes face +Z",
        "uses": ["octopus_arm"],
        "triangles": total,
    })
    return {"slug": SLUG, "triangles": total}


def _cameras(review) -> None:
    import json
    cams = [
        {"name": "octopus_primary", "pos": [0.26, 0.25, 0.34], "look_at": [0.0, 0.04, 0.0], "fov": 40.0},
        {"name": "octopus_front", "pos": [0.0, 0.05, 2.0], "look_at": [0.0, 0.05, 0.0], "ortho": 0.42},
        {"name": "octopus_side", "pos": [-2.0, 0.05, 0.0], "look_at": [0.0, 0.05, 0.0], "ortho": 0.42, "up": [0, 1, 0]},
        {"name": "octopus_top", "pos": [0.0, 2.0, 0.0], "look_at": [0.0, 0.0, 0.0], "ortho": 0.42, "up": [0, 0, -1]},
        {"name": "octopus_bottom", "pos": [0.0, -2.0, 0.0], "look_at": [0.0, 0.0, 0.0], "ortho": 0.42, "up": [0, 0, 1]},
        {"name": "overview_high", "pos": [-0.35, 0.35, 0.35], "look_at": [0.0, 0.03, 0.0], "fov": 40.0},
        {"name": "overview_low", "pos": [0.05, 0.07, 0.45], "look_at": [0.0, 0.05, 0.0], "fov": 40.0},
    ]
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    library.note(review / "cameras.json")
