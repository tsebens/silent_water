"""`asset concept --reference`: paint-over and inspire, lineage, refine, cost, formats. No live calls."""
import json

from PIL import Image

from asset_pipeline import cli, paths, providers, writers
from asset_pipeline.manifest import Manifest


def run(capsys, *argv):
    code = cli.main(list(argv))
    return code, json.loads(capsys.readouterr().out)


def seed(root, capsys):
    sb = root / "assets" / "style_bible"
    (sb / "anchors" / "prop").mkdir(parents=True)
    (sb / "style.md").write_text("STYLE")
    (sb / "anchors" / "prop" / "a0.png").write_bytes(b"x")
    run(capsys, "new", "cabin", "--class", "prop")


def img(path, fmt, size=(32, 24), color=(200, 30, 30)):
    Image.new("RGB", size, color).save(path, format=fmt)
    return path


def concept(capsys, *extra):
    return run(capsys, "concept", "cabin", "--brief", "a cabin", *extra)


def test_two_references_two_variants_each(root, capsys, tmp_path):
    seed(root, capsys)
    a, b = img(tmp_path / "a.png", "PNG"), img(tmp_path / "b.jpg", "JPEG")
    code, out = concept(capsys, "--reference", str(a), "--reference", str(b), "--n", "2")
    assert code == 0 and len(out["variants"]) == 4
    m = Manifest.load(paths.manifest_path(root, "cabin"))
    assert [e.reference["name"] for e in m.lineage] == ["a.png", "a.png", "b.jpg", "b.jpg"]
    assert all(e.mode == "paint-over" and len(e.reference["sha256"]) == 64 for e in m.lineage)
    stored = sorted(p.name for p in (root / ".asset_work" / "cabin" / "references").iterdir())
    assert len(stored) == 2 and all(n.endswith(".png") for n in stored)
    for p in (root / ".asset_work" / "cabin" / "references").iterdir():
        assert Image.open(p).format == "PNG"  # the JPEG is stored as PNG
    text = paths.manifest_path(root, "cabin").read_text()
    assert str(tmp_path) not in text  # the original location is never recorded
    for e in m.lineage:
        assert all(not r.startswith("/") for r in e.references)


def test_paint_over_uses_edit_and_inspire_uses_generate(root, capsys, tmp_path, monkeypatch):
    seed(root, capsys)
    calls = []
    orig_g, orig_e = providers.MockImageProvider.generate, providers.MockImageProvider.edit
    monkeypatch.setattr(providers.MockImageProvider, "generate",
                        lambda self, p, r, o: (calls.append(("generate", None, r)), orig_g(self, p, r, o))[1])
    monkeypatch.setattr(providers.MockImageProvider, "edit",
                        lambda self, p, s, r, o: (calls.append(("edit", s, r)), orig_e(self, p, s, r, o))[1])
    a = img(tmp_path / "a.png", "PNG")
    concept(capsys, "--reference", str(a), "--n", "1")
    concept(capsys, "--reference", str(a), "--mode", "inspire", "--n", "1")
    assert calls[0][0] == "edit" and calls[0][1].parent.name == "references" and calls[0][2][0].name == "a0.png"
    assert calls[1][0] == "generate" and calls[1][2][-1].parent.name == "references"
    m = Manifest.load(paths.manifest_path(root, "cabin"))
    assert [e.mode for e in m.lineage] == ["paint-over", "inspire"]


def test_writer_instructions_differ_by_mode():
    po = writers.prompts_request("b", "s", "", 2, True, "paint-over")
    insp = writers.prompts_request("b", "s", "", 2, True, "inspire")
    none = writers.prompts_request("b", "s", "", 2, True)
    assert "KEEP its composition, camera, proportions and major shapes" in po and "KEEP" not in insp
    assert "composition, camera and proportions may change" in insp
    assert po != insp and "reference" not in none and "starting point" not in none


def test_mock_writer_prompts_differ_by_mode(tmp_path):
    w = providers.MockPromptWriter()
    r = tmp_path / "r.png"
    assert w.write_prompts("b", "s", "", [r], 1, mode="paint-over") != w.write_prompts("b", "s", "", [r], 1, mode="inspire")


def test_refine_of_paint_over_keeps_reference(root, capsys, tmp_path, monkeypatch):
    seed(root, capsys)
    a = img(tmp_path / "a.png", "PNG")
    concept(capsys, "--reference", str(a), "--n", "1")
    seen = []
    orig = providers.MockImageProvider.edit
    monkeypatch.setattr(providers.MockImageProvider, "edit",
                        lambda self, p, s, r, o: (seen.append((s, r)), orig(self, p, s, r, o))[1])
    code, out = run(capsys, "concept", "cabin", "--refine", "v1", "--notes", "darker", "--n", "2")
    assert code == 0 and len(out["variants"]) == 2
    m = Manifest.load(paths.manifest_path(root, "cabin"))
    v1, v2 = m.entry("v1"), m.entry("v2")
    assert v2.reference == v1.reference and v2.mode == "paint-over" and v2.parent == "v1"
    assert seen[0][0].parent.name == "references" and seen[0][1][-1].name == "v1.png"


def test_refine_of_plain_variant_has_no_reference(root, capsys):
    seed(root, capsys)
    concept(capsys, "--n", "1")
    run(capsys, "concept", "cabin", "--refine", "v1", "--notes", "n", "--n", "1")
    assert Manifest.load(paths.manifest_path(root, "cabin")).entry("v2").reference == {}


def test_estimate_and_ledger_count_four(root, capsys, tmp_path):
    seed(root, capsys)
    a, b = img(tmp_path / "a.png", "PNG"), img(tmp_path / "b.jpg", "JPEG")
    args = ["--reference", str(a), "--reference", str(b), "--n", "2"]
    code, out = concept(capsys, *args, "--estimate")
    assert code == 0
    calls = {c["kind"]: c["count"] for c in out["estimate"]["calls"]}
    assert calls["image"] == 4
    assert not (root / ".asset_work" / "cabin" / "references").exists()  # nothing written
    concept(capsys, *args)
    m = Manifest.load(paths.manifest_path(root, "cabin"))
    assert len([c for c in m.costs if c.lineage]) == 4


def test_webp_and_oversize_inputs(root, capsys, tmp_path):
    seed(root, capsys)
    w = img(tmp_path / "w.webp", "WEBP")
    big = img(tmp_path / "big.png", "PNG", size=(3000, 1000))
    code, out = concept(capsys, "--reference", str(w), "--reference", str(big), "--n", "1")
    assert code == 0
    sizes = sorted(Image.open(p).size for p in (root / ".asset_work" / "cabin" / "references").iterdir())
    assert max(max(s) for s in sizes) == providers.MockImageProvider.max_input_px == 2048
    assert (2048, 683) in sizes and (32, 24) in sizes


def test_bad_inputs(root, capsys, tmp_path):
    seed(root, capsys)
    bad = tmp_path / "x.gif"
    bad.write_bytes(b"GIF89a")
    assert concept(capsys, "--reference", str(bad))[0] == 1
    assert concept(capsys, "--reference", str(tmp_path / "missing.png"))[0] == 1
    assert concept(capsys, "--mode", "inspire")[0] == 1
