"""hand_pump: the manual bilge pump's end of the console: a pump housing with a long lever on a pivot. Element.

Brief (#570, concept #530): a low housing on the mount face carries two pivot cheeks. Between them a lever hub turns
about X; a long shaft runs out along +Z (out of the mount face) and ends in a crossbar handle in the large-lever
colour (`lever`, sub_yellow). The lever is its own GLB, its pivot axis (X) through the origin, and swings up and
down in the YZ plane. Behaviour: HandPump (value 0 rests with the handle up, 1 is the bottom of the down stroke).
`stand_out_mm` is the furthest point of the sweep, so a parent can check the aisle.
"""
import math

import build123d as bd

from cadkit.solids import Solid, at, box, prism, expect, expect_in_front, bbox_mm, export_solids_glb
from cadkit.library import out_dir, quiet_noise, res, write_entry
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "hand_pump", "kit"
USES: list[str] = []
HOUSING_W, HOUSING_H, HOUSING_D = 160.0, 120.0, 60.0
CHEEK_T, CHEEK_GAP, CHEEK_H, CHEEK_TOP = 8.0, 36.0, 80.0, 104.0   # cheeks stand on the housing up to z = CHEEK_TOP
PIVOT_Z = 82.0
HUB_R, HUB_LEN = 14.0, CHEEK_GAP - 2.0
SHAFT_R, SHAFT_LEN = 9.0, 420.0          # from the pivot to the handle's centre
BAR_W, BAR_H, BAR_D = 110.0, 26.0, 26.0
SWING_DEG = 50.0                         # HandPump.swing_deg; value 0 is -25, value 1 is +25 about X
GRAB_MARGIN = 20.0
MAX_STAND_OUT = 600.0
BOTTOM = CHEEK_TOP - PIVOT_Z             # cheek top above the pivot


def lever_solid() -> bd.Shape:
    hub = bd.extrude(bd.Plane.YZ * bd.RegularPolygon(HUB_R, 8), amount=HUB_LEN / 2, both=True)
    shaft = at(prism(8, SHAFT_R, SHAFT_LEN))
    bar = at(box(BAR_W, BAR_H, BAR_D, chamfer_mm=4.0, base_z=False), z=SHAFT_LEN)
    lever = hub + shaft + bar
    expect(len(lever.solids()) == 1, "lever is one solid")
    return lever


def body_solids() -> list[Solid]:
    housing = box(HOUSING_W, HOUSING_H, HOUSING_D, chamfer_mm=4.0)
    cheeks = [at(box(CHEEK_T, CHEEK_H, CHEEK_TOP - HOUSING_D + 2.0, chamfer_mm=2.0),
                 x=sx * (CHEEK_GAP / 2 + CHEEK_T / 2), z=HOUSING_D - 2.0) for sx in (-1, 1)]
    pin = at(prism(8, 5.0, CHEEK_GAP + 2 * CHEEK_T + 6.0), x=-(CHEEK_GAP / 2 + CHEEK_T + 3.0), z=PIVOT_Z, ry=90)
    return [Solid(housing, "interior_panel"), Solid(cheeks[0] + cheeks[1], "interior_dark"), Solid(pin, "trim_black")]


def _swing(lever: bd.Shape, deg: float) -> bd.Shape:
    """The lever, in the housing's frame, with the pivot turned `deg` about X."""
    return at(at(lever, rx=deg), z=PIVOT_Z)


def sweep(lever: bd.Shape) -> list[tuple[float, tuple, tuple]]:
    lo, hi = -SWING_DEG / 2, SWING_DEG / 2
    steps = [lo + (hi - lo) * i / 50 for i in range(51)]
    return [(d, *bbox_mm(_swing(lever, d))) for d in steps]


def tip_mm(deg: float) -> tuple[float, float]:
    """(y, z) of the handle's centre at `deg` about X, in the housing's frame."""
    r = math.radians(deg)
    return -SHAFT_LEN * math.sin(r), PIVOT_Z + SHAFT_LEN * math.cos(r)


def stand_out(lever: bd.Shape) -> float:
    return max(max(b[1][2] for _, b in [(d, (lo, hi)) for d, lo, hi in sweep(lever)]), CHEEK_TOP)


def solids() -> tuple[list[Solid], list[Solid], dict]:
    body, lever = body_solids(), lever_solid()
    lo_d, hi_d = -SWING_DEG / 2, SWING_DEG / 2
    ends = {"up": _swing(lever, lo_d), "down": _swing(lever, hi_d)}
    up_y, _ = tip_mm(lo_d)
    dn_y, _ = tip_mm(hi_d)
    expect(up_y > 150.0 and dn_y < -150.0, f"handle rises and falls clear of the housing at the ends (up {up_y:.0f}, down {dn_y:.0f})")
    for name, s in ends.items():
        lo, hi = bbox_mm(s)
        expect(abs(abs(lo[0]) - abs(hi[0])) < 0.5 and hi[0] <= BAR_W / 2 + 0.5, f"lever stays on its axis plane, {name} end")
        expect(lo[2] > 0.0, f"lever stays in front of the mount face, {name} end")
    expect(bbox_mm(ends["down"])[0][2] > HOUSING_D, "lever at the bottom of the stroke stays clear of the housing")
    expect(bbox_mm(ends["up"])[0][2] > HOUSING_D, "lever at the top of the stroke stays clear of the housing")
    # The shaft does not touch the cheeks at the ends: it stays inside the gap.
    expect(SHAFT_R < CHEEK_GAP / 2 and HUB_LEN < CHEEK_GAP, "hub and shaft sit between the cheeks")
    expect(SHAFT_LEN > 3 * HOUSING_W / 2 * 0.8, "lever reads as long against the housing")
    so = stand_out(lever)
    expect(so <= MAX_STAND_OUT, f"stand-out {so:.1f} within {MAX_STAND_OUT}")
    mid = bbox_mm(_swing(lever, 0.0))
    expect(so >= mid[1][2] - 0.01, "stand-out covers the lever at mid sweep")
    expect(so >= max(bbox_mm(e)[1][2] for e in ends.values()) - 0.01, "stand-out covers both ends of the sweep")
    placed = [Solid(_swing(lever, d), "lever") for d in (lo_d, hi_d)]
    expect_in_front(body + placed, SLUG)
    allb = [bbox_mm(s.shape) for s in body] + [bbox_mm(e) for e in ends.values()]
    foot = (max(b[1][0] for b in allb) - min(b[0][0] for b in allb), max(b[1][1] for b in allb) - min(b[0][1] for b in allb))
    return body, [Solid(lever, "lever")], {"stand_out": so, "footprint": foot, "up": tip_mm(lo_d), "down": tip_mm(hi_d),
                                           "y": (min(b[0][1] for b in allb), max(b[1][1] for b in allb))}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, lever, m = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "HandPumpBody")
    rl = export_solids_glb(lever, d / f"{SLUG}_lever.glb", "HandPumpLever")
    s = Scene("HandPump", script="res://src/interact/hand_pump.gd")
    s.set(".", noise_profile=quiet_noise(s, 0.0, 0.0), pivot=NodePath("Pivot"), swing_deg=SWING_DEG)
    s.node("Body", instance=rb["glb"])
    s.node("Pivot", props={"transform": Xform(origin=(0, 0, PIVOT_Z / 1000))})
    s.node("Lever", parent="Pivot", instance=rl["glb"])
    so = m["stand_out"] / 1000
    y0, y1 = m["y"]
    fw, fh = m["footprint"]
    grab_box(s, ".", ((fw + 2 * GRAB_MARGIN) / 1000, (fh + 2 * GRAB_MARGIN) / 1000, so),
             (0, (y0 + y1) / 2000, so / 2))
    s.write(d / f"{SLUG}.tscn")
    tris = rb["triangles"] + rl["triangles"]
    expect(tris <= 1500, f"triangles {tris} within 1500")
    write_entry(GROUP, SLUG, {
        "kind": "element",
        "summary": "Manual bilge pump: a housing with a long yellow lever that swings up (rest) and down (stroke) about X. "
                   "HandPump behaviour; hold to pump. stand_out_mm is the furthest point of the sweep.",
        "tags": ["pump", "hand pump", "manual", "bilge", "lever", "engineering"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "HandPump", "values": "0 rest (handle up) .. 1 bottom of the stroke (handle down)",
                      "wiring": "leaks export or the leak_system group (LeakSystem.manual_bail)"},
        "footprint_mm": [round(fw, 1), round(fh, 1)],
        "stand_out_mm": round(m["stand_out"], 2),
        "handle_tip_mm": {"up_yz": [round(v, 2) for v in m["up"]], "down_yz": [round(v, 2) for v in m["down"]]},
        "mount": "back on Z=0, centred; front +Z; the lever runs out along +Z and swings in the YZ plane (up is +Y)",
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
