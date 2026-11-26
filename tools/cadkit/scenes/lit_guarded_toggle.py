"""lit_guarded_toggle: guarded_toggle's switch and hinged cap on a 1x3 base with a real indicator_lamp above the cap, lit by the switch. Base 1x3.

Brief (#603): as guarded_toggle (the cap's solids and checks are that script's); the lamp stays visible with the cap
closed and is not covered by it lifted. Behaviour: GuardedSwitch (#602).
"""
import build123d as bd

from cadkit.solids import Solid, expect_in_front, at, expect, export_solids_glb, prism
from cadkit.library import entry, scene_path, PLATE_T_MM, base_glb, base_size_mm, out_dir, quiet_noise, res, write_entry, scene_module
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "lit_guarded_toggle", "kit"
USES: list[str] = ["control_base", "indicator_lamp", "guarded_toggle"]
BASE = (1, 3)
MAX_TRIS = 1500
LAMP_Y = 56.0   # the indicator_lamp instance sits at (0, LAMP_Y) on the plate


def solids() -> tuple[list[Solid], list[Solid], list[Solid], dict]:
    g = scene_module("guarded_toggle")
    lamp_out = entry("indicator_lamp")["footprint_mm"][0] / 2
    collar = at(prism(12, g.COLLAR_R, g.COLLAR_H), z=PLATE_T_MM)
    bat, cap, posts = g.bat_solid(), g.cap_solid(), g.post_solids()
    stand = g.check_cap(BASE, bat, cap, posts, LAMP_Y - lamp_out, LAMP_Y + lamp_out)
    for bx, by in scene_module("control_base").bolt_positions(*BASE):
        expect(((bx) ** 2 + (LAMP_Y - by) ** 2) ** 0.5 > lamp_out + 3.5, f"lamp clear of bolt {bx},{by}")
    body = [Solid(collar, "interior_dark")] + [Solid(p, "control_interface") for p in posts]
    batl, capl = [Solid(bat, "control_grey")], [Solid(cap, "control_interface")]
    expect_in_front(body + [Solid(g.bat_pose(bat, 0.0), "control_grey"), Solid(g.cap_pose(cap, 0.0), "control_interface"),
                            Solid(g.cap_pose(cap, g.CAP_OPEN_DEG), "control_interface")], SLUG)
    return body, batl, capl, stand


def build() -> dict:
    g = scene_module("guarded_toggle")
    d = out_dir(GROUP, SLUG)
    body, bat, cap, stand = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "LitGuardedToggleBody")
    rt = export_solids_glb(bat, d / f"{SLUG}_bat.glb", "LitGuardedToggleBat")
    rc = export_solids_glb(cap, d / f"{SLUG}_cap.glb", "LitGuardedToggleCap")
    w, h = base_size_mm(*BASE)
    tris = rb["triangles"] + rt["triangles"] + rc["triangles"] + entry("indicator_lamp")["triangles"]
    expect(tris <= MAX_TRIS, f"{tris} triangles; the cap is {MAX_TRIS}")
    s = Scene("LitGuardedToggle", script="res://src/interact/guarded_switch.gd")
    s.set(".", swing_deg=g.SWING_DEG, noise_profile=quiet_noise(s, 0.15, 2.0), pivot=NodePath("Pivot"),
          cap=NodePath("Cap"), cap_open_deg=-g.CAP_OPEN_DEG)
    s.node("Base", instance=base_glb(*BASE))
    s.node("Body", instance=rb["glb"])
    s.node("Pivot", props={"transform": Xform(origin=(0, 0, g.HINGE_Z / 1000))})
    s.node("Bat", parent="Pivot", instance=rt["glb"])
    s.node("Cap", instance=rc["glb"], props={"transform": Xform(origin=(0, g.CAP_HY / 1000, g.CAP_HZ / 1000))})
    s.node("Lamp", instance=scene_path("indicator_lamp"), props={"transform": Xform(origin=(0, LAMP_Y / 1000, PLATE_T_MM / 1000))})
    s.set(".", indicator=NodePath("Lamp"))
    grab_box(s, ".", (w / 1000, h / 1000, stand["closed"] / 1000), (0, 0, stand["closed"] / 2000))
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "control",
        "summary": "Guarded two-position toggle under a hinged cap, on a tall plate. Click lifts the cap, a second click sets "
                   "the switch on and the cap stays open; click from on sets it off and closes the cap; a lifted cap over an "
                   "off switch drops after 5 s. A real indicator lamp above the cap is lit while the switch is on and dark "
                   "while off, visible with the cap closed, with nothing to wire.",
        "tags": ["toggle", "switch", "guarded", "cap", "cover", "on-off", "lamp", "lit", "safety"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "GuardedSwitch", "values": "0 off (bat down, cap closed, lamp dark), 1 on (bat up, cap open, lamp lit)",
                      "signal": "value_changed", "cap": "child node `Cap` (hinge pivot), closed by default; cap_changed(open)"},
        "base": f"{BASE[0]}x{BASE[1]}",
        "footprint_mm": [w, h],
        "stand_out_mm": round(stand["closed"], 1),
        "stand_out_open_mm": round(stand["open"], 1),
        "mount": "back on Z=0, centred; front +Z; on is toward +Y; the cap's hinge is along its top edge, +Y",
        "set_on_instance": {"label": "name at the aiming point"},
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
