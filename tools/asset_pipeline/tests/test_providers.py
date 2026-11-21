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
