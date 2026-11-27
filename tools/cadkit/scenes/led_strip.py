"""led_strip: a thin, flat LED bar, the flat alternative to indicator_lamp. Element: mounts on a plate or panel.

The lens is its own GLB (one surface, an `indicator_*` palette role) under an `IndicatorLamp` node, so the existing
script lights it. Length is an instance setting: scale X on the instance (no script, no rebuild); the reference
length is REF_LEN. `led_strip_warn` and `led_strip_alarm` reuse `build_strip` with their own role. `loop_lens`
builds a rectangular loop lens (the bat toggle's ring around its bay).
"""
import json

from cadkit.solids import Solid, at, box, bbox_mm, expect, expect_in_front, export_solids_glb
from cadkit.library import note, out_dir, res, write_entry

SLUG, GROUP = "led_strip", "kit"
USES: list[str] = []
LENS_ROLE = "indicator_ok"
REF_LEN, WIDTH, HEIGHT, CHAMFER = 40.0, 3.0, 1.2, 0.4
LEN_MIN, LEN_MAX = 10.0, 120.0       # instance length limits, mm (scale X = length / REF_LEN)
MAX_STAND_OUT = 3.0
BUDGET = 1500


def strip_lens(length: float = REF_LEN, width: float = WIDTH, height: float = HEIGHT):
    """The bar: length (X) by width (Y), standing `height` out of the mount face, edges chamfered."""
    return box(length, width, height, chamfer_mm=CHAMFER)


def loop_lens(inner_w: float, inner_h: float, bar: float = WIDTH, height: float = HEIGHT, gap: float = 0.0):
    """A rectangular loop lens round a bay of inner_w x inner_h (mm), `bar` wide, `height` proud of the face.

    `gap` is clearance from the bay edge to the loop's inner edge."""
    iw, ih = inner_w + 2 * gap, inner_h + 2 * gap
    outer = box(iw + 2 * bar, ih + 2 * bar, height, chamfer_mm=CHAMFER)
    ring = outer - box(iw, ih, height)
    expect(len(ring.solids()) == 1, "loop is one solid")
    lo, hi = bbox_mm(ring)
    expect(lo[0] <= -inner_w / 2 and hi[0] >= inner_w / 2 and lo[1] <= -inner_h / 2 and hi[1] >= inner_h / 2,
           "loop extends beyond the inner rectangle on every side")
    hole = box(inner_w, inner_h, height + 2.0, base_z=True)
    expect((ring & hole).volume < 1e-6, f"loop encloses the {inner_w} x {inner_h} mm inner rectangle without touching it")
    return ring


def solids(role: str) -> list[Solid]:
    lens = strip_lens()
    lo, hi = bbox_mm(lens)
    expect(abs((hi[0] - lo[0]) - REF_LEN) < 0.01 and abs((hi[1] - lo[1]) - WIDTH) < 0.01,
           f"footprint {hi[0] - lo[0]:.2f} x {hi[1] - lo[1]:.2f} mm at the {REF_LEN} mm reference length")
    expect(abs(lo[2]) < 0.01 and hi[2] <= HEIGHT + 0.01, f"flat: stands {hi[2]:.2f} mm out")
    expect(hi[2] <= MAX_STAND_OUT, f"stands {hi[2]:.1f} mm out; limit {MAX_STAND_OUT}")
    expect(WIDTH < 5.0, "a bar, not a pad: narrower than 5 mm")
    loop_lens(30.0, 20.0)         # runs the helper's own checks on a sample bay
    out = [Solid(lens, role)]
    expect_in_front(out, SLUG)
    return out


def _review(d) -> None:
    look = [0.0, 0.0, 0.0]
    # The sheet renderer lights only switch scenes ("on" drives host_set_value), so the lamp is shown unlit; the unit
    # test covers the lit state.
    cams = [
        {"name": "unlit", "pos": [0.04, 0.03, 0.09], "look_at": look, "fov": 30.0},
        {"name": "unlit_red", "pos": [0.04, 0.03, 0.09], "look_at": look, "fov": 30.0, "light": "red"},
        {"name": "profile", "pos": [0.0, 0.3, 0.0012], "look_at": [0.0, 0.0, 0.0012], "ortho": 0.06},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    for n in (".gdignore", "cameras.json"):
        note(review / n)


def build_strip(slug: str, role: str, uses: list[str], colour: str, meaning: str) -> dict:
    from cadkit.tscn import NodePath, Scene
    d = out_dir(GROUP, slug)
    rl = export_solids_glb(solids(role), d / f"{slug}_lens.glb", "LedStripLens")
    expect(rl["triangles"] <= BUDGET, f"{rl['triangles']} triangles; kit budget {BUDGET}")
    s = Scene("IndicatorLamp", script="res://src/interact/indicator_lamp.gd")
    s.node("Lens", instance=rl["glb"])
    s.set(".", lamp=NodePath("Lens/LedStripLens"))
    s.write(d / f"{slug}.tscn")
    _review(d)
    write_entry(GROUP, slug, {
        "kind": "display",
        "summary": f"LED strip: a thin flat bar lens in the {role} palette role ({colour}); {meaning}. IndicatorLamp "
                   "lights it from a bool, exactly as the round indicator_lamp does. Length is set on the instance. "
                   "Mounts on a plate, no base.",
        "tags": ["led", "strip", "bar", "lamp", "indicator", "light", "status"],
        "scene": res(d / f"{slug}.tscn"),
        "behaviour": {"script": "IndicatorLamp", "values": "lit bool", "signal": "lit_changed",
                      "wire": "set_lit(bool) or bind(source, signal)"},
        "footprint_mm": [REF_LEN, WIDTH],
        "stand_out_mm": HEIGHT,
        "mount": "back on Z=0 (on a plate front), centred; faces +Z; runs along X (turn the node to run along Y)",
        "set_on_instance": {
            "scale.x": f"length = {REF_LEN:g} mm x scale.x; limits {LEN_MIN:g} to {LEN_MAX:g} mm "
                       f"(scale.x {LEN_MIN / REF_LEN:g} to {LEN_MAX / REF_LEN:g}); keep scale.y and scale.z at 1",
        },
        "uses": uses,
        "triangles": rl["triangles"],
    })
    return {"slug": slug, "triangles": rl["triangles"]}


def build() -> dict:
    return build_strip(SLUG, LENS_ROLE, USES, "green", "on, safe, friendly")
