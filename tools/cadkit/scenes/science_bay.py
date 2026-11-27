"""science_bay: the science station's panel (a row of three module bays). Brief: assets/models/stations/science_bay/brief.yaml.

A long low housing against the starboard hull: a kick-plinthed pedestal, a sloped hand ledge, and above the ledge a face
raked back by RAKE_DEG so every screen faces up toward the standing eye. Three bay recesses are cut into the raked face
at a 360 mm pitch, each a dark pocket that reads on its own when empty. A module scene (the default fit: SCAN, SWEEP,
CAMERA) is set in each, its back 2 mm off the pocket floor (the mount rule); PROBE, or any of the four in any bay, fits the
same way, because every module is the shared `science_module_frame` chassis (340 x 280 mm, plate overlapping the opening).
Above the row: the SCIENCE BAY plate and a running strip. On the ledge: an orange trim and the shared noise repeater.

Local solids (static, used once): the housing with its pockets, pocket liners, the plate, the strip, the ledge trim.
Everything else is a catalogue scene. No scripts: `OperatorPoint` and `OperatorEye` are markers for the placement arc,
which wraps the scene in `ScienceStation` as the map table is wrapped (the module scenes' roots are their own scripts).

Frame (mm): X along the hull, Y up, Z out of the hull (the mount face). The origin is the station's centre, 1.1 m above
the floor, so Y = -1100 is the floor and the standing eye is at (0, 550, 500).
"""
import json
import math

import build123d as bd
import numpy as np

from cadkit import mount
from cadkit.solids import Solid, at, box, expect, expect_in_front, export_solids_glb
from cadkit.library import entry, note, out_dir, res, scene_path, write_entry
from cadkit.tscn import Scene, Xform

SLUG, GROUP = "science_bay", "stations"
MODULES = ("scan_module", "sweep_module", "camera_module", "probe_module")
DEFAULT_FIT = ("scan_module", "sweep_module", "camera_module")      # ModuleLoadout default: SCAN, SWEEP, CAMERA
USES: list[str] = list(MODULES) + ["science_module_frame", "gauge"]
NOISE_GAUGE_SCENE = "res://src/noise/noise_gauge.tscn"      # an existing scene: a configured gauge (its entry is `gauge`'s)
TRIANGLE_BUDGET = 4000

# The brief's constraints (concept #529).
MAX_ALONG, MAX_OUT = 1200.0, 450.0              # along the hull; deep (Decision #600)
EYE = np.array([0.0, 550.0, 500.0])             # operator_eye_m
SHOULDER = EYE - np.array([0.0, 250.0, 0.0])
REACH = 1100.0                                  # reach_m, from the shoulder
FLOOR_Y = -1100.0                               # the floor, in the station frame (the centre is 1.1 m up)
WAIST_Y = FLOOR_Y + 1000.0                      # about 1.0 m above the floor
FACE_MAX_DEG = 60.0                             # a screen may face the eye within this angle

# The housing: a polygon in (Y, Z) extruded along X. Its upper face is raked back RAKE_DEG; the ledge slopes down to the lip.
HOUSING_W = 1200.0
RAKE_DEG = 12.0
FACE_BASE = np.array([-20.0, 130.0])            # (y, z) where the ledge meets the raked face
FACE_LEN = 430.0                                # the raked face, along its slope
LIP = np.array([-95.0, 436.0])                  # the ledge's front edge
KICK_Y, KICK_Z, BODY_FRONT_Z = -1040.0, 400.0, 436.0   # the plinth's inset, then the pedestal's front

# Bays.
PITCH = 360.0
BAY_X = (-PITCH, 0.0, PITCH)
OPEN_W, OPEN_H = 324.0, 264.0                   # a pocket's opening: the module body (312 x 252) slides in, the plate (340 x 280) overlaps it
POCKET_D = 44.0                                 # the frame's BODY_D
BAY_S = 170.0                                   # the pocket's centre, along the raked face from its base
LINER_T = 1.0

# Face furniture, along the raked face (s) and the ledge (v from the lip).
PLATE_S, PLATE_W, PLATE_H = 385.0, 300.0, 46.0
STRIP_S, STRIP_W, STRIP_H = 415.0, 1100.0, 14.0
TRIM_V, TRIM_W, TRIM_H = 40.0, 1100.0, 16.0
GAUGE_R, GAUGE_X, GAUGE_V = 0.05, 480.0, 165.0

_RAKE = math.radians(RAKE_DEG)
_X = np.array([1.0, 0.0, 0.0])


def _frame(t_yz: np.ndarray) -> tuple[np.ndarray, np.ndarray, float]:
    """A plane's tangent (up the plane) and normal (out of it), as 3-vectors, and the rx (deg) that lays a local box on it."""
    t = t_yz / np.linalg.norm(t_yz)
    t3, n3 = np.array([0.0, t[0], t[1]]), np.array([0.0, -t[1], t[0]])
    return t3, n3, -math.degrees(math.atan2(n3[1], n3[2]))


FACE_T, FACE_N, FACE_RX = _frame(np.array([math.cos(_RAKE), -math.sin(_RAKE)]))
LEDGE_T, LEDGE_N, LEDGE_RX = _frame(FACE_BASE - LIP)
FACE_ORIGIN = np.array([0.0, *FACE_BASE])
LIP_ORIGIN = np.array([0.0, *LIP])
LEDGE_LEN = float(np.linalg.norm(FACE_BASE - LIP))


def on_face(s: float, out: float = 0.0, x: float = 0.0) -> np.ndarray:
    return FACE_ORIGIN + _X * x + FACE_T * s + FACE_N * out


def on_ledge(v: float, out: float = 0.0, x: float = 0.0) -> np.ndarray:
    return LIP_ORIGIN + _X * x + LEDGE_T * v + LEDGE_N * out


def housing_top() -> np.ndarray:
    return on_face(FACE_LEN)


class Item:
    """One placed catalogue scene: its origin, which way it faces, and what it occupies (a box in its own frame)."""

    def __init__(self, name: str, slug: str, scene: str, origin: np.ndarray, basis: np.ndarray, local_box: tuple,
                 offset: float, host: str, plane: str, **props):
        self.name, self.slug, self.scene, self.props = name, slug, scene, props
        self.origin, self.basis, self.local_box, self.offset, self.host, self.plane = origin, basis, local_box, offset, host, plane

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


def module_box(slug: str) -> tuple:
    e = entry(slug)
    w, h = e["footprint_mm"]
    d = e.get("depth_mm") or {"behind_origin": 0.0, "in_front_of_origin": e["stand_out_mm"]}
    return (-w / 2, -h / 2, -d["behind_origin"], w / 2, h / 2, d["in_front_of_origin"])


FACE_BASIS = np.column_stack([_X, FACE_T, FACE_N])
LEDGE_BASIS = np.column_stack([_X, LEDGE_T, LEDGE_N])


def bay_item(i: int, slug: str) -> Item:
    """The module `slug` set in bay `i`: its back MOUNT_GAP_MM off the pocket floor."""
    off = mount.stand_off(0.0)
    return Item(f"Bay{i}", slug, scene_path(slug), on_face(BAY_S, -POCKET_D + off, BAY_X[i]), FACE_BASIS, module_box(slug), off,
                f"pocket floor of bay {i}", "face")


def items() -> list[Item]:
    out = [bay_item(i, slug) for i, slug in enumerate(DEFAULT_FIT)]
    ge = entry("gauge")["extent_radii"]
    r = GAUGE_R * 1000
    behind = (entry("gauge").get("depth_mm") or {"behind_origin": 0.0})["behind_origin"]
    front = (entry("gauge").get("depth_mm") or {"in_front_of_origin": entry("gauge")["stand_out_mm"]})["in_front_of_origin"]
    off = mount.stand_off(behind)
    out.append(Item("NoiseGauge", "gauge", NOISE_GAUGE_SCENE, on_ledge(GAUGE_V, off, GAUGE_X), LEDGE_BASIS,
                    (-ge["bezel"] * r, -ge["plate_bottom"] * r, -behind, ge["bezel"] * r, ge["bezel"] * r, front), off,
                    "ledge top", "ledge", radius=GAUGE_R))
    return out


def _pocket_cutter(x: float) -> bd.Shape:
    """The opening's box, from POCKET_D below the raked face to a little above it, laid on the face."""
    p = on_face(BAY_S, -POCKET_D, x)
    return at(box(OPEN_W, OPEN_H, POCKET_D + 30.0), p[0], p[1], p[2], rx=FACE_RX)


def solids() -> list[Solid]:
    top = housing_top()
    with bd.BuildPart() as b:
        with bd.BuildSketch(bd.Plane.YZ):
            bd.Polygon((FLOOR_Y, 0.0), (FLOOR_Y, KICK_Z), (KICK_Y, KICK_Z), (KICK_Y, BODY_FRONT_Z), (LIP[0], LIP[1]),
                       (FACE_BASE[0], FACE_BASE[1]), (top[1], top[2]), (top[1], 0.0), align=None)
        bd.extrude(amount=HOUSING_W)
    housing = at(b.part, x=-HOUSING_W / 2)
    for x in BAY_X:
        housing = housing - _pocket_cutter(x)
    liners = []
    for x in BAY_X:
        p = on_face(BAY_S, -POCKET_D + 0.5, x)
        liners.append(at(box(OPEN_W - 2.0, OPEN_H - 2.0, LINER_T), p[0], p[1], p[2], rx=FACE_RX))
    pl = on_face(PLATE_S, 0.0)
    plate = at(box(PLATE_W, PLATE_H, 2.5), pl[0], pl[1], pl[2], rx=FACE_RX)
    st = on_face(STRIP_S, 0.0)
    strip = at(box(STRIP_W, STRIP_H, 3.0), st[0], st[1], st[2], rx=FACE_RX)
    tr = on_ledge(TRIM_V, 0.0)
    trim = at(box(TRIM_W, TRIM_H, 3.0), tr[0], tr[1], tr[2], rx=LEDGE_RX)
    inset = at(box(1040.0, 520.0, 4.0), 0.0, -600.0, BODY_FRONT_Z)           # a recessed dark panel on the pedestal's front
    parts = ([Solid(housing, "interior_panel"), Solid(inset, "interior_dark")] + [Solid(s, "interior_dark") for s in liners]
             + [Solid(plate, "label_plate"), Solid(strip, "interior_dark"), Solid(trim, "control_interface")])
    expect_in_front(parts, SLUG)
    return parts


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


def checks(its: list[Item], parts: list[Solid]) -> dict:
    frame = entry("science_module_frame")
    # Size and the mount face: the housing alone, then everything in it.
    lo = np.min([_bb(p.shape)[:3] for p in parts], axis=0)
    hi = np.max([_bb(p.shape)[3:] for p in parts], axis=0)
    all_lo = np.min([lo] + [i.corners().min(axis=0) for i in its], axis=0)
    all_hi = np.max([hi] + [i.corners().max(axis=0) for i in its], axis=0)
    along, out = float(all_hi[0] - all_lo[0]), float(all_hi[2])
    expect(along <= MAX_ALONG + 0.01, f"station at most {MAX_ALONG:.0f} mm along the hull ({along:.0f})")
    expect(out <= MAX_OUT + 0.01, f"station at most {MAX_OUT:.0f} mm deep (stands {out:.0f})")
    expect(all_lo[2] >= -0.01, f"nothing behind the mount face (Z=0): lowest Z {all_lo[2]:.1f}")
    expect(all_lo[1] >= FLOOR_Y - 0.01, f"nothing below the floor (Y {all_lo[1]:.0f})")
    mounts = mounts_record(its)
    expect(not mount.problems(SLUG, {"mounts": mounts}, entry), "no instanced face coplanar with its host face")

    # The bays: pocket against the module frame, and against each other.
    fw, fh = frame["footprint_mm"]
    body_w, body_h = 312.0, 252.0     # the frame's rear mount (science_module_frame.py BODY_W, BODY_H); the plate is the footprint
    expect(body_w < OPEN_W < fw, f"pocket opening {OPEN_W:.0f} mm takes the {body_w:.0f} mm rear mount and the {fw:.0f} mm plate overlaps it")
    expect(body_h < OPEN_H < fh, f"pocket opening {OPEN_H:.0f} mm tall takes the {body_h:.0f} mm rear mount and the {fh:.0f} mm plate overlaps it")
    expect(POCKET_D >= 44.0, "pocket as deep as the frame's rear mount (44 mm)")
    expect(PITCH - fw >= 10.0, f"neighbouring plates at least 10 mm apart ({PITCH - fw:.0f})")
    expect(BAY_X[-1] + fw / 2 <= HOUSING_W / 2 - 40.0, "end bays leave a 40 mm cheek of housing")
    top = housing_top()
    pocket_hi = BAY_S + OPEN_H / 2
    expect(pocket_hi <= FACE_LEN - 20.0, "the pockets stop 20 mm short of the top of the face")
    back_y, back_z = on_face(pocket_hi, -POCKET_D)[1:]
    expect(back_z >= 10.0, f"the pocket's back stays 10 mm in front of the hull face (Z {back_z:.1f})")

    # Every module type, in every bay: size, waist-to-eye band, ledge clearance, reach.
    reach: dict[str, float] = {}
    heights = []
    for slug in MODULES:
        for i in range(3):
            it = bay_item(i, slug)
            c = it.corners()
            heights.append((float(c[:, 1].min()), float(c[:, 1].max())))
            expect(c[:, 1].min() >= WAIST_Y, f"{slug} in bay {i}: lowest point {c[:, 1].min():.0f} at or above the waist ({WAIST_Y:.0f})")
            expect(c[:, 1].max() <= EYE[1], f"{slug} in bay {i}: highest point {c[:, 1].max():.0f} at or below the eye ({EYE[1]:.0f})")
            expect(np.all(c[:, 2] <= MAX_OUT), f"{slug} in bay {i} within the station's depth")
            x0, y0, _, x1, y1, z1 = it.local_box       # the face standing out of the pocket: the plate's front and the highest point
            above = [float(LEDGE_N @ (it.local_to_world((x, y0, z)) - on_ledge(0.0))) for x in (x0, x1) for z in (56.0, z1)]
            expect(min(above) >= 20.0, f"{slug} in bay {i}: at least 20 mm above the ledge ({min(above):.0f})")
            d = float(max(np.linalg.norm(p - SHOULDER) for p in c))
            reach[f"{slug}@{i}"] = round(d, 1)
            expect(d <= REACH, f"{slug} in bay {i}: farthest point {d:.0f} mm from the shoulder, within {REACH:.0f}")
            expect(abs(c[:, 0]).max() <= HOUSING_W / 2 - 40.0, f"{slug} in bay {i} within the housing's width")
    by = {i.name: i for i in its}
    g = by["NoiseGauge"]
    dg = float(max(np.linalg.norm(c - SHOULDER) for c in g.corners()))
    reach["NoiseGauge"] = round(dg, 1)
    expect(dg <= REACH, f"the noise repeater within reach {REACH:.0f} mm of the shoulder ({dg:.0f})")

    # The repeater sits on the ledge: along it, inside the housing, above it, clear of the pocket row.
    vs = [float(LEDGE_T @ (c - LIP_ORIGIN)) for c in g.corners()]
    expect(min(vs) >= 15.0 and max(vs) <= LEDGE_LEN - 15.0, f"the repeater lies on the ledge ({min(vs):.0f}..{max(vs):.0f} of {LEDGE_LEN:.0f})")
    expect(abs(g.corners()[:, 0]).max() <= HOUSING_W / 2 - 20.0, "the repeater inside the housing's width")

    # Grab boxes apart: neighbouring modules and the repeater, 10 mm or more (axis-aligned boxes in the station frame).
    boxes = {i.name: i.aabb for i in its}
    names = list(boxes)
    for a in range(len(names)):
        for b2 in range(a + 1, len(names)):
            ba, bb_ = boxes[names[a]], boxes[names[b2]]
            sep = max(max(bb_[k] - ba[k + 3], ba[k] - bb_[k + 3]) for k in range(3))
            expect(sep >= 10.0, f"{names[a]} and {names[b2]} at least 10 mm apart ({sep:.0f})")

    # Sight lines from the eye to each module's face (centre and the two screen-side points) and the repeater, and the
    # angle each face makes with the line to the eye. Other items block; the housing is below and behind all of them.
    targets = {}
    for it in its:
        if it.plane == "face":
            for tag, (lx, ly) in {"centre": (0.0, 0.0), "left": (-110.0, 40.0), "right": (110.0, 40.0)}.items():
                targets[f"{it.name} {tag}"] = (it, it.local_to_world((lx, ly, 56.0)))
    targets["NoiseGauge"] = (g, g.local_to_world((0.0, 0.0, 14.0)))
    for name, (owner, p) in targets.items():
        for other in its:
            if other is owner:
                continue
            expect(not _seg_hits(EYE, p, other.aabb), f"sight line from the eye to {name} blocked by {other.name}")
        expect(float(FACE_N @ (EYE - on_face(0.0))) > 0 and float(owner.normal @ (p - owner.origin)) >= 0,
               f"{name} and the eye on the same side of its face")
        v = EYE - p
        ang = float(np.degrees(np.arccos(float(owner.normal @ v) / np.linalg.norm(v))))
        expect(ang <= FACE_MAX_DEG, f"{name} faces the eye within {FACE_MAX_DEG:.0f} degrees ({ang:.0f})")
    worst_face = max(float(np.degrees(np.arccos(float(o.normal @ (EYE - p)) / np.linalg.norm(EYE - p)))) for o, p in targets.values())
    return {"reach_mm": reach, "reach_limit_mm": REACH, "sight_lines": len(targets), "along_hull_mm": round(along, 1),
            "deep_mm": round(out, 1), "module_y_mm": [round(min(h[0] for h in heights), 1), round(max(h[1] for h in heights), 1)],
            "worst_face_deg": round(worst_face, 1)}


def mounts_record(its: list[Item]) -> list[dict]:
    return [mount.record(i.name, i.slug, i.offset, i.host) for i in its]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    parts = solids()
    its = items()
    figs = checks(its, parts)
    rep = export_solids_glb(parts, d / f"{SLUG}_body.glb", "ScienceBayBody")
    s = Scene("ScienceBay")
    s.node("Body", instance=rep["glb"])
    for i in its:
        xf = Xform(basis=i.basis, origin=tuple(float(v) / 1000 for v in i.origin))
        if i.plane == "face":     # the bay's anchor; the module is its child, so any other module can replace it
            s.node(i.name, props={"transform": xf})
            s.node("Module", parent=i.name, type_=None, instance=i.scene)
        else:
            s.node(i.name, instance=i.scene, props={"transform": xf, **i.props})
    s.node("OperatorEye", props={"transform": Xform(origin=tuple(float(v) / 1000 for v in EYE))})
    s.node("OperatorPoint", props={"transform": Xform(origin=(0.0, FLOOR_Y / 1000, EYE[2] / 1000))})
    s.write(d / f"{SLUG}.tscn")
    tris = rep["triangles"] + sum(entry(i.slug)["triangles"] for i in its)
    heaviest = sorted((entry(m)["triangles"] for m in MODULES), reverse=True)[:3]
    worst = rep["triangles"] + sum(heaviest) + entry("gauge")["triangles"]
    expect(tris <= TRIANGLE_BUDGET, f"panel within the {TRIANGLE_BUDGET:,} triangle budget with the default fit ({tris})")
    expect(worst <= TRIANGLE_BUDGET, f"panel within the {TRIANGLE_BUDGET:,} triangle budget with the heaviest three modules ({worst})")
    _cameras(d)
    figs["triangles_heaviest_fit"] = worst
    write_entry(GROUP, SLUG, {
        "kind": "panel",
        "summary": "Science bay: a long low raked housing with three module bays at chest height over a sloped hand ledge, "
                   "a SCIENCE BAY plate and running strip above, the shared noise repeater on the ledge. Each bay is an "
                   "anchor (Bay0..Bay2) whose child `Module` is a module scene (default SCAN, SWEEP, CAMERA); any of the "
                   "four module scenes fits any bay, and an empty bay is a dark pocket.",
        "tags": ["panel", "station", "science", "bay", "module", "scan", "sweep", "probe", "camera", "ledge", "standing"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"wire": {
            "bays": "Bay0..Bay2: each holds a module scene as its child `Module` (a ScienceModule root); to change the "
                    "fit replace that child with another module scene (any of the four fits any bay)",
            "operator": "no script on the panel: the placement arc wraps it in ScienceStation (as the map table is wrapped) "
                        "with OperatorPoint (feet) and OperatorEye (the standing eye, 0.5 m out, 0.55 m above the centre)",
            "noise": "NoiseGauge (acoustics_readouts) on the ledge"}},
        "footprint_mm": [figs["along_hull_mm"], figs["deep_mm"]],
        "stand_out_mm": figs["deep_mm"],
        "mount": "back on Z=0 against the starboard hull (X along the hull, Z out into the aisle); the station's centre stands "
                 "1.1 m above the floor (Y -1100 is the floor); the bay face is raked back 12 degrees so screens face the eye",
        "operator_eye_m": [float(v) / 1000 for v in EYE],
        "reach_m": REACH / 1000,
        "mounts": mounts_record(its),
        "uses": list(USES),
        "triangles": tris,
        "triangle_budget": TRIANGLE_BUDGET,
        "triangles_by_part": {"body": rep["triangles"]},
        "checks": figs,
    })
    return {"slug": SLUG, "triangles": tris, "body": rep["triangles"]}


def _cameras(d) -> None:
    """Review cameras: both concept viewpoints, the operator's eye (white and red light), orthographic front and profile."""
    eye = [round(float(v) / 1000, 3) for v in EYE]
    look = [0.0, 0.05, 0.1]
    cams = [
        {"name": "concept_primary", "pos": [-1.2, 0.35, 2.0], "look_at": [0.1, 0.0, 0.1], "fov": 50.0},
        {"name": "concept_modules", "pos": [-0.35, 0.3, 1.1], "look_at": [0.0, 0.15, 0.1], "fov": 45.0},
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
