"""Nested asset folders, moves (with path rewriting), and CLI progress on stderr."""
import json
import shutil

import pytest

from asset_pipeline import cleanup, cli, godot_stage, paths
from asset_pipeline.manifest import LineageEntry, Manifest

from test_check import REPO, asset  # noqa: F401  (asset is a fixture)
from test_godot_stage import make_png


def run(capsys, *argv):
    code = cli.main(list(argv))
    cap = capsys.readouterr()
    return code, json.loads(cap.out), cap.err


def models(root):
    return root / "assets" / "models"


def test_new_in_folder_and_flat_both_found(root, capsys):
    assert run(capsys, "new", "flat", "--class", "prop")[0] == 0
    code, out, _ = run(capsys, "new", "apex", "--class", "creature", "--folder", "organic/fauna")
    assert code == 0 and out["manifest"] == "assets/models/organic/fauna/apex/asset.yaml" and out["folder"] == "organic/fauna"
    assert paths.manifest_path(root, "flat") == models(root) / "flat" / "asset.yaml"
    assert paths.manifest_path(root, "apex") == models(root) / "organic" / "fauna" / "apex" / "asset.yaml"
    assert paths.work_dir(root, "apex") == root / ".asset_work" / "apex"
    code, out, _ = run(capsys, "list")
    assert code == 0
    by = {a["slug"]: a["folder"] for a in out["assets"]}
    assert by == {"apex": "organic/fauna", "flat": ""}
    assert out["folders"] == ["organic", "organic/fauna"]
    assert run(capsys, "describe", "apex", "x")[0] == 0  # commands find it in its folder


def test_slug_unique_across_folders(root, capsys):
    run(capsys, "new", "apex", "--class", "creature", "--folder", "a")
    code, out, _ = run(capsys, "new", "apex", "--class", "creature", "--folder", "b")
    assert code == 1 and "already exists" in out["error"]
    code, out, _ = run(capsys, "new", "apex", "--class", "creature")
    assert code == 1
    assert not (models(root) / "b").exists()


def test_new_inside_asset_or_bad_folder_is_error(root, capsys):
    run(capsys, "new", "apex", "--class", "creature")
    assert run(capsys, "new", "x", "--class", "prop", "--folder", "apex/sub")[0] == 1
    assert run(capsys, "new", "x", "--class", "prop", "--folder", "../up")[0] == 1
    assert run(capsys, "new", "x", "--class", "prop", "--folder", "Bad Name")[0] == 1


def test_folder_create_rules(root, capsys):
    run(capsys, "new", "apex", "--class", "creature", "--folder", "a")
    code, out, _ = run(capsys, "folder", "create", "empty/deep")
    assert code == 0 and (models(root) / "empty" / "deep").is_dir()
    assert "empty/deep" in run(capsys, "list")[1]["folders"]
    assert run(capsys, "folder", "create", "empty/deep")[0] == 1  # exists
    assert run(capsys, "folder", "create", "a/apex")[0] == 1  # hides an asset
    assert run(capsys, "folder", "create", "a/apex/inner")[0] == 1  # nests in an asset
    assert run(capsys, "folder", "create", "")[0] == 1


def test_move_asset_rewrites_manifest_report_and_scene_and_still_exports(asset, capsys):  # noqa: F811
    root = asset
    mpath = models(root) / "blob" / "asset.yaml"
    big = root / ".asset_work" / "blob" / "concept" / "v1.png"
    make_png(big, 600, 300)
    m = Manifest.load(mpath)
    m.add(LineageEntry(id="v1", kind="concept", path=big.relative_to(root).as_posix(), provider="mock", model="mock"))
    m.lock("v1", reviewer="t")
    m.stage = "cleanup"
    m.save(mpath)
    assert run(capsys, "check", "blob")[0] == 0
    assert run(capsys, "export", "blob")[0] == 0
    old = "assets/models/blob"
    code, out, _ = run(capsys, "move", "blob", "--to", "organic/fauna")
    assert code == 0 and out["asset_dir"] == "assets/models/organic/fauna/blob"
    new = "assets/models/organic/fauna/blob"
    assert not (models(root) / "blob").exists()
    d = root / new
    assert "res://assets/models/organic/fauna/blob/blob.glb" in (d / "blob.tscn").read_text()
    assert f'source_file="res://{new}/blob.glb"' in (d / "blob.glb.import").read_text()
    text = (d / "asset.yaml").read_text()
    assert old + "/" not in text.replace(new, "") and new + "/concept" in text
    m2 = Manifest.load(d / "asset.yaml")
    assert m2.checks[-1].report == f"{new}/checks/c1.json"
    assert all(f.startswith(new + "/") for f in m2.exports[-1].files)
    assert "\\" not in text
    report = (d / "checks" / "c1.json").read_text()
    assert old + "/" not in report.replace(new, "")
    assert run(capsys, "check", "blob")[0] == 0
    assert run(capsys, "export", "blob")[0] == 0
    assert (d / "blob.glb").is_file() and not (models(root) / "blob").exists()
    assert Manifest.load(d / "asset.yaml").exports[-1].files[0].startswith(new)


def test_move_errors_and_root(root, capsys):
    run(capsys, "new", "apex", "--class", "creature", "--folder", "a")
    run(capsys, "new", "other", "--class", "prop")
    assert run(capsys, "move", "apex", "--to", "a")[0] == 1  # already there
    assert run(capsys, "move", "apex", "--to", "other")[0] == 1  # into an asset
    assert run(capsys, "move", "apex", "--to", "other/x")[0] == 1
    assert run(capsys, "move", "ghost", "--to", "a")[0] == 1
    (models(root) / "b" / "apex").mkdir(parents=True)  # a leftover directory in the way
    assert run(capsys, "move", "apex", "--to", "b")[0] == 1
    assert (models(root) / "a" / "apex" / "asset.yaml").is_file()
    shutil.rmtree(models(root) / "b")
    assert run(capsys, "move", "apex", "--to", "")[0] == 0  # back to the root
    assert (models(root) / "apex" / "asset.yaml").is_file()


def test_folder_move_and_rename_rewrite_every_asset_inside(root, capsys):
    run(capsys, "new", "apex", "--class", "creature", "--folder", "org/fauna")
    run(capsys, "new", "kelp", "--class", "creature", "--folder", "org/flora")
    mpath = paths.manifest_path(root, "apex")
    m = Manifest.load(mpath)
    m.add(LineageEntry(id="v1", kind="turnaround", path="assets/models/org/fauna/apex/concept/t.png", provider="m", model="m"))
    m.save(mpath)
    run(capsys, "folder", "create", "dest")
    code, out, _ = run(capsys, "folder", "move", "org", "--to", "dest")
    assert code == 0 and out["folder"] == "dest/org"
    assert Manifest.load(paths.manifest_path(root, "apex")).lineage[0].path == "assets/models/dest/org/fauna/apex/concept/t.png"
    code, out, _ = run(capsys, "folder", "rename", "dest/org", "life")
    assert code == 0 and out["folder"] == "dest/life"
    assert Manifest.load(paths.manifest_path(root, "apex")).lineage[0].path == "assets/models/dest/life/fauna/apex/concept/t.png"
    assert paths.find_asset_dir(root, "kelp") == models(root) / "dest" / "life" / "flora" / "kelp"
    assert not (models(root) / "org").exists()


def test_folder_move_errors(root, capsys):
    run(capsys, "new", "apex", "--class", "creature", "--folder", "a/b")
    run(capsys, "folder", "create", "c")
    assert run(capsys, "folder", "move", "a", "--to", "a/b")[0] == 1  # into itself
    assert run(capsys, "folder", "move", "a", "--to", "a")[0] == 1
    assert run(capsys, "folder", "move", "a/b/apex", "--to", "c")[0] == 1  # an asset is not a folder
    assert run(capsys, "folder", "move", "a/b", "--to", "a/b/apex")[0] == 1  # into an asset
    assert run(capsys, "folder", "move", "nope", "--to", "c")[0] == 1
    assert run(capsys, "folder", "rename", "a", "c")[0] == 1  # exists
    assert run(capsys, "folder", "rename", "a", "x/y")[0] == 1
    assert run(capsys, "folder", "rename", "a/b", "b")[0] == 1


# --- progress on stderr ---------------------------------------------------------------------------------------

def test_progress_on_stderr_and_stdout_is_one_json_object(root, capsys, monkeypatch):
    sb = root / "assets" / "style_bible"
    sb.mkdir(parents=True)
    shutil.copy(REPO / "assets" / "style_bible" / "classes.yaml", sb / "classes.yaml")
    (sb / "style.md").write_text("STYLE")
    monkeypatch.setattr(cleanup, "resolve_runner", lambda: cleanup.Runner("native", "blender"))
    monkeypatch.setattr(cleanup, "run_blender", lambda params, workdir, runner=None, root=None: {"blender_version": "stub"})
    monkeypatch.setattr(godot_stage, "godot_check",
                        lambda *a, **k: {"ok": True, "material": {}, "renders": []})
    assert run(capsys, "new", "eel", "--class", "creature", "--folder", "deep")[0] == 0
    seen = {}
    for argv in (("concept", "eel", "--n", "2", "--brief", "an eel"),
                 ("lock", "eel", "v1", "--reviewer", "t"),
                 ("turnaround", "eel"),
                 ("brief", "eel"),
                 ("to3d", "eel", "--poll-interval", "0"),
                 ("cleanup", "eel", "--source", "r1_mock", "--size-m", "1"),
                 ("godot-check", "eel", "--log-dir", str(root / "logs"))):
        code = cli.main(list(argv))
        cap = capsys.readouterr()
        assert code == 0, (argv, cap.out)
        assert json.loads(cap.out)["ok"] is True  # stdout is exactly one JSON object
        if argv[0] == "lock":
            continue  # not a long command
        assert cap.err.strip(), argv
        assert all(line.strip() and "{" not in line for line in cap.err.splitlines())
        seen[argv[0]] = cap.err
    assert "writing prompts (mock" in seen["concept"] and "image 2/2" in seen["concept"]
    assert "view 6/6" in seen["turnaround"]


def test_no_progress_on_estimate_or_errors(root, capsys):
    code, out, err = run(capsys, "concept", "ghost")
    assert code == 1 and err == ""
