"""control_base: the standard mounting plate every panel control sits on, in whole modules (60 mm).

Brief: powder-grey plate, chamfered, four black hex bolts at the corners. One GLB per size; controls instance the
GLB directly, so changing this script and rebuilding updates every control that uses a size, with no other rebuild.
"""
import build123d as bd

from cadkit.solids import Solid, at, box, prism, expect, bbox_mm, export_solids_glb
from cadkit.library import PLATE_T_MM, base_size_mm, out_dir, write_entry

SLUG, GROUP = "control_base", "kit"
USES: list[str] = []
SIZES = [(1, 1), (1, 2), (2, 2)]
CHAMFER = 3.0
BOLT_R, BOLT_H, BOLT_INSET = 3.5, 2.5, 8.0


def solids(cols: int, rows: int) -> list[Solid]:
    w, h = base_size_mm(cols, rows)
    plate = box(w, h, PLATE_T_MM)
    plate = bd.chamfer(plate.edges().filter_by(bd.Axis.Z), CHAMFER)
    plate = bd.chamfer(plate.faces().sort_by(bd.Axis.Z)[-1].edges(), 1.0)
    bolts = [at(prism(6, BOLT_R, BOLT_H), sx * (w / 2 - BOLT_INSET), sy * (h / 2 - BOLT_INSET), PLATE_T_MM)
             for sx in (-1, 1) for sy in (-1, 1)]
    out = [Solid(plate, "interior_dark")] + [Solid(b, "trim_black") for b in bolts]
    lo, hi = bbox_mm(plate)
    expect(abs(hi[0] - lo[0] - w) < 0.01 and abs(hi[1] - lo[1] - h) < 0.01, f"plate {lo}..{hi} is {w} x {h}")
    expect(abs(lo[2]) < 0.01 and abs(hi[2] - PLATE_T_MM) < 0.01, "plate back on Z=0, front at PLATE_T_MM")
    return out


def bolt_positions(cols: int, rows: int) -> list[tuple[float, float]]:
    w, h = base_size_mm(cols, rows)
    return [(sx * (w / 2 - BOLT_INSET), sy * (h / 2 - BOLT_INSET)) for sx in (-1, 1) for sy in (-1, 1)]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    sizes = {}
    for c, r in SIZES:
        rep = export_solids_glb(solids(c, r), d / f"control_base_{c}x{r}.glb", f"ControlBase{c}x{r}")
        sizes[f"{c}x{r}"] = {"glb": rep["glb"], "footprint_mm": list(base_size_mm(c, r)), "triangles": rep["triangles"]}
    write_entry(GROUP, SLUG, {
        "kind": "solid_set",
        "summary": "Standard mounting plate for panel controls: powder grey, chamfered, four black hex bolts.",
        "tags": ["base", "plate", "mount", "panel"],
        "sizes": sizes,
        "mount": "back on Z=0, centred; front +Z; controls put their parts at Z = 6 mm (the plate front)",
        "keep_clear_mm": {"bolt_inset": BOLT_INSET, "bolt_radius": BOLT_R},
    })
    return {"slug": SLUG, "sizes": {k: v["triangles"] for k, v in sizes.items()}}
