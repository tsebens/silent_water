import json

import pytest

from asset_pipeline import cli, paths
from asset_pipeline.manifest import LineageEntry, Manifest


def run(capsys, *argv):
    code = cli.main(list(argv))
    return code, json.loads(capsys.readouterr().out)


def test_new_creates_manifest_and_folders(root, capsys):
    code, out = run(capsys, "new", "angler", "--class", "creature", "--issue", "9")
    assert code == 0 and out["ok"] and out["slug"] == "angler" and out["class"] == "creature"
    m = Manifest.load(paths.manifest_path(root, "angler"))
    assert m.issue == 9 and m.asset_class == "creature" and m.stage == "new"
    assert paths.work_dir(root, "angler").is_dir()


def test_new_twice_and_bad_slug_fail(root, capsys):
    run(capsys, "new", "angler", "--class", "creature")
    code, out = run(capsys, "new", "angler", "--class", "creature")
    assert code == 1 and not out["ok"]
    code, out = run(capsys, "new", "../x", "--class", "prop")
    assert code == 1 and not out["ok"]


def test_lock_records_variant_and_reviewer(root, capsys):
    run(capsys, "new", "angler", "--class", "creature")
    mp = paths.manifest_path(root, "angler")
    m = Manifest.load(mp)
    m.add(LineageEntry(id="v1", kind="concept", path="v1.png", provider="mock", model="m"))
    m.save(mp)
    code, out = run(capsys, "lock", "angler", "v1", "--reviewer", "tristan", "--notes", "yes")
    assert code == 0 and out["locked"] and out["stage"] == "locked"
    m = Manifest.load(mp)
    assert m.locked.variant == "v1" and m.locked.reviewer == "tristan" and m.locked.decision == "approved"
    code, out = run(capsys, "lock", "angler", "nope")
    assert code == 1 and not out["ok"]
