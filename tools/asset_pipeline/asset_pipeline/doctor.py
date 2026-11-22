"""`asset doctor [--live]`: is this machine able to run the pipeline, and why not."""
from __future__ import annotations

import os
import shutil
from typing import Any

from . import providers
from .adapters._net import ImageProviderError, request


def _tool(env: str, default: str) -> tuple[bool, str]:
    cmd = os.environ.get(env) or default
    found = shutil.which(cmd)
    if found:
        return True, found
    return False, f"{cmd!r} not found on PATH (set {env} to its full path)"


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

    add("blender", *_tool("ASSET_BLENDER_BIN", "blender"))
    add("godot", *_tool("GODOT", "godot"))
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
    return {"ok": ok, "live": live, "checks": checks}
