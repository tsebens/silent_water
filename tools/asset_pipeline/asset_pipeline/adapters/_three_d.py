"""Shared plumbing for the image-to-3D adapters: keys, GLB download and validation."""
from __future__ import annotations

import os
from pathlib import Path

from ..providers import ThreeDProvider
from . import _net
from ._net import ImageProviderError


class ThreeDProviderError(ImageProviderError):
    """A hosted image-to-3D provider could not produce a mesh."""


class HostedThreeD(ThreeDProvider):
    """Base for keyed hosted providers. Subclasses set `env_key` and implement submit/poll/download."""
    env_key = ""
    timeout = 300

    def __init__(self) -> None:
        self.failures: dict[str, str] = {}

    def _key(self) -> str:
        key = os.environ.get(self.env_key)
        if not key:
            raise ThreeDProviderError(f"{self.env_key} is not set (add it to tools/asset_pipeline/.env)")
        return key

    def _check_views(self, views: list[Path]) -> None:
        if not views:
            raise ThreeDProviderError(f"{self.name}: no views to submit")
        for v in views:
            _net.mime_of(v)

    def failure_reason(self, job_id: str) -> str:
        return self.failures.get(job_id, "")

    def _fetch_glb(self, url: str, out: Path) -> Path:
        """Download a result URL (signed, so unauthenticated) and check it is a GLB."""
        if not url:
            raise ThreeDProviderError(f"{self.name} reply has no model url")
        data = _net.request(self.name, url, {}, timeout=self.timeout)
        if data[:4] != b"glTF":
            raise ThreeDProviderError(f"{self.name} download is not a GLB")
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(data)
        return out
