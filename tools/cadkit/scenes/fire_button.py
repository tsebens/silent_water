"""fire_button: the guarded FIRE button of a decoy launch tube. A push_button under a hinged hazard-stripe flip guard, on a 2x2 base.

Built as the drop_weights_button is (#764, concept #758); posts in the button red. Original brief (#569, concept #530): the guard hangs from a hinge along its top edge and covers the button when closed; lifting it
flips it up and forward, clear of the button and of the sight line from a standing eye. The guard is its own GLB with its
hinge on the origin, driven by a SwitchLever (two positions: closed at min, open at max); `FireButton` on the root
gates the press on the guard being open.
"""
import math

import build123d as bd

from cadkit.solids import Solid, at, bbox_mm, box, expect, expect_in_front, export_solids_glb
from cadkit.library import PLATE_T_MM, base_glb, base_size_mm, entry, out_dir, quiet_noise, res, scene_path, scene_module, write_entry
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "fire_button", "kit"
USES: list[str] = ["control_base", "push_button"]
BASE = (2, 2)
MAX_TRIS = 1500
HINGE_Y, HINGE_Z = 36.0, 24.0         # the hinge axis (along X), on the plate: above the button, clear of the cap
LID_W, LID_H, LID_T = 72.0, 72.0, 4.0  # the guard plate, hanging from the hinge
TAB_W, TAB_H, TAB_D = 30.0, 6.0, 10.0  # the lift tab on the lid's bottom edge, standing toward the viewer
PIN_R, PIN_HALF = 4.5, 44.0           # hinge pin: radius, half length
POST_W, POST_H = 6.0, 18.0            # hinge posts either side of the lid
SWING_DEG = 160.0                      # closed to open
EYE_MM = (0.0, 550.0, 500.0)           # the standing eye relative to the button (concept: 0.55 m above, 0.5 m out)


def overlap_mm3(a: bd.Shape, b: bd.Shape) -> float:
    r = a & b
    return 0.0 if r is None else float(r.volume)


def lid_solid() -> bd.Shape:
    """Modelled with the hinge axis on the origin, hanging down (-Y), front face toward +Z."""
    plate = at(box(LID_W, LID_H, LID_T, chamfer_mm=1.0, base_z=False), y=-LID_H / 2)
    tab = at(box(TAB_W, TAB_H, TAB_D), y=-LID_H + TAB_H / 2 + 3.0, z=LID_T / 2)
    pin = bd.extrude(bd.Plane.YZ * bd.RegularPolygon(PIN_R, 8), amount=PIN_HALF, both=True)
    return plate + tab + pin


def solids():
    w, h = base_size_mm(*BASE)
    pb = entry("push_button")
    cap_top = pb["stand_out_mm"]
    ring_r = pb["footprint_mm"][0] / 2
    lid = lid_solid()
    expect(len(lid.solids()) == 1, "guard is one solid")
    guard = [Solid(lid, "hazard_stripe")]
    post_x = PIN_HALF - POST_W / 2
    posts = [at(box(POST_W, POST_H, HINGE_Z - PLATE_T_MM + PIN_R + 2.0), sx * post_x, HINGE_Y, PLATE_T_MM) for sx in (-1, 1)]
    body = [Solid(p, "button") for p in posts]

    def pose(shape: bd.Shape, deg: float) -> bd.Shape:
        return at(at(shape, rx=-deg), y=HINGE_Y, z=HINGE_Z)

    closed, opened = pose(lid, 0.0), pose(lid, SWING_DEG)
    # The button, in the plate's frame: its ring and cap, from push_button's entry.
    cap_axis = at(box(2 * ring_r, 2 * ring_r, cap_top - PLATE_T_MM), z=PLATE_T_MM)
    # Footprint and stand-out.
    lo, hi = bbox_mm(closed)
    stand_out = max(hi[2], max(bbox_mm(p.shape)[1][2] for p in body))
    expect(max(abs(lo[0]), abs(hi[0]), PIN_HALF) <= w / 2, f"guard and hinge inside the {w:.0f} mm plate")
    expect(lo[1] >= -h / 2 and max(hi[1], HINGE_Y + POST_H / 2) <= h / 2, f"guard and hinge inside the {h:.0f} mm plate")
    # Bolts stay clear of the posts.
    for bx, by in scene_module("control_base").bolt_positions(*BASE):
        near_post = any(abs(abs(bx) - post_x) < POST_W / 2 + 3.5 and abs(by - HINGE_Y) < POST_H / 2 + 3.5 for _ in (0,))
        expect(not near_post, f"bolt at {bx},{by} clear of the hinge posts")
        expect(overlap_mm3(at(bd.Cylinder(3.5, 10.0), bx, by, PLATE_T_MM + 5.0), closed) < 1e-3, f"bolt at {bx},{by} clear of the closed guard")
    # Closed: the guard covers the button, clear of the cap.
    expect(abs(lo[0]) >= ring_r and lo[1] <= -ring_r and hi[1] >= ring_r, "closed guard covers the button's ring")
    lid_back = HINGE_Z - LID_T / 2
    expect(lid_back >= cap_top + 2.0, f"closed guard's back (z {lid_back}) clears the cap top (z {cap_top}) by 2 mm")
    expect(overlap_mm3(closed, cap_axis) < 1e-3, "closed guard does not touch the button")
    # Open: the guard clears the button's footprint and the sight line from the standing eye to the cap.
    d = math.hypot(EYE_MM[1], EYE_MM[2])
    tilt = -math.degrees(math.atan2(EYE_MM[1], EYE_MM[2]))
    sight = at(box(6.0, 6.0, d), 0, 0, cap_top, rx=tilt)
    expect(overlap_mm3(closed, sight) > 1.0, "the closed guard blocks the sight line (the check can see the guard)")
    expect(overlap_mm3(opened, sight) < 1e-3, "the open guard clears the sight line from the standing eye")
    expect(overlap_mm3(opened, cap_axis) < 1e-3, "the open guard clears the button")
    olo, ohi = bbox_mm(opened)
    expect(olo[2] >= HINGE_Z - PIN_R - 0.1, "the open guard is nowhere behind the hinge line (nothing behind the mount face)")
    stand_open = ohi[2]
    expect(max(stand_out, stand_open) <= 60.0, f"guard stands {max(stand_out, stand_open):.0f} mm out at most; the brief allows 60")
    expect_in_front(body + [Solid(closed, "hazard_stripe"), Solid(opened, "hazard_stripe")], SLUG)
    return body, guard, stand_out


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, guard, stand_out = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "FireButtonBody")
    rg = export_solids_glb(guard, d / f"{SLUG}_guard.glb", "FireButtonGuard")
    w, h = base_size_mm(*BASE)
    pb = entry("push_button")
    tris = rb["triangles"] + rg["triangles"] + pb["triangles"]
    expect(tris <= MAX_TRIS, f"{tris} triangles; the cap is {MAX_TRIS}")
    s = Scene("FireButton", script="res://src/interact/fire_button.gd")
    s.node("Base", instance=base_glb(*BASE))
    s.node("Body", instance=rb["glb"])
    s.node("Button", instance=scene_path("push_button"), props={"transform": Xform(origin=(0, 0, PLATE_T_MM / 1000))})
    s.node("Guard", type_="Node3D", script="res://src/interact/switch_lever.gd",
           props={"transform": Xform(origin=(0, HINGE_Y / 1000, HINGE_Z / 1000))})
    s.set("Guard", swing_deg=SWING_DEG, noise_profile=quiet_noise(s, 0.2, 2.0), pivot=NodePath("Pivot"), label="guard")
    s.node("Pivot", parent="Guard")
    half = math.radians(SWING_DEG / 2)
    c, sn = math.cos(-half), math.sin(-half)
    # Closed is the pivot at +half; this fixed offset of -half makes the lid hang flat then.
    s.node("Lid", parent="Guard/Pivot", props={"transform": Xform.frame((1, 0, 0), (0, c, sn), (0, -sn, c))})
    s.node("GuardMesh", parent="Guard/Pivot/Lid", instance=rg["glb"])
    lid_stand = TAB_D + LID_T / 2
    grab_box(s, "Guard/Pivot/Lid", (LID_W / 1000, LID_H / 1000, (lid_stand + LID_T / 2) / 1000),
             (0, -LID_H / 2000, (lid_stand - LID_T / 2) / 2000))
    s.set(".", guard=NodePath("Guard"), button=NodePath("Button"))
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "control",
        "summary": "FIRE: a red push button on a 2x2 plate under a hazard-striped flip guard hinged along its top "
                   "edge. Click the guard to lift it up and forward; click again to close it. The button counts "
                   "only while the guard is open, then fires the tube set on `tube`.",
        "tags": ["fire", "launch", "decoy", "emergency", "button", "guard", "flip guard", "hazard", "release"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "FireButton",
                      "values": "guard is a SwitchLever: 0 closed, 1 open; the press is the push_button",
                      "signal": "pressed",
                      "wiring": "`guard` and `button` are set in the scene; set `tube` (a LaunchTube) on the instance"},
        "base": f"{BASE[0]}x{BASE[1]}",
        "footprint_mm": [w, h],
        "stand_out_mm": round(stand_out, 1),
        "mount": "back on Z=0, centred; front +Z; the guard's hinge is along its top edge, +Y",
        "uses": USES,
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
