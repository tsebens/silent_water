"""Convert an Onshape glTF export of a kit part into a game-ready GLB (run inside Blender 4.5, headless).

    blender -b --factory-startup --python-exit-code 1 -P tools/kit/onshape_import_bpy.py -- \
        <in.gltf> <out.glb> <pivot_part> [--flip-up] [--dissolve-deg 2.0] \
        [--materials "Housing=fitting_dark_grey;Switch=fitting_grey;Indicator Light=led_cyan"] \
        [--palette assets/style_bible/palette.json]

Conventions (the kit spec):
- Origin at the mount point: the centre of the part's back face, where it sits on a panel.
- The part's front (the side its controls stand out from) faces Godot's +Z; up is +Y.
- The moving part (<pivot_part>, an Onshape part name such as "Switch") sits under a node named "Pivot" placed on its
  hinge with identity rotation, so a Lever rotates it about local X. Its Onshape part studio origin must be on the
  hinge axis; its assembly pose is reset to 0 (upright).
- One mesh per part, named after the part (spaces removed), flat shaded, coplanar CAD faces dissolved.

Model in Onshape with the part's back on the Top plane, its front standing out along Onshape +Z and its up along
Onshape +Y. Blender's glTF importer then gives front = -Y and up = +Z, which the exporter turns into Godot's +Z front
and +Y up, so no rotation is needed. --flip-up turns the part 180 degrees about its front axis if it comes out upside
down.
--materials replaces each named part's Onshape appearance with a palette role from assets/style_bible/palette.json
(sRGB in the file, converted to the linear factors glTF stores). Parts not named keep their Onshape colour.
Prints KIT_IMPORT_RESULT <json> on success.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector


def args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(prog="onshape_import_bpy.py")
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("pivot_part")
    ap.add_argument("--flip-up", action="store_true")
    ap.add_argument("--dissolve-deg", type=float, default=2.0)
    ap.add_argument("--materials", default="", help="'Part Name=role;Other Part=role'")
    ap.add_argument("--palette", default="assets/style_bible/palette.json")
    return ap.parse_args(sys.argv[sys.argv.index("--") + 1:])


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def palette_material(role: str, spec: dict) -> bpy.types.Material:
    """A material named after its palette role; the glTF exporter writes base colour, metallic, roughness and
    emission from the Principled BSDF."""
    m = bpy.data.materials.get(role) or bpy.data.materials.new(role)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    lin = [srgb_to_linear(c) for c in spec["albedo"]]
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Metallic"].default_value = spec.get("metallic", 0.0)
    bsdf.inputs["Roughness"].default_value = spec.get("roughness", 0.85)
    if "emission" in spec:
        bsdf.inputs["Emission Color"].default_value = (*[srgb_to_linear(c) for c in spec["emission"]], 1.0)
        bsdf.inputs["Emission Strength"].default_value = spec.get("emission_energy", 1.0)
    m.diffuse_color = (*lin, 1.0)
    return m


def tri_count(obj: bpy.types.Object) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def main() -> None:
    a = args()
    src, dst, pivot_part, flip, dissolve_deg = a.src, a.dst, a.pivot_part, a.flip_up, a.dissolve_deg
    palette = json.loads(Path(a.palette).read_text(encoding="utf-8"))["roles"]
    assign = dict(pair.split("=", 1) for pair in a.materials.split(";") if pair.strip())
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=src)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    moving = next(o for o in meshes if o.name == pivot_part)
    tris_in = {o.name: tri_count(o) for o in meshes}

    # Reset the moving part's assembly pose: keep the hinge location, drop the rotation (0 = upright).
    occ = moving.parent
    hinge_world = occ.matrix_world.translation.copy()
    occ.matrix_world = Matrix.Translation(hinge_world)
    bpy.context.view_layer.update()

    # The mount point: the centre of the back face of the fixed parts (the face away from the moving part's side).
    fixed = [o for o in meshes if o is not moving]
    pts = [o.matrix_world @ Vector(c) for o in fixed for c in o.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    mount = Vector(((lo.x + hi.x) / 2, hi.y, (lo.z + hi.z) / 2))  # front is -Y, so the back face is the +Y face

    # Blender frame after import: front = -Y, up = +Z, already the target (Godot +Z front, +Y up).
    rot = Matrix.Identity(4)
    if flip:
        rot = Matrix.Rotation(math.pi, 4, "Y")  # 180 degrees about the front axis (Blender Y)
    to_kit = rot @ Matrix.Translation(-mount)

    # Bake every mesh into the kit frame, unparented, then drop the Onshape occurrence empties.
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.data.transform(to_kit @ mw)
        o.matrix_world = Matrix.Identity(4)
    for o in [o for o in bpy.data.objects if o.type == "EMPTY"]:
        bpy.data.objects.remove(o)

    hinge = to_kit @ hinge_world
    pivot = bpy.data.objects.new("Pivot", None)
    bpy.context.scene.collection.objects.link(pivot)
    pivot.location = hinge
    moving.data.transform(Matrix.Translation(-hinge))
    moving.parent = pivot

    # CAD cleanup: weld the per-face vertex splits, dissolve coplanar faces, flat shade.
    for o in meshes:
        if o.name in assign:
            role = assign.pop(o.name)
            o.data.materials.clear()
            o.data.materials.append(palette_material(role, palette[role]))
    if assign:
        raise SystemExit(f"--materials names parts that are not in the export: {sorted(assign)}")
    for o in meshes:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
        bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(dissolve_deg), verts=bm.verts, edges=bm.edges)
        bmesh.ops.triangulate(bm, faces=bm.faces)
        bm.to_mesh(o.data)
        bm.free()
        for p in o.data.polygons:
            p.use_smooth = False
        o.name = o.name.replace(" ", "")
        o.data.name = o.name

    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_apply=True, export_yup=True)

    def bbox(objs: list[bpy.types.Object]) -> list[list[float]]:
        ps = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
        return [[round(min(getattr(p, k) for p in ps), 4) for k in "xyz"], [round(max(getattr(p, k) for p in ps), 4) for k in "xyz"]]

    bpy.context.view_layer.update()
    print("KIT_IMPORT_RESULT " + json.dumps({
        "out": dst,
        "triangles_in": tris_in,
        "triangles_out": {o.name: tri_count(o) for o in meshes},
        "hinge_blender": [round(v, 4) for v in hinge],
        "bbox_blender": bbox(meshes),
        "materials": {o.name: [m.name for m in o.data.materials] for o in meshes},
    }))


main()
