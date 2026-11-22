"""`godot-check` and `export`: Godot import of the cleaned GLB, game-lighting renders, and the committed deliverable."""
from __future__ import annotations

import json
import os
import shutil
import struct
import subprocess
import zlib
from pathlib import Path
from typing import Any

from . import check, paths

IMPORT_SCRIPT = "res://assets/import/vertex_color_import.gd"
CHECK_SCRIPT = "res://tools/asset_pipeline/asset_pipeline/godot/godot_check.gd"
MAX_CONCEPT_PX = 2048
MAX_FILE_BYTES = 5 * 1024 * 1024
MARK = "ASSET_CHECK:"


def find_godot() -> str:
    cmd = os.environ.get("GODOT") or "godot"
    found = shutil.which(cmd)
    if not found:
        raise ValueError(f"Godot not found ({cmd!r}): set GODOT to its full path")
    return found


def import_stub(res_dir: str, name: str) -> str:
    """A minimal `<name>.glb.import` that selects the shared post-import script. Godot fills in the rest."""
    return ('[remap]\n\nimporter="scene"\nimporter_version=1\ntype="PackedScene"\n\n'
            f'[deps]\n\nsource_file="{res_dir}/{name}.glb"\n\n'
            f'[params]\n\nimport_script/path="{IMPORT_SCRIPT}"\n')


def _run_godot(godot: str, root: Path, args: list[str], timeout: float, log: Path) -> subprocess.CompletedProcess[str]:
    cmd = [godot, "--path", str(root), *args]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as e:
        raise ValueError(f"Godot timed out after {timeout:g} s: {' '.join(cmd)}") from e
    log.write_text((proc.stdout or "") + (proc.stderr or ""))
    return proc


def _result(proc: subprocess.CompletedProcess[str]) -> dict[str, Any]:
    for line in (proc.stdout or "").splitlines():
        if line.startswith(MARK):
            return json.loads(line[len(MARK):])
    tail = ((proc.stdout or "") + (proc.stderr or "")).strip().splitlines()[-5:]
    return {"ok": False, "error": "Godot printed no result: " + " | ".join(tail)}


def godot_check(root: Path, slug: str, glb: Path, log_dir: Path, render: bool = True, timeout: float = 300.0) -> dict[str, Any]:
    """Import `glb` through the shared post-import script, verify the material flag and render three shots."""
    godot = find_godot()
    log_dir.mkdir(parents=True, exist_ok=True)
    stage = root / "build" / "asset_check" / slug
    shutil.rmtree(stage, ignore_errors=True)
    stage.mkdir(parents=True)
    shutil.copy(glb, stage / f"{slug}.glb")
    res_dir = f"res://build/asset_check/{slug}"
    (stage / f"{slug}.glb.import").write_text(import_stub(res_dir, slug))
    try:
        imp = _run_godot(godot, root, ["--headless", "--import", "--quit"], timeout, log_dir / f"{slug}_import.log")
        if imp.returncode != 0:
            raise ValueError(f"Godot import failed (see {log_dir / (slug + '_import.log')})")
        model = f"{res_dir}/{slug}.glb"
        ver = _result(_run_godot(godot, root, ["--headless", "--script", CHECK_SCRIPT, "--", "verify", model, ""],
                                 timeout, log_dir / f"{slug}_verify.log"))
        out: dict[str, Any] = {"ok": bool(ver.get("ok")), "import_script": IMPORT_SCRIPT, "material": ver, "renders": []}
        if render:
            prefix = str(log_dir / slug)
            cmd = ["--script", CHECK_SCRIPT, "--", "render", model, prefix]
            if not os.environ.get("DISPLAY") and shutil.which("xvfb-run"):
                rproc = _xvfb(godot, root, cmd, timeout, log_dir / f"{slug}_render.log")
            else:
                rproc = _run_godot(godot, root, cmd, timeout, log_dir / f"{slug}_render.log")
            r = _result(rproc)
            out["renders"] = r.get("renders", [])
            if not r.get("ok"):
                out["ok"] = False
                out["render_error"] = r.get("error", "render failed")
        return out
    finally:
        shutil.rmtree(root / "build" / "asset_check" / slug, ignore_errors=True)


def _xvfb(godot: str, root: Path, args: list[str], timeout: float, log: Path) -> subprocess.CompletedProcess[str]:
    cmd = ["xvfb-run", "-a", godot, "--path", str(root), *args]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as e:
        raise ValueError(f"Godot render timed out after {timeout:g} s") from e
    log.write_text((proc.stdout or "") + (proc.stderr or ""))
    return proc


# --- export -----------------------------------------------------------------------------------------------------

def png_size(path: Path) -> tuple[int, int]:
    head = path.read_bytes()[:24]
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path.name} is not a PNG")
    return struct.unpack(">II", head[16:24])


def downscale_png(src: Path, dst: Path, max_px: int = MAX_CONCEPT_PX) -> bool:
    """Copy `src` to `dst`, shrinking by box sampling so the longest side is at most `max_px`. Returns True if resized.
    Only PNGs can be resized (no imaging library is a dependency); larger WebP/JPEG fail with a clear error."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.suffix.lower() != ".png":
        if max(_other_size(src)) > max_px:
            raise ValueError(f"{src.name} is larger than {max_px} px and is not a PNG, so it cannot be resized here")
        shutil.copy(src, dst)
        return False
    w, h = png_size(src)
    if max(w, h) <= max_px:
        shutil.copy(src, dst)
        return False
    _, _, rows = check.read_png(src)
    k = max(w, h) / max_px
    nw, nh = max(1, int(w / k)), max(1, int(h / k))
    ch = len(rows[0][0])
    out = bytearray()
    for y in range(nh):
        y0, y1 = int(y * k), max(int(y * k) + 1, int((y + 1) * k))
        out.append(0)
        for x in range(nw):
            x0, x1 = int(x * k), max(int(x * k) + 1, int((x + 1) * k))
            cells = [rows[yy][xx] for yy in range(y0, min(y1, h)) for xx in range(x0, min(x1, w))]
            out += bytes(sum(c[i] for c in cells) // len(cells) for i in range(ch))
    ctype = {1: 0, 2: 4, 3: 2, 4: 6}[ch]

    def chunk(kind: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    dst.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", nw, nh, 8, ctype, 0, 0, 0))
                    + chunk(b"IDAT", zlib.compress(bytes(out))) + chunk(b"IEND", b""))
    return True


def _other_size(path: Path) -> tuple[int, int]:
    """Dimensions of a JPEG or WebP, enough to enforce the 2048 px limit."""
    data = path.read_bytes()
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        if data[12:16] == b"VP8X":
            return (int.from_bytes(data[24:27], "little") + 1, int.from_bytes(data[27:30], "little") + 1)
        if data[12:16] == b"VP8 ":
            return (struct.unpack("<H", data[26:28])[0] & 0x3FFF, struct.unpack("<H", data[28:30])[0] & 0x3FFF)
        if data[12:16] == b"VP8L":
            b = int.from_bytes(data[21:25], "little")
            return ((b & 0x3FFF) + 1, ((b >> 14) & 0x3FFF) + 1)
    if data[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
                h, w = struct.unpack(">HH", data[i + 5:i + 9])
                return w, h
            i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
    raise ValueError(f"cannot read the size of {path.name}")


def pascal(slug: str) -> str:
    return "".join(p.capitalize() for p in slug.split("_") if p) or "Asset"


def tscn(slug: str) -> str:
    return ('[gd_scene load_steps=2 format=3]\n\n'
            f'[ext_resource type="PackedScene" path="res://assets/models/{slug}/{slug}.glb" id="1_model"]\n\n'
            f'[node name="{pascal(slug)}" type="Node3D"]\n\n'
            '[node name="Model" parent="." instance=ExtResource("1_model")]\n')


def oversize(root: Path, limit: int = MAX_FILE_BYTES) -> list[str]:
    return [p.relative_to(root).as_posix() for p in sorted((root / "assets").rglob("*")) if p.is_file() and p.stat().st_size > limit]


def shrink_in_place(path: Path, max_px: int = MAX_CONCEPT_PX) -> bool:
    tmp = path.with_name("_resize" + path.suffix)
    try:
        if downscale_png(path, tmp, max_px):
            tmp.replace(path)
            return True
        return False
    finally:
        tmp.unlink(missing_ok=True)
