"""pilot_station: the pilot's station in the glass dome: the seat and one knee-height instrument strip (shell arc, #481).

Brief: assets/models/stations/pilot_station/brief.yaml (concept #446, structure from `pilot_strip_primary.png`).
Frame: floor at Y=0, the seat's origin at X=0, Z=0 on the centreline, the pilot facing -Z toward the dome.

The strip is a fascia built of flat facets, one per instrument group, so every instrument lies flat on its facet. It runs
in two wings that follow the dome glass (read from the hull's `layout.json`, placed by the pilot's program position),
standing off it, with an orange end cap either side of a clear gap at the apex. Each wing's section is a raked back
(matching the glass above knee height), a short ledge, and a fascia tilted up toward the eye. Instruments are not
here: this scene leaves a marked anchor for each (the next arc fills them), and a bore in the fascia where the navball's
rear half sinks. Everything the strip is checked against (the glass, the rim ring, the seat's armrests, joysticks and
pedals, the gap, the knee, the sight line) is measured on the solids below.
"""
import json
import math

import build123d as bd
import numpy as np

from cadkit import library
from cadkit.solids import Solid, at, expect, export_solids_glb, prism
from cadkit.library import entry, note, out_dir, res, scene_module, scene_path, write_entry
from cadkit.tscn import Scene, Xform

SLUG, GROUP = "pilot_station", "stations"
USES: list[str] = ["pilot_seat", "operator_seat", "joystick", "multidisplay", "navball", "depth_finder", "gauge",
                   "guarded_toggle", "indicator_lamp"]
TRIANGLE_BUDGET = 12000

# --- where the station sits in the hull (the program's pilot position and the cockpit floor), mm
HULL_Z0 = -3800.0          # program.yaml `pilot` z: the seat's origin
HULL_Y0 = -1150.0          # layout.json cockpit floor y
LAYOUT = library.REPO / "assets/models/vehicles/sub_interior/layout.json"
RIM_HALF_MM = 60.0         # build_sub_hull.py RIM_HALF
RIM_INSET_MM = 80.0        # the ring stands this far in from the wall
EYE_MM = np.array([0.0, 1150.0, 0.0])    # seated eye (brief: seated_eye_height_m 1.15)

# --- the strip's section, in (d, y): d toward the pilot from the back's foot, y up, mm
BOT, TOP = 440.0, 780.0    # foot and top of the back; the strip's top edge is TOP
RAKE = 105.0               # the back leans away from the pilot by this much over its height, as the glass does
LEDGE = 90.0               # the flat top, before the fascia starts
FASCIA_DEG = 40.0          # the fascia's normal is this far above horizontal (toward the eye)
FASCIA_L = 330.0           # fascia length, top to bottom
LIP = 60.0                 # depth of the front's edge face under the fascia
STANDOFF = 85.0            # the foot of the back stands this far off the glass
GAP = 600.0                # the clear gap at the apex, X
CAP_T, CAP_PROUD = 40.0, 10.0    # the orange end cap's thickness along the wing, and how far it stands proud
MARGIN = 30.0              # space between an instrument and its facet's edge, each side

# --- the hologram: the map table's display model, about 20 cm, above the depth finder on the strip's top
HOLO_H, HOLO_R = 200.0, 100.0
HOLO_BASE_R, HOLO_BASE_H, HOLO_BASE_D = 75.0, 22.0, -30.0    # projector pad: radius, height, d from the back's foot

# --- instruments (sizes come from the catalogue entries; settings are those the next arc will set)
SPEED_R, NOISE_R = 0.10, 0.11      # gauge radii, m
TOGGLE_PITCH, LAMP_PITCH = 84.0, 50.0
LAMP_PLATE_T = 8.0
BORE_D, BORE_SIDES = 36.0, 24      # the navball's bore into the fascia: depth (keep_clear 34) and sides


def _gauge_extent(radius_m: float) -> tuple[float, float, float]:
    """A round dial's half-width, top and bottom extents (mm) from the gauge entry."""
    e = entry("gauge")["extent_radii"]
    r = radius_m * 1000.0
    return e["bezel"] * r, e["bezel"] * r, e["plate_bottom"] * r


def _facets() -> dict[str, list[tuple[str, float, str]]]:
    """Per wing: facets from the gap outward: (name, length mm, what it carries)."""
    df = entry("depth_finder")["footprint_mm"][0]
    md = entry("multidisplay")["footprint_mm"][0]
    nb = entry("navball")["footprint_mm"][0]
    sw = entry("guarded_toggle")["footprint_mm"][0]
    m2 = 2 * MARGIN
    return {
        "left": [("DepthFinder", df + m2, "depth finder, with the hologram above it"),
                 ("Multidisplay", md + m2, "multidisplay"),
                 ("Speed", 2 * _gauge_extent(SPEED_R)[0] + m2, "speed and throttle gauge")],
        "right": [("Navball", nb + m2, "navball"),
                  ("Switches", 3 * TOGGLE_PITCH + sw + m2, "four light switches"),
                  ("Lamps", 2 * LAMP_PITCH + entry("indicator_lamp")["footprint_mm"][0] + m2, "three warning lamps"),
                  ("Noise", 2 * _gauge_extent(NOISE_R)[0] + m2, "noise repeater")],
    }


# ---------------------------------------------------------------------------------------------------------------- hull
_HULL: dict = {}


def _rings() -> tuple[np.ndarray, list[np.ndarray], float]:
    """The dome's rings in the station's frame (mm): z values, and (n, 2) points (x, y) per ring; and the rim's z."""
    if not _HULL:
        lay = json.loads(LAYOUT.read_text())
        zs, pts = [], []
        for r in lay["hull"]["rings"]:
            zs.append(r["z"] * 1000.0 - HULL_Z0)
            pts.append(np.array(r["points"], float) * 1000.0 - np.array([0.0, HULL_Y0]))
        cockpit_end = next(c for c in lay["compartments"] if c["id"] == "cockpit")["z"][1]
        _HULL.update(z=np.array(zs), pts=pts, rim=cockpit_end * 1000.0 - HULL_Z0)
    return _HULL["z"], _HULL["pts"], _HULL["rim"]


def ring_at(z: float) -> np.ndarray:
    zs, pts, _ = _rings()
    i = int(np.clip(np.searchsorted(zs, z) - 1, 0, len(zs) - 2))
    t = (z - zs[i]) / (zs[i + 1] - zs[i])
    return (1 - t) * pts[i] + t * pts[i + 1]


def halfwidth(z: float, y: float) -> float:
    """How far the glass is from the centreline (X>0 side) at height y and station z, mm."""
    p = ring_at(z)
    best = -1e9
    for k in range(len(p)):
        a, b = p[k], p[(k + 1) % len(p)]
        if (a[1] - y) * (b[1] - y) <= 0 and a[1] != b[1]:
            best = max(best, a[0] + (y - a[1]) / (b[1] - a[1]) * (b[0] - a[0]))
    return best


def inside_dome(x: float, y: float, z: float) -> bool:
    p = ring_at(z)
    c = False
    for k in range(len(p)):
        a, b = p[k], p[(k + 1) % len(p)]
        if (a[1] > y) != (b[1] > y) and x < a[0] + (y - a[1]) / (b[1] - a[1]) * (b[0] - a[0]):
            c = not c
    return c


def glass_cloud() -> np.ndarray:
    """Dense points on the glass from the bow to the rim ring, (n, 3) mm."""
    if "cloud" in _HULL:
        return _HULL["cloud"]
    zs, _, rim = _rings()
    out = []
    for z in np.arange(zs[0], rim + 1.0, 20.0):
        p = ring_at(float(z))
        for k in range(len(p)):
            a, b = p[k], p[(k + 1) % len(p)]
            for t in (0.0, 0.25, 0.5, 0.75):
                q = a + t * (b - a)
                out.append((q[0], q[1], z))
    _HULL["cloud"] = np.array(out)
    return _HULL["cloud"]


# ---------------------------------------------------------------------------------------------------------------- strip
def profile() -> list[tuple[float, float]]:
    s, c = math.sin(math.radians(FASCIA_DEG)), math.cos(math.radians(FASCIA_DEG))
    p2 = (-RAKE + LEDGE, TOP)
    p3 = (p2[0] + FASCIA_L * s, p2[1] - FASCIA_L * c)
    return [(0.0, BOT), (-RAKE, TOP), p2, p3, (p3[0], p3[1] - LIP)]


def fascia_dir() -> tuple[float, float]:
    """Unit vector in (d, y) up the fascia, and its normal (toward the pilot, up) is (cos, sin of FASCIA_DEG)."""
    return -math.sin(math.radians(FASCIA_DEG)), math.cos(math.radians(FASCIA_DEG))


def enlarge(prof: list[tuple[float, float]], by: float, keep: tuple[int, ...] = (0, 1)) -> list[tuple[float, float]]:
    """The profile pushed outward by `by`, except the vertices in `keep` (the back stays where it is)."""
    pts = np.array(prof)
    area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts)))
    sign = 1.0 if area < 0 else -1.0       # outward normal of edge e is sign * (ey, -ex) for a clockwise polygon
    out = []
    for i, p in enumerate(pts):
        if i in keep:
            out.append(tuple(p))
            continue
        e0, e1 = p - pts[i - 1], pts[(i + 1) % len(pts)] - p
        n0 = sign * np.array([e0[1], -e0[0]]) / np.linalg.norm(e0)
        n1 = sign * np.array([e1[1], -e1[0]]) / np.linalg.norm(e1)
        m = (n0 + n1) / (1.0 + float(n0 @ n1))
        out.append(tuple(p + by * m))
    return out


def contour(sx: float, z: float) -> tuple[float, float]:
    """The foot of the back at station z: the glass at the foot's height, less the standoff (X sign `sx`)."""
    return sx * (halfwidth(z, BOT) - STANDOFF), z


def walk(sx: float, z0: float, lengths: list[float]) -> list[tuple[float, float]]:
    """Joints (x, z) of a wing, each chord the next length, along the glass contour, from z0 aft."""
    pts = [contour(sx, z0)]
    z = z0
    for length in lengths:
        while True:
            z += 1.0
            q = contour(sx, z)
            if math.dist(q, pts[-1]) >= length:
                pts.append(q)
                break
    return pts


def chord_normals(joints: list[tuple[float, float]]) -> list[np.ndarray]:
    """Per chord, the horizontal unit normal toward the pilot, (x, z)."""
    out = []
    for a, b in zip(joints, joints[1:]):
        t = np.array([b[0] - a[0], b[1] - a[1]])
        t /= np.linalg.norm(t)
        n = np.array([-t[1], t[0]])
        mid = np.array([(a[0] + b[0]) / 2, (a[1] + b[1]) / 2])
        out.append(n if float(n @ (np.array([0.0, 0.0]) - mid)) > 0 else -n)
    return out


def miters(norms: list[np.ndarray]) -> list[np.ndarray]:
    """Per joint, the vector that moves a point d toward the pilot by d along every adjoining chord's normal."""
    m = [norms[0]]
    for a, b in zip(norms, norms[1:]):
        m.append((a + b) / (1.0 + float(a @ b)))
    m.append(norms[-1])
    return m


def section(joint: tuple[float, float], miter: np.ndarray, prof: list[tuple[float, float]]) -> list[tuple[float, float, float]]:
    return [(joint[0] + d * miter[0], y, joint[1] + d * miter[1]) for d, y in prof]


def poly_solid(secs: list[list[tuple[float, float, float]]]) -> bd.Solid:
    """A closed solid through planar sections: side quads between consecutive sections, an end face each."""
    def make(ss):
        faces = []
        for a, b in zip(ss, ss[1:]):
            for k in range(len(a)):
                k2 = (k + 1) % len(a)
                faces.append(bd.Face(bd.Wire.make_polygon([a[k], a[k2], b[k2], b[k]], close=True)))
        for s in (ss[0], ss[-1]):
            faces.append(bd.Face(bd.Wire.make_polygon(list(s), close=True)))
        return bd.Solid(bd.Shell(faces))
    sol = make(secs)
    if sol.volume < 0:
        sol = make(secs[::-1])
    return sol


class Wing:
    """One wing: its joints, miters and facets."""

    def __init__(self, side: str, z0: float) -> None:
        self.side, self.sx = side, (-1.0 if side == "left" else 1.0)
        self.names = ["Cap"] + [n for n, _, _ in _facets()[side]]
        self.carries = ["orange end cap"] + [c for _, _, c in _facets()[side]]
        self.lengths = [CAP_T] + [ln for _, ln, _ in _facets()[side]]
        self.joints = walk(self.sx, z0, self.lengths)
        self.normals = chord_normals(self.joints)
        self.miters = miters(self.normals)
        self.prof = profile()

    def sections(self, i: int, prof=None) -> list[list[tuple[float, float, float]]]:
        p = prof or self.prof
        return [section(self.joints[j], self.miters[j], p) for j in (i, i + 1)]

    def facet_solid(self, i: int) -> bd.Solid:
        return poly_solid(self.sections(i))

    def cap_solid(self) -> bd.Solid:
        return poly_solid(self.sections(0, enlarge(self.prof, CAP_PROUD)))

    def frame(self, i: int, along: float = 0.0, up: float = 0.0, out: float = 0.0) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        """Mount frame on chord i's fascia: (x, y, z, origin) mm. The origin is the fascia's middle, moved `along` the
        chord toward the pilot's right, `up` the slope and `out` along the normal. Z is out of the face."""
        a, b = np.array(self.joints[i]), np.array(self.joints[i + 1])
        t = (b - a) / np.linalg.norm(b - a)
        n = self.normals[i]
        if t[0] < 0:
            t = -t                                     # +X of an instrument points to the pilot's right
        ud, uy = fascia_dir()
        y_axis = np.array([ud * n[0], uy, ud * n[1]])
        x_axis = np.array([t[0], 0.0, t[1]])
        z_axis = np.cross(x_axis, y_axis)
        p2, p3 = self.prof[2], self.prof[3]
        mid_d, mid_y = (p2[0] + p3[0]) / 2, (p2[1] + p3[1]) / 2
        c = (a + b) / 2 + mid_d * n
        origin = np.array([c[0], mid_y, c[1]]) + along * x_axis + up * y_axis + out * z_axis
        return x_axis, y_axis, z_axis, origin


def _fits_dome(w: Wing) -> bool:
    """The cap and first two facets are inside the dome and 25 mm clear of the glass."""
    cloud = glass_cloud()
    for i in range(3):
        p = chord_points(w, i)
        if not all(inside_dome(q[0], q[1], q[2]) for q in p):
            return False
        if np.min(np.linalg.norm(cloud[None] - p[:, None], axis=2)) < 40.0:
            return False
    return True


def make_wings() -> dict[str, Wing]:
    """Each wing starts as near the glass's bow as the gap allows: the nearest start whose cap and first facet clear it."""
    wings = {}
    for side in ("left", "right"):
        for z0 in np.arange(-1200.0, -300.0, 5.0):
            w = Wing(side, float(z0))
            low = min(abs(p[0]) for i in (0, 1) for s in w.sections(i, enlarge(w.prof, CAP_PROUD)) for p in s)
            if low >= GAP / 2 + 5.0 and _fits_dome(w):
                wings[side] = w
                break
        else:
            raise ValueError(f"no start for the {side} wing")
    return wings


def hologram_frame(w: Wing) -> tuple[np.ndarray, np.ndarray]:
    """The hologram's anchor: the middle of the first facet's pad, standing up. (origin mm, x axis)"""
    a, b = np.array(w.joints[1]), np.array(w.joints[2])
    t = (b - a) / np.linalg.norm(b - a)
    if t[0] < 0:
        t = -t
    c = (a + b) / 2 + HOLO_BASE_D * w.normals[1]
    return np.array([c[0], TOP + HOLO_BASE_H, c[1]]), np.array([t[0], 0.0, t[1]])


# ------------------------------------------------------------------------------------------------------------- anchors
def anchors(wings: dict[str, Wing]) -> dict[str, dict]:
    """Every instrument anchor: name -> {wing, facet index, slug, along, up, out, size mm (w, h), settings}."""
    sw, lamp = entry("guarded_toggle"), entry("indicator_lamp")
    out: dict[str, dict] = {}

    def add(name, side, facet, slug, w, h, along=0.0, up=0.0, o=0.0, **settings):
        out[name] = {"wing": side, "facet": facet, "slug": slug, "along": along, "up": up, "out": o, "size": (w, h),
                     "stand_out": entry(slug).get("stand_out_mm") or entry(slug)["depth_mm"]["in_front_of_origin"], "settings": settings}

    df, md = entry("depth_finder"), entry("multidisplay")
    add("DepthFinder", "left", 1, "depth_finder", *df["footprint_mm"])
    add("Multidisplay", "left", 2, "multidisplay", *md["footprint_mm"])
    sp, _t, sb = _gauge_extent(SPEED_R)
    add("SpeedGauge", "left", 3, "gauge", 2 * sp, _t + sb, up=(sb - _t) / 2, radius=SPEED_R)
    add("Navball", "right", 1, "navball", *entry("navball")["footprint_mm"])
    for k, name in enumerate(("ExternalLightSwitch", "ExternalColourSwitch", "CabinLightSwitch", "CabinColourSwitch")):
        add(name, "right", 2, "guarded_toggle", *sw["footprint_mm"], along=(k - 1.5) * TOGGLE_PITCH)
    for k, name in enumerate(("BilgeLamp", "Co2Lamp", "LowO2Lamp")):
        add(name, "right", 3, "indicator_lamp", *lamp["footprint_mm"], along=(k - 1) * LAMP_PITCH, o=LAMP_PLATE_T)
    nb, nt, nbot = _gauge_extent(NOISE_R)
    add("NoiseRepeater", "right", 4, "gauge", 2 * nb, nt + nbot, up=(nbot - nt) / 2, radius=NOISE_R)
    return out


def anchor_frame(wings: dict[str, Wing], a: dict) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    return wings[a["wing"]].frame(a["facet"], a["along"], a["up"], a["out"])


# ---------------------------------------------------------------------------------------------------------------- build
def _loc(origin: np.ndarray, x: np.ndarray, z: np.ndarray) -> bd.Location:
    return bd.Location(bd.Plane(origin=tuple(float(v) for v in origin), x_dir=tuple(float(v) for v in x), z_dir=tuple(float(v) for v in z)))


def solids() -> tuple[list[Solid], dict]:
    wings = make_wings()
    out: list[Solid] = []
    shapes: dict[str, bd.Shape] = {}
    for side, w in wings.items():
        cap = w.cap_solid()
        out.append(Solid(cap, "control_interface"))
        shapes[f"{side}.cap"] = cap
        for i in range(1, len(w.joints) - 1):
            f = w.facet_solid(i)
            if w.names[i] == "Navball":
                x, y, z, o = w.frame(i)
                rb = 115.0 / 2 / math.cos(math.pi / BORE_SIDES)
                bore = prism(BORE_SIDES, rb, BORE_D + 8.0).moved(_loc(o - z * BORE_D, x, z))
                inner = prism(BORE_SIDES, rb, BORE_D).moved(_loc(o - z * BORE_D, x, z))
                expect((inner - f).volume < 1.0, f"the navball's bore ({BORE_D:.0f} mm deep) stays inside its facet ({(bore - f).volume:.0f} mm3 outside)")
                f = f - bore
                shapes["navball_bore"] = bore
            out.append(Solid(f, "interior_panel"))
            shapes[f"{side}.{w.names[i]}"] = f
    # lamp plate: a dark plate on the lamps' facet
    rw = wings["right"]
    li = rw.names.index("Lamps")
    x, y, z, o = rw.frame(li)
    lp = box_plate(2 * LAMP_PITCH + entry("indicator_lamp")["footprint_mm"][0] + 20.0, 50.0, LAMP_PLATE_T).moved(_loc(o, x, z))
    out.append(Solid(lp, "interior_dark"))
    shapes["lamp_plate"] = lp
    # the hologram's pad on the left wing's top
    ho, hx = hologram_frame(wings["left"])
    pad = prism(16, HOLO_BASE_R, HOLO_BASE_H, chamfer_top=4.0).moved(_loc(ho - np.array([0.0, HOLO_BASE_H, 0.0]), hx, np.array([0.0, 1.0, 0.0])))
    out.append(Solid(pad, "trim_black"))
    shapes["hologram_pad"] = pad
    figures = _check(wings, shapes, ho)
    return out, {"wings": wings, "shapes": shapes, "figures": figures, "holo": ho}


def box_plate(w: float, h: float, t: float) -> bd.Shape:
    return bd.Box(w, h, t, align=(bd.Align.CENTER, bd.Align.CENTER, bd.Align.MIN))


def chord_points(w: Wing, i: int) -> np.ndarray:
    """Sample points (mm) on chord i's edges, 25 mm apart."""
    prof = enlarge(w.prof, CAP_PROUD) if i == 0 else w.prof
    a, b = w.sections(i, prof)
    n = max(2, int(math.dist(w.joints[i], w.joints[i + 1]) / 25.0) + 1)
    return np.array([np.array(pa) + t * (np.array(pb) - np.array(pa)) for pa, pb in zip(a, b) for t in np.linspace(0, 1, n)])


def strip_points(wings: dict[str, Wing], holo: np.ndarray) -> dict[str, np.ndarray]:
    """Sample points (mm) on every part of the strip, by name: its edges at 25 mm, and the hologram's envelope."""
    pts: dict[str, np.ndarray] = {}
    for side, w in wings.items():
        for i in range(len(w.joints) - 1):
            pts[f"{side}.{w.names[i]}"] = chord_points(w, i)
    ang = np.linspace(0, 2 * math.pi, 24, endpoint=False)
    ring = np.array([(HOLO_R * math.cos(t), 0.0, HOLO_R * math.sin(t)) for t in ang])
    pts["hologram"] = np.concatenate([holo + ring, holo + ring + np.array([0.0, HOLO_H, 0.0])])
    return pts


def _check(wings: dict[str, Wing], shapes: dict[str, bd.Shape], holo: np.ndarray) -> dict:
    left, right = wings["left"], wings["right"]
    pts = strip_points(wings, holo)
    allp = np.concatenate(list(pts.values()))
    strip = {k: v for k, v in shapes.items() if k not in ("navball_bore",)}
    # --- the section and the wings
    expect(abs(left.joints[0][1] - right.joints[0][1]) < 6.0, "the two wings start at the same depth, to the gap")
    # --- the gap: nothing crosses the apex
    for k, p in pts.items():
        side = k.split(".")[0]
        if side == "left":
            expect(p[:, 0].max() <= -GAP / 2 + 0.5, f"nothing of {k} crosses the gap ({p[:, 0].max():.0f} mm, gap edge {-GAP / 2:.0f})")
        elif side == "right":
            expect(p[:, 0].min() >= GAP / 2 - 0.5, f"nothing of {k} crosses the gap ({p[:, 0].min():.0f} mm, gap edge {GAP / 2:.0f})")
    for k, s in strip.items():
        lo, hi = s.bounding_box().min.X, s.bounding_box().max.X
        expect(hi <= -GAP / 2 + 0.5 or lo >= GAP / 2 - 0.5, f"{k}'s solid does not cross the gap ({lo:.0f}..{hi:.0f})")
    expect(abs(pts["hologram"][:, 0].max() + GAP / 2) > 0 and pts["hologram"][:, 0].max() < -GAP / 2, "the hologram stands up and to the side of the gap, over the left wing")
    # --- the dome: inside the glass, clear of it, short of the rim ring
    cloud = glass_cloud()
    near = 1e9
    for k, p in pts.items():
        for q in p:
            expect(inside_dome(q[0], q[1], q[2]), f"{k} is inside the dome at {q.round(0)}")
        d = np.min(np.linalg.norm(cloud[None, :, :] - p[:, None, :], axis=2), axis=1).min()
        near = min(near, d)
        expect(d >= 25.0, f"{k} stays clear of the glass ({d:.0f} mm)")
    zs, _, rim_z = _rings()
    rim_near = rim_z - RIM_HALF_MM
    zmax = float(allp[:, 2].max())
    expect(zmax <= rim_near - 100.0, f"the strip ends {rim_near - zmax:.0f} mm short of the rim ring (at {rim_near:.0f} mm), 100 needed")
    # --- knee height and the sight line
    top = max(p[:, 1].max() for k, p in pts.items() if k != "hologram")
    expect(600.0 <= top <= 900.0, f"knee height: the strip's top edge is {top:.0f} mm above the floor (600 to 900)")
    expect(min(p[:, 1].min() for k, p in pts.items() if k != "hologram") >= 300.0, "the strip's underside is clear of the floor and the footrest")
    holo_top = float(holo[1] + HOLO_H)
    expect(allp[:, 1].max() <= holo_top + 0.01, f"nothing rises above the hologram's top ({allp[:, 1].max():.0f} mm vs {holo_top:.0f} mm)")
    worst = -99.0
    for k, p in pts.items():
        if k == "hologram":
            continue
        d = p - EYE_MM
        elev = np.degrees(np.arctan2(d[:, 1], np.hypot(d[:, 0], d[:, 2])))
        worst = max(worst, float(elev.max()))
    expect(worst <= -8.0, f"the strip is below the seated eye's horizon by {-worst:.0f} degrees at its highest point (8 or more)")
    hd = holo - EYE_MM
    holo_elev = math.degrees(math.atan2(holo_top - EYE_MM[1], math.hypot(hd[0], hd[2])))
    expect(holo_elev < 0, f"the hologram's top is below the eye's horizon ({holo_elev:.0f} degrees)")
    # --- the seat, its armrests, joysticks and pedals
    seat = [s.shape for s in scene_module("operator_seat").solids()] + [s.shape for s in scene_module("pilot_seat").solids()]
    seat_all = bd.Compound(seat)
    for k, s in strip.items():
        d = s.distance_to(seat_all)
        expect(d >= 100.0, f"{k} is clear of the seat, armrests and pedals ({d:.0f} mm, 100 needed)")
    js = entry("joystick")
    arm_x = scene_module("operator_seat").ARM_X
    pm = scene_module("pilot_seat")
    stick_far = js["stand_out_mm"]
    jdist = 1e9
    for sx in (-1, 1):
        pivot = np.array([sx * arm_x, pm.ARM_TOP, pm.JOY_Z])
        d = float(np.min(np.linalg.norm(allp - pivot, axis=1))) - stick_far
        jdist = min(jdist, d)
    expect(jdist >= 100.0, f"the strip is {jdist:.0f} mm clear of the sticks' whole sweep (100 needed)")
    # --- the anchors sit on their facets, and their instruments fit and clear the view
    an = anchors(wings)
    reach = {}
    ud, uy = fascia_dir()
    for name, a in an.items():
        w = wings[a["wing"]]
        x, y, z, o = anchor_frame(wings, a)
        fl = math.dist(w.joints[a["facet"]], w.joints[a["facet"] + 1])
        wd, ht = a["size"]
        expect(abs(a["along"]) + wd / 2 <= fl / 2 - 10.0, f"{name} ({wd:.0f} mm) fits across its facet ({fl:.0f} mm)")
        expect(ht / 2 <= FASCIA_L / 2 - 5.0, f"{name} ({ht:.0f} mm, its box centred on the fascia) fits up its fascia ({FASCIA_L:.0f} mm)")
        expect(float(z @ np.array([0.0, 1.0, 0.0])) > 0.5, f"{name} faces up toward the eye")
        top_y = o[1] + abs(y[1]) * ht / 2 + z[1] * a["stand_out"]
        expect(top_y <= holo_top, f"{name} does not rise above the hologram's top ({top_y:.0f} mm)")
        to_eye = EYE_MM - o
        to_eye /= np.linalg.norm(to_eye)
        expect(float(z @ to_eye) >= 0.55, f"{name}'s face is within 57 degrees of the line to the eye")
        reach[name] = round(float(np.linalg.norm(o - EYE_MM)))
    order = {"left": ["DepthFinder", "Multidisplay", "SpeedGauge"],
             "right": ["Navball", "ExternalLightSwitch", "BilgeLamp", "NoiseRepeater"]}
    for side, names in order.items():
        xs = [abs(anchor_frame(wings, an[n])[3][0]) for n in names]
        expect(xs == sorted(xs), f"the {side} wing's order from the gap outward: {', '.join(names)}")
    expect(abs(anchor_frame(wings, an["DepthFinder"])[3][0] - holo[0]) < 150.0, "the hologram stands above the depth finder")
    # the navball's keep-clear behind its face
    nb = entry("navball")
    expect(BORE_D >= nb["keep_clear_mm"]["behind_face"], f"the bore ({BORE_D:.0f} mm) holds the ball's {nb['keep_clear_mm']['behind_face']:.0f} mm behind the face")
    expect(math.isclose(nb["panel_cutout"]["diameter_mm"], 115.0), "the bore is the navball's 115 mm cutout")
    return {"strip_top_mm": round(top), "hologram_top_mm": round(holo_top), "glass_clearance_mm": round(near),
            "gap_mm": GAP, "eye_to_anchor_mm": reach, "rim_ring_clear_mm": round(rim_near - zmax),
            "stick_clearance_mm": round(jdist)}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    sol, info = solids()
    wings, fig, holo = info["wings"], info["figures"], info["holo"]
    rep = export_solids_glb(sol, d / f"{SLUG}_strip.glb", "PilotStrip")
    seat_tris = entry("pilot_seat")["triangles"]
    shell_tris = rep["triangles"] + seat_tris
    an = anchors(wings)
    inst = sum(entry(a["slug"])["triangles"] for a in an.values())
    expect(shell_tris <= TRIANGLE_BUDGET - 1000, f"shell and seat ({shell_tris} triangles) leave room under {TRIANGLE_BUDGET}")
    s = Scene("PilotStation")
    s.node("Seat", instance=scene_path("pilot_seat"))
    s.node("Strip", instance=rep["glb"])
    s.node("Anchors")
    for name, a in an.items():
        x, y, z, o = anchor_frame(wings, a)
        s.node(name, parent="Anchors", props={"transform": Xform.frame(x, y, z, tuple(o / 1000.0))})
    ho = holo
    hx = hologram_frame(wings["left"])[1]
    s.node("HologramAnchor", parent="Anchors",
           props={"transform": Xform.frame(hx, (0, 1, 0), np.cross(hx, (0, 1, 0)), tuple(ho / 1000.0))})
    s.write(d / f"{SLUG}.tscn")
    _cameras(d)
    write_entry(GROUP, SLUG, {
        "kind": "station",
        "summary": "Pilot's station: the pilot seat on the centreline facing -Z, and one knee-height instrument strip low against the "
                   "dome in two faceted wings with orange end caps either side of a clear gap (600 mm). Marked anchors for every "
                   "instrument (left wing from the gap outward: depth finder with the hologram above it, multidisplay, speed gauge; "
                   "right wing: navball, four light switches, three warning lamps, noise repeater). Shell and seat only: the "
                   "instruments are placed by the next arc.",
        "tags": ["station", "pilot", "strip", "dome", "helm", "seat"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": None,
                      "wire": {"seat": "Seat/SitPoint (PilotSeat binds it; Seat/ThrottleJoystick and Seat/FlightJoystick take a JoystickIndicator)",
                               "anchors": "Anchors/<name> (Node3D; mount frame: +Z out of the fascia, +Y up the slope, +X toward the pilot's right)",
                               "left_wing": "DepthFinder, Multidisplay, SpeedGauge (from the gap outward); HologramAnchor above the depth finder, standing up",
                               "right_wing": "Navball, ExternalLightSwitch, ExternalColourSwitch, CabinLightSwitch, CabinColourSwitch, "
                                             "BilgeLamp, Co2Lamp, LowO2Lamp (on a dark plate, 8 mm proud: mount their lamps at the anchor), NoiseRepeater"}},
        "footprint_mm": [round(float(2 * max(abs(w.joints[-1][0]) for w in wings.values()))), round(float(-min(w.joints[0][1] for w in wings.values()) + 400))],
        "mount": "floor at Y=0, seat origin on the centreline at X=0, Z=0; the pilot faces -Z; the strip is ahead at -Z",
        "placement": {"hull_z_m": HULL_Z0 / 1000.0, "hull_floor_y_m": HULL_Y0 / 1000.0,
                      "note": "the dome check assumes the seat origin at the program's pilot z (-3.8 m) and the cockpit floor (y -1.15 m)"},
        "seated_eye_height_m": float(EYE_MM[1] / 1000.0),
        "context": ["dome glass and rim ring of assets/models/vehicles/sub_interior (checked against, not built)"],
        "uses": list(USES),
        "triangles": shell_tris,
        "triangles_by_part": {"strip": rep["triangles"], "pilot_seat": seat_tris},
        "triangles_with_instruments": shell_tris + inst,
        "checks": fig,
    })
    return {"slug": SLUG, "triangles": shell_tris, "strip": rep["triangles"]}


def _cameras(d) -> None:
    """Review cameras: the concept viewpoints, the seated eye (white and red light), orthographic profile, front and plan."""
    eye = [round(float(v) / 1000, 3) for v in EYE_MM]
    cams = [
        {"name": "concept_pilot_view", "pos": eye, "look_at": [0.0, 0.62, -1.0], "fov": 100.0},
        {"name": "concept_behind", "pos": [0.0, 1.75, 1.7], "look_at": [0.0, 0.7, -0.6], "fov": 60.0},
        {"name": "operator_eye", "pos": eye, "look_at": [0.0, 0.62, -1.0], "fov": 75.0},
        {"name": "operator_eye_red", "pos": eye, "look_at": [0.0, 0.62, -1.0], "fov": 75.0, "light": "red"},
        {"name": "profile_right", "pos": [4.0, 0.7, -0.4], "look_at": [0.0, 0.7, -0.4], "ortho": 2.4},
        {"name": "front", "pos": [0.0, 0.7, 4.0], "look_at": [0.0, 0.7, 0.0], "ortho": 2.4},
        {"name": "plan", "pos": [0.0, 4.0, -0.4], "look_at": [0.0, 0.0, -0.4], "ortho": 3.0, "up": [0, 0, -1]},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
