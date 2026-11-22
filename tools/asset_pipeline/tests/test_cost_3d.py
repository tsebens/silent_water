"""Cost extraction for the 3D adapters from recorded responses, billed failures, and bake-off subtotals."""
import json

import pytest

from asset_pipeline import cli, cost, paths, providers
from asset_pipeline.adapters.fal_trellis import FalTrellis
from asset_pipeline.adapters.meshy_3d import MeshyThreeD
from asset_pipeline.adapters.rodin_3d import RodinThreeD
from asset_pipeline.adapters.tripo_3d import TripoThreeD
from asset_pipeline.manifest import Manifest
from test_cost import FIX, PRICES  # noqa: F401
from test_three_d import GLB, Routes, run, server, staged, views  # noqa: F401


def entry(prov, **kw):
    return cost.entry_for(prov, "three_d", PRICES, command="to3d", stage="to3d", **kw)


def finish(prov, views, tmp_path):
    job = prov.submit(views)
    while prov.poll(job) != "done":
        pass
    prov.download(job, tmp_path / "o.glb")


def test_tripo_reports_the_tasks_credits(server, tmp_path, monkeypatch, views):  # noqa: F811
    monkeypatch.setenv("TRIPO_API_KEY", "tk")
    Routes.routes = {("POST", "/upload"): ["tripo_upload.json"], ("POST", "/task"): ["tripo_task_create.json"],
                     ("GET", "/task/tripo-task-1"): ["tripo_task_success_billed.json"]}
    p = TripoThreeD(base_url=server)
    finish(p, views, tmp_path)
    e = entry(p, lineage="r1_tripo")
    assert e.units == {"generations": 1, "credits": 40}
    assert (e.basis, e.usd, e.unit_price) == ("reported", pytest.approx(0.4), {"usd_per_credit": 0.01})


def test_meshy_is_priced_from_the_credit_table(server, tmp_path, monkeypatch, views):  # noqa: F811
    monkeypatch.setenv("MESHY_API_KEY", "mk")
    Routes.routes = {("POST", "/multi-image-to-3d"): ["meshy_create.json"],
                     ("GET", "/multi-image-to-3d/meshy-task-1"): ["meshy_succeeded.json"]}
    p = MeshyThreeD(base_url=server)
    finish(p, views, tmp_path)
    e = entry(p)
    assert e.units == {"generations": 1}
    assert (e.basis, e.usd) == ("estimated", pytest.approx(0.6))  # 30 credits * 0.02
    assert e.unit_price == {"credits_per_generation": 30, "usd_per_credit": 0.02}


def test_rodin_is_priced_from_the_credit_table(server, tmp_path, monkeypatch, views):  # noqa: F811
    monkeypatch.setenv("RODIN_API_KEY", "rk")
    Routes.routes = {("POST", "/rodin"): ["rodin_create.json"], ("POST", "/status"): ["rodin_done.json"],
                     ("POST", "/download"): ["rodin_download.json"]}
    p = RodinThreeD(base_url=server)
    finish(p, views, tmp_path)
    e = entry(p)
    assert (e.basis, e.usd, e.units) == ("estimated", pytest.approx(0.05), {"generations": 1})


def test_trellis_is_priced_per_generation(server, tmp_path, monkeypatch, views):  # noqa: F811
    monkeypatch.setenv("FAL_KEY", "fk")
    Routes.routes = {("POST", "/fal-ai/trellis-2"): ["trellis_submit.json"],
                     ("GET", "/fal-ai/trellis-2/requests/fal-req-1/status"): ["trellis_completed.json"],
                     ("GET", "/fal-ai/trellis-2/requests/fal-req-1"): ["trellis_result.json"]}
    p = FalTrellis(base_url=server)
    finish(p, views, tmp_path)
    e = entry(p)
    assert (e.basis, e.usd, e.unit_price) == ("estimated", pytest.approx(0.25), {"usd_per_generation": 0.25})


def test_an_unpriced_3d_model_is_unknown(server, tmp_path, monkeypatch, views):  # noqa: F811
    monkeypatch.setenv("MESHY_API_KEY", "mk")
    Routes.routes = {("POST", "/multi-image-to-3d"): ["meshy_create.json"]}
    p = MeshyThreeD(base_url=server, model="meshy-99")
    p.submit(views)
    assert (entry(p).usd, entry(p).basis) == (None, "unknown")


def test_nothing_submitted_is_nothing_billed(server, monkeypatch, views):  # noqa: F811
    monkeypatch.setenv("MESHY_API_KEY", "mk")
    Routes.routes = {("POST", "/multi-image-to-3d"): [500]}
    p = MeshyThreeD(base_url=server)
    with pytest.raises(ValueError):
        p.submit(views)
    assert p.last_usage is None


# ---- the to3d command ------------------------------------------------------------------------

def three_d_cfg(monkeypatch, **adapters):
    cfg = providers.load_config()
    for name, cls in adapters.items():
        cfg["providers"]["three_d"][name] = {"adapter": name, "model": "m"}
        monkeypatch.setitem(providers.REGISTRY["three_d"], name, cls)
    monkeypatch.setattr(providers, "load_config", lambda path=None: cfg)
    monkeypatch.setattr(cost, "load_prices", lambda path=None: PRICES)


def test_a_failed_but_billed_job_is_recorded(staged, root, capsys, monkeypatch):  # noqa: F811
    class Billed(providers.MockThreeDProvider):
        billing = "paid"

        def submit(self, views):
            self.last_usage = {"generations": 1}
            return "job"

        def poll(self, job_id):
            return "failed"

    three_d_cfg(monkeypatch, **{"mock-a": Billed})
    code, out = run(capsys, "to3d", "angler", "--3d-provider", "mock-a", "--poll-interval", "0")
    assert code == 1 and out["runs"] == []
    (c,) = Manifest.load(paths.manifest_path(root, "angler")).costs[-1:]
    assert (c.provider, c.basis, c.usd, c.lineage) == ("mock-a", "estimated", pytest.approx(0.1), None)
    assert "failed" in c.error


def test_a_job_that_never_started_is_not_recorded(staged, root, capsys, monkeypatch):  # noqa: F811
    class Rejected(providers.MockThreeDProvider):
        billing = "paid"

        def submit(self, views):
            raise ValueError("rejected")

    three_d_cfg(monkeypatch, **{"mock-a": Rejected})
    n = len(Manifest.load(paths.manifest_path(root, "angler")).costs)
    run(capsys, "to3d", "angler", "--3d-provider", "mock-a", "--poll-interval", "0")
    assert len(Manifest.load(paths.manifest_path(root, "angler")).costs) == n


def test_bakeoff_records_one_entry_per_provider(staged, root, capsys, monkeypatch):  # noqa: F811
    class Priced(providers.MockThreeDProvider):
        billing = "paid"

        def submit(self, views):
            self.last_usage = {"generations": 1}
            return super().submit(views)

    three_d_cfg(monkeypatch, **{n: Priced for n in ("mock-a", "mock-b", "mock-c")})
    n0 = len(Manifest.load(paths.manifest_path(root, "angler")).costs)
    code, out = run(capsys, "to3d", "angler", "--3d-provider", "mock-a", "mock-b", "mock-c", "--poll-interval", "0")
    assert code == 0 and len(out["runs"]) == 3
    m = Manifest.load(paths.manifest_path(root, "angler"))
    new = m.costs[n0:]
    assert [(c.provider, c.usd, c.basis, c.lineage) for c in new] == [
        ("mock-a", pytest.approx(0.1), "estimated", "r1_mock-a"),
        ("mock-b", pytest.approx(0.2), "estimated", "r1_mock-b"),
        ("mock-c", pytest.approx(0.3), "estimated", "r1_mock-c")]
    assert cost.total_usd(m) == pytest.approx(0.6)


def test_mock_to3d_records_zero(staged, root, capsys):  # noqa: F811
    run(capsys, "to3d", "angler", "--poll-interval", "0")
    c = Manifest.load(paths.manifest_path(root, "angler")).costs[-1]
    assert (c.command, c.provider, c.usd, c.basis, c.lineage) == ("to3d", "mock", 0.0, "mock", "r1_mock")
