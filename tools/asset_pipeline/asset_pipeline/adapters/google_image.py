"""Google Nano Banana (Gemini image models) through generateContent."""
from __future__ import annotations

import base64
import os
from pathlib import Path

from ..providers import REGISTRY, ImageProvider
from . import _net
from ._net import ImageProviderError


class GoogleImage(ImageProvider):
    name = "google"
    env_key = "GEMINI_API_KEY"

    def __init__(self, model: str = "gemini-nano-banana-2.1",
                 base_url: str = "https://generativelanguage.googleapis.com", timeout: int = 180) -> None:
        self.model, self.base_url, self.timeout = model, base_url.rstrip("/"), timeout

    def _headers(self) -> dict[str, str]:
        key = os.environ.get(self.env_key)
        if not key:
            raise ImageProviderError(f"{self.env_key} is not set (add it to tools/asset_pipeline/.env)")
        return {"x-goog-api-key": key}

    def _call(self, prompt: str, images: list[Path], out: Path) -> Path:
        parts: list[dict] = [{"inline_data": {"mime_type": _net.mime_of(p), "data": _net.b64_of(p)}} for p in images]
        parts.append({"text": prompt})
        reply = _net.post_json("google", f"{self.base_url}/v1beta/models/{self.model}:generateContent",
                               self._headers(), {"contents": [{"parts": parts}],
                                                 "generationConfig": {"responseModalities": ["IMAGE"]}}, self.timeout)
        for cand in (reply.get("candidates") or []) if isinstance(reply, dict) else []:
            for part in (cand.get("content") or {}).get("parts") or []:
                blob = part.get("inlineData") or part.get("inline_data")
                if blob and blob.get("data"):
                    return _net.write_image(out, base64.b64decode(blob["data"]))
        reason = ((reply.get("promptFeedback") or {}).get("blockReason") if isinstance(reply, dict) else None)
        raise ImageProviderError("google reply has no image" + (f" (blocked: {reason})" if reason else ""))

    def generate(self, prompt: str, references: list[Path], out: Path) -> Path:
        return self._call(prompt, references, out)

    def edit(self, prompt: str, source: Path, references: list[Path], out: Path) -> Path:
        return self._call(prompt, [source, *references], out)

    def live_check(self) -> str:
        _net.request("google", f"{self.base_url}/v1beta/models/{self.model}", self._headers(), timeout=self.timeout)
        return f"model {self.model} reachable"


REGISTRY["image"]["google"] = GoogleImage
