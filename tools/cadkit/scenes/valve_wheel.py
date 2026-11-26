"""valve_wheel: a handwheel on a heavy valve body, mounted on a pipe run. Element: mounts on a plate or hull wall.

Brief: a horizontal pipe run (along X) rests on the mount face; a boxy valve body sits on it with a bonnet and a stem
rising along +Z. The handwheel is its own GLB modelled in its own frame, its turning axis (Z) through the origin, and
sits at the top of the stem. Behaviour: Valve (circle the mouse; `get_normalized()` drives the wheel). Orange wheel
(interaction), grey body, black flanges and stem. The label is set per instance.
"""
import math

import build123d as bd

from cadkit.solids import Solid, at, box, prism, expect, expect_in_front, bbox_mm, export_solids_glb
from cadkit.library import out_dir, quiet_noise, res, write_entry
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "valve_wheel", "kit"
USES: list[str] = []
PIPE_R, PIPE_LEN = 28.0, 200.0
FLANGE_R, FLANGE_T = 36.0, 8.0
BODY_W, BODY_D, BODY_H = 90.0, 80.0, 76.0     # X along the pipe, Y across, Z up
BONNET_R, BONNET_H = 24.0, 24.0
STEM_R, STEM_TOP = 5.0, 128.0
WHEEL_Z = 108.0                                # the wheel's base plane above the mount face
RIM_R, RIM_IN_R, RIM_H = 60.0, 53.0, 9.0
HUB_R, HUB_H = 13.0, 20.0
SPOKE_W, SPOKE_H = 7.0, 6.0
SPINNER_R, SPINNER_H = 3.5, 22.0
TURNS = 3.0                                    # Valve.turns_full_range default
GRAB_MARGIN = 6.0                              # grab box beyond the rim, each side
MAX_STAND_OUT = 150.0
FOOTPRINT = (PIPE_LEN, 2 * RIM_R)


def wheel_solids() -> list[Solid]:
    rim = prism(16, RIM_R, RIM_H) - prism(16, RIM_IN_R, RIM_H)
    spokes = [at(box(2 * (RIM_IN_R + 2), SPOKE_W, SPOKE_H), z=1.5, rz=a) for a in (0.0, 90.0)]
    hub = prism(12, HUB_R, HUB_H, chamfer_top=2.0)
    spinner = at(prism(8, SPINNER_R, SPINNER_H, chamfer_top=1.5), y=(RIM_R + RIM_IN_R) / 2)
    wheel = rim + hub + spinner
    for s in spokes:
        wheel = wheel + s
    expect(len(wheel.solids()) == 1, "wheel is one solid")
    lo, hi = bbox_mm(wheel)
    expect(abs(lo[0] + hi[0]) < 1.0 and abs(lo[2]) < 0.01, "wheel centred on its axis, base on the origin plane")
    return [Solid(wheel, "control_interface")]


def body_solids() -> list[Solid]:
    pipe = at(prism(16, PIPE_R, PIPE_LEN), x=-PIPE_LEN / 2, z=PIPE_R, ry=90)
    flanges = [at(prism(16, FLANGE_R, FLANGE_T), x=sx * (PIPE_LEN / 2 - 30) - FLANGE_T / 2, z=FLANGE_R, ry=90)
               for sx in (-1, 1)]
    body = box(BODY_W, BODY_D, BODY_H, chamfer_mm=4.0)
    bonnet = at(prism(8, BONNET_R, BONNET_H), z=BODY_H)
    stem = at(prism(8, STEM_R, STEM_TOP - BODY_H - BONNET_H + 2), z=BODY_H + BONNET_H - 2)
    return [Solid(pipe, "infra_metal"), Solid(flanges[0] + flanges[1], "trim_black"),
            Solid(body, "interior_panel"), Solid(bonnet, "interior_panel"), Solid(stem, "trim_black")]


def solids() -> tuple[list[Solid], list[Solid]]:
    body, wheel = body_solids(), wheel_solids()
    w = wheel[0].shape
    placed = at(w, z=WHEEL_Z)
    # Footprint and stand-out of the whole part.
    allb = [bbox_mm(s.shape) for s in body] + [bbox_mm(placed)]
    x0, x1 = min(b[0][0] for b in allb), max(b[1][0] for b in allb)
    y0, y1 = min(b[0][1] for b in allb), max(b[1][1] for b in allb)
    z1 = max(b[1][2] for b in allb)
    expect(x1 - x0 <= FOOTPRINT[0] + 0.1 and y1 - y0 <= FOOTPRINT[1] + 0.1, f"fits the stated footprint {FOOTPRINT}")
    expect(z1 <= MAX_STAND_OUT, f"stands out within {MAX_STAND_OUT} mm (is {z1:.1f})")
    expect(z1 <= stand_out() + 0.01, "stand-out figure covers the tallest point")
    expect(WHEEL_Z > BODY_H + BONNET_H - 2, "wheel clears the bonnet")
    expect(WHEEL_Z < STEM_TOP, "stem passes through the wheel hub")
    expect(RIM_R > BODY_D / 2 - 10, "wheel reads larger than the body")
    # The wheel at both ends of its turn (Valve turns it by -TURNS * 360 degrees about Z).
    half = RIM_R + GRAB_MARGIN
    for deg in (0.0, -TURNS * 360.0):
        lo, hi = bbox_mm(at(w, rz=deg))
        reach = max(abs(lo[0]), abs(hi[0]), abs(lo[1]), abs(hi[1]))
        expect(reach <= RIM_R + 0.5, f"wheel inside its swept disc at {deg:.0f} degrees")
        expect(max(abs(lo[0]), abs(hi[0]), abs(lo[1]), abs(hi[1])) <= half, f"grab box clears the wheel rim at {deg:.0f} degrees")
    expect(bbox_mm(w)[1][2] - 0 + WHEEL_Z <= stand_out() + 0.01, "grab box height covers the wheel top")
    expect_in_front(body + [Solid(placed, "control_interface")], SLUG)
    return body, wheel


def stand_out() -> float:
    return WHEEL_Z + max(HUB_H, RIM_H, SPINNER_H)


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, wheel = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "ValveWheelBody")
    rw = export_solids_glb(wheel, d / f"{SLUG}_wheel.glb", "ValveWheelWheel")
    s = Scene("ValveWheel", script="res://src/interact/valve.gd")
    s.set(".", noise_profile=quiet_noise(s, 0.1, 1.0), wheel=NodePath("Wheel"), turns_full_range=TURNS)
    s.node("Body", instance=rb["glb"])
    s.node("Wheel", instance=rw["glb"], props={"transform": Xform(origin=(0, 0, WHEEL_Z / 1000))})
    so = stand_out() / 1000
    side = 2 * (RIM_R + GRAB_MARGIN) / 1000
    grab_box(s, ".", (side, side, so), (0, 0, so / 2))
    s.write(d / f"{SLUG}.tscn")
    tris = rb["triangles"] + rw["triangles"]
    write_entry(GROUP, SLUG, {
        "kind": "element",
        "summary": "Handwheel on a heavy valve body on a short pipe run; the orange wheel is its own GLB and turns about Z "
                   "(3 turns, clockwise opens). Valve behaviour: circle the mouse. Label set per instance.",
        "tags": ["valve", "wheel", "handwheel", "pipe", "ballast", "flood", "blow"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "Valve", "values": "0 closed .. 1 open", "signal": "value_changed", "wiring": "bind to SubController flood_valve / blow_valve"},
        "footprint_mm": [FOOTPRINT[0], FOOTPRINT[1]],
        "stand_out_mm": stand_out(),
        "mount": "back on Z=0 (the pipe rests on the wall), centred; the pipe runs along X; the wheel turns about Z",
        "set_on_instance": {"label": "FLOOD or BLOW", "turns_full_range": "full turns, min to max"},
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
