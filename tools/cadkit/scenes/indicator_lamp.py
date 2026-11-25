"""indicator_lamp: a bezel and a lens that lights. Element: mounts on a plate or panel. Behaviour: IndicatorLamp.

The lens is its own GLB (one surface, an `indicator_*` palette role) so the script can switch its emission.
"""
from cadkit.solids import Solid, prism, at, expect, expect_in_front, bbox_mm, export_solids_glb
from cadkit.library import out_dir, res, write_entry
from cadkit.tscn import NodePath, Scene, Xform

SLUG, GROUP = "indicator_lamp", "kit"
USES: list[str] = []
BEZEL_R, BEZEL_IN_R, BEZEL_H = 10.0, 7.0, 3.0
LENS_R, LENS_H, LENS_Z = 6.5, 4.0, 1.0
LENS_ROLE = "indicator_ok"
MAX_STAND_OUT = 8.0


def solids() -> tuple[list[Solid], list[Solid]]:
    bezel = prism(8, BEZEL_R, BEZEL_H, chamfer_top=0.8) - prism(8, BEZEL_IN_R, BEZEL_H)
    lens = at(prism(8, LENS_R, LENS_H, chamfer_top=1.2), z=LENS_Z)
    expect(len(bezel.solids()) == 1, "bezel is one solid")
    expect(LENS_R < BEZEL_IN_R, "lens fits inside the bezel")
    _, hi = bbox_mm(lens)
    expect(hi[2] > BEZEL_H, "lens stands proud of the bezel so it reads from the side")
    expect(hi[2] <= MAX_STAND_OUT, f"lamp stands {hi[2]:.1f} mm out; limit {MAX_STAND_OUT}")
    body, lens_s = [Solid(bezel, "trim_black")], [Solid(prism(8, LENS_R, LENS_H, chamfer_top=1.2), LENS_ROLE)]
    expect_in_front(body + [Solid(lens, LENS_ROLE)], SLUG)
    return body, lens_s


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, lens = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_bezel.glb", "IndicatorLampBezel")
    rl = export_solids_glb(lens, d / f"{SLUG}_lens.glb", "IndicatorLampLens")
    s = Scene("IndicatorLamp", script="res://src/interact/indicator_lamp.gd")
    s.node("Bezel", instance=rb["glb"])
    s.node("Lens", instance=rl["glb"], props={"transform": Xform(origin=(0, 0, LENS_Z / 1000))})
    s.set(".", lamp=NodePath("Lens/IndicatorLampLens"))
    s.write(d / f"{SLUG}.tscn")
    tris = rb["triangles"] + rl["triangles"]
    write_entry(GROUP, SLUG, {
        "kind": "display",
        "summary": "Indicator lamp: black octagonal bezel and a lens in the indicator_ok palette role; "
                   "IndicatorLamp lights it from a bool. Mounts on a plate, no base.",
        "tags": ["lamp", "indicator", "light", "status"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "IndicatorLamp", "values": "lit bool", "signal": "lit_changed",
                      "wire": "set_lit(bool) or bind(source, signal)"},
        "footprint_mm": [2 * BEZEL_R, 2 * BEZEL_R],
        "stand_out_mm": LENS_Z + LENS_H,
        "mount": "back on Z=0 (on a plate front), centred; faces +Z",
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
