"""`asset check <slug>`: numeric gates on a cleaned mesh, written as a JSON report. Pure Python (no Blender, no
renderer): the mesh is read from the GLB and its silhouette is computed by orthographic projection."""
from __future__ import annotations

import struct
import zlib
from pathlib import Path
from typing import Any

from .fixture_mesh import glb_document

GRID = 256  # silhouette canvas, pixels per side
VIEWS = ("front", "left", "back", "right")  # the views every turnaround has
ALL_VIEWS = VIEWS + ("top", "bottom")  # top and bottom are optional (a class's `turnaround_views` asks for them)
# Orthographic cameras, as (right axis index, sign, up axis index, sign): which mesh axis, signed, runs along the
# image's right and up directions. The asset faces +Z (glTF), up is +Y.
# front: camera on +Z, so +X is right. back: camera on -Z, +X is left.
# left / right are the asset's own sides: left (its -X side) is seen from -X, where +Z is right;
# right is seen from +X, where -Z is right.
# top: camera above looking straight down, +X right and the front (+Z) toward the bottom of the image.
# bottom: camera below looking straight up, +X right and the front (+Z) toward the top of the image.
VIEW_AXES = {"front": (0, 1.0, 1, 1.0), "back": (0, -1.0, 1, 1.0), "left": (2, 1.0, 1, 1.0), "right": (2, -1.0, 1, 1.0),
             "top": (0, 1.0, 2, -1.0), "bottom": (0, 1.0, 2, 1.0)}
WELD_DIGITS = 5
COLLISION_MARKS = ("colonly",)  # Godot's import suffixes `-colonly` and `-convcolonly`
GATE_NAMES = ("triangles", "bbox", "loose_parts", "non_manifold") + tuple(f"silhouette_{v}" for v in VIEWS)  # always present; top and bottom are added when those views exist


# --- mesh loading ---------------------------------------------------------------------------------------------

def _mat_mul(a: list[float], b: list[float]) -> list[float]:
    """4x4 column-major matrices (glTF layout): a * b."""
    return [sum(a[k * 4 + r] * b[c * 4 + k] for k in range(4)) for c in range(4) for r in range(4)]


def _node_matrix(node: dict[str, Any]) -> list[float]:
    if "matrix" in node:
        return [float(x) for x in node["matrix"]]
    tx, ty, tz = node.get("translation", (0.0, 0.0, 0.0))
    x, y, z, w = node.get("rotation", (0.0, 0.0, 0.0, 1.0))
    sx, sy, sz = node.get("scale", (1.0, 1.0, 1.0))
    r = [1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w),
         2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w),
         2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y)]
    return [r[0] * sx, r[1] * sx, r[2] * sx, 0.0, r[3] * sy, r[4] * sy, r[5] * sy, 0.0,
            r[6] * sz, r[7] * sz, r[8] * sz, 0.0, tx, ty, tz, 1.0]


def load_mesh(path: Path) -> dict[str, Any]:
    """World-space geometry of every scene mesh except collision helpers:
    {positions, triangles, skipped_collision}. Node transforms are applied."""
    doc, acc = glb_document(path)
    nodes = doc.get("nodes", [])
    scene = doc.get("scenes", [{"nodes": list(range(len(nodes)))}])[doc.get("scene", 0)]
    pos: list[tuple[float, float, float]] = []
    tris: list[tuple[int, int, int]] = []
    skipped: list[str] = []

    def visit(i: int, parent: list[float]) -> None:
        node = nodes[i]
        m = _mat_mul(parent, _node_matrix(node))
        name = str(node.get("name", ""))
        is_col = any(k in name.lower() for k in COLLISION_MARKS)
        if is_col:
            skipped.append(name)
        elif "mesh" in node:
            for prim in doc["meshes"][node["mesh"]]["primitives"]:
                if prim.get("mode", 4) != 4:
                    continue
                p = acc(prim["attributes"]["POSITION"])
                base = len(pos)
                for x, y, z in p:
                    pos.append((m[0] * x + m[4] * y + m[8] * z + m[12], m[1] * x + m[5] * y + m[9] * z + m[13],
                                m[2] * x + m[6] * y + m[10] * z + m[14]))
                ind = [v[0] for v in acc(prim["indices"])] if "indices" in prim else list(range(len(p)))
                tris.extend((base + ind[k], base + ind[k + 1], base + ind[k + 2]) for k in range(0, len(ind) - 2, 3))
        for c in node.get("children", []):
            visit(c, m)

    ident = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]
    for n in scene.get("nodes", []):
        visit(n, ident)
    if not tris:
        raise ValueError(f"{path} has no triangles to check")
    return {"positions": pos, "triangles": tris, "skipped_collision": skipped}


# --- measurements ---------------------------------------------------------------------------------------------

def bounding_box(pos: list[tuple[float, float, float]], tris: list[tuple[int, int, int]]) -> tuple[list[float], list[float]]:
    used = {i for t in tris for i in t}
    pts = [pos[i] for i in used]
    return [min(p[a] for p in pts) for a in range(3)], [max(p[a] for p in pts) for a in range(3)]


def topology(pos: list[tuple[float, float, float]], tris: list[tuple[int, int, int]]) -> dict[str, int]:
    """Non-manifold edge count and loose-part count, with vertices welded by position (flat shading and UV seams
    split them); faces collapsed by the weld are ignored. An edge is non-manifold unless exactly two triangles share it (so holes count)."""
    weld: dict[tuple[float, ...], int] = {}
    ids = [weld.setdefault(tuple(round(c, WELD_DIGITS) for c in p), len(weld)) for p in pos]
    parent = list(range(len(weld)))

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    edges: dict[tuple[int, int], int] = {}
    used: set[int] = set()
    for a, b, c in tris:
        a, b, c = ids[a], ids[b], ids[c]
        if a == b or b == c or a == c:
            continue  # a face collapsed by welding has no area and no real edges
        used.update((a, b, c))
        for u, v in ((a, b), (b, c), (c, a)):
            k = (u, v) if u < v else (v, u)
            edges[k] = edges.get(k, 0) + 1
            parent[find(u)] = find(v)
    return {"non_manifold_edges": sum(1 for n in edges.values() if n != 2),
            "loose_parts": len({find(i) for i in used})}


# --- silhouettes ----------------------------------------------------------------------------------------------

def _fit(w: int, h: int) -> tuple[float, float, float]:
    """Uniform scale and offsets that centre a w x h extent in the canvas, leaving a one-pixel margin."""
    s = (GRID - 2) / max(w, h, 1e-12)
    return s, (GRID - w * s) / 2.0, (GRID - h * s) / 2.0


def mesh_silhouette(pos: list[tuple[float, float, float]], tris: list[tuple[int, int, int]], view: str) -> bytearray:
    """GRID x GRID mask (1 = covered) of the mesh projected orthographically from `view`, scaled uniformly so
    its projected extent fills the canvas, row 0 at the top."""
    ax, sign, vx, vsign = VIEW_AXES[view]
    pts = [(sign * p[ax], vsign * p[vx]) for p in pos]
    used = {i for t in tris for i in t}
    u0, u1 = min(pts[i][0] for i in used), max(pts[i][0] for i in used)
    v0, v1 = min(pts[i][1] for i in used), max(pts[i][1] for i in used)
    s, ox, oy = _fit(u1 - u0, v1 - v0)
    scr = [((p[0] - u0) * s + ox, (v1 - p[1]) * s + oy) for p in pts]
    mask = bytearray(GRID * GRID)
    for ia, ib, ic in tris:
        (ax_, ay), (bx, by), (cx, cy) = scr[ia], scr[ib], scr[ic]
        for x, y in ((ax_, ay), (bx, by), (cx, cy)):  # sub-pixel triangles still leave their mark
            mask[min(GRID - 1, int(y)) * GRID + min(GRID - 1, int(x))] = 1
        area = (bx - ax_) * (cy - ay) - (by - ay) * (cx - ax_)
        if abs(area) < 1e-9:
            continue
        x0, x1 = max(0, int(min(ax_, bx, cx))), min(GRID - 1, int(max(ax_, bx, cx)))
        y0, y1 = max(0, int(min(ay, by, cy))), min(GRID - 1, int(max(ay, by, cy)))
        for y in range(y0, y1 + 1):
            py = y + 0.5
            row = y * GRID
            for x in range(x0, x1 + 1):
                px = x + 0.5
                w0 = ((bx - px) * (cy - py) - (by - py) * (cx - px)) / area
                w1 = ((cx - px) * (ay - py) - (cy - py) * (ax_ - px)) / area
                if w0 >= 0 and w1 >= 0 and w0 + w1 <= 1:
                    mask[row + x] = 1
    return mask


def read_png(path: Path) -> tuple[int, int, list[list[tuple[int, ...]]]]:
    """Decode an 8-bit, non-interlaced PNG (grey, RGB, palette, grey+alpha, RGBA) into rows of pixel tuples."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path.name} is not a PNG (only PNG views can be compared)")
    pos, idat, plte, hdr = 8, b"", b"", None
    while pos + 8 <= len(data):
        n, kind = struct.unpack_from(">I4s", data, pos)
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"PLTE":
            plte = body
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    if hdr is None:
        raise ValueError(f"{path.name} has no IHDR")
    w, h, depth, ctype, _, _, interlace = hdr
    if depth != 8 or interlace != 0 or ctype not in (0, 2, 3, 4, 6):
        raise ValueError(f"{path.name}: only 8-bit non-interlaced PNGs are supported")
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    stride = w * ch
    raw = zlib.decompress(idat)
    rows: list[list[tuple[int, ...]]] = []
    prev = bytearray(stride)
    off = 0
    for _ in range(h):
        f = raw[off]
        line = bytearray(raw[off + 1:off + 1 + stride])
        off += 1 + stride
        for i in range(stride):
            a = line[i - ch] if i >= ch else 0
            b = prev[i]
            c = prev[i - ch] if i >= ch else 0
            if f == 1:
                line[i] = (line[i] + a) & 255
            elif f == 2:
                line[i] = (line[i] + b) & 255
            elif f == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        if ctype == 3:
            rows.append([(plte[3 * v], plte[3 * v + 1], plte[3 * v + 2], 255) for v in line])
        else:
            rows.append([tuple(line[x * ch:(x + 1) * ch]) for x in range(w)])
    return w, h, rows


def write_mask_png(path: Path, mask: bytearray, size: int = GRID) -> None:
    """Write a mask as an RGBA PNG: opaque white where covered, transparent elsewhere."""
    raw = b"".join(b"\x00" + b"".join(b"\xff\xff\xff\xff" if mask[y * size + x] else b"\x00\x00\x00\x00"
                                       for x in range(size)) for y in range(size))

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def image_silhouette(path: Path) -> bytearray:
    """GRID x GRID mask of a turnaround view's subject, fitted the same way as `mesh_silhouette`. Subject = pixels
    with alpha above half when the image has transparency, else pixels that differ from the corner colour."""
    w, h, rows = read_png(path)
    has_alpha = len(rows[0][0]) in (2, 4)
    if has_alpha and any(px[-1] < 128 for r in rows for px in r):
        fg = [[px[-1] >= 128 for px in r] for r in rows]
    else:
        bg = rows[0][0][:3] if len(rows[0][0]) >= 3 else rows[0][0][:1]
        fg = [[max(abs(a - b) for a, b in zip(px[:len(bg)], bg)) > 24 for px in r] for r in rows]
    ys = [y for y in range(h) if any(fg[y])]
    if not ys:
        raise ValueError(f"{path.name} shows no subject (fully transparent or one flat colour)")
    xs = [x for x in range(w) if any(fg[y][x] for y in range(h))]
    x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
    s, ox, oy = _fit(x1 - x0, y1 - y0)
    mask = bytearray(GRID * GRID)
    for gy in range(GRID):
        sy = (gy + 0.5 - oy) / s
        if not 0 <= sy < y1 - y0:
            continue
        row = fg[y0 + int(sy)]
        for gx in range(GRID):
            sx = (gx + 0.5 - ox) / s
            if 0 <= sx < x1 - x0 and row[x0 + int(sx)]:
                mask[gy * GRID + gx] = 1
    return mask


def iou(a: bytearray, b: bytearray) -> float:
    inter = sum(1 for x, y in zip(a, b) if x and y)
    union = sum(1 for x, y in zip(a, b) if x or y)
    return inter / union if union else 0.0


# --- the gates ------------------------------------------------------------------------------------------------

def gate(name: str, ok: bool, value: Any, limit: Any, detail: str) -> dict[str, Any]:
    return {"name": name, "ok": bool(ok), "value": value, "limit": limit, "detail": detail}


def run_gates(mesh: dict[str, Any], profile: dict[str, Any], size_m: float, size_from: str, budget: int,
              views: dict[str, Path], silhouettes: bool = True) -> list[dict[str, Any]]:
    """Every gate, in a fixed order. Thresholds come from the class profile's `gates` block. Nothing is skipped:
    a gate that cannot be evaluated (a missing view) fails with the reason."""
    g = profile["gates"]
    pos, tris = mesh["positions"], mesh["triangles"]
    out: list[dict[str, Any]] = []
    limit = int(budget * g["triangle_tolerance"])
    out.append(gate("triangles", len(tris) <= limit, len(tris), limit,
                    f"{len(tris)} triangles against a budget of {budget} (tolerance x{g['triangle_tolerance']:g})"))
    lo, hi = bounding_box(pos, tris)
    dims = [h - l for l, h in zip(lo, hi)]
    largest = max(dims)
    err = abs(largest - size_m) / size_m
    out.append(gate("bbox", err <= g["bbox_tolerance"], round(largest, 4), round(size_m, 4),
                    f"largest dimension {largest:.3f} m against {size_m:.3f} m ({size_from}), off by {err * 100:.1f}% "
                    f"(tolerance {g['bbox_tolerance'] * 100:g}%); extents {dims[0]:.3f} x {dims[1]:.3f} x {dims[2]:.3f} m"))
    topo = topology(pos, tris)
    out.append(gate("loose_parts", topo["loose_parts"] <= g["max_loose_parts"], topo["loose_parts"], g["max_loose_parts"],
                    f"{topo['loose_parts']} connected parts, at most {g['max_loose_parts']} allowed"))
    out.append(gate("non_manifold", topo["non_manifold_edges"] <= g["max_non_manifold"], topo["non_manifold_edges"],
                    g["max_non_manifold"], f"{topo['non_manifold_edges']} edges not shared by exactly two faces "
                    f"(holes and overlaps), at most {g['max_non_manifold']} allowed"))
    need = g["silhouette_iou_min"]
    for view in ALL_VIEWS if silhouettes else ():  # a cad part has no turnaround to compare against
        name = f"silhouette_{view}"
        if view not in views and view not in VIEWS:
            continue  # top and bottom are checked only when the turnaround has them
        if view not in views:
            out.append(gate(name, False, None, need, f"no {view} turnaround view to compare against"))
            continue
        try:
            score = iou(mesh_silhouette(pos, tris, view), image_silhouette(views[view]))
        except (ValueError, OSError, zlib.error, struct.error) as e:
            out.append(gate(name, False, None, need, f"could not read the {view} view: {e}"))
            continue
        out.append(gate(name, score >= need, round(score, 4), need, f"{view} silhouette IoU {score:.3f}, at least {need:g} needed"))
    return out

