"""prime_lever: a long-armed lever with an orange grip on a small pivot block, for the decoy loader's prime action.

Brief (#752, concept #746): a flat grey arm on a hub between two cheeks of a compact block, a cross grip in the
`control_interface` colour at its end. Pulled down it stays down while primed. The arm runs out along +Z from a pivot
about X and swings in the YZ plane. Behaviour: SwitchLever, whose off end (value min) holds the arm up and whose on end
(value max) holds it down; that needs a negative `swing_deg` (the Lever maps min to +swing/2, which tips the tip down).
The arm is modelled with its rest direction lifted ARM_LIFT_DEG above the mount axis, so the throw is not symmetric:
up is a raised rest, down is a pull to just below horizontal. Own GLB for the arm, pivot axis through the origin.
`stand_out_mm` is the furthest point of the sweep.
"""
import math

import build123d as bd

from cadkit.solids import Solid, at, box, prism, expect, expect_in_front, bbox_mm, export_solids_glb
from cadkit.library import TRIANGLE_BUDGET, out_dir, quiet_noise, res, write_entry
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "prime_lever", "kit"
USES: list[str] = []
BLOCK_W, BLOCK_H, BLOCK_D = 84.0, 70.0, 40.0            # the pivot block on the mount face
CHEEK_T, CHEEK_GAP, CHEEK_TOP = 10.0, 22.0, 84.0         # cheeks stand on the block up to z = CHEEK_TOP
PIVOT_Z = 62.0
HUB_R, HUB_LEN = 13.0, CHEEK_GAP - 2.0
ARM_LEN, ARM_W, ARM_T = 210.0, 22.0, 12.0                # pivot to the grip's centre; the arm is wide in Y, thin in X
GRIP_R, GRIP_LEN = 9.0, 56.0                             # cross grip, along X
SWING_DEG = 80.0                                         # total throw
ARM_LIFT_DEG = 10.0                                      # the arm's mid-throw direction above the mount axis (+Z)
UP_DEG, DOWN_DEG = ARM_LIFT_DEG + SWING_DEG / 2, ARM_LIFT_DEG - SWING_DEG / 2   # elevation of the arm at the two ends
GRAB_MARGIN = 20.0
MAX_STAND_OUT = 450.0                                    # the decoy loader stands 0.45 m out closed


def grip_solid() -> bd.Shape:
    grip = at(prism(8, GRIP_R, GRIP_LEN, chamfer_top=2.0), ry=90, x=-GRIP_LEN / 2, z=ARM_LEN)
    return at(grip, rx=-ARM_LIFT_DEG)


def arm_only() -> bd.Shape:
    hub = bd.extrude(bd.Plane.YZ * bd.RegularPolygon(HUB_R, 8), amount=HUB_LEN / 2, both=True)
    bar = at(box(ARM_T, ARM_W, ARM_LEN + GRIP_R, chamfer_mm=2.0))
    return at(hub + bar, rx=-ARM_LIFT_DEG)


def body_solids() -> list[Solid]:
    block = box(BLOCK_W, BLOCK_H, BLOCK_D, chamfer_mm=3.0)
    cheeks = [at(box(CHEEK_T, BLOCK_H - 10.0, CHEEK_TOP - BLOCK_D + 2.0, chamfer_mm=2.0),
                 x=sx * (CHEEK_GAP / 2 + CHEEK_T / 2), z=BLOCK_D - 2.0) for sx in (-1, 1)]
    pin = at(prism(8, 5.0, CHEEK_GAP + 2 * CHEEK_T + 6.0), x=-(CHEEK_GAP / 2 + CHEEK_T + 3.0), z=PIVOT_Z, ry=90)
    return [Solid(block, "interior_panel"), Solid(cheeks[0] + cheeks[1], "interior_dark"), Solid(pin, "trim_black")]


def _swing(shape: bd.Shape, deg: float) -> bd.Shape:
    """A part of the arm, in the block's frame, with the pivot turned `deg` about X (positive tips the arm down)."""
    return at(at(shape, rx=deg), z=PIVOT_Z)


def tip_mm(elev_deg: float) -> tuple[float, float]:
    """(y, z) of the grip's centre at an arm elevation, in the block's frame."""
    r = math.radians(elev_deg)
    return ARM_LEN * math.sin(r), PIVOT_Z + ARM_LEN * math.cos(r)


def solids() -> tuple[list[Solid], list[Solid], dict]:
    body = body_solids()
    arm, grip, bar = arm_only() + grip_solid(), grip_solid(), arm_only()
    half = SWING_DEG / 2
    # Pivot angles: the Lever turns by -/+half about X; up is the off end (pivot -half), down the on end (+half).
    ends = {"up": -half, "down": half}
    expect(len(bar.solids()) == 1 and len(grip.solids()) == 1, "arm bar and grip are each one solid")
    # arm length
    expect(ARM_LEN >= 2.0 * BLOCK_W, f"arm reads as long against the block ({ARM_LEN:g} mm vs a {BLOCK_W:g} mm block)")
    expect(ARM_LEN <= MAX_STAND_OUT - PIVOT_Z, "arm short enough to stay inside the stand-out limit")
    # grip size
    glo, ghi = bbox_mm(grip)
    expect(abs((ghi[0] - glo[0]) - GRIP_LEN) < 0.5, f"grip is {GRIP_LEN:g} mm across")
    expect(GRIP_R * 2 >= 14.0 and GRIP_LEN >= 40.0, "grip is big enough to take a gloved hand")
    expect(GRIP_LEN > ARM_T * 3, "grip stands well wider than the arm")
    expect(GRIP_LEN / 2 > CHEEK_GAP / 2 + CHEEK_T, "grip is wider than the pivot block's cheeks")
    # swing: arm elevation at the ends and clearance of the block
    up_y, _ = tip_mm(UP_DEG)
    dn_y, _ = tip_mm(DOWN_DEG)
    expect(UP_DEG > 40.0, f"the up end raises the arm well above horizontal ({UP_DEG:g} deg)")
    expect(-45.0 < DOWN_DEG < 0.0, f"the down end pulls the arm to just below horizontal ({DOWN_DEG:g} deg)")
    expect(up_y > 100.0 and dn_y < -80.0, f"grip rises and falls clear of the block (up {up_y:.0f}, down {dn_y:.0f})")
    blocksolid = body[0].shape + body[1].shape
    for name, deg in ends.items():
        for part, what in ((bar, "arm"), (grip, "grip")):
            placed = _swing(part, deg)
            lo, hi = bbox_mm(placed)
            expect(lo[2] > 0.0, f"{what} stays in front of the mount face, {name} end")
            expect((placed & blocksolid).volume < 1e-3, f"{what} clear of the block, {name} end")
        expect(abs(bbox_mm(_swing(arm, deg))[1][0]) <= GRIP_LEN / 2 + 0.5, f"arm stays on its axis plane, {name} end")
    # hub and bar sit between the cheeks
    expect(ARM_T < CHEEK_GAP and HUB_LEN < CHEEK_GAP, "arm and hub sit between the cheeks")
    # stand-out is the furthest point of the sweep
    sweep = [-half + 2 * half * i / 40 for i in range(41)]
    boxes = [bbox_mm(_swing(arm, d)) for d in sweep] + [bbox_mm(s.shape) for s in body]
    so = max(b[1][2] for b in boxes)
    expect(so <= MAX_STAND_OUT, f"stand-out {so:.1f} within {MAX_STAND_OUT}")
    placed = [Solid(_swing(arm, d), "lever") for d in ends.values()]
    expect_in_front(body + placed, SLUG)
    y0 = min(b[0][1] for b in boxes)
    y1 = max(b[1][1] for b in boxes)
    fw = max(max(b[1][0] for b in boxes) - min(b[0][0] for b in boxes), BLOCK_W)
    return body, [Solid(bar, "control_grey"), Solid(grip, "control_interface")], {
        "stand_out": so, "footprint": (fw, y1 - y0), "y": (y0, y1), "up": tip_mm(UP_DEG), "down": tip_mm(DOWN_DEG)}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, arm, m = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "PrimeLeverBody")
    ra = export_solids_glb(arm, d / f"{SLUG}_arm.glb", "PrimeLeverArm")
    s = Scene("PrimeLever", script="res://src/interact/switch_lever.gd")
    # negative swing: value min (off) holds the arm up, value max (on, primed) holds it down
    s.set(".", swing_deg=-SWING_DEG, noise_profile=quiet_noise(s, 0.25, 2.0), pivot=NodePath("Pivot"))
    s.node("Body", instance=rb["glb"])
    s.node("Pivot", props={"transform": Xform(origin=(0, 0, PIVOT_Z / 1000))})
    s.node("Arm", parent="Pivot", instance=ra["glb"])
    so = m["stand_out"] / 1000
    y0, y1 = m["y"]
    fw, fh = m["footprint"]
    grab_box(s, ".", ((fw + 2 * GRAB_MARGIN) / 1000, (fh + 2 * GRAB_MARGIN) / 1000, so),
             (0, (y0 + y1) / 2000, so / 2))
    s.write(d / f"{SLUG}.tscn")
    tris = rb["triangles"] + ra["triangles"]
    expect(tris <= TRIANGLE_BUDGET[GROUP], f"{tris} triangles; kit budget {TRIANGLE_BUDGET[GROUP]}")
    write_entry(GROUP, SLUG, {
        "kind": "control",
        "summary": "Prime lever: a long flat grey arm with an orange cross grip on a small pivot block, swinging about X. "
                   "SwitchLever: pull it down to set on (primed) and it stays down; click from on lifts it back to off.",
        "tags": ["lever", "prime", "lock", "pull-down", "decoy", "loader", "switch"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "SwitchLever", "values": "0 off (arm up), 1 on / primed (arm down, stays down)",
                      "signal": "value_changed"},
        "footprint_mm": [round(fw, 1), round(fh, 1)],
        "stand_out_mm": round(m["stand_out"], 2),
        "handle_tip_mm": {"up_yz": [round(v, 2) for v in m["up"]], "down_yz": [round(v, 2) for v in m["down"]]},
        "swing_envelope": {"swing_deg": SWING_DEG, "arm_elevation_deg": [round(DOWN_DEG, 1), round(UP_DEG, 1)],
                           "arm_length_mm": ARM_LEN, "note": "scene swing_deg is negative so that on is down"},
        "mount": "back on Z=0, centred; front +Z; the arm runs out along +Z and swings in the YZ plane (up is +Y)",
        "set_on_instance": {"label": "name at the aiming point"},
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
