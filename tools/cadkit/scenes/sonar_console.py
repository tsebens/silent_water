"""sonar_console: the sonar operator's desk console (a station). Brief: assets/models/stations/sonar_console/brief.yaml.

Station-local solids (they don't move, aren't reused, aren't tunable content): the console body, its bezel, the
gauge header, the orange side frames, the kick plate and the headset hook. Everything else is a scene from the
catalogue, placed on one of two mount faces: the raked control strip and the screen face.
"""
import math

import build123d as bd
import numpy as np

from cadkit.solids import Solid, at, box, expect, export_solids_glb
from cadkit.library import entry, note, out_dir, res, scene_path, write_entry
from cadkit.tscn import NodePath, SName, Scene, Xform

SLUG, GROUP = "sonar_console", "stations"
USES: list[str] = ["gauge", "guarded_toggle", "trackball", "map_keypad", "operator_seat"]
W = 820.0                                     # console width (X), mm
# Side profile (y up, z out from the hull), mm, anticlockwise from the back foot.
STRIP_FRONT, STRIP_BACK = (740.0, 620.0), (860.0, 400.0)
FACE_TOP = (1520.0, 276.0)
PROFILE = [(0.0, 0.0), (0.0, 300.0), (620.0, 300.0), (700.0, 600.0), STRIP_FRONT, STRIP_BACK, FACE_TOP, (FACE_TOP[0], 0.0)]
BEZEL_W, BEZEL_H, BEZEL_D, BEZEL_S = 700.0, 625.0, 60.0, 332.5     # BEZEL_S: centre, mm up the screen face
OPEN_W, OPEN_H, GLASS_T = 580.0, 370.0, 20.0
DIAL_BAND = 200.0                             # the bezel's bottom border, which carries the dials (round 1 review)
OPEN_S = BEZEL_S - BEZEL_H / 2 + DIAL_BAND + OPEN_H / 2     # centre of the screen opening, mm up the face
DIAL_S = BEZEL_S - BEZEL_H / 2 + 115.0
CHART_M = 0.36                                # FlatChart is square: its edge, m
FRAME_W, FRAME_T = 45.0, 60.0                 # orange front-edge frame: band width, thickness in X (round 1 review)
STRIP_INSET_T = 4.0                           # dark inset panel the controls sit on (round 1 review)
SEAT_Z = 980.0
EYE_H = 1200.0

# Layout on the control strip: x (mm, right of centre) and s (mm up the slope from the strip's middle).
STRIP_LAYOUT = {"ActiveSonar": ("guarded_toggle", -230.0, 0.0, "active sonar"),
                "Trackball": ("trackball", 0.0, 0.0, "hydrophone trackball"),
                "MapKeys": ("map_keypad", 230.0, 0.0, None)}
# Dials on the header: x (mm), radius (m), and the Gauge settings (from the game's sonar station).
DIALS = {
    "SignalGauge": (-255.0, 0.04, {"readout": "signal", "title": "SIGNAL", "min_value": 40.0, "max_value": 110.0}),
    "BearingGauge": (-90.0, 0.055, {"readout": "bearing", "title": "BEARING", "max_value": 360.0, "wraps": True,
                                   "wrap_labels": ["FWD", "STBD", "AFT", "PORT"]}),
    "NoiseGauge": (90.0, 0.055, None),
    "BearingRateGauge": (255.0, 0.04, {"readout": "bearing_rate", "title": "BRG RATE", "min_value": -120.0,
                                        "max_value": 120.0, "sweep_deg": 180.0}),
}


def _unit(a, b) -> np.ndarray:
    d = np.array([0.0, b[0] - a[0], b[1] - a[1]])
    return d / np.linalg.norm(d)


# Mount faces, in station coordinates (x, y, z) mm: an origin, an up direction in the face and the outward normal.
FACE_UP = _unit(STRIP_BACK, FACE_TOP)
FACE_N = np.array([0.0, -FACE_UP[2], FACE_UP[1]])
FACE_O = np.array([0.0, *STRIP_BACK])
STRIP_UP = _unit(STRIP_FRONT, STRIP_BACK)
STRIP_N = np.array([0.0, -STRIP_UP[2], STRIP_UP[1]])
STRIP_O = np.array([0.0, (STRIP_FRONT[0] + STRIP_BACK[0]) / 2, (STRIP_FRONT[1] + STRIP_BACK[1]) / 2])
STRIP_LEN = math.dist(STRIP_FRONT, STRIP_BACK)
FACE_LEN = math.dist(STRIP_BACK, FACE_TOP)


def face_point(s: float, out: float = 0.0, x: float = 0.0) -> np.ndarray:
    return FACE_O + s * FACE_UP + out * FACE_N + np.array([x, 0.0, 0.0])


def strip_point(x: float, s: float, out: float = 0.0) -> np.ndarray:
    return STRIP_O + np.array([x, 0.0, 0.0]) + s * STRIP_UP + out * STRIP_N


def on_face(shape: bd.Shape, s: float) -> bd.Shape:
    o = face_point(s)
    return shape.moved(bd.Location(bd.Plane(origin=tuple(o), x_dir=(1, 0, 0), z_dir=tuple(FACE_N))))


def on_strip(shape: bd.Shape) -> bd.Shape:
    return shape.moved(bd.Location(bd.Plane(origin=tuple(STRIP_O), x_dir=(1, 0, 0), z_dir=tuple(STRIP_N))))


def solids() -> list[Solid]:
    prof = bd.Plane.YZ * bd.Polygon(*PROFILE, align=None)
    body = bd.extrude(prof, amount=W / 2, both=True)
    bezel = box(BEZEL_W, BEZEL_H, BEZEL_D) - at(box(OPEN_W, OPEN_H, BEZEL_D), y=OPEN_S - BEZEL_S)
    bezel = bd.chamfer(bezel.faces().sort_by(bd.Axis.Z)[-1].outer_wire().edges(), 10.0)
    glass = box(OPEN_W, OPEN_H, GLASS_T)
    outer = bd.offset(prof, FRAME_W, kind=bd.Kind.INTERSECTION)
    inner = bd.offset(prof, -FRAME_W, kind=bd.Kind.INTERSECTION)
    ring = bd.extrude(outer - inner, amount=FRAME_T)
    ring = ring & bd.Box(FRAME_T * 4, 4000, 4000, align=(bd.Align.CENTER, bd.Align.MIN, bd.Align.CENTER))
    # Keep the front edge and the top: a structural member, not an outline (round 1 review).
    ring = ring - bd.Box(FRAME_T * 4, FACE_TOP[0] - 120 + 100, 300, align=(bd.Align.CENTER, bd.Align.MIN, bd.Align.CENTER)).moved(
        bd.Location((0, -100, 50)))
    inset = on_strip(box(W - 80, STRIP_LEN - 30, STRIP_INSET_T))
    frames = [at(ring, x=W / 2), at(ring, x=-W / 2 - FRAME_T)]
    kick = at(box(W, 80, 8), y=40, z=300)
    hook_x = W / 2 + FRAME_T
    hook = at(bd.Box(70, 20, 20, align=(bd.Align.MIN, bd.Align.CENTER, bd.Align.CENTER)), hook_x, 1250, 200)
    hook_lip = at(bd.Box(20, 40, 20, align=(bd.Align.MIN, bd.Align.MIN, bd.Align.CENTER)), hook_x + 50, 1250, 200)
    out = ([Solid(body, "interior_panel"), Solid(on_face(bezel, BEZEL_S), "trim_black"), Solid(on_face(glass, OPEN_S), "screen_off"),
            Solid(inset, "interior_dark"), Solid(kick, "trim_black"), Solid(hook + hook_lip, "trim_black")]
           + [Solid(f, "control_interface") for f in frames])
    _check(body, frames)
    return out


def _check(body: bd.Part, frames: list[bd.Part]) -> None:
    """Checks against the brief and the catalogue entries of everything placed on the console."""
    expect(abs(body.bounding_box().min.Y) < 0.01, "console stands on the floor")
    for f in frames:
        expect(f.bounding_box().min.Y > -0.01, "side frames do not go below the floor")
    expect(BEZEL_S - BEZEL_H / 2 > 0 and BEZEL_S + BEZEL_H / 2 <= FACE_LEN, "bezel on the screen face")
    expect(OPEN_S + OPEN_H / 2 <= BEZEL_S + BEZEL_H / 2 - 40, "a bezel border above the screen")
    ext = entry("gauge")["extent_radii"]             # the gauge's own envelope, from its catalogue entry
    for name, (x, r, _) in DIALS.items():
        rim, title = ext["bezel"] * r * 1000, ext["plate_bottom"] * r * 1000
        expect(DIAL_S + rim <= OPEN_S - OPEN_H / 2 - 5, f"{name} below the screen opening")
        expect(DIAL_S - title >= BEZEL_S - BEZEL_H / 2 + 5, f"{name}'s title inside the bezel band")
        expect(abs(x) + rim <= BEZEL_W / 2 - 10, f"{name} inside the bezel's width")
    xs = sorted((x, r) for x, r, _ in DIALS.values())
    for (xa, ra), (xb, rb) in zip(xs, xs[1:]):
        expect(xb - xa >= ext["bezel"] * (ra + rb) * 1000 + 30, f"dials at {xa} and {xb} do not overlap")
    eye_y = EYE_H
    expect(abs(face_point(OPEN_S)[1] - eye_y) <= 120, f"screen centre near seated eye height ({face_point(OPEN_S)[1]:.0f} mm)")
    expect(OPEN_W >= 540, "screen opening about 55 cm wide (brief)")
    expect(CHART_M * 1000 <= OPEN_H, "the square chart fits the opening's height")
    eye = np.array([0.0, EYE_H, SEAT_Z])
    rects = []
    for name, (slug, x, s, _) in STRIP_LAYOUT.items():
        e = entry(slug)
        w, h = e["footprint_mm"]
        expect(abs(x) + w / 2 <= W / 2 - 20, f"{name} inside the strip's width")
        expect(abs(s) + h / 2 <= STRIP_LEN / 2 - 10, f"{name} inside the strip's depth")
        rects.append((name, x - w / 2, x + w / 2))
        reach = np.linalg.norm(strip_point(x, s) - eye) / 1000
        expect(reach <= 0.75, f"{name} within reach of the seated eye ({reach:.2f} m)")
        # Its envelope must stay clear of the bezel, which stands BEZEL_D out from the screen face.
        bez_lo = face_point(BEZEL_S - BEZEL_H / 2)[1]
        for cx in (x - w / 2, x + w / 2):
            for cs in (s - h / 2, s + h / 2):
                for out in (STRIP_INSET_T, STRIP_INSET_T + e["stand_out_mm"]):
                    p = strip_point(cx, cs, out)
                    if p[1] >= bez_lo - 5:
                        expect(np.dot(p - FACE_O, FACE_N) >= BEZEL_D + 5, f"{name} clear of the bezel")
    rects.sort(key=lambda r: r[1])
    for a, b in zip(rects, rects[1:]):
        expect(b[1] - a[2] >= 40, f"{a[0]} and {b[0]} a hand apart ({b[1] - a[2]:.0f} mm)")
    screen = face_point(OPEN_S)
    view = eye - screen
    ang = math.degrees(math.acos(np.dot(view / np.linalg.norm(view), FACE_N)))
    expect(ang <= 25, f"screen faces the seated eye ({ang:.0f} degrees off)")


def _xf(origin_mm: np.ndarray, up: np.ndarray, normal: np.ndarray) -> Xform:
    return Xform.frame((1, 0, 0), up, normal, tuple(origin_mm / 1000))


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    rep = export_solids_glb(solids(), d / f"{SLUG}_body.glb", "SonarConsoleBody")
    s = Scene("SonarConsole", script="res://src/sonar/sonar_station.gd")
    s.set(".", headset=NodePath("Headset"), wheel=NodePath("Controls/Trackball"))
    s.node("Body", instance=rep["glb"])
    lower = s.sub("BoxShape3D", "lower", {"size": (W / 1000, 0.74, 0.3)})
    upper = s.sub("BoxShape3D", "upper", {"size": (W / 1000, (FACE_TOP[0] - 740) / 1000, 0.4)})
    s.node("Collision", type_="StaticBody3D")
    s.node("Lower", parent="Collision", type_="CollisionShape3D", props={"transform": Xform(origin=(0, 0.37, 0.15)), "shape": lower})
    s.node("Upper", parent="Collision", type_="CollisionShape3D", props={"transform": Xform(origin=(0, (FACE_TOP[0] + 740) / 2000, 0.2)), "shape": upper})
    # The chart turns itself to face its parent's -Z, so its mount's -Z is the face normal.
    glass_front = face_point(OPEN_S, GLASS_T + 1)
    s.node("ScreenMount", props={"transform": Xform.frame((-1, 0, 0), FACE_UP, -FACE_N, tuple(glass_front / 1000))})
    s.node("Chart", parent="ScreenMount", type_="MeshInstance3D", script="res://src/map/flat_chart.gd",
           props={"screen_size": CHART_M})
    s.node("Gauges", props={"transform": _xf(face_point(DIAL_S, BEZEL_D), FACE_UP, FACE_N)})
    gauge = "res://src/interact/gauge.gd"
    for name, (x, r, cfg) in DIALS.items():
        pos = Xform(origin=(x / 1000, 0.0, 0.012))
        if cfg is None:
            s.node(name, parent="Gauges", instance="res://src/noise/noise_gauge.tscn", props={"transform": pos, "radius": r})
            continue
        props = {"transform": pos, "source_group": SName("sonar_readouts"), "readout": SName(cfg["readout"]),
                 "title": cfg["title"], "radius": r}
        props.update({k: v for k, v in cfg.items() if k not in ("readout", "title")})
        s.node(name, parent="Gauges", script=gauge, props=props)
    s.node("Controls", props={"transform": _xf(strip_point(0, 0, STRIP_INSET_T), STRIP_UP, STRIP_N)})
    for name, (slug, x, sv, label) in STRIP_LAYOUT.items():
        props = {"transform": Xform(origin=(x / 1000, sv / 1000, 0))}
        if label:
            props["label"] = label
        s.node(name, parent="Controls", instance=scene_path(slug), props=props)
    s.node("Seat", script="res://src/sonar/sonar_seat.gd",
           props={"transform": Xform(origin=(0, 0, SEAT_Z / 1000)), "headset": NodePath("../Headset"),
                  "sit_point": NodePath("Model/SitPoint"), "eye_height": EYE_H / 1000, "label": "sonar seat"})
    s.node("Model", parent="Seat", instance=scene_path("operator_seat"))
    hook_tip = np.array([W / 2 + FRAME_T + 55, 1250 - 20, 200]) / 1000
    s.node("Headset", instance="res://src/sonar/headset.tscn",
           props={"transform": Xform.frame((0, 0, -1), (0, 1, 0), (1, 0, 0), tuple(hook_tip - np.array([0, 0.08, 0])))})
    s.write(d / f"{SLUG}.tscn")
    parts = {n: entry(sl)["triangles"] for n, (sl, *_r) in STRIP_LAYOUT.items()}
    parts["gauges"] = len(DIALS) * entry("gauge")["triangles"]
    tris = rep["triangles"] + sum(parts.values()) + entry("operator_seat")["triangles"]
    expect(tris <= 12000, f"station within the interior budget ({tris} triangles)")
    _cameras(d)
    write_entry(GROUP, SLUG, {
        "kind": "station",
        "summary": "Sonar operator's desk console: raked control strip, 55 cm screen in a deep bezel with dials below it, seat.",
        "tags": ["station", "sonar", "console", "desk"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "SonarStation", "wire": {"wheel": "Controls/Trackball", "headset": "Headset"}},
        "footprint_mm": [W + 2 * FRAME_T, SEAT_Z + 300],
        "mount": "floor at Y=0, back against the hull on Z=0, operator at +Z facing -Z",
        "uses": [v[0] for v in STRIP_LAYOUT.values()] + ["operator_seat", "gauge", "noise_gauge", "flat_chart", "headset"],
        "triangles": tris,
        "triangles_by_part": {"body": rep["triangles"], **parts},
    })
    return {"slug": SLUG, "triangles": tris, "body": rep["triangles"]}


def _cameras(d) -> None:
    """Review cameras: the two concept viewpoints, the operator's eye, and orthographic profile and front."""
    import json
    eye = [0.0, EYE_H / 1000, SEAT_Z / 1000]
    cams = [
        {"name": "concept_console_view", "pos": [-0.38, 1.32, 1.3], "look_at": [0.12, 1.0, 0.36], "fov": 62.0},
        {"name": "concept_primary_view", "pos": [-1.5, 1.7, 2.8], "look_at": [0.0, 0.9, 0.5], "fov": 50.0},
        {"name": "operator_eye", "pos": eye, "look_at": [0.0, 1.0, 0.4], "fov": 75.0},
        {"name": "operator_eye_red", "pos": eye, "look_at": [0.0, 1.0, 0.4], "fov": 75.0, "light": "red"},
        {"name": "profile_right", "pos": [4.0, 0.9, 0.65], "look_at": [0.0, 0.9, 0.65], "ortho": 2.1},
        {"name": "front", "pos": [0.0, 0.9, 5.0], "look_at": [0.0, 0.9, 0.0], "ortho": 2.1},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
