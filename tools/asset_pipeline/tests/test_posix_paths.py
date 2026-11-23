"""Stored and printed paths are repo-relative with forward slashes on every OS (runs on Windows CI too)."""
import yaml

from asset_pipeline import cli, paths
from asset_pipeline.manifest import LineageEntry, Manifest


def run(capsys, *argv):
    code = cli.main(list(argv))
    return code, capsys.readouterr().out


def test_posix_rel_uses_forward_slashes(tmp_path):
    assert paths.posix_rel(tmp_path, tmp_path / "assets" / "models" / "a.glb") == "assets/models/a.glb"


def test_scripted_flow_writes_no_backslash(root, capsys):
    sb = root / "assets" / "style_bible"
    (sb / "anchors" / "creature").mkdir(parents=True)
    (sb / "style.md").write_text("STYLE BLOCK")
    (sb / "negative.md").write_text("- none")
    (sb / "anchors" / "creature" / "a0.png").write_bytes(b"x")
    outputs = []
    for argv in (("new", "angler", "--class", "creature"),
                 ("concept", "angler", "--n", "2", "--brief", "an anglerfish"),
                 ("lock", "angler", "v1", "--reviewer", "t"),
                 ("turnaround", "angler"),
                 ("list",)):
        code, out = run(capsys, *argv)
        outputs.append(out)
        assert code == 0, out
    outputs += [f.read_text() for f in [*root.rglob("asset.yaml"), *root.rglob("*.json")]]
    assert any(".asset_work/angler/concept/v1.png" in o for o in outputs)
    for o in outputs:
        # Prompts hold newlines (JSON "\\n", or real ones in YAML); anything else with a backslash is a path.
        assert "\\" not in o.replace("\\n", ""), o


def test_manifest_with_backslash_paths_loads_normalised(tmp_path):
    m = Manifest(slug="a", asset_class="prop")
    m.add(LineageEntry(id="v1", kind="concept", path=r".asset_work\a\concept\v1.png", provider="mock", model="m",
                       references=[r"assets\style\x.png"]))
    p = tmp_path / "asset.yaml"
    d = m.to_dict()
    p.write_text(yaml.safe_dump(d))
    assert "\\" in p.read_text()
    loaded = Manifest.load(p)
    assert loaded.lineage[0].path == ".asset_work/a/concept/v1.png"
    assert loaded.lineage[0].references == ["assets/style/x.png"]


def test_reference_flow_records_no_absolute_path(root, capsys, tmp_path):
    from PIL import Image
    sb = root / "assets" / "style_bible"
    (sb / "anchors" / "prop").mkdir(parents=True)
    (sb / "anchors" / "prop" / "a0.png").write_bytes(b"x")
    ref = tmp_path / "somewhere" / "view.jpg"
    ref.parent.mkdir()
    Image.new("RGB", (8, 8)).save(ref, format="JPEG")
    outputs = []
    for argv in (("new", "cabin", "--class", "prop"),
                 ("concept", "cabin", "--brief", "b", "--n", "1", "--reference", str(ref)),
                 ("concept", "cabin", "--refine", "v1", "--notes", "n", "--n", "1")):
        code, out = run(capsys, *argv)
        assert code == 0, out
        outputs.append(out)
    outputs += [f.read_text() for f in root.rglob("asset.yaml")]
    for o in outputs:
        assert str(tmp_path) not in o and str(tmp_path).replace("\\", "/") not in o
        assert "\\" not in o.replace("\\n", "")
    assert any("view.jpg" in o for o in outputs)
    assert any(".asset_work/cabin/references/" in o for o in outputs)
