"""bat_toggle: a lit two-position bat switch on the 1x2 base, with a small swing and a low stand-out.

Brief (concept #700): a light-grey bat lever with deep horizontal grip ridges stands out of the bay and flips about X at the centre of a shallow
recessed bay. A rectangular LED loop (led_strip's `loop_lens`) follows the bay's border: dark at off, lit at on. No round
lamp. Behaviour: SwitchLever, whose `indicator` is the loop's IndicatorLamp. On tips the lever toward +Y.
Three GLBs: the bay and frame (static), the paddle (own frame, pivot through the origin about X) and the loop lens.
"""
import json
import math

import build123d as bd

from cadkit.solids import Solid, at, box, bbox_mm, expect, expect_in_front, export_solids_glb
from cadkit.library import PLATE_T_MM, TRIANGLE_BUDGET, base_glb, base_size_mm, entry, note, out_dir, quiet_noise, res, scene_module, write_entry
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "bat_toggle", "kit"
USES: list[str] = ["control_base", "led_strip"]
BASE = (1, 2)
FRAME_W, FRAME_H_Y, FRAME_Z = 36.0, 72.0, 3.0      # raised frame round the bay (X, Y, height above the plate)
BAY_W, BAY_H_Y, FLOOR_Z = 26.0, 62.0, 1.0          # the recess: floor FLOOR_Z above the plate
LOOP_BAR, LOOP_GAP, LOOP_Z = 3.0, 0.5, 1.2         # LED loop round the frame
PAD_W, PAD_T, PAD_BOT, PAD_LEN = 21.0, 7.0, -2.0, 16.0   # paddle in its own frame: wide in X, thick in Y, standing out along +Z from the pivot on the X axis
GROOVES, GROOVE_W, GROOVE_D = 4, 2.0, 1.6
HINGE_Z = PLATE_T_MM + FLOOR_Z + 4.0
SWING_DEG = 30.0                                   # total; +/-15 degrees about X
MAX_STAND_OUT = 30.0                               # lit_toggle stands 56 mm out; this is about half


def _paddle() -> bd.Shape:
    """A flip-switch lever: stands out along +Z from the pivot, ridged across its +Y face (the face that leads on)."""
    pad = at(box(PAD_W, PAD_T, PAD_LEN - PAD_BOT, chamfer_mm=1.0), z=PAD_BOT)
    pitch = (PAD_LEN - 5.0) / (GROOVES - 1)
    for i in range(GROOVES):
        z = 4.0 + i * pitch
        pad = pad - at(box(PAD_W + 2.0, GROOVE_D, GROOVE_W), 0, PAD_T / 2 - GROOVE_D / 2 + 0.01, z - GROOVE_W / 2)
    return pad


def _tilted(pad: bd.Shape, deg: float) -> bd.Shape:
    return at(at(pad, rx=deg), z=HINGE_Z)


def solids():
    loop_mod = scene_module("led_strip")
    pad = _paddle()
    half = SWING_DEG / 2
    frame = at(box(FRAME_W, FRAME_H_Y, FRAME_Z, chamfer_mm=0.8), z=PLATE_T_MM)
    frame = frame - at(box(BAY_W, BAY_H_Y, FRAME_Z), 0, 0, PLATE_T_MM + FLOOR_Z)
    for sx in (-1, 1):                                        # hinge blocks in the bay walls, clear of the paddle
        frame = frame + at(box(1.5, 8.0, HINGE_Z + 2.0 - PLATE_T_MM - FLOOR_Z), sx * (PAD_W / 2 + 1.25), 0, PLATE_T_MM + FLOOR_Z)
    loop = at(loop_mod.loop_lens(FRAME_W, FRAME_H_Y, LOOP_BAR, LOOP_Z, LOOP_GAP), z=PLATE_T_MM)
    expect(len(pad.solids()) == 1 and len(frame.solids()) == 1, "paddle and frame are each one solid")
    lo, hi = bbox_mm(pad)
    expect(abs(hi[0] - lo[0] - PAD_W) < 0.01, "paddle is as wide as stated")
    expect(abs(lo[0] + hi[0]) < 0.01 and abs(lo[1] + hi[1]) < 0.01, "paddle centred on its pivot in X and Y")
    # footprint
    w, h = base_size_mm(*BASE)
    llo, lhi = bbox_mm(loop)
    expect(lhi[0] - llo[0] < w - 2 * 4.0 and lhi[1] - llo[1] < h, f"frame and loop within the {w:g} x {h:g} mm base")
    # swing clearance at both ends: the paddle stays inside the bay and off its floor, and below the stand-out limit
    stand = 0.0
    for sgn in (-1, 1):
        t = _tilted(pad, sgn * half)
        tlo, thi = bbox_mm(t)
        expect(tlo[1] > -BAY_H_Y / 2 and thi[1] < BAY_H_Y / 2 and tlo[0] > -BAY_W / 2 and thi[0] < BAY_W / 2,
               f"paddle inside the bay at {sgn * half:+g} deg")
        expect(tlo[2] > PLATE_T_MM + FLOOR_Z + 0.5, f"paddle clear of the bay floor at {sgn * half:+g} deg (low point {tlo[2]:.1f})")
        expect((t & frame).volume < 1e-6, f"paddle clear of the frame at {sgn * half:+g} deg")
        stand = max(stand, thi[2])
    expect(stand <= MAX_STAND_OUT, f"stand-out {stand:.1f} mm, well under the bar toggle's 56 mm (limit {MAX_STAND_OUT})")
    expect(stand > PLATE_T_MM + FRAME_Z + 8.0, "lever stands well proud of the frame")
    # the loop clear of the bolts and the bay
    for bx, by in scene_module("control_base").bolt_positions(*BASE):
        expect(abs(bx) - 3.5 >= lhi[0] or abs(by) - 3.5 >= lhi[1], f"loop clear of bolt {bx:g},{by:g}")
    expect((loop & at(box(BAY_W, BAY_H_Y, 20.0), z=PLATE_T_MM)).volume < 1e-6, "loop clear of the bay")
    expect((loop & frame).volume < 1e-6, "loop clear of the frame")
    body = [Solid(frame, "interior_dark")]
    paddle = [Solid(pad, "control_grey")]
    lens = [Solid(loop, "indicator_ok")]
    expect_in_front(body + lens + [Solid(_tilted(pad, -half), "control_grey"), Solid(_tilted(pad, half), "control_grey")], SLUG)
    return body, paddle, lens, stand


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, paddle, lens, stand = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "BatToggleBody")
    rp = export_solids_glb(paddle, d / f"{SLUG}_paddle.glb", "BatTogglePaddle")
    rl = export_solids_glb(lens, d / f"{SLUG}_loop.glb", "BatToggleLoop")
    w, h = base_size_mm(*BASE)
    tris = rb["triangles"] + rp["triangles"] + rl["triangles"] + entry("control_base")["sizes"][f"{BASE[0]}x{BASE[1]}"]["triangles"]
    expect(tris <= TRIANGLE_BUDGET[GROUP], f"{tris} triangles; kit budget {TRIANGLE_BUDGET[GROUP]}")
    s = Scene("BatToggle", script="res://src/interact/switch_lever.gd")
    s.set(".", swing_deg=SWING_DEG, noise_profile=quiet_noise(s, 0.1, 2.0), pivot=NodePath("Pivot"),
          indicator=NodePath("IndicatorLamp"))
    s.node("Base", instance=base_glb(*BASE))
    s.node("Body", instance=rb["glb"])
    s.node("Pivot", props={"transform": Xform(origin=(0, 0, HINGE_Z / 1000))})
    s.node("Paddle", parent="Pivot", instance=rp["glb"])
    s.node("IndicatorLamp", script="res://src/interact/indicator_lamp.gd")
    s.node("Lens", parent="IndicatorLamp", instance=rl["glb"])
    s.set("IndicatorLamp", lamp=NodePath("Lens/BatToggleLoop"))
    gstand = (stand + 4.0) / 1000
    grab_box(s, ".", (w / 1000, h / 1000, gstand), (0, 0, gstand / 2))
    s.write(d / f"{SLUG}.tscn")
    _review(d)
    write_entry(GROUP, SLUG, {
        "kind": "control",
        "summary": "Lit bat toggle: a light grey flip lever with deep grip ridges standing out of a shallow recessed bay and flipping up and down about X, "
                   "a small swing and low stand-out. A rectangular LED loop round the bay is lit at on and dark at off, "
                   "with nothing wired on the instance. No round lamp.",
        "tags": ["toggle", "switch", "bat", "paddle", "lit", "led", "on-off", "indicator", "low-profile"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "SwitchLever", "values": "0 off (lever tipped to -Y, loop dark), 1 on (lever tipped to +Y, loop lit)",
                      "signal": "value_changed", "wiring": "none: `indicator` is set to the IndicatorLamp node"},
        "base": f"{BASE[0]}x{BASE[1]}",
        "footprint_mm": [w, h],
        "stand_out_mm": math.ceil(stand),
        "swing_envelope": {"swing_deg": SWING_DEG, "paddle_travel_deg": "+/-15 about X; the lever tip travels along Y",
                           "within_mm": [BAY_W, BAY_H_Y], "stand_out_mm": math.ceil(stand),
                           "note": "the bar toggle (lit_toggle) stands 56 mm out"},
        "mount": "back on Z=0, centred; front +Z; on flips the lever toward +Y; the LED loop encircles the bay",
        "set_on_instance": {"label": "name at the aiming point"},
        "uses": USES,
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}


def _review(d) -> None:
    """Review cameras: the concept view off and on, red light, and the profile at both ends."""
    c = {"pos": [0.17, 0.07, 0.22], "look_at": [0.0, 0.0, 0.01], "fov": 30.0}
    cams = [
        {"name": "concept_bat", **c},
        {"name": "concept_bat_on", **c, "on": True},
        {"name": "on_red", **c, "on": True, "light": "red"},
        {"name": "profile_off", "pos": [0.6, 0.0, 0.02], "look_at": [0.0, 0.0, 0.02], "ortho": 0.1},
        {"name": "profile_on", "pos": [0.6, 0.0, 0.02], "look_at": [0.0, 0.0, 0.02], "ortho": 0.1, "on": True},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    for n in (".gdignore", "cameras.json"):
        note(review / n)
