"""Generator for the noisy, coloured, ~100k-triangle fixture mesh that cleanup is tested on.

It imitates raw image-to-3D output: far too many triangles, high-frequency surface noise, a per-vertex
colour for every vertex (baked-lighting-like variation), a duplicated UV seam (so welding is needed),
and a stray loose fragment. Deterministic for a given seed. Pure Python: no numpy, no Blender."""
from __future__ import annotations

import json
import math
import random
import struct
from pathlib import Path

DEFAULT_SEGMENTS = 224  # 2 * 224 * 224 = 100352 triangles


def build(segments: int = DEFAULT_SEGMENTS, seed: int = 7) -> tuple[list[tuple[float, float, float]], list[tuple[float, float, float, float]], list[int]]:
    """Returns (positions, colours, triangle indices). A lumpy ellipsoid, 3 x 2 x 1.4 units, centred away from
    the origin, in an arbitrary scale, so cleanup has to fix scale and pivot."""
    rng = random.Random(seed)
    lat_n, lon_n = segments, segments
    pos: list[tuple[float, float, float]] = []
    col: list[tuple[float, float, float, float]] = []
    bases = [(0.2, 0.5, 0.6), (0.7, 0.3, 0.2), (0.3, 0.6, 0.3), (0.8, 0.8, 0.5), (0.4, 0.3, 0.6)]
    for i in range(lat_n + 1):
        th = math.pi * i / lat_n
        for j in range(lon_n + 1):  # j == lon_n repeats j == 0: a duplicated seam
            ph = 2.0 * math.pi * (j % lon_n) / lon_n
            lump = 1.0 + 0.12 * math.sin(th) * math.sin(3 * ph + 2 * th) + 0.05 * math.sin(11 * th) * math.sin(th)
            r = lump + rng.uniform(-0.015, 0.015) * (0 < i < lat_n)
            x = 1.5 * r * math.sin(th) * math.cos(ph) + 4.0
            y = 0.7 * r * math.cos(th) + 2.0
            z = 1.0 * r * math.sin(th) * math.sin(ph) - 1.0
            pos.append((x, y, z))
            b = bases[(i // (lat_n // 5 + 1)) % len(bases)]
            col.append((*(min(1.0, max(0.0, c + rng.uniform(-0.08, 0.08))) for c in b), 1.0))
    idx: list[int] = []
    stride = lon_n + 1
    for i in range(lat_n):
        for j in range(lon_n):
            a, b, c, d = i * stride + j, i * stride + j + 1, (i + 1) * stride + j, (i + 1) * stride + j + 1
            idx += [a, c, b, b, c, d]
    base = len(pos)  # a stray fragment, far from the body
    for p in ((9.0, 0.0, 0.0), (9.2, 0.0, 0.0), (9.0, 0.2, 0.0)):
        pos.append(p)
        col.append((1.0, 0.0, 1.0, 1.0))
    idx += [base, base + 1, base + 2]
    return pos, col, idx


def write_glb(path: Path, pos, col, idx) -> None:
    """Write one triangle mesh with a COLOR_0 attribute as a binary glTF 2.0 file."""
    pb = b"".join(struct.pack("<3f", *p) for p in pos)
    cb = b"".join(struct.pack("<4f", *c) for c in col)
    ib = struct.pack(f"<{len(idx)}I", *idx)
    blob = pb + cb + ib
    xs, ys, zs = zip(*pos)
    doc = {
        "asset": {"version": "2.0", "generator": "silent_water fixture_mesh"},
        "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "fixture"}],
        "meshes": [{"name": "fixture", "primitives": [{"attributes": {"POSITION": 0, "COLOR_0": 1}, "indices": 2}]}],
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(pb), "target": 34962},
                        {"buffer": 0, "byteOffset": len(pb), "byteLength": len(cb), "target": 34962},
                        {"buffer": 0, "byteOffset": len(pb) + len(cb), "byteLength": len(ib), "target": 34963}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "count": len(pos), "type": "VEC3",
                       "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)]},
                      {"bufferView": 1, "componentType": 5126, "count": len(col), "type": "VEC4"},
                      {"bufferView": 2, "componentType": 5125, "count": len(idx), "type": "SCALAR"}],
    }
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    blob += b"\0" * (-len(blob) % 4)
    total = 12 + 8 + len(js) + 8 + len(blob)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(js), b"JSON") + js
                     + struct.pack("<I4s", len(blob), b"BIN\0") + blob)


def glb_document(path: Path):
    """Parse a GLB: (glTF JSON document, accessor reader `acc(i) -> list of tuples`)."""
    data = path.read_bytes()
    jlen = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen = struct.unpack_from("<I", data, off)[0]
    blob = data[off + 8:off + 8 + blen]
    sizes = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

    def acc(i: int) -> list[tuple]:
        a = doc["accessors"][i]
        bv = doc["bufferViews"][a["bufferView"]]
        fmt, sz = sizes[a["componentType"]]
        n = ncomp[a["type"]]
        stride = bv.get("byteStride") or sz * n
        base = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        norm = a.get("normalized", False)
        out = []
        for k in range(a["count"]):
            v = struct.unpack_from(f"<{n}{fmt}", blob, base + k * stride)
            if norm:
                m = {"B": 255.0, "H": 65535.0}[fmt]
                v = tuple(x / m for x in v)
            out.append(v)
        return out

    return doc, acc


def read_glb(path: Path) -> dict:
    """Read a GLB: {prims: [{positions, colours, triangles}], nodes} (independent of Blender, used by tests)."""
    doc, acc = glb_document(path)
    prims = []
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            pos = acc(attrs["POSITION"])
            ind = [x[0] for x in acc(prim["indices"])] if "indices" in prim else list(range(len(pos)))
            prims.append({"positions": pos, "colours": acc(attrs["COLOR_0"]) if "COLOR_0" in attrs else [],
                          "triangles": [tuple(ind[k:k + 3]) for k in range(0, len(ind), 3)]})
    return {"prims": prims, "nodes": doc["nodes"]}


def main() -> None:
    import argparse
    ap = argparse.ArgumentParser(description="write the noisy cleanup fixture GLB")
    ap.add_argument("out", type=Path)
    ap.add_argument("--segments", type=int, default=DEFAULT_SEGMENTS)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    write_glb(a.out, *build(a.segments, a.seed))


if __name__ == "__main__":
    main()
