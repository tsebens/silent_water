"""science_module_frame: the shared bolt-in chassis of a science-station instrument module (kit element, static).

Concept #529, arc #612: a face plate with rails, two quick-release latches, orange side handles, and a rear mount
that slides into a bay of about 0.35 m. The four module types (SCAN, SWEEP, PROBE, CAMERA) are later scenes that
instance this one and add their own face. No behaviour, no script.

Mount: back on Z=0, centred, faces +Z. The rear body sits inside the bay; the face plate overlaps the bay opening.
"""
from cadkit.solids import Solid, at, box, prism, expect, expect_in_front, bbox_mm, export_solids_glb
from cadkit.library import out_dir, res, write_entry
from cadkit.tscn import Scene

SLUG, GROUP = "science_module_frame", "kit"
USES: list[str] = []
BAY_W = 350.0                                  # the bay's opening
W, H, T = 340.0, 280.0, 12.0                   # the face plate
BODY_W, BODY_H, BODY_D = 312.0, 252.0, 44.0    # the rear mount, inside the bay
RAIL_W, RAIL_H, RAIL_T, RAIL_Y = 292.0, 14.0, 6.0, 118.0   # a rail along the top and bottom of the face
LATCH_X, LATCH_R, LATCH_L = 120.0, 14.0, 12.0  # quick-release latch knobs, on the top rail
LATCH_TAB_W, LATCH_TAB_H, LATCH_TAB_T = 8.0, 26.0, 5.0
HANDLE_X, HANDLE_W, HANDLE_H, HANDLE_T = 156.0, 12.0, 120.0, 14.0   # orange grip bars, one each side
POST_W, POST_H, POST_L, POST_Y = 12.0, 14.0, 26.0, 40.0
MAX_STAND_OUT, MAX_TRIS = 100.0, 1500


def solids() -> tuple[list[Solid], float, float, float]:
    plate_z = BODY_D
    face_z = plate_z + T
    body = box(BODY_W, BODY_H, BODY_D, chamfer_mm=3.0)
    plate = at(box(W, H, T, chamfer_mm=3.0), z=plate_z)
    rails = [at(box(RAIL_W, RAIL_H, RAIL_T, chamfer_mm=1.0), y=sy * RAIL_Y, z=face_z) for sy in (-1, 1)]
    latch_bodies = [at(prism(8, LATCH_R, LATCH_L, chamfer_top=2.0), x=sx * LATCH_X, y=RAIL_Y, z=face_z + RAIL_T)
                    for sx in (-1, 1)]
    latch_tabs = [at(box(LATCH_TAB_W, LATCH_TAB_H, LATCH_TAB_T), x=sx * LATCH_X, y=RAIL_Y,
                     z=face_z + RAIL_T + LATCH_L) for sx in (-1, 1)]
    posts = [at(box(POST_W, POST_H, POST_L), x=sx * HANDLE_X, y=sy * POST_Y, z=face_z)
             for sx in (-1, 1) for sy in (-1, 1)]
    grips = [at(box(HANDLE_W, HANDLE_H, HANDLE_T, chamfer_mm=2.0), x=sx * HANDLE_X, z=face_z + POST_L)
             for sx in (-1, 1)]

    every = [body, plate] + rails + latch_bodies + latch_tabs + posts + grips
    los = [bbox_mm(s)[0] for s in every]
    his = [bbox_mm(s)[1] for s in every]
    lo = tuple(min(l[i] for l in los) for i in range(3))
    hi = tuple(max(h[i] for h in his) for i in range(3))
    stand_out = hi[2]
    width, height = hi[0] - lo[0], hi[1] - lo[1]
    expect(abs(lo[2]) < 0.01, f"back on Z=0, not {lo[2]:.2f}")
    expect(width <= BAY_W + 0.01, f"module is {width:.1f} mm wide; the bay takes {BAY_W:.0f} mm")
    expect(abs(lo[0] + hi[0]) < 0.01, "centred across the width")
    expect(stand_out <= MAX_STAND_OUT, f"module stands {stand_out:.1f} mm out; limit {MAX_STAND_OUT:.0f}")
    expect(stand_out > face_z + RAIL_T, "handles and latches stand proud of the face plate")
    expect(BODY_W <= W - 2 * T, "the rear mount is narrower than the plate, so the plate overlaps the bay opening")
    expect(HANDLE_X + HANDLE_W / 2 <= W / 2 and LATCH_X + LATCH_R <= RAIL_W / 2 + 0.01,
           "handles stay on the plate and the latches on the rails")
    expect(POST_Y + POST_H / 2 < HANDLE_H / 2 and POST_L > 0, "handle posts land on the grip bars")
    expect(HANDLE_X - HANDLE_W / 2 > RAIL_W / 2, "side handles clear the rails (room for the module face)")
    out = ([Solid(body, "interior_dark"), Solid(plate, "control_grey")]
           + [Solid(r, "hull_metal") for r in rails]
           + [Solid(b, "trim_black") for b in latch_bodies] + [Solid(t, "control_interface") for t in latch_tabs]
           + [Solid(p, "trim_black") for p in posts] + [Solid(g, "control_interface") for g in grips])
    expect_in_front(out, SLUG)
    return out, stand_out, width, height


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    parts, stand_out, width, height = solids()
    rep = export_solids_glb(parts, d / f"{SLUG}.glb", "ScienceModuleFrameBody")
    tris = rep["triangles"]
    expect(tris <= MAX_TRIS, f"{tris} triangles; the kit allows {MAX_TRIS}")
    s = Scene("ScienceModuleFrame", script=None)
    s.node("Body", instance=rep["glb"])
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "element",
        "summary": "Science-station module chassis: grey face plate with two rails, two quick-release latches with orange "
                   "tabs, orange side handles on posts, and a rear mount that fits a 350 mm bay. The shared frame the four "
                   "instrument modules build on. Static; no script.",
        "tags": ["science", "module", "frame", "chassis", "bay", "handle", "latch", "static"],
        "scene": res(d / f"{SLUG}.tscn"),
        "footprint_mm": [round(width, 1), round(height, 1)],
        "stand_out_mm": round(stand_out, 1),
        "depth_mm": {"behind_origin": 0.0, "in_front_of_origin": round(stand_out, 1)},
        "mount": "back on Z=0, centred; faces +Z; the rear mount slides into a bay about 0.35 m wide, the plate overlaps its opening",
        "uses": [],
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
