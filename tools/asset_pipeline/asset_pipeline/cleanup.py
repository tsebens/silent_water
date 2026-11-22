"""`asset cleanup <slug> --source <run>`: headless Blender cleanup of a raw mesh, per the class profile."""
from __future__ import annotations

import hashlib
import json
import math
import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

import yaml

SCRIPT = Path(__file__).resolve().parent / "blender" / "cleanup_bpy.py"
RESULT_PREFIX = "ASSET_CLEANUP_RESULT "
BLENDER_ENV = "ASSET_BLENDER_BIN"
BLENDER_TIMEOUT_S = 900
SIZE_RE = re.compile(r"^\s*[-*]?\s*(?:\*\*)?size_m(?:\*\*)?\s*:\s*(.+?)\s*$", re.IGNORECASE | re.MULTILINE)


class BlenderUnavailable(ValueError):
    pass


def find_blender() -> str:
    """$ASSET_BLENDER_BIN (set in the shell or tools/asset_pipeline/.env), else `blender` on PATH."""
    cmd = os.environ.get(BLENDER_ENV) or "blender"
    found = shutil.which(cmd)
    if not found:
        raise BlenderUnavailable(f"Blender not found ({cmd!r} is not on PATH): install Blender 4.5 LTS "
                                 f"or set {BLENDER_ENV} to its full path")
    return found


def class_profile(root: Path, asset_class: str) -> dict[str, Any]:
    f = root / "assets" / "style_bible" / "classes.yaml"
    if not f.is_file():
        raise ValueError(f"no class profiles at {f}")
    prof = (yaml.safe_load(f.read_text()) or {}).get("classes", {}).get(asset_class)
    if not prof:
        raise ValueError(f"no class profile for {asset_class!r} in {f}")
    return prof


def brief_size_m(brief_path: Path | None, profile: dict[str, Any]) -> tuple[float, str]:
    """The asset's largest dimension in metres: a `size_m: 2.5` line in brief.md (the largest of up to three
    numbers), else the geometric middle of the class's scale range. Returns (size, where it came from)."""
    if brief_path is not None and brief_path.is_file():
        m = SIZE_RE.search(brief_path.read_text())
        if m:
            nums = [float(x) for x in re.findall(r"\d+(?:\.\d+)?", m.group(1))]
            if nums:
                return max(nums), "brief"
    lo, hi = profile["scale_range_m"]
    return math.sqrt(lo * hi), "class scale range"


def code_commit(root: Path) -> str:
    """Git commit of the checkout that ran the cleanup (empty outside a git checkout)."""
    try:
        out = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True, timeout=20)
        return out.stdout.strip() if out.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def script_digest() -> str:
    return hashlib.sha256(SCRIPT.read_bytes()).hexdigest()


def run_blender(params: dict[str, Any], workdir: Path) -> dict[str, Any]:
    blender = find_blender()
    workdir.mkdir(parents=True, exist_ok=True)
    pfile = workdir / "cleanup_params.json"
    pfile.write_text(json.dumps(params, indent=2))
    try:
        proc = subprocess.run([blender, "-b", "--factory-startup", "-P", str(SCRIPT), "--", str(pfile)],
                              capture_output=True, text=True, timeout=BLENDER_TIMEOUT_S)
    except subprocess.TimeoutExpired as e:
        raise ValueError(f"Blender cleanup timed out after {BLENDER_TIMEOUT_S}s") from e
    for line in proc.stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    tail = "\n".join((proc.stdout + proc.stderr).strip().splitlines()[-12:])
    raise ValueError(f"Blender cleanup failed (exit {proc.returncode}):\n{tail}")
