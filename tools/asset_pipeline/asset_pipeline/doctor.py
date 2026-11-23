"""`asset doctor [--live]`: is this machine able to run the pipeline, and why not."""
from __future__ import annotations

import os
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

import yaml

from . import providers
from .adapters._net import ImageProviderError, request


def _tool(env: str, default: str) -> tuple[bool, str]:
    cmd = os.environ.get(env) or default
    found = shutil.which(cmd)
    if found:
        return True, found
    return False, f"{cmd!r} not found on PATH (set {env} to its full path)"


def expected_versions() -> dict[str, Any]:
    return yaml.safe_load((Path(__file__).resolve().parent.parent / "versions.yaml").read_text())


def _version_output(exe: str) -> str:
    try:
        r = subprocess.run([exe, "--version"], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError) as e:
        return f"(could not run: {e})"
    lines = (r.stdout.strip() or r.stderr.strip()).splitlines()
    return lines[0] if lines else ""


def _versioned(env: str, default: str, kind: str) -> tuple[bool, str]:
    """`_tool`, then compare `<exe> --version` with versions.yaml; the detail names found and expected."""
    ok, detail = _tool(env, default)
    if not ok:
        return ok, detail
    want = expected_versions()[kind]
    out = _version_output(detail)
    if kind == "blender":
        m = re.search(r"Blender\s+(\d+)\.(\d+)", out)
        found = f"{m.group(1)}.{m.group(2)}" if m else None
        expected = f"Blender {want['major_minor']}.x"
        good = found == want["major_minor"]
    else:
        m = re.match(r"(\d+\.\d+(?:\.\d+)?)\.(\w+)\.(mono\.)?", out)
        found = f"{m.group(1)}{' .NET' if m.group(3) else ' standard'}" if m else None
        expected = f"Godot {want['version']} standard (non-.NET)"
        good = bool(m) and m.group(1) == want["version"] and not m.group(3)
    if good:
        return True, f"{detail} ({out})"
    return False, f"found {out or 'no version output'!r} at {detail}; expected {expected}"


def _blender_check() -> tuple[bool, str]:
    """The `blender` check for whichever runner `asset cleanup` would use."""
    from . import cleanup
    try:
        runner = cleanup.resolve_runner()
    except ValueError as e:
        return False, str(e)
    if runner.kind == "native":
        return _versioned("ASSET_BLENDER_BIN", "blender", "blender")
    try:
        have = subprocess.run([runner.exe, "image", "inspect", runner.image], capture_output=True, timeout=30).returncode == 0
    except (OSError, subprocess.SubprocessError):
        have = False
    if not have:
        return False, f"docker: image {runner.image} not found: run `asset blender-image build`"
    try:
        r = subprocess.run([runner.exe, "run", "--rm", runner.image, "--version"], capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.SubprocessError) as e:
        return False, f"docker: could not run {runner.image}: {e}"
    out = (r.stdout.strip() or r.stderr.strip()).splitlines()
    out_line = out[0] if out else ""
    m = re.search(r"Blender\s+(\d+)\.(\d+)", out_line)
    want = expected_versions()["blender"]["major_minor"]
    if m and f"{m.group(1)}.{m.group(2)}" == want:
        return True, f"docker: {runner.image}, {out_line}"
    return False, f"docker: {runner.image} reports {out_line or 'no version output'!r}; expected Blender {want}.x"


def _anthropic_live(base_url: str = "https://api.anthropic.com") -> str:
    request("anthropic-api", base_url + "/v1/models?limit=1",
            {"x-api-key": os.environ["ANTHROPIC_API_KEY"], "anthropic-version": "2023-06-01"}, timeout=30)
    return "models list reachable"


def run(config: dict[str, Any], live: bool = False) -> dict[str, Any]:
    """Each check is {name, ok, detail, required}. `required` marks what the selected defaults need;
    other configured providers are reported but do not fail the run."""
    from . import adapters, writers  # noqa: F401
    checks: list[dict[str, Any]] = []

    def add(name: str, ok: bool, detail: str, required: bool = True) -> None:
        checks.append({"name": name, "ok": ok, "detail": detail, "required": required})

    add("blender", *_blender_check())
    add("godot", *_versioned("GODOT", "godot", "godot"))
    selected = config.get("selection", {})
    for kind, entries in config["providers"].items():
        for name, entry in (entries or {}).items():
            if name == "mock":
                continue
            required = selected.get(kind) == name
            try:
                prov = providers.build(kind, name, entry)
            except (ValueError, TypeError) as e:
                add(f"{kind}:{name}", False, f"cannot build provider: {e}", required)
                continue
            key = getattr(prov, "env_key", None)
            if key is None:  # a local CLI rather than a keyed API
                add("claude CLI", *_tool("ASSET_CLAUDE_BIN", "claude"), required=required)
                continue
            if not os.environ.get(key):
                add(f"{kind}:{name} key", False, f"{key} is not set", required)
                continue
            add(f"{kind}:{name} key", True, f"{key} is set", required)
            if live:
                try:
                    detail = prov.live_check() if hasattr(prov, "live_check") else _anthropic_live()
                    add(f"{kind}:{name} live", True, detail, required)
                except ImageProviderError as e:
                    add(f"{kind}:{name} live", False, str(e), required)
    ok = all(c["ok"] for c in checks if c["required"])
    return {"ok": ok, "live": live, "selected": dict(selected),
            "selected_source": dict(config.get("selection_source", {})), "checks": checks}
