"""decoy: the carried noisemaker decoy (furniture). Behaviour: DecoyItem.

Brief (#746, #750): a stubby round-nosed torpedo about 55 cm long and 16 cm across, a small finned tail cap, hazard
yellow with a black band, a NOISEMAKER label plate and a carry handle on top. It is used in the rack, the drawer cradle
(DecoyCradle seats it at its origin) and the player's arms. Under about 400 triangles, so six fit in the countermeasures
station's rack (#758).

DecoyItem's local axes: the decoy lies along -Z (nose at -Z), axis through the origin, centred on it, handle up (+Y).
Modelled Y-up with the nose along +Z, then turned half a circle about Y. The label is a plain aluminium plate: lettering
is not modelled at this budget.
"""
import build123d as bd

from cadkit.solids import Solid, at, box, prism, expect, bbox_mm, export_solids_glb
from cadkit.library import out_dir, res, write_entry
from cadkit.tscn import Scene, grab_box

SLUG, GROUP = "decoy", "furniture"
USES: list[str] = []
SIDES = 12                                      # flats face +-X and +-Y
R_BODY, NOSE_ROUND = 80.0, 45.0
LENGTH = 550.0
TAIL_Z1 = 50.0                                  # tail cap Z 0..50, body Z 50..LENGTH
R_TAIL = 60.0
FIN_SPAN, FIN_T, FIN_Z1 = 150.0, 6.0, 90.0      # two crossed plates, to FIN_Z1
BAND_Z0, BAND_Z1, R_BAND = 400.0, 470.0, 81.0
LABEL_Z0, LABEL_LEN, LABEL_H, LABEL_T = 120.0, 160.0, 50.0, 4.0
HANDLE_Z0, HANDLE_LEN, HANDLE_TOP = 210.0, 130.0, 110.0
POST_W, POST_D, BAR_H = 10.0, 12.0, 12.0
MAX_TRIANGLES = 400


def solids() -> list[Solid]:
    body = at(prism(SIDES, R_BODY, LENGTH - TAIL_Z1, chamfer_top=NOSE_ROUND), z=TAIL_Z1)
    tail = prism(SIDES, R_TAIL, TAIL_Z1 + 5.0)
    fins = at(box(FIN_SPAN, FIN_T, FIN_Z1), z=0) + at(box(FIN_T, FIN_SPAN, FIN_Z1), z=0)
    band = at(prism(SIDES, R_BAND, BAND_Z1 - BAND_Z0), z=BAND_Z0)
    apothem = R_BODY * 0.9659258                # flat distance of a 12-gon, cos(15 deg)
    label = at(box(LABEL_T, LABEL_H, LABEL_LEN), x=apothem - 1.0, z=LABEL_Z0)
    bar_y = HANDLE_TOP - BAR_H / 2
    post_h = HANDLE_TOP - (apothem - 8.0)
    post_y = HANDLE_TOP - post_h / 2
    handle = (at(box(POST_W, BAR_H, HANDLE_LEN), y=bar_y, z=HANDLE_Z0)
              + at(box(POST_W, post_h, POST_D), y=post_y, z=HANDLE_Z0)
              + at(box(POST_W, post_h, POST_D), y=post_y, z=HANDLE_Z0 + HANDLE_LEN - POST_D))

    hull = body + tail + fins
    lo, hi = bbox_mm(hull)
    expect(abs(lo[2]) < 0.01 and abs(hi[2] - LENGTH) < 0.01, f"decoy spans Z {lo[2]:.1f}..{hi[2]:.1f}; the brief says about 550 long")
    expect(520.0 <= hi[2] - lo[2] <= 580.0, f"decoy {hi[2] - lo[2]:.0f} mm long; the brief says about 550")
    blo, bhi = bbox_mm(body)
    expect(150.0 <= bhi[0] - blo[0] <= 165.0 and 150.0 <= bhi[1] - blo[1] <= 165.0,
           f"decoy {bhi[0] - blo[0]:.0f} x {bhi[1] - blo[1]:.0f} mm across; the brief says about 160")
    flo, fhi = bbox_mm(fins)
    expect(max(fhi[0], fhi[1]) <= R_BODY, f"fins reach {max(fhi[0], fhi[1]):.0f} mm, past the body's {R_BODY:.0f} radius")
    hlo, hhi = bbox_mm(handle)
    expect(hhi[1] <= HANDLE_TOP + 0.01 and hlo[2] > TAIL_Z1 and hhi[2] < LENGTH - NOSE_ROUND, "handle on the straight of the body")
    expect(hlo[1] < apothem, "handle posts reach into the body")
    expect(BAND_Z1 <= LENGTH - NOSE_ROUND + 1.0 and BAND_Z0 > HANDLE_Z0 + HANDLE_LEN, "band on the straight, clear of the handle")
    expect(R_BAND > R_BODY, "band proud of the body")

    def turn(s: bd.Shape) -> bd.Shape:
        """Centre along the length and turn the nose to -Z."""
        return s.moved(bd.Location((0, 0, -LENGTH / 2))).rotate(axis=bd.Axis.Y, angle=180)
    return [Solid(turn(body), "hazard_stripe"), Solid(turn(band), "trim_black"), Solid(turn(tail), "trim_black"),
            Solid(turn(fins), "trim_black"), Solid(turn(label), "label_plate"), Solid(turn(handle), "control_interface")]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    rep = export_solids_glb(solids(), d / f"{SLUG}.glb", "DecoyBody")
    tris = rep["triangles"]
    expect(tris <= MAX_TRIANGLES, f"{tris} triangles; the arc allows under about {MAX_TRIANGLES} (six in the rack)")
    s = Scene("Decoy", script="res://src/interact/decoy_item.gd")
    s.node("Body", instance=rep["glb"])
    grab_box(s, ".", (0.16, 0.19, LENGTH / 1000), (0, 0.0165, 0))
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "furniture",
        "summary": "Noisemaker decoy: a stubby round-nosed torpedo in hazard yellow with a black band, finned tail cap, "
                   "NOISEMAKER label plate and an orange carry handle. DecoyItem carries it; DecoyCradle seats it.",
        "tags": ["decoy", "noisemaker", "torpedo", "countermeasure", "carried"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "DecoyItem", "values": "carried/seated state", "signal": "carried_changed",
                      "wire": "seat in a DecoyCradle (rack slot or launch drawer)"},
        "footprint_mm": [160, LENGTH],
        "stand_out_mm": 160,
        "mount": "lies along -Z (nose -Z), centred on the origin with its axis through it, handle up (+Y)",
        "set_on_instance": {"lift_height, carry_offset": "carry motion"},
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
