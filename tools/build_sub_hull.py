"""Build the sub's hull from the program (assets/models/vehicles/sub_interior/program.yaml), headless.

    uv run --project tools/asset_pipeline python assets/models/vehicles/sub_interior/plan.py   # refresh layout.json
    python3 tools/build_sub_hull.py [out.glb]                                                  # default assets/sub/sub_hull.glb

Reads layout.json (which plan.py makes from the program: the hull's inner-surface rings, the floors, the
compartments and the clearances) and writes a GLB in the interior frame (origin on the main cabin floor at the
centreline, x starboard, y up, z toward the stern; docs/sub_frame.md). Needs only numpy. Surfaces are named after
palette roles (docs/palette.md); the import script gives them the shared role materials.

Parts (node names; "-col" nodes become StaticBody3D trimesh collision on import):

    hull_shell-col      the cabin wall, midships to the stern cap, seen from inside   (hull_metal)
    dome_glass-col      the cockpit bubble, bow to the rim ring, with its cap          (glass)
    dome_rim            the steel ring where the dome meets the cabin                  (trim_black)
    deck_cockpit-col    the pilot's floor, one step down, narrowing to glass underfoot (interior_dark)
    deck_midships-col   the main deck from the step to the bulkhead                    (interior_dark)
    deck_bulkhead-col   the deck through the bulkhead's thickness, the hatch sill      (interior_dark)
    deck_engineering-col  the deck aft of the bulkhead                                (interior_dark)
    cockpit_step-col    the way up from the cockpit floor to the main deck: a 0.25 m ramp, 0.2 m rise (interior_dark)
    bulkhead-col        the watertight bulkhead with its 0.75 x 1.7 m hatch opening   (interior_panel)
    hatch_frame         the coaming round the hatch opening                           (trim_black)
    tower               the conning tower on the hull's roof, with its top hatch      (hull_metal)

The tower is a fairing on the outside of the shell; the shaft through the roof belongs to the ladder's arc.
"""
from __future__ import annotations

import json
import math
import struct
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
LAYOUT = ROOT / "assets/models/vehicles/sub_interior/layout.json"
DEFAULT_OUT = ROOT / "assets/sub/sub_hull.glb"

LOFT_STRIDE = 2
DECK_THICKNESS = 0.06
STEP_RUN = 0.25            # fore-and-aft length of the ramp from the cockpit floor up to the main deck
RIM_HALF = 0.06            # the dome ring's half-section, along and across the wall
TOWER_RADIUS = 0.6
TOWER_HEIGHT = 1.0
TOWER_SINK = 0.25          # how far the tower's skirt sinks into the roof
HATCH_FRAME = 0.06         # coaming width round the hatch opening


class Part:
    """One mesh: triangles with a palette-role material. Faces wind counter-clockwise seen from the front."""

    def __init__(self, name: str, role: str) -> None:
        self.name, self.role = name, role
        self.tris: list[tuple[tuple[float, float, float], ...]] = []

    def tri(self, a, b, c) -> None:
        a, b, c = (tuple(float(v) for v in p) for p in (a, b, c))
        if np.linalg.norm(np.cross(np.subtract(b, a), np.subtract(c, a))) > 1e-10:
            self.tris.append((a, b, c))

    def quad(self, a, b, c, d) -> None:
        self.tri(a, b, c)
        self.tri(a, c, d)

    def quad_dir(self, a, b, c, d, direction) -> None:
        """A quad wound so its normal points along `direction`."""
        n = np.cross(np.subtract(b, a), np.subtract(c, a)) + np.cross(np.subtract(c, a), np.subtract(d, a))
        if np.dot(n, direction) < 0:
            b, d = d, b
        self.quad(a, b, c, d)

    def poly(self, pts: list, flip: bool = False) -> None:
        """A planar simple polygon (ear clipped), counter-clockwise seen from the front unless flipped."""
        p = np.array(pts, dtype=float)
        n = np.zeros(3)
        for i in range(len(p)):
            n += np.cross(p[i], p[(i + 1) % len(p)])
        axis = int(np.argmax(np.abs(n)))
        keep = [k for k in range(3) if k != axis]
        uv = p[:, keep]
        idx = list(range(len(p)))
        area = sum(uv[i][0] * uv[(i + 1) % len(p)][1] - uv[(i + 1) % len(p)][0] * uv[i][1] for i in range(len(p)))
        if area < 0:
            idx.reverse()
        guard = 0
        while len(idx) > 3 and guard < 10000:
            guard += 1
            for k in range(len(idx)):
                i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % len(idx)]
                a, b, c = uv[i0], uv[i1], uv[i2]
                if (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) <= 1e-12:
                    continue
                if any(_inside(uv[j], a, b, c) for j in idx if j not in (i0, i1, i2)):
                    continue
                self._emit(p[i0], p[i1], p[i2], n, flip)
                idx.pop(k)
                break
            else:
                break
        if len(idx) == 3:
            self._emit(p[idx[0]], p[idx[1]], p[idx[2]], n, flip)

    def _emit(self, a, b, c, n, flip: bool) -> None:
        if np.dot(np.cross(b - a, c - a), n) < 0:
            b, c = c, b
        if flip:
            b, c = c, b
        self.tri(a, b, c)


def _inside(p, a, b, c) -> bool:
    def s(u, v, w) -> float:
        return (u[0] - w[0]) * (v[1] - w[1]) - (v[0] - w[0]) * (u[1] - w[1])
    d1, d2, d3 = s(p, a, b), s(p, b, c), s(p, c, a)
    return not ((d1 < -1e-12 or d2 < -1e-12 or d3 < -1e-12) and (d1 > 1e-12 or d2 > 1e-12 or d3 > 1e-12))


def box(part: Part, x0, x1, y0, y1, z0, z1) -> None:
    for pts in (
        [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],   # +z
        [(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)],   # -z
        [(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)],   # +x
        [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)],   # -x
        [(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)],   # +y
        [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],   # -y
    ):
        part.quad(*pts)


def fix_outward(part: Part, centre) -> None:
    """Flip any triangle whose normal points toward `centre` (for convex-ish closed parts)."""
    c = np.array(centre, dtype=float)
    out = []
    for a, b, d in part.tris:
        n = np.cross(np.subtract(b, a), np.subtract(d, a))
        mid = (np.array(a) + np.array(b) + np.array(d)) / 3
        out.append((a, b, d) if np.dot(n, mid - c) >= 0 else (a, d, b))
    part.tris = out


def build(layout: dict) -> list[Part]:
    deck_y = float(layout["main_deck_y"])
    all_rings = layout["hull"]["rings"]
    rings = all_rings[::LOFT_STRIDE]            # every second ring: the wall is smooth enough, at half the triangles
    if rings[-1] is not all_rings[-1]:
        rings.append(all_rings[-1])
    comps = {c["id"]: c for c in layout["compartments"]}
    clr = layout["clearances"]
    cockpit_end = float(comps["cockpit"]["z"][1])
    n = len(rings[0]["points"])
    parts: list[Part] = []

    # --- the cabin wall and the dome: the rings' lofted inner surface, wound to face the inside -----------
    shell = Part("hull_shell-col", "hull_metal")
    dome = Part("dome_glass-col", "glass")
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        target = dome if 0.5 * (a["z"] + b["z"]) < cockpit_end else shell
        for k in range(n):
            k2 = (k + 1) % n
            # rings run counter-clockwise in (x, y) as z increases; this winding faces the axis
            target.quad(
                (*a["points"][k], a["z"]), (*b["points"][k], b["z"]),
                (*b["points"][k2], b["z"]), (*a["points"][k2], a["z"]),
            )
    for part in (shell, dome):
        _face_axis(part)
    dome.poly([(x, y, rings[0]["z"]) for x, y in rings[0]["points"]])               # the bow cap faces aft
    shell.poly([(x, y, rings[-1]["z"]) for x, y in rings[-1]["points"]], flip=True)  # the stern cap faces forward
    parts += [shell, dome]

    # --- the dome's rim ring, a square-section band on the wall at the cockpit's end ----------------------
    ring = min(rings, key=lambda r: abs(r["z"] - cockpit_end))
    rim = Part("dome_rim", "trim_black")
    pts = ring["points"]
    cx = 0.0
    cy = sum(p[1] for p in pts) / n
    inner = []
    for x, y in pts:
        d = np.array([cx - x, cy - y])
        d /= np.linalg.norm(d)
        inner.append((x + d[0] * 0.08, y + d[1] * 0.08))
    z0, z1 = cockpit_end - RIM_HALF, cockpit_end + RIM_HALF
    for k in range(n):
        k2 = (k + 1) % n
        pa, pb, ia, ib = pts[k], pts[k2], inner[k], inner[k2]
        mx, my = (pa[0] + pb[0]) / 2 - cx, (pa[1] + pb[1]) / 2 - cy
        rim.quad_dir((*pa, z0), (*pb, z0), (*pb, z1), (*pa, z1), (mx, my, 0))        # against the wall
        rim.quad_dir((*ia, z1), (*ib, z1), (*ib, z0), (*ia, z0), (-mx, -my, 0))      # facing the cabin
        rim.quad_dir((*pa, z0), (*ia, z0), (*ib, z0), (*pb, z0), (0, 0, -1))         # forward face
        rim.quad_dir((*pb, z1), (*ib, z1), (*ia, z1), (*pa, z1), (0, 0, 1))          # aft face
    parts.append(rim)

    # --- deck plates: floors from layout.json, each a slab DECK_THICKNESS thick -------------------------
    floors = {f["id"]: f for f in layout["floors"]}
    for fid in ("cockpit", "midships", "bulkhead", "engineering"):
        f = floors[fid]
        y = float(f["y"])
        plate = Part(f"deck_{fid}-col", "interior_dark")
        out = [(float(z), float(hw)) for z, hw in f["outline"]]
        z_lo, z_hi = out[0][0], out[-1][0]
        if fid == "cockpit":
            z_hi = z_hi - STEP_RUN       # the ramp takes the aft quarter metre
            out = [(z, hw) for z, hw in out if z <= z_hi + 1e-9] + [(z_hi, _hw_at(out, z_hi))]
        _slab(plate, out, y, DECK_THICKNESS)
        parts.append(plate)

    # --- the step: a ramp the player capsule can walk up (a vertical 0.2 m riser would stop it) ---------
    cock_y = float(floors["cockpit"]["y"])
    step_z1 = cockpit_end
    step_z0 = step_z1 - STEP_RUN
    mid_out = [(float(z), float(hw)) for z, hw in floors["midships"]["outline"]]
    hw0, hw1 = _hw_at(mid_out, step_z0), _hw_at(mid_out, step_z1)
    ramp = Part("cockpit_step-col", "interior_dark")
    lo = cock_y - DECK_THICKNESS
    top = [(-hw0, cock_y, step_z0), (hw0, cock_y, step_z0), (hw1, deck_y, step_z1), (-hw1, deck_y, step_z1)]
    bot = [(-hw0, lo, step_z0), (hw0, lo, step_z0), (hw1, lo, step_z1), (-hw1, lo, step_z1)]
    slope = (0.0, step_z1 - step_z0, -(deck_y - cock_y))      # normal of the ramp surface (up and toward the bow)
    ramp.quad_dir(top[0], top[1], top[2], top[3], slope)
    ramp.quad_dir(bot[0], bot[1], bot[2], bot[3], (0, -1, 0))
    ramp.quad_dir(bot[0], top[0], top[1], bot[1], (0, 0, -1))
    ramp.quad_dir(bot[2], top[2], top[3], bot[3], (0, 0, 1))
    ramp.quad_dir(bot[1], top[1], top[2], bot[2], (1, 0, 0))
    ramp.quad_dir(bot[0], top[0], top[3], bot[3], (-1, 0, 0))
    parts.append(ramp)

    # --- the bulkhead and its hatch --------------------------------------------------------------------
    bz0, bz1 = (float(v) for v in comps["bulkhead"]["z"])
    bring = min(rings, key=lambda r: abs(r["z"] - 0.5 * (bz0 + bz1)))
    section = _above(bring["points"], deck_y)       # right deck edge, over the top, left deck edge
    hw = float(clr["hatch_width_m"]) / 2
    hh = float(clr["hatch_height_m"])
    # section runs right edge -> top -> left edge; the notch goes back along the deck, up and over the hatch
    outline = section + [(-hw, deck_y), (-hw, deck_y + hh), (hw, deck_y + hh), (hw, deck_y)]
    plate = Part("bulkhead-col", "interior_panel")
    _prism(plate, outline, bz0, bz1)
    parts.append(plate)

    frame = Part("hatch_frame", "trim_black")
    f = HATCH_FRAME
    for zface, sgn in ((bz0, -1), (bz1, 1)):
        zf0, zf1 = (zface - 0.02, zface) if sgn < 0 else (zface, zface + 0.02)
        box(frame, -hw - f, -hw, deck_y, deck_y + hh + f, zf0, zf1)
        box(frame, hw, hw + f, deck_y, deck_y + hh + f, zf0, zf1)
        box(frame, -hw - f, hw + f, deck_y + hh, deck_y + hh + f, zf0, zf1)
    parts.append(frame)

    # --- the conning tower, over the ladder's z --------------------------------------------------------
    ladder = next((i for i in layout["items"] if i["kind"] == "ladder"), None)
    tz = float(ladder["z"]) if ladder else 1.2
    roof = _roof_y(rings, tz)
    tower = Part("tower", "hull_metal")
    y0, y1 = roof - TOWER_SINK, roof + TOWER_HEIGHT
    seg = 32
    circ = [(TOWER_RADIUS * math.cos(2 * math.pi * k / seg), TOWER_RADIUS * math.sin(2 * math.pi * k / seg)) for k in range(seg)]
    for k in range(seg):
        (xa, za), (xb, zb) = circ[k], circ[(k + 1) % seg]
        tower.quad((xa, y0, tz + za), (xb, y0, tz + zb), (xb, y1, tz + zb), (xa, y1, tz + za))
        tower.tri((0, y1, tz), (xa, y1, tz + za), (xb, y1, tz + zb))
    fix_outward(tower, (0.0, (y0 + y1) / 2, tz))
    hatch = Part("tower_hatch", "interior_panel")           # a wheel-lid disc on top
    r2 = TOWER_RADIUS * 0.7
    for k in range(seg):
        ca, cb = circ[k], circ[(k + 1) % seg]
        a = (ca[0] * 0.7, y1 + 0.03, tz + ca[1] * 0.7)
        b = (cb[0] * 0.7, y1 + 0.03, tz + cb[1] * 0.7)
        hatch.tri((0, y1 + 0.03, tz), a, b)
        hatch.quad((a[0], y1, a[2]), (b[0], y1, b[2]), b, a)
    fix_outward(hatch, (0.0, y1 - 0.02, tz))
    parts += [tower, hatch]

    # --- to the interior frame --------------------------------------------------------------------------
    for part in parts:
        part.tris = [tuple((x, y - deck_y, z) for x, y, z in t) for t in part.tris]
    return parts


def _face_axis(part: Part, ring_part: bool = False) -> None:
    """Make every triangle's normal point toward the hull axis (y at the section's centre), i.e. inward."""
    out = []
    for a, b, d in part.tris:
        n = np.cross(np.subtract(b, a), np.subtract(d, a))
        mid = (np.array(a) + np.array(b) + np.array(d)) / 3
        # wall triangles face the axis; end caps (nearly constant z) are handled by the caller's winding
        if abs(n[2]) > 0.9 * np.linalg.norm(n):
            out.append((a, b, d))
            continue
        to_axis = np.array([-mid[0], -mid[1] + 0.0, 0.0])
        out.append((a, b, d) if np.dot(n, to_axis) >= 0 else (a, d, b))
    part.tris = out


def _hw_at(outline: list[tuple[float, float]], z: float) -> float:
    for (za, ha), (zb, hb) in zip(outline, outline[1:]):
        if za <= z <= zb:
            t = 0.0 if zb == za else (z - za) / (zb - za)
            return ha + (hb - ha) * t
    return outline[-1][1]


def _slab(part: Part, outline: list[tuple[float, float]], y: float, thick: float) -> None:
    """A plate whose top is at y: the floor outline (z, half-width) mirrored about the centreline."""
    for k in range(len(outline) - 1):
        (za, ha), (zb, hb) = outline[k], outline[k + 1]
        lo = y - thick
        # top
        part.quad((-ha, y, za), (-hb, y, zb), (hb, y, zb), (ha, y, za))
        # bottom
        part.quad((-ha, lo, za), (ha, lo, za), (hb, lo, zb), (-hb, lo, zb))
        # side edges
        part.quad((ha, y, za), (hb, y, zb), (hb, lo, zb), (ha, lo, za))
        part.quad((-ha, lo, za), (-hb, lo, zb), (-hb, y, zb), (-ha, y, za))
    for (z, h), sgn in ((outline[0], -1), (outline[-1], 1)):
        if h > 1e-6:
            if sgn < 0:
                part.quad((-h, y, z), (h, y, z), (h, y - thick, z), (-h, y - thick, z))
            else:
                part.quad((h, y, z), (-h, y, z), (-h, y - thick, z), (h, y - thick, z))


def _above(points: list, y: float) -> list[tuple[float, float]]:
    """The part of a closed ring above height y, in order from the right edge over the top to the left edge,
    ending on y at both edges."""
    pts = [tuple(p) for p in points]
    k0 = min(range(len(pts)), key=lambda k: pts[k][1])      # the keel point: start there
    pts = pts[k0:] + pts[:k0]
    # the ring runs counter-clockwise: the right side first, then the top, then the left
    out: list[tuple[float, float]] = []
    for a, b in zip(pts, pts[1:] + pts[:1]):
        if a[1] < y <= b[1] or (a[1] < y and b[1] >= y):
            t = (y - a[1]) / (b[1] - a[1])
            out.append((a[0] + (b[0] - a[0]) * t, y))
        if a[1] >= y:
            out.append(a)
        if a[1] >= y > b[1]:
            t = (y - a[1]) / (b[1] - a[1])
            out.append((a[0] + (b[0] - a[0]) * t, y))
    return out


def _prism(part: Part, outline: list[tuple[float, float]], z0: float, z1: float) -> None:
    """A closed polygon in (x, y) extruded fore and aft, faces outward."""
    front = [(x, y, z0) for x, y in outline]
    back = [(x, y, z1) for x, y in outline]
    part.poly(front)
    part.poly(back)
    n = len(outline)
    for k in range(n):
        part.quad(front[k], front[(k + 1) % n], back[(k + 1) % n], back[k])
    part.tris = _orient(part.tris, z0, z1)


def _orient(tris, z0, z1):
    """Cap faces point away from the slab's mid-plane; side faces are left as the polygon winds them
    (counter-clockwise outlines wind sides outward)."""
    mid = 0.5 * (z0 + z1)
    out = []
    for a, b, d in tris:
        n = np.cross(np.subtract(b, a), np.subtract(d, a))
        if abs(n[2]) > 0.9 * np.linalg.norm(n):
            zc = (a[2] + b[2] + d[2]) / 3
            want = 1.0 if zc > mid else -1.0
            out.append((a, b, d) if n[2] * want > 0 else (a, d, b))
        else:
            out.append((a, b, d))
    return out


def _roof_y(rings: list, z: float) -> float:
    r = min(rings, key=lambda r: abs(r["z"] - z))
    return max(p[1] for p in r["points"])


# ---- GLB writer ------------------------------------------------------------------------------------

def write_glb(parts: list[Part], path: Path) -> None:
    buf = bytearray()
    views, accessors, meshes, nodes, materials = [], [], [], [], []
    mat_index: dict[str, int] = {}
    for part in parts:
        if not part.tris:
            raise SystemExit(f"part {part.name} is empty")
        tris = np.array(part.tris, dtype=np.float32)            # (T, 3, 3)
        a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
        nrm = np.cross(b - a, c - a)
        nrm /= np.linalg.norm(nrm, axis=1)[:, None]
        pos = tris.reshape(-1, 3)
        normals = np.repeat(nrm, 3, axis=0).astype(np.float32)
        idx = np.arange(len(pos), dtype=np.uint32)
        if part.role not in mat_index:
            mat_index[part.role] = len(materials)
            materials.append({"name": part.role, "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 1.0},
                              "doubleSided": False})
        refs = []
        for arr, target, kind, extra in ((pos, 34962, "VEC3", True), (normals, 34962, "VEC3", False), (idx, 34963, "SCALAR", False)):
            while len(buf) % 4:
                buf.append(0)
            data = arr.tobytes()
            views.append({"buffer": 0, "byteOffset": len(buf), "byteLength": len(data), "target": target})
            buf += data
            acc = {"bufferView": len(views) - 1, "componentType": 5125 if arr.dtype == np.uint32 else 5126,
                   "count": int(arr.shape[0]), "type": kind}
            if extra:
                acc["min"], acc["max"] = [float(v) for v in arr.min(axis=0)], [float(v) for v in arr.max(axis=0)]
            accessors.append(acc)
            refs.append(len(accessors) - 1)
        meshes.append({"name": part.name, "primitives": [{"attributes": {"POSITION": refs[0], "NORMAL": refs[1]},
                                                          "indices": refs[2], "material": mat_index[part.role]}]})
        nodes.append({"name": part.name, "mesh": len(meshes) - 1})
    doc = {
        "asset": {"version": "2.0", "generator": "tools/build_sub_hull.py"},
        "scene": 0, "scenes": [{"name": "SubHull", "nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes, "materials": materials, "accessors": accessors, "bufferViews": views,
        "buffers": [{"byteLength": len(buf)}],
    }
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    buf += b"\0" * (-len(buf) % 4)
    total = 12 + 8 + len(js) + 8 + len(buf)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        f.write(struct.pack("<I4s", len(buf), b"BIN\0") + bytes(buf))


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    parts = build(layout)
    write_glb(parts, out)
    print(f"wrote {out} ({sum(len(p.tris) for p in parts)} triangles)")
    for p in parts:
        print(f"  {p.name}: {len(p.tris)} triangles, {p.role}")


if __name__ == "__main__":
    main()
