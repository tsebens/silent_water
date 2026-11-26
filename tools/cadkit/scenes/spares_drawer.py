"""spares_drawer: a clear-fronted drawer holding up to four spare breaker modules (kit display, static). Behaviour: SparesDrawer.

Brief (#561, concept #534): a recessed tray behind a pane of glass, label plate SPARES. Each spare is a stand-in
built from `breaker_module`'s body GLB (no handle, no lamp), lying face-out in its own slot node (`Spare1`..`Spare4`).
`SparesDrawer` extends Node, so it sits on a child node `Drawer` of the Node3D root and its `slots` are the four nodes.

Mount: back on Z=0, centred, faces +Z. At the foot of a board.
"""
from cadkit.solids import Solid, at, box, expect, expect_in_front, bbox_mm, export_solids_glb, read_glb
from cadkit.library import entry, out_dir, res, write_entry
from cadkit.tscn import NodePath, Scene, Xform

SLUG, GROUP = "spares_drawer", "kit"
USES: list[str] = ["breaker_module"]
SLOTS = 4
MAX_W, MAX_H, MAX_STAND_OUT, MAX_TRIS = 900.0, 250.0, 300.0, 700
GAP, LIP = 10.0, 20.0                 # between spares and to the pocket wall; the frame lip round the pocket
D, POCKET_D = 36.0, 26.0              # frame depth; the tray's depth below the frame's front face
GLASS_T = 3.0
LABEL_W, LABEL_H, LABEL_T = 100.0, 10.0, 1.5


def solids(plate_w: float, plate_h: float, body_t: float):
    """The module lies turned a quarter about Z: its height runs along X, its width along Y."""
    mod_w, mod_h = plate_h, plate_w
    pocket_w = SLOTS * mod_w + (SLOTS + 1) * GAP
    pocket_h = mod_h + 2 * GAP
    w, h = pocket_w + 2 * LIP, pocket_h + 2 * LIP
    floor_z = D - POCKET_D
    frame = box(w, h, D, chamfer_mm=2.0) - at(box(pocket_w, pocket_h, POCKET_D + 1.0), z=floor_z)
    glass = at(box(pocket_w + 4.0, pocket_h + 4.0, GLASS_T), z=D)
    label_y = pocket_h / 2 + 2.0 + (LIP - 2.0) / 2 + 1.0
    label = at(box(LABEL_W, LABEL_H, LABEL_T), y=label_y, z=D)
    spare_top = floor_z + body_t
    expect(len(frame.solids()) == 1, "frame is one solid")
    expect(spare_top < D - 1.0, f"spares (to z={spare_top:.1f}) sit below the glass at z={D}")
    expect(label_y - LABEL_H / 2 >= pocket_h / 2 + 2.0 and label_y + LABEL_H / 2 <= h / 2, "label plate sits on the top lip")
    parts = [Solid(frame, "interior_panel"), Solid(glass, "glass"), Solid(label, "control_grey")]
    xs = [(i - (SLOTS - 1) / 2) * (mod_w + GAP) for i in range(SLOTS)]
    expect(abs(xs[0]) + mod_w / 2 <= pocket_w / 2 - GAP + 0.01, "outer spares inside the pocket")
    expect_in_front(parts, SLUG)
    lo = [min(bbox_mm(p.shape)[0][i] for p in parts) for i in range(3)]
    hi = [max(bbox_mm(p.shape)[1][i] for p in parts) for i in range(3)]
    return parts, xs, floor_z, (w, h), hi[2], lo


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    bm = entry("breaker_module")
    plate_w, plate_h = bm["footprint_mm"]
    body_glb = d.parent / "breaker_module" / "breaker_module_body.glb"
    body_info = read_glb(body_glb)
    body_tris = sum(body_info["surfaces"].values())
    body_t = body_info["bounds"][1][2] * 1000.0     # read_glb bounds are metres
    parts, xs, floor_z, (w, h), stand_out, lo = solids(plate_w, plate_h, body_t)
    expect(abs(lo[2]) < 0.01, f"back on Z=0, not {lo[2]:.2f}")
    expect(w <= MAX_W and h <= MAX_H, f"footprint {w:.0f} x {h:.0f} within {MAX_W:.0f} x {MAX_H:.0f} mm")
    expect(stand_out <= MAX_STAND_OUT, f"drawer stands {stand_out:.1f} mm out; limit {MAX_STAND_OUT}")
    rep = export_solids_glb(parts, d / f"{SLUG}.glb", "SparesDrawerBody")
    tris = rep["triangles"] + SLOTS * body_tris
    expect(tris <= MAX_TRIS, f"{tris} triangles; the drawer's cap is {MAX_TRIS}")
    body_res = res(body_glb)
    s = Scene("SparesDrawer")
    s.node("Body", instance=rep["glb"])
    names = []
    for i, x in enumerate(xs):
        n = f"Spare{i + 1}"
        names.append(n)
        # Quarter turn about Z: module X -> +Y, module Y -> -X.
        s.node(n, instance=body_res, props={"transform": Xform.frame((0, 1, 0), (-1, 0, 0), (0, 0, 1),
                                                                     (x / 1000, 0, floor_z / 1000))})
    s.node("Drawer", type_="Node", script="res://src/interact/spares_drawer.gd")
    s.set("Drawer", slots=[NodePath(f"../{n}") for n in names])
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "display",
        "summary": "Clear-fronted spares drawer: a recessed tray behind glass holding up to four spare breaker "
                   "modules (stand-ins from breaker_module's body), label plate SPARES. The first N slots show, N "
                   "being the spares readout.",
        "tags": ["spares", "breaker", "drawer", "power", "display", "glass"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "SparesDrawer",
                      "values": "shows the first N of its four slots, N = spares_remaining clamped to 4",
                      "signal": "none: display only",
                      "wiring": f"`slots` is set in the scene (nodes {', '.join(names)}); on a child node `Drawer`"},
        "slots": names,
        "slot_count": SLOTS,
        "footprint_mm": [round(w, 1), round(h, 1)],
        "stand_out_mm": round(stand_out, 1),
        "mount": "back on Z=0, centred; faces +Z; spares lie face-out in the tray, handle-less",
        "uses": USES,
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
