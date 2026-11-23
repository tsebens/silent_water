"""to3d view selection, model options and by-option pricing (#293). No live calls: adapters run against the
loopback fixtures server from test_three_d."""
import json
import shutil
from pathlib import Path

import pytest
import yaml

from asset_pipeline import cli, cost, paths, providers
from asset_pipeline.adapters.fal_trellis import FalTrellis
from asset_pipeline.adapters.meshy_3d import MeshyThreeD
from asset_pipeline.adapters.rodin_3d import RodinThreeD
from asset_pipeline.adapters.tripo_3d import TripoThreeD
from asset_pipeline.manifest import Manifest

from test_three_d import Routes, server, views  # noqa: F401

REPO = Path(__file__).resolve().parents[3]
SIX = ["front", "left", "back", "right", "top", "bottom"]


def run(capsys, *argv):
    code = cli.main(list(argv))
    return code, json.loads(capsys.readouterr().out)


class Recorder(providers.MockThreeDProvider):
    sent: list = []
    opts: list = []

    def submit(self, views):
        Recorder.sent.append([v.name.rsplit("_", 1)[1][:-4] for v in views])
        Recorder.opts.append(dict(self.options))
        return super().submit(views)


class One(Recorder):
    max_views = 1


@pytest.fixture
def staged(root, capsys, monkeypatch):
    sb = root / "assets" / "style_bible"
    sb.mkdir(parents=True)
    shutil.copy(REPO / "assets" / "style_bible" / "classes.yaml", sb / "classes.yaml")
    run(capsys, "new", "angler", "--class", "creature")
    run(capsys, "concept", "angler", "--n", "1", "--brief", "a thing")
    run(capsys, "lock", "angler", "v1")
    run(capsys, "turnaround", "angler")
    monkeypatch.setitem(providers.REGISTRY["three_d"], "rec", Recorder)
    monkeypatch.setitem(providers.REGISTRY["three_d"], "one", One)
    cfg = providers.load_config()
    cfg["providers"]["three_d"].update({
        "rec": {"adapter": "rec"}, "one": {"adapter": "one"},
        "entry": {"adapter": "rec", "views": ["back", "left"], "options": {"seed": 1, "texture_size": 1024}}})
    monkeypatch.setattr(providers, "load_config", lambda *a, **k: cfg)
    Recorder.sent, Recorder.opts = [], []
    return root, cfg


def set_class_views(root, views):
    f = root / "assets" / "style_bible" / "classes.yaml"
    data = yaml.safe_load(f.read_text())
    data["classes"]["creature"]["to3d_views"] = views
    f.write_text(yaml.safe_dump(data))


def test_views_flag_sends_exactly_those_views_in_order(staged, capsys):
    code, out = run(capsys, "to3d", "angler", "--3d-provider", "rec", "--views", "left,front,top", "--poll-interval", "0")
    assert code == 0, out
    assert Recorder.sent == [["left", "front", "top"]]


def fails(capsys, *argv):
    code, out = run(capsys, *argv)
    assert code == 1 and out["ok"] is False
    return out["error"]


def test_single_image_provider_rejects_two_views(staged, capsys):
    err = fails(capsys, "to3d", "angler", "--3d-provider", "one", "--views", "front,left", "--poll-interval", "0")
    assert "one takes at most 1 view" in err and "got 2" in err
    assert Recorder.sent == []
    code, out = run(capsys, "to3d", "angler", "--3d-provider", "one", "--views", "left", "--poll-interval", "0")
    assert code == 0 and Recorder.sent == [["left"]]


def test_unknown_or_missing_flag_views_are_errors(staged, capsys):
    for bad in ("sideways", "front,front", ""):
        assert "--views" in fails(capsys, "to3d", "angler", "--3d-provider", "rec", "--views", bad)
    # a prop-style turnaround has no top view
    m = Manifest.load(paths.manifest_path(staged[0], "angler"))
    m.lineage = [e for e in m.lineage if not e.id.endswith("_top")]
    m.save(paths.manifest_path(staged[0], "angler"))
    assert "no top view" in fails(capsys, "to3d", "angler", "--3d-provider", "rec", "--views", "top")


def test_default_view_resolution_order(staged, capsys):
    root, _ = staged
    go = lambda *p: run(capsys, "to3d", "angler", "--3d-provider", *p, "--poll-interval", "0")  # noqa: E731
    go("rec")  # nothing set: front, left, back, right
    assert Recorder.sent[-1] == ["front", "left", "back", "right"]
    go("one")  # fallback truncated to the provider's limit
    assert Recorder.sent[-1] == ["front"]
    set_class_views(root, ["left", "top"])
    go("rec")  # the class's to3d_views
    assert Recorder.sent[-1] == ["left", "top"]
    go("one")  # truncated to one view
    assert Recorder.sent[-1] == ["left"]
    go("entry")  # the provider entry's views beat the class's
    assert Recorder.sent[-1] == ["back", "left"]
    go("entry", "--views", "right")  # the flag beats everything
    assert Recorder.sent[-1] == ["right"]


def test_options_merge_with_flag_winning_and_land_in_lineage(staged, capsys):
    code, out = run(capsys, "to3d", "angler", "--3d-provider", "entry", "--option", "seed=7", "--option", "remesh=true",
                    "--option", "mode=fast", "--poll-interval", "0")
    assert code == 0, out
    want = {"seed": 7, "texture_size": 1024, "remesh": True, "mode": "fast"}
    assert Recorder.opts == [want]
    e = Manifest.load(paths.manifest_path(staged[0], "angler")).entry("r1_entry")
    assert e.options == want
    assert e.views == ["t1_back", "t1_left"] and e.references == [e.references[0], e.references[1]]


def test_bad_option_syntax(staged, capsys):
    assert "key=value" in fails(capsys, "to3d", "angler", "--3d-provider", "rec", "--option", "seed")


def test_old_manifests_without_views_or_options_load(tmp_path):
    f = tmp_path / "m.yaml"
    f.write_text(yaml.safe_dump({"slug": "x", "class": "prop", "lineage": [
        {"id": "r1_mock", "kind": "mesh", "path": "a.glb", "provider": "mock", "model": "m"}]}))
    e = Manifest.load(f).entry("r1_mock")
    assert e.views == [] and e.options == {}


def test_provider_entry_validation():
    for bad in ({"max_views": 0}, {"options": [1]}, {"views": ["front", "left"], "max_views": 1}):
        with pytest.raises(ValueError):
            providers.build("three_d", "x", {"adapter": "mock", **bad})
    with pytest.raises(ValueError, match="three_d"):
        providers.build("image", "x", {"adapter": "mock", "options": {"a": 1}})


def test_committed_limits_and_defaults():
    cfg = providers.load_config()
    assert providers.select("three_d", cfg, "trellis").max_views == 1
    assert providers.select("three_d", cfg, "trellis").options == {"resolution": 1024}
    assert providers.select("three_d", cfg, "trellis-multi").max_views == 8
    assert "multiimage_algo" not in providers.select("three_d", cfg, "trellis-multi").options


# ---- options reach each adapter's request body ----------------------------------------

OPTS = {"seed": 7, "resolution": 1536}


def last_body(kind="json"):
    raw = Routes.seen[-1]["body"]
    return json.loads(raw) if kind == "json" else raw.decode("latin-1")


def test_trellis_options_in_body(server, monkeypatch, views):  # noqa: F811
    monkeypatch.setenv("FAL_KEY", "fk")
    Routes.routes = {("POST", "/fal-ai/trellis-2"): ["trellis_submit.json"]}
    p = FalTrellis(base_url=server)
    p.options = {"resolution": 1024, "texture_size": 2048} | {"resolution": 1536}  # flag over entry
    p.submit(views[:1])
    body = last_body()
    assert body["resolution"] == 1536 and body["texture_size"] == 2048 and "image_url" in body
    Routes.routes = {("POST", "/fal-ai/trellis/multi"): ["trellis_submit.json"]}
    m = FalTrellis(model="fal-ai/trellis/multi", base_url=server, input="multi")
    m.options = {"multiimage_algo": "multidiffusion"}
    m.submit(views)
    assert last_body()["multiimage_algo"] == "multidiffusion" and len(last_body()["image_urls"]) == 4


def test_meshy_options_in_body(server, monkeypatch, views):  # noqa: F811
    monkeypatch.setenv("MESHY_API_KEY", "mk")
    Routes.routes = {("POST", "/multi-image-to-3d"): ["meshy_create.json"]}
    p = MeshyThreeD(base_url=server)
    p.options = {"should_texture": False, "seed": 3}
    p.submit(views)
    assert last_body()["seed"] == 3 and last_body()["should_texture"] is False


def test_tripo_options_in_body(server, monkeypatch, views):  # noqa: F811
    monkeypatch.setenv("TRIPO_API_KEY", "tk")
    Routes.routes = {("POST", "/upload"): ["tripo_upload.json"], ("POST", "/task"): ["tripo_task_create.json"]}
    p = TripoThreeD(base_url=server)
    p.options = {"texture_quality": "detailed"}
    p.submit(views)
    assert last_body()["texture_quality"] == "detailed" and last_body()["type"] == "multiview_to_model"


def test_rodin_options_in_form(server, monkeypatch, views):  # noqa: F811
    monkeypatch.setenv("RODIN_API_KEY", "rk")
    Routes.routes = {("POST", "/rodin"): ["rodin_create.json"]}
    p = RodinThreeD(base_url=server)
    p.options = {"seed": 5, "quality": "high", "use_hyper": True}
    p.submit(views)
    form = last_body("raw")
    assert 'name="seed"\r\n\r\n5' in form and 'name="quality"\r\n\r\nhigh' in form
    assert 'name="use_hyper"\r\n\r\ntrue' in form and 'name="tier"' in form


# ---- by-option pricing -----------------------------------------------------------------

PRICES = {"three_d": {"trellis": {"fal-ai/trellis-2": {"by_option": "resolution", "option_default": 1024,
                                                      "usd": {512: 0.25, 1024: 0.30, 1536: 0.35}}}}}


def trellis(**options):
    p = FalTrellis()
    p.options = options
    p.last_usage = {"generations": 1}
    return p


@pytest.mark.parametrize("opts,usd", [({"resolution": 512}, 0.25), ({"resolution": 1536}, 0.35),
                                      ({"resolution": "1024"}, 0.30), ({}, 0.30)])
def test_ledger_prices_by_option(opts, usd):
    e = cost.entry_for(trellis(**opts), "three_d", PRICES, command="to3d", stage="to3d")
    assert (e.basis, e.usd) == ("estimated", pytest.approx(usd)) and e.unit_price == {"usd_per_generation": usd}


def test_unlisted_option_value_is_unknown_not_zero():
    e = cost.entry_for(trellis(resolution=2048), "three_d", PRICES, command="to3d", stage="to3d")
    assert (e.basis, e.usd) == ("unknown", None)


def test_estimate_uses_options_actually_sent(staged, capsys, monkeypatch):
    monkeypatch.setattr(cost, "load_prices", lambda path=None: PRICES)
    root, cfg = staged
    est = lambda *a: run(capsys, "to3d", "angler", "--3d-provider", "trellis", "--estimate", *a)[1]["estimate"]  # noqa: E731
    assert est()["usd"] == pytest.approx(0.30)  # providers.yaml sets resolution 1024
    assert est("--option", "resolution=512")["usd"] == pytest.approx(0.25)
    assert est("--option", "resolution=1536")["usd"] == pytest.approx(0.35)


def test_committed_prices_cover_trellis_resolutions():
    prices = cost.load_prices()
    for res, usd in ((512, 0.25), (1024, 0.30), (1536, 0.35)):
        p = trellis(resolution=res)
        assert cost.unit_usd(p, "three_d", prices) == (pytest.approx(usd), "estimated")
