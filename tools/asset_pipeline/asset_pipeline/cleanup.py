"""`asset cleanup <slug> --source <run>`: headless Blender cleanup of a raw mesh, per the class profile."""
from __future__ import annotations

import hashlib
import json
import math
import os
import re
import shutil
import subprocess
import sys
import threading
from dataclasses import dataclass
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


RUNNER_ENV = "ASSET_BLENDER_RUNNER"
IMAGE_ENV = "ASSET_BLENDER_IMAGE"
IMAGE_REPO = "silent-water/blender-cleanup"
CONTAINER_ROOT = "/work"
# Where the script lives relative to the repo root: the container mounts only the root, so it runs it from there.
SCRIPT_REL = "tools/asset_pipeline/asset_pipeline/blender/cleanup_bpy.py"
NO_BLENDER_HINT = ("install Blender 4.5 LTS, set ASSET_BLENDER_BIN, or install Docker and run "
                   "`asset blender-image build`")


@dataclass
class Runner:
    kind: str  # "native" or "docker"
    exe: str  # the blender binary, or the docker client
    image: str = ""  # docker only


def blender_version() -> str:
    """The full Blender version the pipeline pins (versions.yaml)."""
    f = Path(__file__).resolve().parent.parent / "versions.yaml"
    return str(yaml.safe_load(f.read_text())["blender"]["version"])


def image_name() -> str:
    return os.environ.get(IMAGE_ENV) or f"{IMAGE_REPO}:{blender_version()}"


def _native() -> str | None:
    return shutil.which(os.environ.get(BLENDER_ENV) or "blender")


def docker_client() -> str | None:
    return shutil.which("docker")


def docker_reachable(exe: str) -> bool:
    try:
        return subprocess.run([exe, "info"], capture_output=True, timeout=30).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def resolve_runner() -> Runner:
    """Pick how to run Blender: $ASSET_BLENDER_RUNNER = native | docker | auto (default). `auto` prefers a local
    Blender ($ASSET_BLENDER_BIN, else `blender` on PATH), then Docker with a reachable daemon."""
    mode = (os.environ.get(RUNNER_ENV) or "auto").strip().lower()
    if mode not in ("native", "docker", "auto"):
        raise ValueError(f"{RUNNER_ENV} must be native, docker or auto, not {mode!r}")
    if mode in ("native", "auto"):
        found = _native()
        if found:
            return Runner("native", found)
        if mode == "native":
            cmd = os.environ.get(BLENDER_ENV) or "blender"
            raise BlenderUnavailable(f"Blender not found ({cmd!r} is not on PATH): install Blender 4.5 LTS "
                                     f"or set {BLENDER_ENV} to its full path")
    docker = docker_client()
    if mode == "docker":
        if not docker:
            raise BlenderUnavailable(f"{RUNNER_ENV}=docker but the docker client is not on PATH: install Docker "
                                     "and run `asset blender-image build`")
        if not docker_reachable(docker):
            raise BlenderUnavailable(f"{RUNNER_ENV}=docker but the Docker daemon is not reachable: start Docker")
        return Runner("docker", docker, image_name())
    if docker and docker_reachable(docker):
        return Runner("docker", docker, image_name())
    raise BlenderUnavailable(f"Blender not found: {NO_BLENDER_HINT}")


def image_ref(runner: Runner) -> str:
    """The image reference plus its digest when the daemon reports one (empty for the native runner)."""
    if runner.kind != "docker":
        return ""
    try:
        r = subprocess.run([runner.exe, "image", "inspect", "--format", "{{json .RepoDigests}}|{{.Id}}", runner.image],
                           capture_output=True, text=True, timeout=30)
        if r.returncode == 0:
            digests, _, ident = r.stdout.strip().partition("|")
            digest = (json.loads(digests or "[]") or [""])[0].partition("@")[2] or ident
            if digest:
                return f"{runner.image}@{digest}"
    except (OSError, subprocess.SubprocessError, ValueError):
        pass
    return runner.image


def rel_to_root(root: Path, path: Path) -> str:
    """`path` as a POSIX path relative to the repo root; a path outside the root cannot be mounted."""
    try:
        return Path(os.path.abspath(path)).relative_to(os.path.abspath(root)).as_posix()
    except ValueError:
        raise ValueError(f"{path} is outside the repo root {root}: cleanup can only read and write inside the repo") from None


def docker_user_args() -> list[str]:
    """`--user uid:gid` on Linux and macOS so files written under .asset_work/ belong to the caller; Docker Desktop
    on Windows already writes bind-mounted files as the host user."""
    if sys.platform == "win32" or not hasattr(os, "getuid"):
        return []
    return ["--user", f"{os.getuid()}:{os.getgid()}"]


def docker_command(runner: Runner, root: Path, params_rel: str) -> list[str]:
    """The `docker run` line. No -e, --env-file or secrets: only the repo root is mounted."""
    return [runner.exe, "run", "--rm", *docker_user_args(), "-v", f"{os.path.abspath(root)}:{CONTAINER_ROOT}",
            "-w", CONTAINER_ROOT, runner.image, "-b", "--factory-startup", "-P", f"{CONTAINER_ROOT}/{SCRIPT_REL}",
            "--", f"{CONTAINER_ROOT}/{params_rel}"]


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


def script_digest(script: Path = SCRIPT) -> str:
    return hashlib.sha256(script.read_bytes()).hexdigest()


def _run_streaming(cmd: list[str], timeout: float) -> tuple[int, str, str]:
    """Run `cmd`, forwarding stderr lines to our stderr as they arrive (image pulls, Blender logs)."""
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    err: list[str] = []

    def pump() -> None:
        for line in proc.stderr:  # type: ignore[union-attr]
            err.append(line)
            print(line.rstrip("\n"), file=sys.stderr, flush=True)

    t = threading.Thread(target=pump, daemon=True)
    t.start()
    out: list[str] = []
    reader = threading.Thread(target=lambda: out.append(proc.stdout.read()), daemon=True)  # type: ignore[union-attr]
    reader.start()
    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        raise
    finally:
        t.join(5)
        reader.join(5)
    return proc.returncode, "".join(out), "".join(err)


def run_blender(params: dict[str, Any], workdir: Path, runner: Runner | None = None, root: Path | None = None) -> dict[str, Any]:
    """Run the cleanup script. `params` carries repo-relative POSIX paths; `root` (added here) is the repo root as
    the runner sees it, so the native and Docker runners read the same params apart from that one field."""
    runner = runner or resolve_runner()
    if root is None:
        root = workdir
        while root.parent != root and not (root / "project.godot").exists():
            root = root.parent
    workdir.mkdir(parents=True, exist_ok=True)
    pfile = workdir / "cleanup_params.json"
    params = {**params, "root": CONTAINER_ROOT if runner.kind == "docker" else Path(os.path.abspath(root)).as_posix()}
    pfile.write_text(json.dumps(params, indent=2))
    try:
        if runner.kind == "docker":
            rc, stdout, stderr = _run_streaming(docker_command(runner, root, rel_to_root(root, pfile)), BLENDER_TIMEOUT_S)
        else:
            proc = subprocess.run([runner.exe, "-b", "--factory-startup", "-P", str(SCRIPT), "--", str(pfile)],
                                  capture_output=True, text=True, timeout=BLENDER_TIMEOUT_S)
            rc, stdout, stderr = proc.returncode, proc.stdout, proc.stderr
    except subprocess.TimeoutExpired as e:
        raise ValueError(f"Blender cleanup timed out after {BLENDER_TIMEOUT_S}s") from e
    for line in stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            return json.loads(line[len(RESULT_PREFIX):])
    tail = "\n".join((stdout + stderr).strip().splitlines()[-12:])
    hint = ""
    if runner.kind == "docker" and ("Unable to find image" in stderr or "pull access denied" in stderr):
        hint = f"\nThe image {runner.image} is missing: run `asset blender-image build`"
    raise ValueError(f"Blender cleanup failed (exit {rc}):\n{tail}{hint}")
