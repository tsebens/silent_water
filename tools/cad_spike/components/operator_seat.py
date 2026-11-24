"""operator_seat: a heavy-equipment operator seat on a pedestal (furniture, no behaviour of its own).

Brief (cockpit concept #328): modern operator seat on a suspension pedestal, armrests, powder grey with orange
accents. The occupant faces -Z. The parent binds the behaviour (StationSeat, SonarSeat...) on a node above this
scene and points `sit_point` at SitPoint, because which seat script applies depends on the station.
"""
import build123d as bd

from kitcad import Solid, at, box, prism, expect, bbox_mm, export_solids_glb
from spike import out_dir, res, write_entry
from tscn import Scene, Xform

SLUG, GROUP = "operator_seat", "furniture"
PAN_W, PAN_T, PAN_D, PAN_Y = 500.0, 80.0, 470.0, 400.0
BACK_W, BACK_H, BACK_T, BACK_TILT = 440.0, 440.0, 70.0, 10.0     # shoulder height, not an office chair (round 1 review)
BOLSTER_W = 45.0
ARM_Y, ARM_X = 640.0, 285.0


def solids() -> list[Solid]:
    base = prism(8, 240, 20)
    base = base.rotate(axis=bd.Axis.X, angle=-90)          # lie flat: prism +Z becomes +Y
    column = prism(8, 45, PAN_Y - 20).rotate(axis=bd.Axis.X, angle=-90)
    column = at(column, y=20)
    pan = at(box(PAN_W, PAN_D, PAN_T, chamfer_mm=15).rotate(axis=bd.Axis.X, angle=-90), y=PAN_Y, z=20)
    back = box(BACK_W, BACK_H, BACK_T, chamfer_mm=15, base_z=False)
    back = at(back, y=BACK_H / 2)                                       # bottom edge at y=0
    back = back.rotate(axis=bd.Axis.X, angle=-BACK_TILT)   # lean back (+Z)
    back = at(back, y=PAN_Y + PAN_T + 10, z=PAN_D / 2 + 20 - BACK_T / 2)
    stripes = [at(box(BOLSTER_W, BACK_H, BACK_T + 20, chamfer_mm=10, base_z=False), sx * (BACK_W + BOLSTER_W) / 2, BACK_H / 2)
               for sx in (-1, 1)]
    stripes = [at(s.rotate(axis=bd.Axis.X, angle=-BACK_TILT), y=PAN_Y + PAN_T + 10, z=PAN_D / 2 + 20 - BACK_T / 2)
               for s in stripes]
    arms = [at(box(60, 40, 300, chamfer_mm=8, base_z=False), sx * ARM_X, ARM_Y, 40) for sx in (-1, 1)]
    posts = [at(prism(8, 15, ARM_Y - PAN_Y - PAN_T).rotate(axis=bd.Axis.X, angle=-90),
                sx * ARM_X, PAN_Y + PAN_T / 2, 120) for sx in (-1, 1)]
    lo, hi = bbox_mm(pan)
    expect(abs(hi[1] - (PAN_Y + PAN_T)) < 1 and abs(lo[1] - PAN_Y) < 1, f"seat pan at {PAN_Y} mm: {lo}..{hi}")
    blo, bhi = bbox_mm(back)
    expect(bhi[2] > hi[2] - 40, "backrest at the back (+Z) of the pan")
    expect(900 < bhi[1] < 1050, f"backrest top {bhi[1]:.0f} mm: shoulder height")
    expect(ARM_X - 30 > PAN_W / 2, "armrests outside the pan")
    return ([Solid(base, "black"), Solid(column, "black"), Solid(pan, "powder_grey"), Solid(back, "powder_grey")]
            + [Solid(s, "safety_orange") for s in stripes] + [Solid(a, "black") for a in arms + posts])


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    rep = export_solids_glb(solids(), d / f"{SLUG}.glb", "OperatorSeat")
    s = Scene("OperatorSeat")
    s.node("Model", instance=rep["glb"])
    s.node("SitPoint")
    body_shape = s.sub("BoxShape3D", "body", {"size": (0.5, 0.48, 0.5)})
    s.node("Body", type_="StaticBody3D")
    s.node("Shape", parent="Body", type_="CollisionShape3D",
           props={"transform": Xform(origin=(0, 0.24, 0.02)), "shape": body_shape})
    grab_shape = s.sub("BoxShape3D", "grab", {"size": (0.56, 0.6, 0.55)})
    s.node("Grab", type_="StaticBody3D", props={"collision_layer": 2, "collision_mask": 0})
    s.node("Shape", parent="Grab", type_="CollisionShape3D",
           props={"transform": Xform(origin=(0, 0.7, 0.05)), "shape": grab_shape})
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "furniture",
        "summary": "Operator seat on a pedestal with armrests; grey, shoulder-height back with orange bolsters. Faces -Z.",
        "tags": ["seat", "chair", "operator", "pedestal", "station"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": None, "bind_on_parent": "StationSeat or a subclass; sit_point = <instance>/SitPoint"},
        "footprint_mm": [2 * ARM_X + 60, PAN_D + 60],
        "mount": "on the floor at Y=0, centred on the pedestal; occupant faces -Z",
        "seated_eye_height_m": 1.2,
        "triangles": rep["triangles"],
    })
    return {"slug": SLUG, "triangles": rep["triangles"]}
