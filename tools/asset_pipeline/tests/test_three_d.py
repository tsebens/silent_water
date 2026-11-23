import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest

from asset_pipeline import cli, doctor, paths, providers
from asset_pipeline.adapters._net import ImageProviderError
from asset_pipeline.adapters._net import data_uri as _net_data_uri
from asset_pipeline.adapters.fal_trellis import FalTrellis
from asset_pipeline.adapters.meshy_3d import MeshyThreeD
from asset_pipeline.adapters.rodin_3d import RodinThreeD
from asset_pipeline.adapters.tripo_3d import TripoThreeD
from asset_pipeline.manifest import Manifest

FIX = Path(__file__).parent / "fixtures" / "three_d"
_tmp = Path(__import__("tempfile").mkdtemp()) / "p.glb"
providers.MockThreeDProvider().download("x", _tmp)
GLB = _tmp.read_bytes()


class Routes(BaseHTTPRequestHandler):
    """Replays recorded fixtures per (method, path). A route's list is consumed in order, the last repeats;
    an int entry replies with that HTTP error status. /files/* serves a GLB."""
    routes: dict = {}
    seen: list = []
    base = ""

    def _reply(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n)
        Routes.seen.append({"method": self.command, "path": self.path, "body": body,
                            "headers": {k.lower(): v for k, v in self.headers.items()}})
        if self.path.startswith("/files/"):
            return self._send(200, GLB, "model/gltf-binary")
        seq = Routes.routes.get((self.command, self.path))
        if not seq:
            return self._send(404, b'{"error":"no route"}', "application/json")
        item = seq.pop(0) if len(seq) > 1 else seq[0]
        if isinstance(item, int):
            return self._send(item, json.dumps({"message": f"boom {item}"}).encode(), "application/json")
        data = (FIX / item).read_text().replace("{base}", Routes.base).encode()
        self._send(200, data, "application/json")

    def _send(self, status, data, ctype):
        self.send_response(status)
        self.send_header("content-type", ctype)
        self.end_headers()
        self.wfile.write(data)

    do_POST = do_GET = _reply

    def log_message(self, *a):
        pass


@pytest.fixture
def server():
    Routes.routes, Routes.seen = {}, []
    srv = HTTPServer(("127.0.0.1", 0), Routes)
    Routes.base = f"http://127.0.0.1:{srv.server_port}"
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield Routes.base
    srv.shutdown()


@pytest.fixture
def views(tmp_path):
    out = []
    for v in cli.VIEWS:
        p = tmp_path / f"{v}.png"
        p.write_bytes(b"\x89PNG\r\n\x1a\n" + v.encode())
        out.append(p)
    return out


def run_job(prov, views, out, polls):
    job = prov.submit(views)
    states = [prov.poll(job) for _ in range(polls)]
    return job, states, prov.download(job, out)


# ---- Tripo ----------------------------------------------------------------------------

def test_tripo_submit_poll_download(server, tmp_path, monkeypatch, views):
    monkeypatch.setenv("TRIPO_API_KEY", "tk")
    Routes.routes = {("POST", "/upload"): ["tripo_upload.json"], ("POST", "/task"): ["tripo_task_create.json"],
                     ("GET", "/task/tripo-task-1"): ["tripo_task_queued.json", "tripo_task_running.json",
                                                      "tripo_task_success.json"]}
    job, states, out = run_job(TripoThreeD(base_url=server), views, tmp_path / "w" / "t.glb", 3)
    assert job == "tripo-task-1" and states == ["pending", "running", "done"]
    assert out.read_bytes() == GLB
    uploads = [r for r in Routes.seen if r["path"] == "/upload"]
    assert len(uploads) == 4 and uploads[0]["headers"]["authorization"] == "Bearer tk"
    task = json.loads([r for r in Routes.seen if r["path"] == "/task" and r["method"] == "POST"][0]["body"])
    assert task["type"] == "multiview_to_model" and task["model_version"] == "v3.1-20260211"
    assert [f["file_token"] for f in task["files"]] == ["tok-1"] * 4 and task["files"][0]["type"] == "png"


def test_tripo_failed_task(server, monkeypatch):
    monkeypatch.setenv("TRIPO_API_KEY", "tk")
    Routes.routes = {("GET", "/task/x"): ["tripo_task_failed.json"]}
    p = TripoThreeD(base_url=server)
    assert p.poll("x") == "failed" and "failed" in p.failure_reason("x")


def test_tripo_http_error_is_mapped(server, tmp_path, monkeypatch, views):
    monkeypatch.setenv("TRIPO_API_KEY", "tk")
    Routes.routes = {("POST", "/upload"): [429]}
    with pytest.raises(ImageProviderError, match="tripo HTTP 429: rate limited"):
        TripoThreeD(base_url=server).submit(views)


# ---- Meshy ----------------------------------------------------------------------------

def test_meshy_submit_poll_download(server, tmp_path, monkeypatch, views):
    monkeypatch.setenv("MESHY_API_KEY", "mk")
    Routes.routes = {("POST", "/multi-image-to-3d"): ["meshy_create.json"],
                     ("GET", "/multi-image-to-3d/meshy-task-1"): ["meshy_pending.json", "meshy_progress.json",
                                                                   "meshy_succeeded.json"]}
    job, states, out = run_job(MeshyThreeD(base_url=server, model="meshy-6"), views, tmp_path / "m.glb", 3)
    assert job == "meshy-task-1" and states == ["pending", "running", "done"] and out.read_bytes() == GLB
    sent = json.loads(Routes.seen[0]["body"])
    assert sent["ai_model"] == "meshy-6" and len(sent["image_urls"]) == 4
    assert sent["image_urls"][0].startswith("data:image/png;base64,")
    assert Routes.seen[0]["headers"]["authorization"] == "Bearer mk"


def test_meshy_failure_reason_and_error(server, monkeypatch, views):
    monkeypatch.setenv("MESHY_API_KEY", "mk")
    Routes.routes = {("GET", "/multi-image-to-3d/t"): ["meshy_failed.json"], ("POST", "/multi-image-to-3d"): [401]}
    p = MeshyThreeD(base_url=server)
    assert p.poll("t") == "failed" and p.failure_reason("t") == "images do not show one object"
    with pytest.raises(ImageProviderError, match="meshy HTTP 401: authentication failed"):
        p.submit(views)


# ---- Rodin ----------------------------------------------------------------------------

def test_rodin_submit_poll_download(server, tmp_path, monkeypatch, views):
    monkeypatch.setenv("RODIN_API_KEY", "rk")
    Routes.routes = {("POST", "/rodin"): ["rodin_create.json"],
                     ("POST", "/status"): ["rodin_waiting.json", "rodin_generating.json", "rodin_done.json"],
                     ("POST", "/download"): ["rodin_download.json"]}
    job, states, out = run_job(RodinThreeD(base_url=server), views, tmp_path / "r.glb", 3)
    assert job == "rodin-uuid-1:sub-1" and states == ["pending", "running", "done"] and out.read_bytes() == GLB
    create = Routes.seen[0]
    assert create["body"].count(b'name="images"') == 4 and b'name="tier"' in create["body"]
    assert json.loads([r for r in Routes.seen if r["path"] == "/status"][0]["body"]) == {"subscription_key": "sub-1"}
    assert json.loads([r for r in Routes.seen if r["path"] == "/download"][0]["body"]) == {"task_uuid": "rodin-uuid-1"}


def test_rodin_failed_job_and_server_error(server, monkeypatch, views):
    monkeypatch.setenv("RODIN_API_KEY", "rk")
    Routes.routes = {("POST", "/status"): ["rodin_failed.json"], ("POST", "/rodin"): [500]}
    p = RodinThreeD(base_url=server)
    assert p.poll("u:s") == "failed" and "Failed" in p.failure_reason("u:s")
    with pytest.raises(ImageProviderError, match="rodin HTTP 500: provider server error"):
        p.submit(views)


# ---- TRELLIS.2 via fal ----------------------------------------------------------------

def test_trellis_submit_poll_download(server, tmp_path, monkeypatch, views):
    monkeypatch.setenv("FAL_KEY", "fk")
    base = "/fal-ai/trellis-2"
    Routes.routes = {("POST", base): ["trellis_submit.json"],
                     ("GET", "/fal-ai/trellis-2/requests/fal-req-1/status"): [
                         "trellis_queue.json", "trellis_progress.json", "trellis_completed.json"],
                     ("GET", "/fal-ai/trellis-2/requests/fal-req-1"): ["trellis_result.json"]}
    job, states, out = run_job(FalTrellis(base_url=server), views, tmp_path / "t.glb", 3)
    assert job == "fal-req-1" and states == ["pending", "running", "done"] and out.read_bytes() == GLB
    assert Routes.seen[0]["headers"]["authorization"] == "Key fk"
    body = json.loads(Routes.seen[0]["body"])
    # fal-ai/trellis-2 takes one image: the front view, as image_url (a 4-view image_urls body is a 422)
    assert set(body) == {"image_url"} and body["image_url"] == _net_data_uri(views[0])


def test_trellis_multi_input_sends_every_view(server, tmp_path, monkeypatch, views):
    monkeypatch.setenv("FAL_KEY", "fk")
    Routes.routes = {("POST", "/fal-ai/trellis-multi"): ["trellis_submit.json"]}
    FalTrellis(model="fal-ai/trellis-multi", base_url=server, input="multi").submit(views)
    body = json.loads(Routes.seen[-1]["body"])
    assert set(body) == {"image_urls"} and len(body["image_urls"]) == 4


def test_trellis_rejects_unknown_input_mode():
    with pytest.raises(ValueError, match="single' or 'multi"):
        FalTrellis(input="both")


def test_trellis_error_and_missing_key(server, monkeypatch, views, tmp_path):
    monkeypatch.delenv("FAL_KEY", raising=False)
    with pytest.raises(ImageProviderError, match="FAL_KEY is not set"):
        FalTrellis(base_url=server).submit(views)
    monkeypatch.setenv("FAL_KEY", "fk")
    Routes.routes = {("POST", "/fal-ai/trellis-2"): [422]}
    with pytest.raises(ImageProviderError, match="trellis HTTP 422: request rejected"):
        FalTrellis(base_url=server).submit(views)


def test_download_rejects_non_glb(server, tmp_path, monkeypatch):
    monkeypatch.setenv("MESHY_API_KEY", "mk")
    Routes.routes = {("GET", "/multi-image-to-3d/t"): [
        "meshy_succeeded.json"]}
    Routes.base = server + "/nothing"  # url resolves to a 404 path
    with pytest.raises(ImageProviderError):
        MeshyThreeD(base_url=server).download("t", tmp_path / "x.glb")


# ---- registry and doctor ----------------------------------------------------------------

def test_three_d_providers_are_selectable():
    cfg = providers.load_config()
    for name, cls in (("tripo", TripoThreeD), ("meshy", MeshyThreeD), ("rodin", RodinThreeD),
                      ("trellis", FalTrellis)):
        p = providers.select("three_d", cfg, override=name)
        assert isinstance(p, cls) and p.name == name and p.model


def test_doctor_checks_three_d_keys_and_live(server, monkeypatch):
    for k in ("TRIPO_API_KEY", "MESHY_API_KEY", "RODIN_API_KEY", "FAL_KEY"):
        monkeypatch.delenv(k, raising=False)
    cfg = providers.load_config()
    r = doctor.run(cfg)
    names = {c["name"]: c for c in r["checks"]}
    assert names["three_d:tripo key"]["detail"] == "TRIPO_API_KEY is not set"
    monkeypatch.setenv("MESHY_API_KEY", "k")
    cfg["providers"]["three_d"]["meshy"]["base_url"] = server
    Routes.routes = {("GET", "/balance"): ["meshy_pending.json"]}
    r = doctor.run(cfg, live=True)
    assert {c["name"]: c for c in r["checks"]}["three_d:meshy live"]["ok"]


# ---- to3d command -------------------------------------------------------------------------

def run(capsys, *argv):
    code = cli.main(list(argv))
    return code, json.loads(capsys.readouterr().out)


@pytest.fixture
def staged(root, capsys):
    """An asset with a locked concept and a turnaround, made with the mock providers."""
    run(capsys, "new", "angler", "--class", "creature")
    run(capsys, "concept", "angler", "--n", "1", "--brief", "an angler")
    run(capsys, "lock", "angler", "v1")
    run(capsys, "turnaround", "angler")


def test_to3d_requires_a_turnaround(root, capsys):
    run(capsys, "new", "angler", "--class", "creature")
    code, out = run(capsys, "to3d", "angler")
    assert code == 1 and "turnaround" in out["error"]


def test_to3d_default_provider_records_a_run(staged, root, capsys):
    code, out = run(capsys, "to3d", "angler", "--poll-interval", "0")
    assert code == 0 and [r["provider"] for r in out["runs"]] == ["mock"] and out["stage"] == "to3d"
    assert (root / out["runs"][0]["path"]).read_bytes()[:4] == b"glTF"
    assert out["runs"][0]["path"].startswith(".asset_work/angler/")


def test_to3d_bakeoff_two_providers_two_recorded_runs(staged, root, capsys, monkeypatch):
    cfg = providers.load_config()
    cfg["providers"]["three_d"]["mock2"] = {"adapter": "mock", "model": "mock-3d-2"}
    monkeypatch.setattr(providers, "load_config", lambda path=None: cfg)
    code, out = run(capsys, "to3d", "angler", "--3d-provider", "mock", "mock2", "--poll-interval", "0")
    assert code == 0 and out["errors"] == [] and len(out["runs"]) == 2
    m = Manifest.load(paths.manifest_path(root, "angler"))
    meshes = [e for e in m.lineage if e.kind == "mesh"]
    assert [(e.provider, e.model) for e in meshes] == [("mock", "mock-3d-1"), ("mock2", "mock-3d-2")]
    assert all(e.task_id.startswith("mock-") and (root / e.path).is_file() for e in meshes)
    assert meshes[0].task_id != meshes[1].task_id
    assert meshes[0].references and meshes[0].parent.startswith("t1_")
    assert m.stage == "to3d"


def test_to3d_rerun_gets_fresh_ids(staged, root, capsys):
    run(capsys, "to3d", "angler", "--poll-interval", "0")
    _, out = run(capsys, "to3d", "angler", "--poll-interval", "0")
    assert out["runs"][0]["id"] == "r2_mock"


def test_to3d_unknown_provider_fails_before_any_run(staged, root, capsys):
    code, out = run(capsys, "to3d", "angler", "--3d-provider", "mock", "nope")
    assert code == 1 and "nope" in out["error"]
    assert not [e for e in Manifest.load(paths.manifest_path(root, "angler")).lineage if e.kind == "mesh"]


def test_to3d_failed_provider_does_not_stop_the_others(staged, root, capsys, monkeypatch):
    class Failing(providers.MockThreeDProvider):
        def poll(self, job_id):
            return "failed"

        def failure_reason(self, job_id):
            return "bad input"

    cfg = providers.load_config()
    cfg["providers"]["three_d"]["bad"] = {"adapter": "failing", "model": "x"}
    monkeypatch.setitem(providers.REGISTRY["three_d"], "failing", Failing)
    monkeypatch.setattr(providers, "load_config", lambda path=None: cfg)
    code, out = run(capsys, "to3d", "angler", "--3d-provider", "bad", "mock", "--poll-interval", "0")
    assert code == 1 and [r["provider"] for r in out["runs"]] == ["mock"]
    assert out["errors"] == [{"provider": "bad", "error": out["errors"][0]["error"]}]
    assert "bad input" in out["errors"][0]["error"]


def test_to3d_polls_until_done_then_times_out(staged, root, capsys, monkeypatch):
    class Slow(providers.MockThreeDProvider):
        n = 0

        def poll(self, job_id):
            Slow.n += 1
            return "running" if Slow.n < 3 else "done"

    cfg = providers.load_config()
    cfg["providers"]["three_d"]["slow"] = {"adapter": "slow", "model": "x"}
    monkeypatch.setitem(providers.REGISTRY["three_d"], "slow", Slow)
    monkeypatch.setattr(providers, "load_config", lambda path=None: cfg)
    code, out = run(capsys, "to3d", "angler", "--3d-provider", "slow", "--poll-interval", "0")
    assert code == 0 and Slow.n == 3

    class Never(providers.MockThreeDProvider):
        def poll(self, job_id):
            return "pending"

    monkeypatch.setitem(providers.REGISTRY["three_d"], "slow", Never)
    code, out = run(capsys, "to3d", "angler", "--3d-provider", "slow", "--poll-interval", "0", "--timeout", "0")
    assert code == 1 and "timed out" in out["errors"][0]["error"]


def test_trellis_multi_entry_uses_v1_multi_endpoint(server, tmp_path, monkeypatch, views):
    monkeypatch.setenv("FAL_KEY", "fk")
    cfg = providers.load_config()
    cfg["providers"]["three_d"]["trellis-multi"]["base_url"] = server
    p = providers.select("three_d", cfg, override="trellis-multi")
    assert isinstance(p, FalTrellis) and p.input == "multi" and p.model == "fal-ai/trellis/multi"
    Routes.routes = {("POST", "/fal-ai/trellis/multi"): ["trellis_submit.json"],
                     ("GET", "/fal-ai/trellis/requests/fal-req-1/status"): ["trellis_completed.json"],
                     ("GET", "/fal-ai/trellis/requests/fal-req-1"): ["trellis_result.json"]}
    job, states, out = run_job(p, views, tmp_path / "m.glb", 1)
    assert states == ["done"] and out.read_bytes() == GLB
    assert len(json.loads(Routes.seen[0]["body"])["image_urls"]) == 4
