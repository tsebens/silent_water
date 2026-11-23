"""Rename, delete and the trash. Working-tree only; no live API calls."""
import json

from asset_pipeline import cli, paths, trash
from asset_pipeline.manifest import CostRecord, LineageEntry, Manifest

from test_check import asset  # noqa: F401  (fixture)
from test_folders import models, run
from test_godot_stage import make_png


def exported_asset(root, capsys, nested=None):
    """The `blob` fixture, given a locked concept and a cost, checked and exported; optionally moved into a folder."""
    mpath = models(root) / "blob" / "asset.yaml"
    big = root / ".asset_work" / "blob" / "concept" / "v1.png"
    make_png(big, 600, 300)
    m = Manifest.load(mpath)
    m.add(LineageEntry(id="v1", kind="concept", path=big.relative_to(root).as_posix(), provider="mock", model="mock"))
    m.lock("v1", reviewer="t", notes="good")
    m.lock("v1", reviewer="u", decision="rejected")
    m.costs.append(CostRecord(command="concept", stage="concept", provider="mock", model="mock", usd=1.25, basis="reported"))
    m.stage = "cleanup"
    m.save(mpath)
    assert run(capsys, "check", "blob")[0] == 0
    assert run(capsys, "export", "blob")[0] == 0
    if nested:
        assert run(capsys, "move", "blob", "--to", nested)[0] == 0
    return root


def test_rename_rewrites_everything_and_still_checks_and_exports(asset, capsys):  # noqa: F811
    root = exported_asset(asset, capsys)
    before = Manifest.load(models(root) / "blob" / "asset.yaml")
    code, out, _ = run(capsys, "rename", "blob", "reef")
    assert code == 0 and out["asset_dir"] == "assets/models/reef"
    d = models(root) / "reef"
    assert not (models(root) / "blob").exists() and not (root / ".asset_work" / "blob").exists()
    assert (root / ".asset_work" / "reef" / "concept" / "v1.png").is_file()
    for ext in (".glb", ".glb.import", ".tscn"):
        assert (d / f"reef{ext}").is_file() and not (d / f"blob{ext}").exists()
    assert "res://assets/models/reef/reef.glb" in (d / "reef.tscn").read_text()
    assert 'name="Reef"' in (d / "reef.tscn").read_text()
    assert 'source_file="res://assets/models/reef/reef.glb"' in (d / "reef.glb.import").read_text()
    m = Manifest.load(d / "asset.yaml")
    assert m.slug == "reef"
    assert m.checks[-1].report == "assets/models/reef/checks/c1.json"
    assert all("blob" not in f for f in m.exports[-1].files) and "assets/models/reef/reef.glb" in m.exports[-1].files
    assert m.entry("v1").path == ".asset_work/reef/concept/v1.png"
    assert "blob" not in (d / "checks" / "c1.json").read_text()
    # untouched: lineage ids, ledger, decisions
    assert [e.id for e in m.lineage] == [e.id for e in before.lineage]
    assert m.costs == before.costs and m.decisions == before.decisions and m.locked == before.locked
    assert [(r.old, r.new) for r in m.renames] == [("blob", "reef")] and m.renames[0].at
    assert run(capsys, "check", "reef")[0] == 0
    assert run(capsys, "export", "reef")[0] == 0
    assert (d / "reef.glb").is_file() and not (d / "blob.glb").exists()


def test_rename_refuses_invalid_and_taken(asset, capsys):  # noqa: F811
    root = asset
    run(capsys, "new", "other", "--class", "prop")
    before = (models(root) / "blob" / "asset.yaml").read_text()
    for bad in ("Reef", "9lives", "a-b", "has space", "other", "blob"):
        assert run(capsys, "rename", "blob", bad)[0] == 1, bad
    assert run(capsys, "rename", "nothere", "fine")[0] == 1
    assert (models(root) / "blob" / "asset.yaml").read_text() == before


def test_rename_nested_keeps_folder_and_posix_paths(asset, capsys):  # noqa: F811
    root = exported_asset(asset, capsys, nested="organic/fauna")
    code, out, _ = run(capsys, "rename", "blob", "reef")
    assert code == 0 and out["folder"] == "organic/fauna"
    d = models(root) / "organic" / "fauna" / "reef"
    assert d.is_dir() and not (models(root) / "reef").exists()
    text = (d / "asset.yaml").read_text()
    assert "\\" not in text and "organic/fauna/reef/reef.glb" in text
    assert "res://assets/models/organic/fauna/reef/reef.glb" in (d / "reef.tscn").read_text()
    assert run(capsys, "check", "reef")[0] == 0 and run(capsys, "export", "reef")[0] == 0


def test_delete_moves_both_folders_to_trash_and_summary(asset, capsys):  # noqa: F811
    root = exported_asset(asset, capsys)
    code, s, _ = run(capsys, "summary", "blob")
    assert code == 0
    assert s["class"] == "creature" and s["variants"] == 1 and s["meshes"] >= 1 and s["cost_usd"] == 1.25
    assert s["exported"] is True and s["exported_present"] == {"glb": True, "import": True, "tscn": True}
    assert "assets/models/blob/blob.glb" in s["exported_files"]
    code, out, _ = run(capsys, "delete", "blob")
    assert code == 0 and out["summary"]["cost_usd"] == 1.25
    entry = out["trashed"][0]["entry"]
    assert entry.startswith("blob-")
    t = root / ".asset_work" / "_trash" / entry
    assert (t / "asset" / "asset.yaml").is_file() and (t / "work" / "concept" / "v1.png").is_file()
    assert not (models(root) / "blob").exists() and not (root / ".asset_work" / "blob").exists()
    assert run(capsys, "summary", "blob")[0] == 1


def test_delete_folder_empty_and_nonempty(root, capsys):
    run(capsys, "folder", "create", "a/b")
    assert run(capsys, "folder", "delete", "a")[0] == 0
    assert not (models(root) / "a").exists() and not (root / ".asset_work" / "_trash").exists()
    run(capsys, "new", "one", "--class", "prop", "--folder", "x/y")
    run(capsys, "new", "two", "--class", "prop", "--folder", "x")
    code, out, _ = run(capsys, "folder", "delete", "x")
    assert code == 0 and sorted(t["slug"] for t in out["trashed"]) == ["one", "two"]
    assert not (models(root) / "x").exists()
    code, out, _ = run(capsys, "trash", "list")
    assert sorted((e["slug"], e["folder"]) for e in out["entries"]) == [("one", "x/y"), ("two", "x")]
    assert run(capsys, "folder", "delete", "nothere")[0] == 1


def test_trash_list_restore_empty(asset, capsys):  # noqa: F811
    root = asset
    assert run(capsys, "trash", "list")[1]["entries"] == []
    run(capsys, "new", "deep", "--class", "prop", "--folder", "a/b")
    run(capsys, "delete", "blob")
    run(capsys, "delete", "deep")
    code, out, _ = run(capsys, "trash", "list")
    by = {e["slug"]: e for e in out["entries"]}
    assert set(by) == {"blob", "deep"} and by["deep"]["folder"] == "a/b" and by["blob"]["summary"]["class"] == "creature"
    # restore to the original (nested) folder, work dir included
    code, r, _ = run(capsys, "trash", "restore", by["deep"]["entry"])
    assert code == 0 and r["asset_dir"] == "assets/models/a/b/deep"
    assert (models(root) / "a" / "b" / "deep" / "asset.yaml").is_file() and (root / ".asset_work" / "deep").is_dir()
    # a reused slug blocks restore
    run(capsys, "new", "blob", "--class", "prop")
    code, r, _ = run(capsys, "trash", "restore", by["blob"]["entry"])
    assert code == 1 and "reused" in r["error"]
    assert run(capsys, "trash", "restore", "nope-1")[0] == 1
    assert run(capsys, "trash", "restore", "../x")[0] == 1
    code, out, _ = run(capsys, "trash", "empty")
    assert code == 0 and out["removed"] == 1
    assert run(capsys, "trash", "list")[1]["entries"] == []


def test_refused_while_a_command_is_running(asset, capsys):  # noqa: F811
    root = asset
    with trash.hold(root, "blob"):
        assert trash.running(root, "blob")
        code, out, _ = run(capsys, "rename", "blob", "reef")
        assert code == 1 and "running" in out["error"]
        code, out, _ = run(capsys, "delete", "blob")
        assert code == 1 and "running" in out["error"]
        run(capsys, "new", "inner", "--class", "prop", "--folder", "f")
        with trash.hold(root, "inner"):
            assert run(capsys, "folder", "delete", "f")[0] == 1
    assert (models(root) / "blob").is_dir() and (models(root) / "f" / "inner").is_dir()
    assert not trash.running(root, "blob")
    assert run(capsys, "rename", "blob", "reef")[0] == 0


def test_stale_lock_is_ignored(asset):  # noqa: F811
    d = asset / ".asset_work" / "_locks"
    d.mkdir(parents=True, exist_ok=True)
    (d / "blob.99999999.dead").write_text("99999999")
    assert not trash.running(asset, "blob") and not (d / "blob.99999999.dead").exists()


def test_nested_delete_and_restore_keep_posix(asset, capsys):  # noqa: F811
    root = exported_asset(asset, capsys, nested="organic/fauna")
    code, out, _ = run(capsys, "delete", "blob")
    assert code == 0 and out["trashed"][0]["folder"] == "organic/fauna"
    assert "\\" not in json.dumps(out)
    code, out, _ = run(capsys, "trash", "list")
    code, r, _ = run(capsys, "trash", "restore", out["entries"][0]["entry"])
    assert code == 0 and r["asset_dir"] == "assets/models/organic/fauna/blob"
    assert run(capsys, "check", "blob")[0] == 0
