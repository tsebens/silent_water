"""sea_anemone: a static sea anemone (organics, M20 experiment). No script, no behaviour.

Brief (#773, #783): about 15 cm tall, crown about 15 cm across; a flared dark-teal column on a chamfered disc base, and a
crown of roughly 60-100 short blunt pale-teal hexagonal-prism tentacles in 4-5 concentric rings, the inner ring upright
and the outer rings splayed outward. Faceted, flat-shaded. Two palette roles: anemone_column, anemone_tentacle.

Frame (the brief's, not the organics default): base on the floor at Y=0, bounds centred on X/Z, radially symmetric about
Y. Modelled Z-up (prisms stand along +Z) and turned into Y-up at the end.

Parametric: RINGS lists (tentacles, ring radius, lean from vertical, length) per ring, and TENT_SIDES, TENT_R set the
tentacle, so other organics with repeated limbs can reuse `tentacle` and `ring`.
"""
import math

import build123d as bd

from cadkit.solids import Solid, at, expect, bbox_mm, export_solids_glb, prism
from cadkit.library import out_dir, res, write_entry, note
from cadkit.tscn import Scene

SLUG, GROUP = "sea_anemone", "organics"
USES: list[str] = []

SIDES = 16                                      # column and base facets
BASE_R, BASE_H, BASE_CHAMFER = 44.0, 8.0, 3.0   # chamfered disc base
FOOT_R, WAIST_R, COLLAR_R = 34.0, 30.0, 40.0    # column radii to the corners: foot, waist, collar
FOOT_Z, WAIST_Z, COLLAR_Z = 12.0, 56.0, 98.0     # where each radius sits
DISC_R, DISC_H = 46.0, 5.0                      # the oral disc on the collar
# per ring: (count, radius on the disc, lean from vertical in degrees, length), inner to outer
RINGS = [(6, 8.0, 0.0, 48.0), (10, 18.0, 18.0, 44.0), (14, 28.0, 36.0, 40.0), (20, 37.0, 52.0, 38.0), (26, 44.0, 68.0, 36.0)]
RING_PHASE = [0.0, 0.5, 0.0, 0.5, 0.0]          # each ring's offset, in steps of its own spacing
TENT_SIDES, TENT_R, TENT_TIP = 6, 2.7, 1.0      # hexagonal prism, to the corners; the tip chamfer keeps it blunt
HEIGHT, CROWN = 150.0, 150.0
TENT_RANGE = (60, 100)


def frustum(sides: int, r0: float, r1: float, z0: float, z1: float) -> bd.Shape:
    """A faceted cone section from radius r0 at z0 to r1 at z1 (same side count, same flats)."""
    def poly(r: float, z: float) -> bd.Wire:
        pts = [(r * math.cos(math.radians(360.0 / sides * (i + 0.5))), r * math.sin(math.radians(360.0 / sides * (i + 0.5))), z)
               for i in range(sides)]
        return bd.Wire.make_polygon([bd.Vector(*p) for p in pts], close=True)
    return bd.Solid.make_loft([poly(r0, z0), poly(r1, z1)], ruled=True)


def tentacle(length: float) -> bd.Shape:
    """One blunt hexagonal-prism tentacle along +Z from the origin."""
    return prism(TENT_SIDES, TENT_R, length, chamfer_top=TENT_TIP, rotation_deg=0.0)


def ring(count: int, radius: float, lean_deg: float, length: float, phase: float, z: float) -> list[bd.Shape]:
    """`count` tentacles on a circle of `radius` at height z, leaning outward by lean_deg."""
    out = []
    for i in range(count):
        ang = 360.0 / count * (i + phase)
        t = tentacle(length).moved(bd.Location((0, 0, -1.0)))                    # sunk 1 mm into the disc
        t = t.rotate(axis=bd.Axis.Y, angle=lean_deg)                              # lean toward +X
        t = t.moved(bd.Location((radius, 0, z)))
        out.append(t.rotate(axis=bd.Axis.Z, angle=ang))
    return out


def up(shape: bd.Shape) -> bd.Shape:
    """Z-up modelling frame to Y-up: +Z becomes +Y."""
    return shape.rotate(axis=bd.Axis.X, angle=-90)


def solids() -> tuple[list[Solid], int]:
    base = prism(SIDES, BASE_R, BASE_H, chamfer_top=BASE_CHAMFER, rotation_deg=180.0 / SIDES)
    column = (frustum(SIDES, FOOT_R, FOOT_R, BASE_H - 1.0, FOOT_Z) + frustum(SIDES, FOOT_R, WAIST_R, FOOT_Z, WAIST_Z)
              + frustum(SIDES, WAIST_R, COLLAR_R, WAIST_Z, COLLAR_Z))
    disc = at(frustum(SIDES, COLLAR_R, DISC_R, COLLAR_Z - 0.01, COLLAR_Z + DISC_H), 0, 0, 0)
    body = base + column + disc
    z_top = COLLAR_Z + DISC_H
    tents: list[bd.Shape] = []
    for (n, r, lean, length), ph in zip(RINGS, RING_PHASE):
        tents += ring(n, r, lean, length, ph, z_top)
    count = len(tents)
    crown = bd.Compound(tents)

    blo, bhi = bbox_mm(up(body))
    tlo, thi = bbox_mm(up(crown))
    lo = tuple(min(a, b) for a, b in zip(blo, tlo))
    hi = tuple(max(a, b) for a, b in zip(bhi, thi))
    expect(abs(lo[1]) < 0.01, f"base on Y=0, not {lo[1]:.2f}")
    expect(HEIGHT * 0.95 <= hi[1] <= HEIGHT * 1.05, f"anemone {hi[1]:.1f} mm tall; the brief says 150 +/-5%")
    w, d = hi[0] - lo[0], hi[2] - lo[2]
    expect(0.9 * CROWN <= w <= 1.1 * CROWN and 0.9 * CROWN <= d <= 1.1 * CROWN, f"crown {w:.0f} x {d:.0f} mm; the brief says about 150")
    expect(abs(lo[0] + hi[0]) <= 3.0 and abs(lo[2] + hi[2]) <= 3.0,
           f"bounds centred on X/Z, not {(lo[0] + hi[0]) / 2:.1f}, {(lo[2] + hi[2]) / 2:.1f}")
    expect(TENT_RANGE[0] <= count <= TENT_RANGE[1], f"{count} tentacles; the brief says 60-100")
    expect(4 <= len(RINGS) <= 5, f"{len(RINGS)} rings; the brief says 4-5")
    expect(RINGS[0][2] == 0.0 and all(a[2] < b[2] for a, b in zip(RINGS, RINGS[1:])), "inner ring upright, each ring more splayed than the last")
    expect(abs(w - d) <= 4.0, f"crown {w:.1f} x {d:.1f} mm: not round")
    # radial symmetry about Y: every ring is n-fold, so tentacle centroid sits on the axis and the column is a regular prism
    cx = sum((t.bounding_box().min.X + t.bounding_box().max.X) / 2 for t in tents) / count
    cy = sum((t.bounding_box().min.Y + t.bounding_box().max.Y) / 2 for t in tents) / count
    expect(math.hypot(cx, cy) <= 1.0, f"tentacle centroid {math.hypot(cx, cy):.2f} mm off the axis: not radially symmetric")
    expect(len(body.solids()) == 1, "base, column and disc are one solid")
    return [Solid(up(body), "anemone_column"), Solid(up(crown), "anemone_tentacle")], count


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    parts, count = solids()
    rep = export_solids_glb(parts, d / f"{SLUG}.glb", "SeaAnemoneBody")
    tris = rep["triangles"]
    expect(tris <= 8000, f"{tris} triangles; the arc allows 8000")
    s = Scene("SeaAnemone")
    s.node("Body", instance=rep["glb"])
    s.write(d / f"{SLUG}.tscn")
    _cameras(d)
    write_entry(GROUP, SLUG, {
        "kind": "organic",
        "summary": f"Sea anemone, 15 cm tall and across: flared dark-teal faceted column on a chamfered disc base, crowned by {count} short "
                   "blunt pale-teal hexagonal tentacles in 5 rings, upright inside and splayed outside. Static; no script.",
        "tags": ["organic", "anemone", "sea anemone", "creature", "static", "tentacles"],
        "scene": res(d / f"{SLUG}.tscn"),
        "footprint_mm": [CROWN, CROWN],
        "stand_out_mm": HEIGHT,
        "mount": "base on Y=0, centred on X/Z, radially symmetric about Y; static, no behaviour",
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}


def _cameras(d) -> None:
    """Review cameras: the five concept viewpoints, from the brief's views."""
    import json
    c = [0.0, 0.07, 0.0]
    cams = [
        {"name": "concept_primary", "pos": [0.17, 0.2, 0.3], "look_at": c, "fov": 40.0},
        {"name": "concept_front", "pos": [0.0, 0.07, 1.0], "look_at": c, "ortho": 0.2},
        {"name": "concept_side", "pos": [1.0, 0.07, 0.0], "look_at": c, "ortho": 0.2},
        {"name": "concept_top", "pos": [0.0, 1.0, 0.0001], "look_at": [0.0, 0.0, 0.0], "ortho": 0.2},
        {"name": "concept_bottom", "pos": [0.0, -1.0, 0.0001], "look_at": [0.0, 0.0, 0.0], "ortho": 0.2},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
