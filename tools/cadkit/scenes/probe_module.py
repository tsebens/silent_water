"""probe_module: the PROBE science-station module, the winch (kit display, concept #529, arc #624).

The shared `science_module_frame` chassis with this module's face: a cable reel on the left (its own GLB under a
`ReelPivot`, axis Z through the origin, so the station turns it with `ProbeModule.reel_angle()`), a mechanical depth
counter window and a sample-point list screen in the middle, and a winch switch (a `lit_toggle`) on the right. The root
is a ProbeModule, which readies the probe objective. Wiring left to the station: connect `WinchSwitch`'s
`value_changed` to the module's `toggle_armed`, set `ReelPivot.rotation.z = reel_angle()` each frame and draw the
counter digits and point list on the glass (the scene has no control script of its own).

Mount: as the frame: back on Z=0, centred, faces +Z; the rear body slides into a bay about 0.35 m wide.
"""
import json
import math

from cadkit.solids import Solid, at, box, prism, expect, expect_in_front, bbox_mm, export_solids_glb
from cadkit.library import entry, note, out_dir, res, write_entry
from cadkit.mount import stand_off
from cadkit.tscn import Scene, Xform

SLUG, GROUP = "probe_module", "kit"
USES: list[str] = ["science_module_frame", "lit_toggle"]
PLATE_FRONT = 56.0                         # the frame's face plate front (BODY_D + T)
RAIL_IN, HANDLE_IN = 118.0 - 7.0, 156.0 - 6.0
REEL_X = -85.0
FLANGE_R, FLANGE_T, FLANGE_GAP = 56.0, 4.0, 22.0
DRUM_R, HUB_R = 38.0, 14.0
TAB_W, TAB_H = 8.0, 14.0                   # orange marker on the front flange, so the turn is visible
BRACKET_W, BRACKET_T = 128.0, 8.0
REEL_Z = PLATE_FRONT + BRACKET_T + FLANGE_GAP / 2 + FLANGE_T + 3.0 + 0.5   # axis on Z; hub back just off the bracket
MAX_ANGLE_DEG = math.degrees(60.0 * 0.5)   # ProbeObjective: MAX_LOWER_M * REEL_RAD_PER_M radians at full depth
CTR_X, CTR_W, CTR_Y, CTR_H = 32.0, 88.0, 72.0, 36.0
LST_X, LST_W, LST_Y, LST_H = 32.0, 88.0, -22.0, 110.0
SWITCH_X = 112.0
BEZEL_M, BEZEL_T, GLASS_T, LINE_W, LINE_T = 5.0, 4.0, 1.5, 1.2, 0.6
DIGITS, ROWS = 4, 5
MAX_STAND_OUT, MAX_TRIS = 125.0, 2000


def reel_solid():
    """The reel in its own frame: axis Z through the origin, centred on Z=0."""
    half = FLANGE_GAP / 2
    flanges = [at(prism(8, FLANGE_R, FLANGE_T), z=sz * (half + FLANGE_T / 2) - FLANGE_T / 2) for sz in (-1, 1)]
    drum = at(prism(8, DRUM_R, FLANGE_GAP), z=-half)
    hub = at(prism(8, HUB_R, FLANGE_GAP + 2 * FLANGE_T + 6.0), z=-half - FLANGE_T - 3.0)
    tab = at(box(TAB_W, TAB_H, 3.0), y=FLANGE_R - TAB_H / 2 - 4.0, z=half + FLANGE_T)
    return ([Solid(f, "control_grey") for f in flanges] + [Solid(drum, "interior_dark"), Solid(hub, "trim_black"),
                                                           Solid(tab, "control_interface")])


def face_solids() -> list[Solid]:
    parts = [Solid(at(box(BRACKET_W, BRACKET_W, BRACKET_T, chamfer_mm=2.0), x=REEL_X, z=PLATE_FRONT), "trim_black")]
    z0 = PLATE_FRONT
    for x, w, y, h in ((CTR_X, CTR_W, CTR_Y, CTR_H), (LST_X, LST_W, LST_Y, LST_H)):
        parts.append(Solid(at(box(w + 2 * BEZEL_M, h + 2 * BEZEL_M, BEZEL_T, chamfer_mm=1.0), x=x, y=y, z=z0), "trim_black"))
        parts.append(Solid(at(box(w, h, GLASS_T), x=x, y=y, z=z0 + BEZEL_T), "screen_off"))
    gz = z0 + BEZEL_T + GLASS_T
    for i in range(1, DIGITS):          # digit-drum separators in the counter window
        parts.append(Solid(at(box(LINE_W, CTR_H, LINE_T), x=CTR_X - CTR_W / 2 + i * CTR_W / DIGITS, y=CTR_Y, z=gz),
                           "interior_dark"))
    for i in range(1, ROWS):            # row rules of the sample-point list
        parts.append(Solid(at(box(LST_W, LINE_W, LINE_T), x=LST_X, y=LST_Y - LST_H / 2 + i * LST_H / ROWS, z=gz),
                           "interior_dark"))
    return parts


def check(frame, toggle, face, reel) -> float:
    fw, _ = frame["footprint_mm"]
    # Reel at both ends of its travel (0 and full depth), as the station places it.
    ends = {"start": 0.0, "full depth": MAX_ANGLE_DEG}
    for name, deg in ends.items():
        placed = [at(at(s.shape, rz=deg), x=REEL_X, z=REEL_Z) for s in reel]
        for b in (bbox_mm(p) for p in placed):
            expect(b[0][2] > PLATE_FRONT + BRACKET_T - 0.01, f"reel clear of the bracket and face plate, {name}")
            expect(b[0][0] >= -HANDLE_IN and b[1][1] <= RAIL_IN and b[0][1] >= -RAIL_IN,
                   f"reel inside the side handle and the rails, {name}")
            expect(b[1][0] <= CTR_X - CTR_W / 2 - BEZEL_M, f"reel clear of the counter and list, {name}")
    ax = bbox_mm(at(reel[3].shape, x=REEL_X))
    expect(abs((ax[0][0] + ax[1][0]) / 2 - REEL_X) < 0.01 and abs((ax[0][1] + ax[1][1]) / 2) < 0.01,
           "reel turns about its own axis (hub centred on the pivot)")
    expect(DRUM_R < FLANGE_R and HUB_R < DRUM_R, "cable drum sits between the flanges, hub inside it")
    # Face layout.
    tw, th = toggle["footprint_mm"]
    expect(CTR_X - CTR_W / 2 - BEZEL_M > REEL_X + FLANGE_R, "counter bezel clear of the reel")
    expect(CTR_X + CTR_W / 2 + BEZEL_M < SWITCH_X - tw / 2 and LST_X + LST_W / 2 + BEZEL_M < SWITCH_X - tw / 2,
           "counter and list clear of the winch switch")
    expect(CTR_Y + CTR_H / 2 + BEZEL_M <= RAIL_IN and LST_Y - LST_H / 2 - BEZEL_M >= -RAIL_IN,
           "counter and list inside the rails")
    expect(CTR_Y - CTR_H / 2 - BEZEL_M > LST_Y + LST_H / 2 + BEZEL_M - 0.01, "counter above the list, not overlapping")
    expect(SWITCH_X + tw / 2 <= HANDLE_IN and th / 2 <= RAIL_IN, "winch switch plate between the handle and the rails")
    expect_in_front(face + reel_placed(reel, 0.0) + reel_placed(reel, MAX_ANGLE_DEG), SLUG)
    top = max(bbox_mm(s.shape)[1][2] for s in face + reel_placed(reel, 0.0) + reel_placed(reel, MAX_ANGLE_DEG))
    stand = max(top, PLATE_FRONT + stand_off(0.0) + toggle["stand_out_mm"], frame["stand_out_mm"])
    expect(stand <= MAX_STAND_OUT, f"module stands {stand:.1f} mm out; limit {MAX_STAND_OUT:.0f}")
    expect(fw <= 350.0, f"frame {fw:.0f} mm wide fits the 350 mm bay")
    return stand


def reel_placed(reel, deg: float) -> list[Solid]:
    return [Solid(at(at(s.shape, rz=deg), x=REEL_X, z=REEL_Z), s.role) for s in reel]


def build() -> dict:
    frame, toggle = entry("science_module_frame"), entry("lit_toggle")
    d = out_dir(GROUP, SLUG)
    face, reel = face_solids(), reel_solid()
    stand = check(frame, toggle, face, reel)
    rf = export_solids_glb(face, d / f"{SLUG}_face.glb", "ProbeModuleFace")
    rr = export_solids_glb(reel, d / f"{SLUG}_reel.glb", "ProbeModuleReel")
    tris = rf["triangles"] + rr["triangles"] + frame["triangles"] + toggle["triangles"]
    expect(tris <= MAX_TRIS, f"{tris} triangles; the cap is {MAX_TRIS}")
    s = Scene("ProbeModule", script="res://src/science/probe_module.gd")
    s.node("Frame", instance=frame["scene"])
    s.node("Face", instance=rf["glb"])
    s.node("ReelPivot", props={"transform": Xform(origin=(REEL_X / 1000, 0, REEL_Z / 1000))})
    s.node("Reel", parent="ReelPivot", instance=rr["glb"])
    s.node("WinchSwitch", instance=toggle["scene"], props={"transform": Xform(
        origin=(SWITCH_X / 1000, 0, (PLATE_FRONT + stand_off(0.0)) / 1000))})
    _review(d)
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "display",
        "summary": "PROBE science module (winch): the shared module chassis with a cable reel (its own GLB under "
                   "ReelPivot, turns about Z), a mechanical depth-counter window, a sample-point list screen and a "
                   "lit winch switch. The root is a ProbeModule. Connect WinchSwitch's value_changed to toggle_armed; "
                   "the station sets ReelPivot.rotation.z from reel_angle() and draws the counter and list.",
        "tags": ["science", "module", "probe", "winch", "reel", "cable", "depth", "counter", "sample", "switch"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "ProbeModule", "values": "armed off/on; counter_m() metres of line; reel_angle() radians",
                      "signal": "WinchSwitch (SwitchLever) value_changed",
                      "wiring": "station connects WinchSwitch.value_changed to toggle_armed and turns ReelPivot "
                                "(rotation.z) by reel_angle(); `objective` is found by group"},
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
