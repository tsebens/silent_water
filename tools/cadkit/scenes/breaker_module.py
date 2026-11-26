"""breaker_module: a chunky breaker for one power circuit (kit control, no base). Behaviour: BreakerSwitch.

Brief (#560, concept #534): a powder-coated grey plate (the life support's grey, role `interior_panel`), a chunky
toggle handle in its own GLB with its pivot axis (X) through the origin, a status lamp (the kit `indicator_lamp`,
its lens wired to the switch's `lamp` export) and a static recess for an engraved label plate. Mounts on a flat
face, at most 150 x 150 mm, standing out at most 60 mm (the handle at its extremes included).

The handle's GLB points along +Z at rest. `BreakerSwitch` pitches it about X by -30 deg for off, +30 deg for on,
0 for tripped and -75 deg for blown, so the handle hangs on a Hinge node turned 180 degrees about Z: on is then
toward +Y (up), and a blown breaker's handle falls toward -Y.
"""
import json
import math

from cadkit.solids import Solid, at, box, expect, expect_in_front, bbox_mm, export_solids_glb
from cadkit.library import entry, note, out_dir, res, write_entry
from cadkit.tscn import NodePath, Scene, Xform

SLUG, GROUP = "breaker_module", "kit"
USES: list[str] = ["indicator_lamp"]
MAX_FOOT, MAX_STAND_OUT, MAX_TRIS = 150.0, 60.0, 200
PLATE_W, PLATE_H, PLATE_T = 100.0, 150.0, 6.0
HINGE_Y, HINGE_Z = 0.0, PLATE_T + 7.0              # the handle's axis, in front of the plate
BLOCK_W, BLOCK_H, BLOCK_T = 44.0, 18.0, 7.0         # the hinge block the handle's barrel turns in
STEM_W, STEM_L = 12.0, 30.0
KNOB_W, KNOB_H, KNOB_L = 28.0, 16.0, 10.0
LAMP_Y = 58.0
RECESS_W, RECESS_H, RECESS_D, RECESS_Y = 60.0, 16.0, 1.5, -62.0
ANGLES_DEG = {"off": -30.0, "on": 30.0, "tripped": 0.0, "blown": -75.0}   # BreakerSwitch.handle_angles_deg


def handle_solid():
    stem = at(box(STEM_W, STEM_W, STEM_L + 4.0), z=-4.0)       # starts behind the axis, inside the block
    knob = at(box(KNOB_W, KNOB_H, KNOB_L), z=STEM_L)
    return stem + knob


def _extent(shape, angle_deg: float):
    """The handle's bounding box (in the hinge frame) pitched `angle_deg` about X, as BreakerSwitch does."""
    return bbox_mm(at(shape, rx=angle_deg))


def solids():
    lamp = entry("indicator_lamp")
    lamp_r = max(lamp["footprint_mm"]) / 2
    plate = box(PLATE_W, PLATE_H, PLATE_T)
    plate = plate - at(box(RECESS_W, RECESS_H, RECESS_D), y=RECESS_Y, z=PLATE_T - RECESS_D)
    block = at(box(BLOCK_W, BLOCK_H, BLOCK_T), y=HINGE_Y, z=PLATE_T)
    handle = handle_solid()
    expect(len(handle.solids()) == 1, "handle is one solid")
    lo_h, hi_h = bbox_mm(handle)
    expect(lo_h[1] < 0 < hi_h[1] and lo_h[2] < 0 < hi_h[2] and abs(lo_h[0] + hi_h[0]) < 0.01,
           "handle's X axis runs through the origin, inside its body")

    # Handle extremes in the module frame: the hinge turns 180 deg about Z, so Y is mirrored and X too.
    ymin, ymax, zmax = 1e9, -1e9, -1e9
    for name, a in ANGLES_DEG.items():
        lo, hi = _extent(handle, a)
        ymin, ymax, zmax = min(ymin, -hi[1]), max(ymax, -lo[1]), max(zmax, hi[2])
        expect(HINGE_Z + lo[2] >= PLATE_T - 0.01 or name == "blown", f"handle ({name}) clears the plate front")
    ymin, ymax = ymin + HINGE_Y, ymax + HINGE_Y
    stand_out = HINGE_Z + zmax
    footprint = (PLATE_W, PLATE_H)
    expect(footprint[0] <= MAX_FOOT and footprint[1] <= MAX_FOOT, f"footprint {footprint} within {MAX_FOOT} mm")
    expect(stand_out <= MAX_STAND_OUT, f"module stands {stand_out:.1f} mm out; limit {MAX_STAND_OUT}")
    expect(ymax < LAMP_Y - lamp_r - 2.0, f"handle's swing (to y={ymax:.1f}) clears the lamp")
    expect(LAMP_Y + lamp_r < PLATE_H / 2 - 2.0, "lamp inside the plate")
    expect(ymin > RECESS_Y + RECESS_H / 2 + 2.0, f"handle's swing (to y={ymin:.1f}) clears the label recess")
    expect(RECESS_Y - RECESS_H / 2 > -PLATE_H / 2 + 2.0 and RECESS_W < PLATE_W - 4.0, "recess inside the plate")
    expect(BLOCK_W / 2 < PLATE_W / 2 and STEM_W / 2 < BLOCK_H / 2, "stem leaves the hinge block at its middle")
    expect(len(plate.solids()) == 1, "plate is one solid")
    body = [Solid(plate, "interior_panel"), Solid(block, "interior_dark")]
    hs = [Solid(handle, "control_grey")]
    expect_in_front(body + [Solid(at(handle, y=HINGE_Y, z=HINGE_Z), "control_grey")], SLUG)
    return body, hs, stand_out, (ymin, ymax)


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, hs, stand_out, _ = solids()
    lamp = entry("indicator_lamp")
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "BreakerModuleBody")
    rh = export_solids_glb(hs, d / f"{SLUG}_handle.glb", "BreakerModuleHandle")
    tris = rb["triangles"] + rh["triangles"] + lamp["triangles"]
    expect(tris <= MAX_TRIS, f"{tris} triangles; the module's cap is {MAX_TRIS}")
    s = Scene("BreakerModule", script="res://src/interact/breaker_switch.gd")
    s.node("Body", instance=rb["glb"])
    s.node("Hinge", props={"transform": Xform.frame((-1, 0, 0), (0, -1, 0), (0, 0, 1),
                                                    (0, HINGE_Y / 1000, HINGE_Z / 1000))})
    s.node("Handle", parent="Hinge", instance=rh["glb"])
    s.node("IndicatorLamp", instance=lamp["scene"],
           props={"transform": Xform(origin=(0, LAMP_Y / 1000, PLATE_T / 1000))})
    s.set(".", handle=NodePath("Hinge/Handle"), lamp=NodePath("IndicatorLamp/Lens/IndicatorLampLens"))
    _review(d)
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "control",
        "summary": "Chunky breaker module for one power circuit: grey plate with a label-plate recess, a toggle "
                   "handle on a hinge block and a status lamp above it. A click switches the breaker, resets a "
                   "trip or asks for a replacement when blown.",
        "tags": ["breaker", "switch", "power", "circuit", "toggle", "lamp", "fuse"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "BreakerSwitch",
                      "values": "off (handle down, lamp dark), on (handle up, lamp ok), tripped (handle mid, lamp "
                                "warn), blown (handle limp, lamp alarm)",
                      "signal": "none: the state is read from the power system's breaker_<circuit> readout",
                      "wiring": "`handle` and `lamp` are set in the scene; set `circuit` on the instance"},
        "footprint_mm": [PLATE_W, PLATE_H],
        "stand_out_mm": round(stand_out, 2),
        "mount": "back on Z=0 on a flat face, centred; front +Z; on is toward +Y; the label recess is at the bottom",
        "set_on_instance": {"circuit": "PowerSystem.Circuit the breaker switches", "label": "name at the aiming point"},
        "uses": USES,
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}


def _review(d) -> None:
    """Review cameras: each breaker state's handle. The sheet renders the rest pose; `profile` shows the stand-out."""
    look = [0.0, 0.0, 0.02]
    cams = [
        {"name": "front", "pos": [0.14, 0.08, 0.45], "look_at": look, "fov": 30.0},
        {"name": "front_red", "pos": [0.14, 0.08, 0.45], "look_at": look, "fov": 30.0, "light": "red"},
        {"name": "profile", "pos": [0.6, 0.0, 0.03], "look_at": [0.0, 0.0, 0.03], "ortho": 0.22},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    for n in (".gdignore", "cameras.json"):
        note(review / n)
