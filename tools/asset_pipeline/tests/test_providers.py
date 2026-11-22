import pytest

from asset_pipeline import providers as P


def cfg():
    return P.load_config()


def test_default_selection_from_yaml():
    c = cfg()
    assert isinstance(P.select("image", c), P.MockImageProvider)
    assert isinstance(P.select("three_d", c), P.MockThreeDProvider)
    assert isinstance(P.select("prompt_writer", c), P.MockPromptWriter)


def test_selection_and_model_come_from_config():
    c = cfg()
    c["selection"]["image"] = "alt"
    c["providers"]["image"]["alt"] = {"model": "alt-model"}
    P.REGISTRY["image"]["alt"] = P.MockImageProvider
    try:
        assert P.select("image", c).model == "alt-model"
        # a command override beats the configured default
        assert P.select("image", c, override="mock").model == "mock-image-1"
    finally:
        del P.REGISTRY["image"]["alt"]


def test_unknown_provider_errors():
    with pytest.raises(ValueError):
        P.select("image", cfg(), override="nope")
    with pytest.raises(ValueError):
        P.select("sound", cfg())


def test_mock_image_deterministic(tmp_path):
    a, b = P.MockImageProvider(), P.MockImageProvider()
    a.generate("x", [], tmp_path / "1.png")
    b.generate("x", [], tmp_path / "2.png")
    b.generate("y", [], tmp_path / "3.png")
    assert (tmp_path / "1.png").read_bytes() == (tmp_path / "2.png").read_bytes()
    assert (tmp_path / "1.png").read_bytes() != (tmp_path / "3.png").read_bytes()
    assert (tmp_path / "1.png").read_bytes().startswith(b"\x89PNG")


def test_mock_3d_and_writer(tmp_path):
    t = P.MockThreeDProvider()
    job = t.submit([tmp_path / "front.png"])
    assert t.poll(job) == "done"
    t.download(job, tmp_path / "m.glb")
    assert (tmp_path / "m.glb").read_bytes()[:4] == b"glTF"
    assert t.submit([tmp_path / "front.png"]) == job
    w = P.MockPromptWriter()
    assert w.write_prompts("b", "s", "", [], 3) == w.write_prompts("b", "s", "", [], 3)
    assert len(w.write_prompts("b", "s", "", [], 3)) == 3


# ---- providers.local.yaml ----------------------------------------------------------------

LOCAL = "selection:\n  image: google\n  three_d: tripo\n  prompt_writer: claude-cli\n"


def local_file(tmp_path, monkeypatch, text):
    f = tmp_path / "providers.local.yaml"
    f.write_text(text)
    monkeypatch.setenv("ASSET_PROVIDERS_LOCAL", str(f))
    return f


def test_no_local_file_is_identical_to_committed(tmp_path):
    import yaml
    c = cfg()
    committed = yaml.safe_load(P.DEFAULT_CONFIG.read_text())
    assert c["selection"] == committed["selection"]
    assert set(c["selection_source"].values()) == {"committed"}


def test_local_overrides_committed_and_flag_overrides_local(tmp_path, monkeypatch):
    local_file(tmp_path, monkeypatch, LOCAL)
    c = cfg()
    assert c["selection"] == {"image": "google", "three_d": "tripo", "prompt_writer": "claude-cli"}
    assert set(c["selection_source"].values()) == {"local"}
    assert P.select("image", c).name == "google"
    assert P.select("three_d", c).name == "tripo"
    assert P.select("prompt_writer", c).name == "claude-cli"
    assert P.select("image", c, override="mock").name == "mock"
    assert P.select("three_d", c, override="mock").name == "mock"
    assert P.select("prompt_writer", c, override="mock").name == "mock"


def test_local_overrides_key_by_key(tmp_path, monkeypatch):
    local_file(tmp_path, monkeypatch, "selection:\n  prompt_writer: claude-cli\n")
    c = cfg()
    assert c["selection"]["prompt_writer"] == "claude-cli" and c["selection"]["image"] == "mock"
    assert c["selection_source"] == {"image": "committed", "three_d": "committed", "prompt_writer": "local"}


@pytest.mark.parametrize("text", [
    "selection:\n  image: nope\n",
    "selection:\n  bogus: mock\n",
    "providers:\n  image: {}\n",
])
def test_local_file_errors_are_clear(tmp_path, monkeypatch, text):
    local_file(tmp_path, monkeypatch, text)
    with pytest.raises(ValueError, match="providers.local.yaml"):
        cfg()


def test_doctor_and_list_report_effective_selection_and_source(tmp_path, monkeypatch, root, capsys):
    import json
    from asset_pipeline import cli, doctor
    local_file(tmp_path, monkeypatch, "selection:\n  prompt_writer: claude-cli\n")
    r = doctor.run(cfg())
    assert r["selected"]["prompt_writer"] == "claude-cli"
    assert r["selected_source"] == {"image": "committed", "three_d": "committed", "prompt_writer": "local"}
    assert cli.main(["list"]) == 0
    out = json.loads(capsys.readouterr().out)
    assert out["selected"]["prompt_writer"] == "claude-cli"
    assert out["selected_source"]["prompt_writer"] == "local" and out["selected_source"]["image"] == "committed"


def test_local_file_is_ignored_by_git_and_example_exists():
    import subprocess
    root = P.DEFAULT_CONFIG.parent
    assert (root / "providers.local.example.yaml").is_file()
    r = subprocess.run(["git", "check-ignore", "-q", str(root / "providers.local.yaml")], cwd=root)
    assert r.returncode == 0
    import yaml
    ex = yaml.safe_load((root / "providers.local.example.yaml").read_text())
    for kind, name in ex["selection"].items():
        assert name in yaml.safe_load(P.DEFAULT_CONFIG.read_text())["providers"][kind]
