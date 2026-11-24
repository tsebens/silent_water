"""tools/validate_style_bible.py checks the per-class style files."""
import importlib.util
import shutil

import yaml
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]


def load(tmp_path):
    spec = importlib.util.spec_from_file_location("validate_style_bible", REPO / "tools" / "validate_style_bible.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    root = tmp_path / "style_bible"
    shutil.copytree(REPO / "assets" / "style_bible", root)
    mod.ROOT = root
    return mod, root


def test_repo_passes():
    spec = importlib.util.spec_from_file_location("validate_style_bible", REPO / "tools" / "validate_style_bible.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    assert mod.validate() == []


def test_missing_class_file_fails(tmp_path):
    mod, root = load(tmp_path)
    (root / "classes" / "prop.md").unlink()
    assert any("classes/prop.md missing" in e for e in mod.validate())


def test_missing_section_fails(tmp_path):
    mod, root = load(tmp_path)
    (root / "classes" / "terrain.md").write_text("## Style\nrocks\n")
    errs = mod.validate()
    assert any("terrain.md" in e and "Avoid" in e for e in errs)
    (root / "classes" / "terrain.md").write_text("## Avoid\n- x\n")
    assert any("terrain.md" in e and "Style" in e for e in mod.validate())


def _set_budget(root, value):
    import yaml
    f = root / "classes.yaml"
    data = yaml.safe_load(f.read_text())
    data["classes"]["prop"]["budget_usd"] = value
    f.write_text(yaml.safe_dump(data))


def test_budget_usd_is_optional_and_validated(tmp_path):
    mod, root = load(tmp_path)
    for ok in (0, 2, 7.5):
        _set_budget(root, ok)
        assert mod.validate() == []
    for bad in (-1, "5", True, None):
        _set_budget(root, bad)
        assert any("budget_usd" in e for e in mod.validate()), bad


def _set_views(root, value):
    f = root / "classes.yaml"
    data = yaml.safe_load(f.read_text())
    data["classes"]["prop"]["turnaround_views"] = value
    f.write_text(yaml.safe_dump(data))


def test_turnaround_views_are_validated(tmp_path):
    mod, root = load(tmp_path)
    assert "turnaround_views" in yaml.safe_load((root / "classes.yaml").read_text())["classes"]["creature"]
    for ok in (["front"], ["front", "left", "back", "right", "top", "bottom"]):
        _set_views(root, ok)
        assert mod.validate() == [], ok
    for bad in ([], "front", None, ["front", "up"], ["front", "front"], [3]):
        _set_views(root, bad)
        assert any("turnaround_views" in e for e in mod.validate()), bad


def test_to3d_views_are_validated(tmp_path):
    mod, root = load(tmp_path)
    f = root / "classes.yaml"

    def put(value):
        data = yaml.safe_load(f.read_text())
        data["classes"]["prop"]["to3d_views"] = value
        f.write_text(yaml.safe_dump(data))

    for ok in (["front"], ["left"], ["left", "front", "top"]):
        put(ok)
        assert mod.validate() == [], ok
    for bad in ([], "left", None, ["front", "up"], ["front", "front"], [3]):
        put(bad)
        assert any("to3d_views" in e for e in mod.validate()), bad
    data = yaml.safe_load(f.read_text())
    data["classes"]["prop"].update(turnaround_views=["front", "left"], to3d_views=["top"])
    f.write_text(yaml.safe_dump(data))
    assert any("to3d_views" in e and "turnaround_views" in e for e in mod.validate())


def test_concept_presentation_validated(tmp_path):
    mod, root = load(tmp_path)
    f = root / "classes.yaml"
    data = yaml.safe_load(f.read_text())
    assert data["classes"]["interior"]["concept_presentation"] == "scene"
    assert data["classes"]["interior"]["build_route"] == "scripted"
    data["classes"]["prop"]["concept_presentation"] = "scene"
    f.write_text(yaml.safe_dump(data))
    assert mod.validate() == []
    data["classes"]["prop"]["concept_presentation"] = "wide"
    f.write_text(yaml.safe_dump(data))
    assert any("prop" in e and "concept_presentation" in e for e in mod.validate())


def test_interior_must_be_scripted(tmp_path):
    mod, root = load(tmp_path)
    f = root / "classes.yaml"
    data = yaml.safe_load(f.read_text())
    data["classes"]["interior"]["build_route"] = "image-to-3d"
    f.write_text(yaml.safe_dump(data))
    assert any("interior" in e and "scripted" in e for e in mod.validate())
