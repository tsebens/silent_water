"""TRELLIS.2 (or another image-to-3D endpoint) on fal.ai's queue API: the model is the endpoint id.

`input` says what the endpoint takes: `single` sends the front view as `image_url` (fal-ai/trellis-2
accepts one image and rejects `image_urls` with a 422), `multi` sends every view as `image_urls`
for endpoints that take several images.
"""
from __future__ import annotations

import json
from pathlib import Path

from ..providers import REGISTRY
from . import _net
from ._three_d import HostedThreeD, ThreeDProviderError

STATUS = {"IN_QUEUE": "pending", "IN_PROGRESS": "running", "COMPLETED": "done"}
MODEL_KEYS = ("model_glb", "model_mesh", "glb")


class FalTrellis(HostedThreeD):
    name = "trellis"
    env_key = "FAL_KEY"

    def __init__(self, model: str = "fal-ai/trellis-2", base_url: str = "https://queue.fal.run",
                 timeout: int = 300, input: str = "single") -> None:
        super().__init__()
        if input not in ("single", "multi"):
            raise ValueError(f"trellis: input must be 'single' or 'multi', not {input!r}")
        self.model, self.base_url, self.timeout, self.input = model, base_url.rstrip("/"), timeout, input
        self.max_views = 1 if input == "single" else 8

    def _auth(self) -> dict[str, str]:
        return {"authorization": f"Key {self._key()}"}

    def _app(self) -> str:
        """Queue status and result URLs use only the owner/app part of the endpoint id."""
        return "/".join(self.model.split("/")[:2])

    def _get(self, job_id: str, suffix: str) -> dict:
        raw = _net.request("trellis", f"{self.base_url}/{self._app()}/requests/{job_id}{suffix}", self._auth(),
                           timeout=self.timeout)
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            raise ThreeDProviderError(f"trellis returned invalid JSON: {e}") from e
        if not isinstance(data, dict):
            raise ThreeDProviderError("trellis returned an unexpected reply")
        return data

    def submit(self, views: list[Path]) -> str:
        self._check_views(views)
        if self.input == "single":
            payload: dict = {"image_url": _net.data_uri(views[0])}  # views arrive front, left, back, right
        else:
            payload = {"image_urls": [_net.data_uri(v) for v in views]}
        payload = {**payload, **self.options}  # e.g. resolution, texture_size; multiimage_algo for the multi endpoint
        reply = _net.post_json("trellis", f"{self.base_url}/{self.model}", self._auth(), payload, self.timeout)
        rid = reply.get("request_id") if isinstance(reply, dict) else None
        if not rid:
            raise ThreeDProviderError("trellis reply has no request_id")
        self.last_usage = {"generations": 1}  # fal's queue replies report no cost: priced per generation
        return rid

    def poll(self, job_id: str) -> str:
        data = self._get(job_id, "/status")
        status = str(data.get("status", ""))
        if status in STATUS:
            if status == "COMPLETED" and data.get("error"):
                self.failures[job_id] = str(data["error"])[:300]
                return "failed"
            return STATUS[status]
        self.failures[job_id] = f"request ended {status or 'unknown'}"
        return "failed"

    def download(self, job_id: str, out: Path) -> Path:
        data = self._get(job_id, "")
        for key in MODEL_KEYS:
            item = data.get(key)
            if isinstance(item, dict) and item.get("url"):
                return self._fetch_glb(item["url"], out)
        raise ThreeDProviderError("trellis result has no GLB")

    def live_check(self) -> str:
        """An empty body is rejected (422) only after auth passes."""
        _net.request("trellis", f"{self.base_url}/{self.model}", {**self._auth(), "content-type": "application/json"},
                     b"{}", self.timeout, ok_status=(422,))
        return f"endpoint {self.model} accepts the key"


REGISTRY["three_d"]["trellis"] = FalTrellis
