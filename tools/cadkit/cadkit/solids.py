"""CAD solids to game meshes: build123d shapes, tessellated flat-shaded, coloured by palette role, written as GLB.

A GLB holds every static solid of a scene that shares one frame: one mesh, one surface per palette role
(docs/palette.md), each surface's material named by its role. On import into Godot the shared post-import script
swaps each for the role's shared material, so a palette change reaches every asset with no rebuild. A moving part gets
its own GLB, modelled in its own frame with its motion axis through the origin.

Low-poly by construction: round things are prisms with an explicit side count, and edges are chamfered, never
filleted. Every build script checks its solids against its brief with `expect` before anything is written.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import json
import struct

import build123d as bd
import numpy as np
from OCP.BRepTools import BRepTools

from cadkit import library

IMPORT_SCRIPT = "res://assets/import/vertex_color_import.gd"


def tessellate(shape: bd.Shape, tol_mm: float = 0.2, ang: float = 0.5) -> tuple[np.ndarray, np.ndarray]:
    BRepTools.Clean_s(shape.wrapped)  # drop any cached finer triangulation
    verts, tris = shape.tessellate(tolerance=tol_mm, angular_tolerance=ang)
    return np.array([[v.X, v.Y, v.Z] for v in verts]) / 1000.0, np.array(tris, dtype=np.int64)



def ngon_prism(sides: int, radius_mm: float, height_mm: float, rotation_deg: float = 0.0) -> bd.Part:
    """A polygonal 'cylinder' along +Z from z=0: explicit segment count, so the game mesh stays low-poly."""
    with bd.BuildPart() as b:
        with bd.BuildSketch():
            bd.RegularPolygon(radius_mm, sides, rotation=rotation_deg)
        bd.extrude(amount=height_mm)
    return b.part



@dataclass
class Solid:
    shape: bd.Shape          # mm, in the GLB's frame
    role: str                # a palette role: a file in assets/palette/roles/
    bind: object = None      # a cadkit.skeleton Rigid or Chain, for a scene with a skeleton


def srgb_to_linear(rgb: tuple[float, float, float]) -> tuple[float, ...]:
    """Palette values are sRGB (as a colour picker shows them); glTF colour factors are linear."""
    return tuple(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb)


def expect_in_front(solids: list["Solid"], what: str) -> None:
    """A panel part must not reach behind its mount face (Z=0): the panel it sits on has no hole for it."""
    for s in solids:
        z0 = s.shape.bounding_box().min.Z
        expect(z0 >= -0.01, f"{what}: a {s.role} solid reaches {z0:.1f} mm behind the mount face")


def surfaces(solids: list[Solid], tol_mm: float = 0.2, ang: float = 0.5) -> list[tuple[str, np.ndarray, np.ndarray]]:
    """One flat-shaded surface per role, in order of first use: (role, positions in metres (n, 3), face normals (n, 3)),
    three vertices per triangle."""
    known = library.roles()
    by_role: dict[str, list[np.ndarray]] = {}
    for s in solids:
        if s.role not in known:
            raise ValueError(f"role {s.role!r} is not a palette role: {sorted(known)}")
        v, t = tessellate(s.shape, tol_mm, ang)
        by_role.setdefault(s.role, []).append(v[t].reshape(-1, 3))
    out = []
    for role, chunks in by_role.items():
        pos = np.concatenate(chunks).astype(np.float32)
        tri = pos.reshape(-1, 3, 3)
        n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        out.append((role, pos, np.repeat(n, 3, axis=0).astype(np.float32)))
    return out


def skinned_surfaces(solids: list[Solid], skel, tol_mm: float = 0.2, ang: float = 0.5) -> list[tuple]:
    """`surfaces`, with each vertex's skin kept through the per-role merge:
    (role, positions, normals, joints (n, 4) uint16, weights (n, 4) float32). Every solid must be bound."""
    known = library.roles()
    by_role: dict[str, list] = {}
    for s in solids:
        if s.role not in known:
            raise ValueError(f"role {s.role!r} is not a palette role: {sorted(known)}")
        if s.bind is None:
            raise ValueError(f"a {s.role} solid has no bone binding, but the scene has a skeleton")
        v, t = tessellate(s.shape, tol_mm, ang)
        pos = v[t].reshape(-1, 3)
        j, w = skel.weights(s.bind, pos * 1000.0)
        by_role.setdefault(s.role, []).append((pos, j, w))
    out = []
    for role, chunks in by_role.items():
        pos = np.concatenate([c[0] for c in chunks]).astype(np.float32)
        tri = pos.reshape(-1, 3, 3)
        n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
        out.append((role, pos, np.repeat(n, 3, axis=0).astype(np.float32),
                    np.concatenate([c[1] for c in chunks]), np.concatenate([c[2] for c in chunks])))
    return out


def write_glb(path: Path, node_name: str, surfs: list[tuple], skel=None) -> None:
    """A GLB with one node and one mesh holding a primitive per surface, its material named by the role.
    With a skeleton, surfaces are `skinned_surfaces` tuples and the file also holds joint nodes in their hierarchy and a
    skin the mesh node points at (joints, inverse bind matrices; JOINTS_0 and WEIGHTS_0 on each primitive)."""
    blob, views, accessors, prims, materials = bytearray(), [], [], [], []

    def add(data: bytes, target: int | None) -> int:
        while len(blob) % 4:
            blob.append(0)
        views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)})
        if target is not None:
            views[-1]["target"] = target
        blob.extend(data)
        return len(views) - 1

    for surf in surfs:
        role, pos, nrm = surf[:3]
        count = len(pos)
        big = count > 65535
        idx = np.arange(count, dtype=np.uint32 if big else np.uint16)
        a_pos = len(accessors)
        accessors.append({"bufferView": add(pos.tobytes(), 34962), "componentType": 5126, "count": count, "type": "VEC3",
                          "min": [float(x) for x in pos.min(axis=0)], "max": [float(x) for x in pos.max(axis=0)]})
        accessors.append({"bufferView": add(nrm.tobytes(), 34962), "componentType": 5126, "count": count, "type": "VEC3"})
        accessors.append({"bufferView": add(idx.tobytes(), 34963), "componentType": 5125 if big else 5123,
                          "count": count, "type": "SCALAR"})
        rgb = srgb_to_linear(library.role_preview(role))
        materials.append({"name": role, "pbrMetallicRoughness": {
            "baseColorFactor": [round(c, 6) for c in rgb] + [1.0], "metallicFactor": 0.0, "roughnessFactor": 0.8}})
        prims.append({"attributes": {"POSITION": a_pos, "NORMAL": a_pos + 1}, "indices": a_pos + 2,
                      "material": len(materials) - 1})
        if skel is not None:
            prims[-1]["attributes"]["JOINTS_0"] = len(accessors)
            accessors.append({"bufferView": add(np.ascontiguousarray(surf[3], dtype=np.uint16).tobytes(), 34962),
                              "componentType": 5123, "count": count, "type": "VEC4"})
            prims[-1]["attributes"]["WEIGHTS_0"] = len(accessors)
            accessors.append({"bufferView": add(np.ascontiguousarray(surf[4], dtype=np.float32).tobytes(), 34962),
                              "componentType": 5126, "count": count, "type": "VEC4"})
    nodes = [{"name": node_name, "mesh": 0}]
    scene_nodes = [0]
    extra = {}
    if skel is not None:
        heads = [np.array(b.head) / 1000.0 for b in skel.bones]
        ibm = np.zeros((len(heads), 16), dtype=np.float32)
        ibm[:, [0, 5, 10, 15]] = 1.0
        ibm[:, 12:15] = -np.array(heads)
        a_ibm = len(accessors)
        accessors.append({"bufferView": add(ibm.tobytes(), None), "componentType": 5126, "count": len(heads),
                          "type": "MAT4"})
        for i, b in enumerate(skel.bones):
            at_ = heads[i] - (heads[skel.index(b.parent)] if b.parent else 0.0)
            nodes.append({"name": b.name, "translation": [float(x) for x in at_]})
        for i, b in enumerate(skel.bones):
            if b.parent is None:
                scene_nodes.append(1 + i)
            else:
                nodes[1 + skel.index(b.parent)].setdefault("children", []).append(1 + i)
        nodes[0]["skin"] = 0
        extra["skins"] = [{"name": node_name, "joints": [1 + i for i in range(len(heads))],
                           "inverseBindMatrices": a_ibm}]
    while len(blob) % 4:
        blob.append(0)
    doc = {"asset": {"version": "2.0", "generator": "cadkit"}, "scene": 0, "scenes": [{"nodes": scene_nodes}],
           "nodes": nodes, "meshes": [{"name": node_name, "primitives": prims}], **extra,
           "materials": materials, "buffers": [{"byteLength": len(blob)}], "bufferViews": views, "accessors": accessors}
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    body = struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\0") + bytes(blob)
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


def read_glb(path: Path) -> dict:
    """What a GLB holds, for comparing: {"bounds": [[min], [max]], "surfaces": {material name: triangles}}."""
    data = Path(path).read_bytes()
    jlen = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jlen])
    surf, lo, hi = {}, [], []
    for mesh in doc["meshes"]:
        for p in mesh["primitives"]:
            name = doc["materials"][p["material"]]["name"] if "material" in p else ""
            n = doc["accessors"][p["indices"]]["count"] if "indices" in p else doc["accessors"][p["attributes"]["POSITION"]]["count"]
            surf[name] = surf.get(name, 0) + n // 3
            acc = doc["accessors"][p["attributes"]["POSITION"]]
            lo.append(acc["min"])
            hi.append(acc["max"])
    out = {"bounds": [np.min(lo, axis=0).tolist(), np.max(hi, axis=0).tolist()], "surfaces": surf}
    if doc.get("skins"):
        skin = doc["skins"][0]
        nodes = doc["nodes"]
        parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}
        out["bones"] = [{"name": nodes[j]["name"], "parent": nodes[parent[j]]["name"] if j in parent else None,
                         "translation": nodes[j].get("translation", [0.0, 0.0, 0.0])} for j in skin["joints"]]
        out["skin"] = {"joints": [nodes[j]["name"] for j in skin["joints"]],
                       "inverse_bind_matrices": doc["accessors"][skin["inverseBindMatrices"]]["count"]}
    return out


def _accessor(doc: dict, blob: bytes, idx: int) -> np.ndarray:
    acc = doc["accessors"][idx]
    view = doc["bufferViews"][acc["bufferView"]]
    width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc["type"]]
    dtype = {5126: np.float32, 5123: np.uint16, 5125: np.uint32}[acc["componentType"]]
    a = np.frombuffer(blob, dtype, acc["count"] * width, view.get("byteOffset", 0) + acc.get("byteOffset", 0))
    return a.reshape(acc["count"], width) if width > 1 else a


def read_skinned(path: Path) -> dict:
    """A skinned GLB's data for checking and posing: {"surfaces": [{"role", "pos" (metres), "joints", "weights",
    "indices"}], "bones": [{"name", "parent", "head" (metres, world at rest), "ibm_t" (inverse bind translation)}]}.
    Raises ValueError if the file has no skin."""
    data = Path(path).read_bytes()
    jlen = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jlen])
    blob = data[20 + jlen + 8:]
    if not doc.get("skins"):
        raise ValueError(f"{path} is not skinned")
    skin, nodes = doc["skins"][0], doc["nodes"]
    parent = {c: i for i, n in enumerate(nodes) for c in n.get("children", [])}

    def world(j: int) -> np.ndarray:
        t = np.array(nodes[j].get("translation", [0.0, 0.0, 0.0]), dtype=float)
        return t + (world(parent[j]) if j in parent else 0.0)

    ibm = _accessor(doc, blob, skin["inverseBindMatrices"])
    bones = [{"name": nodes[j]["name"], "parent": nodes[parent[j]]["name"] if j in parent else None,
              "head": world(j), "ibm_t": ibm[i, 12:15].astype(float)} for i, j in enumerate(skin["joints"])]
    out = []
    for p in doc["meshes"][0]["primitives"]:
        at_ = p["attributes"]
        if "JOINTS_0" not in at_ or "WEIGHTS_0" not in at_:
            raise ValueError(f"{path}: a primitive has no JOINTS_0/WEIGHTS_0")
        out.append({"role": doc["materials"][p["material"]]["name"],
                    "pos": _accessor(doc, blob, at_["POSITION"]).astype(float),
                    "joints": _accessor(doc, blob, at_["JOINTS_0"]),
                    "weights": _accessor(doc, blob, at_["WEIGHTS_0"]),
                    "indices": _accessor(doc, blob, p["indices"])})
    return {"surfaces": out, "bones": bones}


def export_solids_glb(solids: list[Solid], path: Path, node_name: str, tol_mm: float = 0.2, ang: float = 0.5,
                      skeleton=None) -> dict:
    """Write a GLB of the solids (one node, one surface per role) and its Godot .import. Returns triangles and bbox.
    With a skeleton the solids must be bound and the GLB is skinned; the report then also lists the bone names."""
    surfs = surfaces(solids, tol_mm, ang) if skeleton is None else skinned_surfaces(solids, skeleton, tol_mm, ang)
    path.parent.mkdir(parents=True, exist_ok=True)
    write_glb(path, node_name, surfs, skeleton)
    res = library.res(path)
    library.note(path)
    imp = Path(str(path) + ".import")
    if not imp.exists():
        imp.write_text(f'[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n[deps]\n\n'
                       f'source_file="{res}"\n\n[params]\n\nimport_script/path="{IMPORT_SCRIPT}"\n')
    allpos = np.concatenate([sf[1] for sf in surfs])
    lo, hi = allpos.min(axis=0), allpos.max(axis=0)
    rep = {"glb": res, "triangles": int(len(allpos) // 3), "bbox_m": [lo.round(4).tolist(), hi.round(4).tolist()]}
    if skeleton is not None:
        rep["bones"] = skeleton.names()
    return rep


def at(shape: bd.Shape, x: float = 0.0, y: float = 0.0, z: float = 0.0, rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> bd.Shape:
    """Move a shape (mm, degrees about X, then Y, then Z)."""
    return shape.moved(bd.Location((x, y, z), (rx, ry, rz)))


def box(w: float, h: float, d: float, chamfer_mm: float = 0.0, base_z: bool = True) -> bd.Part:
    """A box w (X) by h (Y) by d (Z), centred in X and Y, from Z=0 to d (or centred in Z), edges chamfered."""
    b = bd.Box(w, h, d, align=(bd.Align.CENTER, bd.Align.CENTER, bd.Align.MIN if base_z else bd.Align.CENTER))
    return bd.chamfer(b.edges(), chamfer_mm) if chamfer_mm > 0 else b


def prism(sides: int, radius: float, height: float, chamfer_top: float = 0.0, rotation_deg: float | None = None) -> bd.Part:
    """A polygonal cylinder along +Z from Z=0 with an explicit side count (low-poly by construction).

    `radius` is to the corners. By default a flat faces +X and +Y, so the bounding box is narrower than 2 * radius
    (0.924 of it for 8 sides); a part's footprint is the corner-to-corner figure, 2 * radius."""
    p = ngon_prism(sides, radius, height, rotation_deg if rotation_deg is not None else 180.0 / sides)
    if chamfer_top > 0:
        p = bd.chamfer(p.faces().sort_by(bd.Axis.Z)[-1].edges(), chamfer_top)
    return p


class GeometryError(AssertionError):
    pass


def expect(cond: bool, what: str) -> None:
    """A geometric assertion against the brief. Every scene's build must pass all of them before it writes files."""
    if not cond:
        raise GeometryError(what)


def bbox_mm(shape: bd.Shape) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    b = shape.bounding_box()
    return (tuple(round(c, 2) for c in b.min), tuple(round(c, 2) for c in b.max))
