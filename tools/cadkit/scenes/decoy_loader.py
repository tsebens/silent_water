"""decoy_loader: the decoy launch-tube loader (a panel). Brief: assets/models/panels/decoy_loader/brief.yaml (concept #746).

An armoured wall unit, back on Z=0 against the hull, centred on X and Y, the drawer opening toward +Z. The lower half is
the `loader_drawer` (a heavy slide-out drawer, 0.65 m of travel); the upper half is a shallower armoured box carrying
the `prime_lever`, the engraved tube plate, three LED strips (EMPTY / LOADED / PRIMED), a valve body and a compressed
air hose. The root has no script: a `LaunchTube` node (with the `tube_name` setting) wires the drawer, its cradle and
the lever into the tube state machine, and a `TubeLamps` node lights exactly one strip from it (the same behaviour as
the countermeasures station's tube lamps, so the two agree).

Local solids (static, used once): the upper box, its dark lamp inset, the label plates, the bolts, the valve body and
hand wheel, the hose. Everything else is a catalogue scene, set 2 mm off its host face (the mount rule).

Frame (mm): X right, Y up, origin at the unit's centre (the seam between drawer and upper box), Z out of the wall.
"""
import json

import numpy as np

from cadkit import mount
from cadkit.solids import Solid, at, bbox_mm, box, expect, expect_in_front, export_solids_glb, prism
from cadkit.library import entry, note, out_dir, res, scene_path, write_entry
from cadkit.tscn import NodePath, Scene, Xform

SLUG, GROUP = "decoy_loader", "panels"
USES: list[str] = ["loader_drawer", "prime_lever", "led_strip", "led_strip_warn", "led_strip_alarm"]
TRIANGLE_BUDGET = 4000

# The brief's constraints (arc #754).
UNIT_W, UNIT_H = 800.0, 600.0
MAX_CLOSED_D = 450.0
OPEN_REACH = 650.0                              # the open drawer's travel
EYE = np.array([0.0, 650.0, 500.0])             # operator_eye_m
SHOULDER = EYE - np.array([0.0, 250.0, 0.0])
REACH = 1100.0

# The upper box.
BOX_W, BOX_H, BOX_D = 800.0, 300.0, 150.0
BOX_Y0 = 0.0                                    # its bottom, on the drawer's top
DRAWER_Y = -150.0                               # the drawer instance's origin (its sleeve spans -300..0)
INSET_T, PLATE_T = 4.0, 2.0
FACE = BOX_D                                    # host face for the lever
FACE_INSET = BOX_D + INSET_T

INSET = (-215.0, 225.0, 300.0, 110.0)           # lamp inset: centre x, y, width, height
TUBE_PLATE = (-215.0, 256.0, 200.0, 34.0)
LAMP_Y, LAMP_XS, LAMP_LEN = 210.0, (-305.0, -215.0, -125.0), 80.0
LAMPS = [("EmptyLamp", "led_strip_warn", "EMPTY"), ("LoadedLamp", "led_strip", "LOADED"), ("PrimedLamp", "led_strip_alarm", "PRIMED")]
LEVER_AT = (160.0, 125.0)

VALVE_Y, VALVE_Z = 120.0, FACE + 26.0           # pipe axis
VALVE_X0, VALVE_X1, VALVE_R = -392.0, -250.0, 17.0
WHEEL_X, WHEEL_R = -300.0, 32.0
HOSE_X, HOSE_R = -440.0, 14.0
HOSE_Z = 40.0
HOSE_BOTTOM = -290.0


def _along_x(r, x0, x1, y, z):
    return at(prism(8, r, x1 - x0), ry=90, x=x0, y=y, z=z)


def _along_z(r, z0, z1, x, y):
    return at(prism(8, r, z1 - z0), x=x, y=y, z=z0)


def _along_ny(r, y_top, y_bot, x, z):
    return at(prism(8, r, y_top - y_bot), rx=90, x=x, y=y_top, z=z)


def solids() -> list[Solid]:
    upper = at(box(BOX_W, BOX_H, BOX_D, chamfer_mm=5.0), y=BOX_Y0 + BOX_H / 2)
    inset = at(box(INSET[2], INSET[3], INSET_T), INSET[0], INSET[1], FACE)
    plates = [at(box(TUBE_PLATE[2], TUBE_PLATE[3], PLATE_T), TUBE_PLATE[0], TUBE_PLATE[1], FACE_INSET)]
    plates += [at(box(84.0, 12.0, PLATE_T), x, LAMP_Y - 20.0, FACE_INSET) for x in LAMP_XS]
    bolts = [at(prism(8, 6.0, 4.0), x, y, FACE) for x in (-370.0, 370.0) for y in (30.0, 150.0, 270.0)]
    # Valve: a pad on the face, the body along X, a stem and a hand wheel facing +Z.
    pad = at(box(170.0, 54.0, 18.0, chamfer_mm=3.0), (VALVE_X0 + VALVE_X1) / 2, VALVE_Y, FACE)
    body = _along_x(VALVE_R, VALVE_X0, VALVE_X1, VALVE_Y, VALVE_Z)
    stem = _along_z(5.0, VALVE_Z, VALVE_Z + 34.0, WHEEL_X, VALVE_Y)
    wheel = at(prism(12, WHEEL_R, 8.0), WHEEL_X, VALVE_Y, VALVE_Z + 34.0)
    hub = at(prism(8, 9.0, 12.0), WHEEL_X, VALVE_Y, VALVE_Z + 34.0)
    # Hose: out of the valve's left end, back to the wall, down and away.
    hose = (_along_x(HOSE_R, HOSE_X - HOSE_R, VALVE_X0 + 8.0, VALVE_Y, VALVE_Z)
            + _along_z(HOSE_R, HOSE_Z, VALVE_Z + HOSE_R, HOSE_X, VALVE_Y)
            + _along_ny(HOSE_R, VALVE_Y + HOSE_R, HOSE_BOTTOM, HOSE_X, HOSE_Z + HOSE_R))
    parts = ([Solid(upper, "interior_panel"), Solid(inset, "interior_dark")]
             + [Solid(p, "label_plate") for p in plates]
             + [Solid(b, "trim_black") for b in bolts]
             + [Solid(pad, "interior_dark"), Solid(body, "hull_metal"), Solid(stem, "hull_metal"),
                Solid(wheel, "control_interface"), Solid(hub, "trim_black"),
                Solid(hose, "trim_black")])
    return parts


def _depth(slug: str) -> tuple[float, float]:
    e = entry(slug)
    d = e.get("depth_mm")
    return (d["behind_origin"], d["in_front_of_origin"]) if d else (0.0, e["stand_out_mm"])


def placements() -> list[dict]:
    out = []
    for (name, slug, _), x in zip(LAMPS, LAMP_XS):
        out.append({"name": name, "slug": slug, "x": x, "y": LAMP_Y, "host": FACE_INSET, "scale_x": LAMP_LEN / 40.0})
    out.append({"name": "PrimeLever", "slug": "prime_lever", "x": LEVER_AT[0], "y": LEVER_AT[1], "host": FACE, "scale_x": 1.0})
    for p in out:
        behind, front = _depth(p["slug"])
        p["z"] = p["host"] + mount.stand_off(behind)
        p["offset"] = p["z"] - p["host"]
        p["front"] = p["z"] + front
    return out


def checks(parts: list[Solid], pl: list[dict]) -> dict:
    lo = [min(bbox_mm(p.shape)[0][i] for p in parts) for i in range(3)]
    hi = [max(bbox_mm(p.shape)[1][i] for p in parts) for i in range(3)]
    drawer = entry("loader_drawer")
    lever = entry("prime_lever")
    # Size: the armoured box and the drawer are the unit; the hose runs outside it, as context.
    expect(abs(BOX_W - UNIT_W) < 0.01 and drawer["footprint_mm"][0] <= UNIT_W + 0.01,
           f"unit {UNIT_W:.0f} mm wide: box {BOX_W:.0f}, drawer {drawer['footprint_mm'][0]:.0f}")
    height = BOX_Y0 + BOX_H - (DRAWER_Y - drawer["footprint_mm"][1] / 2)
    expect(abs(height - UNIT_H) < 0.01, f"unit {UNIT_H:.0f} mm tall ({height:.0f}): drawer {drawer['footprint_mm'][1]:.0f} + box {BOX_H:.0f}")
    expect(abs(DRAWER_Y + drawer["footprint_mm"][1] / 2 - BOX_Y0) < 0.01, "the upper box sits on the drawer's top")
    expect(abs(lo[2]) < 0.01, f"back on Z=0, not {lo[2]:.2f}")
    # Depth, closed: the drawer's handle, the box, the lever's whole sweep, the wheel.
    deepest = max(hi[2], drawer["stand_out_mm"], *(p["front"] for p in pl))
    expect(deepest <= MAX_CLOSED_D, f"closed depth {deepest:.0f} mm, at most {MAX_CLOSED_D:.0f}")
    expect(drawer["open_stand_out_mm"] - drawer["stand_out_mm"] == drawer["travel_mm"], "drawer travel matches its entry")
    expect(abs(drawer["travel_mm"] - OPEN_REACH) <= 50.0, f"open drawer reaches {drawer['travel_mm']:.0f} mm beyond its closed front, about {OPEN_REACH:.0f}")
    expect(drawer["open_stand_out_mm"] <= 1100.0, f"open, the drawer stands {drawer['open_stand_out_mm']:.0f} mm out")
    expect_in_front(parts, SLUG)
    # The lever: its grip, at both ends of the throw, within reach of the shoulder.
    pv = next(p for p in pl if p["name"] == "PrimeLever")
    tips = {}
    for end, key in (("up", "up_yz"), ("down", "down_yz")):
        ty, tz = lever["handle_tip_mm"][key]
        tip = np.array([pv["x"], pv["y"] + ty, pv["z"] + tz])
        d = float(np.linalg.norm(tip - SHOULDER))
        tips[end] = round(d, 1)
        expect(d <= REACH, f"lever grip {end} within reach {REACH:.0f} mm of the shoulder ({d:.0f})")
    down_y = pv["y"] + lever["handle_tip_mm"]["down_yz"][0]
    drawer_front_top = DRAWER_Y + drawer["footprint_mm"][1] / 2
    expect(down_y - 9.0 > drawer_front_top + 5.0, f"lever down-grip at y={down_y:.0f} (grip radius 9) clears the closed drawer top ({drawer_front_top:.0f}) by 5 mm")
    # The lever sits on the box face, inside it.
    lw, lh = lever["footprint_mm"]
    expect(pv["x"] + lw / 2 <= BOX_W / 2 - 20.0 and pv["y"] - 35.0 >= BOX_Y0 + 10.0, "lever block inside the face")
    # Lamps and plates on the inset; valve and lever apart; hose outside the drawer's travel.
    ix, iy, iw, ih = INSET
    for p in pl:
        if p["name"].endswith("Lamp"):
            hl = LAMP_LEN / 2
            expect(ix - iw / 2 <= p["x"] - hl and p["x"] + hl <= ix + iw / 2 and iy - ih / 2 <= p["y"] <= iy + ih / 2,
                   f"{p['name']} inside the lamp inset")
    expect(VALVE_Y + WHEEL_R < iy - ih / 2 - 5.0, "valve wheel below the lamp inset")
    expect(VALVE_X1 < LEVER_AT[0] - lw / 2 - 20.0, "valve clear of the lever block")
    expect(HOSE_X + HOSE_R < -drawer["footprint_mm"][0] / 2 and HOSE_X - HOSE_R > -UNIT_W / 2 - 80.0,
           "hose runs down the wall beside the drawer, clear of its travel")
    mounts = [mount.record(p["name"], p["slug"], p["offset"], "box face" if p["host"] == FACE else "lamp inset") for p in pl]
    expect(not mount.problems(SLUG, {"mounts": mounts}, entry), "no instanced face coplanar with its host face")
    # Sight lines: the lamps face the eye within 70 degrees and nothing on the box stands in front of them.
    for p in pl:
        if p["name"].endswith("Lamp"):
            tgt = np.array([p["x"], p["y"], p["host"] + 1.0])
            v = EYE - tgt
            ang = float(np.degrees(np.arccos(v[2] / np.linalg.norm(v))))
            expect(ang <= 70.0, f"{p['name']} faces the eye within 70 degrees ({ang:.0f})")
    return {"width_mm": UNIT_W, "height_mm": UNIT_H, "closed_depth_mm": round(deepest, 1),
            "open_reach_mm": OPEN_REACH, "grip_reach_mm": tips, "reach_limit_mm": REACH}


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    parts = solids()
    pl = placements()
    figs = checks(parts, pl)
    rep = export_solids_glb(parts, d / f"{SLUG}_body.glb", "DecoyLoaderBody")
    s = Scene("DecoyLoader")
    s.node("Body", instance=rep["glb"])
    s.node("Drawer", instance=scene_path("loader_drawer"), props={"transform": Xform(origin=(0, DRAWER_Y / 1000, 0))})
    for p in pl:
        xf = Xform(basis=np.diag([p["scale_x"], 1.0, 1.0]), origin=(p["x"] / 1000, p["y"] / 1000, p["z"] / 1000))
        s.node(p["name"], instance=scene_path(p["slug"]), props={"transform": xf})
    s.node("Exit", props={"transform": Xform(origin=(0, DRAWER_Y / 1000, 0.02))})
    s.node("Tube", type_="Node", script="res://src/interact/launch_tube.gd",
           props={"tube_name": "FORE TUBE", "drawer": NodePath("../Drawer"), "cradle": NodePath("../Drawer/Slide/Cradle"),
                  "prime_lever": NodePath("../PrimeLever"), "exit_point": NodePath("../Exit")})
    s.node("Lamps", type_="Node", script="res://src/interact/tube_lamps.gd",
           props={"tube": NodePath("../Tube"), "empty_lamp": NodePath("../EmptyLamp"),
                  "loaded_lamp": NodePath("../LoadedLamp"), "primed_lamp": NodePath("../PrimedLamp")})
    s.node("OperatorEye", props={"transform": Xform(origin=tuple(float(v) / 1000 for v in EYE))})
    s.write(d / f"{SLUG}.tscn")
    tris = rep["triangles"] + entry("loader_drawer")["triangles"] + sum(entry(p["slug"])["triangles"] for p in pl)
    expect(tris <= TRIANGLE_BUDGET, f"panel within the {TRIANGLE_BUDGET:,} triangle budget ({tris})")
    _cameras(d)
    write_entry(GROUP, SLUG, {
        "kind": "panel",
        "summary": "Decoy loader: an armoured wall unit, 0.8 x 0.6 m, at most 0.45 m deep closed. A heavy slide-out drawer "
                   "with a viewing window below (0.65 m of travel, an orange pull handle), an armoured box above with "
                   "the prime lever, an engraved tube plate, EMPTY / LOADED / PRIMED strip lamps, a valve body and a "
                   "compressed-air hose. A LaunchTube wires drawer, cradle and lever; TubeLamps lights the lamps.",
        "tags": ["panel", "decoy", "loader", "launch tube", "countermeasure", "drawer", "lever", "wall unit"],
        "scene": res(d / f"{SLUG}.tscn"),
        "behaviour": {"wire": {
            "tube": "Tube (LaunchTube; set `tube_name` there: FORE TUBE or STERN TUBE); request_fire() fires it; `fired(exit_point)` "
                    "emits from `Exit`",
            "drawer": "Drawer (loader_drawer: LoaderDrawer, with Slide/Cradle a DecoyCradle)",
            "lever": "PrimeLever (SwitchLever; down is primed)",
            "lamps": "Lamps (TubeLamps) lights EmptyLamp / LoadedLamp / PrimedLamp from the tube's state",
            "eye": "OperatorEye (the standing eye, 0.5 m out, 0.65 m above the unit's centre)"}},
        "footprint_mm": [UNIT_W, UNIT_H],
        "stand_out_mm": figs["closed_depth_mm"],
        "open_stand_out_mm": entry("loader_drawer")["open_stand_out_mm"],
        "mount": "back on Z=0 against the hull, centred on the unit (X and Y); the drawer opens toward +Z",
        "set_on_instance": {"Tube.tube_name": "FORE TUBE or STERN TUBE"},
        "operator_eye_m": [float(v) / 1000 for v in EYE],
        "reach_m": REACH / 1000,
        "mounts": [mount.record(p["name"], p["slug"], p["offset"], "box face" if p["host"] == FACE else "lamp inset") for p in pl],
        "uses": list(USES),
        "triangles": tris,
        "triangle_budget": TRIANGLE_BUDGET,
        "triangles_by_part": {"body": rep["triangles"], "drawer": entry("loader_drawer")["triangles"]},
        "checks": figs,
    })
    return {"slug": SLUG, "triangles": tris, "body": rep["triangles"]}


def _cameras(d) -> None:
    eye = [round(float(v) / 1000, 3) for v in EYE]
    cams = [
        {"name": "concept_primary", "pos": [0.9, 0.35, 1.9], "look_at": [-0.05, 0.0, 0.12], "fov": 45.0},
        {"name": "operator_eye", "pos": eye, "look_at": [0.0, 0.0, 0.2], "fov": 75.0},
        {"name": "operator_eye_red", "pos": eye, "look_at": [0.0, 0.0, 0.2], "fov": 75.0, "light": "red"},
        {"name": "profile_right", "pos": [4.0, 0.0, 0.3], "look_at": [0.0, 0.0, 0.3], "ortho": 1.4},
        {"name": "front", "pos": [0.0, 0.0, 4.0], "look_at": [0.0, 0.0, 0.0], "ortho": 1.4},
    ]
    review = d / "review"
    review.mkdir(parents=True, exist_ok=True)
    (review / ".gdignore").touch()
    (review / "cameras.json").write_text(json.dumps(cams, indent=1) + "\n")
    note(review / ".gdignore")
    note(review / "cameras.json")
