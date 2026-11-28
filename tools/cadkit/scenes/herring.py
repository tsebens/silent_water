"""herring: a faceted herring (organics), rigged (#930). No script, no behaviour.

Skeleton: spine0..spine4 from the head's rear edge (z 75, where the head is one rigid piece with the eyes and gill
plates) to the tail root, then `tail` (the fin) as the last spine child; `dorsal`, `pectoral_l/r` and `pelvic_l/r` are
rigid fins parented to the spine bone they root on. The body is weighted along the spine and tail; the tail fin to
`tail`, blended with spine4 at its root. The look and triangle count at rest are those of the static fish.

Brief (#781, concept #770): about 25 cm nose to tail, centred on the origin, Y up, nose toward +Z. A fusiform body
lofted from polygon sections (sparse on the flanks), a forked tail, one dorsal fin, pectoral and pelvic fins and a round
eye. Darker blue-grey back, pale silver flank and belly: palette roles only. Fin edges and the tail carry more vertices
than the flanks.
"""
import math

import numpy as np
import build123d as bd

from cadkit.solids import Solid, at, prism, expect, bbox_mm, export_solids_glb, surfaces
from cadkit.library import out_dir, res, write_entry
from cadkit.tscn import Scene
from cadkit.skeleton import Bone, Chain, Rigid, Skeleton, lay_chain
from cadkit.skin_checks import check_skinned_glb, expect_bone_count

SLUG, GROUP = "herring", "organics"
USES: list[str] = []
LENGTH = 250.0
NOSE_Z, TAIL_Z = 125.0, -125.0
MAX_TRIANGLES = 8000
STATIC_TRIANGLES = 544                           # the unrigged herring, unchanged by the rig
# (z, half height, half width, y offset) of the body's cross sections, tail to nose
SECTIONS = [(-92, 7.5, 4.0, 0.0), (-62, 15.0, 7.5, 0.0), (-25, 25.0, 12.0, 0.0), (15, 30.0, 14.5, 0.0),
            (55, 28.5, 14.0, -0.5), (73, 26.0, 13.0, -1.0), (75, 22.5, 11.6, -1.2), (88, 21.0, 10.8, -1.5), (110, 12.0, 7.0, -3.0), (125, 3.0, 2.5, -5.0)]
RING = 12                                       # points round a section, 30 degrees apart
BACK_SIN = 0.5                                  # the back is the part of a section above sin(angle) >= this
FIN_T = 1.6
TAIL_PTS = [(7, -86), (15, -98), (25, -111), (38, -125), (27, -121), (14, -113), (0, -105),
            (-14, -113), (-27, -121), (-38, -125), (-25, -111), (-15, -98), (-7, -86)]       # (y, z)
DORSAL_PTS = [(24, 30), (36, 17), (50, 0), (34, -4), (24, -12)]
PECT_PTS = [(-10, 84), (-17, 66), (-28, 44), (-19, 55), (-12, 72)]
# operculum (gill cover): a crescent plate on each side of the head, its rear edge on the step in the body
GILL_PTS = [(13, 75), (13, 82), (6, 88), (-4, 89), (-13, 85), (-19, 78), (-21, 75)]
PELVIC_PTS = [(-25, 10), (-40, -6), (-27, -9)]


def _ring_point(sec: tuple, k: int) -> tuple[float, float, float]:
    z, hh, hw, yo = sec
    a = math.radians(30 * k)
    return (hw * math.cos(a), hh * math.sin(a) + yo, z)


def _loft(ks: list[int]) -> bd.Shape:
    wires = [bd.Wire.make_polygon([bd.Vector(*_ring_point(s, k)) for k in ks], close=True) for s in SECTIONS]
    return bd.Solid.make_loft(wires, ruled=True)


def _plate(pts: list[tuple[float, float]]) -> bd.Shape:
    """A thin plate in the YZ plane from (y, z) points, FIN_T thick about X=0."""
    face = bd.Face(bd.Wire.make_polygon([bd.Vector(0, y, z) for y, z in pts], close=True))
    return at(bd.extrude(face, amount=FIN_T, dir=(1, 0, 0)), x=-FIN_T / 2)


def _paired(pts: list[tuple[float, float]], root_x: float, lean: float) -> list[bd.Shape]:
    """A fin on each side: its root at (root_x, pts[0].y), leaning outward by `lean` degrees about the Z axis."""
    y0 = pts[0][0]
    out = []
    for side in (1, -1):
        f = at(_plate(pts), y=-y0)
        f = at(f, rz=side * lean)
        out.append(at(f, x=side * root_x, y=y0))
    return out


HEAD_Z = 75.0                                   # the spine starts at the head's rear edge
SPINE_BONES = 5
MAX_BIND_MM = 80.0
POSE = ["spine1=0,-12,0", "spine2=0,-24,0", "spine3=0,24,0", "spine4=0,20,0", "tail=0,-35,0"]   # the S-bend, tail flicked


def _skeleton(dx: float, dy: float, dz: float) -> Skeleton:
    """The herring's bones in the final (centred) frame."""
    line = [(0.0, yo + dy, z + dz) for z, _, _, yo in reversed(SECTIONS) if z <= HEAD_Z]
    spine = lay_chain("spine", line, SPINE_BONES)
    last = spine[-1]
    bones = spine + [Bone("tail", last.tail, (0.0, last.tail[1], TAIL_Z + dz), last.name)]

    def host(z: float) -> str:
        return next((b.name for b in spine if b.tail[2] <= z <= b.head[2]), spine[0].name)

    def fin(name: str, root: tuple, tip: tuple) -> Bone:
        r = (root[0] + dx, root[1] + dy, root[2] + dz)
        return Bone(name, r, (tip[0] + dx, tip[1] + dy, tip[2] + dz), host(r[2]))

    bones.append(fin("dorsal", (0.0, DORSAL_PTS[0][0], DORSAL_PTS[0][1]), (0.0, DORSAL_PTS[2][0], DORSAL_PTS[2][1])))
    for name, pts, rx, tx in (("pectoral", PECT_PTS, 9.0, 17.0), ("pelvic", PELVIC_PTS, 3.5, 11.0)):
        for side, tag in ((1, "l"), (-1, "r")):
            tip = min(pts, key=lambda q: q[0])
            bones.append(fin(f"{name}_{tag}", (side * rx, pts[0][0], pts[0][1]), (side * tx, tip[0], tip[1])))
    return Skeleton(bones)


def solids() -> tuple[list[Solid], Skeleton, list[Solid]]:
    back = _loft([1, 2, 3, 4, 5])
    flank = _loft([5, 6, 7, 8, 9, 10, 11, 0, 1])
    tail = _plate(TAIL_PTS)
    dorsal = _plate(DORSAL_PTS)
    pect = _paired(PECT_PTS, 9.0, 28.0)
    pelvic = _paired(PELVIC_PTS, 3.5, 30.0)
    gills = [at(_plate(GILL_PTS), x=11.3 * s) for s in (1, -1)]
    eyes_ring = [at(prism(8, 6.5, 1.8), x=8.4 * s, y=4.0, z=100.0, ry=90 * s) for s in (1, -1)]
    eyes_pupil = [at(prism(8, 3.6, 2.6), x=8.4 * s, y=4.0, z=100.0, ry=90 * s) for s in (1, -1)]

    tags = [("pectoral_l", "pectoral_r"), ("pelvic_l", "pelvic_r")]
    spine = [f"spine{i}" for i in range(SPINE_BONES)]
    along = Chain(spine + ["tail"])
    parts = [(back, "fish_back", along), (flank, "fish_flank", along), (tail, "fish_fin", Chain([spine[-1], "tail"])),
             (dorsal, "fish_fin", Rigid("dorsal")),
             *[(f, "fish_fin", Rigid(n)) for f, n in zip(pect + pelvic, tags[0] + tags[1])],
             *[(g, "fish_fin", Rigid("spine0")) for g in gills], *[(e, "fish_flank", Rigid("spine0")) for e in eyes_ring],
             *[(e, "trim_black", Rigid("spine0")) for e in eyes_pupil]]
    # centre the whole fish on the origin in X and Y (Z is designed about it)
    lo = [min(bbox_mm(p)[0][i] for p, _, _ in parts) for i in range(3)]
    hi = [max(bbox_mm(p)[1][i] for p, _, _ in parts) for i in range(3)]
    dx, dy, dz = -(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -(lo[2] + hi[2]) / 2
    parts = [(at(p, x=dx, y=dy, z=dz), r, b) for p, r, b in parts]
    tail, dorsal = at(tail, x=dx, y=dy, z=dz), at(dorsal, x=dx, y=dy, z=dz)
    fins = [at(f, x=dx, y=dy, z=dz) for f in pect + pelvic] + [tail, dorsal]
    body = at(back, x=dx, y=dy, z=dz) + at(flank, x=dx, y=dy, z=dz)

    lo = [min(bbox_mm(p)[0][i] for p, _, _ in parts) for i in range(3)]
    hi = [max(bbox_mm(p)[1][i] for p, _, _ in parts) for i in range(3)]
    expect(240.0 <= hi[2] - lo[2] <= 260.0, f"herring {hi[2] - lo[2]:.0f} mm long; the brief says about 250")
    expect(all(abs(lo[i] + hi[i]) < 1.0 for i in range(3)), f"herring bounds {lo}..{hi} are not centred on the origin")
    blo, bhi = bbox_mm(body)
    expect(bhi[2] - blo[2] > 0.8 * (hi[2] - lo[2]) and abs(bhi[2] - hi[2]) < 1.0,
           "the body's snout is the nose, toward +Z, and the tail is at -Z")
    expect(bhi[2] > 0 > blo[2] and abs(bhi[2]) > abs(blo[2]) * 0.9, "body runs from the tail (-Z) to the nose (+Z)")
    # the eyes sit on the head, forward of the middle: the nose is the +Z end
    expect(all(bbox_mm(e)[0][2] > 0 for e in eyes_ring), "the eyes are on the head, toward +Z")
    ts = [v for v in tail.vertices()]
    tlo, thi = bbox_mm(tail)
    mid = (tlo[1] + thi[1]) / 2
    upper = [v for v in ts if v.Y > mid + 10 and v.Z < tlo[2] + 1]
    lower = [v for v in ts if v.Y < mid - 10 and v.Z < tlo[2] + 1]
    notch = [v for v in ts if abs(v.Y - mid) < 2 and v.Z < thi[2] - 15]
    expect(upper and lower and max(v.Y for v in upper) - min(v.Y for v in lower) > 50.0,
           "the tail tips are not separated in Y: no fork")
    tip_z = min(v.Z for v in upper)
    expect(notch and min(v.Z for v in notch) > tip_z + 12.0, "the fork's notch is not cut back from the tips")
    for f in fins:
        flo, fhi = bbox_mm(f)
        expect(flo[2] >= lo[2] - 0.01 and fhi[2] <= hi[2] + 0.01, "a fin reaches beyond the body's length")
    dlo, dhi = bbox_mm(dorsal)
    expect(dlo[2] > lo[2] + 40 and dhi[2] < hi[2] - 40, "the dorsal fin sits mid-body, within its length")
    skel = _skeleton(dx, dy, dz)
    expect(skel.names()[:SPINE_BONES] == spine and skel.bone("tail").parent == spine[-1], "the tail bone is the last spine child")
    expect(abs(skel.bone("tail").tail[2] - lo[2]) < 1.0, "the tail bone ends at the fork's tips")
    expect(skel.bone("dorsal").parent not in ("spine0", "tail"), "the dorsal fin roots on the mid-body spine")
    return [Solid(p, r, b) for p, r, b in parts], skel, [Solid(p, r) for p, r, _ in parts]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    bound, skel, static = solids()
    expect_bone_count(skel, SLUG)
    rep = export_solids_glb(bound, d / f"{SLUG}.glb", "Herring", skeleton=skel)
    tris = rep["triangles"]
    static_pos = np.concatenate([sf[1] for sf in surfaces(static)]) * 1000.0
    check_skinned_glb(d / f"{SLUG}.glb", SLUG, max_bind_mm=MAX_BIND_MM, static_mm=static_pos)
    expect(tris == STATIC_TRIANGLES, f"{tris} triangles; the static herring has {STATIC_TRIANGLES}")
    expect(tris <= MAX_TRIANGLES, f"{tris} triangles; the organics budget is {MAX_TRIANGLES}")
    s = Scene("Herring")
    s.node("Body", instance=rep["glb"])
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "organic",
        "summary": "Rigged faceted herring, about 25 cm: blue-grey back, silver flank, forked tail, dorsal, pectoral and "
                   "pelvic fins, round eye. Skinned to a 5-bone spine, tail and fin bones. No script.",
        "tags": ["herring", "fish", "creature", "organic", "rigged"],
        "scene": res(d / f"{SLUG}.tscn"),
        "footprint_mm": [60, LENGTH],
        "mount": "centred on the origin, Y up, nose toward +Z",
        "triangles": tris,
    }, bones=skel.names())
    return {"slug": SLUG, "triangles": tris}
