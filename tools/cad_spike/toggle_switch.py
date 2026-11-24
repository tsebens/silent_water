"""AI-authored kit part: a guarded toggle switch. Parameters up top; run: uv run python toggle_switch.py out.gltf"""
import sys, json
import build123d as bd
from kitcad import KitPart, export_kit_gltf, ngon_prism

# --- parameters (mm) ---------------------------------------------------------------------------------------------
PLATE_W, PLATE_H, PLATE_T = 70.0, 100.0, 8.0     # faceplate: width (X), height (Y), thickness (Z)
PLATE_CHAMFER = 4.0
BOLT_R, BOLT_H, BOLT_INSET = 4.0, 3.0, 9.0       # hex bolt heads at the corners
COLLAR_R, COLLAR_H = 12.0, 10.0                  # 12-gon bezel the bat comes out of
HINGE_Z = PLATE_T + COLLAR_H + 2.0               # hinge height above the back face (=20)
GUARD_T, GUARD_H, GUARD_DEPTH, GUARD_GAP = 6.0, 56.0, 48.0, 20.0  # guard walls: thickness, height, stand-out, half-gap
GUARD_CHAMFER = 6.0
BAT_R, BAT_LEN, KNOB_R, KNOB_H = 4.5, 36.0, 7.5, 12.0  # the lever: shaft radius/length, chunky knob
LAMP_R, LAMP_H, LAMP_Y = 6.0, 5.0, 38.0          # indicator lamp near the top


def housing() -> bd.Part:
    with bd.BuildPart() as b:
        bd.Box(PLATE_W, PLATE_H, PLATE_T, align=(bd.Align.CENTER, bd.Align.CENTER, bd.Align.MIN))
        bd.chamfer(b.edges().filter_by(bd.Axis.Z), PLATE_CHAMFER)
        # collar around the bat
        bd.insert(ngon_prism(12, COLLAR_R, COLLAR_H, rotation_deg=15).moved(bd.Location((0, 0, PLATE_T))))
        # lamp bezel
        bd.insert(ngon_prism(8, LAMP_R + 2.5, 2.0, rotation_deg=22.5).moved(bd.Location((0, LAMP_Y, PLATE_T))))
    return b.part


def bolts() -> bd.Part:
    with bd.BuildPart() as b:
        pts = [(sx * (PLATE_W / 2 - BOLT_INSET), sy * (PLATE_H / 2 - BOLT_INSET), PLATE_T) for sx in (-1, 1) for sy in (-1, 1)]
        for p in pts:
            bd.insert(ngon_prism(6, BOLT_R, BOLT_H).moved(bd.Location(p)))
    return b.part


def guard() -> bd.Part:
    """Two walls either side of the bat, standing out from the plate, with the outer front corners chamfered."""
    with bd.BuildPart() as b:
        for sx in (-1, 1):
            with bd.Locations((sx * (GUARD_GAP + GUARD_T / 2), 0, PLATE_T)):
                bd.Box(GUARD_T, GUARD_H, GUARD_DEPTH, align=(bd.Align.CENTER, bd.Align.CENTER, bd.Align.MIN))
        front_y_edges = b.edges().filter_by(bd.Axis.X).group_by(bd.Axis.Z)[-1]
        bd.chamfer(front_y_edges, GUARD_CHAMFER)
    return b.part


def bat() -> bd.Part:
    """The lever, in its own frame: hinge on the X axis through the origin, standing straight out along +Z."""
    with bd.BuildPart() as b:
        bd.insert(ngon_prism(8, BAT_R, BAT_LEN, rotation_deg=22.5))
        bd.insert(ngon_prism(8, KNOB_R, KNOB_H, rotation_deg=22.5).moved(bd.Location((0, 0, BAT_LEN))))
        top = b.faces().sort_by(bd.Axis.Z)[-1]
        bd.chamfer(top.edges(), 3.0)
        # hinge boss: a short 8-gon barrel along X through the origin
        with bd.BuildSketch(bd.Plane.YZ):
            bd.RegularPolygon(BAT_R + 1.5, 8, rotation=22.5)
        bd.extrude(amount=8.0, both=True)
    return b.part


def lamp() -> bd.Part:
    with bd.BuildPart() as b:
        bd.insert(ngon_prism(8, LAMP_R, LAMP_H, rotation_deg=22.5).moved(bd.Location((0, LAMP_Y, PLATE_T + 2.0))))
        bd.chamfer(b.faces().sort_by(bd.Axis.Z)[-1].edges(), 1.5)
    return b.part


parts = [
    KitPart("Housing", housing(), "powder_grey"),
    KitPart("Bolts", bolts(), "black"),
    KitPart("Guard", guard(), "safety_orange"),
    KitPart("Switch", bat(), "black", hinge=(0.0, 0.0, HINGE_Z)),
    KitPart("Indicator Light", lamp(), "led"),
]
if __name__ != "__main__": raise SystemExit
from kitcad import expect_bbox, expect_one_solid
for p in parts:
    expect_one_solid(p, n={"Bolts": 4, "Guard": 2}.get(p.name, 1))
expect_bbox(parts[0], (-PLATE_W / 2, -PLATE_H / 2, 0), (PLATE_W / 2, PLATE_H / 2, PLATE_T + COLLAR_H))
expect_bbox(parts[1], (-PLATE_W / 2, -PLATE_H / 2, PLATE_T), (PLATE_W / 2, PLATE_H / 2, PLATE_T + BOLT_H))
expect_bbox(parts[2], (-GUARD_GAP - GUARD_T, -GUARD_H / 2, PLATE_T), (GUARD_GAP + GUARD_T, GUARD_H / 2, PLATE_T + GUARD_DEPTH))
expect_bbox(parts[3], (-KNOB_R - 1, -KNOB_R - 1, -BAT_R - 2), (KNOB_R + 1, KNOB_R + 1, BAT_LEN + KNOB_H))
expect_bbox(parts[4], (-LAMP_R, LAMP_Y - LAMP_R, PLATE_T), (LAMP_R, LAMP_Y + LAMP_R, PLATE_T + 2 + LAMP_H))
out = sys.argv[1] if len(sys.argv) > 1 else "toggle_switch.gltf"
print(json.dumps(export_kit_gltf(parts, out), indent=1))
