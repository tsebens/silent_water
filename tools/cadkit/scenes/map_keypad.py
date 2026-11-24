"""map_keypad: four map keys (zoom in, zoom out, rotate left, rotate right) on a 2x2 base.

A composite control: it reuses push_button four times and adds only a base and black label plates (shapes only,
no legible text, per the art direction). It has no behaviour of its own; the station wires its keys by name.
"""
from cadkit.solids import Solid, at, box, expect, export_solids_glb
from cadkit.library import PLATE_T_MM, base_glb, base_size_mm, entry, out_dir, res, scene_path, write_entry, scene_module
from cadkit.tscn import Scene, Xform

SLUG, GROUP = "map_keypad", "kit"
USES: list[str] = ["control_base", "push_button"]
BASE = (2, 2)
KEYS = {"ZoomIn": ("zoom in", -26, 22), "ZoomOut": ("zoom out", -26, -22),
        "RotateLeft": ("rotate left", 26, 22), "RotateRight": ("rotate right", 26, -22)}
PLATE_W, PLATE_H, PLATE_DY = 26.0, 6.0, -17.0


def solids() -> list[Solid]:
    btn = entry("push_button")
    r = btn["footprint_mm"][0] / 2
    w, h = base_size_mm(*BASE)
    plates = [at(box(PLATE_W, PLATE_H, 1.0), x, y + PLATE_DY, PLATE_T_MM) for _, x, y in KEYS.values()]
    for name, (_, x, y) in KEYS.items():
        expect(abs(x) + r < w / 2 and abs(y) + r < h / 2, f"{name} inside the base")
        for bx, by in scene_module("control_base").bolt_positions(*BASE):
            expect(((x - bx) ** 2 + (y - by) ** 2) ** 0.5 > r + 3.5 + 1, f"{name} clear of bolt {bx},{by}")
        expect(abs(PLATE_DY) - PLATE_H / 2 > r, f"{name}'s label plate clear of the key")
    keys = list(KEYS.values())
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            dx, dy = keys[i][1] - keys[j][1], keys[i][2] - keys[j][2]
            expect((dx * dx + dy * dy) ** 0.5 >= 2 * r + 12, f"keys {keys[i][0]} and {keys[j][0]} a finger apart")
    return [Solid(p, "black") for p in plates]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    rp = export_solids_glb(solids(), d / f"{SLUG}_plates.glb", "MapKeypadPlates")
    w, h = base_size_mm(*BASE)
    s = Scene("MapKeypad")
    s.node("Base", instance=base_glb(*BASE))
    s.node("Plates", instance=rp["glb"])
    for name, (label, x, y) in KEYS.items():
        s.node(name, instance=scene_path("push_button"),
               props={"transform": Xform(origin=(x / 1000, y / 1000, PLATE_T_MM / 1000)), "label": label})
    s.write(d / f"{SLUG}.tscn")
    btn = entry("push_button")
    tris = rp["triangles"] + 4 * btn["triangles"]
    write_entry(GROUP, SLUG, {
        "kind": "control_group",
        "summary": "Four map keys on a 2x2 base: zoom in, zoom out, rotate left, rotate right.",
        "tags": ["keypad", "keys", "buttons", "map", "chart", "zoom", "rotate"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": None, "children": {n: "PushButton" for n in KEYS}, "signal": "<key>.value_changed"},
        "base": f"{BASE[0]}x{BASE[1]}",
        "footprint_mm": [w, h],
        "stand_out_mm": PLATE_T_MM + btn["stand_out_mm"],
        "mount": "back on Z=0, centred; front +Z; zoom keys left, rotate keys right",
        "uses": ["push_button", "control_base"],
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
