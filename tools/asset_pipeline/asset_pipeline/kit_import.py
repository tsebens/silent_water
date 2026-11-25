"""`asset import <slug> <export.gltf>`: bring an Onshape glTF export of a kit part into the pipeline (the `cad` route).

The converter (blender/onshape_import_bpy.py) makes the game-ready GLB; this module copies the export, runs the
converter, snaps the material names to palette roles, reads back what was made and writes the part's Godot scene.
The Blender run is the one function tests replace (`run_converter`); everything else is pure Python."""
from __future__ import annotations

import json
import os
import re
import struct
import subprocess
from pathlib import Path
from typing import Any

import yaml

from . import check, cleanup
from .fixture_mesh import glb_document
from .godot_stage import pascal

SCRIPT = Path(__file__).resolve().parent / "blender" / "onshape_import_bpy.py"
SCRIPT_REL = "tools/asset_pipeline/asset_pipeline/blender/onshape_import_bpy.py"
RESULT_PREFIX = "KIT_IMPORT_RESULT "
PALETTE_REL = "assets/palette/palette.tres"
ROLES_REL = "assets/palette/roles"
AXES = ("x", "y", "z")
PIVOT_NODE = "Pivot"
MEDIA_DIR = "assets/media/kit"
COLOUR_NAME = re.compile(r"^(\d*\.?\d+)_(\d*\.?\d+)_(\d*\.?\d+)(?:_.*)?$")

# Control scripts `export` can put on a part's scene. Each maps its manifest fields to scene properties.
CONTROLS = ("switch_lever", "none")
SWITCH_LEVER_SCRIPT = "res://src/interact/switch_lever.gd"
NOISE_PROFILE_SCRIPT = "res://src/interact/noise_profile.gd"
GRAB_LAYER = 2


# --- reading the CAD export ------------------------------------------------------------------------------------

def _gltf_document(path: Path) -> dict[str, Any]:
    if path.suffix.lower() == ".glb":
        return glb_document(path)[0]
    try:
        return json.loads(path.read_text())
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        raise ValueError(f"{path.name} is not a glTF file: {e}") from e


def part_names(path: Path) -> list[str]:
    """The names of the parts (mesh nodes) in a glTF export, in file order: what `--pivot` may name."""
    doc = _gltf_document(path)
    return [str(n.get("name", "")) for n in doc.get("nodes", []) if "mesh" in n and n.get("name")]


def external_files(path: Path) -> list[str]:
    """Relative files a .gltf refers to besides itself (data: URIs are embedded and need no copying)."""
    if path.suffix.lower() != ".gltf":
        return []
    doc = _gltf_document(path)
    uris = [x["uri"] for x in (*doc.get("buffers", []), *doc.get("images", [])) if x.get("uri")]
    return [u for u in uris if not u.startswith("data:")]


def check_pivot(part: str | None, parts: list[str], source: str) -> None:
    if part and part not in parts:
        raise ValueError(f"no part named {part!r} in {source}; the parts are: {', '.join(parts) or '(none)'}")


def check_pivot_fields(axis: str, limits: list[float], control: str) -> None:
    if axis not in AXES:
        raise ValueError(f"axis must be one of {', '.join(AXES)}, not {axis!r}")
    if len(limits) != 2 or not limits[0] < limits[1] or limits[0] < -180 or limits[1] > 180:
        raise ValueError(f"limits must be MIN MAX degrees with -180 <= MIN < MAX <= 180, not {limits}")
    if control not in CONTROLS:
        raise ValueError(f"control must be one of {', '.join(CONTROLS)}, not {control!r}")


# --- the palette -----------------------------------------------------------------------------------------------

def _swatches(root: Path) -> dict[str, list[float]]:
    """Every swatch of the game palette (paint and light) by name, as sRGB 0..1."""
    f = root / PALETTE_REL
    if not f.is_file():
        raise ValueError(f"no palette at {PALETTE_REL}")
    found = re.findall(r'&"([A-Za-z0-9_]+)":\s*Color\(([^)]*)\)', f.read_text())
    return {name: [float(c) for c in args.split(",")[:3]] for name, args in found}


def load_palette(root: Path) -> dict[str, list[float]]:
    """The colour each palette role (docs/palette.md) shows, by role name: what it glows, else its surface swatch.
    Colours come from `palette.tres` and the role files; nothing is copied, so a tuned swatch snaps differently."""
    swatches = _swatches(root)
    out: dict[str, list[float]] = {}
    for f in sorted((root / ROLES_REL).glob("*.tres")):
        fields = dict(re.findall(r'^(swatch|glow|stripe) = &"([A-Za-z0-9_]*)"$', f.read_text(), re.M))
        key = fields.get("glow") or fields.get("swatch")
        if key in swatches:
            out[f.stem] = swatches[key]
    if not out:
        raise ValueError(f"no palette roles under {ROLES_REL}")
    return out


def snap_colour(rgb: list[float], palette: dict[str, list[float]]) -> str:
    """The role whose colour is nearest to `rgb` (ties go to the earlier role)."""
    return min(palette, key=lambda role: sum((a - b) ** 2 for a, b in zip(rgb, palette[role][:3])))


def material_rgb(name: str, factor: list[float] | None) -> list[float] | None:
    """The RGB an Onshape material stands for: the one in its name, else its base colour factor."""
    m = COLOUR_NAME.match(name)
    if m:
        return [float(m.group(i)) for i in (1, 2, 3)]
    return list(factor[:3]) if factor else None


# --- GLB read and write ----------------------------------------------------------------------------------------

def read_glb(path: Path) -> tuple[dict[str, Any], bytes]:
    data = path.read_bytes()
    if data[:4] != b"glTF":
        raise ValueError(f"{path.name} is not a GLB")
    jlen = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blob = b""
    if off + 8 <= len(data):
        blen = struct.unpack_from("<I", data, off)[0]
        blob = data[off + 8:off + 8 + blen]
    return doc, blob


def write_glb(path: Path, doc: dict[str, Any], blob: bytes) -> None:
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    blob += b"\x00" * (-len(blob) % 4)
    body = struct.pack("<II", len(js), 0x4E4F534A) + js
    if blob:
        body += struct.pack("<II", len(blob), 0x004E4942) + blob
    path.write_bytes(b"glTF" + struct.pack("<II", 2, 12 + len(body)) + body)


def snap_materials(glb: Path, palette: dict[str, list[float]]) -> dict[str, str]:
    """Rewrite the GLB so each material is named by its nearest palette role and carries no colour: on import the shared
    post-import script gives the surface the role's material (docs/palette.md). Materials that
    snap to the same role merge into one. Returns {old material name: role}."""
    doc, blob = read_glb(glb)
    old = doc.get("materials", [])
    mapping: dict[str, str] = {}
    new: list[dict[str, Any]] = []
    index: dict[str, int] = {}
    remap: dict[int, int] = {}
    for i, mat in enumerate(old):
        pbr = mat.get("pbrMetallicRoughness", {})
        rgb = material_rgb(str(mat.get("name", "")), pbr.get("baseColorFactor"))
        role = snap_colour(rgb, palette) if rgb is not None else str(mat.get("name", ""))
        mapping[str(mat.get("name", ""))] = role
        if role not in index:
            index[role] = len(new)
            fixed = {**mat, "name": role}
            if rgb is not None:
                fixed["pbrMetallicRoughness"] = {"metallicFactor": 0.0}
            new.append(fixed)
        remap[i] = index[role]
    if old:
        doc["materials"] = new
        for mesh in doc.get("meshes", []):
            for prim in mesh.get("primitives", []):
                if "material" in prim:
                    prim["material"] = remap[prim["material"]]
    write_glb(glb, doc, blob)
    return mapping


def glb_nodes(glb: Path) -> list[dict[str, Any]]:
    return read_glb(glb)[0].get("nodes", [])


def find_pivot(glb: Path, part: str) -> dict[str, Any]:
    """The `Pivot` node of a converted GLB, which must be the parent of `part` and have an identity rotation."""
    nodes = glb_nodes(glb)
    pivot = next((n for n in nodes if n.get("name") == PIVOT_NODE), None)
    if pivot is None:
        raise ValueError(f"the converted mesh has no {PIVOT_NODE!r} node")
    kids = [str(nodes[c].get("name", "")) for c in pivot.get("children", [])]
    if part.replace(" ", "") not in kids:
        raise ValueError(f"the {PIVOT_NODE!r} node does not carry {part!r} (it carries: {', '.join(kids) or 'nothing'})")
    rot = pivot.get("rotation", [0, 0, 0, 1])
    if any(abs(a - b) > 1e-6 for a, b in zip(rot, [0, 0, 0, 1])):
        raise ValueError(f"the {PIVOT_NODE!r} node is rotated {rot}; it must be at identity rotation")
    return pivot


# --- running the converter -------------------------------------------------------------------------------------

def run_converter(root: Path, src: Path, dst: Path, pivot: str | None) -> dict[str, Any]:
    """Convert `src` (a glTF export) to `dst` (a GLB) in headless Blender. Returns the script's result plus how it
    ran: {blender_version, runner, image, script_sha256, ...}. Tests replace this function."""
    runner = cleanup.resolve_runner()
    args = [cleanup.rel_to_root(root, src), cleanup.rel_to_root(root, dst), pivot or "-"]
    if runner.kind == "docker":
        base = f"{cleanup.CONTAINER_ROOT}/"
        cmd = [runner.exe, "run", "--rm", *cleanup.docker_user_args(), "-v", f"{os.path.abspath(root)}:{cleanup.CONTAINER_ROOT}",
               "-w", cleanup.CONTAINER_ROOT, runner.image, "-b", "--factory-startup", "--python-exit-code", "1",
               "-P", base + SCRIPT_REL, "--", *[base + a if i < 2 else a for i, a in enumerate(args)]]
    else:
        cmd = [runner.exe, "-b", "--factory-startup", "--python-exit-code", "1", "-P", str(SCRIPT), "--",
               *[str(root / a) if i < 2 else a for i, a in enumerate(args)]]
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        if runner.kind == "docker":
            rc, out, err = cleanup._run_streaming(cmd, cleanup.BLENDER_TIMEOUT_S)
        else:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=cleanup.BLENDER_TIMEOUT_S)
            rc, out, err = proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired as e:
        raise ValueError(f"Blender import timed out after {cleanup.BLENDER_TIMEOUT_S}s") from e
    for line in out.splitlines():
        if line.startswith(RESULT_PREFIX) and dst.is_file():
            res = json.loads(line[len(RESULT_PREFIX):])
            return {**res, "runner": runner.kind, "image": cleanup.image_ref(runner),
                    "script_sha256": cleanup.script_digest(SCRIPT)}
    tail = "\n".join((out + err).strip().splitlines()[-12:])
    raise ValueError(f"Blender import failed (exit {rc}):\n{tail}")


def measure(glb: Path) -> dict[str, Any]:
    """Largest dimension (m) and triangle count of a converted GLB, read in pure Python."""
    mesh = check.load_mesh(glb)
    lo, hi = check.bounding_box(mesh["positions"], mesh["triangles"])
    return {"size_m": max(h - l for l, h in zip(lo, hi)), "triangles": len(mesh["triangles"]),
            "bbox": [list(lo), list(hi)]}


# --- the part's Godot scene ------------------------------------------------------------------------------------

def _f(v: float) -> str:
    return f"{v:.5g}"


def scene_text(slug: str, res_dir: str, glb: Path, pivot_part: str | None, limits_deg: list[float] | None,
               control: str) -> str:
    """The `<slug>.tscn` for a kit part: the model, the control script with its pivot path, and a grab box on layer 2."""
    box = measure(glb)["bbox"]
    size = [h - l for l, h in zip(*box)]
    centre = [(h + l) / 2 for l, h in zip(*box)]
    moving = bool(pivot_part) and control != "none"
    ext = ['[ext_resource type="PackedScene" path="%s/%s.glb" id="model"]' % (res_dir, slug)]
    sub: list[str] = []
    root_attrs = 'type="Node3D"'
    props = ""
    if moving:
        find_pivot(glb, pivot_part or "")
        ext.insert(0, f'[ext_resource type="Script" path="{SWITCH_LEVER_SCRIPT}" id="script"]')
        ext.append(f'[ext_resource type="Script" path="{NOISE_PROFILE_SCRIPT}" id="noise_script"]')
        sub.append('[sub_resource type="Resource" id="noise"]\nscript = ExtResource("noise_script")\n'
                   'idle_intensity = 0.0\nmax_intensity = 0.15\nclank_rate = 2.0\nexponent = 2.0')
        root_attrs = 'type="Node3D" node_paths=PackedStringArray("pivot")'
        lo, hi = limits_deg or [-40.0, 40.0]
        props = (f'\nscript = ExtResource("script")\nswing_deg = {_f(hi - lo)}\nnoise_profile = SubResource("noise")\n'
                 f'pivot = NodePath("Model/{PIVOT_NODE}")')
    sub.append('[sub_resource type="BoxShape3D" id="grab"]\nsize = Vector3(%s, %s, %s)' % tuple(_f(v) for v in size))
    steps = len(ext) + len(sub) + 1
    out = [f"[gd_scene load_steps={steps} format=3]\n", *ext, "", *[s + "\n" for s in sub],
           f'[node name="{pascal(slug)}" {root_attrs}]{props}\n',
           '[node name="Model" parent="." instance=ExtResource("model")]\n',
           '[node name="Grab" type="StaticBody3D" parent="."]\ncollision_layer = %d\ncollision_mask = 0\n' % GRAB_LAYER,
           '[node name="Shape" type="CollisionShape3D" parent="Grab"]\n'
           'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)\nshape = SubResource("grab")\n'
           % tuple(_f(v) for v in centre)]
    return "\n".join(out)
