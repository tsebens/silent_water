"""gauge: the solids of the shared dial instrument. Every Gauge in the game instances these (src/interact/gauge.gd).

Brief (#346, reference image from Tristan): a modern instrument, not an antique: chunky dark round bezel, dark face,
light needle, title on a small plate below. Shape only: what varies per use (range, sweep, where the scale starts,
title, radius, colours of face and needle) is an export on the Gauge script, not geometry.

Reference size: radius 100 mm. The script scales X and Y by radius / 0.1 and leaves Z alone, so every gauge has the
same depth and mounts the same way: back on Z = -10 mm, dial face on Z = 0, bezel front at Z = +14 mm.
"""
import build123d as bd

from kitcad import Solid, at, box, prism, expect, bbox_mm, export_solids_glb
from spike import out_dir, res, write_entry
from tscn import Scene

SLUG, GROUP = "gauge", "kit"
R = 100.0
SIDES = 16
BACK_Z = -10.0
RIM_OUT, RIM_IN, RIM_FRONT, RIM_CHAMFER = 1.12 * R, 0.96 * R, 14.0, 5.0     # the old rim's outer size, so layouts hold
HUB_R, HUB_FRONT = 0.10 * R, 10.0
PLATE_W, PLATE_H, PLATE_T, PLATE_Y = 1.7 * R, 0.36 * R, 4.0, -1.37 * R
NEEDLE_TIP, NEEDLE_TAIL, NEEDLE_W_ROOT, NEEDLE_W_TIP, NEEDLE_T = 0.80 * R, 0.18 * R, 0.08 * R, 0.03 * R, 2.0


def solids() -> tuple[list[Solid], list[Solid]]:
    back = at(prism(SIDES, RIM_IN + 2, -BACK_Z - 1.0), z=BACK_Z)                  # stops 1 mm under the dial face
    rim = at(prism(SIDES, RIM_OUT, RIM_FRONT - BACK_Z, chamfer_top=RIM_CHAMFER) - prism(SIDES, RIM_IN, RIM_FRONT - BACK_Z), z=BACK_Z)
    hub = at(prism(8, HUB_R, HUB_FRONT + 1.0, chamfer_top=2.0), z=-1.0)
    plate = at(box(PLATE_W, PLATE_H, PLATE_T, chamfer_mm=1.0), y=PLATE_Y, z=BACK_Z)
    needle = bd.extrude(bd.Polygon((-NEEDLE_W_ROOT / 2, -NEEDLE_TAIL), (NEEDLE_W_ROOT / 2, -NEEDLE_TAIL),
                                   (NEEDLE_W_TIP / 2, NEEDLE_TIP), (-NEEDLE_W_TIP / 2, NEEDLE_TIP), align=None), amount=NEEDLE_T)
    lo, hi = bbox_mm(rim)
    expect(abs(lo[2] - BACK_Z) < 0.01 and abs(hi[2] - RIM_FRONT) < 0.01, "bezel from the mount face to its front")
    expect(bbox_mm(back)[1][2] < 0, "the backing stops under the dial face (Z=0), which the script draws")
    expect(bbox_mm(plate)[1][1] < -RIM_OUT, "title plate clear below the bezel")
    expect(PLATE_W / 2 <= RIM_OUT, "title plate no wider than the bezel, so the footprint stays the bezel's")
    expect(NEEDLE_TIP < RIM_IN * 0.9 and HUB_FRONT < RIM_FRONT, "needle and hub sit inside the bezel")
    nlo, nhi = bbox_mm(needle)
    expect(abs(nlo[2]) < 0.01 and abs(nhi[1] - NEEDLE_TIP) < 0.01 and abs(nlo[0] + nhi[0]) < 0.01,
           "needle: pivot on the origin, pointing +Y, lying on Z=0")
    return ([Solid(back, "black"), Solid(rim, "black"), Solid(hub, "black"), Solid(plate, "black")],
            [Solid(needle, "powder_grey")])


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, needle = solids()
    rb = export_solids_glb(body, d / "gauge_body.glb", "GaugeBody")
    rn = export_solids_glb(needle, d / "gauge_needle.glb", "GaugeNeedle")
    s = Scene("Gauge", script="res://src/interact/gauge.gd")
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "display",
        "summary": "Round dial instrument: dark bezel and face, light needle and markings, title plate below. "
                   "Reads a readout group; optional second needle.",
        "tags": ["gauge", "dial", "needle", "readout", "instrument"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "Gauge", "reads": "readout(name) on the first node in source_group"},
        "solids": {"body": rb["glb"], "needle": rn["glb"], "used_by": "src/interact/gauge.gd (preloaded)"},
        "extent_radii": {"bezel": RIM_OUT / R, "plate_half_width": PLATE_W / 2 / R,
                         "plate_bottom": (-PLATE_Y + PLATE_H / 2) / R},
        "depth_mm": {"behind_origin": -BACK_Z, "in_front_of_origin": RIM_FRONT},
        "mount": "dial face toward +Z, centred on the origin; the back is 10 mm behind the origin at every radius",
        "set_on_instance": {
            "radius": "m; scales the dial in X and Y",
            "title, readout, readout_b, source_group": "what it shows",
            "min_value, max_value, wraps, wrap_labels": "the scale",
            "sweep_deg, sweep_center_deg": "how far the scale runs, and where its middle points (degrees clockwise from up)",
            "major_divisions, minor_per_division, show_scale": "the markings",
            "face_color, marking_color, needle_color, needle_b_color": "colours",
        },
        "triangles": rb["triangles"] + rn["triangles"],
    })
    return {"slug": SLUG, "triangles": rb["triangles"] + rn["triangles"]}
