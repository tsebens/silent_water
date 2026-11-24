"""Grey-box blockout of the sub interior, built in Blender from layout.json (written by plan.py).

    uv run --project tools/asset_pipeline python assets/models/vehicles/sub_interior/plan.py   # refresh layout.json
    blender -b --factory-startup -P assets/models/vehicles/sub_interior/blockout.py -- [out_dir] [camera_id ...]

Renders every camera in layout.json (or the ones named) with the Workbench engine into out_dir
(default: renders/blockout/ next to this file) and saves blockout.blend there. Everything is plain boxes,
cylinders and the lofted hull: shape and placement only, no detail. Colours are by category so stations
read at a glance; the dome glass and the map table's hologram are wireframes so they don't block the view.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

HERE = Path(__file__).resolve().parent
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = Path(ARGS[0]) if ARGS else HERE / "renders" / "blockout"
ONLY = set(ARGS[1:])

COL = {
    "shell": (0.46, 0.48, 0.50), "floor": (0.36, 0.37, 0.38), "cockpit_floor": (0.22, 0.30, 0.34),
    "bulkhead": (0.55, 0.42, 0.30), "panel": (0.86, 0.50, 0.18), "desk": (0.86, 0.50, 0.18),
    "screen": (0.10, 0.12, 0.13), "table": (0.30, 0.62, 0.42), "cowl": (0.55, 0.57, 0.60),
    "seat": (0.30, 0.50, 0.72), "chair": (0.30, 0.50, 0.72), "well": (0.30, 0.10, 0.10),
    "hatch": (0.90, 0.78, 0.25), "ladder": (0.70, 0.70, 0.76), "storage": (0.42, 0.43, 0.48),
    "lever": (0.90, 0.80, 0.20), "crew": (0.62, 0.66, 0.72), "glass": (0.55, 0.85, 0.95),
    "holo": (0.25, 0.95, 0.90), "ring": (0.35, 0.36, 0.38), "tower": (0.46, 0.48, 0.50),
    "seafloor": (0.16, 0.20, 0.18),
}


def material(name: str) -> bpy.types.Material:
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        c = COL[name]
        m.diffuse_color = (*c, 1.0)
        m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*c, 1.0)
    return m


def to_blender(x: float, y: float, z: float) -> Vector:
    """Sub-local (x starboard, y up, z aft) to Blender (x starboard, y forward, z up)."""
    return Vector((x, -z, y))


def link(obj: bpy.types.Object, group: str) -> bpy.types.Object:
    obj["group"] = group
    bpy.context.scene.collection.objects.link(obj)
    return obj


def mesh_object(name: str, bm: bmesh.types.BMesh, mat: str, group: str) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(material(mat))
    return link(bpy.data.objects.new(name, me), group)


def box(name: str, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, mat: str, group: str = "items") -> bpy.types.Object:
    bm = bmesh.new()
    lo, hi = to_blender(min(x0, x1), min(y0, y1), max(z0, z1)), to_blender(max(x0, x1), max(y0, y1), min(z0, z1))
    bmesh.ops.create_cube(bm, size=1.0)
    centre = (lo + hi) / 2
    size = Vector((abs(hi.x - lo.x), abs(hi.y - lo.y), abs(hi.z - lo.z)))
    for v in bm.verts:
        v.co = Vector((v.co.x * size.x, v.co.y * size.y, v.co.z * size.z)) + centre
    return mesh_object(name, bm, mat, group)


def cylinder(name: str, x: float, y0: float, y1: float, z: float, r: float, mat: str, group: str = "items",
             segments: int = 24) -> bpy.types.Object:
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=r, radius2=r, depth=abs(y1 - y0))
    c = to_blender(x, (y0 + y1) / 2, z)
    for v in bm.verts:
        v.co += c
    return mesh_object(name, bm, mat, group)


def wireframe(obj: bpy.types.Object, thickness: float = 0.012) -> None:
    mod = obj.modifiers.new("wire", "WIREFRAME")
    mod.thickness = thickness
    mod.use_replace = True


# ---- hull -------------------------------------------------------------------------------------

def build_hull(layout: dict, cockpit_end: float) -> None:
    """Loft the inner hull surface from its rings, split into groups so cutaways can hide parts:
    shell_low / shell_high (split above head height) and port / starboard halves; the dome (cockpit) apart."""
    rings = layout["hull"]["rings"]
    split_y = layout["main_deck_y"] + 2.0
    n = len(rings[0]["points"])
    faces: dict[str, list] = {}
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for k in range(n):
            k2 = (k + 1) % n
            quad = [(a["points"][k], a["z"]), (a["points"][k2], a["z"]), (b["points"][k2], b["z"]), (b["points"][k], b["z"])]
            cx = sum(p[0][0] for p in quad) / 4
            cy = sum(p[0][1] for p in quad) / 4
            cz = sum(p[1] for p in quad) / 4
            side = "port" if cx < 0 else "stbd"
            if cz < cockpit_end:
                key = f"dome_{'port' if cx < 0 else 'stbd'}"
            else:
                key = f"shell_{'high' if cy > split_y else 'low'}_{side}"
            faces.setdefault(key, []).append(quad)
    for key, quads in faces.items():
        bm = bmesh.new()
        cache: dict = {}
        for quad in quads:
            vs = []
            for (x, y), z in quad:
                kk = (round(x, 4), round(y, 4), round(z, 4))
                if kk not in cache:
                    cache[kk] = bm.verts.new(to_blender(x, y, z))
                vs.append(cache[kk])
            try:
                bm.faces.new(vs)
            except ValueError:
                pass
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        is_dome = key.startswith("dome")
        obj = mesh_object(key, bm, "glass" if is_dome else "shell", key.rsplit("_", 1)[0] if not is_dome else "dome")
        obj["groups"] = [key.split("_")[0], key.rsplit("_", 1)[0], f"{key.split('_')[0]}_{key.rsplit('_', 1)[1]}"]
        if is_dome:
            # a sparse wireframe: keep every 3rd ring and 6th meridian so the glass reads without blocking the view
            wireframe(obj, 0.008)


def build_floors(layout: dict) -> None:
    for f in layout["floors"]:
        y = f["y"]
        outline = f["outline"]
        bm = bmesh.new()
        top = [bm.verts.new(to_blender(-hw, y, z)) for z, hw in outline] + \
              [bm.verts.new(to_blender(hw, y, z)) for z, hw in reversed(outline)]
        face = bm.faces.new(top)
        ext = bmesh.ops.extrude_face_region(bm, geom=[face])
        for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
            v.co.z -= 0.06
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh_object(f"floor_{f['id']}", bm, "cockpit_floor" if f["id"] == "cockpit" else "floor", "floor")


def build_bulkhead(layout: dict, comp: dict) -> None:
    z0, z1 = comp["z"]
    zc = (z0 + z1) / 2
    ring = min(layout["hull"]["rings"], key=lambda r: abs(r["z"] - zc))
    deck = layout["main_deck_y"]
    # the plate fills the section above the deck; the hatch is left as an opening by building the plate
    # as the region outside the door rectangle: left, right and over the door
    # the plate is the hull's cross-section above the deck, extruded fore-and-aft, with the hatch cut through
    pts = [(x, y) for x, y in ring["points"] if y >= deck]
    pts.sort(key=lambda p: math.atan2(p[1] - deck, p[0]))  # from starboard deck edge over the top to port
    bm = bmesh.new()
    half = (z1 - z0) / 2
    verts = [bm.verts.new(to_blender(x, y, zc - half)) for x, y in pts]
    face = bm.faces.new(verts)
    ext = bmesh.ops.extrude_face_region(bm, geom=[face])
    for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.y -= (z1 - z0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    plate = mesh_object("bulkhead", bm, "bulkhead", "bulkhead")
    door_w, door_h = 0.75, 1.7
    door = box("bulkhead_door_cutter", -door_w / 2, door_w / 2, deck - 0.1, deck + door_h, z0 - 0.1, z1 + 0.1, "bulkhead", "cutter")
    mod = plate.modifiers.new("door", "BOOLEAN")
    mod.operation, mod.object, mod.solver = "DIFFERENCE", door, "EXACT"
    bpy.context.view_layer.objects.active = plate
    bpy.ops.object.modifier_apply(modifier="door")
    bpy.data.objects.remove(door)


# ---- crew figures -------------------------------------------------------------------------------

def standing(name: str, x: float, floor: float, z: float) -> None:
    cylinder(f"crew_{name}_body", x, floor, floor + 1.5, z, 0.2, "crew", "crew", 12)
    cylinder(f"crew_{name}_head", x, floor + 1.52, floor + 1.75, z, 0.11, "crew", "crew", 12)


def seated(name: str, x: float, floor: float, z: float) -> None:
    cylinder(f"crew_{name}_body", x, floor + 0.45, floor + 1.1, z, 0.19, "crew", "crew", 12)
    cylinder(f"crew_{name}_head", x, floor + 1.12, floor + 1.32, z, 0.1, "crew", "crew", 12)


# ---- items ---------------------------------------------------------------------------------------

def build_item(it: dict, layout: dict) -> None:
    kind = it["kind"]
    x0, x1, z0, z1 = it["floor_box"]
    fy = it["floor_y"]
    iid = it["id"]
    inboard = -1 if x0 + x1 > 0 else 1  # direction from the wall toward the aisle
    if kind == "panel":
        box(iid, x0, x1, fy, fy + 1.7, z0, z1, "panel")
        face = x0 if inboard < 0 else x1
        standing(iid, face + inboard * 0.35, fy, (z0 + z1) / 2)
    elif kind in ("desk", "table"):
        top_y = fy + it.get("mount_height_m", 0.75)
        tx0, tx1, _, _ = it.get("top_box", it["floor_box"])
        mat = "table" if kind == "table" else "desk"
        # plinth under the top, the top itself, then the instruments on the wall above it
        box(f"{iid}_plinth", x0 + 0.1 * inboard if False else x0, x1, fy, top_y - 0.05, z0 + 0.15, z1 - 0.15, mat)
        box(f"{iid}_top", tx0, tx1, top_y - 0.05, top_y, z0, z1, mat)
        wall = tx0 if inboard > 0 else tx1
        if kind == "desk" and it.get("faces") == "aft":
            # the screen stands at the desk's forward end facing aft, raked, as in the sonar console reference;
            # its operator sits behind the desk facing forward
            box(f"{iid}_screen", tx0 + 0.05, tx1 - 0.05, top_y, top_y + 0.5, z0, z0 + 0.12, "screen")
        elif kind == "desk":
            box(f"{iid}_screen", wall, wall + inboard * 0.18, top_y, top_y + 0.55, z0 + 0.15, z1 - 0.15, "screen")
        else:
            box(f"{iid}_cowl", wall, wall + inboard * 0.28, top_y + 0.75, top_y + 1.25, z0, z1, "cowl")
            holo = box(f"{iid}_hologram", tx0, tx1, top_y, top_y + it.get("hologram_height_m", 0.7), z0, z1, "holo", "hologram")
            wireframe(holo, 0.01)
            # observers standing along the front edge either side of the operator
            edge = tx1 if inboard > 0 else tx0
            standing(f"{iid}_obs_fwd", edge + inboard * 0.75, fy, z0 + 0.3)
            standing(f"{iid}_obs_aft", edge + inboard * 0.75, fy, z1 - 0.3)
    elif kind == "chair":
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        box(f"{iid}_seat", x0 + 0.05, x1 - 0.05, fy + 0.4, fy + 0.5, z0 + 0.05, z1 - 0.05, "chair")
        cylinder(f"{iid}_post", cx, fy, fy + 0.4, cz, 0.04, "chair")
        if it.get("faces") == "forward":
            box(f"{iid}_back", x0 + 0.05, x1 - 0.05, fy + 0.5, fy + 1.0, z1 - 0.06, z1, "chair")
        else:  # backrest on the side away from the desk
            bx = x1 - 0.06 if inboard > 0 else x0
            box(f"{iid}_back", bx, bx + 0.06, fy + 0.5, fy + 1.0, z0 + 0.05, z1 - 0.05, "chair")
        seated(iid, cx, fy, cz)
    elif kind == "seat":
        cz = (z0 + z1) / 2
        box(f"{iid}_seat", x0, x1, fy + 0.4, fy + 0.52, z0, z1, "seat")
        box(f"{iid}_back", x0, x1, fy + 0.52, fy + 1.3, z1 - 0.12, z1, "seat")
        box(f"{iid}_rail_port", x0 - 0.12, x0, fy + 0.6, fy + 0.68, z0 - 0.45, z1 - 0.2, "panel")
        box(f"{iid}_rail_stbd", x1, x1 + 0.12, fy + 0.6, fy + 0.68, z0 - 0.45, z1 - 0.2, "panel")
        mini = cylinder(f"{iid}_mini_hologram", 0.0, fy + 0.62, fy + 0.82, z0 - 0.5, 0.1, "holo", "hologram")
        wireframe(mini, 0.006)
        seated(iid, (x0 + x1) / 2, fy, cz + 0.05)
    elif kind == "well":
        box(iid, x0, x1, fy - 0.01, fy + 0.02, z0, z1, "well")
        box(f"{iid}_pump", x0, x0 + 0.3, fy, fy + 0.6, z1 - 0.3, z1, "panel")
    elif kind == "floor_hatch":
        cx, cz, r = (x0 + x1) / 2, (z0 + z1) / 2, (x1 - x0) / 2
        cylinder(f"{iid}_rim", cx, fy, fy + 0.04, cz, r, "hatch")
        cylinder(f"{iid}_lid", cx, fy + 0.04, fy + 0.07, cz, r - 0.08, "ring")
        chamber = cylinder(f"{iid}_chamber", cx, fy - 1.0, fy - 0.02, cz, r - 0.05, "hatch", "below_deck")
        wireframe(chamber, 0.008)
    elif kind == "ladder":
        top = max(p[1] for r in layout["hull"]["rings"] for p in r["points"])
        for dz in (z0 + 0.05, z1 - 0.05):
            box(f"{iid}_rail_{dz:.2f}", x0 + 0.1, x0 + 0.15, fy, top, dz - 0.025, dz + 0.025, "ladder")
        for k in range(7):
            yk = fy + 0.3 * (k + 1)
            box(f"{iid}_rung_{k}", x0 + 0.1, x0 + 0.15, yk, yk + 0.03, z0 + 0.05, z1 - 0.05, "ladder")
    elif kind == "storage":
        box(iid, x0, x1, fy, fy + 1.9, z0, z1, "storage")
    elif kind == "release_lever":
        box(iid, x0, x1, fy + 0.2, fy + 1.0, z0, z1, "lever")


def build_tower(layout: dict, ladder: dict) -> None:
    top = max(p[1] for r in layout["hull"]["rings"] for p in r["points"])
    z = ladder["z"]
    cylinder("tower", 0.0, top + 0.1, top + 1.0, z, 0.6, "tower", "tower", 32)


# ---- cameras and rendering ---------------------------------------------------------------------

def setup_scene() -> None:
    scn = bpy.context.scene
    scn.render.engine = "BLENDER_WORKBENCH"
    scn.render.resolution_x, scn.render.resolution_y = 1600, 900
    sh = scn.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_cavity = True
    sh.cavity_type = "BOTH"
    sh.show_shadows = True
    sh.shadow_intensity = 0.35
    sh.show_object_outline = True
    sh.object_outline_color = (0.08, 0.08, 0.09)
    scn.display.render_aa = "8"
    world = bpy.data.worlds.new("w")
    world.color = (0.02, 0.07, 0.09)
    scn.world = world
    scn.view_settings.view_transform = "Standard"


def groups_of(obj: bpy.types.Object) -> set[str]:
    g = {obj.get("group", "")}
    g.update(obj.get("groups", []) or [])
    name = obj.name
    if name.startswith("shell_"):
        g.update({"shell", f"shell_{name.split('_')[-1]}".replace("stbd", "stbd"),
                  "shell_port" if name.endswith("port") else "shell_stbd"})
    if name.startswith("dome_"):
        g.update({"dome", "dome_port" if name.endswith("port") else "dome_stbd"})
    return g


def render_camera(cam_spec: dict, out: Path) -> Path:
    scn = bpy.context.scene
    cam_data = bpy.data.cameras.new(cam_spec["id"])
    cam = bpy.data.objects.new(cam_spec["id"], cam_data)
    scn.collection.objects.link(cam)
    pos, look = to_blender(*cam_spec["pos"]), to_blender(*cam_spec["look"])
    cam.location = pos
    d = look - pos
    if abs(d.normalized().z) > 0.99:
        # straight down: bow (Blender +Y) to the left of the frame, starboard at the top
        cam.rotation_euler = (0.0, 0.0, -math.pi / 2)
    else:
        cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if "ortho" in cam_spec:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = cam_spec["ortho"]
    else:
        cam_data.lens = cam_spec.get("lens_mm", 18)
    cam_data.clip_start = 0.02
    scn.camera = cam
    hide = set(cam_spec.get("hide", []))
    for obj in scn.objects:
        if obj.type == "MESH":
            obj.hide_render = bool(groups_of(obj) & hide)
    path = out / f"blockout_{cam_spec['id']}.png"
    scn.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    return path


def main() -> None:
    layout = json.loads((HERE / "layout.json").read_text(encoding="utf-8"))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup_scene()
    comps = {c["id"]: c for c in layout["compartments"]}
    build_hull(layout, comps["cockpit"]["z"][1])
    build_floors(layout)
    if "bulkhead" in comps:
        build_bulkhead(layout, comps["bulkhead"])
    for it in layout["items"]:
        build_item(it, layout)
    ladder = next((i for i in layout["items"] if i["kind"] == "ladder"), None)
    if ladder:
        build_tower(layout, ladder)
    # a flat sea floor 2 m under the keel, for the dome views
    keel = min(p[1] for r in layout["hull"]["rings"] for p in r["points"])
    box("seafloor", -30.0, 30.0, keel - 2.05, keel - 2.0, -40.0, 40.0, "seafloor", "seafloor")
    # the dome's rim ring
    cockpit_end = comps["cockpit"]["z"][1]
    ring = min(layout["hull"]["rings"], key=lambda r: abs(r["z"] - cockpit_end))
    bm = bmesh.new()
    pts = [bm.verts.new(to_blender(x, y, cockpit_end)) for x, y in ring["points"]]
    for k in range(len(pts)):
        bm.edges.new((pts[k], pts[(k + 1) % len(pts)]))
    rim = mesh_object("dome_rim", bm, "ring", "dome_rim")
    skin = rim.modifiers.new("skin", "SKIN")
    for v in rim.data.skin_vertices[0].data:
        v.radius = (0.06, 0.06)
    OUT.mkdir(parents=True, exist_ok=True)
    written = []
    for cam_spec in layout["cameras"]:
        if ONLY and cam_spec["id"] not in ONLY:
            continue
        written.append(str(render_camera(cam_spec, OUT)))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "blockout.blend"))
    print("BLOCKOUT", json.dumps(written))


main()
