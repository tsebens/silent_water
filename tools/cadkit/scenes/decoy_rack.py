"""decoy_rack: the countermeasures station's decoy rack (furniture, no script). Brief #758, concept
countermeasures_station_primary.png (the column to the right of the panel).

A flat grey column of six cradles, one above another, each a `DecoyCradle` anchor seating a `decoy`, with an engraved
plate and an orange grab rail. The decoy is 550 mm long and the column may be only 450 mm deep, so every decoy lies
tilted nose up toward the wall (as in the concept), tail out and low, and the six step up the column. An empty cradle is
a bare tilted tray with a stop at its tail end.

Frame: floor at Y=0, back on Z=0 against the hull, centred on X (the column), cradle faces toward +Z. The root has no
script; the cradle nodes are DecoyCradle (intrinsic to a cradle anchor, as CanisterSlot is to the life support's slots).
Decoy lies along the cradle's local -Z (nose), handle up its +Y, so the cradle frame is the column's turned about X.
"""
import math

import build123d as bd
import numpy as np

from cadkit.solids import Solid, at, bbox_mm, box, expect, export_solids_glb, tessellate
from cadkit.library import entry, out_dir, res, scene_module, scene_path, write_entry
from cadkit.tscn import Scene, Xform

SLUG, GROUP = "decoy_rack", "furniture"
USES: list[str] = ["decoy"]
TRIANGLE_BUDGET = 4000                      # the rack with its six decoys (Tristan, 2026-11-27, #758)

N = 6
W = 320.0                                   # column width along the hull
MAX_W, MAX_D = 450.0, 450.0                 # footprint limit (brief)
DEPTH = 444.0                               # plinth, cap and cheeks reach this far from the wall
BACK_T, CHEEK_T = 8.0, 14.0
PLINTH_H, CAP_H = 40.0, 44.0
TILT = 53.0                                 # degrees, nose up toward the wall
PERP = 196.0                                # spacing between parallel decoy axes, perpendicular to them
FLOOR_T, STOP_H = 8.0, 46.0
TRAY_Z0, TRAY_Z1 = -90.0, 215.0            # tray extent along the decoy axis (local Z, nose is -Z)
BODY_BELOW = 78.5                           # decoy underside below its axis
RAIL_W, RAIL_OUT, RAIL_Z = 26.0, 58.0, 120.0
PLATE_T = 4.0
MARGIN = 6.0                                # clear space round a decoy


def _decoy_points() -> np.ndarray:
    """Vertices (mm) of the decoy, in the cradle's local frame (centred, nose -Z, handle +Y)."""
    pts = []
    for s in scene_module("decoy").solids():
        p, _ = tessellate(s.shape)
        pts.append(np.asarray(p).reshape(-1, 3) * 1000.0)
    return np.concatenate(pts)


def _rx(deg: float) -> np.ndarray:
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def _layout(pts: np.ndarray) -> tuple[list[tuple[float, float]], float, float]:
    """Cradle origins (y, z) bottom to top, and the column height. Decoys sit just off the wall, the lowest on the plinth."""
    rot = pts @ _rx(TILT).T
    tray = _tray_local_points() @ _rx(TILT).T
    lo = np.minimum(rot.min(axis=0), tray.min(axis=0))
    z_c = BACK_T + MARGIN - lo[2]
    y0 = PLINTH_H + MARGIN - lo[1]
    pitch = PERP / math.cos(math.radians(TILT))
    cs = [(y0 + i * pitch, z_c) for i in range(N)]
    top = cs[-1][0] + rot.max(axis=0)[1]
    return cs, pitch, top + MARGIN + CAP_H


def _tray_local_points() -> np.ndarray:
    iw = W - 2 * CHEEK_T
    out = []
    for s in _tray_solids():
        lo, hi = bbox_mm(s.shape)
        for x in (lo[0], hi[0]):
            for y in (lo[1], hi[1]):
                for z in (lo[2], hi[2]):
                    out.append((x, y, z))
    return np.array(out)


def _tray_solids() -> list[Solid]:
    """One cradle's tray in the decoy's frame: a floor under the body spanning the column's inside, and a tail stop."""
    iw = W - 2 * CHEEK_T
    floor = at(box(iw, FLOOR_T, TRAY_Z1 - TRAY_Z0), y=-BODY_BELOW - FLOOR_T / 2, z=TRAY_Z0)
    stop = at(box(iw, STOP_H, FLOOR_T), y=-BODY_BELOW - FLOOR_T + STOP_H / 2, z=TRAY_Z1 - FLOOR_T)
    return [Solid(floor, "control_grey"), Solid(stop, "control_grey")]


def solids() -> list[Solid]:
    pts = _decoy_points()
    cs, pitch, H = _layout(pts)
    out: list[Solid] = []
    out.append(Solid(at(box(W, H, BACK_T), y=H / 2), "interior_panel"))
    for sx in (-1, 1):
        out.append(Solid(at(box(CHEEK_T, H, DEPTH), x=sx * (W - CHEEK_T) / 2, y=H / 2), "interior_panel"))
    out.append(Solid(at(box(W, PLINTH_H, DEPTH), y=PLINTH_H / 2), "hazard_stripe"))
    out.append(Solid(at(box(W, CAP_H, DEPTH), y=H - CAP_H / 2), "interior_panel"))
    for (y, z) in cs:
        for t in _tray_solids():
            out.append(Solid(at(t.shape, y=y, z=z, rx=TILT), t.role))
    # Engraved plates on the cap's front face, and the grab rail up the right cheek's outside.
    out.append(Solid(at(box(190.0, 30.0, PLATE_T), x=-40.0, y=H - CAP_H / 2, z=DEPTH), "label_plate"))
    out.append(Solid(at(box(60.0, 30.0, PLATE_T), x=100.0, y=H - CAP_H / 2, z=DEPTH), "label_plate"))
    rx = W / 2 + RAIL_OUT - RAIL_W / 2
    y0, y1 = PLINTH_H + 220.0, H - CAP_H - 220.0
    out.append(Solid(at(box(RAIL_W, y1 - y0, RAIL_W), x=rx, y=(y0 + y1) / 2, z=RAIL_Z), "control_interface"))
    for y in (y0 + RAIL_W / 2, y1 - RAIL_W / 2):
        out.append(Solid(at(box(RAIL_OUT, RAIL_W, RAIL_W), x=W / 2 + RAIL_OUT / 2 - 1.0, y=y, z=RAIL_Z), "control_interface"))
    return out


def _check(sol: list[Solid], cs: list[tuple[float, float]], pitch: float, H: float, pts: np.ndarray) -> dict:
    los, his = zip(*(bbox_mm(s.shape) for s in sol))
    lo, hi = np.min(los, axis=0), np.max(his, axis=0)
    expect(abs(lo[1]) < 0.01 and abs(lo[2]) < 0.01, f"floor on Y=0 and back on Z=0 ({lo[1]:.1f}, {lo[2]:.1f})")
    width, depth = hi[0] - lo[0], hi[2] - lo[2]
    expect(width <= MAX_W, f"footprint {width:.0f} mm along the hull, at most {MAX_W:.0f}")
    expect(depth <= MAX_D, f"footprint {depth:.0f} mm deep, at most {MAX_D:.0f}")
    expect(H <= 2260.0, f"column {H:.0f} mm tall, no taller than the life support unit (2260)")
    rot = pts @ _rx(TILT).T
    dlo, dhi = rot.min(axis=0), rot.max(axis=0)
    inner = W / 2 - CHEEK_T
    for i, (y, z) in enumerate(cs):
        # The decoy's full length (the whole mesh) inside the column's envelope: between the cheeks, plinth and cap, wall to front.
        expect(-inner <= dlo[0] and dhi[0] <= inner, f"cradle {i + 1}: decoy between the cheeks")
        expect(BACK_T <= z + dlo[2] and z + dhi[2] <= DEPTH, f"cradle {i + 1}: decoy Z {z + dlo[2]:.0f}..{z + dhi[2]:.0f} inside 0..{DEPTH:.0f}")
        expect(PLINTH_H <= y + dlo[1] and y + dhi[1] <= H - CAP_H, f"cradle {i + 1}: decoy Y {y + dlo[1]:.0f}..{y + dhi[1]:.0f} inside the column")
    # Neighbours: the decoys are parallel and offset straight up, so their separation is the perpendicular spacing.
    sep = pitch * math.cos(math.radians(TILT))
    expect(sep >= BODY_BELOW + FLOOR_T + 110.0 - 1.0, f"cradles clear of each other: {sep:.0f} mm between axes, handle {110:.0f} + tray + underside {BODY_BELOW + FLOOR_T:.0f}")
    return {"width_mm": round(float(width), 1), "depth_mm": round(float(depth), 1), "height_mm": round(float(H), 1),
            "pitch_mm": round(pitch, 1), "tilt_deg": TILT}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    pts = _decoy_points()
    cs, pitch, H = _layout(pts)
    sol = solids()
    figures = _check(sol, cs, pitch, H, pts)
    rep = export_solids_glb(sol, d / f"{SLUG}_body.glb", "DecoyRackBody")
    s = Scene("DecoyRack", type_="Node3D")
    s.node("Body", instance=rep["glb"])
    sh = s.sub("BoxShape3D", "rack", {"size": (W / 1000, H / 1000, DEPTH / 1000)})
    s.node("Collision", type_="StaticBody3D")
    s.node("Column", parent="Collision", type_="CollisionShape3D",
           props={"transform": Xform(origin=(0, H / 2000, DEPTH / 2000)), "shape": sh})
    c, sn = math.cos(math.radians(TILT)), math.sin(math.radians(TILT))
    for i, (y, z) in enumerate(cs):
        xf = Xform.frame((1, 0, 0), (0, c, sn), (0, -sn, c), (0.0, y / 1000, z / 1000))
        s.node(f"Cradle{i + 1}", script="res://src/interact/decoy_cradle.gd", props={"transform": xf})
        s.node(f"Decoy{i + 1}", instance=scene_path("decoy"), props={"transform": xf})
    s.write(d / f"{SLUG}.tscn")
    n_dec = entry("decoy")["triangles"]
    tris = rep["triangles"] + N * n_dec
    expect(tris <= TRIANGLE_BUDGET, f"rack within the {TRIANGLE_BUDGET:,} triangle budget ({tris})")
    write_entry(GROUP, SLUG, {
        "kind": "furniture",
        "summary": "Decoy rack: a flat grey column of six tilted cradles one above another, each a DecoyCradle seating a decoy "
                   "(nose up toward the wall, tail out), with a hazard-striped plinth, an engraved plate and an orange grab rail. "
                   "An empty cradle is a bare tray with a tail stop.",
        "tags": ["decoy", "rack", "cradle", "countermeasure", "furniture", "column"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"wire": {"cradles": "Cradle1..Cradle6, bottom to top (DecoyCradle; the decoy lies along its -Z, handle up +Y)",
                               "decoys": "Decoy1..Decoy6 (DecoyItem), each placed at its cradle; call try_seat on the cradle to seat it"}},
        "footprint_mm": [round(float(figures["width_mm"])), round(float(figures["depth_mm"]))],
        "stand_out_mm": round(float(figures["depth_mm"])),
        "mount": "floor at Y=0, back against the hull on Z=0, centred on the column, cradles face +Z",
        "uses": list(USES),
        "triangles": tris,
        "triangle_budget": TRIANGLE_BUDGET,   # six decoys counted (Tristan, 2026-11-27, #758)
        "triangles_by_part": {"body": rep["triangles"], "decoys": N * n_dec},
        "checks": figures,
    })
    return {"slug": SLUG, "triangles": tris, "body": rep["triangles"]}
