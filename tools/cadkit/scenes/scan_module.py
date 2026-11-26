"""scan_module: the SCAN instrument module of the science station (kit control). Behaviour: ScanModule.

Concept #529, arc #619: the shared `science_module_frame` chassis with SCAN's own face. A square ring screen sits
recessed in a bezel on the left of the face (the progress ring, the range to the array and a CLOSER hint, drawn by
`ScanScreen`) and a large lit toggle on the right arms the scan (its lamp lights while armed). The other three modules
put their own faces on the same frame; SCAN's is the one with the ring and the big switch.

The switch is the kit `lit_toggle` (a lit switch reads as "armed" at a glance); it is wired to `ScanModule.arm_switch`.
Mount: as the frame, back on Z=0, centred, faces +Z; slides into a bay about 0.35 m wide.
"""
import json

from cadkit.solids import Solid, at, box, bbox_mm, expect, expect_in_front, export_solids_glb
from cadkit.library import entry, note, out_dir, res, scene_module, write_entry
from cadkit.tscn import NodePath, Scene, Xform

SLUG, GROUP = "scan_module", "kit"
USES: list[str] = ["science_module_frame", "lit_toggle"]
MAX_TRIS = 1000
MAX_STAND_OUT = 130.0                       # the bay's usable depth in front of its opening, switch included
SCREEN = 160.0                              # the square screen, mm: ScanScreen.screen_size's default (0.16 m)
BEZEL = SCREEN + 12.0
BEZEL_D, RECESS_FLOOR, INSERT_T = 8.0, 2.0, 1.0
QUAD_LIFT = 0.3
SCREEN_X = -45.0
SWITCH_X = 95.0
BAT_TIP_REACH_MM = 130.0                    # a crew member's hand reaches this far off the bay opening


def solids(fr) -> tuple[list[Solid], float]:
    opening = at(box(SCREEN, SCREEN, BEZEL_D), z=RECESS_FLOOR)
    bezel = box(BEZEL, BEZEL, BEZEL_D, chamfer_mm=2.0) - opening
    insert = at(box(SCREEN, SCREEN, INSERT_T), z=RECESS_FLOOR - INSERT_T)
    bl, bh = bbox_mm(bezel)
    il, ih = bbox_mm(insert)
    expect(abs(bl[2]) < 0.01 and il[2] >= -0.01, "bezel and insert have nothing behind their back")
    expect(ih[0] >= SCREEN / 2 - 0.01 and ih[0] < bh[0], "the screen is inside the bezel")
    expect(ih[2] + QUAD_LIFT < bh[2], "the screen sits below the bezel's front (recessed)")
    parts = [Solid(bezel, "trim_black"), Solid(insert, "interior_dark")]
    expect_in_front(parts, SLUG)
    return parts, bh[2]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    fr = scene_module("science_module_frame")
    frame = entry("science_module_frame")
    toggle = entry("lit_toggle")
    face_z = fr.BODY_D + fr.T
    parts, bezel_front = solids(fr)

    # Fit in the bay and reach: the screen and switch are inside the plate, clear of the rails and the handles.
    sw_w, sw_h = toggle["footprint_mm"]
    free_top = fr.RAIL_Y - fr.RAIL_H / 2          # the rails' inner edge
    free_side = fr.HANDLE_X - fr.HANDLE_W / 2     # the handles' inner edge
    expect(SCREEN_X - BEZEL / 2 > -free_side and SCREEN_X + BEZEL / 2 < SWITCH_X - sw_w / 2 - 4.0,
           "screen bezel clear of the left handle and of the switch")
    expect(BEZEL / 2 < free_top, "screen bezel clear of the rails")
    expect(SWITCH_X + sw_w / 2 < free_side - 4.0, "switch plate clear of the right handle")
    expect(sw_h / 2 < free_top, f"switch plate ({sw_h} mm tall) clear of the rails")
    stand_out = max(frame["stand_out_mm"], face_z + toggle["stand_out_mm"])
    expect(stand_out <= MAX_STAND_OUT, f"module stands {stand_out:.1f} mm out; limit {MAX_STAND_OUT}")
    expect(face_z + toggle["stand_out_mm"] <= face_z + BAT_TIP_REACH_MM,
           "the switch's bat is within hand reach of the face")
    expect(face_z + bezel_front < stand_out, "the bezel is lower than the switch (the screen faces the eye, unshadowed)")
    expect(frame["footprint_mm"][0] <= 350.0, "fits the 350 mm bay")

    rb = export_solids_glb(parts, d / f"{SLUG}_bezel.glb", "ScanModuleBezel")
    tris = rb["triangles"] + frame["triangles"] + toggle["triangles"]
    expect(tris <= MAX_TRIS, f"{tris} triangles; the module's cap is {MAX_TRIS}")

    s = Scene("ScanModule", script="res://src/science/scan_module.gd")
    s.node("Frame", instance=frame["scene"])
    s.node("Bezel", instance=rb["glb"],
           props={"transform": Xform(origin=(SCREEN_X / 1000, 0, face_z / 1000))})
    s.node("Screen", type_="MeshInstance3D", script="res://src/science/scan_screen.gd",
           props={"transform": Xform(origin=(SCREEN_X / 1000, 0, (face_z + RECESS_FLOOR + QUAD_LIFT) / 1000))})
    s.node("ArmSwitch", instance=toggle["scene"],
           props={"transform": Xform(origin=(SWITCH_X / 1000, 0, face_z / 1000))})
    s.set(".", arm_switch=NodePath("ArmSwitch"))
    _review(d, face_z)
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "control",
        "summary": "SCAN science module: the module frame with a recessed square ring screen (progress, range, "
                   "CLOSER hint) on the left and a large lit arm switch on the right. Arming it runs the scan.",
        "tags": ["science", "module", "scan", "screen", "ring", "switch", "lit", "arm"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "ScanModule",
                      "values": "armed (switch up, lamp lit) or stopped; the screen shows ring, range and hint",
                      "signal": "armed_changed(armed)",
                      "wiring": "`arm_switch` is set in the scene; the objective is found in group scan_objectives"},
        "footprint_mm": frame["footprint_mm"],
        "stand_out_mm": round(stand_out, 1),
        "mount": "back on Z=0, centred; faces +Z; slides into a bay about 0.35 m wide, the plate overlaps its opening",
        "set_on_instance": {"objective": "ScanObjective to drive (default: first in group scan_objectives)"},
        "uses": USES,
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}


def _review(d, face_z: float) -> None:
    z = face_z / 1000
    look = [0.0, 0.0, z]
    cams = [
        {"name": "front", "pos": [0.0, 0.0, 0.75], "look_at": look, "fov": 30.0},
        {"name": "three_quarter", "pos": [0.35, 0.22, 0.6], "look_at": look, "fov": 32.0},
        {"name": "profile", "pos": [0.9, 0.0, 0.06], "look_at": [0.0, 0.0, 0.06], "ortho": 0.4},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    for n in (".gdignore", "cameras.json"):
        note(review / n)
