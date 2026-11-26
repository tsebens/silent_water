"""junction_box: a bolted steel junction box on a cable run (kit element, static). No behaviour.

Brief (#555, concept #534): a grey body with cable glands for the cable trays, a hinged lid shown closed, a hazard
stripe, and a marked spark anchor node (`SparkAnchor`) where #543's sparks spawn. The sparking and the repair are
#543's; this scene is a still body in one GLB.

Mount: back on Z=0, centred, faces +Z. Glands leave the top and bottom faces (the cable trays run vertically).
"""
from cadkit.solids import Solid, at, box, prism, expect, expect_in_front, bbox_mm, export_solids_glb
from cadkit.library import out_dir, res, write_entry
from cadkit.tscn import Scene, Xform

SLUG, GROUP = "junction_box", "kit"
USES: list[str] = []
W, H, D = 220.0, 180.0, 90.0                 # the body
LID_W, LID_H, LID_T = 208.0, 168.0, 8.0      # the closed lid, on the body's front
GLAND_X = (-55.0, 55.0)                      # two glands on the top face, two on the bottom
GLAND_NUT_R, GLAND_NUT_H, GLAND_R, GLAND_L = 14.0, 12.0, 9.0, 26.0
BOLT_R, BOLT_H = 6.0, 4.0
BOLT_X, BOLT_Y = 94.0, 72.0
STRIPE_W, STRIPE_H, STRIPE_T, STRIPE_Y = 152.0, 24.0, 1.5, -60.0
HINGE_X, HINGE_R, HINGE_L = -104.0, 5.0, 36.0
LATCH_X, LATCH_W, LATCH_H, LATCH_T = 98.0, 14.0, 34.0, 4.0
ANCHOR_X, ANCHOR_Y = 60.0, 50.0              # on the lid, upper right
MAX_STAND_OUT, MAX_TRIS = 110.0, 1500


def solids() -> tuple[list[Solid], float, float]:
    lid_z1 = D + LID_T
    body = box(W, H, D, chamfer_mm=3.0)
    lid = at(box(LID_W, LID_H, LID_T, chamfer_mm=2.0), z=D)
    stripe = at(box(STRIPE_W, STRIPE_H, STRIPE_T), y=STRIPE_Y, z=lid_z1)
    bolts = [at(prism(6, BOLT_R, BOLT_H), x=sx * BOLT_X, y=sy * BOLT_Y, z=lid_z1) for sx in (-1, 1) for sy in (-1, 1)]
    latch = at(box(LATCH_W, LATCH_H, LATCH_T), x=LATCH_X, z=lid_z1)
    hinge = [at(prism(8, HINGE_R, HINGE_L, rotation_deg=0.0), x=HINGE_X, y=sy * 50.0 - HINGE_L / 2, z=D + HINGE_R,
                rx=-90) for sy in (-1, 1)]
    nuts, stubs = [], []
    for sy in (-1, 1):
        for gx in GLAND_X:
            rx = -90 if sy > 0 else 90        # +Z of the prism points along +Y (top) or -Y (bottom)
            nuts.append(at(prism(6, GLAND_NUT_R, GLAND_NUT_H), x=gx, y=sy * H / 2, z=D / 2, rx=rx))
            stubs.append(at(prism(8, GLAND_R, GLAND_L), x=gx, y=sy * H / 2, z=D / 2, rx=rx))
    lo_h, hi_h = bbox_mm(hinge[0])

    allshapes = [body, lid, stripe, latch] + bolts + hinge + nuts + stubs
    lo, hi = bbox_mm(allshapes[0])
    los = [bbox_mm(s)[0] for s in allshapes]
    his = [bbox_mm(s)[1] for s in allshapes]
    lo = tuple(min(l[i] for l in los) for i in range(3))
    hi = tuple(max(h[i] for h in his) for i in range(3))
    stand_out = hi[2]
    expect(abs(lo[2]) < 0.01, f"back on Z=0, not {lo[2]:.2f}")
    expect(stand_out <= MAX_STAND_OUT, f"box stands {stand_out:.1f} mm out; limit {MAX_STAND_OUT}")
    expect(stand_out > D + LID_T, "bolts and latch stand proud of the lid")
    expect(hi[0] <= W / 2 + 0.01 and lo[0] >= -W / 2 - 0.01, f"parts stay within the {W:.0f} mm width: {lo[0]}..{hi[0]}")
    expect(lo_h[0] >= -W / 2, "the hinge knuckles stay inside the body's width")
    expect(abs(hi[1] - (H / 2 + GLAND_L)) < 0.01 and abs(lo[1] + (H / 2 + GLAND_L)) < 0.01,
           f"glands reach {GLAND_L:.0f} mm beyond the top and bottom faces")
    sy0 = STRIPE_Y - STRIPE_H / 2
    expect(sy0 >= -LID_H / 2 and STRIPE_Y + STRIPE_H / 2 <= LID_H / 2 and STRIPE_W / 2 <= LID_W / 2,
           "the hazard stripe lies on the lid")
    expect(STRIPE_W / 2 < BOLT_X - BOLT_R, "the stripe clears the lid bolts")
    expect(ANCHOR_X + 0.0 < LID_W / 2 and ANCHOR_Y < LID_H / 2, "the spark anchor lies on the lid")
    expect(all(len(s.solids()) == 1 for s in (body, lid)), "body and lid are each one solid")
    out = ([Solid(body, "interior_panel"), Solid(lid, "interior_panel"), Solid(stripe, "hazard_stripe"),
            Solid(latch, "trim_black")]
           + [Solid(b, "trim_black") for b in bolts] + [Solid(h, "hull_metal") for h in hinge]
           + [Solid(n, "hull_metal") for n in nuts] + [Solid(s, "interior_dark") for s in stubs])
    expect_in_front(out, SLUG)
    return out, stand_out, hi[1] - lo[1]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    parts, stand_out, height = solids()
    rep = export_solids_glb(parts, d / f"{SLUG}.glb", "JunctionBoxBody")
    tris = rep["triangles"]
    expect(tris <= MAX_TRIS, f"{tris} triangles; the kit allows {MAX_TRIS}")
    s = Scene("JunctionBox", script=None)
    s.node("Body", instance=rep["glb"])
    s.node("SparkAnchor", type_="Marker3D",
           props={"transform": Xform(origin=(ANCHOR_X / 1000, ANCHOR_Y / 1000, stand_out / 1000))})
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "element",
        "summary": "Bolted steel junction box for a cable run: grey body, closed hinged lid with a latch and corner bolts, "
                   "hazard stripe on the lid, four cable glands (two top, two bottom). Static; no script. The SparkAnchor "
                   "Marker3D on the lid is where sparks spawn (#543).",
        "tags": ["junction box", "cable", "electrical", "spark", "hazard", "static"],
        "scene": res(d / f"{SLUG}.tscn"),
        "footprint_mm": [W, round(height, 1)],
        "stand_out_mm": round(stand_out, 1),
        "mount": "back on Z=0, centred; faces +Z; cable glands leave the top and bottom faces",
        "anchor": "SparkAnchor (Marker3D) on the lid face, upper right; sparks spawn there",
        "uses": [],
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
