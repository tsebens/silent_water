import json

from asset_pipeline import cli, paths
from asset_pipeline.manifest import Manifest


def run(capsys, *argv):
    code = cli.main(list(argv))
    return code, json.loads(capsys.readouterr().out)


def seed(root, capsys, n_anchors=3):
    sb = root / "assets" / "style_bible"
    (sb / "anchors" / "creature").mkdir(parents=True)
    (sb / "style.md").write_text("STYLE BLOCK")
    (sb / "negative.md").write_text("- no neon magenta")
    for i in range(n_anchors):
        (sb / "anchors" / "creature" / f"a{i}.png").write_bytes(b"x")
    run(capsys, "new", "angler", "--class", "creature")


def test_concept_end_to_end(root, capsys):
    seed(root, capsys)
    code, out = run(capsys, "concept", "angler", "--n", "2", "--brief", "an anglerfish")
    assert code == 0 and [v["id"] for v in out["variants"]] == ["v1", "v2"]
    m = Manifest.load(paths.manifest_path(root, "angler"))
    assert m.stage == "concept" and m.description == "an anglerfish"
    for v in m.lineage:
        assert (root / v.path).is_file()
        assert v.prompt.startswith("STYLE BLOCK") and "no neon magenta" in v.prompt
        assert v.provider == "mock" and v.model == "mock-image-1" and v.writer == "mock:mock-writer-1"
        assert v.parent is None


def test_anchors_are_references_on_every_concept_call(root, capsys, monkeypatch):
    seed(root, capsys, n_anchors=5)
    calls = []
    from asset_pipeline import providers
    orig = providers.MockImageProvider.generate

    def spy(self, prompt, references, out):
        calls.append(references)
        return orig(self, prompt, references, out)

    monkeypatch.setattr(providers.MockImageProvider, "generate", spy)
    run(capsys, "concept", "angler", "--n", "3", "--brief", "b")
    assert len(calls) == 3
    for refs in calls:
        assert [p.name for p in refs] == ["a0.png", "a1.png", "a2.png", "a3.png"]  # capped at 4


def test_refine_records_parent_and_passes_it(root, capsys):
    seed(root, capsys)
    run(capsys, "concept", "angler", "--n", "1", "--brief", "b")
    code, out = run(capsys, "concept", "angler", "--n", "1", "--refine", "v1", "--notes", "longer lure")
    assert code == 0
    m = Manifest.load(paths.manifest_path(root, "angler"))
    v2 = m.entry("v2")
    assert v2.parent == "v1" and "longer lure" in v2.prompt
    assert v2.references[-1].endswith("v1.png") and len(v2.references) == 4
    assert m.ancestry("v2") == ["v2", "v1"]


def test_refine_validation(root, capsys):
    seed(root, capsys)
    code, out = run(capsys, "concept", "angler", "--refine", "v1", "--notes", "x")
    assert code == 1 and "brief" in out["error"]
    run(capsys, "concept", "angler", "--n", "1", "--brief", "b")
    assert run(capsys, "concept", "angler", "--refine", "v1")[0] == 1
    assert run(capsys, "concept", "angler", "--refine", "zzz", "--notes", "x")[0] == 1


def test_turnaround_and_brief(root, capsys):
    seed(root, capsys)
    code, out = run(capsys, "turnaround", "angler")
    assert code == 1 and "lock" in out["error"]
    run(capsys, "concept", "angler", "--n", "1", "--brief", "an anglerfish")
    run(capsys, "lock", "angler", "v1", "--reviewer", "t")
    code, out = run(capsys, "turnaround", "angler")
    assert code == 0 and [v["view"] for v in out["views"]] == ["front", "left", "back", "right"]
    code, out = run(capsys, "brief", "angler")
    assert code == 0 and out["stage"] == "brief"
    d = paths.asset_dir(root, "angler") / "concept"
    assert "anglerfish" in (d / "brief.md").read_text() and (d / ".gdignore").exists()
    assert (d / "turnaround_front.png").is_file()
    m = Manifest.load(paths.manifest_path(root, "angler"))
    t = [e for e in m.lineage if e.kind == "turnaround"]
    assert len(t) == 4 and all(e.parent == "v1" and "2048" in e.prompt for e in t)
    assert m.brief.writer == "mock" and len(m.brief.images) == 5
    # regenerating adds a new set rather than clobbering lineage
    run(capsys, "turnaround", "angler")
    m = Manifest.load(paths.manifest_path(root, "angler"))
    assert len([e for e in m.lineage if e.kind == "turnaround"]) == 8
