"""Provider interfaces, the mock providers, and selection from providers.yaml."""
from __future__ import annotations

import hashlib
import os
import re
import struct
import zlib
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

import yaml

from . import check, fixture_mesh

DEFAULT_CONFIG = Path(__file__).resolve().parent.parent / "providers.yaml"
LOCAL_CONFIG = DEFAULT_CONFIG.with_name("providers.local.yaml")
KINDS = ("image", "three_d", "prompt_writer")


class ImageProvider(ABC):
    name: str
    model: str
    billing = "paid"  # "mock" and "subscription" are never priced from prices.yaml
    last_usage: dict[str, Any] | None = None  # usage of the latest call, as the provider reported it (cost.py)

    @abstractmethod
    def generate(self, prompt: str, references: list[Path], out: Path) -> Path:
        """Generate one image into `out`, conditioned on reference images."""

    @abstractmethod
    def edit(self, prompt: str, source: Path, references: list[Path], out: Path) -> Path:
        """Edit `source` per the prompt into `out`."""


class ThreeDProvider(ABC):
    name: str
    model: str
    billing = "paid"  # "mock" and "subscription" are never priced from prices.yaml
    last_usage: dict[str, Any] | None = None  # usage of the latest call, as the provider reported it (cost.py)
    views: tuple[str, ...] | None = None  # the provider entry's `views:`: the turnaround views `to3d` sends by default
    max_views: int = 4  # how many views one job takes; a single-image provider has 1
    options: dict[str, Any] = {}  # model options merged into the request body (entry `options:`, then `--option`)

    @abstractmethod
    def submit(self, views: list[Path]) -> str:
        """Start a job from multi-view input; returns a job id."""

    @abstractmethod
    def poll(self, job_id: str) -> str:
        """One of: pending, running, done, failed."""

    @abstractmethod
    def download(self, job_id: str, out: Path) -> Path:
        """Write the finished GLB to `out`."""

    def failure_reason(self, job_id: str) -> str:
        """Why a job ended `failed`, if the provider said; empty otherwise."""
        return ""


class PromptWriter(ABC):
    name: str
    model: str
    billing = "paid"  # "mock" and "subscription" are never priced from prices.yaml
    last_usage: dict[str, Any] | None = None  # usage of the latest call, as the provider reported it (cost.py)

    @abstractmethod
    def write_prompts(self, brief: str, style: str, notes: str, images: list[Path], n: int) -> list[str]:
        """Compose `n` image prompts."""

    @abstractmethod
    def write_brief(self, context: str, images: list[Path]) -> str:
        """Draft brief.md text from the locked concept and views."""


def _digest(*parts: Any) -> bytes:
    h = hashlib.sha256()
    for p in parts:
        h.update(str(p).encode())
        h.update(b"\0")
    return h.digest()


def _png(seed: bytes, size: int = 8) -> bytes:
    """A small valid solid-colour PNG derived from the seed."""
    row = b"\x00" + bytes(seed[:3]) * size
    raw = row * size

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")


class MockImageProvider(ImageProvider):
    name = "mock"
    billing = "mock"

    def __init__(self, model: str = "mock-image-1") -> None:
        self.model = model

    def generate(self, prompt: str, references: list[Path], out: Path) -> Path:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(_png(_digest("gen", self.model, prompt, *[r.name for r in references])))
        return out

    def edit(self, prompt: str, source: Path, references: list[Path], out: Path) -> Path:
        out.parent.mkdir(parents=True, exist_ok=True)
        view = re.search(r"Orthographic (front|left|back|right|top|bottom) view", prompt)
        if view:  # a turnaround view: the silhouette of the mock 3D provider's mesh, so the mock flow passes `check`
            pos, _, idx = fixture_mesh.mock_mesh()
            tris = [tuple(idx[k:k + 3]) for k in range(0, len(idx), 3)]
            check.write_mask_png(out, check.mesh_silhouette(pos, tris, view.group(1)))
            return out
        out.write_bytes(_png(_digest("edit", self.model, prompt, source.name, *[r.name for r in references])))
        return out


class MockThreeDProvider(ThreeDProvider):
    name = "mock"
    billing = "mock"
    max_views = 8

    def __init__(self, model: str = "mock-3d-1") -> None:
        self.model = model

    def submit(self, views: list[Path]) -> str:
        return "mock-" + _digest(self.model, *[v.name for v in views]).hex()[:12]

    def poll(self, job_id: str) -> str:
        return "done"

    def download(self, job_id: str, out: Path) -> Path:
        out.parent.mkdir(parents=True, exist_ok=True)
        fixture_mesh.write_glb(out, *fixture_mesh.mock_mesh())
        return out


class MockPromptWriter(PromptWriter):
    name = "mock"
    billing = "mock"

    def __init__(self, model: str = "mock-writer-1") -> None:
        self.model = model

    def write_prompts(self, brief: str, style: str, notes: str, images: list[Path], n: int) -> list[str]:
        tag = _digest(brief, style, notes).hex()[:8]
        return [f"[mock {tag}] variant {i + 1}/{n}: {brief}" + (f" | refine: {notes}" if notes else "") for i in range(n)]

    def write_brief(self, context: str, images: list[Path]) -> str:
        return f"# Brief (mock)\n\n{context}\n"


# name -> factory(model) per kind. Real adapters register here as they are added.
REGISTRY: dict[str, dict[str, Any]] = {
    "image": {"mock": MockImageProvider},
    "three_d": {"mock": MockThreeDProvider},
    "prompt_writer": {"mock": MockPromptWriter},
}


def local_config_path() -> Path:
    """The git-ignored per-machine override; ASSET_PROVIDERS_LOCAL points elsewhere (tests use it)."""
    env = os.environ.get("ASSET_PROVIDERS_LOCAL")
    return Path(env) if env else LOCAL_CONFIG


def load_config(path: Path | None = None, local: Path | None = None) -> dict[str, Any]:
    """The committed providers.yaml, with its `selection:` overridden key by key by providers.local.yaml.
    The local file is read only when `path` is the default config (or `local` is given). The result's
    `selection_source` maps each kind to "committed" or "local"."""
    cfg = yaml.safe_load((path or DEFAULT_CONFIG).read_text()) or {}
    for key in ("selection", "providers"):
        if not isinstance(cfg.get(key), dict):
            raise ValueError(f"providers.yaml: missing '{key}' mapping")
    cfg["selection_source"] = {kind: "committed" for kind in cfg["selection"]}
    local_file = local if local is not None else (local_config_path() if path is None else None)
    if local_file is not None and local_file.is_file():
        data = yaml.safe_load(local_file.read_text()) or {}
        if not isinstance(data, dict) or set(data) - {"selection"}:
            raise ValueError(f"{local_file.name}: only a 'selection:' mapping is allowed")
        sel = data.get("selection") or {}
        if not isinstance(sel, dict):
            raise ValueError(f"{local_file.name}: 'selection' must be a mapping")
        for kind, name in sel.items():
            if kind not in KINDS:
                raise ValueError(f"{local_file.name}: unknown provider kind {kind!r} (expected one of {', '.join(KINDS)})")
            if name not in (cfg["providers"].get(kind) or {}):
                known = ", ".join(sorted(cfg["providers"].get(kind) or {}))
                raise ValueError(f"{local_file.name}: {kind} provider {name!r} is not configured in providers.yaml (known: {known})")
            cfg["selection"][kind] = name
            cfg["selection_source"][kind] = "local"
    return cfg


def select(kind: str, config: dict[str, Any], override: str | None = None) -> Any:
    """Build the provider for `kind`: the command's override if given, else the configured default."""
    if kind not in KINDS:
        raise ValueError(f"unknown provider kind {kind!r}")
    from . import adapters, writers  # noqa: F401  register the real adapters
    name = override or config["selection"].get(kind)
    if not name:
        raise ValueError(f"no {kind} provider selected")
    entry = (config["providers"].get(kind) or {}).get(name)
    if entry is None:
        raise ValueError(f"{kind} provider {name!r} is not configured in providers.yaml")
    return build(kind, name, entry)


def build(kind: str, name: str, entry: Any) -> Any:
    """Instantiate a configured provider. An entry's `adapter:` picks the adapter class (default: its name),
    so a new provider on an existing adapter is a providers.yaml entry and nothing else."""
    opts = dict(entry) if isinstance(entry, dict) else {}
    adapter = opts.pop("adapter", None) or name
    views = opts.pop("views", None)  # 3D providers only: the turnaround views to send
    if views is not None:
        if kind != "three_d":
            raise ValueError(f"{kind} provider {name!r}: `views:` applies to three_d providers only")
        known = check.ALL_VIEWS
        if (not isinstance(views, list) or not views or len(set(views)) != len(views)
                or any(v not in known for v in views)):
            raise ValueError(f"three_d provider {name!r}: views must be a non-empty list of distinct names from "
                             f"{', '.join(known)}")
    max_views = opts.pop("max_views", None)
    options = opts.pop("options", None)
    if (max_views is not None or options is not None) and kind != "three_d":
        raise ValueError(f"{kind} provider {name!r}: `max_views:` and `options:` apply to three_d providers only")
    if max_views is not None and not (isinstance(max_views, int) and not isinstance(max_views, bool) and max_views >= 1):
        raise ValueError(f"three_d provider {name!r}: max_views must be a positive integer")
    if options is not None and not (isinstance(options, dict) and all(isinstance(k, str) for k in options)):
        raise ValueError(f"three_d provider {name!r}: options must be a mapping of names to values")
    factory = REGISTRY[kind].get(adapter)
    if factory is None:
        raise ValueError(f"{kind} provider {name!r} has no adapter {adapter!r}")
    p = factory(**opts)
    p.name = name
    if views is not None:
        p.views = tuple(views)
    if max_views is not None:
        p.max_views = max_views
    if views is not None and len(views) > p.max_views:
        raise ValueError(f"three_d provider {name!r}: views lists {len(views)} but it takes at most {p.max_views}")
    if options is not None:
        p.options = dict(options)
    return p
