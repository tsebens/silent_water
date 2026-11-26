"""map_table: the crew's planning table (a station). Brief: assets/models/stations/map_table/brief.yaml (concept #380).

A D-shaped table in a bay against the port hull wall, an orange edge rail, a grey plinth with orange base ring and
straps, and a console jutting from the middle of the front edge. The operator STANDS (answer 1: no seat), eye 1.65 m, and leans over the table (eye 1.40 m, #429); the console
strip is level with the table top and within reach of the leaning eye (#430).
Above the table, an orange-railed shelf carries the noise repeater and non-functional set-dressing modules, and two
work lamps hang on arms. Nodes are left for the hologram (`HoloMount`) and a plain backdrop panel (`BackPanelAnchor`).

Station-local solids (no behaviour, used once): table top and rail, plinth, ring, straps, console body, side frames,
legs, shelf rails and modules, lamp arms. Everything touched or lit is a catalogue scene on the console strip.
"""
import json
import math

import build123d as bd
import numpy as np
import yaml

from cadkit import mount
from cadkit.solids import Solid, at, bbox_mm, box, expect, export_solids_glb, prism
from cadkit.library import REPO, entry, note, out_dir, res, scene_path, write_entry
from cadkit.tscn import NodePath, Scene, Xform

SLUG, GROUP = "map_table", "stations"
USES: list[str] = ["pan_trackball", "zoom_lever", "rotary_knob", "guarded_toggle", "indicator_lamp", "gauge"]

# Table (mm). Back straight edge on Z=0, a half-ellipse front.
TABLE_HW, TABLE_DEPTH = 1100.0, 900.0
TOP_Y = 750.0                       # top of the edge rail: the table's height (program: mount_height_m 0.75)
RAIL_W, RAIL_H, SLAB_T = 30.0, 80.0, 52.0
PLINTH_INSET, BASE_RING_H, BASE_RING_W = 150.0, 70.0, 20.0
STRAP_W, STRAP_OUT = 50.0, 14.0
# Console jutting from the middle of the front edge.
CON_W = 560.0
CON_BACK_Z, CON_FRONT_Z = 860.0, 1280.0
CON_UNDER_Y = 540.0
# The control strip is level with the table top (#430): its middle at TOP_Y, a shallow 3 degree rake rising away from the operator.
STRIP_MID_Y, STRIP_RAKE_DEG = TOP_Y, 3.0
STRIP_Z = (1280.0, 1000.0)          # z of the strip's front edge and its back edge
_rise = (STRIP_Z[0] - STRIP_Z[1]) * math.tan(math.radians(STRIP_RAKE_DEG))
STRIP_FRONT = (STRIP_MID_Y - _rise / 2, STRIP_Z[0])   # (y, z) of the strip's front edge and its back edge
STRIP_BACK = (STRIP_MID_Y + _rise / 2, STRIP_Z[1])
STRIP_TOL_MM = 10.0                 # how far the strip's middle may sit from the table top
CHEEK_T, INSET_T = 22.0, 4.0
LEG_W = 40.0
EYE = np.array([0.0, 1650.0, CON_FRONT_Z + 100.0])   # the standing operator's eye (answer 1); MapTable leans it in code
# The leaning eye: what src/map/map_table.gd's lean_eye() makes of EYE (LEAN_DOWN below, LEAN_TOWARD toward the hologram).
# The game applies the lean to OperatorEye, so OperatorEye stays the standing eye and LeanEye is a measuring node only.
LEAN_DOWN_MM, LEAN_TOWARD_MM = 250.0, 150.0
LEAN_EYE = EYE + np.array([0.0, -LEAN_DOWN_MM, -LEAN_TOWARD_MM])   # the hologram is straight ahead (-Z) of the eye
REACH_MM = 750.0
# Shelf on the wall above the table.
SHELF_HW, SHELF_D = 950.0, 130.0
SHELF_LO, SHELF_HI = 1230.0, 1620.0
RAIL_BAR = 40.0
# Strip layout: name -> (slug, x mm right of centre, s mm up the slope from the strip's middle).
LAYOUT = {
    "ZoomLever": ("zoom_lever", -170.0, 0.0),
    "PanTrackball": ("pan_trackball", 0.0, -45.0),
    "RotaryKnob": ("rotary_knob", -80.0, 105.0),
    "FollowToggle": ("guarded_toggle", 170.0, 0.0),
    "FollowLamp": ("indicator_lamp", 170.0, 100.0),
}
PROGRAM = REPO / "assets/models/vehicles/sub_interior/program.yaml"


def d_outline(hw: float, depth: float, y_off: float = 0.0, n: int = 14) -> list[tuple[float, float]]:
    """Plan outline (x, z) of a D: straight back on Z=0, a half-ellipse front. Anticlockwise seen from above."""
    b = min(depth, hw)
    pts = [(-hw, 0.0), (hw, 0.0), (hw, depth - b)]
    for i in range(1, n):
        a = math.pi * i / n
        pts.append((hw * math.cos(a), depth - b + b * math.sin(a)))
    pts += [(-hw, depth - b)]
    return pts


def d_front_z(hw: float, depth: float, x: float) -> float:
    b = min(depth, hw)
    return depth - b + b * math.sqrt(max(0.0, 1.0 - (x / hw) ** 2))


def d_slab(hw: float, depth: float, y0: float, y1: float, n: int = 14) -> bd.Part:
    """A D-shaped slab from y0 up to y1 (built in XZ, extruded along +Y)."""
    pts = d_outline(hw, depth, n=n)
    sk = bd.Plane.XZ * bd.Polygon(*pts, align=None)   # XZ plane: local y is global Z, normal is -Y
    solid = bd.extrude(sk, amount=-(y1 - y0))
    return at(solid, y=y0)


def d_ring(hw: float, depth: float, w: float, y0: float, y1: float) -> bd.Part:
    outer = d_slab(hw + w, depth + w, y0, y1)
    inner = d_slab(hw, depth, y0 - 1, y1 + 1)
    return outer - inner


def bar(p0, p1, w: float, h: float | None = None) -> bd.Part:
    """A square-section bar from p0 to p1 (mm)."""
    p0, p1 = np.array(p0, float), np.array(p1, float)
    v = p1 - p0
    length = float(np.linalg.norm(v))
    zdir = v / length
    ref = np.array([1.0, 0.0, 0.0]) if abs(zdir[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
    xdir = np.cross(ref, zdir)
    xdir /= np.linalg.norm(xdir)
    b = bd.Box(w, h or w, length, align=(bd.Align.CENTER, bd.Align.CENTER, bd.Align.MIN))
    return b.moved(bd.Location(bd.Plane(origin=tuple(p0), x_dir=tuple(xdir), z_dir=tuple(zdir))))


def yz_extrude(pts: list[tuple[float, float]], x0: float, x1: float) -> bd.Part:
    """A polygon given as (y, z) points, extruded along X from x0 to x1.

    An extrusion follows the face's normal, which follows the polygon's winding: a clockwise polygon in (y, z) went
    toward -X (the console used to land at x -840..-280). The winding is made anticlockwise first, so it is always +X.
    """
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1]))
    if area < 0:
        pts = pts[::-1]
    sk = bd.Plane.YZ * bd.Polygon(*pts, align=None)
    out = at(bd.extrude(sk, amount=x1 - x0), x=x0)
    b = out.bounding_box()
    expect(abs(b.min.X - x0) < 0.01 and abs(b.max.X - x1) < 0.01, f"yz_extrude spans x {x0}..{x1} ({b.min.X:.1f}..{b.max.X:.1f})")
    return out


# The console strip, in station coordinates (x, y, z): origin at its middle, up the slope, outward normal.
STRIP_UP = np.array([0.0, STRIP_BACK[0] - STRIP_FRONT[0], STRIP_BACK[1] - STRIP_FRONT[1]])
STRIP_LEN = float(np.linalg.norm(STRIP_UP))
STRIP_UP = STRIP_UP / STRIP_LEN
STRIP_N = np.array([0.0, -STRIP_UP[2], STRIP_UP[1]])
if STRIP_N[1] < 0:
    STRIP_N = -STRIP_N
STRIP_O = np.array([0.0, (STRIP_FRONT[0] + STRIP_BACK[0]) / 2, (STRIP_FRONT[1] + STRIP_BACK[1]) / 2])


def strip_point(x: float, s: float, out: float = 0.0) -> np.ndarray:
    return STRIP_O + np.array([x, 0.0, 0.0]) + s * STRIP_UP + out * STRIP_N


def on_strip(shape: bd.Shape, out: float = 0.0) -> bd.Shape:
    o = strip_point(0, 0, out)
    return shape.moved(bd.Location(bd.Plane(origin=tuple(o), x_dir=(1, 0, 0), z_dir=tuple(STRIP_N))))


def hull_half_width_m(z: float, y: float) -> float:
    """Inside half-width of the hull at sub-local z and height y above the centre, from program.yaml's superellipses."""
    h = yaml.safe_load(PROGRAM.read_text())["hull"]
    a, b, c = h["width_m"] / 2, h["length_m"] / 2, h["height_m"] / 2
    plan = (1 - abs(z / b) ** h["plan_exponent"]) ** (1 / h["plan_exponent"])
    sect = (1 - abs(y / c) ** h["section_exponent"]) ** (1 / h["section_exponent"])
    return a * plan * sect - h["wall_m"]


def program() -> dict:
    p = yaml.safe_load(PROGRAM.read_text())
    st = next(s for s in p["stations"] if s["id"] == "map_table")
    other = next(s for s in p["stations"] if s["id"] == "countermeasures")
    return {"table": st, "across": other, "aisle": p["clearances"]["aisle_min_m"], "hull": p["hull"]}


def solids() -> list[Solid]:
    out: list[Solid] = []
    # --- table: slab, rail, plinth, ring, straps
    slab = d_slab(TABLE_HW, TABLE_DEPTH, TOP_Y - SLAB_T - 8, TOP_Y - 8)
    rail = d_ring(TABLE_HW, TABLE_DEPTH, RAIL_W, TOP_Y - RAIL_H, TOP_Y)
    ph = TABLE_HW - PLINTH_INSET
    pd = TABLE_DEPTH - PLINTH_INSET
    plinth = d_slab(ph, pd, BASE_RING_H, TOP_Y - RAIL_H)
    ring = d_ring(ph, pd, BASE_RING_W, 0.0, BASE_RING_H)
    straps = [at(box(STRAP_W, TOP_Y - RAIL_H - BASE_RING_H, STRAP_OUT, base_z=False),
                 x=x, y=BASE_RING_H + (TOP_Y - RAIL_H - BASE_RING_H) / 2, z=d_front_z(ph, pd, x) - 2 + STRAP_OUT / 2)
              for x in (-650.0, -350.0, 350.0, 650.0)]
    out += [Solid(slab, "interior_panel"), Solid(rail, "control_interface"), Solid(plinth, "interior_panel"),
            Solid(ring, "control_interface")] + [Solid(s, "control_interface") for s in straps]
    # --- console: body, strip inset, side frames, legs
    hw = CON_W / 2
    body_pts = [(CON_UNDER_Y, CON_BACK_Z), (CON_UNDER_Y, CON_FRONT_Z), STRIP_FRONT, STRIP_BACK, (STRIP_BACK[0], CON_BACK_Z)]
    body = yz_extrude(body_pts, -hw, hw)
    front_face = yz_extrude([(CON_UNDER_Y, CON_FRONT_Z), (CON_UNDER_Y, CON_FRONT_Z + 6), (STRIP_FRONT[0], CON_FRONT_Z + 6),
                             STRIP_FRONT], -hw + 40, hw - 40)
    inset = on_strip(box(CON_W - 70, STRIP_LEN - 24, INSET_T), 0.0)
    cheeks = [yz_extrude(body_pts, hw, hw + CHEEK_T), yz_extrude(body_pts, -hw - CHEEK_T, -hw)]
    legs = []
    for sx in (-1, 1):
        x0 = sx * (hw - 10) - LEG_W / 2
        legs.append(yz_extrude([(0, CON_FRONT_Z - 70), (0, CON_FRONT_Z - 10), (CON_UNDER_Y + 10, CON_FRONT_Z - 10),
                                (CON_UNDER_Y + 10, CON_FRONT_Z - 110)], x0, x0 + LEG_W))
    # The console's solids share its x extents: the body spans the width, the cheeks sit outside it, the front face and
    # the legs inside the cheeks' outer faces, and the strip inset on the body's top.
    bb = bbox_mm(body)
    expect(abs(bb[0][0] + hw) < 0.1 and abs(bb[1][0] - hw) < 0.1, f"console body spans x -{hw}..{hw} ({bb[0][0]}..{bb[1][0]})")
    expect(abs(bb[0][2] - CON_BACK_Z) < 0.1 and abs(bb[1][2] - CON_FRONT_Z) < 0.1, f"console body spans z {CON_BACK_Z}..{CON_FRONT_Z}")
    expect(abs(bb[0][1] - CON_UNDER_Y) < 0.1 and abs(bb[1][1] - STRIP_BACK[0]) < 0.1, "console body from its underside to the strip's back edge")
    outer = hw + CHEEK_T
    for i, c in enumerate(cheeks):
        cb_ = bbox_mm(c)
        lo, hi = (hw, outer) if i == 0 else (-outer, -hw)
        expect(abs(cb_[0][0] - lo) < 0.1 and abs(cb_[1][0] - hi) < 0.1, f"cheek {i} flush against the body, {lo}..{hi} ({cb_[0][0]}..{cb_[1][0]})")
        expect(cb_[0][1:] == bb[0][1:] and cb_[1][1:] == bb[1][1:], f"cheek {i} the body's y and z extents")
    fb = bbox_mm(front_face)
    expect(fb[0][0] >= -hw and fb[1][0] <= hw, f"front face inside the body's x extents ({fb[0][0]}..{fb[1][0]})")
    expect(abs(fb[0][2] - CON_FRONT_Z) < 0.1 and fb[1][2] <= CON_FRONT_Z + 6.1, "front face on the body's front")
    for i, leg in enumerate(legs):
        lb = bbox_mm(leg)
        expect(lb[0][0] >= -outer and lb[1][0] <= outer, f"leg {i} inside the cheeks' outer faces ({lb[0][0]}..{lb[1][0]})")
        expect(abs(lb[0][1]) < 0.1 and abs(lb[1][1] - (CON_UNDER_Y + 10)) < 0.1, f"leg {i} from the floor up into the body's underside")
        expect(lb[0][2] >= CON_BACK_Z and lb[1][2] <= CON_FRONT_Z, f"leg {i} under the body in z")
    ib = inset.bounding_box()
    n = STRIP_N
    plane_d = [float(np.dot(np.array(v) - strip_point(0, 0), n)) for v in
               [(x, y, z) for x in (ib.min.X, ib.max.X) for y in (ib.min.Y, ib.max.Y) for z in (ib.min.Z, ib.max.Z)]]
    expect(min(abs(d) for d in plane_d) < 0.5, "strip inset's underside lies on the body's top (the strip plane)")
    expect(ib.min.X >= -hw and ib.max.X <= hw, "strip inset inside the body's x extents")
    expect(ib.min.Z >= CON_BACK_Z and ib.max.Z <= CON_FRONT_Z, "strip inset inside the body's z extents")
    out += [Solid(body, "interior_panel"), Solid(inset, "interior_dark"), Solid(front_face, "trim_black")]
    out += [Solid(c, "control_interface") for c in cheeks + legs]
    # --- shelf: rails, back, modules
    rails = [at(box(2 * SHELF_HW, RAIL_BAR, SHELF_D), y=SHELF_LO + RAIL_BAR / 2),
             at(box(2 * SHELF_HW, RAIL_BAR, SHELF_D), y=SHELF_HI - RAIL_BAR / 2)]
    posts = [at(box(RAIL_BAR, SHELF_HI - SHELF_LO, SHELF_D), x=sx * (SHELF_HW - RAIL_BAR / 2), y=(SHELF_LO + SHELF_HI) / 2)
             for sx in (-1, 1)]
    back = at(box(2 * SHELF_HW, SHELF_HI - SHELF_LO - 2 * RAIL_BAR, 8), y=(SHELF_LO + SHELF_HI) / 2)
    out += [Solid(r, "control_interface") for r in rails + posts] + [Solid(back, "interior_dark")]
    out += module_solids()
    # --- work lamps: wall plate, two bars, a head with a lit face
    for sx in (-1, 1):
        out += lamp_solids(sx * 800.0)
    return out


MOD_Y0, MOD_Y1 = SHELF_LO + RAIL_BAR + 12, SHELF_HI - RAIL_BAR - 12
MOD_H = MOD_Y1 - MOD_Y0
MODULES = {                     # name: (x centre, width)
    "ScreenModule": (-640.0, 520.0),
    "GaugeModule": (-170.0, 380.0),
    "SwitchModule": (250.0, 380.0),
    "PanelModule": (650.0, 300.0),
}


def module_solids() -> list[Solid]:
    out: list[Solid] = []
    yc = (MOD_Y0 + MOD_Y1) / 2
    for name, (x, w) in MODULES.items():
        out.append(Solid(at(box(w, MOD_H, 60, chamfer_mm=6), x=x, y=yc, z=8), "interior_panel"))
    x, w = MODULES["ScreenModule"]
    out += [Solid(at(box(w - 50, MOD_H - 60, 8), x=x, y=yc, z=68), "trim_black"),
            Solid(at(box(w - 70, MOD_H - 80, 4), x=x, y=yc, z=76), "screen_off")]
    # switch panel: two rows of small toggles, and lamps
    x, w = MODULES["SwitchModule"]
    for i in range(6):
        for j, (row, role) in enumerate(((yc + 60, "control_grey"), (yc - 20, "control_grey"))):
            out.append(Solid(at(box(18, 30, 24), x=x - 150 + i * 60, y=row, z=68), role))
    for i in range(6):
        out.append(Solid(at(prism(8, 9, 6), x=x - 150 + i * 60, y=yc - 90, z=68), "indicator_off"))
    # right-hand panel: three knobs' plinths and a row of buttons
    x, w = MODULES["PanelModule"]
    for i in range(3):
        out.append(Solid(at(prism(12, 28, 18), x=x - 90 + i * 90, y=yc + 40, z=68), "control_grey"))
    for i in range(4):
        out.append(Solid(at(prism(8, 12, 8), x=x - 90 + i * 60, y=yc - 70, z=68), "button"))
    return out


# The gauges on the shelf (catalogue scenes, no source): name -> (x, y offset from the module centre, radius m).
SHELF_GAUGES = {"NoiseRepeater": ("GaugeModule", 0.0, 10.0, 0.075)}
DECOR_GAUGES = {"DecorGauge1": (-110.0, 55.0, 0.04), "DecorGauge2": (110.0, 55.0, 0.04), "DecorGauge3": (-110.0, -60.0, 0.04),
                "DecorGauge4": (110.0, -60.0, 0.04)}


def lamp_solids(x: float) -> list[Solid]:
    """Wall plate, a two-bar arm reaching over the table, and a head whose face is lit (lamp_cabin)."""
    base = (x, 1150.0, 14.0)
    elbow = (x * 0.92, 1290.0, 330.0)
    tip = (x * 0.80, 1180.0, 560.0)
    plate = at(box(70, 70, 14), x=x, y=base[1])
    a1, a2 = bar(base, elbow, 20), bar(elbow, tip, 20)
    joint = at(prism(8, 20, 30), x=elbow[0], y=elbow[1], z=elbow[2] - 15)
    head = at(prism(8, 50, 70), x=tip[0], y=tip[1], z=tip[2], rx=90)           # nose points down (-Y)
    face = at(prism(8, 40, 4), x=tip[0], y=tip[1] - 70, z=tip[2], rx=90)
    neck = bar((tip[0], tip[1] + 10, tip[2]), (tip[0], tip[1] + 55, tip[2]), 24)
    return [Solid(plate, "trim_black"), Solid(a1 + a2 + joint + neck, "trim_black"), Solid(head, "interior_panel"),
            Solid(face, "lamp_cabin")]


def _check(sol: list[Solid]) -> dict:
    """Checks against the brief, the arc and the catalogue entries of everything placed. Returns figures for the entry."""
    allb = [s.shape.bounding_box() for s in sol]
    lo_y = min(b.min.Y for b in allb)
    lo_z = min(b.min.Z for b in allb)
    expect(abs(lo_y) < 0.01, f"floor at Y=0 (lowest point {lo_y:.2f} mm)")
    expect(abs(lo_z) < 0.01 + 5, f"back on Z=0 (rearmost point {lo_z:.2f} mm)")
    expect(lo_z >= -0.01, f"nothing behind the back plane ({lo_z:.2f} mm)")
    top = max(s.shape.bounding_box().max.Y for s in sol[:2])        # slab and rail
    expect(abs(top - TOP_Y) < 0.5, f"table top at {TOP_Y} mm ({top:.1f})")
    prog = program()
    ft = prog["table"]["footprint"]
    rail = sol[1].shape.bounding_box()
    expect(rail.max.X - rail.min.X <= ft[0] * 1000 + 2 * RAIL_W + 1, f"table within the bay's {ft[0]} m along the wall")
    expect(rail.max.Z <= ft[1] * 1000 + 2 * RAIL_W + 1, f"table within the bay's {ft[1]} m depth ({rail.max.Z:.0f} mm)")
    expect(abs(prog["table"]["mount_height_m"] * 1000 - TOP_Y) <= 1, "table top matches program mount_height_m")
    # Console: does it start on the table's front edge, and is it centred on it?
    front_at_console = d_front_z(TABLE_HW, TABLE_DEPTH, CON_W / 2)
    expect(CON_BACK_Z < front_at_console, "console meets the table's front edge")
    expect(CON_FRONT_Z > TABLE_DEPTH + 200, "console juts clear of the table")
    # Aisle: the station's furthest point against the walkway, at the program position.
    z = prog["table"]["z"]
    y_top = prog["table"]["mount_height_m"] - 0.95 - 0.0             # table height measured from the hull's centre (deck is 0.95 below)
    hw = hull_half_width_m(z, y_top)
    furthest = max(s.shape.bounding_box().max.Z for s in sol if s.role not in ("lamp_cabin",)) / 1000
    across = prog["across"]["footprint"][1]
    front_x = -hw + furthest
    opposite_x = hw - across
    aisle = opposite_x - front_x
    expect(aisle >= prog["aisle"], f"aisle between the console and the starboard side {aisle:.2f} m >= {prog['aisle']} m")
    # The strip is level with the table top, with a shallow rake.
    rake = math.degrees(math.atan2(STRIP_BACK[0] - STRIP_FRONT[0], STRIP_Z[0] - STRIP_Z[1]))
    expect(abs(STRIP_O[1] - TOP_Y) <= STRIP_TOL_MM, f"strip's middle level with the table top ({STRIP_O[1]:.1f} vs {TOP_Y} mm, +/-{STRIP_TOL_MM})")
    expect(0 <= rake <= 5.0, f"strip rake {rake:.1f} degrees, at most 5")
    expect(abs(STRIP_FRONT[0] - TOP_Y) <= STRIP_TOL_MM and abs(STRIP_BACK[0] - TOP_Y) <= STRIP_TOL_MM, "both strip edges within the tolerance of the table top")
    # Sight line from the leaning eye to the hologram's middle (HoloMount, above the table's centre) clears the console.
    holo = np.array([0.0, TOP_Y, TABLE_DEPTH / 2])
    for z in np.linspace(CON_BACK_Z, CON_FRONT_Z, 9):
        t = (LEAN_EYE[2] - z) / (LEAN_EYE[2] - holo[2])
        y_line = LEAN_EYE[1] + t * (holo[1] - LEAN_EYE[1])
        expect(y_line > STRIP_BACK[0] + 100, f"sight line from the leaning eye to the table clears the console at z={z:.0f} ({y_line:.0f} mm)")
    # Controls: footprint on the strip, reach from the leaning eye, and mutual clearance.
    rects = []
    for name, (slug, x, s) in LAYOUT.items():
        e = entry(slug)
        w, h = e["footprint_mm"]
        expect(abs(x) + w / 2 <= CON_W / 2 - 25, f"{name} inside the strip's width")
        expect(abs(s) + h / 2 <= STRIP_LEN / 2 - 8, f"{name} inside the strip's depth ({s:+.0f} +/- {h / 2:.0f} of {STRIP_LEN / 2:.0f})")
        rects.append((name, x - w / 2, x + w / 2, s - h / 2, s + h / 2))
        top_pt = strip_point(x, s, INSET_T + e["stand_out_mm"])
        for p in (strip_point(x, s, INSET_T), top_pt):
            reach = float(np.linalg.norm(p - LEAN_EYE))
            expect(reach <= REACH_MM, f"{name} within reach of the leaning eye ({reach:.0f} mm)")
    for i, a in enumerate(rects):
        for b in rects[i + 1:]:
            gx = max(b[1] - a[2], a[1] - b[2])
            gs = max(b[3] - a[4], a[3] - b[4])
            expect(max(gx, gs) >= 24, f"{a[0]} and {b[0]} clear of each other ({max(gx, gs):.0f} mm)")
    face_to_eye = math.degrees(math.acos(float(np.dot((LEAN_EYE - STRIP_O) / np.linalg.norm(LEAN_EYE - STRIP_O), STRIP_N))))
    expect(face_to_eye <= 45, f"console strip faces the leaning eye ({face_to_eye:.0f} degrees off)")
    expect(STRIP_BACK[0] <= TOP_Y + STRIP_TOL_MM, "console stays level with the table, low enough to see over")
    # Shelf modules: gauges fit their module.
    gx = entry("gauge")["extent_radii"]
    for name, (mx, mw) in MODULES.items():
        expect(MOD_Y0 >= SHELF_LO + RAIL_BAR and MOD_Y1 <= SHELF_HI - RAIL_BAR, f"{name} between the shelf rails")
        expect(abs(mx) + mw / 2 <= SHELF_HW - RAIL_BAR, f"{name} inside the shelf")
    mx, mw = MODULES["GaugeModule"]
    yc = (MOD_Y0 + MOD_Y1) / 2
    items = [(0.0, 10.0, 0.075)] + list(DECOR_GAUGES.values())
    for gx_, gy, r in items:
        ext = r * 1000
        expect(abs(gx_) + gx["bezel"] * ext <= mw / 2 - 6, f"gauge at {gx_} inside the gauge module")
        expect(abs(gy) + gx["bezel"] * ext <= MOD_H / 2 - 6, f"gauge at {gx_},{gy} inside the module's height")
    return {"aisle_m": round(aisle, 3), "hull_half_width_m": round(hw, 3)}


def _xf(origin_mm: np.ndarray, up, normal) -> Xform:
    return Xform.frame((1, 0, 0), tuple(up), tuple(normal), tuple(np.array(origin_mm) / 1000))


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    sol = solids()
    figures = _check(sol)
    rep = export_solids_glb(sol, d / f"{SLUG}_body.glb", "MapTableBody")
    s = Scene("MapTable", type_="Node3D")
    s.node("Body", instance=rep["glb"])
    # Collision: the plinth and table as one box, and the console.
    tb = s.sub("BoxShape3D", "table", {"size": (2 * TABLE_HW / 1000, TOP_Y / 1000, TABLE_DEPTH / 1000)})
    cb = s.sub("BoxShape3D", "console", {"size": (CON_W / 1000, STRIP_BACK[0] / 1000, (CON_FRONT_Z - CON_BACK_Z) / 1000)})
    s.node("Collision", type_="StaticBody3D")
    s.node("Table", parent="Collision", type_="CollisionShape3D",
           props={"transform": Xform(origin=(0, TOP_Y / 2000, TABLE_DEPTH / 2000)), "shape": tb})
    s.node("Console", parent="Collision", type_="CollisionShape3D",
           props={"transform": Xform(origin=(0, STRIP_BACK[0] / 2000, (CON_FRONT_Z + CON_BACK_Z) / 2000)), "shape": cb})
    # The hologram sits on the table's top, at the middle of the D; the backdrop panel stands along the back edge.
    s.node("HoloMount", props={"transform": Xform(origin=(0, TOP_Y / 1000, TABLE_DEPTH / 2000))})
    s.node("BackPanelAnchor", props={"transform": Xform(origin=(0, TOP_Y / 1000, 0.0))})
    s.node("OperatorPoint", props={"transform": Xform(origin=(0, 0, (CON_FRONT_Z + 100) / 1000))})
    s.node("OperatorEye", props={"transform": Xform(origin=tuple(EYE / 1000))})
    s.node("LeanEye", props={"transform": Xform(origin=tuple(LEAN_EYE / 1000))})
    s.node("Controls", props={"transform": _xf(strip_point(0, 0, INSET_T), STRIP_UP, STRIP_N)})
    for name, (slug, x, sv) in LAYOUT.items():
        s.node(name, parent="Controls", instance=scene_path(slug), props={"transform": Xform(origin=(x / 1000, sv / 1000, 0))})
    # Shelf: the noise repeater, and decorative gauges (the catalogue gauge with nothing to read).
    yc = (MOD_Y0 + MOD_Y1) / 2
    mx, _mw = MODULES["GaugeModule"]
    s.node("Shelf", props={"transform": Xform(origin=(mx / 1000, yc / 1000, 68 / 1000))})
    gap = mount.stand_off() / 1000       # the dial's face is drawn on the anchor's Z=0: off the module's front plate by the gap
    s.node("NoiseRepeater", parent="Shelf", instance="res://src/noise/noise_gauge.tscn",
           props={"transform": Xform(origin=(0, 10 / 1000, gap)), "radius": 0.075})
    for name, (gx_, gy, r) in DECOR_GAUGES.items():
        s.node(name, parent="Shelf", instance=scene_path("gauge"),
               props={"transform": Xform(origin=(gx_ / 1000, gy / 1000, gap)), "radius": r, "title": "", "source_group": SName_none()})
    s.write(d / f"{SLUG}.tscn")
    tris = (rep["triangles"] + sum(entry(sl)["triangles"] for sl, *_ in LAYOUT.values())
            + (1 + len(DECOR_GAUGES)) * entry("gauge")["triangles"])
    expect(tris <= 12000, f"station within the 12,000 triangle budget ({tris})")
    _cameras(d)
    mounts = [mount.record(f"Shelf/{n}", "gauge", mount.stand_off(), "GaugeModule front plate")
              for n in ("NoiseRepeater", *DECOR_GAUGES)]
    expect(mounts[0]["offset_mm"] > mount.COPLANAR_TOL_MM and not mount.problems(SLUG, {"mounts": mounts}, entry),
           f"no gauge face (back, dial face on Z=0, bezel front) within {mount.COPLANAR_TOL_MM} mm of the module's front plate")
    write_entry(GROUP, SLUG, {
        "mounts": mounts,
        "kind": "station",
        "summary": "Crew map table: D-shaped table with orange edge rail, plinth and braces, a console jutting from the front "
                   "edge (pan trackball, zoom lever, decorative knob, follow switch, lamp), an orange-railed instrument shelf "
                   "with the noise repeater, and two work lamps. The operator stands; no seat.",
        "tags": ["station", "map", "table", "console", "standing"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"wire": {"pan": "Controls/PanTrackball", "zoom": "Controls/ZoomLever", "follow": "Controls/FollowToggle",
                               "follow_lamp": "Controls/FollowLamp", "hologram_mount": "HoloMount",
                               "backdrop_anchor": "BackPanelAnchor", "standing_eye": "OperatorEye", "leaning_eye": "LeanEye",
                               "noise_repeater": "Shelf/NoiseRepeater"}},
        "footprint_mm": [2 * (TABLE_HW + RAIL_W), CON_FRONT_Z],
        "stand_out_mm": CON_FRONT_Z,
        "mount": "floor at Y=0, back against the hull on Z=0 (the table's straight edge), operator standing at +Z facing -Z",
        "uses": list(USES),
        "triangles": tris,
        "triangles_by_part": {"body": rep["triangles"]},
        "checks": figures,
    })
    return {"slug": SLUG, "triangles": tris, "body": rep["triangles"]}


def SName_none():
    from cadkit.tscn import SName
    return SName("map_table_no_readouts")


def _cameras(d) -> None:
    """Review cameras: the concept viewpoints, the operator's eye (white and red light), orthographic profile and front."""
    eye = [round(v / 1000, 3) for v in LEAN_EYE]
    cams = [
        {"name": "concept_round6_view", "pos": [1.1, 2.0, 3.6], "look_at": [0.1, 0.95, 0.5], "fov": 58.0},
        {"name": "concept_round5_view", "pos": [-1.6, 1.8, 3.8], "look_at": [0.0, 1.0, 0.4], "fov": 55.0},
        {"name": "operator_eye", "pos": eye, "look_at": [0.0, 0.8, 0.7], "fov": 75.0},
        {"name": "operator_eye_red", "pos": eye, "look_at": [0.0, 0.8, 0.7], "fov": 75.0, "light": "red"},
        {"name": "console_level", "pos": [3.2, 0.8, 1.05], "look_at": [0.0, 0.75, 1.05], "ortho": 1.6},
        {"name": "profile_right", "pos": [4.5, 1.0, 0.7], "look_at": [0.0, 1.0, 0.7], "ortho": 2.6},
        {"name": "front", "pos": [0.0, 1.0, 5.5], "look_at": [0.0, 1.0, 0.0], "ortho": 2.6},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
