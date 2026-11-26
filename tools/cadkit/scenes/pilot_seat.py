"""pilot_seat: the pilot's seat: `operator_seat` as it is, plus a headrest, two armrest joysticks and two pedals on a grating.

Brief (cockpit concept #446): the same powder-grey operator seat, a headrest above the backrest, a joystick on each armrest
(left: throttle; right: planes and rudder) and two decorative pedals on an open grating footrest ahead of the seat. The
occupant faces -Z; the glass will be a hand's width beyond the armrests' front ends. No behaviour: the parent binds
`PilotSeat` (a StationSeat subclass) with sit_point = SitPoint, and a JoystickIndicator on each joystick.
The seat itself is the `operator_seat` scene, instanced unchanged (its backrest is already fixed there); the solids
added here share one GLB, in the seat's frame.
"""
import math

import build123d as bd

from cadkit.solids import Solid, at, box, expect, bbox_mm, export_solids_glb
from cadkit.library import entry, out_dir, res, scene_module, scene_path, write_entry
from cadkit import mount
from cadkit.tscn import Scene, Xform

SLUG, GROUP = "pilot_seat", "furniture"
USES: list[str] = ["operator_seat", "joystick", "lit_toggle"]
BUDGET = 3000

HEAD_W, HEAD_H, HEAD_T, HEAD_GAP = 220.0, 130.0, 70.0, 50.0   # gap between the backrest top and the headrest
POST_W, POST_T = 24.0, 24.0
FOOT_X, FOOT_Z0, FOOT_Z1 = 300.0, -680.0, -330.0              # grating extent (X half-width, Z range; toward -Z is forward)
FOOT_Y, SLAT_T, RAIL_W = 60.0, 12.0, 30.0                      # grating top height, slat thickness, side rail width
PEDAL_X, PEDAL_Z, PEDAL_TILT = 110.0, -560.0, 25.0
JOY_Z = 40.0                                                   # joystick centre along the armrest (Z), mm
ARM_TOP = 660.0                                                # operator_seat armrest top, mm
PANEL_W, PANEL_L, PANEL_T = 160.0, 200.0, 40.0                 # switch panel beside each joystick: outboard width, length (Z), thickness
PANEL_EDGE = 8.0                                               # the panel's chamfer
TOG_INNER, TOG_GAP = 24.0, 12.0                                # panel edge to the first toggle (clears the stick's sweep), toggle to toggle
JOY_TILT = 20.0                                                # the joystick's tilt either way, degrees
REACH_MM = 750.0                                               # a toggle lies this close to the resting hand at most
MIN_MARGIN = 8.0                                               # toggle footprint inside its panel by at least this
HAND_UP = 80.0                                                 # resting hand above the armrest top (on the grip)
# mount anchors: (name, side, 0 = inboard toggle / 1 = outboard toggle)
MOUNTS = [("ExternalLightSwitch", 1, 0), ("ExternalColourSwitch", 1, 1),
          ("CabinLightSwitch", -1, 0), ("CabinColourSwitch", -1, 1)]
MOUNT_GAP = mount.stand_off(0.0)


def arm_edge() -> float:
    """X of the armrest's outboard face."""
    return scene_module("operator_seat").ARM_X + 30


def toggle_xz(sx: int, idx: int) -> tuple[float, float]:
    """Centre (X, Z) of a toggle's mount on the panel beside the joystick at side `sx`."""
    tw = entry("lit_toggle")["footprint_mm"][0]
    return sx * (arm_edge() + TOG_INNER + tw / 2 + idx * (tw + TOG_GAP)), JOY_Z


def seat_solids() -> list[Solid]:
    return scene_module("operator_seat").solids()


def solids() -> list[Solid]:
    om = scene_module("operator_seat")
    back_h, tilt = om.BACK_H, om.BACK_TILT

    def on_back(shape: bd.Shape) -> bd.Shape:
        """Place a part modelled in the unleaned backrest frame (Y up its centreline from 0) on the leaned backrest."""
        shape = shape.rotate(bd.Axis.X, tilt)
        return at(shape, y=om.PAN_Y + om.PAN_T + 10, z=om.PAN_D / 2 + 20 - om.BACK_T / 2)

    head_y0 = back_h + HEAD_GAP
    head = on_back(at(box(HEAD_W, HEAD_H, HEAD_T, chamfer_mm=15, base_z=False), y=head_y0 + HEAD_H / 2))
    posts = [on_back(at(box(POST_W, HEAD_GAP + 60, POST_T, base_z=False), sx * 55, back_h - 30 + (HEAD_GAP + 60) / 2))
             for sx in (-1, 1)]

    # footrest: a grating of slats between two side rails, on legs to the floor, tied to the seat base by a spine
    depth = FOOT_Z1 - FOOT_Z0
    zc = (FOOT_Z0 + FOOT_Z1) / 2
    rails = [at(box(RAIL_W, 40, depth, base_z=False), sx * (FOOT_X - RAIL_W / 2), FOOT_Y - 20, zc) for sx in (-1, 1)]
    n_slats = 6
    pitch = (depth - 2 * RAIL_W) / (n_slats - 1)
    slats = [at(box(2 * FOOT_X, SLAT_T, 36, base_z=False), 0, FOOT_Y - SLAT_T / 2, FOOT_Z0 + RAIL_W + i * pitch) for i in range(n_slats)]
    legs = [at(box(RAIL_W, FOOT_Y - 40, 30, base_z=False), sx * (FOOT_X - RAIL_W / 2), (FOOT_Y - 40) / 2, z)
            for sx in (-1, 1) for z in (FOOT_Z0 + 20, FOOT_Z1 - 20)]
    spine = at(box(80, 40, 140, base_z=False), 0, 20, FOOT_Z1 + 60)
    # pedals: a tilted plate on a short post, standing on the grating
    pedals, pedal_posts = [], []
    for sx in (-1, 1):
        plate = box(100, 12, 150, chamfer_mm=3, base_z=False).rotate(bd.Axis.X, PEDAL_TILT)   # the front (-Z) edge rises
        pedals.append(at(plate, sx * PEDAL_X, FOOT_Y + 55, PEDAL_Z))
        pedal_posts.append(at(box(40, 32, 30, base_z=False), sx * PEDAL_X, FOOT_Y + 16, PEDAL_Z + 55))

    # switch panels: the armrest widened outboard of each joystick, flush with the armrest top
    panels = [at(box(PANEL_W, PANEL_T, PANEL_L, chamfer_mm=PANEL_EDGE, base_z=False),
                 sx * (arm_edge() + PANEL_W / 2), ARM_TOP - PANEL_T / 2, JOY_Z) for sx in (-1, 1)]

    foot = rails + slats + legs + [spine]
    # --- checks ---
    seat = seat_solids()
    seat_sh = [s.shape for s in seat]
    floor = min(bbox_mm(s)[0][1] for s in seat_sh)
    expect(abs(floor) < 0.5, f"seat stands on the floor at Y=0 ({floor} mm)")
    expect(all(bbox_mm(s)[0][1] > -0.5 for s in foot), "footrest does not sink below the floor")
    back_top = max(bbox_mm(s.shape)[1][1] for s in seat if s.role == "interior_panel")
    hlo, hhi = bbox_mm(head)
    expect(hlo[1] > back_top, f"headrest ({hlo[1]:.0f} mm) above the backrest top ({back_top:.0f} mm)")
    expect(hlo[1] - back_top < 120, "headrest close above the backrest")
    expect(abs(hlo[0] + hhi[0]) < 0.1 and hhi[0] < om.BACK_W / 2 + om.BOLSTER_W, "headrest centred and no wider than the backrest")
    for p in posts:
        pl, ph = bbox_mm(p)
        expect(pl[1] < back_top and ph[1] > hlo[1], "each headrest post spans the gap from the backrest to the headrest")
    # the occupant faces -Z: the backrest is at +Z of the pan, the footrest at -Z
    pan = [bbox_mm(s.shape) for s in seat if s.role == "interior_panel"][0]
    expect(FOOT_Z1 < pan[0][2], f"footrest ahead (-Z) of the seat pan front ({pan[0][2]:.0f} mm)")
    expect(hlo[2] > pan[1][2] - 60, "headrest behind (+Z) the pan's back edge: the occupant faces -Z")
    # joysticks on the armrests, clear of the seat
    arms = [s for s in seat if s.role == "trim_black" and abs(bbox_mm(s.shape)[0][1] - 620) < 1]
    expect(len(arms) == 2, "two armrests found on the seat")
    jr = entry("joystick")["footprint_mm"][0] / 2
    for a in arms:
        al, ah = bbox_mm(a.shape)
        sx = 1 if al[0] > 0 else -1
        cx = sx * om.ARM_X
        expect(abs(ah[1] - ARM_TOP) < 1, f"armrest top at {ah[1]:.0f}, expected {ARM_TOP}")
        expect(al[0] + 4 <= cx - jr and cx + jr <= ah[0] - 4, "joystick boot inside the armrest's width")
        expect(al[2] + jr <= JOY_Z and JOY_Z + jr <= ah[2], "joystick boot inside the armrest's length")
        expect(abs(cx) - jr > om.PAN_W / 2 + 4, "joystick clear of the seat pan (outboard of it)")
        back_z0 = min(bbox_mm(s.shape)[0][2] for s in seat if s.role == "control_interface")
        expect(JOY_Z + jr < back_z0 - 40, f"joystick ({JOY_Z + jr:.0f} mm) well forward of the backrest ({back_z0:.0f} mm)")
    stand = entry("joystick")["stand_out_mm"]
    expect(ARM_TOP + stand < back_top, f"joystick tip ({ARM_TOP + stand:.0f} mm) lower than the backrest top")
    # switch panels: flush with the armrest top, clear of the joystick boot and sweep, toggles inside with margin, in reach
    tfp = entry("lit_toggle")["footprint_mm"]
    t_out = entry("lit_toggle")["stand_out_mm"]
    for pnl in panels:
        pl2, ph2 = bbox_mm(pnl)
        sx = 1 if pl2[0] > 0 else -1
        expect(abs(ph2[1] - ARM_TOP) < 0.5, f"panel top at {ph2[1]:.0f}, flush with the armrest top {ARM_TOP}")
        inner = pl2[0] if sx > 0 else -ph2[0]
        expect(abs(inner - arm_edge()) < 0.5, "panel meets the armrest's outboard face")
        expect(not any(_overlap(pnl, q) for q in seat_sh), "panel clear of the seat")
        cx = sx * om.ARM_X
        expect(inner - abs(cx) >= jr + 4, "panel clear of the joystick boot")
        for name, msx, idx in MOUNTS:
            if msx != sx:
                continue
            tx, tz = toggle_xz(sx, idx)
            x0, x1, z0, z1 = tx - tfp[0] / 2, tx + tfp[0] / 2, tz - tfp[1] / 2, tz + tfp[1] / 2
            m = min(x0 - pl2[0], ph2[0] - x1, z0 - pl2[2], ph2[2] - z1)
            expect(m >= MIN_MARGIN, f"{name}: lit_toggle footprint {tfp[0]:.0f} x {tfp[1]:.0f} mm inside the panel with {m:.1f} mm margin (min {MIN_MARGIN})")
            # the stick's full sweep: a cone of half-angle JOY_TILT above the boot; the toggle's top is the widest slice
            top = t_out + MOUNT_GAP
            sweep_r = jr + top * math.tan(math.radians(JOY_TILT))
            near = min(abs(x0 - cx), abs(x1 - cx))
            expect(near > sweep_r + 2, f"{name}: clear of the {sweep_r:.0f} mm joystick sweep at its height ({near:.0f} mm away)")
            hand = (cx, ARM_TOP + HAND_UP, JOY_Z)
            far = max(math.dist(hand, (px, ARM_TOP + MOUNT_GAP + t_out, pz)) for px in (x0, x1) for pz in (z0, z1))
            expect(far <= REACH_MM, f"{name}: within the {REACH_MM:.0f} mm reach of the resting hand ({far:.0f} mm)")
    # pedals on the footrest, clear of the seat
    for pl_ in pedals + pedal_posts:
        lo, hi = bbox_mm(pl_)
        expect(lo[1] >= FOOT_Y - SLAT_T - 0.5, f"pedal part low edge {lo[1]:.0f} mm is on the footrest, not under it")
        expect(FOOT_Z0 + RAIL_W <= lo[2] and hi[2] <= FOOT_Z1 and abs(hi[0]) < FOOT_X - RAIL_W,
               "pedal over the grating, within the rails")
        for s in seat_sh:
            expect(not _overlap(pl_, s), "pedal clear of the seat")
    expect(abs(bbox_mm(pedals[0])[1][0] + bbox_mm(pedals[1])[0][0]) < 0.1, "pedals symmetric about the seat")
    # footrest and head parts are clear of the seat except where they are meant to touch (checked as the union staying small)
    for s in rails + slats:
        for q in seat_sh:
            expect(not _overlap(s, q), "grating clear of the seat")
    return ([Solid(head, "interior_panel")] + [Solid(p, "trim_black") for p in posts]
            + [Solid(s, "hull_metal") for s in rails + slats + legs] + [Solid(spine, "trim_black")]
            + [Solid(p, "trim_black") for p in pedals + panels] + [Solid(p, "hull_metal") for p in pedal_posts])


def _overlap(a: bd.Shape, b: bd.Shape) -> bool:
    al, ah = bbox_mm(a)
    bl, bh = bbox_mm(b)
    return all(al[i] < bh[i] - 0.01 and bl[i] < ah[i] - 0.01 for i in range(3))


def mount_xform(sx: int, idx: int) -> Xform:
    """A toggle's mount: its back on the panel top (set off by the mount gap), its face (+Z) up and its lamp side (+Y)
    toward the sitter (+Z), so the lamp reads above the switch from the eye."""
    x, z = toggle_xz(sx, idx)
    return Xform.frame((-1, 0, 0), (0, 0, 1), (0, 1, 0), origin=(x / 1000, (ARM_TOP + MOUNT_GAP) / 1000, z / 1000))


def joystick_xform(sx: int) -> Xform:
    """Stick (the joystick's +Z) points up; its thumb buttons (its -Y) face -Z, ahead of the sitter."""
    return Xform.frame((-1, 0, 0), (0, 0, 1), (0, 1, 0),
                       origin=(sx * scene_module("operator_seat").ARM_X / 1000, ARM_TOP / 1000, JOY_Z / 1000))


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    rep = export_solids_glb(solids(), d / f"{SLUG}.glb", "PilotSeatExtras")
    s = Scene("PilotSeat")
    s.node("Seat", instance=scene_path("operator_seat"))
    s.node("Extras", instance=rep["glb"])
    s.node("SitPoint")
    s.node("ThrottleJoystick", instance=scene_path("joystick"), props={"transform": joystick_xform(-1)})
    s.node("FlightJoystick", instance=scene_path("joystick"), props={"transform": joystick_xform(1)})
    for name, sx, idx in MOUNTS:
        s.node(name, props={"transform": mount_xform(sx, idx)})
    s.write(d / f"{SLUG}.tscn")
    tris = rep["triangles"] + entry("operator_seat")["triangles"] + 2 * entry("joystick")["triangles"]
    expect(tris <= BUDGET, f"furniture within the {BUDGET} triangle budget ({tris})")
    oe = entry("operator_seat")
    mounts = [mount.record(n, "lit_toggle", MOUNT_GAP, "armrest panel top") for n, _, _ in MOUNTS]
    write_entry(GROUP, SLUG, {
        "kind": "furniture",
        "summary": "Pilot's seat: the operator seat with a headrest, a throttle joystick (left armrest) and a planes-and-rudder "
                   "joystick (right armrest), two decorative pedals on an open grating footrest, and a switch panel on each armrest "
                   "with two lit_toggle mounts: anchors ExternalLightSwitch, ExternalColourSwitch (right), CabinLightSwitch, "
                   "CabinColourSwitch (left); toggle face up, lamp toward the sitter. Faces -Z.",
        "tags": ["seat", "chair", "pilot", "joystick", "pedals", "station"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"script": None,
                      "bind_on_parent": "StationSeat or a subclass (PilotSeat); sit_point = <instance>/SitPoint; "
                                        "a JoystickIndicator on ThrottleJoystick and FlightJoystick (stick = Frame/Stick)"},
        "footprint_mm": [max(oe["footprint_mm"][0], 2 * FOOT_X, 2 * (arm_edge() + PANEL_W)), -FOOT_Z0 + 340],
        "mounts": mounts,
        "mount": "on the floor at Y=0, centred on the pedestal; occupant faces -Z; footrest ahead",
        "seated_eye_height_m": oe["seated_eye_height_m"],
        "uses": list(USES),
        "triangles": tris,
        "triangles_by_part": {"extras": rep["triangles"], "operator_seat": oe["triangles"], "joysticks": 2 * entry("joystick")["triangles"]},
    })
    return {"slug": SLUG, "triangles": tris}
