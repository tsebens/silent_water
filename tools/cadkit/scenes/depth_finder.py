"""depth_finder: the letterbox echo-sounder display (concept #446), a low wide bezel round a recessed screen.

A matte black bezel with a chamfered front, a thin safety-orange lip round the opening and a dark screen insert at the
bottom of the recess. The screen is a quad named `DepthFinder` carrying the DepthFinder script (default 240 x 120 mm),
sitting just in front of the insert. Frame: back on Z=0, centred on the origin, face toward +Z; nothing needs a cutout.
"""
from cadkit.solids import Solid, at, box, bbox_mm, expect, expect_in_front, export_solids_glb
from cadkit.library import out_dir, res, write_entry
from cadkit.tscn import Scene, Xform

SLUG, GROUP = "depth_finder", "kit"
USES: list[str] = []
SCREEN_W, SCREEN_H = 240.0, 120.0     # DepthFinder.screen_size default (0.24 x 0.12 m)
BEZEL_W, BEZEL_H, BEZEL_D = 276.0, 156.0, 22.0
LIP_W, LIP_H, LIP_Z = 246.0, 126.0, 2.0   # orange lip round the opening, inside the bezel's front
RECESS_FLOOR = 12.0                   # the insert's front face, from the back
INSERT_T = 1.0
QUAD_LIFT = 0.3                       # the quad stands this far in front of the insert
MAX_STAND_OUT = 25.0


def solids() -> tuple[list[Solid], float]:
    opening = at(box(SCREEN_W + 2.0, SCREEN_H + 2.0, BEZEL_D), z=RECESS_FLOOR)
    bezel = box(BEZEL_W, BEZEL_H, BEZEL_D, chamfer_mm=3.0) - opening
    lip = at(box(LIP_W, LIP_H, LIP_Z), z=BEZEL_D - LIP_Z - 3.0) - at(box(SCREEN_W + 2.0, SCREEN_H + 2.0, LIP_Z), z=BEZEL_D - LIP_Z - 3.0)
    insert = at(box(SCREEN_W + 2.0, SCREEN_H + 2.0, INSERT_T), z=RECESS_FLOOR - INSERT_T)
    bl, bh = bbox_mm(bezel)
    il, ih = bbox_mm(insert)
    expect(abs(bl[2]) < 0.01 and il[2] >= -0.01, "the back is on Z=0 and nothing is behind it")
    expect(abs(bh[0] + bl[0]) < 0.01 and abs(bh[1] + bl[1]) < 0.01, "centred on the origin")
    expect(abs(ih[0]) >= SCREEN_W / 2 and abs(ih[1]) >= SCREEN_H / 2 and abs(ih[0]) < BEZEL_W / 2 and abs(ih[1]) < BEZEL_H / 2,
           "the screen is inside the bezel")
    expect(ih[2] + QUAD_LIFT < bh[2], "the screen sits below the bezel's front (recessed)")
    expect(bh[2] <= MAX_STAND_OUT, f"stands {bh[2]:.1f} mm out; limit {MAX_STAND_OUT}")
    expect(bh[0] > 1.5 * bh[1] * 0.9, "low and wide: a letterbox")
    s = [Solid(bezel, "trim_black"), Solid(lip, "control_interface"), Solid(insert, "interior_dark")]
    expect_in_front(s, SLUG)
    return s, bh[2]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    s, stand = solids()
    rep = export_solids_glb(s, d / f"{SLUG}_housing.glb", "DepthFinderHousing")
    tris = rep["triangles"]
    expect(tris <= 1500, f"{tris} triangles; kit budget 1500")
    sc = Scene("DepthFinderKit")
    sc.node("Housing", instance=rep["glb"])
    sc.node("DepthFinder", type_="MeshInstance3D", script="res://src/interact/depth_finder.gd",
            props={"transform": Xform(origin=(0, 0, (RECESS_FLOOR + QUAD_LIFT) / 1000))})
    sc.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "display",
        "summary": "Letterbox echo-sounder: low wide matte black bezel with an orange lip round a recessed screen. "
                   "The DepthFinder node is a DepthFinder quad drawing the sea floor along the heading.",
        "tags": ["display", "depth", "depth finder", "echo sounder", "sonar", "letterbox", "screen", "pilot"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "DepthFinder", "node": "DepthFinder",
                      "reads": "height_at of the node in group terrain_site; SubFrame.render_transform()"},
        "footprint_mm": [BEZEL_W, BEZEL_H],
        "stand_out_mm": round(stand, 2),
        "depth_mm": {"behind_origin": 0.0, "in_front_of_origin": round(stand, 2)},
        "mount": "back on Z=0, centred on the origin; the screen faces +Z. Sits on a flat face; no cutout needed",
        "set_on_instance": {
            "DepthFinder:range_ahead, range_behind, depth_span, columns": "the window of the trace",
            "DepthFinder:trace_swatch, face_swatch": "palette swatches",
        },
        "limits": {"max_stand_out_mm": MAX_STAND_OUT},
        "uses": list(USES),
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
