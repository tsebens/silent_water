"""life_support: the life-support wall unit (a station). Brief #424, concept life_support_primary.png.

A tall grey body shell on a hazard-striped plinth, orange handle rails down both front edges, and a chest-height
alcove: two chamfered pockets, each with an open cradle for a scrubber canister (a CanisterSlot, the canister standing
in it) and a linear_gauge for that canister's saturation beside it. The face above the alcove is left blank for the
upper panel: two raised plates, one with six storage holes (two rows of three, bored into the shell, four holding a
canister top-out as on a new sub, two empty) and one with the O2 gauge, the CO2 rate gauge (two needles), the fan
toggle with its run lamp and the noise repeater. The operator stands at +Z, back of the unit on Z=0.

Station-local solids (no behaviour, used once): shell, plinth, hazard band, rails, cradles, panel plates and hole
rings. Everything lit, read or carried is a catalogue scene: scrubber_canister, linear_gauge, gauge, guarded_toggle,
indicator_lamp and the existing noise_gauge.
"""
import json
import math

import build123d as bd
import numpy as np
import yaml

from cadkit.solids import Solid, at, bbox_mm, box, expect, export_solids_glb, prism
from cadkit.library import REPO, entry, note, out_dir, res, scene_path, write_entry
from cadkit.tscn import SName, Scene, Xform

SLUG, GROUP = "life_support", "stations"
USES: list[str] = ["scrubber_canister", "linear_gauge", "gauge", "guarded_toggle", "indicator_lamp"]
PROGRAM = REPO / "assets/models/vehicles/sub_interior/program.yaml"

# Body (mm). Back on Z=0, centred on X, floor at Y=0.
W, D, H = 1000.0, 500.0, 2100.0
KICK_H, KICK_INSET = 130.0, 15.0            # the plinth: set back from the shell's face and sides
BAND_Y0, BAND_Y1 = 30.0, 100.0              # the hazard stripe on the plinth's face
BODY_CHAMFER = 12.0
# The alcove: two pockets cut into the front, chest height.
POCKET_CX = (-240.0, 240.0)                 # pocket centres
POCKET_W, POCKET_Y0, POCKET_Y1, POCKET_BACK_Z = 400.0, 1160.0, 1560.0, 240.0
POCKET_BEVEL = 14.0                         # the chamfer round the opening
# Cradle: a low seat with a back guard, open at the front. Offsets are from the pocket's centre.
CRADLE_DX, CRADLE_R, CRADLE_H = -60.0, 98.0, 28.0
CRADLE_Z = POCKET_BACK_Z + 20.0 + 80.0      # the canister's axis: guard (20 mm) then its radius and a little
GUARD_T, GUARD_H = 20.0, 170.0
# Gauge beside its cradle, on the pocket's back wall.
GAUGE_DX = 140.0
# Rails: orange handles down the front edges, on stand-offs.
RAIL_X, RAIL_W, RAIL_Y0, RAIL_Y1, RAIL_OUT = 468.0, 30.0, 320.0, 1560.0, 42.0
# The upper panel: raised plates on the face above the alcove.
PLATE_T = 8.0
STORE_PLATE = (-450.0, 170.0)               # x range of the storage plate
INSTR_PLATE = (185.0, 452.0)                # x range of the instrument plate
PLATE_Y0, PLATE_Y1 = 1585.0, 2025.0
HOLE_R, HOLE_RING_R, HOLE_RING_H = 85.0, 95.0, 6.0   # bore, and the trim ring round its mouth
HOLE_COLS, HOLE_ROWS = (-340.0, -140.0, 60.0), (1696.0, 1900.0)
HOLE_SIDES = 12                             # the bores and rings are 12-gons: the triangle budget
TOP_RECESS = 15.0                           # a stored canister's top sits this far behind the plate face
FILLED_HOLES = (0, 1, 2, 4)                 # holes (row-major) holding a canister on a new sub; the concept shows four of six
O2_AT, CO2_AT, GAUGE_R, GAUGE_Y = 255.0, 385.0, 0.055, 1930.0   # dial centres (mm) and radius (m)
TOGGLE_AT, LAMP_AT, NOISE_AT, NOISE_R, ROW2_Y = 222.0, 285.0, 385.0, 0.05, 1685.0
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


def _pocket_cutter(cx: float) -> bd.Shape:
    """The opening: a box into the front, flared at the mouth by a 45 degree bevel."""
    ph = POCKET_Y1 - POCKET_Y0
    inner = at(box(POCKET_W, ph, D - POCKET_BACK_Z), x=cx, y=(POCKET_Y0 + POCKET_Y1) / 2, z=POCKET_BACK_Z)
    flare = bd.extrude(
        bd.Plane(origin=(cx, (POCKET_Y0 + POCKET_Y1) / 2, D - POCKET_BEVEL), z_dir=(0, 0, 1))
        * bd.Rectangle(POCKET_W, ph),
        amount=POCKET_BEVEL + 1.0, taper=-45.0)
    return inner + flare


def _cradle_xyz(i: int) -> tuple[float, float, float]:
    """Slot origin of cradle i: the top of its seat, on the canister's axis."""
    return (POCKET_CX[i] + CRADLE_DX, POCKET_Y0 + CRADLE_H, CRADLE_Z)


def _gauge_xyz(i: int) -> tuple[float, float, float]:
    """Origin of gauge i: the bar's bottom, on the pocket's back wall."""
    return (POCKET_CX[i] + GAUGE_DX, POCKET_Y0 + 100.0, POCKET_BACK_Z)


def _cyl(r: float, h: float) -> bd.Shape:
    """A low-poly round bar (HOLE_SIDES corners) along +Z from Z=0 to h."""
    return prism(HOLE_SIDES, r, h)


def _holes() -> list[tuple[float, float]]:
    """Storage hole centres (x, y), row-major from the lower row."""
    return [(x, y) for y in HOLE_ROWS for x in HOLE_COLS]


def _hole_base_z() -> float:
    """Z of a stored canister's base: its top (300 mm up its axis) sits TOP_RECESS behind the plate face."""
    return D + PLATE_T - TOP_RECESS - entry("scrubber_canister")["stand_out_mm"]


def _slot_xform(x: float, y: float, z: float) -> Xform:
    """A slot lying along +Z (its +Y toward the operator): X stays X, Y turns to Z, Z turns to -Y."""
    return Xform.frame((1, 0, 0), (0, 0, 1), (0, -1, 0), (x, y, z))


def solids() -> list[Solid]:
    shell = at(box(W, H - KICK_H, D, chamfer_mm=BODY_CHAMFER), y=KICK_H + (H - KICK_H) / 2)
    for cx in POCKET_CX:
        shell = shell - _pocket_cutter(cx)
    for hx, hy in _holes():
        shell = shell - at(_cyl(HOLE_R, D + 1.0 - (_hole_base_z() - 6.0)), x=hx, y=hy, z=_hole_base_z() - 6.0)
    kick = at(box(W - 2 * KICK_INSET, KICK_H, D - 2 * KICK_INSET, chamfer_mm=6.0), y=KICK_H / 2, z=KICK_INSET)
    band = at(box(W - 2 * KICK_INSET - 60.0, BAND_Y1 - BAND_Y0, 4.0), y=(BAND_Y0 + BAND_Y1) / 2, z=D - KICK_INSET)
    out = [Solid(shell, "interior_panel"), Solid(kick, "trim_black"), Solid(band, "hazard_stripe")]
    # Rails: a bar, and two stand-offs back to the shell.
    for sx in (-1, 1):
        bar = at(box(RAIL_W, RAIL_Y1 - RAIL_Y0, RAIL_W, chamfer_mm=5.0), x=sx * RAIL_X, y=(RAIL_Y0 + RAIL_Y1) / 2, z=D + RAIL_OUT - RAIL_W)
        out.append(Solid(bar, "control_interface"))
        for y in (RAIL_Y0 + 60.0, RAIL_Y1 - 60.0):
            out.append(Solid(at(box(RAIL_W - 8.0, 40.0, RAIL_OUT - RAIL_W + 2.0), x=sx * RAIL_X, y=y, z=D - 2.0), "control_grey"))
    # Cradles: the seat (a prism stood up from Z-up into Y-up) and a back guard against the pocket wall.
    for i in range(2):
        cx, cy, cz = _cradle_xyz(i)
        seat = at(prism(12, CRADLE_R, CRADLE_H, chamfer_top=4.0), x=cx, y=cy - CRADLE_H, z=cz, rx=-90.0)
        guard = at(box(2 * CRADLE_R - 20.0, GUARD_H, GUARD_T, chamfer_mm=3.0), x=cx, y=POCKET_Y0 + GUARD_H / 2, z=POCKET_BACK_Z)
        out += [Solid(seat, "trim_black"), Solid(guard, "control_grey")]
    # The upper panel: two raised plates (the storage plate pierced by the six holes) and a trim ring round each hole.
    for x0, x1 in (STORE_PLATE, INSTR_PLATE):
        plate = at(box(x1 - x0, PLATE_Y1 - PLATE_Y0, PLATE_T, chamfer_mm=3.0), x=(x0 + x1) / 2, y=(PLATE_Y0 + PLATE_Y1) / 2, z=D)
        if x0 == STORE_PLATE[0]:
            for hx, hy in _holes():
                plate = plate - at(_cyl(HOLE_R, PLATE_T + 2.0), x=hx, y=hy, z=D - 1.0)
        out.append(Solid(plate, "control_grey"))
    for hx, hy in _holes():
        ring = _cyl(HOLE_RING_R, HOLE_RING_H) - _cyl(HOLE_R, HOLE_RING_H)
        out.append(Solid(at(ring, x=hx, y=hy, z=D + PLATE_T), "trim_black"))
    return out


def _check(sol: list[Solid]) -> dict:
    allb = [s.shape.bounding_box() for s in sol]
    lo = [min(b.min.X for b in allb), min(b.min.Y for b in allb), min(b.min.Z for b in allb)]
    hi = [max(b.max.X for b in allb), max(b.max.Y for b in allb), max(b.max.Z for b in allb)]
    # Footprint and frame.
    expect(hi[0] - lo[0] <= 1000.0 + 1.0, f"unit {hi[0] - lo[0]:.0f} mm wide; the brief allows about 1000")
    expect(hi[2] - lo[2] <= 500.0 + RAIL_OUT, f"unit {hi[2] - lo[2]:.0f} mm deep; the brief allows about 500 (rails stand {RAIL_OUT:.0f} proud)")
    expect(abs(lo[1]) < 0.01, f"floor at Y=0, not {lo[1]:.2f}")
    expect(lo[2] >= -0.01, f"nothing behind the back face ({lo[2]:.1f} mm)")
    expect(abs(lo[0] + hi[0]) < 0.5, "centred on X")
    # The aisle: the unit stands against the port hull; the starboard unit across (the engineering panel) is 0.45 m deep.
    p = program()
    across = next(s for s in p["stations"] if s["id"] == "engineering")["footprint"][1]
    me = next(s for s in p["stations"] if s["id"] == "life_support")
    top = hull_half_width_m(me["z"], H / 1000.0 - 0.95)
    tog = entry("guarded_toggle")
    depth_full = max(hi[2], D + PLATE_T + tog["stand_out_mm"])     # the toggle is the deepest thing on the unit
    expect(depth_full <= D + 70.0, f"unit with the toggle {depth_full:.0f} mm deep; about 0.5 m plus the 8 mm plate and a 56 mm toggle")
    aisle = 2 * top - across - depth_full / 1000.0
    expect(aisle >= p["clearances"]["aisle_min_m"], f"aisle across the hull beside the unit {aisle:.2f} m >= {p['clearances']['aisle_min_m']} m")
    ft = me["footprint"]
    expect(W / 1000 <= ft[0] + 0.001 and D / 1000 <= ft[1] + 0.001, f"shell within the program's {ft} m footprint")
    # What the cradles and gauges are made of.
    can, gau = entry("scrubber_canister"), entry("linear_gauge")
    cw, ch = can["footprint_mm"][0], can["stand_out_mm"]
    gw, gh = gau["footprint_mm"]
    expect(gau["track_mm"]["bottom_y"] == 0.0, "linear_gauge's origin is its bar bottom")
    for i in range(2):
        cx, cy, cz = _cradle_xyz(i)
        gx, gy, gz = _gauge_xyz(i)
        px0, px1 = POCKET_CX[i] - POCKET_W / 2, POCKET_CX[i] + POCKET_W / 2
        # inside the pocket
        expect(cx - cw / 2 >= px0 + 10.0 and gx + gw / 2 <= px1 - 10.0, f"cradle {i} and gauge {i} inside pocket {i}")
        expect(cy + ch <= POCKET_Y1 - 40.0, f"canister {i} stands {cy + ch - POCKET_Y0:.0f} mm in a pocket {POCKET_Y1 - POCKET_Y0:.0f} mm tall, with room to lift")
        expect(cz + cw / 2 <= D - 60.0, f"canister {i} sits well back from the face (its front at {cz + cw / 2:.0f} of {D:.0f})")
        expect(cz - cw / 2 >= POCKET_BACK_Z + GUARD_T, f"canister {i} clear of the back guard")
        expect(gy + gh <= POCKET_Y1 - 20.0 and gy >= POCKET_Y0 + 20.0, f"gauge {i} inside the pocket's height")
        # canister beside the gauge, not in it
        gap = (gx - gw / 2) - (cx + cw / 2)
        expect(gap >= 10.0, f"gauge {i} {gap:.0f} mm clear of its canister")
        # cradle seat holds the canister's footprint
        expect(CRADLE_R * math.cos(math.pi / 12) >= cw / 2, f"cradle {i}'s seat holds the {cw:.0f} mm canister")
        # reach: every extreme of the cradle seat, canister and gauge from the standing eye
        pts = [np.array([cx + dx, cy + dy, cz + dz]) for dx in (-cw / 2, cw / 2) for dy in (0.0, ch) for dz in (-cw / 2, cw / 2)]
        pts += [np.array([gx + dx, gy + dy, gz + dz]) for dx in (-gw / 2, gw / 2) for dy in (0.0, gh) for dz in (0.0, gau["stand_out_mm"])]
        far = max(float(np.linalg.norm(q - EYE)) for q in pts)
        expect(far <= REACH_MM, f"cradle {i} and gauge {i} within {REACH_MM:.0f} mm of the standing eye ({far:.0f} mm)")
    # The alcove is at chest height.
    expect(1000.0 <= POCKET_Y0 and POCKET_Y1 <= 1600.0, "alcove at chest height")
    figures = _check_panel(sol, hi)
    # The rails are within reach, clear of the pockets.
    for sx in (-1, 1):
        expect(abs(sx * RAIL_X) - RAIL_W / 2 >= POCKET_CX[1] + POCKET_W / 2 + 10.0, "rails clear of the pockets")
        expect(abs(sx * RAIL_X) + RAIL_W / 2 <= W / 2, "rails inside the unit's width")
    # Aperture: the pockets stay inside the shell (nothing cut away at the sides).
    expect(POCKET_CX[1] + POCKET_W / 2 + POCKET_BEVEL < W / 2 - 20.0, "pockets leave a wall at the sides")
    expect(POCKET_CX[0] + POCKET_W / 2 + POCKET_BEVEL < POCKET_CX[1] - POCKET_W / 2 - POCKET_BEVEL - 10.0, "a web between the pockets")
    return {"aisle_m": round(aisle, 3), **figures}


def _disc_clear(a: tuple[float, float, float], b: tuple[float, float, float], what: str) -> None:
    """Two round things (x, y, radius) on the panel face do not overlap, with 6 mm between."""
    gap = math.hypot(a[0] - b[0], a[1] - b[1]) - a[2] - b[2]
    expect(gap >= 6.0, f"{what}: {gap:.0f} mm apart")


def _check_panel(sol: list[Solid], hi: list[float]) -> dict:
    """The upper panel: everything fits its plate, nothing overlaps, and the controls and storage tops are in reach."""
    gau, can = entry("gauge"), entry("scrubber_canister")
    tog, lamp = entry("guarded_toggle"), entry("indicator_lamp")
    bez, pb = gau["extent_radii"]["bezel"], gau["extent_radii"]["plate_bottom"]
    face = D + PLATE_T
    # The plates sit on the face, above the alcove and below the top, and leave the rails alone.
    expect(PLATE_Y0 >= POCKET_Y1 + POCKET_BEVEL + 10.0, f"panel starts {PLATE_Y0 - POCKET_Y1:.0f} mm above the alcove, past its flared mouth")
    expect(PLATE_Y1 <= H - BODY_CHAMFER, "panel below the unit's top chamfer")
    expect(STORE_PLATE[0] >= -W / 2 + BODY_CHAMFER and INSTR_PLATE[1] <= RAIL_X - RAIL_W / 2, "plates inside the sides and clear of the rail column")
    expect(STORE_PLATE[1] < INSTR_PLATE[0], "a gap between the plates")
    # Storage: six holes in two rows of three, inside their plate, clear of each other.
    holes = _holes()
    expect(len(holes) == 6 and len(set(y for _, y in holes)) == 2, "six storage holes in two rows of three")
    for (hx, hy) in holes:
        expect(STORE_PLATE[0] + 8.0 <= hx - HOLE_RING_R and hx + HOLE_RING_R <= STORE_PLATE[1] - 8.0, f"hole at x={hx:.0f} inside the storage plate")
        expect(PLATE_Y0 + 8.0 <= hy - HOLE_RING_R and hy + HOLE_RING_R <= PLATE_Y1 - 8.0, f"hole at y={hy:.0f} inside the storage plate")
    for i, a in enumerate(holes):
        for b in holes[i + 1:]:
            _disc_clear((*a, HOLE_RING_R), (*b, HOLE_RING_R), "storage holes")
    expect(HOLE_R >= can["footprint_mm"][0] / 2 + 5.0, f"a canister ({can['footprint_mm'][0]:.0f} mm) goes into a {2 * HOLE_R:.0f} mm hole with play")
    base = _hole_base_z()
    expect(base >= 100.0, f"stored canister bases {base:.0f} mm from the back face: the bore stays in the shell")
    expect(base + can["stand_out_mm"] <= face - TOP_RECESS + 0.01 and TOP_RECESS >= 5.0, "a stored canister shows its top just behind the plate face")
    # Instruments, at their entry sizes.
    r = GAUGE_R * 1000.0
    o2, co2 = (O2_AT, GAUGE_Y, bez * r), (CO2_AT, GAUGE_Y, bez * r)
    noise = (NOISE_AT, ROW2_Y + 15.0, bez * NOISE_R * 1000.0)
    tw, th = tog["footprint_mm"]
    lmp = (LAMP_AT, ROW2_Y, lamp["footprint_mm"][0] / 2)
    _disc_clear(o2, co2, "O2 and CO2 rate dials")
    expect((LAMP_AT - lmp[2]) - (TOGGLE_AT + tw / 2) >= 6.0, "toggle clear of the lamp")
    _disc_clear(lmp, noise, "lamp and noise dial")
    for name, (x, y, rr) in {"O2 dial": o2, "CO2 rate dial": co2, "noise dial": noise}.items():
        expect(INSTR_PLATE[0] + 5.0 <= x - rr and x + rr <= INSTR_PLATE[1] - 5.0, f"{name} inside the instrument plate")
        expect(y + rr <= PLATE_Y1 - 8.0, f"{name} below the plate's top edge")
    expect(TOGGLE_AT - tw / 2 >= INSTR_PLATE[0] + 5.0, "toggle inside the instrument plate")
    # Dial plates (the title strip below each dial) clear what is under them.
    for name, (x, y, rr) in {"O2 dial": o2, "CO2 rate dial": co2}.items():
        low = y - pb * r
        expect(low >= ROW2_Y + th / 2 + 6.0, f"{name}'s title plate ({low:.0f}) clear of the toggle row ({ROW2_Y + th / 2:.0f})")
    expect(ROW2_Y - th / 2 >= PLATE_Y0 + 8.0, "toggle row inside the plate's bottom edge")
    # Reach from the standing eye: the fan toggle and every dial and lamp, and the stored canisters' tops.
    far_tog = max(float(np.linalg.norm(np.array([TOGGLE_AT + dx, ROW2_Y + dy, face + tog["stand_out_mm"]]) - EYE))
                  for dx in (-tw / 2, tw / 2) for dy in (-th / 2, th / 2))
    expect(far_tog <= REACH_MM, f"the fan toggle within {REACH_MM:.0f} mm of the standing eye ({far_tog:.0f} mm)")
    far_top = 0.0
    for hx, hy in holes:
        for ang in range(0, 360, 45):
            q = np.array([hx + HOLE_R * math.cos(math.radians(ang)), hy + HOLE_R * math.sin(math.radians(ang)), face - TOP_RECESS])
            far_top = max(far_top, float(np.linalg.norm(q - EYE)))
    expect(far_top <= REACH_MM, f"every storage top within {REACH_MM:.0f} mm of the standing eye ({far_top:.0f} mm)")
    top_y = max(hy for _, hy in holes) + HOLE_R
    expect(top_y <= EYE[1] + 400.0, f"the highest storage top ({top_y:.0f} mm) reachable at head height")
    return {"toggle_reach_mm": round(far_tog), "storage_reach_mm": round(far_top)}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    sol = solids()
    figures = _check(sol)
    rep = export_solids_glb(sol, d / f"{SLUG}_body.glb", "LifeSupportBody", tol_mm=0.5, ang=0.6)
    s = Scene("LifeSupport", type_="Node3D")
    s.node("Body", instance=rep["glb"])
    sh = s.sub("BoxShape3D", "unit", {"size": (W / 1000, H / 1000, D / 1000)})
    s.node("Collision", type_="StaticBody3D")
    s.node("Unit", parent="Collision", type_="CollisionShape3D",
           props={"transform": Xform(origin=(0, H / 2000, D / 2000)), "shape": sh})
    s.node("OperatorPoint", props={"transform": Xform(origin=(0, 0, (D + 150.0) / 1000))})
    s.node("OperatorEye", props={"transform": Xform(origin=tuple(EYE / 1000))})
    s.node("UpperPanelAnchor", props={"transform": Xform(origin=(0, PLATE_Y0 / 1000, (D + PLATE_T) / 1000))})
    names = ["A", "B"]
    for i, n in enumerate(names):
        x, y, z = (v / 1000 for v in _cradle_xyz(i))
        s.node(f"Cradle{n}", script="res://src/interact/canister_slot.gd", props={"transform": Xform(origin=(x, y, z))})
        s.node(f"Canister{n}", instance=scene_path("scrubber_canister"), props={"transform": Xform(origin=(x, y, z))})
        gx, gy, gz = (v / 1000 for v in _gauge_xyz(i))
        s.node(f"Saturation{n}", instance=scene_path("linear_gauge"),
               props={"transform": Xform(origin=(gx, gy, gz)), "source_group": SName("life_support_readouts"),
                      "readout": SName(f"saturation_{n.lower()}"), "max_value": 1.0})
    # Storage: a slot per hole, lying along +Z, a canister in the filled ones.
    face = D + PLATE_T
    for k, (hx, hy) in enumerate(_holes()):
        o = (hx / 1000, hy / 1000, _hole_base_z() / 1000)
        s.node(f"Storage{k + 1}", script="res://src/interact/canister_slot.gd", props={"transform": _slot_xform(*o)})
        if k in FILLED_HOLES:
            s.node(f"Stored{k + 1}", instance=scene_path("scrubber_canister"), props={"transform": _slot_xform(*o)})
    # Instruments, on the plate face.
    ls = SName("life_support_readouts")
    s.node("O2Gauge", instance=scene_path("gauge"), props={
        "transform": Xform(origin=(O2_AT / 1000, GAUGE_Y / 1000, face / 1000)), "radius": GAUGE_R, "title": "O2",
        "source_group": ls, "readout": SName("o2_level"), "min_value": 0.0, "max_value": 1.0})
    s.node("Co2RateGauge", instance=scene_path("gauge"), props={
        "transform": Xform(origin=(CO2_AT / 1000, GAUGE_Y / 1000, face / 1000)), "radius": GAUGE_R, "title": "CO2 RATE",
        "source_group": ls, "readout": SName("co2_capacity_rate"), "readout_b": SName("co2_production_rate"),
        "min_value": 0.0, "max_value": 1.0})
    s.node("FanToggle", instance=scene_path("guarded_toggle"), props={"transform": Xform(origin=(TOGGLE_AT / 1000, ROW2_Y / 1000, face / 1000)), "label": "FANS"})
    s.node("FanLamp", instance=scene_path("indicator_lamp"), props={"transform": Xform(origin=(LAMP_AT / 1000, ROW2_Y / 1000, face / 1000))})
    s.node("NoiseRepeater", instance="res://src/noise/noise_gauge.tscn", props={
        "transform": Xform(origin=(NOISE_AT / 1000, (ROW2_Y + 15.0) / 1000, face / 1000)), "radius": NOISE_R})
    s.write(d / f"{SLUG}.tscn")
    _cameras(d)
    n_can = 2 + len(FILLED_HOLES)
    tris = (rep["triangles"] + n_can * entry("scrubber_canister")["triangles"] + 2 * entry("linear_gauge")["triangles"]
            + 3 * entry("gauge")["triangles"] + entry("guarded_toggle")["triangles"] + entry("indicator_lamp")["triangles"])
    expect(tris <= 12000, f"station within the 12,000 triangle budget ({tris})")
    write_entry(GROUP, SLUG, {
        "kind": "station",
        "summary": "Life-support wall unit: tall grey body on a hazard-striped plinth, orange handle rails, a chamfered "
                   "chest-height alcove of two cradles (each with a scrubber canister and a linear saturation gauge), and an "
                   "upper panel with six storage holes (canister tops showing), O2 gauge, two-needle CO2 rate gauge, a guarded "
                   "fan toggle with run lamp and the noise repeater. The operator stands.",
        "tags": ["station", "life support", "scrubber", "canister", "cradle", "storage", "o2", "co2", "wall unit", "standing"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"wire": {"cradles": "CradleA, CradleB (CanisterSlot; call try_seat on CanisterA, CanisterB)",
                               "gauges": "SaturationA, SaturationB read life_support_readouts: saturation_a, saturation_b (0..1)",
                               "storage": "Storage1..Storage6 (CanisterSlot lying along +Z, lower row then upper row; Stored1,2,3,5 hold a canister, 4 and 6 are empty)",
                               "o2": "O2Gauge reads life_support_readouts: o2_level (0..1)",
                               "co2_rate": "Co2RateGauge reads life_support_readouts: co2_capacity_rate, co2_production_rate (0..1, needle B is production)",
                               "fans": "FanToggle (SwitchLever, value_changed) with FanLamp (IndicatorLamp)",
                               "noise_repeater": "NoiseRepeater",
                               "upper_panel": "UpperPanelAnchor (bottom-left corner of the storage plate, on its face)",
                               "standing_eye": "OperatorEye"}},
        "footprint_mm": [W, D + RAIL_OUT],
        "stand_out_mm": D + RAIL_OUT,   # the rails; the fan toggle reaches D + 64
        "mount": "floor at Y=0, back against the hull on Z=0, centred on X, operator standing at +Z facing -Z",
        "uses": list(USES),
        "triangles": tris,
        "triangles_by_part": {"body": rep["triangles"]},
        "checks": figures,
    })
    return {"slug": SLUG, "triangles": tris, "body": rep["triangles"]}


def _cameras(d) -> None:
    """Review cameras: the concept's three viewpoints, the operator's eye (white and red light), orthographic profile and front."""
    eye = [round(v / 1000, 3) for v in EYE]
    cams = [
        {"name": "concept_swap_view", "pos": [-0.9, 1.5, 2.0], "look_at": [0.1, 1.45, 0.3], "fov": 62.0},
        {"name": "concept_canister_pair", "pos": [0.0, 1.5, 1.3], "look_at": [0.0, 1.2, 0.3], "fov": 40.0},
        {"name": "concept_storage_tops", "pos": [-0.2, 2.05, 1.1], "look_at": [-0.15, 1.8, 0.5], "fov": 45.0},
        {"name": "operator_eye", "pos": eye, "look_at": [0.0, 1.3, 0.2], "fov": 75.0},
        {"name": "operator_eye_red", "pos": eye, "look_at": [0.0, 1.3, 0.2], "fov": 75.0, "light": "red"},
        {"name": "profile_right", "pos": [3.5, 1.0, 0.25], "look_at": [0.0, 1.0, 0.25], "ortho": 2.2},
        {"name": "front", "pos": [0.0, 1.0, 4.0], "look_at": [0.0, 1.0, 0.0], "ortho": 2.2},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
