"""Provider interfaces, the mock providers, and selection from providers.yaml."""
from __future__ import annotations

import hashlib
import json
import struct
import zlib
from abc import ABC, abstractmethod
from pathlib import Path
from typing import Any

import yaml

DEFAULT_CONFIG = Path(__file__).resolve().parent.parent / "providers.yaml"
KINDS = ("image", "three_d", "prompt_writer")


class ImageProvider(ABC):
    name: str
    model: str

    @abstractmethod
    def generate(self, prompt: str, references: list[Path], out: Path) -> Path:
        """Generate one image into `out`, conditioned on reference images."""

    @abstractmethod
    def edit(self, prompt: str, source: Path, references: list[Path], out: Path) -> Path:
        """Edit `source` per the prompt into `out`."""


class ThreeDProvider(ABC):
    name: str
    model: str

    @abstractmethod
    def submit(self, views: list[Path]) -> str:
        """Start a job from multi-view input; returns a job id."""

    @abstractmethod
    def poll(self, job_id: str) -> str:
        """One of: pending, running, done, failed."""

    @abstractmethod
    def download(self, job_id: str, out: Path) -> Path:
        """Write the finished GLB to `out`."""


class PromptWriter(ABC):
    name: str
    model: str

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


def _glb(seed: bytes) -> bytes:
    """A minimal valid GLB containing one triangle, scaled slightly by the seed."""
    s = 1.0 + seed[0] / 255.0
    pos = struct.pack("<9f", 0, 0, 0, s, 0, 0, 0, s, 0)
    doc = {
        "asset": {"version": "2.0"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
                       "min": [0, 0, 0], "max": [s, s, 0]}],
        "bufferViews": [{"buffer": 0, "byteLength": len(pos)}],
        "buffers": [{"byteLength": len(pos)}],
    }
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    total = 12 + 8 + len(js) + 8 + len(pos)
    return (struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<I4s", len(js), b"JSON") + js
            + struct.pack("<I4s", len(pos), b"BIN\0") + pos)


class MockImageProvider(ImageProvider):
    name = "mock"

    def __init__(self, model: str = "mock-image-1") -> None:
        self.model = model

    def generate(self, prompt: str, references: list[Path], out: Path) -> Path:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(_png(_digest("gen", self.model, prompt, *[r.name for r in references])))
        return out

    def edit(self, prompt: str, source: Path, references: list[Path], out: Path) -> Path:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(_png(_digest("edit", self.model, prompt, source.name, *[r.name for r in references])))
        return out


class MockThreeDProvider(ThreeDProvider):
    name = "mock"

    def __init__(self, model: str = "mock-3d-1") -> None:
        self.model = model

    def submit(self, views: list[Path]) -> str:
        return "mock-" + _digest(self.model, *[v.name for v in views]).hex()[:12]

    def poll(self, job_id: str) -> str:
        return "done"

    def download(self, job_id: str, out: Path) -> Path:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(_glb(_digest(job_id)))
        return out


class MockPromptWriter(PromptWriter):
    name = "mock"

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


def load_config(path: Path | None = None) -> dict[str, Any]:
    cfg = yaml.safe_load((path or DEFAULT_CONFIG).read_text()) or {}
    for key in ("selection", "providers"):
        if not isinstance(cfg.get(key), dict):
            raise ValueError(f"providers.yaml: missing '{key}' mapping")
    return cfg


def select(kind: str, config: dict[str, Any], override: str | None = None) -> Any:
    """Build the provider for `kind`: the command's override if given, else the configured default."""
    if kind not in KINDS:
        raise ValueError(f"unknown provider kind {kind!r}")
    from . import writers  # noqa: F401  registers the real prompt writers
    name = override or config["selection"].get(kind)
    if not name:
        raise ValueError(f"no {kind} provider selected")
    entry = (config["providers"].get(kind) or {}).get(name)
    if entry is None:
        raise ValueError(f"{kind} provider {name!r} is not configured in providers.yaml")
    factory = REGISTRY[kind].get(name)
    if factory is None:
        raise ValueError(f"{kind} provider {name!r} has no adapter")
    return factory(**entry) if isinstance(entry, dict) else factory()
