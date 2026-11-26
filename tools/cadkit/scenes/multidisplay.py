"""multidisplay: the housing of the round digital instrument, with the MultiDisplay screen drawn on it (concept #458).

A heavy matte black round bezel with four hex bolts in a square powder-coated grey plate, a thin safety-orange ring
round the bezel, an engraved label plate and a recessed screen disc. The face is the `MultiDisplay` script with the
pilot preset. The build parameter SCREEN_D_MM (default 200) scales the whole housing; the plate's size limit is
MAX_PLATE_MM (the pilot strip, #446, does not exist yet, so the limit is a named figure to adjust).

`housing(screen_d_mm)` is the shared housing family: the navball's script (#459) imports it with
`scene_module("multidisplay").housing(...)` (and lists "multidisplay" in USES).
Frame: back on Z=0, centred on the origin, face toward +Z.
"""
from cadkit.solids import Solid, at, box, prism, bbox_mm, expect, expect_in_front, export_solids_glb
from cadkit.library import note, out_dir, res, write_entry
from cadkit.tscn import SName, Scene, Xform

import json

SLUG, GROUP = "multidisplay", "kit"
USES: list[str] = []
SCREEN_D_MM = 200.0                 # the build parameter: diameter of the screen (matches the gauge dial)
REF_D_MM = 140.0                    # every figure below is for this diameter and scales with SCREEN_D_MM
MAX_PLATE_MM = 280.0                # the largest plate that fits the strip (a named figure to adjust)
MAX_STAND_OUT_MM = 26.0
SIDES = 32
PILOT_PRESET = "res://assets/models/cockpit/pilot_multidisplay.tres"
SOURCE_GROUP = "sub_readouts"
# Sample values for the review renders (the pilot preset's readouts); the render tool serves them to the display.
SAMPLES = {"depth": 142.0, "tank_fraction": 0.8, "buoyancy": -0.12, "altitude": 6.4,
           "vertical_speed": -1.2, "air_fraction": 0.7}


def housing(screen_d_mm: float = SCREEN_D_MM, max_plate_mm: float = MAX_PLATE_MM) -> dict:
    """The housing solids and the figures a parent needs, for a screen of this diameter. Checks included."""
    k = screen_d_mm / REF_D_MM
    plate_w, plate_t = 190.0 * k, 8.0 * k
    bezel_in, bezel_out, bezel_h = 73.0 * k, 84.0 * k, 24.0 * k
    ring_out, ring_h = 87.0 * k, 3.0 * k
    disc_r, disc_h = bezel_in, 12.0 * k
    bolt_at, bolt_r, bolt_h = 80.0 * k, 5.5 * k, 3.0 * k
    label_w, label_h, label_y = 46.0 * k, 6.0 * k, -91.0 * k

    plate = box(plate_w, plate_w, plate_t, chamfer_mm=2.0 * k)
    bezel = prism(SIDES, bezel_out, bezel_h, chamfer_top=3.0 * k) - prism(SIDES, bezel_in, bezel_h)
    ring = at(prism(SIDES, ring_out, ring_h) - prism(SIDES, bezel_out, ring_h), z=plate_t)
    disc = prism(SIDES, disc_r, disc_h)
    bolts = [at(prism(6, bolt_r, bolt_h, chamfer_top=0.6 * k), x=sx * bolt_at, y=sy * bolt_at, z=plate_t)
             for sx in (-1, 1) for sy in (-1, 1)]
    label = at(box(label_w, label_h, 1.0 * k), y=label_y, z=plate_t)

    pl, ph = bbox_mm(plate)
    bl, bh = bbox_mm(bezel)
    rl, rh = bbox_mm(ring)
    dl, dh = bbox_mm(disc)
    expect(abs(pl[2]) < 0.01 and abs(bl[2]) < 0.01 and min(rl[2], dl[2]) >= -0.01,
           "the back is on Z=0 and nothing is behind it")
    expect(ph[2] > bl[2] and bh[2] > ph[2], "the plate is in front of the bezel's back, and the bezel stands proud of the plate")
    expect(rl[2] >= ph[2] - 0.01 and rh[2] < bh[2], "the orange ring sits on the plate, below the bezel's front")
    expect(bezel_out - 0.01 <= ring_out - 0.5 * k and ring_out < plate_w / 2,
           "the orange ring is round the bezel and inside the plate")
    expect(abs(dh[0]) <= bezel_in + 0.01 and dh[2] < bh[2] and dl[2] >= -0.01, "the screen disc is inside the bezel, below its front")
    expect(plate_w <= max_plate_mm + 0.01, f"the plate is {plate_w:.0f} mm; the strip allows {max_plate_mm:.0f}")
    expect(bh[2] <= MAX_STAND_OUT_MM * k + 0.01, f"stands {bh[2]:.1f} mm out; limit {MAX_STAND_OUT_MM * k:.1f}")
    expect(all(abs(bbox_mm(b)[1][0]) + bolt_r < plate_w / 2 for b in bolts), "the bolts are inside the plate")
    expect(abs(label_y) + label_h / 2 < plate_w / 2 and abs(label_y) - label_h / 2 > ring_out,
           "the label plate sits on the plate, clear of the ring")
    solids = [Solid(plate, "control_grey"), Solid(bezel, "trim_black"), Solid(ring, "control_interface"),
              Solid(disc, "readout_face"), Solid(label, "trim_black"), *[Solid(b, "trim_black") for b in bolts]]
    expect_in_front(solids, SLUG)
    return {"solids": solids, "k": k, "plate_mm": plate_w, "stand_out_mm": bh[2], "screen_front_mm": dh[2],
            "bezel_out_mm": bezel_out}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    h = housing()
    rep = export_solids_glb(h["solids"], d / f"{SLUG}_housing.glb", "MultiDisplayHousing")
    tris = rep["triangles"]
    expect(abs(SCREEN_D_MM - 200.0) < 0.01, f"the screen is {SCREEN_D_MM:.0f} mm; the gauge dial is 200")
    expect(tris <= 1500, f"{tris} triangles; kit budget 1500")
    s = Scene("MultiDisplayKit")
    s.node("Housing", instance=rep["glb"])
    s.node("Screen", type_="MeshInstance3D", script="res://src/interact/multi_display.gd",
           props={"transform": Xform(origin=(0, 0, (h["screen_front_mm"] + 0.3) / 1000)),
                  "screen_diameter": SCREEN_D_MM / 1000, "source_group": SName(SOURCE_GROUP),
                  "preset": s.ext("Resource", PILOT_PRESET)})
    s.write(d / f"{SLUG}.tscn")
    _review(d)
    plate = h["plate_mm"]
    write_entry(GROUP, SLUG, {
        "kind": "display",
        "summary": "Round digital instrument: heavy matte black bezel with four hex bolts in a square grey plate, a thin "
                   "orange ring, a label plate and a recessed screen. The Screen node is a MultiDisplay with the pilot preset.",
        "tags": ["display", "multidisplay", "round", "screen", "instrument", "pilot", "depth"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "MultiDisplay", "node": "Screen",
                      "reads": "readout(name) on the first node in source_group"},
        "footprint_mm": [plate, plate],
        "stand_out_mm": round(h["stand_out_mm"], 2),
        "extent_radii": {"plate_half_width": round(plate / 2 / (SCREEN_D_MM / 2), 4),
                         "bezel": round(h["bezel_out_mm"] / (SCREEN_D_MM / 2), 4)},
        "depth_mm": {"behind_origin": 0.0, "in_front_of_origin": round(h["stand_out_mm"], 2)},
        "mount": "back on Z=0, centred on the origin; the screen faces +Z. Bolts to the plate's corners; no cutout needed",
        "set_on_instance": {
            "Screen:screen_diameter": "m; the quad. The housing is built for 0.2 (build parameter SCREEN_D_MM scales it for every user)",
            "Screen:slots, preset": "the four widget slots (top, left, right, bottom), or a MultiDisplayPreset",
            "Screen:source_group": "where the readouts come from",
            "Screen:chevrons_enabled, chevron_readout, chevron_count, chevron_step": "the centre chevron column",
            "Screen:ring_enabled, ring_readout, ring_segments, ring_warn_below, ring_alarm_below": "the segmented ring",
        },
        "limits": {"max_plate_mm": MAX_PLATE_MM, "max_stand_out_mm": MAX_STAND_OUT_MM},
        "uses": list(USES),
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}


def _review(d) -> None:
    """Review cameras and the sample readouts the render tool feeds the display."""
    cams = [
        {"name": "concept_housing", "pos": [0.04, 0.09, 0.62], "look_at": [0.0, 0.0, 0.012], "fov": 26.0},
        {"name": "concept_face", "pos": [0.0, 0.0, 0.7], "look_at": [0.0, 0.0, 0.012], "fov": 16.0},
        {"name": "pilot_eye", "pos": [0.0, 0.1, 0.7], "look_at": [0.0, 0.0, 0.01], "fov": 24.0},
        {"name": "pilot_eye_red", "pos": [0.0, 0.1, 0.7], "look_at": [0.0, 0.0, 0.01], "fov": 24.0, "light": "red"},
        {"name": "face_red", "pos": [0.0, 0.0, 0.7], "look_at": [0.0, 0.0, 0.012], "fov": 16.0, "light": "red"},
        {"name": "profile", "pos": [0.6, 0.0, 0.015], "look_at": [0.0, 0.0, 0.015], "ortho": 0.26},
    ]
    k = SCREEN_D_MM / REF_D_MM
    for c in cams:                      # the cameras were framed for REF_D_MM; scale them with the screen
        c["pos"] = [round(v * k, 4) for v in c["pos"]]
        c["look_at"] = [round(v * k, 4) for v in c["look_at"]]
        if "ortho" in c:
            c["ortho"] = round(c["ortho"] * k, 4)
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    (review / "samples.json").write_text(json.dumps({"group": SOURCE_GROUP, "values": SAMPLES}, indent=1) + "\n")
    for n in (".gdignore", "cameras.json", "samples.json"):
        note(review / n)
