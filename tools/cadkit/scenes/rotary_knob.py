"""rotary_knob: a static, decorative rotary knob (no script, no grab box). Element: mounts on a plate or panel.

Brief: a grippable-looking light-grey knob on a black collar, with a pointer ridge on top. The knob head is its own
GLB modelled in its own frame with its turning axis (Z) through the origin, under a `Pivot` node, so a later
placement arc can rotate it. Rotation is driven by mouse and keyboard there, not by a script on this scene.
"""
from cadkit.solids import Solid, at, box, prism, expect, expect_in_front, bbox_mm, export_solids_glb
from cadkit.library import out_dir, res, write_entry
from cadkit.tscn import Scene, Xform

SLUG, GROUP = "rotary_knob", "kit"
USES: list[str] = []
COLLAR_R, COLLAR_H = 20.0, 4.0
KNOB_R, KNOB_H = 16.0, 18.0
KNOB_SIDES = 12
POINTER_W, POINTER_L, POINTER_H = 3.0, 12.0, 1.5
KNOB_Z = COLLAR_H
MAX_STAND_OUT = 30.0


def solids() -> tuple[list[Solid], list[Solid]]:
    collar = prism(16, COLLAR_R, COLLAR_H)
    # The head in its own frame: its base sits on Z=0, axis through the origin.
    head = prism(KNOB_SIDES, KNOB_R, KNOB_H, chamfer_top=2.5)
    pointer = at(box(POINTER_W, POINTER_L, POINTER_H), 0, KNOB_R - POINTER_L / 2 - 2.0, KNOB_H - 0.5)
    lo, hi = bbox_mm(head)
    expect(abs(lo[0] + hi[0]) < 0.01 and abs(lo[1] + hi[1]) < 0.01, "knob head centred on its axis")
    expect(abs(lo[2]) < 0.01, "knob head base at the origin plane")
    expect(KNOB_R < COLLAR_R, "knob head sits inside the collar")
    plo, phi = bbox_mm(pointer)
    expect(phi[1] <= hi[1] and plo[1] >= 0.0, "pointer on the knob top, pointing out along +Y")
    expect(KNOB_Z + KNOB_H + POINTER_H - 0.5 <= MAX_STAND_OUT, f"knob stands out within {MAX_STAND_OUT} mm")
    body = [Solid(collar, "trim_black")]
    cap = [Solid(head, "control_grey"), Solid(pointer, "trim_black")]
    expect_in_front(body + [Solid(at(head, z=KNOB_Z), "control_grey")], SLUG)
    return body, cap


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, cap = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "RotaryKnobBody")
    rc = export_solids_glb(cap, d / f"{SLUG}_head.glb", "RotaryKnobHead")
    s = Scene("RotaryKnob")  # static: no script, no grab box
    s.node("Body", instance=rb["glb"])
    s.node("Pivot", props={"transform": Xform(origin=(0, 0, KNOB_Z / 1000))})
    s.node("Head", parent="Pivot", instance=rc["glb"])
    s.write(d / f"{SLUG}.tscn")
    tris = rb["triangles"] + rc["triangles"]
    stand = KNOB_Z + KNOB_H + POINTER_H - 0.5
    write_entry(GROUP, SLUG, {
        "kind": "element",
        "summary": "Static decorative rotary knob: light grey 12-sided head with a pointer ridge on a black collar. "
                   "No script and no grab box; turn the Pivot node from outside.",
        "tags": ["knob", "rotary", "dial", "decorative", "static"],
        "scene": res(d / f"{SLUG}.tscn"),
        "footprint_mm": [2 * COLLAR_R, 2 * COLLAR_R],
        "stand_out_mm": stand,
        "mount": "back on Z=0 (on a plate front), centred; the Pivot node turns about Z",
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
