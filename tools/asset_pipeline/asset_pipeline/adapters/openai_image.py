"""OpenAI GPT Image: /v1/images/generations, and /v1/images/edits when images go in."""
from __future__ import annotations

import base64
import os
from pathlib import Path

from ..providers import REGISTRY, ImageProvider
from . import _net
from ._net import ImageProviderError


class OpenAIImage(ImageProvider):
    name = "openai"
    env_key = "OPENAI_API_KEY"

    def __init__(self, model: str = "gpt-image-1", base_url: str = "https://api.openai.com",
                 size: str = "1024x1024", timeout: int = 180) -> None:
        self.model, self.base_url, self.size, self.timeout = model, base_url.rstrip("/"), size, timeout

    def _headers(self) -> dict[str, str]:
        key = os.environ.get(self.env_key)
        if not key:
            raise ImageProviderError(f"{self.env_key} is not set (add it to tools/asset_pipeline/.env)")
        return {"authorization": f"Bearer {key}"}

    def _save(self, reply: dict, out: Path) -> Path:
        items = reply.get("data") if isinstance(reply, dict) else None
        if not items or not isinstance(items[0], dict):
            raise ImageProviderError("openai reply has no image")
        item = items[0]
        if item.get("b64_json"):
            return _net.write_image(out, base64.b64decode(item["b64_json"]))
        if item.get("url"):
            return _net.write_image(out, _net.request("openai", item["url"], {}, timeout=self.timeout))
        raise ImageProviderError("openai reply has no image data")

    def _call(self, prompt: str, images: list[Path], out: Path) -> Path:
        headers = self._headers()
        if images:
            fields = {"model": self.model, "prompt": prompt, "size": self.size, "n": "1"}
            reply = _net.post_multipart("openai", self.base_url + "/v1/images/edits", headers, fields,
                                        [("image[]", p) for p in images], self.timeout)
        else:
            reply = _net.post_json("openai", self.base_url + "/v1/images/generations", headers,
                                   {"model": self.model, "prompt": prompt, "size": self.size, "n": 1}, self.timeout)
        return self._save(reply, out)

    def generate(self, prompt: str, references: list[Path], out: Path) -> Path:
        return self._call(prompt, references, out)

    def edit(self, prompt: str, source: Path, references: list[Path], out: Path) -> Path:
        return self._call(prompt, [source, *references], out)

    def live_check(self) -> str:
        """One cheap call: retrieve the model. Raises ImageProviderError on failure."""
        _net.request("openai", f"{self.base_url}/v1/models/{self.model}", self._headers(), timeout=self.timeout)
        return f"model {self.model} reachable"


REGISTRY["image"]["openai"] = OpenAIImage
