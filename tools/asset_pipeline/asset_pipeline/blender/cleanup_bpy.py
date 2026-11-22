"""Runs INSIDE Blender: `blender -b -P cleanup_bpy.py -- params.json`. Not importable outside Blender.

Params (JSON): source, output, slug, asset_class, recipe (ordered step names), triangle_budget, size_m,
palette_size, snap_grid_m, max_loose_parts. Prints one `ASSET_CLEANUP_RESULT {json}` line with the measured
result, which the Python side records in the manifest. Y-up GLB in, Y-up GLB out."""
import json
import math
import sys

import bmesh
import bpy
from mathutils import Vector

RESULT_PREFIX = "ASSET_CLEANUP_RESULT "
COLLISION_HULL_TRIS = 128


def log(msg):
    print(f"[cleanup] {msg}", flush=True)


def load_params():
    return json.load(open(sys.argv[sys.argv.index("--") + 1]))


def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def import_source(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    objs = mesh_objects()
    if not objs:
        raise RuntimeError("source GLB has no mesh")
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(objs) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = "body"
    obj.data.name = "body"
    return obj


def colour_attr(mesh):
    if mesh.color_attributes:
        return mesh.color_attributes.active_color or mesh.color_attributes[0]
    return None


def bbox(obj):
    pts = [v.co for v in obj.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def components(bm):
    """Face groups connected through shared vertices."""
    seen, groups = set(), []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack, grp = [f], []
        seen.add(f.index)
        while stack:
            cur = stack.pop()
            grp.append(cur)
            for v in cur.verts:
                for nf in v.link_faces:
                    if nf.index not in seen:
                        seen.add(nf.index)
                        stack.append(nf)
        groups.append(grp)
    return groups


def non_manifold_count(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    n = sum(1 for e in bm.edges if not e.is_manifold) + sum(1 for v in bm.verts if not v.is_manifold)
    bm.free()
    return n


def edit_bmesh(obj, fn):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    fn(bm)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def apply_modifier(obj, mod):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


# ---- recipe steps -------------------------------------------------------------------------------------------

def step_repair(obj, p):
    """Weld, drop degenerate faces, keep only the main parts, fill holes, fix winding."""
    size = max(obj.dimensions) or 1.0
    keep = max(1, int(p["max_loose_parts"]))

    def fix(bm):
        bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=size * 1e-5)
        bmesh.ops.dissolve_degenerate(bm, edges=bm.edges[:], dist=size * 1e-7)
        bm.faces.ensure_lookup_table()
        bm.faces.index_update()
        groups = sorted(components(bm), key=len, reverse=True)
        floor = max(1, int(0.01 * len(groups[0]))) if groups else 0
        doomed = [f for g in groups[keep:] for f in g]
        doomed += [f for g in groups[:keep] if len(g) < floor for f in g]
        if doomed:
            bmesh.ops.delete(bm, geom=doomed, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
        border = [e for e in bm.edges if e.is_boundary]
        if border:
            bmesh.ops.holes_fill(bm, edges=border, sides=0)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    edit_bmesh(obj, fix)
    return {"non_manifold": non_manifold_count(obj.data)}


def step_scale_and_pivot(obj, p):
    """Uniform scale so the largest dimension is size_m metres; pivot at the bottom centre."""
    lo, hi = bbox(obj)
    longest = max(hi - lo) or 1.0
    k = p["size_m"] / longest
    centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for v in obj.data.vertices:
        v.co = (v.co - centre) * k
    obj.data.update()
    return {"scale_factor": k}


def step_snap_to_grid(obj, p):
    g = p.get("snap_grid_m")
    if not g:
        return {}
    for v in obj.data.vertices:
        v.co = Vector(tuple(round(c / g) * g for c in v.co))
    obj.data.update()
    return {"snap_grid_m": g}


def step_decimate_to_budget(obj, p):
    budget = int(p["triangle_budget"])

    def tris(bm):
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
    edit_bmesh(obj, tris)
    ratio = 1.0
    for attempt in range(8):
        n = tri_count(obj)
        if n <= budget:
            break
        ratio = min(0.98, budget / n * 0.97)
        mod = obj.modifiers.new("decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        apply_modifier(obj, mod)
        log(f"decimate pass {attempt + 1}: ratio {ratio:.4f} -> {tri_count(obj)} tris")
    return {"triangles": tri_count(obj)}


def step_remesh_to_budget(obj, p):
    """Voxel remesh to even topology, then decimate the remainder to budget."""
    lo, hi = bbox(obj)
    obj.data.remesh_voxel_size = max(hi - lo) / 160.0
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.voxel_remesh()
    return step_decimate_to_budget(obj, p)


def step_flat_shade(obj, p):
    for poly in obj.data.polygons:
        poly.use_smooth = False
    obj.data.update()
    return {}


def kmeans(points, k, iters=12):
    """Deterministic k-means in RGB: farthest-point initialisation, no randomness."""
    uniq = list(dict.fromkeys(points))
    if len(uniq) <= k:
        return uniq
    cents = [uniq[0]]
    while len(cents) < k:
        cents.append(max(uniq, key=lambda c: min(sum((a - b) ** 2 for a, b in zip(c, q)) for q in cents)))
    for _ in range(iters):
        sums = [[0.0, 0.0, 0.0, 0] for _ in cents]
        for pt in points:
            i = min(range(len(cents)), key=lambda j: sum((a - b) ** 2 for a, b in zip(pt, cents[j])))
            s = sums[i]
            s[0] += pt[0]; s[1] += pt[1]; s[2] += pt[2]; s[3] += 1
        cents = [(s[0] / s[3], s[1] / s[3], s[2] / s[3]) if s[3] else c for s, c in zip(sums, cents)]
    return cents


def step_vertex_colour_palette(obj, p):
    """Replace the noisy (baked-lighting) vertex colours with one of at most palette_size flat colours per face."""
    mesh = obj.data
    k = max(1, int(p["palette_size"]))
    attr = colour_attr(mesh)
    face_col = []
    if attr is not None:
        data = attr.data
        per_corner = attr.domain == "CORNER"
        for poly in mesh.polygons:
            idxs = poly.loop_indices if per_corner else poly.vertices
            cs = [data[i].color for i in idxs]
            face_col.append(tuple(sum(c[j] for c in cs) / len(cs) for j in range(3)))
        mesh.color_attributes.remove(attr)
    else:
        face_col = [(0.5, 0.5, 0.5)] * len(mesh.polygons)
    cents = kmeans(face_col, k)
    # Round to 8 bits so the palette survives export unchanged.
    cents = [tuple(round(c * 255) / 255 for c in cc) for cc in cents]
    cents = list(dict.fromkeys(cents))
    new = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    for poly, fc in zip(mesh.polygons, face_col):
        best = min(cents, key=lambda c: sum((a - b) ** 2 for a, b in zip(fc, c)))
        for li in poly.loop_indices:
            new.data[li].color = (*best, 1.0)
    mesh.color_attributes.active_color = new
    mesh.color_attributes.render_color_index = list(mesh.color_attributes).index(new)
    return {"palette": [list(c) for c in cents]}


def step_collision_helper(obj, p):
    """A hull named for Godot's import suffix: `-convcolonly` becomes a convex shape, `-colonly` a trimesh."""
    terrain = p["asset_class"] == "terrain"
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    if not terrain:
        res = bmesh.ops.convex_hull(bm, input=bm.verts[:])
        bmesh.ops.delete(bm, geom=res["geom_interior"] + res["geom_unused"], context="VERTS")
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new("collision")
    bm.to_mesh(mesh)
    bm.free()
    suffix = "-colonly" if terrain else "-convcolonly"
    col = bpy.data.objects.new(f"{p['slug']}_collision{suffix}", mesh)
    bpy.context.scene.collection.objects.link(col)
    for attr in list(mesh.color_attributes):
        mesh.color_attributes.remove(attr)
    for _ in range(4):
        if terrain or len(mesh.polygons) <= COLLISION_HULL_TRIS:
            break
        mod = col.modifiers.new("decimate", "DECIMATE")
        mod.ratio = min(0.98, COLLISION_HULL_TRIS / len(mesh.polygons) * 0.9)
        apply_modifier(col, mod)
    return {"collision_object": col.name, "collision_triangles": tri_count(col)}


STEPS = {
    "repair": step_repair,
    "scale_and_pivot": step_scale_and_pivot,
    "snap_to_grid": step_snap_to_grid,
    "decimate_to_budget": step_decimate_to_budget,
    "remesh_to_budget": step_remesh_to_budget,
    "flat_shade": step_flat_shade,
    "vertex_colour_palette": step_vertex_colour_palette,
    "collision_helper": step_collision_helper,
}


def export(path, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    props = bpy.ops.export_scene.gltf.get_rna_type().properties
    kw = dict(filepath=path, export_format="GLB", export_yup=True, use_selection=True, export_apply=False,
              export_normals=True, export_materials="NONE" if "export_materials" in props else None)
    if "export_vertex_color" in props:
        kw["export_vertex_color"] = "ACTIVE"
    if "export_active_vertex_color_when_no_material" in props:
        kw["export_active_vertex_color_when_no_material"] = True
    if "export_all_vertex_colors" in props:
        kw["export_all_vertex_colors"] = True
    bpy.ops.export_scene.gltf(**{k: v for k, v in kw.items() if v is not None})


def measure(obj):
    mesh = obj.data
    lo, hi = bbox(obj)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    parts = len(components(bm))
    bm.free()
    attr = colour_attr(mesh)
    colours = set()
    if attr is not None:
        colours = {tuple(round(c, 4) for c in d.color[:3]) for d in attr.data}
    return {"triangles": tri_count(obj), "non_manifold": non_manifold_count(mesh), "loose_parts": parts,
            "vertex_colours": len(colours), "size_m": [hi.x - lo.x, hi.z - lo.z, hi.y - lo.y],
            "bbox_min": list(lo), "bbox_max": list(hi)}


def main():
    p = load_params()
    obj = import_source(p["source"])
    log(f"imported {len(obj.data.polygons)} faces")
    steps = {}
    for name in p["recipe"]:
        if name not in STEPS:
            raise RuntimeError(f"unknown cleanup step {name!r}")
        steps[name] = STEPS[name](obj, p) or {}
        if name in ("decimate_to_budget", "remesh_to_budget"):
            steps[name]["post_repair"] = step_repair(obj, p)  # collapses can pinch edges: re-weld, re-fill
        log(f"{name}: done")
    result = measure(obj)
    result["steps"] = steps
    result["blender_version"] = bpy.app.version_string
    objs = [obj] + [o for o in mesh_objects() if o is not obj]
    export(p["output"], objs)
    print(RESULT_PREFIX + json.dumps(result), flush=True)


try:
    main()
except Exception as e:  # make Blender exit non-zero so the caller sees the failure
    import traceback
    traceback.print_exc()
    sys.exit(1)
