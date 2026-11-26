"""sweep_module: the SWEEP science-station module, the bathymetry sounder (kit display, concept #529, arc #622).

The shared `science_module_frame` chassis (bay fit, rails, latches, orange handles) with this module's face: an 8 x 8
coverage-grid screen (the grid SweepObjective samples) and an arm switch, a `lit_toggle` whose lamp shows armed. The
root is a SweepModule, which arms the sweep objective. Wiring left to the station: connect the switch's
`value_changed` to the module's `toggle_armed` (the scene has no control script of its own).

Mount: as the frame: back on Z=0, centred, faces +Z; the rear body slides into a bay about 0.35 m wide. The screen
glass is a static dark quad with the empty grid lines; live coverage is the objective's, shown by the station's
screen layer, not baked here.
"""
import json

from cadkit.solids import Solid, at, box, expect, expect_in_front, bbox_mm, export_solids_glb
from cadkit.library import entry, note, out_dir, res, write_entry
from cadkit.mount import stand_off
from cadkit.tscn import Scene, Xform

SLUG, GROUP = "sweep_module", "kit"
USES: list[str] = ["science_module_frame", "lit_toggle"]
GRID = 8                                   # SweepObjective.GRID
SCREEN_W = 188.0                           # square screen glass
SCREEN_X, SCREEN_Y = -42.0, 0.0
BEZEL_T, GLASS_T, LINE_W, LINE_T = 5.0, 2.0, 1.2, 0.8
SWITCH_X, SWITCH_Y = 112.0, 0.0
MAX_STAND_OUT, MAX_TRIS = 125.0, 2000


def solids(frame, toggle) -> tuple[list[Solid], float]:
    fw, fh = frame["footprint_mm"]
    face_z = frame["stand_out_mm"] - 0.0
    # The plate front is the frame's face; rails sit 6 mm above it, handles 26 mm.  Face plate front z = 56.
    plate_front = 56.0
    bez_w = SCREEN_W + 2 * 6.0
    bezel = at(box(bez_w, bez_w, BEZEL_T, chamfer_mm=1.5), x=SCREEN_X, y=SCREEN_Y, z=plate_front)
    glass = at(box(SCREEN_W, SCREEN_W, GLASS_T), x=SCREEN_X, y=SCREEN_Y, z=plate_front + BEZEL_T)
    gz = plate_front + BEZEL_T + GLASS_T
    cell = SCREEN_W / GRID
    lines = []
    for i in range(1, GRID):
        o = -SCREEN_W / 2 + i * cell
        lines.append(at(box(LINE_W, SCREEN_W, LINE_T), x=SCREEN_X + o, y=SCREEN_Y, z=gz))
        lines.append(at(box(SCREEN_W, LINE_W, LINE_T), x=SCREEN_X, y=SCREEN_Y + o, z=gz))
    parts = ([Solid(bezel, "trim_black"), Solid(glass, "screen_off")] + [Solid(l, "interior_dark") for l in lines])
    lo, hi = bbox_mm(bezel)
    # Frame geometry (science_module_frame.py): rails at y=+-118, latches at x=+-120 on them, handles at x=+-156.
    rail_in, handle_in = 118.0 - 7.0, 156.0 - 6.0
    expect(abs(plate_front + 6.0 - (frame["stand_out_mm"] - 40.0)) < 100, "frame face height sanity")
    expect(lo[0] >= -handle_in and hi[0] <= SWITCH_X - toggle["footprint_mm"][0] / 2,
           "screen bezel clear of the side handle and the arm switch")
    expect(hi[1] <= rail_in and lo[1] >= -rail_in, "screen bezel inside the top and bottom rails")
    expect(SCREEN_X - SCREEN_W / 2 > -fw / 2 and SCREEN_Y == 0.0, "screen inside the frame's face")
    tw, th = toggle["footprint_mm"]
    expect(SWITCH_X + tw / 2 <= handle_in and SWITCH_Y + th / 2 <= rail_in - 4.0 and SWITCH_Y - th / 2 >= -rail_in + 4.0,
           "arm switch plate sits between the handle and the rails, clear of the latches")
    expect(gz > plate_front + BEZEL_T and gz <= plate_front + BEZEL_T + GLASS_T + LINE_T + 0.01,
           "screen faces +Z (towards the eye), glass behind the bezel's front")
    expect(hi[2] > plate_front and lo[2] >= plate_front - 0.01, "screen stands proud of the face plate, none behind it")
    expect_in_front(parts, SLUG)
    stand = max(bbox_mm(s.shape)[1][2] for s in parts)
    toggle_out = plate_front + stand_off(0.0) + toggle["stand_out_mm"]
    stand = max(stand, toggle_out, frame["stand_out_mm"])
    expect(stand <= MAX_STAND_OUT, f"module stands {stand:.1f} mm out; limit {MAX_STAND_OUT:.0f}")
    expect(fw <= 350.0, f"frame {fw:.0f} mm wide fits the 350 mm bay")
    return parts, stand


def build() -> dict:
    frame, toggle = entry("science_module_frame"), entry("lit_toggle")
    d = out_dir(GROUP, SLUG)
    parts, stand = solids(frame, toggle)
    rep = export_solids_glb(parts, d / f"{SLUG}_screen.glb", "SweepModuleScreen")
    tris = rep["triangles"] + frame["triangles"] + toggle["triangles"]
    expect(tris <= MAX_TRIS, f"{tris} triangles; the cap is {MAX_TRIS}")
    s = Scene("SweepModule", script="res://src/science/sweep_module.gd")
    s.node("Frame", instance=frame["scene"])
    s.node("Screen", instance=rep["glb"])
    s.node("ArmSwitch", instance=toggle["scene"], props={"transform": Xform(
        origin=(SWITCH_X / 1000, SWITCH_Y / 1000, (56.0 + stand_off(0.0)) / 1000))})
    _review(d)
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "display",
        "summary": "SWEEP science module (bathymetry sounder): the shared module chassis with an 8 x 8 coverage-grid "
                   "screen in a black bezel and a lit arm switch beside it. The root is a SweepModule. Connect "
                   "ArmSwitch's value_changed to toggle_armed on the instance.",
        "tags": ["science", "module", "sweep", "bathymetry", "sounder", "screen", "grid", "arm", "switch"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "SweepModule", "values": "armed off/on; coverage 0..1",
                      "signal": "ArmSwitch (SwitchLever) value_changed",
                      "wiring": "station connects ArmSwitch.value_changed to toggle_armed; `objective` is found by group"},
        "footprint_mm": frame["footprint_mm"],
        "stand_out_mm": round(stand, 1),
        "depth_mm": {"behind_origin": 0.0, "in_front_of_origin": round(stand, 1)},
        "mount": "as science_module_frame: back on Z=0, centred; faces +Z; the rear body slides into a bay about 0.35 m wide",
        "uses": USES,
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}


def _review(d) -> None:
    look = [0.0, 0.0, 0.06]
    cams = [
        {"name": "front", "pos": [0.25, 0.18, 0.7], "look_at": look, "fov": 30.0},
        {"name": "front_red", "pos": [0.25, 0.18, 0.7], "look_at": look, "fov": 30.0, "light": "red"},
        {"name": "profile", "pos": [0.8, 0.0, 0.06], "look_at": [0.0, 0.0, 0.06], "ortho": 0.4},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    for n in (".gdignore", "cameras.json"):
        note(review / n)
