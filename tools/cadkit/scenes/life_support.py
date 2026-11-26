"""life_support: the life-support wall unit (a station). Brief #424, concept life_support_primary.png.

Shaped like an arcade cabinet (side profile, top to bottom): a top block that overhangs the front; an upper panel
sloping down and back toward the wall, carrying the dials; a recessed vertical carriage face at standing eye level with
two rectangular pockets cut into it, side by side, each holding a cradle (a CanisterSlot with a scrubber canister, and a linear_gauge for its saturation beside each); a storage
shelf sloping like a console desk, tilted up toward the operator, bored with six 24-sided holes (two rows of three; the
canisters stand along the shelf's normal, tops just below the surface; four filled, two empty); and a vertical base
down to the plinth, standing further forward than the carriage face. Orange rails run down the cheeks. The operator
stands at +Z, back of the unit on Z=0.

Station-local solids (no behaviour, used once): the profile shell and cheeks, plinth, hazard band, rails,
cradles, the panel plate and hole rings. Everything lit, read or carried is a catalogue scene: scrubber_canister,
linear_gauge, gauge, guarded_toggle, indicator_lamp and the existing noise_gauge.
"""
import json
import math

import build123d as bd
import numpy as np
import yaml

from cadkit.solids import Solid, at, box, expect, export_solids_glb, prism
from cadkit.library import REPO, entry, note, out_dir, res, scene_path, write_entry
from cadkit.tscn import SName, Scene, Xform

SLUG, GROUP = "life_support", "stations"
USES: list[str] = ["scrubber_canister", "linear_gauge", "gauge", "guarded_toggle", "indicator_lamp"]
PROGRAM = REPO / "assets/models/vehicles/sub_interior/program.yaml"
TRIANGLE_BUDGET = 24000

# Body (mm). Back on Z=0, centred on X, floor at Y=0. D is the base's front face; the top block overhangs by OVERHANG.
W, D, H = 1000.0, 500.0, 2260.0
OVERHANG = 70.0
KICK_H, KICK_INSET = 130.0, 15.0            # the plinth: set back from the shell's face and sides
BAND_Y0, BAND_Y1 = 30.0, 100.0              # the hazard stripe on the plinth's face
BODY_CHAMFER = 6.0
CHEEK_T = 55.0                              # side walls that frame the carriage face and the panel, full depth
# The storage shelf: a slope from the base's front edge up and back to the carriage face.
SHELF_DEG, SHELF_L = 42.0, 390.0
SHELF_N = (math.cos(math.radians(SHELF_DEG)), math.sin(math.radians(SHELF_DEG)))   # outward normal (y, z)
ZC = D - SHELF_L * math.cos(math.radians(SHELF_DEG))     # the carriage face
YS1 = 1286.0                                              # where the shelf meets the carriage face (a riser below the pockets)
YB0 = YS1 - SHELF_L * math.sin(math.radians(SHELF_DEG))   # the base's top front edge
# The carriage face: two rectangular pockets cut into it at standing eye level (1650).
CARR_Y0, CARR_Y1 = 1472.0, 1860.0
POCKET_DEPTH = 180.0                        # each pocket is cut this far into the carriage face (canister 150 wide: +20%)
POCKET_Y1 = 1832.0                          # the pockets' tops (canister 300 tall: +20%): solid panel above and around
POCKET_CHAMFER = 22.0                       # the pocket's corners, as in the concept's alcove
ZP = ZC - POCKET_DEPTH                      # a pocket's back wall
POCKET_CX = (-170.0, 170.0)                 # pocket centres
POCKET_W = 180.0                            # canister 150 wide: +20%
# Cradle: a low seat with a back guard, open at the front. Centred in the pocket.
CRADLE_DX, CRADLE_R, CRADLE_H = 0.0, 82.0, 28.0
CRADLE_Z = ZP + 12.0 + 78.0                 # the canister's axis: guard (12 mm) then its radius and a little
GUARD_T, GUARD_H = 12.0, 150.0
GAUGE_X = 330.0                             # saturation bars on the housing, outside each pocket (mirrored), on the carriage face
# Rails: orange handles down the front edges of the cheeks, on stand-offs.
RAIL_X, RAIL_W, RAIL_Y0, RAIL_Y1, RAIL_OUT = 468.0, 30.0, 320.0, 1700.0, 42.0
# The upper panel: slopes down and back from the top block to the carriage face.
PANEL_DEG, PANEL_L = 45.0, 330.0
_pc, _ps = math.cos(math.radians(PANEL_DEG)), math.sin(math.radians(PANEL_DEG))
PANEL_O = np.array([0.0, CARR_Y1, ZC])                    # panel bottom edge, middle
PANEL_T = np.array([0.0, _ps, _pc])                       # up the slope
PANEL_N = np.array([0.0, -_pc, _ps])                      # outward (forward and down)
YT = CARR_Y1 + PANEL_L * _ps                              # the underside of the top block
PLATE_T = 8.0
GAUGE_BACK = 10.0                           # a dial's back is this far behind its origin (gauge entry): the origin stands this far off the plate
PANEL_HALF_W = W / 2 - CHEEK_T - 5.0
# Storage holes: on the shelf, (u across, s up the slope from the base's edge).
HOLE_R, HOLE_RING_R, HOLE_RING_H = 80.0, 88.0, 6.0        # bore, and the trim ring round its mouth
HOLE_COLS, HOLE_ROWS = (-200.0, 0.0, 200.0), (96.0, 280.0)
HOLE_SIDES = 24                             # round bores against the angular unit
TOP_RECESS = 15.0                           # a stored canister's top sits this far below the shelf surface
FILLED_HOLES = (0, 1, 2, 4)                 # holes (row-major) holding a canister on a new sub
# Instruments on the panel plate: (u across, v up the slope).
ROW_A, ROW_B = 230.0, 68.0
O2_AT, CO2_AT, RATE_AT, NOISE_AT = -310.0, -105.0, 105.0, 310.0
GAUGE_R, NOISE_R = 0.055, 0.055            # dial radii (m)
O2_ALARM_AT, CO2_ALARM_AT = -310.0, -105.0
# The fan switch: the upper-right corner of the storage shelf, (u across, s up the slope), with its run lamp beside it.
TOGGLE_U, TOGGLE_S, LAMP_U = 352.0, 300.0, 412.0
# The operator.
EYE = np.array([0.0, 1650.0, D + 150.0])
REACH_MM = 750.0
APERTURE_MIN_MM = 800.0                      # the aisle the unit must leave clear (program clearances)


def program() -> dict:
    return yaml.safe_load(PROGRAM.read_text())


def hull_half_width_m(z: float, y: float) -> float:
    h = program()["hull"]
    a, b, c = h["width_m"] / 2, h["length_m"] / 2, h["height_m"] / 2
    plan = (1 - abs(z / b) ** h["plan_exponent"]) ** (1 / h["plan_exponent"])
    sect = (1 - abs(y / c) ** h["section_exponent"]) ** (1 / h["section_exponent"])
    return a * plan * sect - h["wall_m"]


def _cradle_xyz(i: int) -> tuple[float, float, float]:
    """Slot origin of cradle i: the top of its seat, on the canister's axis."""
    return (POCKET_CX[i] + CRADLE_DX, CARR_Y0 + CRADLE_H, CRADLE_Z)


def _gauge_xyz(i: int) -> tuple[float, float, float]:
    """Origin of gauge i: the bar's bottom, on the carriage face beside pocket i, centred on eye level."""
    return ((-1.0, 1.0)[i] * GAUGE_X, EYE[1] - entry("linear_gauge")["footprint_mm"][1] / 2, ZC)


def _holes() -> list[tuple[float, float]]:
    """Storage hole centres (u across, s up the shelf from its lower edge), row-major from the lower row."""
    return [(u, s) for s in HOLE_ROWS for u in HOLE_COLS]


def _shelf_point(u: float, s: float) -> np.ndarray:
    """A point on the shelf surface: u across, s up the slope from the base's front edge."""
    return np.array([u, YB0 + s * SHELF_N[1], D - s * SHELF_N[0]])


def _shelf_normal() -> np.ndarray:
    return np.array([0.0, SHELF_N[0], SHELF_N[1]])


def _hole_base(u: float, s: float) -> np.ndarray:
    """A stored canister's base: its top (300 mm up its axis) sits TOP_RECESS below the surface."""
    return _shelf_point(u, s) - _shelf_normal() * (TOP_RECESS + entry("scrubber_canister")["stand_out_mm"])


def _slot_xform(base: np.ndarray) -> Xform:
    """A slot's frame for a canister along the shelf normal: X stays X, Y is the normal, Z completes it."""
    c, sn = SHELF_N
    return Xform.frame((1, 0, 0), (0, c, sn), (0, -sn, c), tuple(float(v) / 1000.0 for v in base))


def _shelf_xform(u: float, s: float, out: float = 0.0) -> Xform:
    """A frame on the shelf: +Z out of its surface, +Y up the slope."""
    o = _shelf_point(u, s) + _shelf_normal() * out
    return Xform.frame((1, 0, 0), (0, SHELF_N[1], -SHELF_N[0]), tuple(_shelf_normal()), tuple(float(v) / 1000.0 for v in o))


def _panel_xform(u: float, v: float, out: float = 0.0) -> Xform:
    """A frame on the panel: +Z out of the sloping face, +Y up the slope."""
    o = PANEL_O + PANEL_T * v + PANEL_N * out
    return Xform.frame((1, 0, 0), tuple(PANEL_T), tuple(PANEL_N), (u / 1000.0, float(o[1]) / 1000.0, float(o[2]) / 1000.0))


def _along(shape: bd.Shape, origin: np.ndarray, z_dir: np.ndarray) -> bd.Shape:
    """Move a shape built along +Z from Z=0 onto an axis: X stays X."""
    return shape.moved(bd.Location(bd.Plane(origin=tuple(float(v) for v in origin), x_dir=(1, 0, 0), z_dir=tuple(float(v) for v in z_dir))))


def _yz_extrude(pts: list[tuple[float, float]], x0: float, x1: float) -> bd.Part:
    """A polygon given as (y, z) points, extruded along X from x0 to x1 (made anticlockwise first, so it is +X)."""
    area = sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1]))
    if area < 0:
        pts = pts[::-1]
    out = at(bd.extrude(bd.Plane.YZ * bd.Polygon(*pts, align=None), amount=x1 - x0), x=x0)
    bb = out.bounding_box()
    expect(abs(bb.min.X - x0) < 0.01 and abs(bb.max.X - x1) < 0.01, f"profile spans x {x0}..{x1} ({bb.min.X:.1f}..{bb.max.X:.1f})")
    return out


def _profile() -> list[tuple[float, float]]:
    """The cabinet's side profile as (y, z), top block to base."""
    return [(KICK_H, 0.0), (KICK_H, D), (YB0, D), (YS1, ZC), (CARR_Y1, ZC), (YT, ZC + PANEL_L * _pc),
            (YT, D + OVERHANG), (H, D + OVERHANG), (H, 0.0)]


def _pocket_cutter() -> bd.Part:
    """A pocket's volume, from its back wall to a millimetre past the face, centred on X and Y, with chamfered corners."""
    w, h, c = POCKET_W / 2, (POCKET_Y1 - CARR_Y0) / 2, POCKET_CHAMFER
    pts = [(-w + c, -h), (w - c, -h), (w, -h + c), (w, h - c), (w - c, h), (-w + c, h), (-w, h - c), (-w, -h + c)]
    return bd.extrude(bd.Plane.XY * bd.Polygon(*pts, align=None), amount=POCKET_DEPTH + 1.0)


def solids() -> list[Solid]:
    shell = _yz_extrude(_profile(), -W / 2, W / 2)
    shell = bd.chamfer(shell.edges(), BODY_CHAMFER)
    # Cheeks: full-depth side walls beside the carriage face and the panel.
    for sx in (-1, 1):
        shell = shell + at(box(CHEEK_T, YT - YB0, D, chamfer_mm=BODY_CHAMFER), x=sx * (W / 2 - CHEEK_T / 2), y=(YB0 + YT) / 2)
    # Two rectangular pockets, side by side, cut into the carriage face; solid panel between and around them.
    for cx in POCKET_CX:
        shell = shell - at(_pocket_cutter(), x=cx, y=(CARR_Y0 + POCKET_Y1) / 2, z=ZP)
    nrm = _shelf_normal()
    bore = 330.0
    for u, s in _holes():
        shell = shell - _along(prism(HOLE_SIDES, HOLE_R, bore), _shelf_point(u, s) - nrm * (bore - 1.0), nrm)
    kick = at(box(W - 2 * KICK_INSET, KICK_H, D - 2 * KICK_INSET, chamfer_mm=6.0), y=KICK_H / 2, z=KICK_INSET)
    band = at(box(W - 2 * KICK_INSET - 60.0, BAND_Y1 - BAND_Y0, 4.0), y=(BAND_Y0 + BAND_Y1) / 2, z=D - KICK_INSET)
    out = [Solid(shell, "interior_panel"), Solid(kick, "trim_black"), Solid(band, "hazard_stripe")]
    # Rails: a bar, and two stand-offs back to the cheek.
    for sx in (-1, 1):
        bar = at(box(RAIL_W, RAIL_Y1 - RAIL_Y0, RAIL_W, chamfer_mm=5.0), x=sx * RAIL_X, y=(RAIL_Y0 + RAIL_Y1) / 2, z=D + RAIL_OUT - RAIL_W)
        out.append(Solid(bar, "control_interface"))
        for y in (RAIL_Y0 + 60.0, RAIL_Y1 - 60.0):
            out.append(Solid(at(box(RAIL_W - 8.0, 40.0, RAIL_OUT - RAIL_W + 2.0), x=sx * RAIL_X, y=y, z=D - 2.0), "control_grey"))
    # Each cradle, in its pocket: a seat on the pocket floor and a back guard against its back wall.
    for i in range(2):
        cx, cy, cz = _cradle_xyz(i)
        seat = at(prism(12, CRADLE_R, CRADLE_H, chamfer_top=4.0), x=cx, y=cy - CRADLE_H, z=cz, rx=-90.0)
        guard = at(box(2 * CRADLE_R - 20.0, GUARD_H, GUARD_T, chamfer_mm=3.0), x=cx, y=CARR_Y0 + GUARD_H / 2, z=ZP + GUARD_T / 2)
        out += [Solid(seat, "trim_black"), Solid(guard, "control_grey")]
    # The panel plate, on the sloping face.
    plate = _along(box(2 * PANEL_HALF_W, PANEL_L - 4.0, PLATE_T, chamfer_mm=3.0), PANEL_O + PANEL_T * (PANEL_L / 2) + PANEL_N * (PLATE_T / 2), PANEL_N)
    out.append(Solid(plate, "control_grey"))
    # A trim ring round each hole's mouth.
    for u, s in _holes():
        ring = prism(HOLE_SIDES, HOLE_RING_R, HOLE_RING_H) - prism(HOLE_SIDES, HOLE_R, HOLE_RING_H)
        out.append(Solid(_along(ring, _shelf_point(u, s) - nrm * 0.5, nrm), "trim_black"))
    return out


def _check(sol: list[Solid]) -> dict:
    allb = [s.shape.bounding_box() for s in sol]
    lo = [min(b.min.X for b in allb), min(b.min.Y for b in allb), min(b.min.Z for b in allb)]
    hi = [max(b.max.X for b in allb), max(b.max.Y for b in allb), max(b.max.Z for b in allb)]
    # Footprint and frame.
    expect(hi[0] - lo[0] <= 1000.0 + 1.0, f"unit {hi[0] - lo[0]:.0f} mm wide; the brief allows about 1000")
    expect(hi[2] - lo[2] <= D + OVERHANG + 1.0, f"unit {hi[2] - lo[2]:.0f} mm deep; the base is {D:.0f} and the top block overhangs {OVERHANG:.0f}")
    expect(RAIL_OUT + D <= D + OVERHANG, "rails stand under the top block's overhang")
    expect(abs(lo[1]) < 0.01, f"floor at Y=0, not {lo[1]:.2f}")
    expect(lo[2] >= -0.01, f"nothing behind the back face ({lo[2]:.1f} mm)")
    expect(abs(lo[0] + hi[0]) < 0.5, "centred on X")
    # The aisle: the unit stands against the port hull; the starboard unit across (the engineering panel) is 0.45 m deep.
    p = program()
    across = next(s for s in p["stations"] if s["id"] == "engineering")["footprint"][1]
    me = next(s for s in p["stations"] if s["id"] == "life_support")
    top = hull_half_width_m(me["z"], H / 1000.0 - 0.95)
    depth_full = hi[2]
    aisle = 2 * top - across - depth_full / 1000.0
    expect(aisle >= p["clearances"]["aisle_min_m"], f"aisle across the hull beside the unit {aisle:.2f} m >= {p['clearances']['aisle_min_m']} m")
    ft = me["footprint"]
    expect(W / 1000 <= ft[0] + 0.001 and D / 1000 <= ft[1] + 0.001, f"base within the program's {ft} m footprint")
    # The stack, top to bottom: block, panel, carriage face at eye level, shelf, base.
    expect(H - YT >= 100.0, f"the top block is {H - YT:.0f} mm tall")
    expect(ZC + PANEL_L * _pc <= D, "the panel's top edge is behind the base's front face")
    expect(ZC < D - 150.0, f"the carriage face is recessed {D - ZC:.0f} mm behind the base's front")
    expect(YB0 >= 1000.0 and YB0 < YS1, f"the base tops out at {YB0:.0f} mm and the shelf rises to {YS1:.0f}")
    can, gau = entry("scrubber_canister"), entry("linear_gauge")
    cw, ch = can["footprint_mm"][0], can["stand_out_mm"]
    gw, gh = gau["footprint_mm"]
    expect(gau["track_mm"]["bottom_y"] == 0.0, "linear_gauge's origin is its bar bottom")
    # The carriages are at crew eye level: the canister's middle within 50 mm of 1650.
    for i in range(2):
        cx, cy, cz = _cradle_xyz(i)
        gx, gy, gz = _gauge_xyz(i)
        px0, px1 = POCKET_CX[i] - POCKET_W / 2, POCKET_CX[i] + POCKET_W / 2
        expect(abs(cy + ch / 2 - EYE[1]) <= 50.0, f"canister {i}'s middle ({cy + ch / 2:.0f}) at crew eye level ({EYE[1]:.0f})")
        expect(cx - cw / 2 >= px0 + 5.0 and cx + cw / 2 <= px1 - 5.0, f"canister {i} inside pocket {i}")
        expect(POCKET_W <= 1.25 * cw and POCKET_Y1 - CARR_Y0 <= 1.25 * ch and POCKET_DEPTH <= 1.25 * cw,
               f"pocket {i} ({POCKET_W:.0f} x {POCKET_Y1 - CARR_Y0:.0f} x {POCKET_DEPTH:.0f}) about 20% larger than the {cw:.0f} x {ch:.0f} canister")
        expect(px0 >= -W / 2 + CHEEK_T and px1 <= W / 2 - CHEEK_T, f"pocket {i} between the cheeks")
        expect(cy + ch <= POCKET_Y1 - 30.0, f"canister {i} stands {cy + ch - CARR_Y0:.0f} mm in a pocket {POCKET_Y1 - CARR_Y0:.0f} mm tall, with room to lift")
        expect(cz + cw / 2 <= ZC, f"canister {i} sits wholly inside its pocket (front at {cz + cw / 2:.0f}, face at {ZC:.0f})")
        expect(cz + cw / 2 <= D - 60.0, f"canister {i} sits well back from the face (its front at {cz + cw / 2:.0f} of {D:.0f})")
        expect(cz + CRADLE_R <= ZC + 30.0, f"cradle {i}'s seat within its pocket")
        expect(cz - cw / 2 >= ZP + GUARD_T, f"canister {i} clear of the back guard")
        # the saturation bar is on the housing beside its pocket: the face, in view, between the pocket and the cheek
        out_edge = abs(gx) - gw / 2
        expect(abs(gz - ZC) < 0.01, f"saturation bar {i} on the carriage face, not in the pocket")
        expect(out_edge >= abs(POCKET_CX[i]) + POCKET_W / 2 + 20.0, f"saturation bar {i} {out_edge - abs(POCKET_CX[i]) - POCKET_W / 2:.0f} mm outside pocket {i}")
        expect(abs(gx) + gw / 2 <= W / 2 - CHEEK_T - 20.0, f"saturation bar {i} clear of the cheek")
        expect(gy >= YS1 + 20.0 and gy + gh <= CARR_Y1 - 20.0, f"saturation bar {i} on the solid face, between the shelf and the panel")
        expect(gx * POCKET_CX[i] > 0, f"saturation bar {i} on pocket {i}'s own side")
        expect(CRADLE_R * math.cos(math.pi / 12) >= cw / 2, f"cradle {i}'s seat holds the {cw:.0f} mm canister")
        pts = [np.array([cx + dx, cy + dy, cz + dz]) for dx in (-cw / 2, cw / 2) for dy in (0.0, ch) for dz in (-cw / 2, cw / 2)]
        pts += [np.array([gx + dx, gy + dy, gz + dz]) for dx in (-gw / 2, gw / 2) for dy in (0.0, gh) for dz in (0.0, gau["stand_out_mm"])]
        far = max(float(np.linalg.norm(q - EYE)) for q in pts)
        expect(far <= REACH_MM, f"cradle {i} and gauge {i} within {REACH_MM:.0f} mm of the standing eye ({far:.0f} mm)")
    expect(POCKET_CX[1] - POCKET_CX[0] - POCKET_W >= 60.0, "solid panel between the pockets")
    expect(POCKET_CHAMFER >= 10.0 and 2 * POCKET_CHAMFER < POCKET_W, f"pocket corners chamfered {POCKET_CHAMFER:.0f} mm")
    expect(W / 2 - CHEEK_T - (POCKET_CX[1] + POCKET_W / 2) >= 10.0 and ZP >= 20.0 and CARR_Y1 - POCKET_Y1 >= 20.0, "solid panel around the pockets")
    figures = _check_panel(sol)
    for sx in (-1, 1):
        expect(abs(sx * RAIL_X) - RAIL_W / 2 >= W / 2 - CHEEK_T, "rails on the cheeks, clear of the pockets")
        expect(abs(sx * RAIL_X) + RAIL_W / 2 <= W / 2, "rails inside the unit's width")
    expect(RAIL_Y1 <= YT and RAIL_Y0 >= KICK_H, "rails within the cheeks height")
    return {"aisle_m": round(aisle, 3), **figures}


def _disc_clear(a: tuple[float, float, float], b: tuple[float, float, float], what: str) -> None:
    """Two round things (x, y, radius) on a face do not overlap, with 6 mm between."""
    gap = math.hypot(a[0] - b[0], a[1] - b[1]) - a[2] - b[2]
    expect(gap >= 6.0, f"{what}: {gap:.0f} mm apart")


def _check_panel(sol: list[Solid]) -> dict:
    """The shelf's holes and the upper panel's instruments fit, do not overlap, and are in reach."""
    gau, can = entry("gauge"), entry("scrubber_canister")
    tog, lamp = entry("guarded_toggle"), entry("indicator_lamp")
    bez, pb, ph = gau["extent_radii"]["bezel"], gau["extent_radii"]["plate_bottom"], gau["extent_radii"]["plate_half_width"]
    # Storage: six holes in two rows of three, inside the shelf, clear of each other and of the cheeks.
    holes = _holes()
    expect(len(holes) == 6 and len(set(s for _, s in holes)) == 2, "six storage holes in two rows of three")
    expect(HOLE_SIDES >= 24, f"bores and rings are {HOLE_SIDES}-sided")
    for u, s in holes:
        expect(abs(u) + HOLE_RING_R <= W / 2 - CHEEK_T - 8.0, f"hole at u={u:.0f} between the cheeks")
        expect(8.0 <= s - HOLE_RING_R and s + HOLE_RING_R <= SHELF_L - 8.0, f"hole at s={s:.0f} on the shelf ({SHELF_L:.0f} mm long)")
    for i, a in enumerate(holes):
        for b in holes[i + 1:]:
            _disc_clear((*a, HOLE_RING_R), (*b, HOLE_RING_R), "storage holes")
    expect(HOLE_R >= can["footprint_mm"][0] / 2 + 5.0, f"a canister ({can['footprint_mm'][0]:.0f} mm) goes into a {2 * HOLE_R:.0f} mm hole with play")
    # A bore stays inside the unit: every point of its far end, from the back face and the plinth.
    nrm, tan = _shelf_normal(), np.array([0.0, -SHELF_N[1], SHELF_N[0]])
    low = 1e9
    back = 1e9
    for u, s in holes:
        for ang in range(0, 360, 15):
            q = _hole_base(u, s) - nrm * 10.0 + tan * HOLE_R * math.cos(math.radians(ang))
            low, back = min(low, q[1]), min(back, q[2])
    expect(back >= 10.0, f"every bore stays {back:.0f} mm in front of the back face")
    expect(low >= KICK_H + 20.0, f"every bore ends {low - KICK_H:.0f} mm above the plinth")
    # A canister lifts out along the shelf normal without touching the carriage face above the shelf.
    for u, s in holes:
        for t in range(0, 341, 10):
            axis = _hole_base(u, s) + nrm * t
            for off in (-can["footprint_mm"][0] / 2, can["footprint_mm"][0] / 2):
                q = axis + tan * off
                hit = q[1] >= YS1 and q[2] < ZC - 0.5
                expect(not hit, f"the canister in hole at u={u:.0f}, s={s:.0f} lifts out clear of the carriage face (blocked at {t} mm)")
    expect(TOP_RECESS >= 5.0, "a stored canister shows its top just below the shelf surface")
    # The panel: plate bounds and dial layout, in plate coordinates (u, v up the slope).
    r, rn = GAUGE_R * 1000.0, NOISE_R * 1000.0
    out_dial = PLATE_T + GAUGE_BACK
    expect(out_dial - GAUGE_BACK >= PLATE_T, f"dials' backs ({out_dial - GAUGE_BACK:.0f} mm out) sit on the plate face ({PLATE_T:.0f} mm), not in it")
    dials = {"O2 dial": (O2_AT, ROW_A, bez * r), "CO2 level dial": (CO2_AT, ROW_A, bez * r),
             "CO2 rate dial": (RATE_AT, ROW_A, bez * r), "noise dial": (NOISE_AT, ROW_A, bez * rn)}
    tw, th = tog["footprint_mm"]
    lw = lamp["footprint_mm"][0] / 2
    lamps = {"O2 alarm lamp": (O2_ALARM_AT, ROW_B, lw), "CO2 alarm lamp": (CO2_ALARM_AT, ROW_B, lw)}
    expect(O2_ALARM_AT == O2_AT and CO2_ALARM_AT == CO2_AT, "each alarm lamp directly under its gauge")
    items = {**dials, **lamps}
    names = list(items)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            _disc_clear(items[a], items[b], f"{a} and {b}")
    for name, (x, y, rr) in dials.items():
        expect(-PANEL_HALF_W + 5.0 <= x - rr and x + rr <= PANEL_HALF_W - 5.0, f"{name} inside the panel plate")
        expect(y + rr <= PANEL_L - 8.0, f"{name} below the plate's top edge")
    for name, (x, y, rr) in lamps.items():
        expect(-PANEL_HALF_W + 5.0 <= x - rr and x + rr <= PANEL_HALF_W - 5.0 and y - rr >= 8.0, f"{name} inside the plate")
    for name, (x, y, rr) in dials.items():
        # a dial's title plate (below it) clears the lamp or the toggle under it
        low_v = y - pb * (rn if name == "noise dial" else r)
        for ln, (lx, ly, lr) in lamps.items():
            if abs(lx - x) < ph * r + lr:
                expect(low_v >= ly + lr + 4.0, f"{name}'s title plate ({low_v:.0f}) clear of the {ln}")
    # Reach from the standing eye: the fan toggle and every dial, and the stored canisters' tops.
    def at_panel(u: float, v: float, out: float) -> np.ndarray:
        return np.array([u, *(PANEL_O + PANEL_T * v + PANEL_N * (PLATE_T + out))[1:]])

    # The fan toggle and its lamp on the shelf's upper-right corner: on the shelf, clear of the holes and the cheek.
    expect(TOGGLE_U - tw / 2 >= max(c for c, _ in holes) + HOLE_RING_R + 10.0, "fan toggle clear of the storage holes")
    expect(LAMP_U + lw <= W / 2 - CHEEK_T - 8.0 and (LAMP_U - lw) - (TOGGLE_U + tw / 2) >= 6.0, "run lamp beside the toggle, clear of the cheek")
    expect(TOGGLE_S + th / 2 <= SHELF_L - 8.0 and TOGGLE_S - th / 2 >= max(s for _, s in holes) - HOLE_RING_R, "fan toggle in the shelf's upper corner")
    expect(TOGGLE_S >= SHELF_L / 2 and TOGGLE_U > 0, "fan toggle in the upper-right corner of the shelf")
    far_tog = max(float(np.linalg.norm(_shelf_point(TOGGLE_U + dx, TOGGLE_S + dy)
                                       + _shelf_normal() * tog["stand_out_mm"] - EYE))
                  for dx in (-tw / 2, tw / 2) for dy in (-th / 2, th / 2))
    expect(far_tog <= REACH_MM, f"the fan toggle within {REACH_MM:.0f} mm of the standing eye ({far_tog:.0f} mm)")
    far_dial = max(float(np.linalg.norm(at_panel(x + dx, y + dy, GAUGE_BACK) - EYE)) for x, y, rr in dials.values() for dx in (-rr, rr) for dy in (-rr, rr))
    expect(far_dial <= REACH_MM, f"every dial within {REACH_MM:.0f} mm of the standing eye ({far_dial:.0f} mm)")
    far_top = 0.0
    top_y = 0.0
    for u, s in holes:
        for ang in range(0, 360, 45):
            q = _shelf_point(u, s) - nrm * TOP_RECESS + tan * HOLE_R * math.cos(math.radians(ang)) + np.array([HOLE_R * math.sin(math.radians(ang)), 0.0, 0.0])
            far_top = max(far_top, float(np.linalg.norm(q - EYE)))
            top_y = max(top_y, float(q[1]))
    expect(far_top <= REACH_MM, f"every storage top within {REACH_MM:.0f} mm of the standing eye ({far_top:.0f} mm)")
    expect(top_y <= EYE[1] + 400.0, f"the highest storage top ({top_y:.0f} mm) reachable at head height")
    return {"toggle_reach_mm": round(far_tog), "storage_reach_mm": round(far_top), "dial_reach_mm": round(far_dial)}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    sol = solids()
    figures = _check(sol)
    rep = export_solids_glb(sol, d / f"{SLUG}_body.glb", "LifeSupportBody", tol_mm=0.5, ang=0.6)
    s = Scene("LifeSupport", type_="Node3D")
    s.node("Body", instance=rep["glb"])
    sh = s.sub("BoxShape3D", "unit", {"size": (W / 1000, H / 1000, (D + OVERHANG) / 1000)})
    s.node("Collision", type_="StaticBody3D")
    s.node("Unit", parent="Collision", type_="CollisionShape3D",
           props={"transform": Xform(origin=(0, H / 2000, (D + OVERHANG) / 2000)), "shape": sh})
    s.node("OperatorPoint", props={"transform": Xform(origin=(0, 0, (D + 150.0) / 1000))})
    s.node("OperatorEye", props={"transform": Xform(origin=tuple(EYE / 1000))})
    s.node("UpperPanelAnchor", props={"transform": _panel_xform(0.0, 0.0, PLATE_T)})
    names = ["A", "B"]
    for i, n in enumerate(names):
        x, y, z = (v / 1000 for v in _cradle_xyz(i))
        s.node(f"Cradle{n}", script="res://src/interact/canister_slot.gd", props={"transform": Xform(origin=(x, y, z))})
        s.node(f"Canister{n}", instance=scene_path("scrubber_canister"), props={"transform": Xform(origin=(x, y, z))})
        gx, gy, gz = (v / 1000 for v in _gauge_xyz(i))
        s.node(f"Saturation{n}", instance=scene_path("linear_gauge"),
               props={"transform": Xform(origin=(gx, gy, gz)), "source_group": SName("life_support_readouts"),
                      "readout": SName(f"saturation_{n.lower()}"), "max_value": 1.0})
    # Storage: a slot per hole, along the shelf normal, a canister in the filled ones.
    for k, (u, sl) in enumerate(_holes()):
        xf = _slot_xform(_hole_base(u, sl))
        s.node(f"Storage{k + 1}", script="res://src/interact/canister_slot.gd", props={"transform": xf})
        if k in FILLED_HOLES:
            s.node(f"Stored{k + 1}", instance=scene_path("scrubber_canister"), props={"transform": xf})
    # Instruments, on the sloping panel plate.
    ls = SName("life_support_readouts")
    def dial(name: str, u: float, title: str, r: float, **kw) -> None:
        s.node(name, instance=scene_path("gauge"), props={"transform": _panel_xform(u, ROW_A, PLATE_T + GAUGE_BACK), "radius": r, "title": title,
                                                          "source_group": ls, **kw})
    dial("O2Gauge", O2_AT, "O2", GAUGE_R, readout=SName("o2_level"), min_value=0.0, max_value=1.0)
    dial("Co2LevelGauge", CO2_AT, "CO2", GAUGE_R, readout=SName("co2_level"), min_value=0.0, max_value=1.0)
    dial("Co2RateGauge", RATE_AT, "CO2 RATE", GAUGE_R, readout=SName("co2_capacity_rate"), readout_b=SName("co2_production_rate"),
         min_value=0.0, max_value=1.0)
    s.node("O2AlarmLamp", instance=scene_path("indicator_lamp"), props={"transform": _panel_xform(O2_ALARM_AT, ROW_B, PLATE_T)})
    s.node("Co2AlarmLamp", instance=scene_path("indicator_lamp"), props={"transform": _panel_xform(CO2_ALARM_AT, ROW_B, PLATE_T)})
    s.node("FanToggle", instance=scene_path("guarded_toggle"),
           props={"transform": _shelf_xform(TOGGLE_U, TOGGLE_S), "label": "FANS", "initial_value": 1.0})
    s.node("FanLamp", instance=scene_path("indicator_lamp"), props={"transform": _shelf_xform(LAMP_U, TOGGLE_S)})
    s.node("NoiseRepeater", instance="res://src/noise/noise_gauge.tscn",
           props={"transform": _panel_xform(NOISE_AT, ROW_A, PLATE_T + GAUGE_BACK), "radius": NOISE_R})
    s.write(d / f"{SLUG}.tscn")
    _cameras(d)
    n_can = 2 + len(FILLED_HOLES)
    tris = (rep["triangles"] + n_can * entry("scrubber_canister")["triangles"] + 2 * entry("linear_gauge")["triangles"]
            + 4 * entry("gauge")["triangles"] + entry("guarded_toggle")["triangles"] + 3 * entry("indicator_lamp")["triangles"])
    expect(tris <= TRIANGLE_BUDGET, f"station within the {TRIANGLE_BUDGET:,} triangle budget ({tris})")
    write_entry(GROUP, SLUG, {
        "kind": "station",
        "summary": "Life-support wall unit shaped like an arcade cabinet: a top block overhanging the front, a sloping upper "
                   "panel (O2, CO2 level, CO2 rate with two needles, noise repeater, O2 and CO2 alarm lamps under their gauges), "
                   "a recessed carriage face at eye level with two small chamfered pockets (each with a cradle and scrubber canister, "
                   "a linear saturation gauge on the housing beside it), a sloped console-desk shelf with six round "
                   "storage holes (canisters inside, tops showing) and the guarded fan toggle (on by default) with its run lamp in its upper-right corner, and a vertical base on a hazard-striped plinth. The operator stands.",
        "tags": ["station", "life support", "scrubber", "canister", "cradle", "storage", "o2", "co2", "wall unit", "standing"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"wire": {"cradles": "CradleA, CradleB (CanisterSlot; call try_seat on CanisterA, CanisterB)",
                               "gauges": "SaturationA, SaturationB (on the housing beside each pocket) read life_support_readouts: saturation_a, saturation_b (0..1)",
                               "storage": "Storage1..Storage6 (CanisterSlot along the sloped shelf's normal, lower row then upper row; Stored1,2,3,5 hold a canister, 4 and 6 are empty)",
                               "o2": "O2Gauge reads life_support_readouts: o2_level (0..1)",
                               "co2_level": "Co2LevelGauge reads life_support_readouts: co2_level (0..1)",
                               "co2_rate": "Co2RateGauge reads life_support_readouts: co2_capacity_rate, co2_production_rate (0..1, needle B is production)",
                               "alarms": "O2AlarmLamp, Co2AlarmLamp (IndicatorLamp)",
                               "fans": "FanToggle (SwitchLever, value_changed, initial_value 1: on; on the shelf's upper-right corner) with FanLamp (IndicatorLamp) beside it",
                               "noise_repeater": "NoiseRepeater",
                               "upper_panel": "UpperPanelAnchor (bottom middle of the sloping panel plate, on its face; +Z out of the face, +Y up the slope)",
                               "standing_eye": "OperatorEye"}},
        "footprint_mm": [W, D + OVERHANG],
        "stand_out_mm": D + OVERHANG,   # the top block; the rails reach D + 42
        "mount": "floor at Y=0, back against the hull on Z=0, centred on X, operator standing at +Z facing -Z",
        "uses": list(USES),
        "triangles": tris,
        "triangle_budget": TRIANGLE_BUDGET,   # approved by the look gate (round 1): the round canisters are costly
        "triangles_by_part": {"body": rep["triangles"]},
        "checks": figures,
    })
    return {"slug": SLUG, "triangles": tris, "body": rep["triangles"]}


def _cameras(d) -> None:
    """Review cameras: the concept's three viewpoints, the operator's eye (white and red light), orthographic profile and front."""
    eye = [round(v / 1000, 3) for v in EYE]
    cams = [
        {"name": "concept_swap_view", "pos": [-0.9, 1.5, 2.0], "look_at": [0.1, 1.45, 0.3], "fov": 62.0},
        {"name": "concept_canister_pair", "pos": [0.0, 1.65, 1.3], "look_at": [0.0, 1.65, 0.3], "fov": 40.0},
        {"name": "concept_storage_tops", "pos": [0.0, 1.95, 1.0], "look_at": [0.0, 1.3, 0.35], "fov": 45.0},
        {"name": "operator_eye", "pos": eye, "look_at": [0.0, 1.7, 0.2], "fov": 75.0},
        {"name": "operator_eye_red", "pos": eye, "look_at": [0.0, 1.7, 0.2], "fov": 75.0, "light": "red"},
        {"name": "profile_right", "pos": [3.5, 1.2, 0.3], "look_at": [0.0, 1.2, 0.3], "ortho": 2.7},
        {"name": "front", "pos": [0.0, 1.2, 4.0], "look_at": [0.0, 1.2, 0.0], "ortho": 2.7},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
