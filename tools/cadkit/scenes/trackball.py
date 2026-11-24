"""trackball: a desk trackball in a black ring on a 2x2 base. Behaviour: Trackball (trains the hydrophone).

Brief: ball about 56 mm across, two thirds proud of the ring so a palm can roll it; ring wide enough to read as a
bezel at arm's length. The ball is its own GLB with its centre at the origin, so it can turn in place.
"""
import build123d as bd

from cadkit.solids import Solid, at, prism, expect, expect_in_front, export_solids_glb
from cadkit.library import PLATE_T_MM, base_glb, base_size_mm, out_dir, quiet_noise, res, write_entry, scene_module
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "trackball", "kit"
USES: list[str] = ["control_base"]
BASE = (2, 2)
RING_R, RING_IN_R, RING_H = 44.0, 27.5, 24.0
BALL_R = 28.0
# The ball rests on the ring's inner lip, so it needs no hole in the panel behind it.
BALL_Z = PLATE_T_MM + RING_H + (BALL_R ** 2 - RING_IN_R ** 2) ** 0.5


def solids() -> tuple[list[Solid], list[Solid]]:
    ring = at(prism(16, RING_R, RING_H, chamfer_top=3.0) - prism(16, RING_IN_R, RING_H), z=PLATE_T_MM)
    ball = bd.Sphere(BALL_R)
    expect(RING_IN_R < BALL_R, "ball rests on the ring's lip")
    expect(BALL_Z - BALL_R >= PLATE_T_MM, "ball clears the plate: no panel cutout needed")
    proud = BALL_Z + BALL_R - (PLATE_T_MM + RING_H)
    expect(BALL_R * 0.9 < proud < BALL_R * 1.4, f"ball stands {proud:.0f} mm proud of the ring: rollable, not perched")
    for bx, by in scene_module("control_base").bolt_positions(*BASE):
        expect((bx * bx + by * by) ** 0.5 > RING_R + 3.5, f"bolt at {bx},{by} clear of the ring")
    out = [Solid(ring, "black")], [Solid(ball, "black")]
    expect_in_front(out[0] + [Solid(at(ball, z=BALL_Z), "black")], SLUG)
    return out


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, ball = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "TrackballBody")
    rball = export_solids_glb(ball, d / f"{SLUG}_ball.glb", "TrackballBall", tol_mm=1.5, ang=0.6)
    w, h = base_size_mm(*BASE)
    s = Scene("Trackball", script="res://src/sonar/trackball.gd")
    s.set(".", noise_profile=quiet_noise(s, 0.005, 0.5), ball=NodePath("Ball"))
    s.node("Base", instance=base_glb(*BASE))
    s.node("Body", instance=rb["glb"])
    s.node("Ball", instance=rball["glb"], props={"transform": Xform(origin=(0, 0, BALL_Z / 1000))})
    top = (BALL_Z + BALL_R) / 1000
    grab_box(s, ".", (2 * RING_R / 1000, 2 * RING_R / 1000, top), (0, 0, top / 2))
    s.write(d / f"{SLUG}.tscn")
    tris = rb["triangles"] + rball["triangles"]
    write_entry(GROUP, SLUG, {
        "kind": "control",
        "summary": "Desk trackball in a black ring; rolling it sideways trains the hydrophone bearing.",
        "tags": ["trackball", "pointing", "hydrophone", "bearing", "sonar"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "Trackball (extends HydrophoneWheel)", "values": "bearing, unbounded, deg",
                      "signal": "value_changed", "wire": "SonarStation.wheel"},
        "base": f"{BASE[0]}x{BASE[1]}",
        "footprint_mm": [w, h],
        "stand_out_mm": BALL_Z + BALL_R,
        "mount": "back on Z=0, centred; front +Z",
        "set_on_instance": {"label": "name at the aiming point"},
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
