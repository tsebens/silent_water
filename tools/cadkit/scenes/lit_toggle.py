"""lit_toggle: an unguarded two-position toggle with an indicator lamp on the plate above it. Base 1x3.

Brief: the shapes of guarded_toggle (12-gon collar, bat swinging +/-40 degrees on a hinge about X) with no guard walls,
on the 1x3 base; an indicator lamp (the kit scene, so its lens is its own GLB under an `IndicatorLamp` node) sits on the
extra plate directly above the switch. Behaviour: SwitchLever, whose `indicator` is that lamp: lit at on, dark at off.
"""
import json
import math

import build123d as bd

from cadkit.solids import Solid, at, prism, expect, expect_in_front, export_solids_glb
from cadkit.library import PLATE_T_MM, base_glb, base_size_mm, entry, out_dir, quiet_noise, note, res, scene_module, write_entry
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "lit_toggle", "kit"
USES: list[str] = ["control_base", "indicator_lamp"]
BASE = (1, 3)
COLLAR_R, COLLAR_H = 11.0, 8.0
HINGE_Z = PLATE_T_MM + COLLAR_H + 2.0
BAT_R, BAT_LEN, KNOB_R, KNOB_H = 3.5, 30.0, 6.5, 10.0
SWING_DEG = 80.0
SWITCH_Y = 0.0
LAMP_Y = 52.0                     # lamp centre, above the switch
GRAB_STAND = 40.0                 # grab box stand-out above the mount face (as the guarded toggle's guard)


def solids() -> tuple[list[Solid], list[Solid]]:
    w, h = base_size_mm(*BASE)
    lamp = entry("indicator_lamp")
    lamp_w, lamp_h = lamp["footprint_mm"]
    lamp_out = max(lamp_w, lamp_h) / 2
    collar = at(prism(12, COLLAR_R, COLLAR_H), 0, SWITCH_Y, PLATE_T_MM)
    bat = prism(8, BAT_R, BAT_LEN) + at(prism(8, KNOB_R, KNOB_H, chamfer_top=2.5), z=BAT_LEN)
    barrel = bd.extrude(bd.Plane.YZ * bd.RegularPolygon(BAT_R + 1.5, 8), amount=6.0, both=True)
    bat = bat + barrel
    tip = BAT_LEN + KNOB_H
    half = math.radians(SWING_DEG / 2)
    reach = tip * math.sin(half) + KNOB_R * math.cos(half)      # furthest the bat gets from the hinge along Y
    expect(HINGE_Z + tip > PLATE_T_MM + GRAB_STAND, "bat stands proud so it can be grabbed")
    expect(LAMP_Y + lamp_out < h / 2 - 2.0, "lamp inside the plate")
    expect(LAMP_Y - lamp_out > SWITCH_Y + reach, f"lamp clear of the bat's swing (reach {reach:.1f} mm)")
    for bx, by in scene_module("control_base").bolt_positions(*BASE):
        expect(((bx) ** 2 + (LAMP_Y - by) ** 2) ** 0.5 > lamp_out + 3.5, f"lamp clear of bolt {bx},{by}")
        expect(abs(by - SWITCH_Y) - 3.5 > reach or abs(bx) - 3.5 > COLLAR_R, f"bat and collar clear of bolt {bx},{by}")
    expect(len(bat.solids()) == 1, "bat is one solid")
    body = [Solid(collar, "interior_dark")]
    bat_s = [Solid(bat, "control_grey")]
    expect_in_front(body + [Solid(at(bat_s[0].shape, 0, SWITCH_Y, HINGE_Z), "control_grey")], SLUG)
    return body, bat_s


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, bat = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "LitToggleBody")
    rt = export_solids_glb(bat, d / f"{SLUG}_bat.glb", "LitToggleBat")
    lamp = entry("indicator_lamp")
    w, h = base_size_mm(*BASE)
    s = Scene("LitToggle", script="res://src/interact/switch_lever.gd")
    s.set(".", swing_deg=SWING_DEG, noise_profile=quiet_noise(s, 0.15, 2.0), pivot=NodePath("Pivot"),
          indicator=NodePath("IndicatorLamp"))
    s.node("Base", instance=base_glb(*BASE))
    s.node("Body", instance=rb["glb"])
    s.node("Pivot", props={"transform": Xform(origin=(0, SWITCH_Y / 1000, HINGE_Z / 1000))})
    s.node("Bat", parent="Pivot", instance=rt["glb"])
    s.node("IndicatorLamp", instance=lamp["scene"],
           props={"transform": Xform(origin=(0, LAMP_Y / 1000, PLATE_T_MM / 1000))})
    _review(d)
    stand = (PLATE_T_MM + GRAB_STAND) / 1000
    grab_box(s, ".", (w / 1000, h / 1000, stand), (0, 0, stand / 2))
    s.write(d / f"{SLUG}.tscn")
    tris = rb["triangles"] + rt["triangles"] + lamp["triangles"]
    stand_out = HINGE_Z + BAT_LEN + KNOB_H
    write_entry(GROUP, SLUG, {
        "kind": "control",
        "summary": "Unguarded two-position toggle with an indicator lamp on the plate above it. The light grey bat "
                   "swings +/-40 deg and snaps to on or off; the lamp is lit at on and dark at off, with nothing "
                   "wired on the instance.",
        "tags": ["toggle", "switch", "lit", "lamp", "on-off", "indicator"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "SwitchLever", "values": "0 off (bat down, lamp dark), 1 on (bat up, lamp lit)",
                      "signal": "value_changed", "wiring": "none: `indicator` is set to the IndicatorLamp node"},
        "base": f"{BASE[0]}x{BASE[1]}",
        "footprint_mm": [w, h],
        "stand_out_mm": stand_out,
        "mount": "back on Z=0, centred; front +Z; on is toward +Y; the lamp is above the switch (+Y)",
        "set_on_instance": {"label": "name at the aiming point"},
        "uses": USES,
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}


def _review(d) -> None:
    """Review cameras: the switch off (lamp dark) and on (lamp lit, `on`), in white and red light."""
    look = [0.0, 0.0, 0.02]
    cams = [
        {"name": "off", "pos": [0.12, 0.06, 0.42], "look_at": look, "fov": 30.0},
        {"name": "on", "pos": [0.12, 0.06, 0.42], "look_at": look, "fov": 30.0, "on": True},
        {"name": "on_red", "pos": [0.12, 0.06, 0.42], "look_at": look, "fov": 30.0, "on": True, "light": "red"},
        {"name": "profile_on", "pos": [0.6, 0.0, 0.03], "look_at": [0.0, 0.0, 0.03], "ortho": 0.22, "on": True},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    for n in (".gdignore", "cameras.json"):
        note(review / n)
