"""electrical_station: the sub's distribution board (a panel). Brief: assets/models/panels/electrical_station/brief.yaml.

A tall flat board, back on Z=0 against the hull, controls toward +Z, centred on the board (X and Y). From the top: the
generator section (guarded START/STOP, RUNNING lamp, HEAT gauge), the 3 x 3 breaker grid, the spares drawer; down the
right edge the battery bar in a dark channel with the analogue LOAD meter beside it; orange grab rails either side;
cable-tray stubs leave the top.

Local solids (static, used once): the board plate, the three dark insets, the channel, the rails, the label plates,
the hazard band and the tray stubs. Everything else is a catalogue scene, set 2 mm off its host face (the mount
rule). No scripts are added: `circuit`, `label`, `readout` and `source_group` are set on the instances.

Frame (mm): X right, Y up, origin at the board's centre, Z out of the mount face. The board's centre stands 1.1 m above
the floor, so Y = -650 is 0.45 m (knee) and Y = +650 is 1.75 m (head).
"""
import json

import numpy as np

from cadkit import mount
from cadkit.solids import Solid, at, box, expect, expect_in_front, export_solids_glb
from cadkit.library import entry, note, out_dir, res, scene_path, write_entry
from cadkit.tscn import NodePath, SName, Scene, Xform

SLUG, GROUP = "electrical_station", "panels"
USES: list[str] = ["breaker_module", "spares_drawer", "guarded_toggle", "indicator_lamp", "gauge", "linear_gauge"]
TRIANGLE_BUDGET = 4000

# The brief's constraints (concept #534).
MAX_W, MAX_D = 1200.0, 450.0
Y_FLOOR, Y_HEAD = -650.0, 650.0                 # knee and head height, in the board frame
EYE = np.array([0.0, 550.0, 500.0])             # operator_eye_m
SHOULDER = EYE - np.array([0.0, 250.0, 0.0])
REACH = 1100.0                                  # reach_m, from the shoulder (Tristan's answer on #534)
FLOOR_TO_CENTRE = 1100.0

# The board.
PLATE_W, PLATE_Y0, PLATE_Y1, PLATE_T = 1000.0, -650.0, 600.0, 24.0
INSET_T, LABEL_T = 4.0, 2.0
FACE_PLATE = PLATE_T                            # host faces (Z of the front of each surface)
FACE_INSET = PLATE_T + INSET_T
FACE_LABEL = LABEL_T

# Breaker grid: 3 x 3 modules on a dark inset.
CIRCUITS = [("MOTOR", 0), ("THRUSTERS", 1), ("BILGE PUMP", 2), ("CABIN LTS", 3), ("EXT LTS", 4),
            ("SONAR", 5), ("FANS", 6), ("HELM", 7), ("DISPLAYS", 8)]
GRID_X0, GRID_DX = -305.0, 190.0
GRID_Y0, GRID_DY = 200.0, -180.0
GRID_INSET = (-115.0, 20.0, 510.0, 540.0)       # centre x, y, width, height

# Generator section (on its own inset), top left.
GEN_INSET = (-240.0, 470.0, 480.0, 220.0)
TOGGLE_AT = (-410.0, 470.0)
LAMP_AT = (-310.0, 500.0)
HEAT_AT, HEAT_R = (-160.0, 470.0), 0.05

# Right edge: battery bar in its channel, the LOAD meter beside it.
CHANNEL = (440.0, 0.0, 56.0, 600.0)
BAR_X, BAR_BOTTOM = 440.0, -116.0
LOAD_AT, LOAD_R = (335.0, 60.0), 0.06

DRAWER_AT = (-115.0, -355.0)

RAIL_X, RAIL_W, RAIL_Y0, RAIL_Y1, RAIL_Z0, RAIL_Z1 = 485.0, 30.0, -560.0, 440.0, 50.0, 86.0
POST = 20.0
STUB_X, STUB_W, STUB_Y1 = (-300.0, 300.0), 70.0, 650.0
STUB_Z1 = 54.0

# (name, centre x, centre y, width, height) of each label plate (aluminium, on its host face).
PLATES = [("GENERATOR", -240.0, 556.0, 160.0, 16.0, FACE_INSET),
          ("START/STOP", TOGGLE_AT[0], 392.0, 90.0, 14.0, FACE_INSET),
          ("RUNNING", LAMP_AT[0], 474.0, 70.0, 12.0, FACE_INSET),
          ("ELECTRICAL", 170.0, 480.0, 300.0, 36.0, FACE_PLATE),
          ("BATTERY", BAR_X, 330.0, 54.0, 14.0, FACE_PLATE)]


def _depth(slug: str) -> tuple[float, float]:
    """(behind the origin, in front of it) in mm, from the catalogue entry."""
    e = entry(slug)
    d = e.get("depth_mm")
    return (d["behind_origin"], d["in_front_of_origin"]) if d else (0.0, e["stand_out_mm"])


def _rect(slug: str, x: float, y: float, radius_m: float = 0.0) -> tuple[float, float, float, float]:
    """The footprint of an instance as (x0, y0, x1, y1) mm, from its catalogue entry (a gauge's from its extent radii)."""
    e = entry(slug)
    if radius_m:
        r = radius_m * 1000
        ext = e["extent_radii"]
        return (x - ext["bezel"] * r, y - ext["plate_bottom"] * r, x + ext["bezel"] * r, y + ext["bezel"] * r)
    w, h = e["footprint_mm"]
    if slug == "linear_gauge":                   # the origin is the bar's bottom
        return (x - w / 2, y, x + w / 2, y + h)
    return (x - w / 2, y - h / 2, x + w / 2, y + h / 2)


class Item:
    """One placed catalogue scene: where its origin is and what it occupies."""

    def __init__(self, name: str, slug: str, x: float, y: float, host_z: float, radius_m: float = 0.0, **props):
        self.name, self.slug, self.x, self.y, self.props = name, slug, x, y, props
        behind, front = _depth(slug)
        self.z = host_z + mount.stand_off(behind)
        self.offset = self.z - host_z
        self.rect = _rect(slug, x, y, radius_m)
        self.radius_m = radius_m
        self.box = (self.rect[0], self.rect[1], self.z - behind, self.rect[2], self.rect[3], self.z + front)
        self.solid_boxes = [self.box]
        if slug == "breaker_module":             # the plate, and the handle's swing (knob 28 wide, stem and knob 40 long)
            self.solid_boxes = [(self.rect[0], self.rect[1], self.z, self.rect[2], self.rect[3], self.z + 13.0),
                                (x - 14.0, y - 40.0, self.z + 13.0, x + 14.0, y + 40.0, self.z + front)]

    @property
    def tip(self) -> np.ndarray:
        """The control's far point (a handle at its extreme), for reach."""
        return np.array([self.x, self.y, self.z + entry(self.slug)["stand_out_mm"]])


def _camel(name: str) -> str:
    return "".join(w[0] + w[1:].lower() for w in name.split())


def items() -> list[Item]:
    out = [Item(f"Breaker{_camel(n)}", "breaker_module", GRID_X0 + (i % 3) * GRID_DX,
                GRID_Y0 + (i // 3) * GRID_DY, FACE_INSET, circuit=c, label=n)
           for i, (n, c) in enumerate(CIRCUITS)]
    out.append(Item("GeneratorToggle", "guarded_toggle", *TOGGLE_AT, FACE_INSET, label="GENERATOR"))
    out.append(Item("RunningLamp", "indicator_lamp", *LAMP_AT, FACE_INSET))
    out.append(Item("HeatGauge", "gauge", *HEAT_AT, FACE_INSET, radius_m=HEAT_R, title="HEAT", readout=SName("generator_heat"),
                    source_group=SName("power_system"), min_value=0.0, max_value=1.0, radius=HEAT_R))
    out.append(Item("LoadGauge", "gauge", *LOAD_AT, FACE_PLATE, radius_m=LOAD_R, title="LOAD", readout=SName("load"),
                    source_group=SName("power_system"), min_value=0.0, max_value=1.0, radius=LOAD_R, zone_from=0.8,
                    zone_to=1.0, zone_swatch=SName("light_alarm")))
    out.append(Item("BatteryBar", "linear_gauge", BAR_X, BAR_BOTTOM, CHANNEL_FACE, readout=SName("battery_charge"),
                    source_group=SName("power_system"), min_value=0.0, max_value=1.0, descending=True, warn_at=0.5,
                    alarm_at=0.15))
    out.append(Item("SparesDrawer", "spares_drawer", *DRAWER_AT, FACE_PLATE))
    return out


CHANNEL_FACE = FACE_INSET


def solids() -> tuple[list[Solid], dict]:
    plate = at(box(PLATE_W, PLATE_Y1 - PLATE_Y0, PLATE_T, chamfer_mm=3.0), y=(PLATE_Y0 + PLATE_Y1) / 2)
    insets = [at(box(w, h, INSET_T), x, y, PLATE_T) for x, y, w, h in (GRID_INSET, GEN_INSET, CHANNEL)]
    plates = [at(box(w, h, LABEL_T), x, y, z) for _, x, y, w, h, z in PLATES]
    hazard = at(box(800.0, 30.0, 2.0), 0.0, -600.0, PLATE_T)
    rail_len = RAIL_Y1 - RAIL_Y0
    rails, posts = [], []
    for sx in (-1, 1):
        rails.append(at(box(RAIL_W, rail_len, RAIL_Z1 - RAIL_Z0, chamfer_mm=5.0), sx * RAIL_X, (RAIL_Y0 + RAIL_Y1) / 2, RAIL_Z0))
        for y in (RAIL_Y0 + 60.0, RAIL_Y1 - 60.0):
            posts.append(at(box(POST, POST, RAIL_Z0 - PLATE_T + 1.0), sx * RAIL_X, y, PLATE_T))
    stubs = [at(box(STUB_W, STUB_Y1 - PLATE_Y1 + 20.0, STUB_Z1 - PLATE_T), x, (PLATE_Y1 - 20.0 + STUB_Y1) / 2, PLATE_T)
             for x in STUB_X]
    parts = ([Solid(plate, "interior_panel")] + [Solid(i, "interior_dark") for i in insets]
             + [Solid(p, "label_plate") for p in plates]
             + [Solid(hazard, "hazard_stripe")] + [Solid(r, "control_interface") for r in rails]
             + [Solid(p, "interior_dark") for p in posts] + [Solid(s, "hull_metal") for s in stubs])
    expect_in_front(parts, SLUG)
    return parts, {"rails": rails, "stubs": stubs, "plate": plate}


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


def checks(its: list[Item], parts: list[Solid], local: dict) -> dict:
    by = {i.name: i for i in its}
    # Size: the board, then everything on it.
    lo = [min(_bb(p.shape)[k] for p in parts) for k in range(3)]
    hi = [max(_bb(p.shape)[k] + 0 for p in parts) for k in (3, 4, 5)]
    expect(hi[0] - lo[0] <= MAX_W + 0.01, f"board at most {MAX_W:.0f} mm wide ({hi[0] - lo[0]:.0f})")
    expect(lo[1] >= Y_FLOOR - 0.01 and hi[1] <= Y_HEAD + 0.01,
           f"board from knee to head height: Y {lo[1]:.0f}..{hi[1]:.0f}, floor to centre {FLOOR_TO_CENTRE:.0f} mm "
           f"({(FLOOR_TO_CENTRE + lo[1]) / 1000:.2f}..{(FLOOR_TO_CENTRE + hi[1]) / 1000:.2f} m above the floor)")
    deepest = max([hi[2]] + [i.box[5] for i in its])
    expect(deepest <= MAX_D, f"board stands out at most {MAX_D:.0f} mm ({deepest:.0f})")
    expect(min(lo[2], *(i.box[2] for i in its)) >= -0.01, "no part behind the mount face (Z=0)")
    for i in its:
        x0, y0, _, x1, y1, _ = i.box
        expect(x0 >= lo[0] and x1 <= hi[0] and y0 >= lo[1] and y1 <= hi[1], f"{i.name} within the board")
    # Mount rule: no face of an instanced scene within the tolerance of its host face.
    mounts = [mount.record(i.name, i.slug, i.offset, "board face") for i in its]
    expect(not mount.problems(SLUG, {"mounts": mounts}, entry), "no instanced face coplanar with its host face")
    # Every part sits on the surface it was meant for.
    for name, (cx, cy, w, h) in (("grid", GRID_INSET[:4]), ("generator", GEN_INSET), ("channel", CHANNEL)):
        grp = [i for i in its if (name == "grid" and i.slug == "breaker_module")
               or (name == "generator" and i.name in ("GeneratorToggle", "RunningLamp", "HeatGauge"))
               or (name == "channel" and i.name == "BatteryBar")]
        for i in grp:
            x0, y0, _, x1, y1, _ = i.box
            expect(cx - w / 2 <= x0 and x1 <= cx + w / 2 and cy - h / 2 <= y0 and y1 <= cy + h / 2,
                   f"{i.name} inside the {name} inset")
    # Footprints apart (grab boxes): a hand between neighbours.
    for a in range(len(its)):
        for b in range(a + 1, len(its)):
            ra, rb = its[a].rect, its[b].rect
            gx = max(rb[0] - ra[2], ra[0] - rb[2])
            gy = max(rb[1] - ra[3], ra[1] - rb[3])
            expect(max(gx, gy) >= 10.0, f"{its[a].name} and {its[b].name} footprints at least 10 mm apart ({max(gx, gy):.0f})")
    # The two rails are far apart; the right-hand column stays clear of the rail.
    expect(2 * RAIL_X - RAIL_W >= 900.0, "grab rails a body apart")
    clear = RAIL_X - RAIL_W / 2 - 10.0
    expect(max(i.rect[2] for i in its) <= clear + 0.01 and min(i.rect[0] for i in its) >= -clear - 0.01,
           "controls clear of the rails")
    # Reach, from the shoulder, to every control (the nine breakers and the generator switch).
    reach = {}
    for i in its:
        if i.slug in ("breaker_module", "guarded_toggle"):
            d = float(np.linalg.norm(i.tip - SHOULDER))
            reach[i.name] = round(d, 1)
            expect(d <= REACH, f"{i.name} within reach {REACH:.0f} mm of the shoulder ({d:.0f})")
    # Sight lines from the eye to every lamp, the battery bar, the LOAD meter and the drawer; nothing in front blocks them.
    targets = {}
    for i in its:
        if i.slug == "breaker_module":
            targets[i.name + " lamp"] = (i, np.array([i.x, i.y + 58.0, i.z + 11.0]))
        elif i.slug == "indicator_lamp":
            targets[i.name] = (i, np.array([i.x, i.y, i.z + 5.0]))
    bar = by["BatteryBar"]
    for k, f in (("bottom", 0.0), ("middle", 0.5), ("top", 1.0)):
        targets[f"battery bar {k}"] = (bar, np.array([bar.x, bar.y + f * entry("linear_gauge")["track_mm"]["travel"], bar.z + 7.0]))
    load = by["LoadGauge"]
    targets["LOAD meter"] = (load, np.array([load.x, load.y, load.z + 14.0]))
    heat = by["HeatGauge"]
    targets["HEAT gauge"] = (heat, np.array([heat.x, heat.y, heat.z + 14.0]))
    dr = by["SparesDrawer"]
    dx0, dy0, _, dx1, dy1, dz = dr.box
    for k, p in (("centre", ((dx0 + dx1) / 2, (dy0 + dy1) / 2)), ("left", (dx0 + 20, (dy0 + dy1) / 2)),
                 ("right", (dx1 - 20, (dy0 + dy1) / 2))):
        targets[f"spares drawer {k}"] = (dr, np.array([p[0], p[1], dz]))
    blockers = [(i.name, b) for i in its for b in i.solid_boxes] + [("rail", _bb(r)) for r in local["rails"]] + [("stub", _bb(s)) for s in local["stubs"]]
    for name, (owner, p) in targets.items():
        for bn, bx in blockers:
            if bn == owner.name:
                continue
            expect(not _seg_hits(EYE, p, bx), f"sight line from the eye to {name} blocked by {bn}")
        # A displayed face turns toward the eye (the board is flat: the steeper the angle, the lower on the board).
        v = EYE - p
        ang = float(np.degrees(np.arccos(v[2] / np.linalg.norm(v))))
        expect(ang <= 70.0, f"{name} faces the eye within 70 degrees ({ang:.0f})")
    return {"reach_mm": reach, "sight_lines": len(targets), "reach_limit_mm": REACH}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    parts, local = solids()
    its = items()
    figs = checks(its, parts, local)
    rep = export_solids_glb(parts, d / f"{SLUG}_body.glb", "ElectricalStationBody")
    s = Scene("ElectricalStation")
    s.node("Body", instance=rep["glb"])
    for i in its:
        props = {"transform": Xform(origin=(i.x / 1000, i.y / 1000, i.z / 1000)), **i.props}
        s.node(i.name, instance=scene_path(i.slug), props=props)
    s.node("GeneratorLink", type_="Node", script="res://src/interact/generator_link.gd",
           props={"switch_lever": NodePath("../GeneratorToggle")})
    s.node("RunningLampDriver", type_="Node", script="res://src/interact/threshold_lamp.gd",
           props={"lamp": NodePath("../RunningLamp"), "source_group": SName("power_system"),
                  "readout": SName("generator_running"), "threshold": 0.5})
    s.node("OperatorEye", props={"transform": Xform(origin=tuple(float(v) / 1000 for v in EYE))})
    s.write(d / f"{SLUG}.tscn")
    count = {}
    for i in its:
        count[i.slug] = count.get(i.slug, 0) + 1
    tris = rep["triangles"] + sum(entry(sl)["triangles"] * n for sl, n in count.items())
    expect(tris <= TRIANGLE_BUDGET, f"panel within the {TRIANGLE_BUDGET:,} triangle budget ({tris})")
    _cameras(d)
    write_entry(GROUP, SLUG, {
        "kind": "panel",
        "summary": "Electrical distribution board: tall flat grey board, back on the hull. Generator section at the top "
                   "(guarded START/STOP, RUNNING lamp, HEAT gauge), a 3 x 3 grid of breaker modules, the spares drawer "
                   "below it, the battery bar in a dark channel down the right edge with the analogue LOAD meter beside "
                   "it, orange grab rails either side, label plates and cable-tray stubs leaving the top.",
        "tags": ["panel", "electrical", "breaker", "power", "battery", "generator", "distribution board", "standing"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"wire": {
            "breakers": "BreakerMotor, BreakerThrusters, BreakerBilgePump, BreakerCabinLts, BreakerExtLts, BreakerSonar, "
                        "BreakerFans, BreakerHelm, BreakerDisplays (BreakerSwitch; circuit and label already set)",
            "generator": "GeneratorToggle (SwitchLever) tied to the power system by GeneratorLink; RunningLamp lit by "
                         "RunningLampDriver (ThresholdLamp on generator_running); HeatGauge reads generator_heat",
            "battery": "BatteryBar (LinearGauge, readout battery_charge, descending)",
            "load": "LoadGauge (Gauge, readout load, red zone from 0.8)",
            "spares": "SparesDrawer (its Drawer node reads spares_remaining)",
            "sources": "every display and driver reads the power_system group (PowerSystem)",
            "eye": "OperatorEye (the standing eye, 0.5 m out, 0.55 m above the board's centre)"}},
        "footprint_mm": [PLATE_W, PLATE_Y1 - PLATE_Y0 + (STUB_Y1 - PLATE_Y1)],
        "stand_out_mm": max(i.box[5] for i in its),
        "mount": "back on Z=0 against the hull, centred on the board (X and Y); controls toward +Z; the board's centre "
                 "stands 1.1 m above the floor (Y -650 is knee height, Y +650 head height)",
        "operator_eye_m": [float(v) / 1000 for v in EYE],
        "reach_m": REACH / 1000,
        "mounts": mounts_record(its),
        "uses": list(USES),
        "triangles": tris,
        "triangles_by_part": {"body": rep["triangles"]},
        "checks": figs,
    })
    return {"slug": SLUG, "triangles": tris, "body": rep["triangles"]}


def mounts_record(its: list[Item]) -> list[dict]:
    return [mount.record(i.name, i.slug, i.offset, "board face") for i in its]


def _cameras(d) -> None:
    """Review cameras: the two concept viewpoints, the operator's eye (white and red light), orthographic front and profile."""
    eye = [round(float(v) / 1000, 3) for v in EYE]
    cams = [
        {"name": "concept_primary", "pos": [-0.8, 0.35, 1.9], "look_at": [0.0, 0.0, 0.0], "fov": 50.0},
        {"name": "concept_load_meter", "pos": [0.55, 0.25, 1.0], "look_at": [0.4, 0.1, 0.0], "fov": 45.0},
        {"name": "operator_eye", "pos": eye, "look_at": [0.0, -0.1, 0.0], "fov": 75.0},
        {"name": "operator_eye_red", "pos": eye, "look_at": [0.0, -0.1, 0.0], "fov": 75.0, "light": "red"},
        {"name": "profile_right", "pos": [4.0, 0.0, 0.2], "look_at": [0.0, 0.0, 0.2], "ortho": 1.6},
        {"name": "front", "pos": [0.0, 0.0, 4.0], "look_at": [0.0, 0.0, 0.0], "ortho": 1.6},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
