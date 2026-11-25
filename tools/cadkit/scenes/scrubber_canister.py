"""scrubber_canister: the carried CO2 scrubber canister (furniture). Behaviour: ScrubberCanister, with a CanisterRing on the cap.

Brief (#424, concept scrubber_canister_primary.png): a perforated cylinder about 30 cm tall and 15 cm across showing
beads, a solid cap with a carry handle, and a ring of indicator lights about 300 degrees round the cap. Base on Y=0.
It seats in a cradle or a storage hole (CanisterSlot), which the parent places.

The lights are CanisterRing's own segments (the driver builds and lights them in _ready); this scene supplies the dark
bed they sit on and sets the ring's radius to the bed. Modelled per-segment GLBs would be duplicated by the driver, and an
asset arc may not change a control script.

Modelled Z-up (prisms stand along +Z) and rotated into Godot's Y-up at the end.
"""
import math

import build123d as bd

from cadkit.solids import Solid, at, box, prism, expect, bbox_mm, export_solids_glb
from cadkit.library import out_dir, res, write_entry
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "scrubber_canister", "furniture"
USES: list[str] = []
SIDES = 14
R_CAP = 75.0                                   # collar and cap, to the corners
R_SHELL, R_SHELL_IN, R_CORE = 70.0, 64.0, 62.0
COLLAR_H = 14.0
SHELL_Z0, SHELL_Z1 = COLLAR_H, 248.0
CAP_Z0, CAP_Z1 = 248.0, 272.0
HOLE_ROWS, HOLE_W, HOLE_PITCH = 3, 18.0, 30.0   # square perforations, one column per flat of the shell
POST_X, POST_W, POST_T = 36.0, 10.0, 10.0
HANDLE_Z1, BAR_Z0 = 300.0, 290.0
BED_R0, BED_R1, BED_H = 50.0, 74.0, 1.0
RING_R, SEG, SEG_HALF_H = 62.0, 12.0, 2.4       # CanisterRing's radius and segment size (src/interact/canister_ring.gd)
TOTAL_H, DIAMETER = 300.0, 150.0


def up(shape: bd.Shape) -> bd.Shape:
    """Z-up modelling frame to Y-up: +Z becomes +Y."""
    return shape.rotate(axis=bd.Axis.X, angle=-90)


def solids() -> list[Solid]:
    collar = prism(SIDES, R_CAP, COLLAR_H, chamfer_top=2.0)
    shell = at(prism(SIDES, R_SHELL, SHELL_Z1 - SHELL_Z0) - prism(SIDES, R_SHELL_IN, SHELL_Z1 - SHELL_Z0), z=SHELL_Z0)
    mid = (SHELL_Z0 + SHELL_Z1) / 2
    for row in range(HOLE_ROWS):
        z = mid + (row - (HOLE_ROWS - 1) / 2) * HOLE_PITCH * 2.4
        for k in range(SIDES):
            ang = 360.0 / SIDES * k
            cut = bd.Box(30.0, HOLE_W, HOLE_W).moved(bd.Location((R_SHELL - 2, 0, 0)))
            cut = cut.rotate(axis=bd.Axis.Z, angle=ang).moved(bd.Location((0, 0, z)))
            shell = shell - cut
    core = at(prism(SIDES, R_CORE, CAP_Z0 - COLLAR_H), z=COLLAR_H)
    cap = at(prism(SIDES, R_CAP, CAP_Z1 - CAP_Z0, chamfer_top=3.0), z=CAP_Z0)
    posts = [at(box(POST_W, POST_T, BAR_Z0 - CAP_Z1 + 1.0), x=sx * POST_X, z=CAP_Z1 - 1.0) for sx in (-1, 1)]
    bar = at(box(2 * POST_X + POST_W, POST_T, HANDLE_Z1 - BAR_Z0, chamfer_mm=2.0), z=BAR_Z0)
    handle = posts[0] + posts[1] + bar
    bed = at(prism(SIDES, BED_R1, BED_H) - prism(SIDES, BED_R0, BED_H), z=CAP_Z1)

    body = collar + cap
    lo, hi = bbox_mm(up(body))
    expect(abs(lo[1]) < 0.01, f"base on Y=0, not {lo[1]:.2f}")
    blo, bhi = bbox_mm(up(handle))
    expect(bhi[1] <= TOTAL_H + 0.01, f"handle top {bhi[1]:.1f} mm; about 300 allowed")
    expect(280.0 <= bhi[1] <= 320.0, f"canister {bhi[1]:.0f} mm tall; the brief says about 300")
    expect(135.0 <= hi[0] - lo[0] <= 160.0 and 135.0 <= hi[2] - lo[2] <= 160.0,
           f"canister {hi[0] - lo[0]:.0f} x {hi[2] - lo[2]:.0f} mm across; the brief says about 150")
    # the ring: CanisterRing puts segments on a circle of RING_R; each is a SEG square, so its reach is half the diagonal
    reach = SEG / 2 * math.sqrt(2)
    bed_lo, bed_hi = bbox_mm(up(bed))
    expect(RING_R + reach <= BED_R1 * math.cos(math.pi / SIDES) and RING_R - reach >= BED_R0,
           "ring segments lie on the bed on the cap")
    expect(BED_R1 <= R_CAP - 1.0, "bed inside the cap's edge")
    expect(abs(bed_lo[1] - CAP_Z1) < 0.01, "bed sits on the cap top")
    # the handle clears the ring in plan: its widest reach from the axis against the ring's innermost segment edge
    reach_h = max(abs(blo[0]), abs(bhi[0]), abs(blo[2]), abs(bhi[2]))
    expect(reach_h < RING_R - reach - 5.0, f"handle reaches {reach_h:.1f} mm from the axis; ring's inner edge is {RING_R - reach:.1f}")
    expect(blo[1] <= CAP_Z1 and bhi[1] >= BAR_Z0, "handle stands on the cap")
    expect(len(up(shell).solids()) == 1, "shell is one solid")
    return [Solid(up(collar), "control_grey"), Solid(up(cap), "control_grey"), Solid(up(shell), "hull_metal"),
            Solid(up(core), "interior_dark"), Solid(up(bed), "interior_dark"), Solid(up(handle), "control_interface")]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    rep = export_solids_glb(solids(), d / f"{SLUG}.glb", "ScrubberCanisterBody")
    tris = rep["triangles"]
    expect(tris <= 1500, f"{tris} triangles; the arc allows about 1500")
    s = Scene("ScrubberCanister", script="res://src/interact/scrubber_canister.gd")
    s.node("Body", instance=rep["glb"])
    s.node("Ring", script="res://src/interact/canister_ring.gd",
           props={"transform": Xform(origin=(0, (CAP_Z1 + BED_H + SEG_HALF_H) / 1000, 0)), "canister": NodePath(".."),
                  "radius": RING_R / 1000, "segment_size": SEG / 1000})
    grab_box(s, ".", (0.16, TOTAL_H / 1000, 0.16), (0, TOTAL_H / 2000, 0))
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "furniture",
        "summary": "CO2 scrubber canister: perforated steel cylinder showing dark beads, grey cap with an orange carry handle and "
                   "a 300-degree ring of 12 indicator lights. ScrubberCanister carries it; CanisterRing lights the ring from capacity.",
        "tags": ["scrubber", "canister", "co2", "life support", "carried", "ring"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "ScrubberCanister", "values": "capacity 0..1", "signal": "capacity_changed",
                      "wire": "seat in a CanisterSlot; the child Ring (CanisterRing) is already bound to it"},
        "footprint_mm": [DIAMETER, DIAMETER],
        "stand_out_mm": TOTAL_H,
        "mount": "base on Y=0, centred; stands along +Y; seats in a cradle or a storage hole (CanisterSlot)",
        "set_on_instance": {"capacity": "remaining capacity, drives the ring", "lift_height, carry_offset": "carry motion"},
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
