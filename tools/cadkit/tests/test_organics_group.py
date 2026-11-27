"""The organics group: builds, checks and verifies like any group, with its own budget and no mount checks."""
import textwrap

from cadkit import build, library

SCENE = '''
from cadkit.library import out_dir, write_entry
from cadkit.solids import Solid, box, export_solids_glb

SLUG, GROUP = "tiny_fish", "organics"
USES: list[str] = []


def build() -> dict:
    rep = export_solids_glb([Solid(box(40, 10, 100), "trim_black")], out_dir(GROUP, SLUG) / "tiny_fish.glb", "N")
    write_entry(GROUP, SLUG, {"kind": "element", "summary": "test", "tags": [], "triangles": rep["triangles"]})
    return {"slug": SLUG, "triangles": rep["triangles"]}
'''


def test_group_and_budget():
    assert "organics" in library.GROUPS
    assert library.TRIANGLE_BUDGET["organics"] == 8000


def test_an_organics_scene_builds_checks_and_verifies(tmp_path):
    scenes, models = tmp_path / "scenes", tmp_path / "models"
    scenes.mkdir()
    models.mkdir()
    (scenes / "tiny_fish.py").write_text(textwrap.dedent(SCENE))
    assert build.run("check", scenes, models)["ok"]
    assert build.run("build", scenes, models)["ok"]
    assert (models / "organics" / "tiny_fish" / "tiny_fish.glb").is_file()
    assert build.run("verify", scenes, models)["ok"]


def test_mounts_are_not_checked_for_organics(monkeypatch):
    monkeypatch.setattr(build.mount, "problems", lambda *a: ["should not be called"])
    build._check_mounts("tiny_fish", "organics")
