#!/usr/bin/env python3
"""Converts the Onshape sub assembly into a game-ready model.

    python3 tools/convert_sub.py [input.gltf] [output.glb]

Defaults: assets/media/sub/Assembly 1.gltf -> assets/sub/sub_model.glb

What it does:
- Rotates Onshape's frame (Z up, bow toward +Y) into Godot's (Y up, bow
  toward -Z) and puts the origin on the main cabin floor, on the centreline.
- Gives every part a stable role name (Shell, Deck, FrontWindow, PilotSeat,
  ...) taken from its assembly and position, so game code can find it.
- Simplifies heavy CAD meshes to a sensible triangle budget.
- Keeps each part's colour as its material.
- Pivots each part on its own centre (the node carries its position).

Re-run after re-exporting from Onshape. Needs: numpy, trimesh, fast-simplification.
"""
import base64
import json
import re
import sys

import fast_simplification
import numpy as np
import trimesh

SRC = sys.argv[1] if len(sys.argv) > 1 else "assets/media/sub/Assembly 1.gltf"
DST = sys.argv[2] if len(sys.argv) > 2 else "assets/sub/sub_model.glb"

# Onshape -> Godot: centreline x = 1.52, main cabin floor z = -4.02, and the
# origin a little aft of the dome seam (y = -0.1).
ORIGIN_ONSHAPE = np.array([1.52, -0.1, -4.02])
ROTATE = np.array([[1, 0, 0], [0, 0, 1], [0, -1, 0]], dtype=float)  # (x,y,z) -> (x, z, -y)

# Triangle budget per part; anything above is simplified down to it.
MAX_TRIS = {"FrontWindow": 16000, "Shell": 24000, "Deck": 20000, "PilotSeat": 6000}
DEFAULT_MAX_TRIS = 8000

COMPONENT_TYPES = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
TYPE_SIZES = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_accessor(g, buf, index):
    acc = g["accessors"][index]
    view = g["bufferViews"][acc["bufferView"]]
    dtype = COMPONENT_TYPES[acc["componentType"]]
    n = TYPE_SIZES[acc["type"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = view.get("byteStride")
    count = acc["count"]
    item = np.dtype(dtype).itemsize * n
    if stride and stride != item:
        raw = np.frombuffer(buf, dtype=np.uint8, count=stride * count, offset=start).reshape(count, stride)[:, :item]
        return np.frombuffer(raw.tobytes(), dtype=dtype).reshape(count, n)
    return np.frombuffer(buf, dtype=dtype, count=count * n, offset=start).reshape(count, n)


def node_matrix(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=float).reshape(4, 4).T
    m = np.eye(4)
    if any(k in node for k in ("translation", "rotation", "scale")):
        raise SystemExit("TRS node transforms are not handled: %s" % node.get("name"))
    return m


def role_for(assembly, part, center):
    """Stable role names from the assembly structure and position (Godot frame)."""
    x, y, z = center
    if part == "Part 1" and assembly.startswith("Pilot Station"):
        return "PilotSeat" if y > -0.2 and z > -1.6 else "PilotMapPedestal"
    if part == "Part 1" and assembly.startswith("Slider"):
        return "SonarSliderTrack"
    if part == "Part 1":
        return "MapTable"
    if assembly.startswith("Sonar Station") and part == "Valve Wheel":
        return "HydrophoneWheel"
    return re.sub(r"[^A-Za-z0-9]", "", part)


def material_for(g, prim):
    mat = g["materials"][prim["material"]] if "material" in prim else {}
    pbr = mat.get("pbrMetallicRoughness", {})
    color = pbr.get("baseColorFactor", [0.7, 0.7, 0.7, 1.0])
    return trimesh.visual.material.PBRMaterial(
        name=mat.get("name", "mat"), baseColorFactor=[int(c * 255) for c in color],
        metallicFactor=pbr.get("metallicFactor", 0.0), roughnessFactor=pbr.get("roughnessFactor", 0.8))


def main():
    g = json.load(open(SRC))
    uri = g["buffers"][0]["uri"]
    buf = base64.b64decode(uri.split(",", 1)[1]) if uri.startswith("data:") else open(uri, "rb").read()

    to_godot = np.eye(4)
    to_godot[:3, :3] = ROTATE
    to_godot[:3, 3] = -ROTATE @ ORIGIN_ONSHAPE

    parts = []

    def walk(index, parent_m, assembly):
        node = g["nodes"][index]
        m = parent_m @ node_matrix(node)
        name = node.get("name", "")
        if name.startswith("occurrence of "):
            pass
        elif "mesh" not in node and name and not name.startswith("Assembly 1"):
            assembly = name
        if "mesh" in node:
            part = name
            verts, faces, mats = [], [], []
            offset = 0
            for prim in g["meshes"][node["mesh"]]["primitives"]:
                pos = read_accessor(g, buf, prim["attributes"]["POSITION"]).astype(float)
                idx = read_accessor(g, buf, prim["indices"]).reshape(-1, 3).astype(np.int64)
                verts.append(pos)
                faces.append(idx + offset)
                mats.append(material_for(g, prim))
                offset += len(pos)
            v = np.vstack(verts)
            v = (np.c_[v, np.ones(len(v))] @ (to_godot @ m).T)[:, :3]
            parts.append((assembly, part, v, np.vstack(faces), mats[0]))
        for c in node.get("children", []):
            walk(c, m, assembly)

    for root in g["scenes"][g.get("scene", 0)]["nodes"]:
        walk(root, np.eye(4), "")

    scene = trimesh.Scene()
    used = {}
    total_in = total_out = 0
    for assembly, part, v, f, mat in parts:
        mesh = trimesh.Trimesh(vertices=v, faces=f, process=True)
        mesh.merge_vertices()
        role = role_for(assembly, part, mesh.bounds.mean(axis=0))
        budget = MAX_TRIS.get(role, DEFAULT_MAX_TRIS)
        total_in += len(mesh.faces)
        if len(mesh.faces) > budget:
            reduction = 1.0 - budget / len(mesh.faces)
            pv, pf = fast_simplification.simplify(mesh.vertices, mesh.faces, target_reduction=reduction)
            mesh = trimesh.Trimesh(vertices=pv, faces=pf, process=True)
        mesh.visual = trimesh.visual.TextureVisuals(material=mat)
        total_out += len(mesh.faces)
        n = used.get(role, 0)
        used[role] = n + 1
        node_name = role if n == 0 else "%s%d" % (role, n + 1)
        lo, hi = mesh.bounds
        # Pivot each part on its own centre so moving parts (wheels, hatch)
        # turn in place; the node carries the position.
        center = (lo + hi) / 2.0
        mesh.apply_translation(-center)
        place = np.eye(4)
        place[:3, 3] = center
        scene.add_geometry(mesh, node_name=node_name, geom_name=node_name, transform=place)
        print("%-20s %6d tris  x %5.2f..%5.2f  y %5.2f..%5.2f  z %5.2f..%5.2f" % (
            node_name, len(mesh.faces), lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
    scene.export(DST)
    print("triangles: %d -> %d   wrote %s" % (total_in, total_out, DST))


if __name__ == "__main__":
    main()
