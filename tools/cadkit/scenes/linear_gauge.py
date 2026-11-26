"""linear_gauge: a vertical bar instrument on a flat mount plate. Display: no base, mounts on a panel. Behaviour: LinearGauge.

Brief (#424, the saturation gauge beside each cradle): a dark bezelled slot with a graduated track, the bar rising from
the bottom. The bar is its own GLB, modelled standing on its origin, so LinearGauge scales its Y and the bar grows
upward from the bottom of the track. The slot is 200 mm of travel, LinearGauge's default track_height.
"""
from cadkit.solids import Solid, at, box, expect, expect_in_front, bbox_mm, export_solids_glb
from cadkit.library import out_dir, res, write_entry
from cadkit.tscn import Scene, Xform

SLUG, GROUP = "linear_gauge", "kit"
USES: list[str] = []
TRAVEL = 200.0                                   # bar height at full, mm (LinearGauge.track_height 0.2 m)
PLATE_W, PLATE_Y0, PLATE_Y1, PLATE_T = 40.0, -16.0, 216.0, 6.0
SLOT_W, SLOT_Y0, SLOT_Y1, SLOT_FLOOR = 16.0, -4.0, 204.0, 3.0
INSERT_T = 0.4
BAR_W, BAR_T, BAR_Z = 12.0, 2.5, 3.4
TICKS, TICK_LEN, TICK_W, TICK_T = 11, 7.0, 1.2, 0.8
MAX_STAND_OUT = 8.0


def solids() -> tuple[list[Solid], list[Solid], list[Solid]]:
    h = PLATE_Y1 - PLATE_Y0
    plate = at(box(PLATE_W, h, PLATE_T, chamfer_mm=1.0), y=(PLATE_Y0 + PLATE_Y1) / 2)
    slot_h = SLOT_Y1 - SLOT_Y0
    slot = at(box(SLOT_W, slot_h, PLATE_T - SLOT_FLOOR + 1.0), y=(SLOT_Y0 + SLOT_Y1) / 2, z=SLOT_FLOOR)
    plate = plate - slot
    insert = at(box(SLOT_W, slot_h, INSERT_T), y=(SLOT_Y0 + SLOT_Y1) / 2, z=SLOT_FLOOR)
    tick_x = SLOT_W / 2 + 1.5 + TICK_LEN / 2
    ticks = []
    for i in range(TICKS):
        y = TRAVEL * i / (TICKS - 1)
        for sx in (-1, 1):
            ticks.append(at(box(TICK_LEN, TICK_W, TICK_T), x=sx * tick_x, y=y, z=PLATE_T))
    bar = at(box(BAR_W, TRAVEL, BAR_T), y=TRAVEL / 2)
    for t in ticks[1:]:
        ticks[0] = ticks[0] + t

    plo, phi = bbox_mm(plate)
    blo, bhi = bbox_mm(bar)
    expect(len(plate.solids()) == 1, "plate is one solid")
    expect(abs(plo[2]) < 0.01 and abs(phi[2] - PLATE_T) < 0.01, "plate from the mount face (Z=0) to its front")
    expect(abs(blo[1]) < 0.01 and abs(bhi[1] - TRAVEL) < 0.01, "bar scales from the bottom: it stands on its origin, 0 to full travel")
    expect(abs(blo[2]) < 0.01 and abs(blo[0] + bhi[0]) < 0.01, "bar lies on Z=0 of its own frame, centred in X")
    expect(SLOT_Y0 <= 0 and SLOT_Y1 >= TRAVEL, "slot covers the whole travel of the bar")
    expect(BAR_W < SLOT_W, "bar narrower than the slot")
    expect(BAR_Z >= SLOT_FLOOR + INSERT_T and BAR_Z + BAR_T < PLATE_T, "bar sits inside the slot, above its floor and below the plate front")
    expect(SLOT_W / 2 + 1.5 + TICK_LEN <= PLATE_W / 2 - 1.0, "graduations stay on the plate beside the slot")
    expect(PLATE_Y0 < SLOT_Y0 and PLATE_Y1 > SLOT_Y1, "bezel all round the slot")
    thi = bbox_mm(ticks[0])[1]
    expect(thi[2] <= MAX_STAND_OUT, f"gauge stands {thi[2]:.1f} mm out; limit {MAX_STAND_OUT}")
    body = [Solid(plate, "control_grey"), Solid(insert, "interior_dark"), Solid(ticks[0], "readout_ink")]
    bar_s = [Solid(bar, "readout_ink")]
    expect_in_front(body, SLUG)
    return body, bar_s, []


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    body, bar, _ = solids()
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "LinearGaugeBody")
    rr = export_solids_glb(bar, d / f"{SLUG}_bar.glb", "LinearGaugeBar")
    s = Scene("LinearGauge", script="res://src/interact/linear_gauge.gd")
    s.node("Body", instance=rb["glb"])
    s.node("Bar", props={"transform": Xform(origin=(0, 0, BAR_Z / 1000))})
    s.node("Fill", parent="Bar", instance=rr["glb"])
    s.write(d / f"{SLUG}.tscn")
    tris = rb["triangles"] + rr["triangles"]
    expect(tris <= 1500, f"{tris} triangles; kit budget 1500")
    write_entry(GROUP, SLUG, {
        "kind": "display",
        "summary": "Vertical bar gauge: grey mount plate, dark slot with graduations either side, a bar that rises from the "
                   "bottom of the slot. LinearGauge scales the bar from a readout; colour steps ok/warn/alarm.",
        "tags": ["gauge", "bar", "linear", "vertical", "readout", "saturation", "instrument"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "LinearGauge", "reads": "readout(name) on the first node in source_group"},
        "footprint_mm": [PLATE_W, PLATE_Y1 - PLATE_Y0],
        "track_mm": {"travel": TRAVEL, "bottom_y": 0.0},
        "stand_out_mm": PLATE_T + TICK_T,
        "mount": "back on Z=0 (on a panel front), faces +Z; the bar's bottom is the origin, the track runs up +Y",
        "set_on_instance": {
            "readout, source_group, min_value, max_value": "what it shows and the scale",
            "warn_at, alarm_at": "where the colour steps (fractions)",
            "descending": "flip the bands so low values are the alarm end: ok above warn_at, warn down to alarm_at, "
                          "alarm below (for a remaining-capacity readout, e.g. warn_at 0.5, alarm_at 0.15)",
        },
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
