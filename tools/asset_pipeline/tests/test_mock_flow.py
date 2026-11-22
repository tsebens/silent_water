"""The description commands and the mock providers' full flow. The flow test needs Blender (skips without it, like cleanup)."""
import json
import os
import shutil
from pathlib import Path

import pytest

from asset_pipeline import check, cli, fixture_mesh, paths
from asset_pipeline.manifest import Manifest

REPO = Path(__file__).resolve().parents[3]
BLENDER = shutil.which(os.environ.get("ASSET_BLENDER_BIN") or "blender")
needs_blender = pytest.mark.skipif(BLENDER is None, reason="Blender is not on PATH (set ASSET_BLENDER_BIN)")


def run(capsys, *argv):
    code = cli.main(list(argv))
    return code, json.loads(capsys.readouterr().out)


def style(root):
    sb = root / "assets" / "style_bible"
    sb.mkdir(parents=True)
    shutil.copy(REPO / "assets" / "style_bible" / "classes.yaml", sb / "classes.yaml")
    (sb / "style.md").write_text("STYLE")
    (sb / "negative.md").write_text("- nothing")


def test_new_description_and_describe_feed_concept(root, capsys):
    style(root)
    code, out = run(capsys, "new", "eel", "--class", "creature", "--description", "  a long electric eel ")
    assert code == 0 and out["description"] == "a long electric eel"
    assert run(capsys, "concept", "eel", "--n", "1")[0] == 0  # no --brief needed
    code, out = run(capsys, "describe", "eel", "a short eel")
    assert code == 0 and out["description"] == "a short eel"
    assert Manifest.load(paths.manifest_path(root, "eel")).description == "a short eel"
    assert run(capsys, "concept", "eel", "--n", "1")[0] == 0
    assert run(capsys, "concept", "eel", "--n", "1", "--brief", "via brief")[0] == 0  # --brief still works
    assert Manifest.load(paths.manifest_path(root, "eel")).description == "via brief"


def test_describe_rejects_empty_and_concept_without_description_fails(root, capsys):
    style(root)
    run(capsys, "new", "eel", "--class", "creature")
    assert cli.main(["describe", "eel", "   "]) == 1
    capsys.readouterr()
    assert cli.main(["concept", "eel"]) == 1
    assert "asset describe" in capsys.readouterr().out


def test_mock_mesh_is_closed_single_part_coloured_and_small():
    pos, col, idx = fixture_mesh.mock_mesh()
    tris = [tuple(idx[k:k + 3]) for k in range(0, len(idx), 3)]
    assert 2000 <= len(tris) <= 8000
    assert len(col) == len(pos) and len({c[:3] for c in col}) > 1
    topo = check.topology(pos, tris)
    assert topo == {"non_manifold_edges": 0, "loose_parts": 1}
    vol = sum(pos[a][0] * (pos[b][1] * pos[c][2] - pos[b][2] * pos[c][1])
              - pos[a][1] * (pos[b][0] * pos[c][2] - pos[b][2] * pos[c][0])
              + pos[a][2] * (pos[b][0] * pos[c][1] - pos[b][1] * pos[c][0]) for a, b, c in tris) / 6.0
    assert vol > 0  # outward winding


def test_mock_provider_mesh_and_views_agree(tmp_path):
    from asset_pipeline.providers import MockImageProvider, MockThreeDProvider
    glb = MockThreeDProvider().download("j", tmp_path / "m.glb")
    mesh = check.load_mesh(glb)
    assert len(mesh["triangles"]) >= 2000 and fixture_mesh.read_glb(glb)["prims"][0]["colours"]
    for view in check.VIEWS:
        png = MockImageProvider().edit(f"Orthographic {view} view of this exact asset", tmp_path / "s.png", [], tmp_path / f"{view}.png")
        score = check.iou(check.mesh_silhouette(mesh["positions"], mesh["triangles"], view), check.image_silhouette(png))
        assert score > 0.95


@needs_blender
def test_full_mock_flow_reaches_export(root, capsys):
    style(root)
    steps = [("new", "eel", "--class", "creature", "--description", "a long electric eel"),
             ("concept", "eel", "--n", "1"), ("lock", "eel", "v1", "--reviewer", "t"),
             ("turnaround", "eel"), ("brief", "eel"), ("to3d", "eel")]
    for s in steps:
        code, out = run(capsys, *s)
        assert code == 0, (s, out)
    code, out = run(capsys, "cleanup", "eel", "--source", "r1_mock")
    assert code == 0, out
    code, out = run(capsys, "check", "eel")
    assert code == 0 and out["ok"], out
    code, out = run(capsys, "export", "eel")
    assert code == 0, out
    d = root / "assets" / "models" / "eel"
    for f in ("eel.glb", "eel.tscn", "asset.yaml"):
        assert (d / f).is_file()
    assert any((d / "concept").iterdir())
    assert Manifest.load(paths.manifest_path(root, "eel")).stage == "exported"
