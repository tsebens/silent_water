"""Top and bottom turnaround views: class-selected generation, per-provider views for to3d."""
import json
import shutil
from pathlib import Path

import pytest

from asset_pipeline import cli, paths, providers
from asset_pipeline.manifest import Manifest

REPO = Path(__file__).resolve().parents[3]
SIX = ["front", "left", "back", "right", "top", "bottom"]
FOUR = SIX[:4]


def run(capsys, *argv):
    code = cli.main(list(argv))
    return code, json.loads(capsys.readouterr().out)


@pytest.fixture
def staged(root, capsys):
    sb = root / "assets" / "style_bible"
    sb.mkdir(parents=True)
    shutil.copy(REPO / "assets" / "style_bible" / "classes.yaml", sb / "classes.yaml")
    run(capsys, "new", "angler", "--class", "creature")
    run(capsys, "new", "crate", "--class", "prop")
    for slug in ("angler", "crate"):
        run(capsys, "concept", slug, "--n", "1", "--brief", "a thing")
        run(capsys, "lock", slug, "v1")
    return root


def ids(root, slug, prefix):
    m = Manifest.load(paths.manifest_path(root, slug))
    return [e.id for e in m.lineage if e.id.startswith(prefix)]


def test_turnaround_makes_the_classes_views(staged, capsys):
    code, out = run(capsys, "turnaround", "angler")
    assert code == 0 and [v["view"] for v in out["views"]] == SIX
    code, out = run(capsys, "turnaround", "crate")
    assert code == 0 and [v["view"] for v in out["views"]] == FOUR


def test_top_and_bottom_prompts_are_straight_down_and_up(staged, capsys):
    run(capsys, "turnaround", "angler")
    m = Manifest.load(paths.manifest_path(staged, "angler"))
    assert "straight down" in m.entry("t1_top").prompt and "2048" in m.entry("t1_top").prompt
    assert "straight up" in m.entry("t1_bottom").prompt
    assert "straight" not in m.entry("t1_front").prompt


def test_each_extra_view_works_alone(staged, capsys):
    run(capsys, "turnaround", "angler")
    for view in ("top", "bottom"):
        code, out = run(capsys, "turnaround", "angler", "--view", view)
        assert code == 0 and [v["view"] for v in out["views"]] == SIX
        assert [v["view"] for v in out["views"] if "carried_from" not in v] == [view]
    assert len(ids(staged, "angler", "t3_")) == 6


def test_an_extra_view_joins_a_four_view_asset(staged, capsys):
    run(capsys, "turnaround", "crate")
    code, out = run(capsys, "turnaround", "crate", "--view", "top")
    assert code == 0 and [v["view"] for v in out["views"]] == FOUR + ["top"]
    code, out = run(capsys, "turnaround", "crate", "--view", "left")  # the set keeps its top
    assert [v["view"] for v in out["views"]] == FOUR + ["top"]


def test_estimate_counts_the_classes_views(staged, capsys):
    _, a = run(capsys, "turnaround", "angler", "--estimate")
    _, c = run(capsys, "turnaround", "crate", "--estimate")
    assert a["estimate"]["calls"][0]["count"] == 6 and c["estimate"]["calls"][0]["count"] == 4


class Recorder(providers.MockThreeDProvider):
    sent: list = []

    def submit(self, views):
        Recorder.sent.append([v.name for v in views])
        return super().submit(views)


def test_to3d_sends_each_provider_its_views(staged, capsys, monkeypatch):
    run(capsys, "turnaround", "angler")
    monkeypatch.setitem(providers.REGISTRY["three_d"], "rec", Recorder)
    cfg = providers.load_config()
    cfg["providers"]["three_d"].update({"rec6": {"adapter": "rec", "views": SIX}, "rec1": {"adapter": "rec", "views": ["front"]},
                                        "rec4": {"adapter": "rec"}})
    monkeypatch.setattr(providers, "load_config", lambda *a, **k: cfg)
    Recorder.sent = []
    code, out = run(capsys, "to3d", "angler", "--3d-provider", "rec6", "rec1", "rec4", "--poll-interval", "0")
    assert code == 0, out
    assert [[n.rsplit("_", 1)[1][:-4] for n in s] for s in Recorder.sent] == [SIX, ["front"], FOUR]
    m = Manifest.load(paths.manifest_path(staged, "angler"))
    assert len(m.entry("r1_rec6").references) == 6 and len(m.entry("r1_rec1").references) == 1


def test_committed_providers_have_the_documented_views():
    cfg = providers.load_config()
    assert providers.select("three_d", cfg, "trellis-multi").views == tuple(SIX)
    assert providers.select("three_d", cfg, "trellis").views == ("front",)
    for name in ("tripo", "meshy", "rodin", "mock"):
        assert providers.select("three_d", cfg, name).views is None  # default: the class's views, else the four


def test_bad_views_are_rejected():
    for bad in ([], ["sideways"], ["front", "front"], "front"):
        with pytest.raises(ValueError, match="views"):
            providers.build("three_d", "x", {"adapter": "mock", "views": bad})
