import pytest


@pytest.fixture
def root(tmp_path, monkeypatch):
    (tmp_path / "project.godot").write_text("")
    monkeypatch.setenv("ASSET_PIPELINE_ROOT", str(tmp_path))
    return tmp_path
