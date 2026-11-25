"""pan_trackball: the desk trackball that pans a view (PanBall), on the same 2x2 base and ring as `trackball`.

Brief: same footprint and look as the hydrophone trackball; the ball rests on the ring's lip and rolls in place.
The solids and constants are the trackball's (`scene_module("trackball")`), so the two cannot drift apart.
"""
from cadkit.solids import Solid, bbox_mm, expect, export_solids_glb
from cadkit.library import PLATE_T_MM, base_glb, base_size_mm, out_dir, quiet_noise, res, scene_module, write_entry
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "pan_trackball", "kit"
USES: list[str] = ["control_base", "trackball"]
BASE = (2, 2)


def solids() -> tuple[list[Solid], list[Solid]]:
    _tb = scene_module("trackball")
    body, ball = _tb.solids()
    w, h = base_size_mm(*BASE)
    lo, hi = bbox_mm(body[0].shape)
    expect(max(hi[0] - lo[0], hi[1] - lo[1]) <= min(w, h), f"ring {hi[0] - lo[0]:.0f} mm fits the {w:.0f} mm footprint")
    expect(_tb.BALL_Z - _tb.BALL_R >= PLATE_T_MM, "ball clears the plate: it rests on the ring, no panel cutout")
    expect(_tb.RING_IN_R < _tb.BALL_R, "ball rests on the ring's lip")
    return body, ball


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    _tb = scene_module("trackball")
    RING_R, BALL_R, BALL_Z = _tb.RING_R, _tb.BALL_R, _tb.BALL_Z
    body, ball = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "PanTrackballBody")
    rball = export_solids_glb(ball, d / f"{SLUG}_ball.glb", "PanTrackballBall", tol_mm=1.5, ang=0.6)
    w, h = base_size_mm(*BASE)
    s = Scene("PanTrackball", script="res://src/interact/pan_ball.gd")
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
        "summary": "Desk trackball in a black ring; rolling it pans a view (emits a 2D roll delta, not a bearing).",
        "tags": ["trackball", "pointing", "pan", "map", "roll"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "PanBall", "values": "2D roll delta", "signal": "rolled"},
        "base": f"{BASE[0]}x{BASE[1]}",
        "footprint_mm": [w, h],
        "stand_out_mm": BALL_Z + BALL_R,
        "mount": "back on Z=0, centred; front +Z",
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
