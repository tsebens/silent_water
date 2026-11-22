"""Rodin (Hyper3D) multi-image generation. The job id is `<task uuid>:<subscription key>`, since
status needs the subscription key and download needs the task uuid."""
from __future__ import annotations

from pathlib import Path

from ..providers import REGISTRY
from . import _net
from ._three_d import HostedThreeD, ThreeDProviderError

STATUS = {"Waiting": "pending", "Generating": "running", "Done": "done"}


class RodinThreeD(HostedThreeD):
    name = "rodin"
    env_key = "RODIN_API_KEY"

    def __init__(self, model: str = "Gen-2.5-Medium", base_url: str = "https://api.hyper3d.com/api/v2",
                 timeout: int = 300) -> None:
        super().__init__()
        self.model, self.base_url, self.timeout = model, base_url.rstrip("/"), timeout  # model is the tier

    def _auth(self) -> dict[str, str]:
        return {"authorization": f"Bearer {self._key()}"}

    @staticmethod
    def _split(job_id: str) -> tuple[str, str]:
        uuid, _, sub = job_id.partition(":")
        if not uuid or not sub:
            raise ThreeDProviderError(f"rodin: malformed job id {job_id!r}")
        return uuid, sub

    def submit(self, views: list[Path]) -> str:
        self._check_views(views)
        fields = {"tier": self.model, "geometry_file_format": "glb", "material": "PBR", "condition_mode": "concat"}
        reply = _net.post_multipart("rodin", f"{self.base_url}/rodin", self._auth(), fields,
                                    [("images", v) for v in views], self.timeout)
        if not isinstance(reply, dict) or reply.get("error"):
            raise ThreeDProviderError(f"rodin rejected the job: {reply.get('error') if isinstance(reply, dict) else reply}")
        sub = (reply.get("jobs") or {}).get("subscription_key")
        if not reply.get("uuid") or not sub:
            raise ThreeDProviderError("rodin reply has no uuid or subscription key")
        self.last_usage = {"generations": 1}  # the status reply carries no charge: priced from prices.yaml credits
        return f"{reply['uuid']}:{sub}"

    def poll(self, job_id: str) -> str:
        uuid, sub = self._split(job_id)
        reply = _net.post_json("rodin", f"{self.base_url}/status", self._auth(), {"subscription_key": sub}, self.timeout)
        jobs = reply.get("jobs") if isinstance(reply, dict) else None
        if not isinstance(jobs, list) or not jobs:
            raise ThreeDProviderError("rodin status reply has no jobs")
        states = [str(j.get("status", "")) for j in jobs if isinstance(j, dict)]
        if any(s not in STATUS for s in states):
            self.failures[job_id] = "job ended " + ",".join(sorted(set(states) - set(STATUS)))
            return "failed"
        if all(s == "Done" for s in states):
            return "done"
        return "running" if any(s == "Generating" for s in states) else "pending"

    def download(self, job_id: str, out: Path) -> Path:
        uuid, _ = self._split(job_id)
        reply = _net.post_json("rodin", f"{self.base_url}/download", self._auth(), {"task_uuid": uuid}, self.timeout)
        items = reply.get("list") if isinstance(reply, dict) else None
        urls = [i.get("url", "") for i in items or [] if isinstance(i, dict) and str(i.get("name", "")).endswith(".glb")]
        return self._fetch_glb(urls[0] if urls else "", out)

    def live_check(self) -> str:
        """No free endpoint: a bogus subscription key is rejected (4xx) only after auth passes."""
        _net.request("rodin", f"{self.base_url}/status", {**self._auth(), "content-type": "application/json"},
                     b'{"subscription_key": "doctor"}', 30, ok_status=(400, 404, 422))
        return "status endpoint accepts the key"


REGISTRY["three_d"]["rodin"] = RodinThreeD
