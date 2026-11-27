"""camera_module: the CAMERA science-station module (kit display, concept #529, arc #623).

The shared `science_module_frame` chassis with this module's face: a hooded viewfinder screen (a bezel, a dark glass
and a four-walled hood that shades it, all one static GLB), a light meter and a stillness indicator (two `linear_gauge`
instances laid on their sides, reading the CameraModule by its `camera_modules` group) and a shutter (a `push_button`).
The root is a CameraModule. Wiring left to the station: connect `Shutter`'s `value_changed` to the objective's
`take_shot` (the module takes it from the left mouse button), and draw the camera view on the viewfinder glass.

Mount: as the frame: back on Z=0, centred, faces +Z; the rear body slides into a bay about 0.35 m wide. The hood is
inside the module's own 340 mm width, so it never reaches the neighbouring bay.
"""
import json

from cadkit.solids import Solid, at, box, expect, expect_in_front, bbox_mm, export_solids_glb
from cadkit.library import entry, note, out_dir, res, scene_path, write_entry
from cadkit.mount import stand_off
from cadkit.tscn import SName, Scene, Xform

SLUG, GROUP = "camera_module", "kit"
USES: list[str] = ["science_module_frame", "linear_gauge", "push_button"]
PLATE_FRONT = 56.0                         # the frame's face plate front (BODY_D + T)
RAIL_IN, HANDLE_IN = 118.0 - 7.0, 156.0 - 6.0
VF_X, VF_Y, VF_W, VF_H = -42.0, 46.0, 176.0, 90.0       # viewfinder glass centre and size
BEZEL_M, BEZEL_T, GLASS_T = 6.0, 4.0, 1.5
HOOD_T, HOOD_FLARE = 3.0, 8.0                            # wall thickness; the hood stands this far outside the bezel
HOOD_TOP, HOOD_SIDE, HOOD_BOT = 46.0, 36.0, 30.0         # how far each wall stands out from the bezel front
GAUGE_X0, GAUGE_YS = -130.0, (-47.0, -91.0)              # gauges' bar start (left end) and their centre rows
SHUTTER_X, SHUTTER_Y = 112.0, 46.0
MAX_STAND_OUT, MAX_TRIS = 125.0, 2000


def hood_bounds() -> tuple[float, float, float, float]:
    w, h = VF_W + 2 * BEZEL_M + 2 * HOOD_FLARE, VF_H + 2 * BEZEL_M + 2 * HOOD_FLARE
    return VF_X - w / 2, VF_X + w / 2, VF_Y - h / 2, VF_Y + h / 2


def face_solids() -> list[Solid]:
    z0 = PLATE_FRONT
    parts = [Solid(at(box(VF_W + 2 * BEZEL_M, VF_H + 2 * BEZEL_M, BEZEL_T, chamfer_mm=1.0), x=VF_X, y=VF_Y, z=z0), "trim_black"),
             Solid(at(box(VF_W, VF_H, GLASS_T), x=VF_X, y=VF_Y, z=z0 + BEZEL_T), "screen_off")]
    x0, x1, y0, y1 = hood_bounds()
    w, h = x1 - x0, y1 - y0
    zb = z0 + BEZEL_T
    parts.append(Solid(at(box(w, HOOD_T, HOOD_TOP), x=VF_X, y=y1 - HOOD_T / 2, z=zb), "control_grey"))
    parts.append(Solid(at(box(w, HOOD_T, HOOD_BOT), x=VF_X, y=y0 + HOOD_T / 2, z=zb), "control_grey"))
    for sx in (-1, 1):
        parts.append(Solid(at(box(HOOD_T, h - 2 * HOOD_T, HOOD_SIDE), x=VF_X + sx * (w / 2 - HOOD_T / 2), y=VF_Y, z=zb),
                           "control_grey"))
    return parts


def gauge_xform(row: int, gentry: dict):
    """A linear_gauge on its side: its track (+Y) runs along +X, its face still +Z; origin is the bar's left end."""
    return Xform.frame((0, -1, 0), (1, 0, 0), (0, 0, 1), origin=(GAUGE_X0 / 1000, GAUGE_YS[row] / 1000, PLATE_FRONT / 1000))


def check(frame, gauge, button, face) -> float:
    fw, _ = frame["footprint_mm"]
    gw, gh = gauge["footprint_mm"]            # plate width (across the track) and length (along it)
    hx0, hx1, hy0, hy1 = hood_bounds()
    # The hood lives inside the module's own width: it cannot reach into the neighbouring bay.
    expect(hx0 >= -fw / 2 and hx1 <= fw / 2, f"hood x {hx0:.0f}..{hx1:.0f} inside the {fw:.0f} mm module, clear of the neighbour bay")
    expect(hx0 >= -HANDLE_IN and hy1 <= RAIL_IN, "hood clear of the side handles and the top rail")
    top = max(bbox_mm(s.shape)[1][2] for s in face)
    expect(top <= MAX_STAND_OUT, f"hood stands {top:.0f} mm out; limit {MAX_STAND_OUT:.0f}")
    # Gauges: lying down, the plate is gw tall (Y) and gh long (X), from the bar start (-16 mm margin at the back end).
    ys = [(y - gw / 2, y + gw / 2) for y in GAUGE_YS]
    expect(ys[1][1] <= ys[0][0] + 0.01, "the two gauges do not overlap")
    expect(ys[1][0] >= -RAIL_IN, "lower gauge inside the bottom rail")
    expect(ys[0][1] < hy0, "gauges clear of the hood's lower edge")
    gx1 = GAUGE_X0 + 216.0
    expect(GAUGE_X0 - 16.0 >= -HANDLE_IN and gx1 <= HANDLE_IN, f"gauges x {GAUGE_X0 - 16:.0f}..{gx1:.0f} between the handles")
    expect(gx1 < SHUTTER_X - button["footprint_mm"][0] / 2, "gauges clear of the shutter")
    # Shutter: beside the hood, on the face, reachable (not behind the hood), between the handle and the viewfinder.
    bw, bh = button["footprint_mm"]
    expect(SHUTTER_X - bw / 2 > hx1 + 6.0, "shutter clear of the hood, free to reach")
    expect(SHUTTER_X + bw / 2 <= HANDLE_IN and abs(SHUTTER_Y) + bh / 2 <= RAIL_IN, "shutter between the handle and the rails")
    expect(PLATE_FRONT + stand_off(0.0) + button["stand_out_mm"] <= MAX_STAND_OUT, "shutter within the stand-out limit")
    expect_in_front(face, SLUG)
    stand = max(top, PLATE_FRONT + stand_off(0.0) + button["stand_out_mm"], frame["stand_out_mm"],
                PLATE_FRONT + gauge["stand_out_mm"])
    expect(fw <= 350.0, f"frame {fw:.0f} mm wide fits the 350 mm bay")
    return stand


def build() -> dict:
    frame, gauge, button = entry("science_module_frame"), entry("linear_gauge"), entry("push_button")
    d = out_dir(GROUP, SLUG)
    face = face_solids()
    stand = check(frame, gauge, button, face)
    rf = export_solids_glb(face, d / f"{SLUG}_face.glb", "CameraModuleFace")
    tris = rf["triangles"] + frame["triangles"] + 2 * gauge["triangles"] + button["triangles"]
    expect(tris <= MAX_TRIS, f"{tris} triangles; the cap is {MAX_TRIS}")
    s = Scene("CameraModule", script="res://src/science/camera_module.gd")
    s.node("Frame", instance=frame["scene"])
    s.node("Face", instance=rf["glb"])
    for i, (name, readout) in enumerate((("LightMeter", "light"), ("StillnessMeter", "stillness"))):
        s.node(name, instance=scene_path("linear_gauge"), props={
            "transform": gauge_xform(i, gauge), "source_group": SName("camera_modules"), "readout": SName(readout),
            "min_value": 0.0, "max_value": 1.0, "warn_at": 0.5, "alarm_at": 0.15, "descending": True})
    s.node("Shutter", instance=scene_path("push_button"), props={
        "transform": Xform(origin=(SHUTTER_X / 1000, SHUTTER_Y / 1000, (PLATE_FRONT + stand_off(0.0)) / 1000)),
        "label": "shutter"})
    _review(d)
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "display",
        "summary": "CAMERA science module: the shared module chassis with a hooded viewfinder screen, a light meter "
                   "and a stillness indicator (linear gauges on their sides) and a red shutter push button. The root "
                   "is a CameraModule; the gauges read it by group.",
        "tags": ["science", "module", "camera", "viewfinder", "photo", "shutter", "light meter", "stillness", "hood"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "CameraModule", "values": "armed off/on; light_meter(), stillness_meter() 0..1",
                      "signal": "Shutter (PushButton) value_changed",
                      "wiring": "the gauges find the module by group `camera_modules`; the station draws the view on "
                                "the viewfinder glass and calls the objective's take_shot from Shutter.value_changed"},
        "footprint_mm": frame["footprint_mm"],
        "stand_out_mm": round(stand, 1),
        "depth_mm": {"behind_origin": 0.0, "in_front_of_origin": round(stand, 1)},
        "mount": "as science_module_frame: back on Z=0, centred; faces +Z; the rear body slides into a bay about 0.35 m wide",
        "uses": USES,
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}


def _review(d) -> None:
    look = [0.0, 0.0, 0.06]
    cams = [
        {"name": "front", "pos": [0.25, 0.18, 0.7], "look_at": look, "fov": 30.0},
        {"name": "front_red", "pos": [0.25, 0.18, 0.7], "look_at": look, "fov": 30.0, "light": "red"},
        {"name": "profile", "pos": [0.8, 0.0, 0.06], "look_at": [0.0, 0.0, 0.06], "ortho": 0.4},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    for n in (".gdignore", "cameras.json"):
        note(review / n)
