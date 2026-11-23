"""Meshy multi-image-to-3D (up to four views, sent as data URIs)."""
from __future__ import annotations

import json
from pathlib import Path

from ..providers import REGISTRY
from . import _net
from ._three_d import HostedThreeD, ThreeDProviderError

STATUS = {"PENDING": "pending", "IN_PROGRESS": "running", "SUCCEEDED": "done"}


class MeshyThreeD(HostedThreeD):
    name = "meshy"
    env_key = "MESHY_API_KEY"

    def __init__(self, model: str = "meshy-7.1", base_url: str = "https://api.meshy.ai/openapi/v1",
                 timeout: int = 300) -> None:
        super().__init__()
        self.model, self.base_url, self.timeout = model, base_url.rstrip("/"), timeout
        self.max_views = 4

    def _auth(self) -> dict[str, str]:
        return {"authorization": f"Bearer {self._key()}"}

    def submit(self, views: list[Path]) -> str:
        self._check_views(views)
        payload = {"image_urls": [_net.data_uri(v) for v in views[:4]], "ai_model": self.model,
                   "should_texture": True,
                   **self.options}
        reply = _net.post_json("meshy", f"{self.base_url}/multi-image-to-3d", self._auth(), payload, self.timeout)
        task = reply.get("result") if isinstance(reply, dict) else None
        if not task:
            raise ThreeDProviderError("meshy reply has no task id")
        self.last_usage = {"generations": 1}  # task responses carry no charge: priced from prices.yaml credits
        return task

    def _task(self, job_id: str) -> dict:
        raw = _net.request("meshy", f"{self.base_url}/multi-image-to-3d/{job_id}", self._auth(), timeout=self.timeout)
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            raise ThreeDProviderError(f"meshy returned invalid JSON: {e}") from e
        if not isinstance(data, dict):
            raise ThreeDProviderError("meshy returned an unexpected reply")
        return data

    def poll(self, job_id: str) -> str:
        data = self._task(job_id)
        status = str(data.get("status", ""))
        if status in STATUS:
            return STATUS[status]
        err = data.get("task_error")
        msg = err.get("message") if isinstance(err, dict) else ""
        self.failures[job_id] = msg or f"task ended {status or 'unknown'}"
        return "failed"

    def download(self, job_id: str, out: Path) -> Path:
        urls = self._task(job_id).get("model_urls") or {}
        return self._fetch_glb(urls.get("glb", ""), out)

    def live_check(self) -> str:
        _net.request("meshy", f"{self.base_url}/balance", self._auth(), timeout=30)
        return "balance endpoint reachable"


REGISTRY["three_d"]["meshy"] = MeshyThreeD
