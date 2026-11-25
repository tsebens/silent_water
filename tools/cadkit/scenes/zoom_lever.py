"""zoom_lever: a short spring-centred lever on a control base, for the map table's zoom rate. Base 1x2.

Brief: the lever rests upright (toward +Z) and swings +/-30 degrees about a hinge on X; up zooms in, down zooms out.
A yellow handle on a short shaft rises from a 12-gon collar; the handle stays inside the plate at both ends of the
throw and clears the bolts. Behaviour: ZoomLever (springs back to centre on release).
"""
import math

import build123d as bd

from cadkit.solids import Solid, expect_in_front, at, prism, expect, bbox_mm, export_solids_glb
from cadkit.library import PLATE_T_MM, base_glb, base_size_mm, out_dir, quiet_noise, res, write_entry, scene_module
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "zoom_lever", "kit"
USES: list[str] = ["control_base"]
BASE = (1, 2)
COLLAR_R, COLLAR_H = 11.0, 8.0
HINGE_Z = PLATE_T_MM + COLLAR_H + 2.0
SHAFT_R, SHAFT_LEN, KNOB_R, KNOB_H = 3.5, 26.0, 7.0, 12.0
SWING_DEG = 60.0   # total throw, centred on upright
CLEARANCE = 2.0    # handle edge to plate edge, mm


def solids() -> tuple[list[Solid], list[Solid]]:
    w, h = base_size_mm(*BASE)
    collar = at(prism(12, COLLAR_R, COLLAR_H), z=PLATE_T_MM)
    lever = prism(8, SHAFT_R, SHAFT_LEN) + at(prism(8, KNOB_R, KNOB_H, chamfer_top=3.0), z=SHAFT_LEN)
    barrel = bd.extrude(bd.Plane.YZ * bd.RegularPolygon(SHAFT_R + 1.5, 8), amount=6.0, both=True)
    lever = lever + barrel
    tip = SHAFT_LEN + KNOB_H
    half = math.radians(SWING_DEG / 2)
    reach_y = tip * math.sin(half) + KNOB_R * math.cos(half)
    expect(reach_y <= h / 2 - CLEARANCE, "handle stays inside the plate at both ends of the throw")
    expect(KNOB_R < COLLAR_R, "handle is narrower than the collar")
    expect(tip * math.cos(half) > 20.0, "handle stands proud of the plate at full throw")
    for bx, by in scene_module("control_base").bolt_positions(*BASE):
        d = 3.5 + KNOB_R
        expect(abs(by) > reach_y + 3.5 or abs(bx) > d, f"throw clears bolt {bx},{by}")
    expect(len(lever.solids()) == 1, "lever is one solid")
    expect(abs(bbox_mm(lever)[0][2] - (-(SHAFT_R + 1.5))) < 0.5 or bbox_mm(lever)[0][2] <= 0.01, "lever pivots at its own origin")
    body = [Solid(collar, "interior_dark")]
    handle = [Solid(lever, "lever")]
    expect_in_front(body + [Solid(at(handle[0].shape, z=HINGE_Z), "lever")], SLUG)
    return body, handle


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, handle = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "ZoomLeverBody")
    rh = export_solids_glb(handle, d / f"{SLUG}_handle.glb", "ZoomLeverHandle")
    w, h = base_size_mm(*BASE)
    s = Scene("ZoomLever", script="res://src/interact/zoom_lever.gd")
    s.set(".", swing_deg=SWING_DEG, noise_profile=quiet_noise(s, 0.15, 2.0), pivot=NodePath("Pivot"))
    s.node("Base", instance=base_glb(*BASE))
    s.node("Body", instance=rb["glb"])
    s.node("Pivot", props={"transform": Xform(origin=(0, 0, HINGE_Z / 1000))})
    s.node("Handle", parent="Pivot", instance=rh["glb"])
    stand = (HINGE_Z + SHAFT_LEN + KNOB_H) / 1000
    grab_box(s, ".", (w / 1000, h / 1000, stand), (0, 0, stand / 2))
    s.write(d / f"{SLUG}.tscn")
    tris = rb["triangles"] + rh["triangles"]
    write_entry(GROUP, SLUG, {
        "kind": "control",
        "summary": "Short spring-centred lever on a 1x2 base; yellow handle swings +/-30 deg and returns to centre on release. "
                   "Emits a zoom rate -1..1 (up zooms in).",
        "tags": ["lever", "zoom", "spring", "rate", "map"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "ZoomLever", "values": "-1 down (zoom out), 0 centre, 1 up (zoom in)", "signal": "zoom_rate_changed"},
        "base": f"{BASE[0]}x{BASE[1]}",
        "footprint_mm": [w, h],
        "stand_out_mm": HINGE_Z + SHAFT_LEN + KNOB_H,
        "mount": "back on Z=0, centred; front +Z; up is toward +Y",
        "set_on_instance": {"label": "name at the aiming point"},
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
