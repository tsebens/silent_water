"""navball: an attitude ball behind a glass dome, in the multidisplay's bezel, plate and orange ring (concept #459).

The ball is its own GLB (`Ball/NavballBall`) so the `Navball` script can turn it; the script also gives it the marking
mask material. Fixed in front of it: a glass dome and a small orange reticle. There are no digit windows and no label
plate (look review round 1). The housing is the multidisplay's (`scene_module("multidisplay").housing()`), not rebuilt:
its screen disc and label plate are left out and its plate is bored for the ball, which is the only change made to it here.

The ball is 110 mm across and the bezel only 24 mm deep, so to look set into the bezel (the concept) it is centred
BALL_Z in front of the mount face and its rear half sinks behind Z=0. The entry declares that as a panel cutout and keep-clear
depth. Everything else keeps its back on Z=0.

Frame: back on Z=0, centred on the origin, face toward +Z. Ball frame: +Y apex, -Z north (see navball.gdshader).
"""
import json
import math

import build123d as bd
import numpy as np

from cadkit.solids import Solid, at, box, prism, bbox_mm, expect, expect_in_front, export_solids_glb
from cadkit.library import note, out_dir, res, scene_module, write_entry
from cadkit.tscn import Scene, Xform

SLUG, GROUP = "navball", "kit"
USES = ["multidisplay"]
HOUSING_D_MM = 140.0            # the multidisplay's screen diameter, which sizes the shared housing
BALL_R = 55.0                   # 110 mm ball
BALL_Z = 22.0                   # the ball's centre in front of the mount face
BORE_R = BALL_R + 2.5           # the hole in the plate round the ball (a 16-sided prism: its flats clear the ball)
DOME_Z, DOME_OUT_R, DOME_IN_R = 14.0, 72.2, 70.2   # the dome's sphere centre, and its outer and inner radii; its rim is cut at BALL_Z
RETICLE_R_IN, RETICLE_R_OUT = 57.0, 58.6      # the reticle lies on a thin shell round the ball
RETICLE_W = 0.9
DOT_R = 0.6
MARGIN_MM = 6.0                 # the ball's reach inside the bezel's inner radius, at least
MAX_STAND_OUT_MM = 90.0
SAMPLE_ATTITUDE = {"heading": 47.0, "pitch": -10.0, "roll": 15.0}     # the review renders and the scene's rest pose
SAMPLES = {"heading_deg": 47.0, "pitch_deg": -10.0}
BUDGET = 10000                  # this scene's triangle budget (Tristan's decision, look review round 1; the kit default is 1500)
SPHERE_TOL = (0.4, 0.14)        # tessellation tolerance (mm, rad) for the ball and the dome: the budget decides
RETICLE_TOL = (0.2, 0.3)
SAMPLE_SOURCE_GROUP = "sub_readouts"

# The reticle's strokes (mm, in the screen plane): a bracket and a V either side of the centre dot.
ARM = [(-5.6, 3.6), (-7.4, 0.4), (-5.2, -2.8), (-3.2, -1.2)]   # 1/5 of the first design: about 1/8 of the ball wide


def _shell(r_out: float, r_in: float) -> bd.Shape:
    return at(bd.Sphere(r_out) - bd.Sphere(r_in), z=BALL_Z)


def _sphere(r: float) -> bd.Shape:
    return at(bd.Sphere(r), z=BALL_Z)


def _volume(shape: bd.Shape) -> float:
    return sum(s.volume for s in shape.solids()) if shape is not None else 0.0


def rest_basis() -> np.ndarray:
    """The ball's basis for the sample attitude: the inverse of the sub's orientation (heading, nose pitch, roll)."""
    def rot(axis, deg):
        a = math.radians(deg)
        c, s = math.cos(a), math.sin(a)
        i, j = [(1, 2), (2, 0), (0, 1)][axis]
        m = np.eye(3)
        m[i][i], m[i][j], m[j][i], m[j][j] = c, -s, s, c
        return m
    pose = rot(1, -SAMPLE_ATTITUDE["heading"]) @ rot(0, SAMPLE_ATTITUDE["pitch"]) @ rot(2, -SAMPLE_ATTITUDE["roll"])
    return pose.T


def solids() -> dict:
    """Every solid, then every check, before anything is written."""
    h = scene_module("multidisplay").housing(HOUSING_D_MM)
    k = h["k"]
    plate_s, bezel_s, ring_s, _disc, _label = h["solids"][:5]    # the screen disc and the label plate are left out
    bolts = h["solids"][5:]
    bezel_in = 73.0 * k
    plate_w = h["plate_mm"]
    bezel_front = bbox_mm(bezel_s.shape)[1][2]

    plate = Solid(plate_s.shape - at(prism(16, BORE_R, 12.0), z=-2.0), plate_s.role)

    ball = bd.Sphere(BALL_R)                       # in its own frame, centred on the origin
    dome = at(bd.Sphere(DOME_OUT_R) - bd.Sphere(DOME_IN_R), z=DOME_Z) & at(box(400, 400, 200), z=BALL_Z)
    shell = _shell(RETICLE_R_OUT, RETICLE_R_IN)
    strokes = None
    for sx in (-1, 1):
        wire = bd.Polyline(*[(sx * x, y) for x, y in ARM])
        face = bd.Face(wire.offset_2d(RETICLE_W / 2, kind=bd.Kind.INTERSECTION))
        s = at(bd.extrude(face, amount=70.0), z=BALL_Z + 18.0)
        strokes = s if strokes is None else strokes + s
    strokes = strokes + at(prism(6, DOT_R, 70.0), z=BALL_Z + 18.0)
    reticle = shell & strokes

    # --- checks ---
    bl, bh = bbox_mm(bezel_s.shape)
    dl, dh = bbox_mm(dome)
    rl, rh = bbox_mm(reticle)
    expect(len(reticle.solids()) >= 3, "the reticle has its two arms and its dot")
    expect(_volume(_sphere(BALL_R) - at(bd.Sphere(DOME_IN_R), z=DOME_Z)) < 1e-6, "the ball is inside the dome")
    expect(max(abs(dl[0]), abs(dh[0]), abs(dl[1]), abs(dh[1])) <= bezel_in and DOME_OUT_R * math.cos(math.asin((BALL_Z - DOME_Z) / DOME_OUT_R)) < bezel_in * math.cos(math.pi / 32),
           "the dome is inside the bezel's inner radius")
    expect(dl[2] >= BALL_Z - 0.01 and dl[2] < bezel_front and dh[2] > bezel_front,
           "the dome rises from inside the bezel to above its front")
    expect(BALL_R + MARGIN_MM <= bezel_in,
           f"the ball's bounding radius {BALL_R:.0f} mm is inside the bezel's {bezel_in:.0f} mm with {MARGIN_MM:.0f} mm margin")
    # Over the sub's pitch range (±30°), any heading and a full roll, the ball only turns about its centre, so its
    # reach is its radius at every attitude; the housing must clear that sphere everywhere (ball vs every housing solid).
    clashes = [s.role for s in [plate, bezel_s, ring_s, *bolts] if _volume(s.shape & _sphere(BALL_R)) > 1e-6]
    expect(not clashes, f"a housing solid clips the ball at some attitude: {clashes}")
    expect(RETICLE_R_IN > BALL_R and _volume(reticle & dome) < 1e-6
           and _volume(reticle & _sphere(BALL_R)) < 1e-6, "the reticle is in front of the ball and behind the dome")
    expect(rh[2] > BALL_Z + BALL_R * 0.9, "the reticle lies on the ball's front")
    expect(abs(bbox_mm(plate.shape)[0][2]) < 0.01, "the plate's back is on Z=0")
    fixed = [plate, bezel_s, ring_s, *bolts]
    glass = [Solid(dome, "glass")]
    ret = [Solid(reticle, "control_interface")]
    expect_in_front(fixed + glass + ret, SLUG)
    stand = max(dh[2], rh[2], BALL_Z + BALL_R)
    expect(stand <= MAX_STAND_OUT_MM, f"stands {stand:.1f} mm out; limit {MAX_STAND_OUT_MM:.0f}")
    return {"fixed": fixed, "glass": glass, "reticle": ret, "ball": [Solid(ball, "readout_face")], "stand_out": stand,
            "plate_mm": plate_w, "k": k}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    s_ = solids()
    rh = export_solids_glb(s_["fixed"], d / f"{SLUG}_housing.glb", "NavballHousing")
    rd = export_solids_glb(s_["glass"], d / f"{SLUG}_dome.glb", "NavballDome", *SPHERE_TOL)
    rr = export_solids_glb(s_["reticle"], d / f"{SLUG}_reticle.glb", "NavballReticle", *RETICLE_TOL)
    rb = export_solids_glb(s_["ball"], d / f"{SLUG}_ball.glb", "NavballBall", *SPHERE_TOL)
    tris = rh["triangles"] + rd["triangles"] + rr["triangles"] + rb["triangles"]
    expect(tris <= BUDGET, f"{tris} triangles; this scene's budget {BUDGET}")

    z = lambda mm: mm / 1000.0
    s = Scene("Navball", script="res://src/interact/navball.gd")
    s.node("Housing", instance=rh["glb"])
    s.node("Ball", instance=rb["glb"], props={"transform": Xform(origin=(0, 0, z(BALL_Z)))})
    s.node("NavballBall", parent="Ball", type_=None, props={"transform": Xform(basis=rest_basis())})
    s.node("Reticle", instance=rr["glb"])
    s.node("Dome", instance=rd["glb"])

    s.set(".", ball_path="Ball/NavballBall")   # NodePath-typed export: a plain value, no node_paths header; no digit windows, so no labels
    s.write(d / f"{SLUG}.tscn")
    _review(d)
    plate = s_["plate_mm"]
    write_entry(GROUP, SLUG, {
        "kind": "display",
        "summary": "Attitude ball: a 110 mm ball behind a glass dome in the multidisplay's bezel, plate, orange ring and "
                   "with a small fixed orange reticle in front of the ball. "
                   "The root is a Navball.",
        "tags": ["display", "navball", "attitude", "ball", "heading", "pitch", "round", "instrument", "pilot"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "Navball", "node": ".",
                      "ball": "Ball/NavballBall (a MeshInstance3D the script turns and gives the mask material)",
                      "reads": "SubFrame.render_transform() from group sub_frame (no digit windows: the Label3D paths are unset)",
                      "wiring": "none: put the sub's SubFrame in group sub_frame"},
        "footprint_mm": [plate, plate],
        "stand_out_mm": round(s_["stand_out"], 2),
        "mount": "back on Z=0, centred on the origin; faces +Z. The ball's rear half sinks behind the mount face "
                 "through a bore in the plate: the parent provides the cutout below",
        "panel_cutout": {"shape": "round", "diameter_mm": round(2 * BORE_R, 1)},
        "keep_clear_mm": {"behind_face": round(BALL_R - BALL_Z + 1.0, 1), "radius": round(BALL_R + 1.0, 1)},
        "depth_mm": {"behind_origin": round(BALL_R - BALL_Z, 1), "in_front_of_origin": round(s_["stand_out"], 2)},
        "set_on_instance": {"mount_rotation_deg": "the ball's marking frame relative to its node",
                            "upper_swatch, lower_swatch, mark_swatch": "palette swatches of the ball",
                            "frame_group": "where the sub pose comes from"},
        "limits": {"max_stand_out_mm": MAX_STAND_OUT_MM},
        "triangle_budget": BUDGET,      # approved by Tristan at look review round 1 (#467), replaces the kit's 1,500
        "uses": list(USES),
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}


def _review(d) -> None:
    """Review cameras and the sample readouts the render tool feeds the digits."""
    cams = [
        {"name": "navball_housing", "pos": [0.05, 0.1, 0.62], "look_at": [0.0, 0.0, 0.03], "fov": 28.0},
        {"name": "navball_readouts", "pos": [0.0, 0.0, 0.7], "look_at": [0.0, 0.0, 0.03], "fov": 18.0},
        {"name": "pilot_eye", "pos": [0.0, 0.1, 0.7], "look_at": [0.0, 0.0, 0.03], "fov": 24.0},
        {"name": "pilot_eye_red", "pos": [0.0, 0.1, 0.7], "look_at": [0.0, 0.0, 0.03], "fov": 24.0, "light": "red"},
        {"name": "navball_readouts_red", "pos": [0.0, 0.0, 0.7], "look_at": [0.0, 0.0, 0.03], "fov": 18.0, "light": "red"},
        {"name": "profile", "pos": [0.6, 0.0, 0.03], "look_at": [0.0, 0.0, 0.03], "ortho": 0.26},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    (review / "samples.json").write_text(json.dumps({"group": SAMPLE_SOURCE_GROUP, "values": SAMPLES}, indent=1) + "\n")
    for n in (".gdignore", "cameras.json", "samples.json"):
        note(review / n)
