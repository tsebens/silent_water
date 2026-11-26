"""engineering_station: the sub's staying-afloat-by-hand station (a panel). Brief: assets/models/panels/engineering_station/brief.yaml.

Plumbing, not a wall unit. Back on Z=0 against the port hull. At chest height a ballast pipe runs along the hull with a
FLOOD and a BLOW `valve_wheel` on it and, between them, a small plate with the TANK LEVEL and AIR REMAINING gauges. Below
it a low console, its top raked toward the standing eye, carries the DROP WEIGHTS button under its hazard-striped guard,
the BILGE PUMP switch with its RUNNING lamp, the BILGE LEVEL gauge and the noise repeater. The manual bilge pump's lever
comes out of the console's end, along the hull, and swings up and down. Two orange grab rails run along the wall.

Local solids (static, used once): the pipe, its brackets, the gauge plate, the console, its front inset and hazard strip,
the hose stub, the rails and the label plates. Everything else is a catalogue scene, set 2 mm off its host face (the
mount rule). No scripts are added: `label`, `readout`, `title` and the scales are set on the instances.

Frame (mm): X along the hull, Y up, Z out of the hull (the mount face). The origin is the station's centre, 1.1 m above
the floor, so Y = -1100 is the floor and the standing eye is at (0, 550, 500).
"""
import json
import math

import numpy as np
import build123d as bd
import yaml

from cadkit import mount
from cadkit.solids import Solid, at, box, expect, expect_in_front, export_solids_glb, prism
from cadkit.library import REPO, entry, note, out_dir, res, scene_path, write_entry
from cadkit.tscn import NodePath, SName, Scene, Xform

SLUG, GROUP = "engineering_station", "panels"
USES: list[str] = ["valve_wheel", "gauge", "lit_toggle", "drop_weights_button", "hand_pump"]
NOISE_GAUGE_SCENE = "res://src/noise/noise_gauge.tscn"      # an existing scene: a configured gauge (its entry is `gauge`'s)
TRIANGLE_BUDGET = 4000

# The brief's constraints (concept #530).
MAX_ALONG = 1200.0                              # along the hull
EYE = np.array([0.0, 550.0, 500.0])             # operator_eye_m
SHOULDER = EYE - np.array([0.0, 250.0, 0.0])
REACH = 1100.0                                  # reach_m, from the shoulder
FLOOR_Y = -1100.0                               # the floor, in the station frame (the centre is 1.1 m up)
BALLAST_Z_M = 3.275                             # program.yaml: the ballast position, port

# Ballast pipework and the gauge plate.
PIPE_Y, PIPE_R, PIPE_Z, PIPE_X0, PIPE_X1 = 170.0, 26.0, 30.0, -560.0, 560.0
BRACKET_X = (-470.0, -140.0, 140.0, 480.0)
WHEEL_X = (-330.0, 330.0)
GPLATE = (0.0, 300.0, 300.0, 190.0, 16.0)       # centre x, y, width, height, thickness (on the wall)
WALL_GAUGE_R, WALL_GAUGE_X, WALL_GAUGE_Y = 0.055, (-75.0, 75.0), 315.0

# The console: a box from the floor, its top raked down toward the aisle by SLOPE_DEG.
CX0, CX1, CONSOLE_D = -600.0, 80.0, 400.0
Y_BACK = -250.0                                 # top at the hull
SLOPE_DEG = 22.0
Y_FRONT = Y_BACK - CONSOLE_D * math.tan(math.radians(SLOPE_DEG))
# Console-top items, in surface coordinates: u along the hull, v up the slope from the front edge.
ROW_V = 250.0
LABEL_V = 130.0
TOP_GAUGE_R = 0.05
DROP_U, TOGGLE_U, BILGE_U, NOISE_U = -470.0, -330.0, -200.0, -60.0

# The manual pump: out of the console's end, its lever along +X, swinging in the XY plane.
PUMP_Y, PUMP_Z = -330.0, 200.0

# Grab rails.
RAIL_Z0, RAIL_Z1, RAIL_H = 50.0, 86.0, 30.0
RAILS = ((40.0, -560.0, 560.0), (-100.0, -560.0, 60.0))     # (y, x0, x1)

# The hull's inner surface at the ballast position, from the program, for the aisle check.
PROGRAM = REPO / "assets/models/vehicles/sub_interior/program.yaml"

_T = np.array([0.0, math.sin(math.radians(SLOPE_DEG)), -math.cos(math.radians(SLOPE_DEG))])   # up the slope
_N = np.array([0.0, math.cos(math.radians(SLOPE_DEG)), math.sin(math.radians(SLOPE_DEG))])    # out of it
_X = np.array([1.0, 0.0, 0.0])
FRONT_POINT = np.array([0.0, Y_FRONT, CONSOLE_D])


def surf_point(u: float, v: float, out: float = 0.0) -> np.ndarray:
    return FRONT_POINT + np.array([u, 0.0, 0.0]) + _T * v + _N * out


def _depth(slug: str) -> tuple[float, float]:
    e = entry(slug)
    d = e.get("depth_mm")
    return (d["behind_origin"], d["in_front_of_origin"]) if d else (0.0, e["stand_out_mm"])


class Item:
    """One placed catalogue scene: where its origin is, which way it faces and what it occupies (a local box)."""

    def __init__(self, name: str, slug: str, scene: str, origin: np.ndarray, basis: np.ndarray, rect: tuple,
                 behind: float, front: float, host: str, offset: float, plane: str, **props):
        self.name, self.slug, self.scene, self.props = name, slug, scene, props
        self.origin, self.basis, self.rect, self.host, self.offset, self.plane = origin, basis, rect, host, offset, plane
        self.local_box = (rect[0], rect[1], -behind, rect[2], rect[3], front)

    def corners(self, local_box: tuple | None = None) -> np.ndarray:
        x0, y0, z0, x1, y1, z1 = local_box or self.local_box
        pts = [(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
        return np.array([self.basis @ np.array(p) + self.origin for p in pts])

    @property
    def aabb(self) -> tuple:
        c = self.corners()
        return tuple(c.min(axis=0)) + tuple(c.max(axis=0))

    @property
    def normal(self) -> np.ndarray:
        return self.basis[:, 2]

    def local_to_world(self, p) -> np.ndarray:
        return self.basis @ np.asarray(p, float) + self.origin


def _gauge_rect(r_m: float) -> tuple:
    ext = entry("gauge")["extent_radii"]
    r = r_m * 1000
    return (-ext["bezel"] * r, -ext["plate_bottom"] * r, ext["bezel"] * r, ext["bezel"] * r)


def _wall(name: str, slug: str, x: float, y: float, host_z: float, plane: str, rect: tuple | None = None,
          scene: str | None = None, **props) -> Item:
    behind, front = _depth(slug)
    off = mount.stand_off(behind)
    if rect is None:
        w, h = entry(slug)["footprint_mm"]
        rect = (-w / 2, -h / 2, w / 2, h / 2)
    return Item(name, slug, scene or scene_path(slug), np.array([x, y, host_z + off]), np.eye(3), rect, behind, front,
                f"wall plane z={host_z:g}", off, plane, **props)


def _console(name: str, slug: str, u: float, rect: tuple | None = None, scene: str | None = None, **props) -> Item:
    behind, front = _depth(slug)
    off = mount.stand_off(behind)
    if rect is None:
        w, h = entry(slug)["footprint_mm"]
        rect = (-w / 2, -h / 2, w / 2, h / 2)
    basis = np.column_stack([_X, _T, _N])
    return Item(name, slug, scene or scene_path(slug), surf_point(u, ROW_V, off), basis, rect, behind, front,
                "console top", off, "console", **props)


def items() -> list[Item]:
    gp = GPLATE
    out = [
        _wall("FloodWheel", "valve_wheel", WHEEL_X[0], PIPE_Y, 0.0, "wall", label="FLOOD"),
        _wall("BlowWheel", "valve_wheel", WHEEL_X[1], PIPE_Y, 0.0, "wall", label="BLOW"),
        _wall("TankGauge", "gauge", WALL_GAUGE_X[0], WALL_GAUGE_Y, gp[4], "wall", rect=_gauge_rect(WALL_GAUGE_R),
              title="TANK LEVEL", readout=SName("tank_fraction"), min_value=0.0, max_value=1.0, sweep_deg=180.0,
              radius=WALL_GAUGE_R),
        _wall("AirGauge", "gauge", WALL_GAUGE_X[1], WALL_GAUGE_Y, gp[4], "wall", rect=_gauge_rect(WALL_GAUGE_R),
              title="AIR REMAINING", readout=SName("air_fraction"), min_value=0.0, max_value=1.0, sweep_deg=180.0,
              radius=WALL_GAUGE_R),
        _console("DropWeights", "drop_weights_button", DROP_U),
        _console("BilgeSwitch", "lit_toggle", TOGGLE_U, label="BILGE PUMP"),
        _console("BilgeGauge", "gauge", BILGE_U, rect=_gauge_rect(TOP_GAUGE_R), title="BILGE LEVEL",
                 readout=SName("bilge_water_t"), min_value=0.0, max_value=8.0, sweep_deg=180.0, radius=TOP_GAUGE_R),
        _console("NoiseGauge", "gauge", NOISE_U, rect=_gauge_rect(TOP_GAUGE_R), scene=NOISE_GAUGE_SCENE, radius=TOP_GAUGE_R),
    ]
    # The pump: its +Z (the lever) runs out along +X, its +X is -Z, its housing back on the console's end face.
    pe = entry("hand_pump")
    w, h = pe["footprint_mm"]
    off = mount.stand_off(0.0)
    basis = np.column_stack([np.array([0.0, 0.0, -1.0]), np.array([0.0, 1.0, 0.0]), np.array([1.0, 0.0, 0.0])])
    out.append(Item("HandPump", "hand_pump", scene_path("hand_pump"), np.array([CX1 + off, PUMP_Y, PUMP_Z]), basis,
                    (-w / 2, -h / 2, w / 2, h / 2), 0.0, pe["stand_out_mm"], f"console end x={CX1:g}", off, "pump"))
    return out


def solids() -> tuple[list[Solid], dict]:
    gp = GPLATE
    pipe = at(prism(16, PIPE_R, PIPE_X1 - PIPE_X0), PIPE_X0, PIPE_Y, PIPE_Z, ry=90)
    brackets = [at(box(26.0, 84.0, PIPE_Z + PIPE_R - 4.0), x, PIPE_Y) for x in BRACKET_X]
    plate = at(box(gp[2], gp[3], gp[4], chamfer_mm=2.0), gp[0], gp[1])
    # The console: a polygon in (Y, Z) extruded along X.
    with bd.BuildPart() as b:
        with bd.BuildSketch(bd.Plane.YZ):
            bd.Polygon((FLOOR_Y, 0.0), (FLOOR_Y, CONSOLE_D), (Y_FRONT, CONSOLE_D), (Y_BACK, 0.0), align=None)
        bd.extrude(amount=CX1 - CX0)
    console = at(b.part, x=CX0)
    inset = at(box(420.0, 300.0, 4.0), -300.0, -800.0, CONSOLE_D)
    kick = at(box(360.0, 30.0, 2.0), -300.0, -1070.0, CONSOLE_D)
    hose = at(prism(8, 22.0, 110.0), CX1, PUMP_Y - 330.0, PUMP_Z, ry=90)
    rails, posts = [], []
    for y, x0, x1 in RAILS:
        rails.append(at(box(x1 - x0, RAIL_H, RAIL_Z1 - RAIL_Z0, chamfer_mm=4.0), (x0 + x1) / 2, y, RAIL_Z0))
        for x in (x0 + 40.0, (x0 + x1) / 2, x1 - 40.0):
            posts.append(at(box(20.0, 20.0, RAIL_Z0 + 1.0), x, y))
    on_wall = lambda w, h, x, y, z: at(box(w, h, 2.0), x, y, z)
    labels = [on_wall(110.0, 26.0, WHEEL_X[0], 285.0, 0.0), on_wall(110.0, 26.0, WHEEL_X[1], 285.0, 0.0)]
    surf = lambda w, h, u, v: bd.Plane(origin=tuple(surf_point(u, v)), x_dir=(1, 0, 0), z_dir=tuple(_N))
    for w, h, u in ((170.0, 16.0, DROP_U), (96.0, 16.0, TOGGLE_U), (104.0, 16.0, BILGE_U), (64.0, 16.0, NOISE_U)):
        labels.append(box(w, h, 2.0).moved(bd.Location(surf(w, h, u, LABEL_V))))
    parts = ([Solid(console, "interior_panel"), Solid(inset, "interior_dark"), Solid(kick, "hazard_stripe"),
              Solid(pipe, "hull_metal"), Solid(hose, "hull_metal")]
             + [Solid(s, "hull_metal") for s in brackets] + [Solid(plate, "label_plate")]
             + [Solid(s, "label_plate") for s in labels] + [Solid(r, "control_interface") for r in rails]
             + [Solid(p, "interior_dark") for p in posts])
    expect_in_front(parts, SLUG)
    return parts, {"rails": rails, "brackets": brackets, "pipe": pipe, "plate": plate, "hose": hose}


def _seg_hits(a: np.ndarray, b: np.ndarray, bx: tuple, margin: float = 0.0) -> bool:
    """Does the segment a->b pass through the box (x0, y0, z0, x1, y1, z1)? Slab test."""
    lo, hi = np.array(bx[:3]) - margin, np.array(bx[3:]) + margin
    d = b - a
    t0, t1 = 0.0, 1.0
    for i in range(3):
        if abs(d[i]) < 1e-9:
            if a[i] < lo[i] or a[i] > hi[i]:
                return False
            continue
        u, v = (lo[i] - a[i]) / d[i], (hi[i] - a[i]) / d[i]
        t0, t1 = max(t0, min(u, v)), min(t1, max(u, v))
        if t0 > t1:
            return False
    return True


def _bb(shape) -> tuple:
    b = shape.bounding_box()
    return (b.min.X, b.min.Y, b.min.Z, b.max.X, b.max.Y, b.max.Z)


def _hull_half_width_m(y_station_mm: float) -> float:
    """The hull's inner half-width (m) at the ballast position, at the height of a point of the station frame
    (program.yaml: superellipse plan and section, less the wall; the station's centre is 1.1 m above the main deck)."""
    p = yaml.safe_load(PROGRAM.read_text())
    h = p["hull"]
    t = abs(BALLAST_Z_M) / (h["length_m"] / 2)
    sup = lambda ext, e: ext * (1 - min(t, 1.0) ** e) ** (1 / e)
    hw = sup(h["width_m"] / 2, h["plan_exponent"]) - h["wall_m"]
    hh = sup(h["height_m"] / 2, h["profile_exponent"]) - h["wall_m"]
    yc = (-h["height_m"] / 2 + h["deck_above_bottom_m"]) + 1.1 + y_station_mm / 1000.0           # in the hull-centre frame
    return hw * (1 - (abs(yc) / hh) ** h["section_exponent"]) ** (1 / h["section_exponent"])


def _pump_sweep_points(pump: Item) -> list[np.ndarray]:
    """The handle bar's corners at both ends of the stroke, in the station frame (from the entry's handle_tip_mm)."""
    tips = entry("hand_pump")["handle_tip_mm"]
    pts = []
    for key in ("up_yz", "down_yz"):
        y, z = tips[key]
        for dx in (-55.0, 55.0):
            for dy in (-13.0, 13.0):
                for dz in (-13.0, 13.0):
                    pts.append(pump.local_to_world((dx, y + dy, z + dz)))
    return pts


def checks(its: list[Item], parts: list[Solid], local: dict) -> dict:
    by = {i.name: i for i in its}
    # Size and the mount face.
    lo = [min(_bb(p.shape)[k] for p in parts) for k in range(3)]
    hi = [max(_bb(p.shape)[k] for p in parts) for k in (3, 4, 5)]
    all_lo = np.min([[*lo]] + [i.corners().min(axis=0) for i in its], axis=0)
    all_hi = np.max([[*hi]] + [i.corners().max(axis=0) for i in its], axis=0)
    along = float(all_hi[0] - all_lo[0])
    expect(along <= MAX_ALONG + 0.01, f"station at most {MAX_ALONG:.0f} mm along the hull ({along:.0f})")
    expect(all_lo[2] >= -0.01, f"nothing behind the mount face (Z=0): lowest Z {all_lo[2]:.1f}")
    expect(all_lo[1] >= FLOOR_Y - 0.01, f"nothing below the floor (Y {all_lo[1]:.0f})")
    mounts = mounts_record(its)
    expect(not mount.problems(SLUG, {"mounts": mounts}, _entry_of), "no instanced face coplanar with its host face")
    # Each item sits on the surface it was meant for.
    for i in its:
        if i.plane == "console":
            for c in i.corners():
                d = float(_N @ (c - FRONT_POINT))
                expect(d >= mount.MOUNT_GAP_MM - 0.01, f"{i.name} stays above the console top (corner {d:.1f} mm)")
            u = i.origin[0]
            expect(CX0 + 10.0 <= u + i.rect[0] and u + i.rect[2] <= CX1 - 10.0, f"{i.name} within the console's length")
        if i.plane == "wall" and i.name.endswith("Gauge"):
            x0, y0, _, x1, y1, _ = i.aabb
            g = GPLATE
            expect(g[0] - g[2] / 2 <= x0 and x1 <= g[0] + g[2] / 2 and g[1] - g[3] / 2 <= y0 and y1 <= g[1] + g[3] / 2,
                   f"{i.name} inside the gauge plate")
    for name in ("FloodWheel", "BlowWheel"):
        i = by[name]
        expect(abs(i.origin[1] - PIPE_Y) < 0.01, f"{name} sits on the ballast pipe")
        expect(PIPE_X0 + 100.0 <= i.origin[0] <= PIPE_X1 - 100.0, f"{name}'s pipe run lies within the ballast pipe")
    # Grab boxes apart, within each plane (a hand between neighbours).
    for plane in ("wall", "console"):
        grp = [i for i in its if i.plane == plane]
        for a in range(len(grp)):
            for b in range(a + 1, len(grp)):
                ra, rb = grp[a], grp[b]
                if plane == "wall":
                    gx = max(rb.origin[0] + rb.rect[0] - (ra.origin[0] + ra.rect[2]), ra.origin[0] + ra.rect[0] - (rb.origin[0] + rb.rect[2]))
                    gy = max(rb.origin[1] + rb.rect[1] - (ra.origin[1] + ra.rect[3]), ra.origin[1] + ra.rect[1] - (rb.origin[1] + rb.rect[3]))
                else:
                    gx = max(rb.origin[0] + rb.rect[0] - (ra.origin[0] + ra.rect[2]), ra.origin[0] + ra.rect[0] - (rb.origin[0] + rb.rect[2]))
                    gy = -1e9    # one row on the console: apart along the hull, or not at all
                    if abs(ra.origin[0] - rb.origin[0]) < 1e-6:
                        gy = 0.0
                expect(max(gx, gy) >= 10.0, f"{ra.name} and {rb.name} footprints at least 10 mm apart ({max(gx, gy):.0f})")
    pump = by["HandPump"]
    for i in its:
        if i is pump:
            continue
        a, b = i.aabb, pump.aabb
        sep = max(max(b[k] - a[k + 3], a[k] - b[k + 3]) for k in range(3))
        expect(sep >= 10.0, f"{i.name} and the pump's grab box at least 10 mm apart ({sep:.0f})")
    # Reach, from the shoulder, to every control at its farthest point.
    reach = {}
    for n in ("FloodWheel", "BlowWheel", "DropWeights", "BilgeSwitch"):
        d = float(max(np.linalg.norm(c - SHOULDER) for c in by[n].corners()))
        reach[n] = round(float(d), 1)
        expect(d <= REACH, f"{n} within reach {REACH:.0f} mm of the shoulder ({d:.0f})")
    d = float(max(np.linalg.norm(p - SHOULDER) for p in _pump_sweep_points(pump)))
    reach["HandPump"] = round(float(d), 1)
    expect(d <= REACH, f"the pump lever, at both ends of its stroke, within reach {REACH:.0f} mm of the shoulder ({d:.0f})")
    # The pump's sweep leaves the aisle: the sweep's depth into it, against the hull's width there.
    sweep = _pump_sweep_points(pump)
    depth = max(float(max(p[2] for p in sweep)), max(float(c[2]) for c in pump.corners((-80.0, -193.1, 0.0, 80.0, 193.1, 60.0))))
    width_m = 2 * min(_hull_half_width_m(min(float(p[1]) for p in sweep)), _hull_half_width_m(max(float(p[1]) for p in sweep)))
    aisle_min = yaml.safe_load(PROGRAM.read_text())["clearances"]["aisle_min_m"]
    free_m = width_m - depth / 1000.0
    expect(free_m >= aisle_min, f"the pump's whole sweep (to {depth:.0f} mm out) leaves {free_m:.2f} m of aisle across a "
                                f"{width_m:.2f} m hull; the program needs {aisle_min} m")
    station_free = width_m - float(all_hi[2]) / 1000.0
    expect(station_free >= aisle_min, f"the station (to {all_hi[2]:.0f} mm out) leaves {station_free:.2f} m of aisle; needs {aisle_min} m")
    # Sight lines from the eye to every gauge face and the lamp; nothing in front blocks them.
    targets = {}
    for n in ("TankGauge", "AirGauge", "BilgeGauge", "NoiseGauge"):
        targets[n] = (by[n], by[n].local_to_world((0.0, 0.0, 14.0)))
    sw = by["BilgeSwitch"]
    targets["BilgeSwitch lamp"] = (sw, sw.local_to_world((0.0, 52.0, 6.0)))
    blockers = [(i.name, i.aabb) for i in its] + [("rail", _bb(r)) for r in local["rails"]] + [("pipe", _bb(local["pipe"]))]
    for name, (owner, p) in targets.items():
        for bn, bx in blockers:
            if bn == owner.name:
                continue
            expect(not _seg_hits(EYE, p, bx), f"sight line from the eye to {name} blocked by {bn}")
        if owner.plane == "console":
            expect(float(_N @ (EYE - FRONT_POINT)) > 0 and float(_N @ (p - FRONT_POINT)) > 0,
                   f"{name} and the eye both above the console top")
        v = EYE - p
        ang = float(np.degrees(np.arccos(float(owner.normal @ v) / np.linalg.norm(v))))
        expect(ang <= 60.0, f"{name} faces the eye within 60 degrees ({ang:.0f})")
    return {"reach_mm": reach, "sight_lines": len(targets), "reach_limit_mm": REACH, "along_hull_mm": round(float(along), 1),
            "aisle_free_m": round(float(free_m), 3), "pump_sweep_depth_mm": round(float(depth), 1)}


def _entry_of(slug: str) -> dict:
    return entry(slug)


def mounts_record(its: list[Item]) -> list[dict]:
    return [mount.record(i.name, i.slug, i.offset, i.host) for i in its]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    parts, local = solids()
    its = items()
    figs = checks(its, parts, local)
    rep = export_solids_glb(parts, d / f"{SLUG}_body.glb", "EngineeringStationBody")
    s = Scene("EngineeringStation")
    s.node("Body", instance=rep["glb"])
    for i in its:
        xf = Xform(basis=i.basis, origin=tuple(float(v) / 1000 for v in i.origin))
        s.node(i.name, instance=i.scene, props={"transform": xf, **i.props})
    s.node("OperatorEye", props={"transform": Xform(origin=tuple(float(v) / 1000 for v in EYE))})
    s.write(d / f"{SLUG}.tscn")
    count: dict[str, int] = {}
    for i in its:
        count[i.slug] = count.get(i.slug, 0) + 1
    tris = rep["triangles"] + sum(entry(sl)["triangles"] * n for sl, n in count.items())
    expect(tris <= TRIANGLE_BUDGET, f"panel within the {TRIANGLE_BUDGET:,} triangle budget ({tris})")
    _cameras(d)
    write_entry(GROUP, SLUG, {
        "kind": "panel",
        "summary": "Engineering station: a ballast pipe along the hull at chest height with the FLOOD and BLOW valve wheels "
                   "and, between them, a plate with the TANK LEVEL and AIR REMAINING gauges; a low raked console beneath "
                   "with the guarded DROP WEIGHTS button, the BILGE PUMP switch and RUNNING lamp, the BILGE LEVEL gauge and "
                   "the noise repeater; the manual bilge pump's lever out of the console's end. Orange grab rails, "
                   "aluminium label plates, matte grey body.",
        "tags": ["panel", "engineering", "ballast", "flood", "blow", "valve", "drop weights", "bilge", "pump", "standing"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"wire": {
            "ballast": "FloodWheel and BlowWheel (Valve): bind SubController.flood_valve and blow_valve (and PilotSeat's)",
            "gauges": "TankGauge (tank_fraction), AirGauge (air_fraction), BilgeGauge (bilge_water_t, 0..8), NoiseGauge "
                      "(acoustics_readouts); all default to the sub_readouts group",
            "drop_weights": "DropWeights (DropWeightsButton: guard and button set; finds the sub controller by group)",
            "bilge": "BilgeSwitch (SwitchLever, its lamp follows it): bind to LeakSystem.pump; HandPump (HandPump, finds the "
                     "leak_system group)",
            "eye": "OperatorEye (the standing eye, 0.5 m out, 0.55 m above the station's centre)"}},
        "footprint_mm": [figs["along_hull_mm"], CONSOLE_D],
        "stand_out_mm": round(float(max(i.aabb[5] for i in its if i.name != "HandPump")), 1),
        "mount": "back on Z=0 against the port hull (X along the hull, Z out into the aisle); the station's centre stands "
                 "1.1 m above the floor (Y -1100 is the floor); the pump lever runs out of the +X end toward the bilge well",
        "operator_eye_m": [float(v) / 1000 for v in EYE],
        "reach_m": REACH / 1000,
        "mounts": mounts_record(its),
        "uses": list(USES),
        "triangles": tris,
        "triangles_by_part": {"body": rep["triangles"]},
        "checks": figs,
    })
    return {"slug": SLUG, "triangles": tris, "body": rep["triangles"]}


def _cameras(d) -> None:
    """Review cameras: the concept viewpoint, the operator's eye (white and red light), orthographic front and profile."""
    eye = [round(float(v) / 1000, 3) for v in EYE]
    look = [0.0, -0.05, 0.1]
    cams = [
        {"name": "concept_primary", "pos": [-1.1, 0.35, 2.4], "look_at": [0.1, -0.35, 0.0], "fov": 50.0},
        {"name": "operator_eye", "pos": eye, "look_at": look, "fov": 80.0},
        {"name": "operator_eye_red", "pos": eye, "look_at": look, "fov": 80.0, "light": "red"},
        {"name": "profile_right", "pos": [4.0, -0.3, 0.3], "look_at": [0.0, -0.3, 0.3], "ortho": 2.0},
        {"name": "front", "pos": [0.0, -0.3, 4.0], "look_at": [0.0, -0.3, 0.0], "ortho": 2.0},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
