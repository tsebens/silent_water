"""science_bay: the science station's panel (a row of three module bays). Brief: assets/models/stations/science_bay/brief.yaml.

A long low housing against the starboard hull: a shallow kick-plinthed pedestal, a proud ledge band, a recessed module panel
raked back by RAKE_DEG so every screen faces up toward the standing eye, and a proud upper panel. Three bays are cut into
the module panel at a 360 mm pitch, each a stepped dark pocket (the plate seats in a step with 6 mm of gap all round, the
rear mount in a slot behind it) that reads on its own when empty. A module scene (the default fit: SCAN, SWEEP,
CAMERA) is set in each, its back 2 mm off the pocket floor (the mount rule); PROBE, or any of the four in any bay, fits the
same way, because every module is the shared `science_module_frame` chassis (340 x 280 mm, plate overlapping the opening).
Upper panel: the SCIENCE BAY plate, a running strip, decorative (unwired) knobs and lamps (local solids), and the shared noise
repeater. On the ledge: an orange trim.

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
from cadkit.solids import Solid, at, box, prism, expect, expect_in_front, export_solids_glb
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

# The housing: a polygon in (Y, Z) extruded along X, shaped like the life-support station. Bottom to top: a shallow kick and
# pedestal; a proud ledge band (the lower panel); the module panel, recessed and raked back RAKE_DEG; and a proud upper panel.
HOUSING_W = 1200.0
RAKE_DEG = 8.0
KICK_Y, KICK_Z = -1040.0, 65.0                  # the plinth's inset
PED_Z, PED_TOP_Y = 105.0, -250.0                # the pedestal's front: shallower than the module panel
LIP = np.array([-130.0, 200.0])                 # the ledge band's top front edge (y, z)
FACE_BASE = np.array([-60.0, 160.0])            # (y, z) where the ledge meets the module panel's face
MOD_LEN = 350.0                                 # the module panel, along its slope
REVEAL = 24.0                                   # the upper panel stands this far proud of the module panel
UP_LEN = 560.0                                  # the upper panel's top, along the slope from the module panel's base

# Bays: a wide shallow step takes the module plate (6 mm of gap all round), a slot behind it takes the rear mount.
PITCH = 360.0
BAY_X = (-PITCH, 0.0, PITCH)
STEP_W, STEP_H, STEP_D = 352.0, 292.0, 8.0      # the plate (340 x 280) seats in this step
OPEN_W, OPEN_H = 324.0, 264.0                   # the slot: the module body (312 x 252) slides in
POCKET_D = 52.0                                 # step + the frame's BODY_D (44) behind the plate
BAY_S = 182.0                                   # the bays' centre, along the module panel from its base
LINER_T = 1.0

# Face furniture on the upper panel (s along the slope from the module panel's base, x along the hull).
PLATE_S, PLATE_X, PLATE_W, PLATE_H = 525.0, -300.0, 300.0, 46.0
STRIP_S, STRIP_W, STRIP_H = 368.0, 1100.0, 14.0
TRIM_V, TRIM_W, TRIM_H = 40.0, 1100.0, 16.0
GAUGE_R, GAUGE_X, GAUGE_S = 0.05, 440.0, 455.0
DECOR_S = 450.0                                 # decorative, unwired controls (local solids: the triangle budget is tight)
KNOB_X, KNOB_R, KNOB_H = (-430.0, -350.0, -270.0), 18.0, 22.0
LAMP_X, LAMP_W = (-150.0, -100.0, -50.0, 0.0), 18.0

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


def on_upper(s: float, out: float = 0.0, x: float = 0.0) -> np.ndarray:
    return on_face(s, REVEAL + out, x)


def housing_top() -> np.ndarray:
    return on_face(UP_LEN, REVEAL)


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
    out.append(Item("NoiseGauge", "gauge", NOISE_GAUGE_SCENE, on_upper(GAUGE_S, off, GAUGE_X), FACE_BASIS,
                    (-ge["bezel"] * r, -ge["plate_bottom"] * r, -behind, ge["bezel"] * r, ge["bezel"] * r, front), off,
                    "upper panel", "upper", radius=GAUGE_R))
    return out


def _pocket_cutters(x: float) -> list[bd.Shape]:
    """The bay's two cuts: the slot (down to POCKET_D) and the wider step for the plate (down to STEP_D), laid on the face."""
    p = on_face(BAY_S, -POCKET_D, x)
    q = on_face(BAY_S, -STEP_D, x)
    return [at(box(OPEN_W, OPEN_H, POCKET_D + 30.0), p[0], p[1], p[2], rx=FACE_RX),
            at(box(STEP_W, STEP_H, STEP_D + 30.0), q[0], q[1], q[2], rx=FACE_RX)]


def solids() -> list[Solid]:
    top = housing_top()
    pts = [(FLOOR_Y, 0.0), (FLOOR_Y, KICK_Z), (KICK_Y, KICK_Z), (KICK_Y, PED_Z), (PED_TOP_Y, PED_Z), (PED_TOP_Y, LIP[1]),
           (LIP[0], LIP[1]), (FACE_BASE[0], FACE_BASE[1]), tuple(on_face(MOD_LEN)[1:]), tuple(on_face(MOD_LEN, REVEAL)[1:]),
           (top[1], top[2]), (top[1], 0.0)]
    with bd.BuildPart() as b:
        with bd.BuildSketch(bd.Plane.YZ):
            bd.Polygon(*pts, align=None)
        bd.extrude(amount=HOUSING_W)
    housing = at(b.part, x=-HOUSING_W / 2)
    for x in BAY_X:
        for c in _pocket_cutters(x):
            housing = housing - c
    liners = []
    for x in BAY_X:
        p = on_face(BAY_S, -POCKET_D + 0.5, x)
        liners.append(at(box(OPEN_W - 2.0, OPEN_H - 2.0, LINER_T), p[0], p[1], p[2], rx=FACE_RX))
    pl = on_upper(PLATE_S, 0.0, PLATE_X)
    plate = at(box(PLATE_W, PLATE_H, 2.5), pl[0], pl[1], pl[2], rx=FACE_RX)
    st = on_upper(STRIP_S, 0.0)
    strip = at(box(STRIP_W, STRIP_H, 3.0), st[0], st[1], st[2], rx=FACE_RX)
    tr = on_ledge(TRIM_V, 0.0)
    trim = at(box(TRIM_W, TRIM_H, 3.0), tr[0], tr[1], tr[2], rx=LEDGE_RX)
    inset = at(box(1040.0, 520.0, 4.0), 0.0, -600.0, PED_Z)                  # a dark panel on the pedestal's front
    decor = []
    for x in KNOB_X:
        k = on_upper(DECOR_S, 0.0, x)
        decor.append(Solid(at(prism(6, KNOB_R, KNOB_H), k[0], k[1], k[2], rx=FACE_RX), "control_interface"))
    for x in LAMP_X:
        k = on_upper(DECOR_S, 0.0, x)
        decor.append(Solid(at(box(LAMP_W, LAMP_W, 5.0), k[0], k[1], k[2], rx=FACE_RX), "indicator_ok"))
    parts = ([Solid(housing, "interior_panel"), Solid(inset, "interior_dark")] + [Solid(s, "interior_dark") for s in liners]
             + [Solid(plate, "label_plate"), Solid(strip, "interior_dark"), Solid(trim, "control_interface")] + decor)
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
    expect(body_w < OPEN_W < fw, f"slot {OPEN_W:.0f} mm takes the {body_w:.0f} mm rear mount; the {fw:.0f} mm plate is wider")
    expect(body_h < OPEN_H < fh, f"slot {OPEN_H:.0f} mm tall takes the {body_h:.0f} mm rear mount; the {fh:.0f} mm plate is taller")
    expect(1.0 <= (STEP_W - fw) / 2 <= 7.0 and 1.0 <= (STEP_H - fh) / 2 <= 7.0,
           f"a narrow gap all round the plate in its step ({(STEP_W - fw) / 2:.1f} x {(STEP_H - fh) / 2:.1f} mm a side)")
    expect(POCKET_D >= STEP_D + 44.0, "bay as deep as the step plus the frame's rear mount (44 mm)")
    expect(mount.stand_off(0.0) + 44.0 <= POCKET_D, "the module's rear mount lies inside the bay")
    expect(PITCH - fw >= 10.0, f"neighbouring plates at least 10 mm apart ({PITCH - fw:.0f})")
    expect(BAY_X[-1] + fw / 2 <= HOUSING_W / 2 - 40.0, "end bays leave a 40 mm cheek of housing")
    top = housing_top()
    pocket_hi = BAY_S + STEP_H / 2
    expect(pocket_hi <= MOD_LEN - 20.0, "the bays stop 20 mm short of the top of the module panel")
    expect(BAY_S - STEP_H / 2 >= 20.0, "the bays start 20 mm above the ledge")
    back_y, back_z = on_face(pocket_hi, -POCKET_D)[1:]
    depths = [float(on_face(s_)[2]) for s_ in (0.0, MOD_LEN)]
    expect(min(depths) >= 100.0 and max(depths) <= 160.0 + 0.01, f"module panel {min(depths):.0f}..{max(depths):.0f} mm deep (a thick section)")
    expect(PED_Z < min(depths), f"the lower section ({PED_Z:.0f} mm) is shallower than the module panel ({min(depths):.0f} mm)")
    expect(REVEAL >= 15.0, "the upper panel stands proud of the module panel")
    expect(LIP[1] > min(depths), "the ledge band stands proud of the module panel")
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

    # The repeater and the decorative controls sit on the upper panel: above the module panel, below its top, inside its width.
    for it in its:
        if it.plane != "upper":
            continue
        ss = [float(FACE_T @ (c - FACE_ORIGIN)) for c in it.corners()]
        expect(min(ss) >= MOD_LEN + 10.0 and max(ss) <= UP_LEN - 10.0, f"{it.name} on the upper panel ({min(ss):.0f}..{max(ss):.0f}, panel {MOD_LEN:.0f}..{UP_LEN:.0f})")
        expect(abs(it.corners()[:, 0]).max() <= HOUSING_W / 2 - 20.0, f"{it.name} inside the housing's width")
    for lo_s, hi_s, what in ((PLATE_S - PLATE_H / 2, PLATE_S + PLATE_H / 2, "plate"), (STRIP_S - STRIP_H / 2, STRIP_S + STRIP_H / 2, "strip"),
                             (DECOR_S - KNOB_R, DECOR_S + KNOB_R, "decorative controls")):
        expect(MOD_LEN + 5.0 <= lo_s and hi_s <= UP_LEN - 5.0, f"the {what} lies on the upper panel")

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
        "summary": "Science bay: a shallow housing with three module bays in a recessed, raked panel at chest height over a ledge band, "
                   "a SCIENCE BAY plate and running strip above, the shared noise repeater and decorative controls on a proud upper panel. Each bay is an "
                   "anchor (Bay0..Bay2) whose child `Module` is a module scene (default SCAN, SWEEP, CAMERA); any of the "
                   "four module scenes fits any bay, and an empty bay is a dark pocket.",
        "tags": ["panel", "station", "science", "bay", "module", "scan", "sweep", "probe", "camera", "ledge", "standing"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"wire": {
            "bays": "Bay0..Bay2: each holds a module scene as its child `Module` (a ScienceModule root); to change the "
                    "fit replace that child with another module scene (any of the four fits any bay)",
            "operator": "no script on the panel: the placement arc wraps it in ScienceStation (as the map table is wrapped) "
                        "with OperatorPoint (feet) and OperatorEye (the standing eye, 0.5 m out, 0.55 m above the centre)",
            "noise": "NoiseGauge (acoustics_readouts) on the upper panel"}},
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
