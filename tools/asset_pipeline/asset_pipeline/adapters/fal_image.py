"""Generic fal.ai image endpoint (FLUX, Seedream, Recraft, ...): the model is the endpoint id.

Reference images go in `image_urls` as data URIs. Models whose edit endpoint differs from the
generate endpoint set `edit_model` in providers.yaml.
"""
from __future__ import annotations

import base64
import os
from pathlib import Path

from ..providers import REGISTRY, ImageProvider
from . import _net
from ._net import ImageProviderError


class FalImage(ImageProvider):
    name = "fal"
    env_key = "FAL_KEY"

    def __init__(self, model: str = "fal-ai/flux-pro/v1.1", edit_model: str | None = None,
                 base_url: str = "https://fal.run", timeout: int = 300) -> None:
        self.model, self.edit_model, self.base_url, self.timeout = model, edit_model, base_url.rstrip("/"), timeout

    def _headers(self) -> dict[str, str]:
        key = os.environ.get(self.env_key)
        if not key:
            raise ImageProviderError(f"{self.env_key} is not set (add it to tools/asset_pipeline/.env)")
        return {"authorization": f"Key {key}"}

    def _call(self, endpoint: str, prompt: str, images: list[Path], out: Path) -> Path:
        payload: dict = {"prompt": prompt, "num_images": 1}
        if images:
            payload["image_urls"] = [_net.data_uri(p) for p in images]
        reply = _net.post_json("fal", f"{self.base_url}/{endpoint}", self._headers(), payload, self.timeout)
        self.last_usage = {"images": 1}  # fal reports no usage: one image requested, priced per image
        items = reply.get("images") if isinstance(reply, dict) else None
        url = items[0].get("url") if items and isinstance(items[0], dict) else None
        if not url:
            raise ImageProviderError("fal reply has no image")
        if url.startswith("data:"):
            return _net.write_image(out, base64.b64decode(url.split(",", 1)[1]))
        return _net.write_image(out, _net.request("fal", url, {}, timeout=self.timeout))

    def generate(self, prompt: str, references: list[Path], out: Path) -> Path:
        return self._call(self.model, prompt, references, out)

    def edit(self, prompt: str, source: Path, references: list[Path], out: Path) -> Path:
        return self._call(self.edit_model or self.model, prompt, [source, *references], out)

    def live_check(self) -> str:
        """fal has no free auth endpoint: an empty body is rejected (422) only after auth passes."""
        _net.request("fal", f"{self.base_url}/{self.model}", {**self._headers(), "content-type": "application/json"},
                     b"{}", self.timeout, ok_status=(422,))
        return f"endpoint {self.model} accepts the key"


REGISTRY["image"]["fal"] = FalImage
