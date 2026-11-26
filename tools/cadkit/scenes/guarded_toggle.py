"""guarded_toggle: a two-position toggle under a hinged cap, with an indicator lamp. Base 1x2.

Brief (#603, concept #593): the side guard walls are gone. A cap in the guard colour (control_interface) hangs from a
hinge along its top edge and covers the bat; lifted, it flips up and forward, clear of the bat and inside the plate.
The bat swings +/-40 degrees about a hinge on X above a 12-gon collar. The cap is its own GLB with its hinge on the
origin; the scene's `Cap` node pivots it, closed by default. Behaviour: GuardedSwitch (#602).
`lit_guarded_toggle` reuses the solids and checks defined here.
"""
import math

import build123d as bd

from cadkit.solids import Solid, expect_in_front, at, bbox_mm, box, prism, expect, export_solids_glb
from cadkit.library import PLATE_T_MM, base_glb, base_size_mm, out_dir, quiet_noise, res, write_entry, scene_module
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "guarded_toggle", "kit"
USES: list[str] = ["control_base"]
BASE = (1, 2)
MAX_TRIS = 1500
COLLAR_R, COLLAR_H = 11.0, 8.0
HINGE_Z = PLATE_T_MM + COLLAR_H + 2.0              # the bat's hinge
BAT_R, BAT_LEN, KNOB_R, KNOB_H = 3.5, 30.0, 6.5, 10.0
SWING_DEG = 80.0
LAMP_R, LAMP_Y = 5.0, 46.0
# The cap: hangs from a hinge axis along X at (CAP_HY, CAP_HZ), down -Y, front plate toward +Z.
CAP_W, CAP_L, CAP_T = 40.0, 66.0, 3.0               # outer width, hang length below the hinge, plate and cheek thickness
CAP_HY, CAP_HZ = 33.0, 61.5
CAP_PIN_R, CAP_PIN_HALF = 2.5, 21.5     # the pin ends on the posts' inner faces
CAP_OPEN_DEG = 100.0                                # closed to open, about X (GuardedSwitch.cap_open_deg is the negative)
TAB_W, TAB_H, TAB_D = 18.0, 5.0, 8.0                # lift tab on the plate's bottom edge, standing toward the viewer
EYE_MM = (0.0, 550.0, 500.0)                       # the standing eye relative to the control (0.55 m above, 0.5 m out)
POST_X, POST_T, POST_H = 24.0, 5.0, 10.0            # hinge posts either side: centre x, width, height (Y)


def bat_solid() -> bd.Shape:
    bat = prism(8, BAT_R, BAT_LEN) + at(prism(8, KNOB_R, KNOB_H, chamfer_top=2.5), z=BAT_LEN)
    barrel = bd.extrude(bd.Plane.YZ * bd.RegularPolygon(BAT_R + 1.5, 8), amount=6.0, both=True)
    return bat + barrel


def cap_solid() -> bd.Shape:
    """Hinge axis on the origin, hanging down (-Y), front face toward +Z."""
    plate = at(box(CAP_W, CAP_L, CAP_T, chamfer_mm=1.0, base_z=False), y=-CAP_L / 2)
    depth = CAP_HZ - CAP_T / 2 - (PLATE_T_MM + 1.5)
    cheeks = [at(box(CAP_T, CAP_L, depth), sx * (CAP_W / 2 - CAP_T / 2), -CAP_L / 2, -CAP_T / 2 - depth) for sx in (-1, 1)]
    tab = at(box(TAB_W, TAB_H, TAB_D), y=-CAP_L + TAB_H, z=CAP_T / 2)
    pin = bd.extrude(bd.Plane.YZ * bd.RegularPolygon(CAP_PIN_R, 8), amount=CAP_PIN_HALF, both=True)
    return plate + cheeks[0] + cheeks[1] + tab + pin


def post_solids() -> list[bd.Shape]:
    return [at(box(POST_T, POST_H, CAP_HZ + CAP_PIN_R - PLATE_T_MM, chamfer_mm=1.0), sx * POST_X, CAP_HY, PLATE_T_MM) for sx in (-1, 1)]


def bat_pose(bat: bd.Shape, deg: float) -> bd.Shape:
    return at(bat, z=HINGE_Z, rx=deg)


def cap_pose(cap: bd.Shape, open_deg: float) -> bd.Shape:
    return at(at(cap, rx=-open_deg), y=CAP_HY, z=CAP_HZ)


def overlap_mm3(a: bd.Shape, b: bd.Shape) -> float:
    r = a & b
    return 0.0 if r is None else float(r.volume)


def check_cap(base: tuple[int, int], bat: bd.Shape, cap: bd.Shape, posts: list[bd.Shape], lamp_bottom: float, lamp_top: float) -> dict:
    """The cap's constraints against the plate, the bat, the bolts and the lamp. Returns its stand-outs (mm)."""
    w, h = base_size_mm(*base)
    expect(len(cap.solids()) == 1, "cap is one solid")
    expect(len(bat.solids()) == 1, "bat is one solid")
    closed, opened = cap_pose(cap, 0.0), cap_pose(cap, CAP_OPEN_DEG)
    # The bat clears the cap at both swing ends and in between.
    half = SWING_DEG / 2
    for deg in (-half, -half / 2, 0.0, half / 2, half):
        expect(overlap_mm3(bat_pose(bat, deg), closed) < 1e-3, f"the bat at {deg:+.0f} deg clears the closed cap")
    bat_z = max(bbox_mm(bat_pose(bat, d))[1][2] for d in (-half, 0.0, half))
    expect(CAP_HZ - CAP_T / 2 - bat_z >= 2.0, f"the closed cap's back clears the bat by {CAP_HZ - CAP_T / 2 - bat_z:.1f} mm; the brief needs 2")
    lo, hi = bbox_mm(closed)
    tip_y = (BAT_LEN + KNOB_H) * math.sin(math.radians(half)) + KNOB_R * math.cos(math.radians(half))
    expect(lo[1] <= -tip_y and CAP_HY - 1.0 >= tip_y, f"the closed cap covers the bat's full swing (tip reaches y {tip_y:.1f})")
    # The open cap clears the bat at both ends, and stays inside the plate (it must not reach a neighbouring control).
    for deg in (-half, half):
        expect(overlap_mm3(bat_pose(bat, deg), opened) < 1e-3, f"the bat at {deg:+.0f} deg clears the open cap")
    olo, ohi = bbox_mm(opened)
    expect(max(abs(olo[0]), abs(ohi[0]), CAP_PIN_HALF) <= w / 2 - 1.0, f"open cap inside the {w:.0f} mm plate width")
    expect(olo[1] >= -h / 2 + 1.0 and ohi[1] <= h / 2 - 1.0, f"open cap inside the {h:.0f} mm plate height ({olo[1]}..{ohi[1]})")
    expect(olo[2] >= PLATE_T_MM, "the open cap is nowhere behind the plate's front")
    # Posts and cap.
    for p in posts:
        pb = bbox_mm(p)
        expect(pb[1][0] <= w / 2 - 1.0, "hinge posts inside the plate")
        for pose in (closed, opened):
            expect(overlap_mm3(p, pose) < 1e-3, "the cap does not collide with its hinge posts")
    # Bolts stay clear of the posts and the closed cap.
    for bx, by in scene_module("control_base").bolt_positions(*base):
        post = at(bd.Cylinder(3.5, 10.0), bx, by, PLATE_T_MM + 5.0)
        expect(all(overlap_mm3(post, p) < 1e-3 for p in posts) and overlap_mm3(post, closed) < 1e-3, f"bolt at {bx},{by} clear of the cap and posts")
    # The lamp stays visible with the cap closed, and the lifted cap does not stand in front of it.
    expect(hi[1] + 1.0 <= lamp_bottom, f"the closed cap (top {hi[1]:.1f}) leaves the lamp (bottom {lamp_bottom:.1f}) visible")
    ly, lz = (lamp_bottom + lamp_top) / 2, PLATE_T_MM + 4.0
    dy, dz = EYE_MM[1] - ly, EYE_MM[2] - lz
    sight = at(box(6.0, 6.0, math.hypot(dy, dz)), 0, ly, lz, rx=-math.degrees(math.atan2(dy, dz)))
    expect(overlap_mm3(opened, sight) < 1e-3, "the lifted cap is not in the sight line from the standing eye to the lamp")
    expect(overlap_mm3(closed, sight) < 1e-3, "the closed cap is not in the sight line from the standing eye to the lamp")
    expect(lamp_top < h / 2 - 2.0, "lamp inside the plate")
    return {"closed": hi[2], "open": ohi[2]}


def solids() -> tuple[list[Solid], list[Solid], list[Solid], dict]:
    collar = at(prism(12, COLLAR_R, COLLAR_H), z=PLATE_T_MM)
    lamp_ring = at(prism(8, LAMP_R + 2.5, 2.0), 0, LAMP_Y, PLATE_T_MM)
    lamp = at(prism(8, LAMP_R, 4.0, chamfer_top=1.0), 0, LAMP_Y, PLATE_T_MM + 2.0)
    bat, cap, posts = bat_solid(), cap_solid(), post_solids()
    stand = check_cap(BASE, bat, cap, posts, LAMP_Y - (LAMP_R + 2.5), LAMP_Y + LAMP_R + 2.5)
    expect(HINGE_Z + BAT_LEN + KNOB_H > PLATE_T_MM + COLLAR_H, "bat stands proud of the collar so it can be grabbed")
    body = [Solid(collar, "interior_dark"), Solid(lamp_ring, "trim_black"), Solid(lamp, "indicator_off")] + [Solid(p, "control_interface") for p in posts]
    batl, capl = [Solid(bat, "control_grey")], [Solid(cap, "control_interface")]
    expect_in_front(body + [Solid(bat_pose(bat, 0.0), "control_grey"), Solid(cap_pose(cap, 0.0), "control_interface"),
                            Solid(cap_pose(cap, CAP_OPEN_DEG), "control_interface")], SLUG)
    return body, batl, capl, stand


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, bat, cap, stand = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "GuardedToggleBody")
    rt = export_solids_glb(bat, d / f"{SLUG}_bat.glb", "GuardedToggleBat")
    rc = export_solids_glb(cap, d / f"{SLUG}_cap.glb", "GuardedToggleCap")
    tris = rb["triangles"] + rt["triangles"] + rc["triangles"]
    expect(tris <= MAX_TRIS, f"{tris} triangles; the cap is {MAX_TRIS}")
    w, h = base_size_mm(*BASE)
    s = Scene("GuardedToggle", script="res://src/interact/guarded_switch.gd")
    s.set(".", swing_deg=SWING_DEG, noise_profile=quiet_noise(s, 0.15, 2.0), pivot=NodePath("Pivot"),
          cap=NodePath("Cap"), cap_open_deg=-CAP_OPEN_DEG)
    s.node("Base", instance=base_glb(*BASE))
    s.node("Body", instance=rb["glb"])
    s.node("Pivot", props={"transform": Xform(origin=(0, 0, HINGE_Z / 1000))})
    s.node("Bat", parent="Pivot", instance=rt["glb"])
    s.node("Cap", instance=rc["glb"], props={"transform": Xform(origin=(0, CAP_HY / 1000, CAP_HZ / 1000))})
    grab_box(s, ".", (w / 1000, h / 1000, stand["closed"] / 1000), (0, 0, stand["closed"] / 2000))
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "control",
        "summary": "Guarded two-position toggle under a hinged cap (control_interface colour). Click lifts the cap, a second "
                   "click sets the switch on and the cap stays open; click from on sets it off and closes the cap. A lifted "
                   "cap over an off switch drops after 5 s. Its lamp lens is a static solid (indicator_off): it does not light.",
        "tags": ["toggle", "switch", "guarded", "cap", "cover", "on-off", "lamp", "safety"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "GuardedSwitch", "values": "0 off (bat down, cap closed), 1 on (bat up, cap open)",
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
