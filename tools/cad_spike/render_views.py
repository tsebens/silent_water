"""Headless Blender: render a GLB from fixed views for an AI critique loop (Workbench, flat shading, CPU, ~1 s/view).
blender -b --factory-startup -P render_views.py -- <in.glb> <out_dir> [size_px]
Views: front (+Z), left, right, top, iso (3/4 from above-front-right), back. Also a contact sheet.
"""
import math, os, sys
import bpy
from mathutils import Vector

src, out = sys.argv[sys.argv.index("--") + 1:][:2]
size = int((sys.argv[sys.argv.index("--") + 1:] + ["512"])[2])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
lo = Vector([min(p[i] for p in pts) for i in range(3)]); hi = Vector([max(p[i] for p in pts) for i in range(3)])
centre, radius = (lo + hi) / 2, max((hi - lo)) * 0.75
for o in meshes:
    for p in o.data.polygons: p.use_smooth = False
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"; sc.display.shading.color_type = "MATERIAL"
sc.display.shading.show_cavity = True; sc.display.shading.show_object_outline = True
sc.display.shading.show_shadows = True
sc.render.resolution_x = sc.render.resolution_y = size
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("w"); sc.world.color = (0.18, 0.18, 0.2)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = radius * 2.2
# Blender frame after glTF import: front is -Y, up is +Z.
views = {"front": (0, -1, 0), "left": (-1, 0, 0), "right": (1, 0, 0), "top": (0, 0, 1), "back": (0, 1, 0),
         "iso": (1, -1, 0.8)}
for name, d in views.items():
    d = Vector(d).normalized()
    cam.location = centre + d * radius * 4
    up = Vector((0, -1, 0)) if name == "top" else Vector((0, 0, 1))
    cam.rotation_euler = d.to_track_quat("Z", "Y").to_euler() if name != "top" else Vector((0, 0, 0)).to_track_quat("Z","Y").to_euler()
    if name == "top":
        cam.rotation_euler = (0, 0, 0)
    sc.render.filepath = os.path.join(out, f"{name}.png")
    bpy.ops.render.render(write_still=True)
# contact sheet
import numpy as np
imgs = {n: bpy.data.images.load(os.path.join(out, f"{n}.png")) for n in views}
def arr(im):
    a = np.array(im.pixels[:]).reshape(im.size[1], im.size[0], 4); return a[::-1]
row1 = np.concatenate([arr(imgs[n]) for n in ("iso", "front", "top")], axis=1)
row2 = np.concatenate([arr(imgs[n]) for n in ("left", "right", "back")], axis=1)
sheet = np.concatenate([row1, row2], axis=0)[::-1]
im = bpy.data.images.new("sheet", sheet.shape[1], sheet.shape[0]); im.pixels = sheet.ravel().tolist()
im.filepath_raw = os.path.join(out, "sheet.png"); im.file_format = "PNG"; im.save()
print("RENDERED", list(views), "+ sheet.png")
