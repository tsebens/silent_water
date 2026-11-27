"""loader_drawer: the decoy loader's sliding drawer (kit control). Behaviour: LoaderDrawer, with a DecoyCradle child.

Brief (#751, concept #746): a heavy drawer front with a viewing window, rails, a half-pipe cradle seat taking one decoy
(`DecoyCradle`), and an orange pull handle (`control_interface`). Mount: back on Z=0, centred; the drawer slides out
along +Z, travel 650 mm (LoaderDrawer's `travel_m`). The sleeve (the rails' housing) is the static `Body`; the drawer
(front, tray, handle) is its own GLB under `Slide`, which the root's `body` points at, with the cradle and the grab
box so they move with it. The decoy lies across the drawer (its axis along X, nose +X, label toward +Z) so the
front window shows its whole length when closed. Closed, the handle stands 450 mm out.
"""
from cadkit.solids import Solid, at, box, prism, expect, expect_in_front, bbox_mm, export_solids_glb
from cadkit.library import TRIANGLE_BUDGET, entry, out_dir, quiet_noise, res, write_entry
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "loader_drawer", "kit"
USES: list[str] = ["decoy"]
W, H = 800.0, 300.0                       # footprint of the sleeve and the drawer front
SLEEVE_D, SLEEVE_WALL = 390.0, 20.0       # the sleeve runs Z 0..390; its back wall is SLEEVE_WALL thick
CAV_W, CAV_H = 760.0, 260.0               # inside the sleeve
RAIL_T, RAIL_H = 10.0, 24.0               # rail strips on the cavity's side walls
FRONT_Z0, FRONT_T = SLEEVE_D, 30.0        # the drawer front, directly ahead of the sleeve
TRAY_W, TRAY_Z0 = 740.0, 90.0             # tray outer width; its back end
FLOOR_T, WALL_T, WALL_H = 12.0, 12.0, 90.0
FLOOR_Y = -98.0                           # the tray floor's upper face
SEAT_R, SEAT_W, SEAT_LEN = 82.0, 30.0, 180.0   # half-pipe radius, saddle thickness (X) and length (Z)
SADDLE_X = 150.0
AXIS_Y = FLOOR_Y + SEAT_R + 8.0           # the decoy's axis (the cradle's origin)
CRADLE_Z = 290.0
WIN_W, WIN_H = 580.0, 190.0               # viewing window in the front; the decoy is 550 x 160
PANE_T = 4.0
HANDLE_Y, HANDLE_W, HANDLE_H = 118.0, 300.0, 22.0
POST_W, POST_OUT = 24.0, 30.0             # handle posts; the handle stands POST_OUT ahead of the front
TRAVEL_MM = 650.0
STAND_OUT = 450.0
GRAB_MARGIN = 10.0


def sleeve_solids() -> list[Solid]:
    sleeve = box(W, H, SLEEVE_D, chamfer_mm=3.0) - at(box(CAV_W, CAV_H, SLEEVE_D), z=SLEEVE_WALL)
    rails = [at(box(RAIL_T, RAIL_H, SLEEVE_D - SLEEVE_WALL), x=sx * (CAV_W / 2 - RAIL_T / 2), y=FLOOR_Y + 40.0, z=SLEEVE_WALL)
             for sx in (-1, 1)]
    return [Solid(sleeve, "interior_panel"), Solid(rails[0] + rails[1], "trim_black")]


def drawer_solids(decoy_len: float, decoy_dia: float) -> list[Solid]:
    win_cut = at(box(WIN_W, WIN_H, FRONT_T + 2.0), y=AXIS_Y, z=FRONT_Z0 - 1.0)
    front = at(box(W, H, FRONT_T, chamfer_mm=4.0), z=FRONT_Z0) - win_cut
    pane = at(box(WIN_W + 20.0, WIN_H + 20.0, PANE_T), y=AXIS_Y, z=FRONT_Z0 + 2.0)
    tray_len = FRONT_Z0 - TRAY_Z0
    floor = at(box(TRAY_W, FLOOR_T, tray_len), y=FLOOR_Y - FLOOR_T / 2, z=TRAY_Z0)
    walls = [at(box(WALL_T, WALL_H, tray_len), x=sx * (TRAY_W / 2 - WALL_T / 2), y=FLOOR_Y + WALL_H / 2, z=TRAY_Z0)
             for sx in (-1, 1)]
    back = at(box(TRAY_W - 2 * WALL_T, WALL_H, WALL_T), y=FLOOR_Y + WALL_H / 2, z=TRAY_Z0)
    tray = floor + walls[0] + walls[1] + back
    saddle_h = AXIS_Y - FLOOR_Y
    cut = at(prism(16, SEAT_R, SEAT_W + 4.0), ry=90, x=-(SEAT_W + 4.0) / 2, y=AXIS_Y, z=CRADLE_Z)
    saddles = []
    for sx in (-1, 1):
        s = at(box(SEAT_W, saddle_h, SEAT_LEN, chamfer_mm=2.0), x=sx * SADDLE_X, y=FLOOR_Y + saddle_h / 2, z=CRADLE_Z - SEAT_LEN / 2)
        saddles.append(s - at(cut, x=sx * SADDLE_X))
    post_len = FRONT_T + POST_OUT
    posts = [at(box(POST_W, POST_W, POST_OUT), x=sx * (HANDLE_W / 2 - POST_W / 2), y=HANDLE_Y, z=FRONT_Z0 + FRONT_T)
             for sx in (-1, 1)]
    bar = at(box(HANDLE_W, HANDLE_H, POST_W), y=HANDLE_Y, z=FRONT_Z0 + FRONT_T + POST_OUT - POST_W)
    handle = posts[0] + posts[1] + bar

    # Constraints
    expect(len(front.solids()) == 1, "drawer front is one solid with its window cut")
    expect(WIN_W >= decoy_len + 20.0 and WIN_H >= decoy_dia + 20.0,
           f"window {WIN_W:.0f} x {WIN_H:.0f} shows the whole {decoy_len:.0f} x {decoy_dia:.0f} decoy with a margin")
    expect(WIN_W + 2 * 60.0 <= W and WIN_H / 2 + abs(AXIS_Y) + 20.0 < H / 2, "front keeps a solid frame round the window")
    expect(AXIS_Y - WIN_H / 2 > -H / 2 + 20.0 and AXIS_Y + WIN_H / 2 < HANDLE_Y - HANDLE_H / 2 - 5.0,
           "window clear of the handle above and the front's lower edge")
    expect(TRAY_W - 2 * WALL_T >= decoy_len + 100.0, f"tray inside {TRAY_W - 2 * WALL_T:.0f} mm takes the {decoy_len:.0f} mm decoy lengthwise")
    expect(TRAY_W / 2 + RAIL_T <= CAV_W / 2 + 0.01 and TRAY_W <= CAV_W, "drawer width fits the sleeve between its rails")
    expect(SADDLE_X + SEAT_W / 2 < decoy_len / 2 - 40.0, "saddles sit under the decoy's body, inside its length")
    expect(SEAT_R >= decoy_dia / 2 and SEAT_R <= decoy_dia / 2 + 6.0, f"half-pipe radius {SEAT_R:.0f} cups the {decoy_dia / 2:.0f} mm decoy")
    expect(AXIS_Y - decoy_dia / 2 > FLOOR_Y, "decoy lies clear above the tray floor")
    top = AXIS_Y + 110.0                 # the decoy's carry handle stands 110 mm over its axis
    expect(top < CAV_H / 2 - 10.0, f"decoy handle (to y={top:.0f}) clears the sleeve roof")
    expect(CRADLE_Z + decoy_dia / 2 < FRONT_Z0 and CRADLE_Z - decoy_dia / 2 > TRAY_Z0 + WALL_T, "decoy sits inside the tray's length")
    expect(TRAVEL_MM == 650.0, "travel is the 0.65 m LoaderDrawer's travel_m")
    expect(FRONT_Z0 + FRONT_T + POST_OUT <= STAND_OUT, f"closed, the handle stands {FRONT_Z0 + FRONT_T + POST_OUT:.0f} mm out; limit {STAND_OUT:.0f}")
    expect(HANDLE_W >= 200.0 and POST_OUT >= 25.0, "handle takes a gloved hand")
    tl, th = bbox_mm(tray)
    sl, sh = bbox_mm(sleeve_solids()[0].shape)
    expect(tl[2] >= SLEEVE_WALL, "closed, the tray clears the sleeve's back wall")
    inter = (tray & sleeve_solids()[0].shape).volume
    expect(inter < 1e-3, f"tray clears the sleeve ({inter:.3f} mm3 overlap)")
    return [Solid(front, "interior_dark"), Solid(tray + saddles[0] + saddles[1], "control_grey"),
            Solid(pane, "glass"), Solid(handle, "control_interface")]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    dec_dia, dec_len = entry("decoy")["footprint_mm"]
    body = sleeve_solids()
    drawer = drawer_solids(dec_len, dec_dia)
    expect_in_front(body + drawer, SLUG)
    lo = [min(bbox_mm(p.shape)[0][i] for p in body + drawer) for i in range(3)]
    hi = [max(bbox_mm(p.shape)[1][i] for p in body + drawer) for i in range(3)]
    expect(abs(lo[2]) < 0.01, f"back on Z=0, not {lo[2]:.2f}")
    expect(hi[2] <= STAND_OUT + 0.01, f"stands {hi[2]:.1f} mm out; limit {STAND_OUT:.0f}")
    expect(hi[0] - lo[0] <= 800.01 and hi[1] - lo[1] <= 600.0, f"footprint {hi[0] - lo[0]:.0f} x {hi[1] - lo[1]:.0f} within the unit")
    rb = export_solids_glb(body, d / f"{SLUG}_body.glb", "LoaderDrawerBody")
    rd = export_solids_glb(drawer, d / f"{SLUG}_drawer.glb", "LoaderDrawerFront")
    tris = rb["triangles"] + rd["triangles"]
    expect(tris <= TRIANGLE_BUDGET[GROUP], f"{tris} triangles; kit budget {TRIANGLE_BUDGET[GROUP]}")
    s = Scene("LoaderDrawer", script="res://src/interact/loader_drawer.gd")
    s.set(".", slide_axis=(0.0, 0.0, 1.0), travel_m=TRAVEL_MM / 1000, body=NodePath("Slide"),
          noise_profile=quiet_noise(s, 0.3, 1.5))
    s.node("Body", instance=rb["glb"])
    s.node("Slide")
    s.node("Drawer", parent="Slide", instance=rd["glb"])
    # Quarter turn about Y: the decoy's -Z (nose) goes to +X and its +X (label) to +Z, so the label faces the window.
    s.node("Cradle", parent="Slide", script="res://src/interact/decoy_cradle.gd",
           props={"transform": Xform.frame((0, 0, 1), (0, 1, 0), (-1, 0, 0), (0, AXIS_Y / 1000, CRADLE_Z / 1000))})
    fz0, fz1 = TRAY_Z0, hi[2]
    grab_box(s, "Slide", ((W + 2 * GRAB_MARGIN) / 1000, (H + 2 * GRAB_MARGIN) / 1000, (fz1 - fz0 + GRAB_MARGIN) / 1000),
             (0, 0, (fz0 + fz1) / 2000))
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {
        "kind": "control",
        "summary": "Decoy loader drawer: a heavy slide-out drawer in a rail sleeve, viewing window in its front, a "
                   "half-pipe cradle (a DecoyCradle, decoy lying across) and an orange pull handle. LoaderDrawer: "
                   "drag to slide, 0 closed to 1 open, 0.65 m of travel along +Z.",
        "tags": ["drawer", "loader", "decoy", "cradle", "slide", "window", "countermeasure"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": "LoaderDrawer", "values": "0 closed .. 1 open (slides `Slide` 0.65 m along +Z)",
                      "signal": "value_changed",
                      "wiring": "`body` is the Slide node; `Cradle` (DecoyCradle) rides on it: wire LaunchTube.drawer to the "
                                "root and LaunchTube.cradle to Slide/Cradle"},
        "cradle_node": "Slide/Cradle",
        "footprint_mm": [W, H],
        "stand_out_mm": round(hi[2], 1),
        "open_stand_out_mm": round(hi[2] + TRAVEL_MM, 1),
        "travel_mm": TRAVEL_MM,
        "mount": "back on Z=0, centred; the drawer opens along +Z; the decoy lies across it, label toward the window",
        "uses": USES,
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
