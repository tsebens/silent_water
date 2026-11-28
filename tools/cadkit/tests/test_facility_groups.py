"""The facility_parts and facilities groups: build and verify like any group, with their own budgets and no mount checks."""
import textwrap

import pytest

from cadkit import build, library

SCENE = '''
from cadkit.library import out_dir, write_entry
from cadkit.solids import Solid, box, export_solids_glb

SLUG, GROUP = "{slug}", "{group}"
USES: list[str] = []


def build() -> dict:
    rep = export_solids_glb([Solid(box(500, 100, 500), "trim_black")], out_dir(GROUP, SLUG) / "{slug}.glb", "N")
    write_entry(GROUP, SLUG, {{"kind": "element", "summary": "test", "tags": [], "triangles": {tris} or rep["triangles"]}})
    return {{"slug": SLUG, "triangles": rep["triangles"]}}
'''

CASES = [("facility_parts", 2000), ("facilities", 60000)]


def _setup(tmp_path, group, tris=0):
    scenes, models = tmp_path / "scenes", tmp_path / "models"
    scenes.mkdir()
    models.mkdir()
    (scenes / "fixture.py").write_text(textwrap.dedent(SCENE.format(slug="fixture", group=group, tris=tris)))
    return scenes, models


@pytest.mark.parametrize("group,budget", CASES)
def test_group_and_budget(group, budget):
    assert group in library.GROUPS
    assert library.TRIANGLE_BUDGET[group] == budget


@pytest.mark.parametrize("group,budget", CASES)
def test_a_fixture_builds_and_verifies(tmp_path, group, budget):
    scenes, models = _setup(tmp_path, group)
    assert build.run("check", scenes, models)["ok"]
    assert build.run("build", scenes, models)["ok"]
    assert (models / group / "fixture" / "fixture.glb").is_file()
    assert build.run("verify", scenes, models)["ok"]


@pytest.mark.parametrize("group,budget", CASES)
def test_over_budget_fails_naming_scene_and_budget(tmp_path, group, budget):
    scenes, models = _setup(tmp_path, group, tris=budget + 1)
    result = build.run("build", scenes, models)
    assert not result["ok"]
    text = str(result)
    assert "fixture" in text and str(budget) in text


@pytest.mark.parametrize("group,budget", CASES)
def test_mounts_are_not_checked(monkeypatch, group, budget):
    monkeypatch.setattr(build.mount, "problems", lambda *a: ["should not be called"])
    build._check_mounts("fixture", group)
