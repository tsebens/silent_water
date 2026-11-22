"""tools/validate_style_bible.py checks the per-class style files."""
import importlib.util
import shutil
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
