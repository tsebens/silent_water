"""push_button: a momentary push button element (no base of its own: it mounts on a base plate or panel).

Brief: black 8-gon bezel ring, grey 8-gon cap standing 4 mm proud, 4 mm travel. Behaviour: PushButton.
"""
import build123d as bd

from kitcad import Solid, expect_in_front, at, prism, expect, bbox_mm, export_solids_glb
from spike import out_dir, quiet_noise, res, write_entry
from tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "push_button", "kit"
RING_R, RING_IN_R, RING_H = 12.0, 9.5, 6.0
CAP_R, CAP_H, CAP_Z = 9.0, 8.0, 2.0
TRAVEL = 4.0


def solids() -> tuple[list[Solid], list[Solid]]:
    ring = prism(8, RING_R, RING_H) - prism(8, RING_IN_R, RING_H)
    cap = at(prism(8, CAP_R, CAP_H, chamfer_top=1.5), z=CAP_Z)
    expect(len(ring.solids()) == 1, "ring is one solid")
    expect(CAP_R < RING_IN_R, "cap fits inside the ring")
    expect(CAP_Z + CAP_H - TRAVEL >= RING_H - 0.01, "pressed cap stays flush or proud of the ring")
    expect(bbox_mm(cap)[1][2] == CAP_Z + CAP_H, "cap top where the brief says")
    body, cap = [Solid(ring, "black")], [Solid(cap, "powder_grey")]
    expect_in_front(body + cap, SLUG)
    return body, cap


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, cap = solids()
    rb = export_solids_glb(body, d / "push_button_body.glb", "PushButtonBody")
    rc = export_solids_glb(cap, d / "push_button_cap.glb", "PushButtonCap")
    s = Scene("PushButton", script="res://src/interact/push_button.gd")
    noise = quiet_noise(s, 0.01, 0.5)
    s.set(".", travel=TRAVEL / 1000, noise_profile=noise, plunger=NodePath("Plunger"))
    s.node("Body", instance=rb["glb"])
    s.node("Plunger")
    s.node("Cap", parent="Plunger", instance=rc["glb"])
    grab_box(s, ".", (0.026, 0.026, 0.014), (0, 0, 0.007))
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "element",
        "summary": "Momentary push button: black bezel ring, grey cap, 4 mm travel. Mounts on a plate, no base.",
        "tags": ["button", "push", "momentary", "key"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "PushButton", "values": "0 released, 1 held", "signal": "value_changed"},
        "footprint_mm": [2 * RING_R, 2 * RING_R],
        "stand_out_mm": CAP_Z + CAP_H,
        "mount": "back on Z=0 (put it on a plate front), centred; presses along -Z",
        "set_on_instance": {"label": "name at the aiming point"},
        "triangles": rb["triangles"] + rc["triangles"],
    })
    return {"slug": SLUG, "triangles": rb["triangles"] + rc["triangles"]}
