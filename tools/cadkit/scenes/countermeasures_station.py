"""countermeasures_station: the countermeasures control panel with its decoy rack (a panel). Brief: assets/models/panels/countermeasures_station/brief.yaml.

A tall flat grey panel against the starboard hull, a sibling of the life support unit, with the decoy rack beside it.
Top to bottom: the COUNTERMEASURES plate; the FORE TUBE and AFT TUBE sections side by side, each with three lamps (EMPTY
alarm, LOADED warn, PRIMED ok, driven by a `TubeLamps`) over a guarded `fire_button`; the decoy status screen (a
`DecoyStatusScreen` on a bezel); the AIR and NOISE gauges. An orange grab rail runs up the panel's outer edge. The six-
cradle `decoy_rack` stands beside the panel. The whole assembly stands on a low dais so the lowest cradle is within reach
of the shoulder (the rack as built has its lowest cradle 0.31 m off the floor; the shared rack is not changed to suit this
parent).

Local solids (static, used once): the panel body, the dais, the section insets, the screen bezel, the label plates, the
hazard strip and the grab rail. Everything else is a catalogue scene, set 2 mm off its host face (the mount rule). No
scripts are added: the FIRE buttons and the lamps take a `tube` (a LaunchTube) set on the instance by the placing arc.

Frame (mm): X along the hull, Y up, Z out of the hull (the mount face). The origin is the assembly's centre along the
hull, 1.1 m above the floor, so Y = -1100 is the floor and the standing eye is at (0, 550, 500).
"""
import json
import math

import numpy as np

from cadkit import mount
from cadkit.solids import Solid, at, box, expect, expect_in_front, export_solids_glb
from cadkit.library import entry, note, out_dir, res, scene_path, write_entry
from cadkit.tscn import NodePath, SName, Scene, Xform

SLUG, GROUP = "countermeasures_station", "panels"
USES: list[str] = ["fire_button", "led_strip", "led_strip_warn", "led_strip_alarm", "gauge", "decoy_rack", "decoy"]
NOISE_GAUGE_SCENE = "res://src/noise/noise_gauge.tscn"
TRIANGLE_BUDGET = 10000                          # with the six decoys counted (Tristan, 2026-11-27, #758)

# The brief's constraints (concept #758).
MAX_ALONG = 1000.0                               # along the hull: the reservation grows to 1.0 m (Tristan, 2026-11-27)
MAX_DEPTH = 450.0
EYE = np.array([0.0, 550.0, 500.0])              # operator_eye_m
SHOULDER = EYE - np.array([0.0, 250.0, 0.0])
REACH = 1100.0                                   # reach_m, from the shoulder
FLOOR_Y = -1100.0                                # the floor, in the station frame

# Layout along the hull (the whole assembly is centred on X = 0 at the end).
RAIL_BAND = 50.0                                 # the panel's grab rail stands in this band outside the panel
PANEL_W, PANEL_D = 560.0, 200.0
GAP = 2.0                                        # panel to rack
RACK_COL_W, RACK_RAIL = 320.0, 58.0              # the rack's column and its own rail (decoy_rack's entry)
DAIS_H = 100.0                                   # the dais under everything
BASE_Y = FLOOR_Y + DAIS_H                        # the panel's and rack's floor
PANEL_TOP = 1100.0
INSET_Z = PANEL_D                                # section insets sit on the panel front, 3 mm thick
INSET_T = 3.0
SEC_Z = PANEL_D + INSET_T                        # the host face of the tube sections
SCREEN_Z = PANEL_D + 6.0                         # the bezel's front face

FIRE_Y, LAMP_Y, HEADER_Y = 565.0, 715.0, 780.0
SCREEN_Y, GAUGE_Y, TITLE_Y = 360.0, 160.0, 910.0
SECTION_DX = 135.0                               # a tube section's centre from the panel's centre
LAMP_DX = 54.0
SCREEN_SCALE = 1.8                               # DecoyStatusScreen's default quad is 0.16 x 0.10 m
SCREEN_W, SCREEN_H = 160.0 * SCREEN_SCALE, 100.0 * SCREEN_SCALE
GAUGE_R = 0.065
GAUGE_DX = 88.0
MAX_EYE_ANGLE = 60.0

_X, _I = np.array([1.0, 0.0, 0.0]), np.eye(3)


def layout() -> dict:
    total = RAIL_BAND + PANEL_W + GAP + RACK_COL_W + RACK_RAIL
    left = -total / 2
    p0 = left + RAIL_BAND
    return {"total": total, "left": left, "p0": p0, "pc": p0 + PANEL_W / 2, "rack_x": p0 + PANEL_W + GAP + RACK_COL_W / 2}


def _depth(slug: str) -> tuple[float, float]:
    e = entry(slug)
    d = e.get("depth_mm")
    return (d["behind_origin"], d["in_front_of_origin"]) if d else (0.0, e["stand_out_mm"])


class Item:
    """One placed catalogue scene (or node): its origin, what it occupies (a local box) and what it is mounted on."""

    def __init__(self, name: str, slug: str, scene: str | None, origin, rect: tuple, behind: float, front: float,
                 host: str, offset: float, **props):
        self.name, self.slug, self.scene, self.props = name, slug, scene, props
        self.origin, self.rect, self.host, self.offset = np.array(origin, float), rect, host, offset
        self.local_box = (rect[0], rect[1], -behind, rect[2], rect[3], front)

    def corners(self) -> np.ndarray:
        x0, y0, z0, x1, y1, z1 = self.local_box
        return np.array([self.origin + np.array([x, y, z]) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)])

    @property
    def aabb(self) -> tuple:
        c = self.corners()
        return tuple(c.min(axis=0)) + tuple(c.max(axis=0))

    def face_point(self, dz: float = 0.0) -> np.ndarray:
        return self.origin + np.array([0.0, 0.0, dz])


def _gauge_rect(r_m: float) -> tuple:
    ext = entry("gauge")["extent_radii"]
    r = r_m * 1000
    return (-ext["bezel"] * r, -ext["plate_bottom"] * r, ext["bezel"] * r, ext["bezel"] * r)


def _on(name: str, slug: str, x: float, y: float, host_z: float, host: str, rect: tuple | None = None,
        scene: str | None = None, **props) -> Item:
    behind, front = _depth(slug)
    off = mount.stand_off(behind)
    if rect is None:
        w, h = entry(slug)["footprint_mm"]
        rect = (-w / 2, -h / 2, w / 2, h / 2)
    return Item(name, slug, scene or scene_path(slug), (x, y, host_z + off), rect, behind, front, host, off, **props)


def sections() -> list[tuple[str, float]]:
    pc = layout()["pc"]
    return [("Fore", pc - SECTION_DX), ("Aft", pc + SECTION_DX)]


def items() -> list[Item]:
    L = layout()
    out: list[Item] = []
    for tube, sx in sections():
        out.append(_on(f"{tube}Fire", "fire_button", sx, FIRE_Y, SEC_Z, f"{tube.lower()} section inset"))
        for i, (n, slug) in enumerate((("Empty", "led_strip_alarm"), ("Loaded", "led_strip_warn"), ("Primed", "led_strip"))):
            out.append(_on(f"{tube}{n}", slug, sx + (i - 1) * LAMP_DX, LAMP_Y, SEC_Z, f"{tube.lower()} section inset"))
    out.append(_on("AirGauge", "gauge", L["pc"] - GAUGE_DX, GAUGE_Y, PANEL_D, "panel front", rect=_gauge_rect(GAUGE_R),
                   title="AIR", readout=SName("air_fraction"), min_value=0.0, max_value=1.0, sweep_deg=180.0, radius=GAUGE_R))
    out.append(_on("NoiseGauge", "gauge", L["pc"] + GAUGE_DX, GAUGE_Y, PANEL_D, "panel front", rect=_gauge_rect(GAUGE_R),
                   scene=NOISE_GAUGE_SCENE, radius=GAUGE_R))
    off = mount.stand_off(0.0)
    rw, rh = entry("decoy_rack")["footprint_mm"]
    out.append(Item("DecoyRack", "decoy_rack", scene_path("decoy_rack"), (L["rack_x"], BASE_Y, off),
                    (-RACK_COL_W / 2, 0.0, RACK_COL_W / 2 + RACK_RAIL, rh_h()), 0.0, entry("decoy_rack")["stand_out_mm"],
                    "hull wall z=0", off))
    return out


def rh_h() -> float:
    return float(entry("decoy_rack")["checks"]["height_mm"])


def screen_item() -> Item:
    """The decoy status screen: a scaled DecoyStatusScreen quad on its bezel (not a catalogue scene)."""
    L = layout()
    off = mount.stand_off(0.0)
    return Item("StatusScreen", "decoy_status_screen", None, (L["pc"], SCREEN_Y, SCREEN_Z + off),
                (-SCREEN_W / 2, -SCREEN_H / 2, SCREEN_W / 2, SCREEN_H / 2), 0.0, 1.0, "screen bezel", off)


def cradle_points() -> list[np.ndarray]:
    """Each cradle's decoy, at the middle of its grab box, in the station frame (from decoy_rack.tscn's node transforms)."""
    L = layout()
    tilt = math.radians(entry("decoy_rack")["checks"]["tilt_deg"])
    pitch = entry("decoy_rack")["checks"]["pitch_mm"]
    pts = []
    c, s = math.cos(tilt), math.sin(tilt)
    grab = np.array([0.0, 16.5, 0.0])                    # decoy.tscn's grab box centre
    rot = np.array([[1, 0, 0], [0, c, -s], [0, s, c]])  # the cradles' frame: the column turned about X
    for i in range(6):
        y0 = _rack_cradle_origin(i, pitch)
        pts.append(np.array([L["rack_x"], BASE_Y + y0[0], mount.stand_off(0.0) + y0[1]]) + rot @ grab)
    return pts


def _rack_cradle_origin(i: int, pitch: float) -> tuple[float, float]:
    """Cradle i's origin (y, z) in the rack's frame, read from the rack's own scene file so it never drifts."""
    import re
    from cadkit.library import root
    tscn = (root() / "furniture" / "decoy_rack" / "decoy_rack.tscn").read_text()
    m = re.search(rf'\[node name="Cradle{i + 1}".*?transform = Transform3D\(([^)]*)\)', tscn, re.S)
    v = [float(x) for x in m.group(1).split(",")]
    return v[10] * 1000.0, v[11] * 1000.0


def solids() -> list[Solid]:
    L = layout()
    p0, pc = L["p0"], L["pc"]
    total = L["total"]
    dais_d = float(entry("decoy_rack")["stand_out_mm"])
    parts: list[Solid] = [
        Solid(at(box(total, DAIS_H, dais_d, chamfer_mm=2.0), 0.0, FLOOR_Y + DAIS_H / 2), "interior_dark"),
        Solid(at(box(PANEL_W, PANEL_TOP - BASE_Y, PANEL_D, chamfer_mm=3.0), pc, (PANEL_TOP + BASE_Y) / 2), "interior_panel"),
        Solid(at(box(PANEL_W - 20.0, 60.0, 2.0), pc, BASE_Y + 50.0, PANEL_D), "hazard_stripe"),
        Solid(at(box(300.0, 56.0, 4.0), pc, TITLE_Y, PANEL_D), "label_plate"),
        Solid(at(box(SCREEN_W + 20.0, SCREEN_H + 20.0, 6.0, chamfer_mm=2.0), pc, SCREEN_Y, PANEL_D), "trim_black"),
        Solid(at(box(180.0, 26.0, 3.0), pc - GAUGE_DX, GAUGE_Y - 100.0, PANEL_D), "label_plate"),
        Solid(at(box(180.0, 26.0, 3.0), pc + GAUGE_DX, GAUGE_Y - 100.0, PANEL_D), "label_plate"),
    ]
    for tube, sx in sections():
        parts.append(Solid(at(box(250.0, 340.0, INSET_T), sx, (FIRE_Y - 80.0 + HEADER_Y + 30.0) / 2, INSET_Z), "interior_dark"))
        parts.append(Solid(at(box(170.0, 34.0, 3.0), sx, HEADER_Y, SEC_Z), "label_plate"))
        parts.append(Solid(at(box(70.0, 20.0, 3.0), sx, FIRE_Y - 80.0, SEC_Z), "label_plate"))
    # The panel's grab rail, up the outer edge, standing proud of the panel's face on two spurs.
    rail_x = L["left"] + 13.0
    y0, y1 = -300.0, 700.0
    parts.append(Solid(at(box(26.0, y1 - y0, 26.0), rail_x, (y0 + y1) / 2, 107.0), "control_interface"))
    for y in (y0 + 13.0, y1 - 13.0):
        parts.append(Solid(at(box(RAIL_BAND - 6.0 + 26.0, 26.0, 26.0), rail_x + (RAIL_BAND - 6.0 + 26.0) / 2 - 13.0, y, 107.0), "control_interface"))
    expect_in_front(parts, SLUG)
    return parts


def _bb(shape) -> tuple:
    b = shape.bounding_box()
    return (b.min.X, b.min.Y, b.min.Z, b.max.X, b.max.Y, b.max.Z)


def _seg_hits(a: np.ndarray, b: np.ndarray, bx: tuple) -> bool:
    lo, hi = np.array(bx[:3]), np.array(bx[3:])
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


def _gap(a: Item, b: Item) -> float:
    ra, rb = a.aabb, b.aabb
    return max(rb[0] - ra[3], ra[0] - rb[3], rb[1] - ra[4], ra[1] - rb[4])


def checks(its: list[Item], screen: Item, parts: list[Solid]) -> dict:
    by = {i.name: i for i in its}
    # Size and the mount face.
    lo = np.min([[min(_bb(p.shape)[k] for p in parts) for k in range(3)]] + [i.corners().min(axis=0) for i in its + [screen]], axis=0)
    hi = np.max([[max(_bb(p.shape)[k] for p in parts) for k in (3, 4, 5)]] + [i.corners().max(axis=0) for i in its + [screen]], axis=0)
    along, depth = float(hi[0] - lo[0]), float(hi[2])
    expect(along <= MAX_ALONG + 0.01, f"assembly {along:.0f} mm along the hull, at most {MAX_ALONG:.0f}")
    expect(depth <= MAX_DEPTH + 0.01, f"assembly {depth:.0f} mm deep, at most {MAX_DEPTH:.0f}")
    expect(lo[2] >= -0.01, f"nothing behind the mount face (Z=0): lowest Z {lo[2]:.1f}")
    expect(lo[1] >= FLOOR_Y - 0.01, f"nothing below the floor (Y {lo[1]:.0f})")
    expect(abs(RACK_COL_W + RACK_RAIL - entry("decoy_rack")["footprint_mm"][0]) <= 1.0, "the rack's width matches its entry")
    expect(not mount.problems(SLUG, {"mounts": mounts_record(its)}, entry), "no instanced face coplanar with its host face")
    # Reach, from the shoulder, to every control at its farthest point; to each cradle's decoy at its grab point.
    reach: dict[str, float] = {}
    for n in ("ForeFire", "AftFire", "AirGauge", "NoiseGauge"):
        d = float(max(np.linalg.norm(c - SHOULDER) for c in by[n].corners()))
        reach[n] = round(d, 1)
        expect(d <= REACH, f"{n} within reach {REACH:.0f} mm of the shoulder ({d:.0f})")
    d = float(max(np.linalg.norm(c - SHOULDER) for c in screen.corners()))
    reach["StatusScreen"] = round(d, 1)
    expect(d <= REACH, f"the status screen within reach {REACH:.0f} mm of the shoulder ({d:.0f})")
    for i, p in enumerate(cradle_points()):
        d = float(np.linalg.norm(p - SHOULDER))
        reach[f"Cradle{i + 1}"] = round(d, 1)
        expect(d <= REACH, f"cradle {i + 1} within reach {REACH:.0f} mm of the shoulder ({d:.0f})")
    # The controls' footprints are well apart (a hand between neighbours).
    ctl = [by["ForeFire"], by["AftFire"], by["AirGauge"], by["NoiseGauge"], screen]
    for a in range(len(ctl)):
        for b in range(a + 1, len(ctl)):
            g = _gap(ctl[a], ctl[b])
            expect(g >= 10.0, f"{ctl[a].name} and {ctl[b].name} footprints at least 10 mm apart ({g:.0f})")
    # The open FIRE guard (up and forward, 72 mm plate on a hinge 36 mm above the button) clears the lamps above it.
    for tube, _sx in sections():
        lamp_bottom = LAMP_Y - 3.0
        lid_top = FIRE_Y + 36.0 + 72.0 + 4.0
        expect(lamp_bottom - lid_top >= 10.0, f"{tube} guard open (to Y {lid_top:.0f}) clears the lamps ({lamp_bottom:.0f})")
    # Sight lines from the eye to each display face and the lamps; nothing in front blocks them. Displays face the eye.
    targets = {"StatusScreen": (screen, screen.face_point(1.0)), "AirGauge": (by["AirGauge"], by["AirGauge"].face_point(14.0)),
               "NoiseGauge": (by["NoiseGauge"], by["NoiseGauge"].face_point(14.0))}
    for tube, _sx in sections():
        for n in ("Empty", "Loaded", "Primed"):
            it = by[f"{tube}{n}"]
            targets[it.name] = (it, it.face_point(1.2))
    blockers = [(i.name, i.aabb) for i in its if i.name != "DecoyRack"] + [("rack", by["DecoyRack"].aabb)]
    blockers += [(f"solid {k}", _bb(p.shape)) for k, p in enumerate(parts) if p.role == "control_interface"]
    ang_max = 0.0
    for name, (owner, p) in targets.items():
        for bn, bx in blockers:
            if bn == owner.name:
                continue
            expect(not _seg_hits(EYE, p, bx), f"sight line from the eye to {name} blocked by {bn}")
        v = EYE - p
        ang = float(np.degrees(np.arccos(float(v[2]) / np.linalg.norm(v))))
        ang_max = max(ang_max, ang)
        expect(ang <= MAX_EYE_ANGLE, f"{name} faces the eye within {MAX_EYE_ANGLE:.0f} degrees ({ang:.0f})")
    return {"reach_mm": reach, "reach_limit_mm": REACH, "sight_lines": len(targets), "along_hull_mm": round(along, 1),
            "depth_mm": round(depth, 1), "max_eye_angle_deg": round(ang_max, 1)}


def mounts_record(its: list[Item]) -> list[dict]:
    return [mount.record(i.name, i.slug, i.offset, i.host) for i in its]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    L = layout()
    parts = solids()
    its = items()
    screen = screen_item()
    figs = checks(its, screen, parts)
    rep = export_solids_glb(parts, d / f"{SLUG}_body.glb", "CountermeasuresStationBody")
    s = Scene("CountermeasuresStation")
    s.node("Body", instance=rep["glb"])
    for i in its:
        xf = Xform(origin=tuple(float(v) / 1000 for v in i.origin))
        s.node(i.name, instance=i.scene, props={"transform": xf, **i.props})
    sx = SCREEN_SCALE
    s.node("StatusScreen", type_="MeshInstance3D", script="res://src/countermeasures/decoy_status_screen.gd",
           props={"transform": Xform(basis=np.diag([sx, sx, sx]), origin=tuple(float(v) / 1000 for v in screen.origin))})
    for tube, _sx in sections():
        s.node(f"{tube}Lamps", type_="Node", script="res://src/interact/tube_lamps.gd",
               props={"empty_lamp": NodePath(f"../{tube}Empty"), "loaded_lamp": NodePath(f"../{tube}Loaded"),
                      "primed_lamp": NodePath(f"../{tube}Primed")})
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
        "summary": "Countermeasures station: a tall flat grey panel against the starboard hull with a COUNTERMEASURES plate, "
                   "FORE TUBE and AFT TUBE sections side by side (EMPTY, LOADED and PRIMED lamps over a guarded FIRE button "
                   "each), the decoy status screen beneath, the AIR and NOISE gauges below it and an orange grab rail; the "
                   "six-cradle decoy rack stands beside it. Engraved label plates, hazard-striped base, matte grey body.",
        "tags": ["panel", "countermeasures", "decoy", "fire", "tube", "rack", "status screen", "air", "noise", "standing"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"wire": {
            "tubes": "ForeFire and AftFire (FireButton) and ForeLamps and AftLamps (TubeLamps): set `tube` (a LaunchTube) on "
                     "each pair; unset until the loaders are placed",
            "lamps": "ForeEmpty, ForeLoaded, ForePrimed, AftEmpty, AftLoaded, AftPrimed (IndicatorLamp), driven by the TubeLamps",
            "screen": "StatusScreen (DecoyStatusScreen): lists the decoy_buoys group",
            "gauges": "AirGauge (air_fraction), NoiseGauge (acoustics_readouts)",
            "rack": "DecoyRack: Cradle1..Cradle6 seat Decoy1..Decoy6 (see the decoy_rack entry)",
            "eye": "OperatorEye (the standing eye, 0.5 m out, 0.55 m above the station's centre)"}},
        "footprint_mm": [figs["along_hull_mm"], figs["depth_mm"]],
        "stand_out_mm": figs["depth_mm"],
        "mount": "back on Z=0 against the starboard hull (X along the hull, Z out into the aisle); centred along the hull on "
                 "the panel and rack together; the origin stands 1.1 m above the floor (Y -1100 is the floor)",
        "operator_eye_m": [float(v) / 1000 for v in EYE],
        "reach_m": REACH / 1000,
        "mounts": mounts_record(its),
        "uses": list(USES),
        "triangles": tris,
        "triangle_budget": TRIANGLE_BUDGET,
        "triangles_by_part": {"body": rep["triangles"], "rack_with_decoys": entry("decoy_rack")["triangles"]},
        "checks": figs,
    })
    return {"slug": SLUG, "triangles": tris, "body": rep["triangles"]}


def _cameras(d) -> None:
    """Review cameras: the concept viewpoint, the operator's eye (white and red light), orthographic front and profile."""
    eye = [round(float(v) / 1000, 3) for v in EYE]
    look = [-0.1, 0.5, 0.2]
    cams = [
        {"name": "concept_primary", "pos": [-1.0, 0.6, 2.2], "look_at": [0.1, 0.3, 0.0], "fov": 62.0},
        {"name": "operator_eye", "pos": eye, "look_at": look, "fov": 80.0},
        {"name": "operator_eye_red", "pos": eye, "look_at": look, "fov": 80.0, "light": "red"},
        {"name": "profile_right", "pos": [4.0, 0.1, 0.3], "look_at": [0.0, 0.1, 0.3], "ortho": 2.6},
        {"name": "front", "pos": [0.0, 0.1, 4.0], "look_at": [0.0, 0.1, 0.0], "ortho": 2.6},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
