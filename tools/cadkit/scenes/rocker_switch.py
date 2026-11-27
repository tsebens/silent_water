"""rocker_switch: a lit two-position rocker on the 1x2 base: a black paddle in an orange bezel, low profile.

Brief (concept #700): the paddle is its own GLB, modelled with its X pivot through the origin, and carries a `led_strip`
(the kit scene, scaled to the paddle) on its upper half as a child, so the strip moves with it. On: the upper half is
pressed in and the bar lit. Off: the lower half is pressed in, the upper half stands out and the bar is dark. No round
lamp. Behaviour: SwitchLever (+SWING/2 about X at off, -SWING/2 at on), `indicator` set to the strip.
"""
import json
import math

from cadkit.solids import Solid, at, box, bbox_mm, expect, expect_in_front, export_solids_glb
from cadkit.library import PLATE_T_MM, base_glb, base_size_mm, entry, out_dir, quiet_noise, note, res, scene_module, write_entry
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "rocker_switch", "kit"
USES: list[str] = ["control_base", "led_strip"]
BASE = (1, 2)
BEZEL_W, BEZEL_H, BEZEL_D = 32.0, 52.0, 5.0       # outer size and height above the plate
OPEN_W, OPEN_H = 24.0, 42.0                        # the opening the paddle sits in
PAD_W, PAD_H, PAD_T = 20.0, 36.0, 4.0              # paddle: width (X), height (Y), thickness (Z), centred on the pivot
SWING_DEG = 20.0
STRIP_LEN, STRIP_Y = 15.0, 11.0                    # strip length (instance scale) and centre height on the paddle
FOLLOW_MM = 1.0                                    # clearance used by the swing checks
BUDGET = 1500


def _pose(shape, deg: float):
    """The paddle as it is at pivot angle `deg` (degrees about X), pivot at the origin."""
    return at(shape, rx=deg)


def solids() -> tuple[list[Solid], list[Solid], dict]:
    w, h = base_size_mm(*BASE)
    strip = entry("led_strip")
    ref_len, strip_w = strip["footprint_mm"]
    strip_h = strip["stand_out_mm"]
    scale_x = STRIP_LEN / ref_len
    half = SWING_DEG / 2

    bezel = at(box(BEZEL_W, BEZEL_H, BEZEL_D, chamfer_mm=0.8), z=PLATE_T_MM)
    bezel = bezel - at(box(OPEN_W, OPEN_H, BEZEL_D + 2), z=PLATE_T_MM - 1)
    expect(len(bezel.solids()) == 1, "bezel is one solid")
    pad = box(PAD_W, PAD_H, PAD_T, chamfer_mm=0.8, base_z=False)
    expect(len(pad.solids()) == 1, "paddle is one solid")

    reach_y = PAD_H / 2 * math.cos(math.radians(half)) + PAD_T / 2 * math.sin(math.radians(half))
    drop = PAD_H / 2 * math.sin(math.radians(half)) + PAD_T / 2 * math.cos(math.radians(half))   # furthest Z from the pivot
    hinge_z = PLATE_T_MM + drop + 0.5                  # the pressed end stops just clear of the plate face
    # footprint: the bezel, and it sits inside the 1x2 base with the bolts clear
    expect(BEZEL_W <= w - 2 and BEZEL_H <= h - 2, f"bezel {BEZEL_W} x {BEZEL_H} inside the {w} x {h} base")
    for bx, by in scene_module("control_base").bolt_positions(*BASE):
        expect(abs(bx) - 3.5 > BEZEL_W / 2 or abs(by) - 3.5 > BEZEL_H / 2, f"bezel clear of bolt {bx},{by}")
    # swing clearance at both ends: the posed paddle stays inside the bezel opening
    for deg, name in ((half, "off"), (-half, "on")):
        lo, hi = bbox_mm(_pose(pad, deg))
        expect(lo[0] >= -OPEN_W / 2 + FOLLOW_MM and hi[0] <= OPEN_W / 2 - FOLLOW_MM,
               f"paddle inside the bezel opening in X at {name}: {lo[0]}..{hi[0]}")
        expect(lo[1] >= -OPEN_H / 2 + FOLLOW_MM and hi[1] <= OPEN_H / 2 - FOLLOW_MM,
               f"paddle inside the bezel opening in Y at {name}: {lo[1]}..{hi[1]}")
        expect(hinge_z + lo[2] >= PLATE_T_MM, f"nothing behind the plate face at {name}: z {hinge_z + lo[2]:.2f}")
    # strip: inside the upper half of the paddle at both ends (checked in the paddle frame, and so posed)
    strip_z = PAD_T / 2
    expect(STRIP_Y - strip_w / 2 > 0 and STRIP_Y + strip_w / 2 < PAD_H / 2, "strip inside the paddle's upper half")
    expect(STRIP_LEN / 2 < PAD_W / 2 - 1.0, "strip inside the paddle's width")
    expect(strip_h <= 3.0, "strip is flat")
    expect(0.25 <= scale_x <= 3.0, f"strip length {STRIP_LEN} mm within the strip's limits")
    # on: the upper half is the pressed one; off: the lower half
    for deg, name, upper_in in ((-half, "on", True), (half, "off", False)):
        up = hinge_z + (STRIP_Y * math.sin(math.radians(deg)) + strip_z * math.cos(math.radians(deg)))
        low = hinge_z + (-STRIP_Y * math.sin(math.radians(deg)) + strip_z * math.cos(math.radians(deg)))
        expect((up < low) == upper_in, f"at {name} the upper half is {'deeper' if upper_in else 'proud'}")
    top = hinge_z + math.sin(math.radians(half)) * (STRIP_Y + strip_w / 2) + (strip_z + strip_h) * math.cos(math.radians(half))
    stand_out = max(hinge_z + drop, top, PLATE_T_MM + BEZEL_D)
    body = [Solid(bezel, "control_interface")]
    pad_s = [Solid(pad, "trim_black")]
    expect_in_front(body, SLUG)
    expect_in_front([Solid(at(_pose(pad, half), z=hinge_z), "trim_black")], SLUG)
    expect_in_front([Solid(at(_pose(pad, -half), z=hinge_z), "trim_black")], SLUG)
    return body, pad_s, {"hinge_z": hinge_z, "stand_out": stand_out, "scale_x": scale_x, "strip": strip,
                         "pressed_depth": drop}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, pad, m = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_bezel.glb", "RockerBezel")
    rp = export_solids_glb(pad, d / f"{SLUG}_paddle.glb", "RockerPaddle")
    strip = m["strip"]
    tris = rb["triangles"] + rp["triangles"] + strip["triangles"]
    expect(tris <= BUDGET, f"{tris} triangles; kit budget {BUDGET}")
    w, h = base_size_mm(*BASE)
    hinge_z = m["hinge_z"]
    s = Scene("RockerSwitch", script="res://src/interact/switch_lever.gd")
    s.set(".", swing_deg=SWING_DEG, noise_profile=quiet_noise(s, 0.1, 1.5), pivot=NodePath("Pivot"),
          indicator=NodePath("Pivot/Paddle/LedStrip"))
    s.node("Base", instance=base_glb(*BASE))
    s.node("Bezel", instance=rb["glb"])
    s.node("Pivot", props={"transform": Xform(origin=(0, 0, hinge_z / 1000))})
    s.node("Paddle", parent="Pivot", instance=rp["glb"])
    s.node("LedStrip", parent="Pivot/Paddle", instance=strip["scene"], props={
        "transform": Xform.frame((m["scale_x"], 0, 0), (0, 1, 0), (0, 0, 1),
                                                   origin=(0, STRIP_Y / 1000, PAD_T / 2000))})
    _review(d)
    stand = m["stand_out"] / 1000 + 0.004
    grab_box(s, ".", (BEZEL_W / 1000, BEZEL_H / 1000, stand), (0, 0, stand / 2))
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "control",
        "summary": "Lit rocker switch: a low black paddle in an orange bezel on the 1x2 base. At on the upper half is "
                   "pressed in and the LED strip on it is lit; at off the lower half is pressed in, the upper half "
                   "stands out and the bar is dark. SwitchLever, nothing wired on the instance. Small swing, so a "
                   "later small guard cap can cover it.",
        "tags": ["rocker", "switch", "toggle", "lit", "led", "on-off", "indicator", "low-profile"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "SwitchLever", "values": "0 off (lower half in, bar dark), 1 on (upper half in, bar lit)",
                      "signal": "value_changed", "wiring": "none: `indicator` is set to the paddle's LedStrip"},
        "base": f"{BASE[0]}x{BASE[1]}",
        "footprint_mm": [w, h],
        "stand_out_mm": round(m["stand_out"], 2),
        "swing_envelope_mm": {"swing_deg": SWING_DEG, "paddle_inside_opening_mm": [OPEN_W, OPEN_H],
                              "bezel_mm": [BEZEL_W, BEZEL_H, BEZEL_D],
                              "bezel_top_z": PLATE_T_MM + BEZEL_D, "pivot_z": round(hinge_z, 2),
                              "paddle_extreme_z": round(hinge_z + m["pressed_depth"], 2)},
        "mount": "back on Z=0, centred; front +Z; on is the upper half (+Y) pressed in",
        "set_on_instance": {"label": "name at the aiming point"},
        "uses": USES,
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}


def _review(d) -> None:
    """Review cameras: the concept view (off first: the renderer keeps the state once a camera turns it on), the face in red light and a side profile."""
    look = [0.0, 0.0, 0.02]
    c = {"pos": [0.075, 0.095, 0.30], "look_at": look, "fov": 30.0}
    cams = [
        {"name": "concept_rocker", **c},
        {"name": "profile_off", "pos": [0.6, 0.0, 0.015], "look_at": [0.0, 0.0, 0.015], "ortho": 0.07},
        {"name": "concept_rocker_on", **c, "on": True},
        {"name": "on_red", **c, "on": True, "light": "red"},
        {"name": "profile_on", "pos": [0.6, 0.0, 0.015], "look_at": [0.0, 0.0, 0.015], "ortho": 0.07, "on": True},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    for n in (".gdignore", "cameras.json"):
        note(review / n)
