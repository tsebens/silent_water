"""guarded_toggle: a two-position toggle between orange guard walls, with an indicator lamp. Base 1x2.

Brief: the bat swings +/-40 degrees about a hinge on X above a 12-gon collar; guard walls either side stop side bumps;
the bat tip stays inside the guard's height at both ends. Behaviour: SwitchLever (snaps to on/off).
"""
import math

import build123d as bd

from cadkit.solids import Solid, expect_in_front, at, box, prism, expect, export_solids_glb
from cadkit.library import PLATE_T_MM, base_glb, base_size_mm, out_dir, quiet_noise, res, write_entry, scene_module
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "guarded_toggle", "kit"
USES: list[str] = ["control_base"]
BASE = (1, 2)
COLLAR_R, COLLAR_H = 11.0, 8.0
HINGE_Z = PLATE_T_MM + COLLAR_H + 2.0
GUARD_T, GUARD_H, GUARD_DEPTH, GUARD_GAP = 5.0, 64.0, 40.0, 17.0   # wall thickness, height (Y), stand-out, half gap
BAT_R, BAT_LEN, KNOB_R, KNOB_H = 3.5, 30.0, 6.5, 10.0
SWING_DEG = 80.0
LAMP_R, LAMP_Y = 5.0, 44.0


def solids() -> tuple[list[Solid], list[Solid]]:
    w, h = base_size_mm(*BASE)
    collar = at(prism(12, COLLAR_R, COLLAR_H), z=PLATE_T_MM)
    walls = [at(box(GUARD_T, GUARD_H, GUARD_DEPTH), sx * (GUARD_GAP + GUARD_T / 2), 0, PLATE_T_MM) for sx in (-1, 1)]
    walls = [bd.chamfer(wl.edges().filter_by(bd.Axis.X).group_by(bd.Axis.Z)[-1], 5.0) for wl in walls]
    lamp_ring = at(prism(8, LAMP_R + 2.5, 2.0), 0, LAMP_Y, PLATE_T_MM)
    lamp = at(prism(8, LAMP_R, 4.0, chamfer_top=1.0), 0, LAMP_Y, PLATE_T_MM + 2.0)
    bat = prism(8, BAT_R, BAT_LEN) + at(prism(8, KNOB_R, KNOB_H, chamfer_top=2.5), z=BAT_LEN)
    barrel = bd.extrude(bd.Plane.YZ * bd.RegularPolygon(BAT_R + 1.5, 8), amount=6.0, both=True)
    bat = bat + barrel
    # Checks against the brief.
    tip = BAT_LEN + KNOB_H
    half = math.radians(SWING_DEG / 2)
    expect(tip * math.sin(half) + KNOB_R * math.cos(half) <= GUARD_H / 2 + 2.0, "bat tip stays within the guard height at full swing")
    expect(KNOB_R < GUARD_GAP, "knob clears the guard walls")
    expect(HINGE_Z + tip > PLATE_T_MM + GUARD_DEPTH, "bat stands proud of the guard so it can be grabbed")
    for bx, by in scene_module("control_base").bolt_positions(*BASE):
        expect(abs(by) - 3.5 > GUARD_H / 2 or abs(bx) + 3.5 < GUARD_GAP, f"bolt at {bx},{by} clear of the guard")
    lamp_out = LAMP_R + 2.5
    expect(LAMP_Y + lamp_out < h / 2 - 2.0, "lamp inside the plate")
    expect(LAMP_Y - lamp_out > GUARD_H / 2, "lamp above the guard walls")
    for bx, by in scene_module("control_base").bolt_positions(*BASE):
        expect(((bx) ** 2 + (LAMP_Y - by) ** 2) ** 0.5 > lamp_out + 3.5, f"lamp clear of bolt {bx},{by}")
    expect(len(bat.solids()) == 1, "bat is one solid")
    body = [Solid(collar, "powder_grey"), Solid(lamp_ring, "black"), Solid(lamp, "led")] + [Solid(wl, "safety_orange") for wl in walls]
    bat = [Solid(bat, "black")]
    expect_in_front(body + [Solid(at(bat[0].shape, z=HINGE_Z), "black")], SLUG)
    return body, bat


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, bat = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "GuardedToggleBody")
    rt = export_solids_glb(bat, d / f"{SLUG}_bat.glb", "GuardedToggleBat")
    w, h = base_size_mm(*BASE)
    s = Scene("GuardedToggle", script="res://src/interact/switch_lever.gd")
    s.set(".", swing_deg=SWING_DEG, noise_profile=quiet_noise(s, 0.15, 2.0), pivot=NodePath("Pivot"))
    s.node("Base", instance=base_glb(*BASE))
    s.node("Body", instance=rb["glb"])
    s.node("Pivot", props={"transform": Xform(origin=(0, 0, HINGE_Z / 1000))})
    s.node("Bat", parent="Pivot", instance=rt["glb"])
    stand = (PLATE_T_MM + GUARD_DEPTH) / 1000
    grab_box(s, ".", (w / 1000, h / 1000, stand), (0, 0, stand / 2))
    s.write(d / f"{SLUG}.tscn")
    tris = rb["triangles"] + rt["triangles"]
    write_entry(GROUP, SLUG, {
        "kind": "control",
        "summary": "Guarded two-position toggle; bat swings +/-40 deg and snaps to on or off. Its lamp is a static "
                   "coloured solid: it does not light.",
        "tags": ["toggle", "switch", "guarded", "on-off", "lamp", "safety"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "SwitchLever", "values": "0 off (bat down), 1 on (bat up)", "signal": "value_changed"},
        "base": f"{BASE[0]}x{BASE[1]}",
        "footprint_mm": [w, h],
        "stand_out_mm": HINGE_Z + BAT_LEN + KNOB_H,
        "mount": "back on Z=0, centred; front +Z; on is toward +Y",
        "set_on_instance": {"label": "name at the aiming point"},
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
