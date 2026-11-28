"""Greybox a facility from its plan's layout.json, in headless Blender, and render fixed cameras.

    blender -b --factory-startup --python-exit-code 1 -P tools/facility_plan/blockout.py -- \
        <layout.json> <out_dir> [camera ids]

Builds the ledge and the chasm, an exterior mass per structure, the tunnels, the rooms (floors, walls with door
openings, a marker per objective), the docking arm's struts and the sub at the collar for scale. Renders each camera
in CAMERAS with Workbench to <out_dir>/<id>.jpg and saves <out_dir>/blockout.blend. Groups let a camera hide parts:
exterior, interior, terrain, tunnels, sub.

Site frame (as in the plan): x along the ledge, z inland (the chasm at z < 0), y up. Blender: X = x, Y = z, Z = y.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
LAYOUT = Path(ARGS[0])
OUT = Path(ARGS[1])
ONLY = set(ARGS[2:])

COL = {
    "terrain": (0.20, 0.23, 0.22), "cliff": (0.13, 0.15, 0.15), "concrete": (0.55, 0.56, 0.55),
    "concrete_dark": (0.40, 0.41, 0.41), "floor": (0.30, 0.32, 0.34), "wall_work": (0.42, 0.52, 0.62),
    "wall_live": (0.66, 0.56, 0.44), "wall_keep": (0.66, 0.38, 0.34), "wall_corridor": (0.50, 0.51, 0.53),
    "objective": (0.95, 0.78, 0.20), "sub": (0.85, 0.48, 0.12), "strut": (0.36, 0.37, 0.38),
    "neon_amber": (1.0, 0.62, 0.20),
}
KEEP_ALIVE = {"life_support", "reactor_control", "reactor_hall", "switchgear", "refuge", "lockout", "dock_airlock",
              "workshop", "dive_locker", "spares", "maint_hall", "dock_passage"}
LIVING_LEVELS = {"L2"}

CAMERAS = [
    # id, position, target (site frame), lens mm, hidden groups
    {"id": "chasm_approach", "pos": (-4, -4, -48), "look": (22, 3, 10), "lens": 24, "hide": []},
    {"id": "edge_profile", "pos": (-55, 6, -14), "look": (20, 2, 8), "lens": 28, "hide": []},
    {"id": "overview", "pos": (-45, 55, -70), "look": (18, 0, 22), "lens": 30, "hide": []},
    {"id": "cutaway", "pos": (-38, 42, -40), "look": (8, 0, 12), "lens": 30, "hide": ["exterior", "tunnel_shell"]},
    {"id": "dock_from_below", "pos": (44, -16, -14), "look": (34, -2, -4), "lens": 22, "hide": []},
]


def mat(name: str) -> bpy.types.Material:
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        c = COL[name]
        m.diffuse_color = (*c, 1.0)
    return m


def B(x: float, y: float, z: float) -> Vector:
    return Vector((x, z, y))


def obj_from(name: str, bm: bmesh.types.BMesh, material: str, group: str) -> bpy.types.Object:
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat(material))
    o = bpy.data.objects.new(name, me)
    o["group"] = group
    bpy.context.scene.collection.objects.link(o)
    return o


def box(name: str, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, material: str, group: str) -> bpy.types.Object:
    bm = bmesh.new()
    vs = [bm.verts.new(B(x, y, z)) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
    idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    for f in idx:
        bm.faces.new([vs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return obj_from(name, bm, material, group)


def strut(name: str, a: tuple[float, float, float], b: tuple[float, float, float], w: float, material: str, group: str) -> None:
    """A square beam from a to b (site frame)."""
    va, vb = B(*a), B(*b)
    d = vb - va
    o = box(name, -w / 2, w / 2, -w / 2, w / 2, 0, d.length, material, group)  # along site z = Blender Y
    o.matrix_world = (Vector((0, 1, 0)).rotation_difference(d.normalized())).to_matrix().to_4x4()
    o.location = va


def gaps_on_edge(doors: list[dict], level: str, fixed: str, value: float, lo: float, hi: float) -> list[tuple[float, float]]:
    """Door openings on one wall: intervals along the wall."""
    out = []
    for d in doors:
        if d.get("level") not in (None, level) or d["kind"] == "hatch":
            continue
        x, z = d["at"]
        along, across = (x, z) if fixed == "z" else (z, x)
        if abs(across - value) <= 0.05 and lo - 0.05 <= along <= hi + 0.05:
            out.append((along - d["width"] / 2, along + d["width"] / 2))
    return sorted(out)


def walls(room: dict, level: str, floor_y: float, height: float, doors: list[dict], material: str) -> None:
    x0, x1, z0, z1 = room["rect"]
    t = 0.12
    mine = [d for d in doors if room["id"] in d["between"]]
    for fixed, value, lo, hi in (("z", z0, x0, x1), ("z", z1, x0, x1), ("x", x0, z0, z1), ("x", x1, z0, z1)):
        cuts = gaps_on_edge(mine, level, fixed, value, lo, hi)
        segs, cur = [], lo
        for a, b in cuts:
            if a > cur:
                segs.append((cur, a))
            cur = max(cur, b)
        if cur < hi:
            segs.append((cur, hi))
        inset = t if value in (z0, x0) else -t
        for k, (a, b) in enumerate(segs):
            if b - a < 0.05:
                continue
            name = f"{room['id']}_{level}_wall_{fixed}{value:g}_{k}"
            if fixed == "z":
                box(name, a, b, floor_y, floor_y + height, min(value, value + inset), max(value, value + inset), material, "interior")
            else:
                box(name, min(value, value + inset), max(value, value + inset), floor_y, floor_y + height, a, b, material, "interior")


FACES = {  # outward direction and the direction along the face, in the site frame (x, y, z)
    "south": ((0, 0, -1), (1, 0, 0)), "north": ((0, 0, 1), (1, 0, 0)),
    "west": ((-1, 0, 0), (0, 0, 1)), "east": ((1, 0, 0), (0, 0, 1)),
}


def extrude(name: str, origin: tuple[float, float, float], out: tuple[float, float, float], along: tuple[float, float, float],
            pts: list[tuple[float, float]], thick: float, material: str, group: str) -> None:
    """A slab whose outline is `pts` (u outward, v up) in the plane of `out` and up, `thick` wide along `along`."""
    bm = bmesh.new()
    rings = []
    for t in (-thick / 2, thick / 2):
        ring = []
        for u, v in pts:
            x = origin[0] + out[0] * u + along[0] * t
            y = origin[1] + v
            z = origin[2] + out[2] * u + along[2] * t
            ring.append(bm.verts.new(B(x, y, z)))
        rings.append(ring)
    n = len(pts)
    bm.faces.new(rings[0])
    bm.faces.new(rings[1][::-1])
    for k in range(n):
        bm.faces.new((rings[0][k], rings[0][(k + 1) % n], rings[1][(k + 1) % n], rings[1][k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj_from(name, bm, material, group)


def exterior(s: dict) -> None:
    ex = s.get("exterior", {})
    sid = s["id"]
    x0, x1, z0, z1 = s["rect"]
    w = ex.get("wall_m", 0.6)
    lo = min(l["floor_y"] for l in s["levels"]) - 0.6
    hi = max(l["floor_y"] + l["height"] for l in s["levels"]) + 0.8
    X0, X1, Z0, Z1 = x0 - w, x1 + w, z0 - w, z1 + w
    box(f"{sid}_mass", X0, X1, lo, hi, Z0, Z1, "concrete", "exterior")
    top = hi
    pl = ex.get("plinth")
    if pl:
        o = pl["out_m"]
        box(f"{sid}_plinth", X0 - o, X1 + o, -0.6, pl["height_m"], Z0 - o, Z1 + o, "concrete_dark", "exterior")
    tier = ex.get("tier")
    if tier:
        tz0 = Z0 - tier["chasm_m"]
        tx0, tx1 = X0 - tier["sides_m"], X1 + tier["sides_m"]
        box(f"{sid}_tier", tx0, tx1, hi, hi + tier["height_m"], tz0, Z1, "concrete", "exterior")
        top = hi + tier["height_m"]
        k, x = 0, tx0 + tier["rib_spacing_m"] / 2
        while x < tx1:  # ribs under the overhang toward the chasm
            box(f"{sid}_rib_{k}", x - 0.3, x + 0.3, hi - tier["rib_depth_m"], hi, tz0, Z0, "concrete_dark", "exterior")
            x += tier["rib_spacing_m"]
            k += 1
        st = ex.get("struts")
        if st:
            base_y = pl["height_m"] if pl else 0.0
            base_z = Z0 - (pl["out_m"] if pl else 0.0)
            k, x = 0, tx0 + st["spacing_m"] / 2
            while x < tx1:
                strut(f"{sid}_strut_{k}", (x, base_y, base_z), (x, hi - tier["rib_depth_m"], tz0 + 0.8), st["width_m"], "concrete", "exterior")
                x += st["spacing_m"]
                k += 1
    fins = ex.get("fins")
    if fins:
        for face in fins["faces"]:
            out, along = FACES[face]
            fixed = {"south": Z0, "north": Z1, "west": X0, "east": X1}[face]
            lo_a, hi_a = (X0, X1) if face in ("south", "north") else (Z0, Z1)
            h = (top if not tier or face != "north" else hi) - 0.0
            d = fins["depth_m"]
            k, a = 0, lo_a + fins["spacing_m"] / 2
            while a < hi_a:
                origin = (a, 0.0, fixed) if face in ("south", "north") else (fixed, 0.0, a)
                extrude(f"{sid}_fin_{face}_{k}", origin, out, along, [(0, -0.5), (d, -0.5), (d, h * 0.3), (0, h)],
                        fins["thick_m"], "concrete", "exterior")
                a += fins["spacing_m"]
                k += 1
    for key, mat_name in (("mast", "strut"), ("stack", "concrete_dark")):
        m = ex.get(key)
        if m:
            mx, mz = m["at"]
            hw = m["width_m"] / 2
            box(f"{sid}_{key}", mx - hw, mx + hw, top, top + m["height_m"], mz - hw, mz + hw, mat_name, "exterior")
    keel = ex.get("keel_m")
    if keel:
        for k, x in enumerate((X0 + 1.0, X1 - 1.0)):
            box(f"{sid}_keel_{k}", x - 0.6, x + 0.6, lo - keel, lo, Z0, Z1, "concrete_dark", "exterior")
    for n in ex.get("neon", []):  # where the amber strips go: thin lines on the edges
        if n == "tier_front" and tier:
            y = hi + tier["height_m"] * 0.55
            box(f"{sid}_neon_tier", X0 - tier["sides_m"], X1 + tier["sides_m"], y - 0.12, y + 0.12,
                Z0 - tier["chasm_m"] - 0.06, Z0 - tier["chasm_m"], "neon_amber", "exterior")
        elif n == "plinth_front" and pl:
            y = pl["height_m"] - 0.3
            box(f"{sid}_neon_plinth", X0 - pl["out_m"], X1 + pl["out_m"], y - 0.1, y + 0.1,
                Z0 - pl["out_m"] - 0.06, Z0 - pl["out_m"], "neon_amber", "exterior")
        elif n == "arm_edges":
            for k, x in enumerate((X0 - 0.06, X1)):
                box(f"{sid}_neon_edge_{k}", x, x + 0.06, hi - 0.6, hi - 0.4, Z0, Z1, "neon_amber", "exterior")


def build(layout: dict) -> None:
    structs = {s["id"]: s for s in layout["structures"]}
    # terrain: the ledge top at y = 0 for z >= 0, a cliff down into the chasm, a far wall across it
    box("ledge_top", -160, 200, -1.0, 0, 0, 220, "terrain", "terrain")
    box("cliff", -160, 200, -160, -1.0, 0, 220, "cliff", "terrain")  # its z = 0 face is the cliff, 160 m of it
    for i, (x, w) in enumerate(((-120, 30), (-60, 22), (90, 26), (150, 30))):  # a ragged lip: a few boulders on the edge
        box(f"lip_{i}", x, x + w, 0, 2.5, 0.0, 4.0, "cliff", "terrain")
    # exterior: per structure, from its `exterior` block (the shell is far bigger than the rooms)
    for s in layout["structures"]:
        exterior(s)
    # docking arm: it overhangs the chasm, so it gets struts back to the cliff face
    if "dock" in structs:
        x0, x1, z0, z1 = structs["dock"]["rect"]
        for x in (x0, x1):
            strut(f"dock_strut_{x:g}", (x, -12, -0.5), (x, -0.6, z0), 1.0, "strut", "exterior")
            strut(f"dock_brace_{x:g}", (x, -12, -0.5), (x, -0.6, (z0 + z1) / 2), 0.8, "strut", "exterior")
    # tunnels: a concrete tube on the seabed
    for t in layout["tunnels"]:
        w, h = t["width"] + 1.0, t["height"] + 1.0
        for k, (p, q) in enumerate(zip(t["path"], t["path"][1:])):
            (ax, az), (bx, bz) = p, q
            box(f"{t['id']}_{k}", min(ax, bx) - (w / 2 if ax == bx else 0), max(ax, bx) + (w / 2 if ax == bx else 0), -0.5, h - 0.5,
                min(az, bz) - (w / 2 if az == bz else 0), max(az, bz) + (w / 2 if az == bz else 0), "concrete_dark", "tunnel_shell")
    # rooms: a floor, walls with openings, objective markers
    for r in layout["rooms"]:
        x0, x1, z0, z1 = r["rect"]
        for lv, fy, ht in zip(r["levels"], r["floor_y"], r["height"]):
            box(f"{r['id']}_{lv}_floor", x0, x1, fy - 0.1, fy, z0, z1, "floor", "interior")
            material = ("wall_corridor" if r["corridor"] else "wall_keep" if r["id"] in KEEP_ALIVE
                        else "wall_live" if lv in LIVING_LEVELS else "wall_work")
            walls(r, lv, fy, ht, layout["doors"], material)
            if any(t.startswith("objective_") for t in r["tags"]):
                cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
                box(f"{r['id']}_{lv}_objective", cx - 0.4, cx + 0.4, fy, fy + 1.6, cz - 0.4, cz + 0.4, "objective", "interior")
    # the sub at the collar, its dorsal hatch to the arm's floor (a 10 m capsule with a tower)
    hatch = next((d for d in layout["doors"] if "sub" in d["between"]), None)
    if hatch:
        hx, hz = hatch["at"]
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=12, radius=1.0)
        bmesh.ops.scale(bm, vec=Vector((5.0, 1.9, 1.5)), verts=bm.verts)  # x along the ledge, 10 m long
        bmesh.ops.translate(bm, vec=B(hx, -0.9 - 1.2 - 1.5, hz), verts=bm.verts)
        obj_from("sub_hull", bm, "sub", "sub")
        box("sub_tower", hx - 0.6, hx + 0.6, -2.1, -0.6, hz - 0.6, hz + 0.6, "sub", "sub")


def setup() -> None:
    scn = bpy.context.scene
    scn.render.engine = "BLENDER_WORKBENCH"
    scn.render.resolution_x, scn.render.resolution_y = 1600, 900
    sh = scn.display.shading
    sh.light = "STUDIO"
    sh.color_type = "MATERIAL"
    sh.show_cavity = True
    sh.cavity_type = "BOTH"
    sh.show_shadows = True
    sh.shadow_intensity = 0.4
    sh.show_object_outline = True
    sh.object_outline_color = (0.05, 0.06, 0.07)
    scn.display.render_aa = "8"
    w = bpy.data.worlds.new("w")
    w.color = (0.02, 0.07, 0.09)
    scn.world = w
    scn.view_settings.view_transform = "Standard"
    scn.render.image_settings.file_format = "JPEG"
    scn.render.image_settings.quality = 88


def render(cam: dict) -> Path:
    scn = bpy.context.scene
    c = bpy.data.objects.get("cam") or bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    if c.name not in scn.collection.objects:
        scn.collection.objects.link(c)
    scn.camera = c
    c.data.clip_end = 2000
    pos, look = B(*cam["pos"]), B(*cam["look"])
    c.location = pos
    d = look - pos
    if abs(d.normalized().z) > 0.99:
        c.rotation_euler = (0.0, 0.0, 0.0)
    else:
        c.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if "ortho" in cam:
        c.data.type = "ORTHO"
        c.data.ortho_scale = cam["ortho"]
    else:
        c.data.type = "PERSP"
        c.data.lens = cam.get("lens", 28)
    hide = set(cam.get("hide", []))
    for o in scn.objects:
        if o.type == "MESH":
            o.hide_render = o.get("group", "") in hide
    out = OUT / f"{cam['id']}.jpg"
    scn.render.filepath = str(out)
    bpy.ops.render.render(write_still=True)
    return out


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup()
    build(json.loads(LAYOUT.read_text(encoding="utf-8")))
    OUT.mkdir(parents=True, exist_ok=True)
    done = [str(render(c)) for c in CAMERAS if not ONLY or c["id"] in ONLY]
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT / "blockout.blend"))
    print("BLOCKOUT " + json.dumps(done))


main()
