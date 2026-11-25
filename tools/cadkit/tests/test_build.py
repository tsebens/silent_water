"""The build's contract, on a tiny fake tree: discovery from USES, all or nothing, stale files, verify."""
import textwrap

import pytest
import yaml

from cadkit import build

SCENE = '''
from cadkit.library import entry, out_dir, write_entry
from cadkit.solids import Solid, box, expect, export_solids_glb

SLUG, GROUP = "{slug}", "kit"
USES: list[str] = {uses}
WIDTH = {width}


def build() -> dict:
    limit = min([entry(u)["width"] for u in USES], default=1000)
    expect(WIDTH <= limit, f"{{SLUG}} ({{WIDTH}} mm) fits what it uses ({{limit}} mm)")
    rep = export_solids_glb([Solid(box(WIDTH, 10, 10), "trim_black")], out_dir(GROUP, SLUG) / "{glb}.glb", "N")
    write_entry(GROUP, SLUG, {{"kind": "element", "summary": "test", "tags": [], "width": WIDTH,
                                "triangles": rep["triangles"]}})
    return {{"slug": SLUG, "triangles": rep["triangles"]}}
'''


def write_scene(folder, slug, uses=(), width=50, glb=None):
    (folder / f"{slug}.py").write_text(textwrap.dedent(SCENE).format(slug=slug, uses=list(uses), width=width, glb=glb or slug))


@pytest.fixture
def tree(tmp_path):
    scenes, models = tmp_path / "scenes", tmp_path / "models"
    scenes.mkdir()
    models.mkdir()
    write_scene(scenes, "plate", width=100)
    write_scene(scenes, "knob", uses=["plate"], width=40)
    return scenes, models


def snapshot(models):
    return {p.relative_to(models).as_posix(): p.read_bytes() for p in sorted(models.rglob("*")) if p.is_file()}


def test_order_puts_a_scene_after_what_it_uses_with_no_list_anywhere(tree):
    scenes, _ = tree
    write_scene(scenes, "a_panel", uses=["knob"], width=30)
    assert build.order(build.discover(scenes)) == ["plate", "knob", "a_panel"]


def test_unknown_use_and_cycles_are_errors(tree):
    scenes, _ = tree
    write_scene(scenes, "lamp", uses=["nothing"])
    with pytest.raises(build.BuildFailed, match="no build script"):
        build.order(build.discover(scenes))
    write_scene(scenes, "lamp", uses=["knob"])
    write_scene(scenes, "plate", uses=["lamp"])
    with pytest.raises(build.BuildFailed, match="cycle"):
        build.order(build.discover(scenes))


def test_build_writes_the_tree_and_a_rebuild_changes_nothing(tree):
    scenes, models = tree
    out = build.run("build", scenes, models)
    assert out["ok"] and "kit/knob/knob.glb" in out["changed"]
    entry = yaml.safe_load((models / "kit" / "knob" / "component.yaml").read_text())
    assert entry["files"] == ["component.yaml", "knob.glb"] and entry["built_by"] == "tools/cadkit/scenes/knob.py"
    before = snapshot(models)
    again = build.run("build", scenes, models)
    assert again["ok"] and again["changed"] == [] and snapshot(models) == before


def test_check_writes_nothing(tree):
    scenes, models = tree
    assert build.run("check", scenes, models)["ok"]
    assert snapshot(models) == {}


def test_a_shared_part_that_breaks_its_user_is_never_written(tree):
    scenes, models = tree
    build.run("build", scenes, models)
    before = snapshot(models)
    write_scene(scenes, "plate", width=20)            # the knob (40 mm) no longer fits the plate
    out = build.run("build", scenes, models)
    assert not out["ok"] and out["failed"] == "knob" and "fits what it uses (20 mm)" in out["error"]
    assert snapshot(models) == before, "not even the plate, which passed its own checks"


def test_a_file_a_scene_stops_making_is_removed(tree):
    scenes, models = tree
    build.run("build", scenes, models)
    (models / "kit" / "knob" / "notes.md").write_text("hand-written, not generated")
    write_scene(scenes, "knob", uses=["plate"], width=40, glb="knob_v2")
    out = build.run("build", scenes, models)
    assert out["ok"]
    assert not (models / "kit" / "knob" / "knob.glb").exists() and (models / "kit" / "knob" / "knob_v2.glb").exists()
    assert (models / "kit" / "knob" / "notes.md").exists(), "files the build did not make are left alone"


def test_verify_reports_stale_and_hand_edited_files(tree):
    scenes, models = tree
    build.run("build", scenes, models)
    clean = build.run("verify", scenes, models)
    assert clean["ok"] and clean["problems"] == []
    entry = models / "kit" / "knob" / "component.yaml"
    entry.write_text(entry.read_text().replace("summary: test", "summary: edited by hand"))
    write_scene(scenes, "plate", width=90)            # the script changed but nobody rebuilt
    out = build.run("verify", scenes, models)
    assert not out["ok"]
    assert any("kit/knob/component.yaml" in p and "by hand" in p for p in out["problems"])
    assert any("kit/plate/plate.glb" in p for p in out["problems"])


def test_a_scene_over_its_groups_triangle_budget_fails(tree, monkeypatch):
    scenes, models = tree
    monkeypatch.setitem(build.library.TRIANGLE_BUDGET, "kit", 10)
    out = build.run("build", scenes, models)
    assert not out["ok"] and "12 triangles; the budget for kit is 10" in out["error"]
    assert snapshot(models) == {}


def test_verify_reports_a_scene_folder_with_no_build_script(tree):
    scenes, models = tree
    build.run("build", scenes, models)
    (scenes / "knob.py").unlink()
    out = build.run("verify", scenes, models)
    assert any("kit/knob/component.yaml: no build script" in p for p in out["problems"])
