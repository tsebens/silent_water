"""Tripo (tripo3d.ai) multiview-to-model: upload each view, create a task, poll it, fetch the GLB.

Views go in the order front, left, back, right.
"""
from __future__ import annotations

import json
from pathlib import Path

from ..providers import REGISTRY
from . import _net
from ._three_d import HostedThreeD, ThreeDProviderError

STATUS = {"queued": "pending", "running": "running", "success": "done"}


class TripoThreeD(HostedThreeD):
    name = "tripo"
    env_key = "TRIPO_API_KEY"

    def __init__(self, model: str = "v2.5-20250123", base_url: str = "https://api.tripo3d.ai/v2/openapi",
                 timeout: int = 300) -> None:
        super().__init__()
        self.model, self.base_url, self.timeout = model, base_url.rstrip("/"), timeout

    def _auth(self) -> dict[str, str]:
        return {"authorization": f"Bearer {self._key()}"}

    @staticmethod
    def _data(reply: object, what: str) -> dict:
        if not isinstance(reply, dict) or reply.get("code", 0) != 0 or not isinstance(reply.get("data"), dict):
            msg = reply.get("message") if isinstance(reply, dict) else None
            raise ThreeDProviderError(f"tripo {what} failed: {msg or 'unexpected reply'}")
        return reply["data"]

    def submit(self, views: list[Path]) -> str:
        self._check_views(views)
        files = []
        for v in views:
            reply = _net.post_multipart("tripo", f"{self.base_url}/upload", self._auth(), {}, [("file", v)], self.timeout)
            token = self._data(reply, "upload").get("image_token")
            if not token:
                raise ThreeDProviderError("tripo upload reply has no image_token")
            files.append({"type": v.suffix.lower().lstrip(".").replace("jpg", "jpeg"), "file_token": token})
        payload = {"type": "multiview_to_model", "model_version": self.model, "files": files}
        reply = _net.post_json("tripo", f"{self.base_url}/task", self._auth(), payload, self.timeout)
        task = self._data(reply, "task").get("task_id")
        if not task:
            raise ThreeDProviderError("tripo task reply has no task_id")
        return task

    def _task(self, job_id: str) -> dict:
        raw = _net.request("tripo", f"{self.base_url}/task/{job_id}", self._auth(), timeout=self.timeout)
        try:
            return self._data(json.loads(raw), "poll")
        except json.JSONDecodeError as e:
            raise ThreeDProviderError(f"tripo returned invalid JSON: {e}") from e

    def poll(self, job_id: str) -> str:
        data = self._task(job_id)
        status = str(data.get("status", "")).lower()
        if status in STATUS:
            return STATUS[status]
        self.failures[job_id] = f"task ended {status or 'unknown'}"
        return "failed"

    def download(self, job_id: str, out: Path) -> Path:
        output = self._task(job_id).get("output") or {}
        return self._fetch_glb(output.get("pbr_model") or output.get("model") or "", out)

    def live_check(self) -> str:
        _net.request("tripo", f"{self.base_url}/user/balance", self._auth(), timeout=30)
        return "balance endpoint reachable"


REGISTRY["three_d"]["tripo"] = TripoThreeD
