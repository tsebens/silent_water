"""Cleanup stage. The Blender-backed tests skip when Blender is not on PATH (CI installs it, #229)."""
import json
import os
import shutil
from pathlib import Path

import pytest
import yaml

from asset_pipeline import cleanup, cli, doctor, fixture_mesh, providers
from asset_pipeline.manifest import LineageEntry, Manifest

REPO = Path(__file__).resolve().parents[3]
BLENDER = shutil.which(os.environ.get("ASSET_BLENDER_BIN") or "blender")
needs_blender = pytest.mark.skipif(BLENDER is None, reason="Blender is not on PATH (set ASSET_BLENDER_BIN)")
SIZE_M = 2.0


def run(*argv):
    return cli.main(list(argv))


@pytest.fixture
def asset(root, capsys):
    """A creature with the repo's class profiles, a brief that asks for 2 m, and the noisy fixture as raw run r1_mock."""
    (root / "assets" / "style_bible").mkdir(parents=True)
    shutil.copy(REPO / "assets" / "style_bible" / "classes.yaml", root / "assets" / "style_bible" / "classes.yaml")
    (root / "assets" / "palette").mkdir(parents=True)
    shutil.copy(REPO / "assets" / "palette" / "palette.tres", root / "assets" / "palette" / "palette.tres")
    assert run("new", "blob", "--class", "creature") == 0
    capsys.readouterr()
    mpath = root / "assets" / "models" / "blob" / "asset.yaml"
    raw = root / ".asset_work" / "blob" / "to3d" / "r1_mock.glb"
    fixture_mesh.write_glb(raw, *fixture_mesh.build())
    brief = root / "assets" / "models" / "blob" / "concept" / "brief.md"
    brief.parent.mkdir(parents=True)
    brief.write_text(f"# Brief\n\n- size_m: {SIZE_M}\n- budget: 8000 tris\n")
    m = Manifest.load(mpath)
    m.add(LineageEntry(id="r1_mock", kind="mesh", path=str(raw.relative_to(root)), provider="mock", model="mock-3d-1"))
    from asset_pipeline.manifest import BriefRecord
    m.brief = BriefRecord(path=str(brief.relative_to(root)), writer="mock", model="mock")
    m.save(mpath)
    return root


def linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def assert_colours_are_swatches(root, cols, used):
    """Every vertex colour is exactly (to float precision) a snap swatch's value, and `used` names those swatches."""
    swatches = cleanup.snap_swatches(root)
    assert swatches and all(n.startswith(cleanup.SNAP_PREFIXES) for n in swatches)
    lin = {n: [linear(c) for c in rgb] for n, rgb in swatches.items()}
    seen = set()
    for c in {tuple(round(x, 5) for x in c4[:3]) for c4 in cols}:
        match = [n for n, v in lin.items() if all(abs(a - b) < 2e-4 for a, b in zip(c, v))]
        assert match, f"vertex colour {c} is not a palette swatch"
        seen.add(match[0])
    assert seen <= set(used) and used


def test_snap_swatches_reads_only_organic_families(asset):
    swatches = cleanup.snap_swatches(asset)
    assert "env_deep" in swatches and "life_coral" in swatches and "floor_sand" in swatches and "flora_sage" in swatches
    assert not any(n.startswith(("light_", "sub_", "info_", "infra_")) for n in swatches)


def test_snap_swatches_needs_a_palette(tmp_path):
    with pytest.raises(ValueError):
        cleanup.snap_swatches(tmp_path)


def test_cleanup_passes_swatches_to_blender_for_organic_classes(asset, monkeypatch, capsys):
    seen = {}

    def fake_run(params, workdir, runner=None, root=None):
        seen.update(params)
        return {"blender_version": "4.5.0"}
    monkeypatch.setattr(cleanup, "resolve_runner", lambda: cleanup.Runner("native", "blender"))
    monkeypatch.setattr(cleanup, "run_blender", fake_run)
    assert run("cleanup", "blob", "--source", "r1_mock") == 0
    assert set(seen["swatches"]) == set(cleanup.snap_swatches(asset))


def edge_stats(positions, tris):
    """(non-manifold edge count, loose parts) with vertices welded by position (flat shading splits them)."""
    weld = {}
    ids = [weld.setdefault(tuple(round(c, 5) for c in p), len(weld)) for p in positions]
    edges = {}
    parent = list(range(len(weld)))

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    for a, b, c in tris:
        a, b, c = ids[a], ids[b], ids[c]
        for u, v in ((a, b), (b, c), (c, a)):
            edges[(min(u, v), max(u, v))] = edges.get((min(u, v), max(u, v)), 0) + 1
            parent[find(u)] = find(v)
    used = {find(i) for t in tris for i in map(lambda k: ids[k], t)}
    return sum(1 for n in edges.values() if n != 2), len(used)


def test_fixture_is_dirty_and_big():
    pos, col, idx = fixture_mesh.build()
    assert 90_000 <= len(idx) // 3 <= 110_000
    assert len({c[:3] for c in col}) > 1000  # noisy colour
    assert len(set(pos)) < len(pos)  # duplicated seam


def test_brief_size_parsing(tmp_path):
    prof = {"scale_range_m": [0.5, 40.0]}
    b = tmp_path / "brief.md"
    b.write_text("- **size_m**: 1.5 x 0.8 x 0.6\n")
    assert cleanup.brief_size_m(b, prof) == (1.5, "brief")
    b.write_text("no size here")
    size, src = cleanup.brief_size_m(b, prof)
    assert src == "class scale range" and 0.5 < size < 40.0
    assert cleanup.brief_size_m(None, prof)[1] == "class scale range"


def test_cleanup_without_blender_errors_cleanly(asset, monkeypatch, capsys, tmp_path):
    monkeypatch.setenv("ASSET_BLENDER_BIN", "definitely-not-blender")
    monkeypatch.setenv("PATH", str(tmp_path))  # no blender, no docker
    assert run("cleanup", "blob", "--source", "r1_mock") == 1
    out = json.loads(capsys.readouterr().out)
    assert out["ok"] is False and "Blender not found" in out["error"]
    assert Manifest.load(asset / "assets" / "models" / "blob" / "asset.yaml").cleanups == []


def test_doctor_reports_missing_blender(monkeypatch, tmp_path):
    monkeypatch.setenv("ASSET_BLENDER_BIN", "definitely-not-blender")
    monkeypatch.setenv("PATH", str(tmp_path))  # neither Blender nor Docker
    res = doctor.run(providers.load_config())
    b = next(c for c in res["checks"] if c["name"] == "blender")
    assert b["ok"] is False and "ASSET_BLENDER_BIN" in b["detail"]


def test_cleanup_rejects_non_mesh_and_bad_size(asset, capsys):
    mpath = asset / "assets" / "models" / "blob" / "asset.yaml"
    m = Manifest.load(mpath)
    m.add(LineageEntry(id="v1", kind="concept", path="x.png", provider="mock", model="m"))
    m.save(mpath)
    assert run("cleanup", "blob", "--source", "v1") == 1
    assert "needs a mesh" in json.loads(capsys.readouterr().out)["error"]


@needs_blender
def test_cleanup_meets_budget_manifold_palette_scale_and_pivot(asset, capsys):
    assert_cleanup_meets_the_profile(asset, capsys)


def assert_cleanup_meets_the_profile(asset, capsys):
    """Run the fixture cleanup with the configured runner and check the result (shared with the Docker test)."""
    assert run("cleanup", "blob", "--source", "r1_mock") == 0
    out = json.loads(capsys.readouterr().out)
    prof = yaml.safe_load((asset / "assets" / "style_bible" / "classes.yaml").read_text())["classes"]["creature"]
    glb = fixture_mesh.read_glb(asset / out["path"])

    # The cleaned body and its collision helper are both in the GLB; the body is the one with colours.
    body = [p for p in glb["prims"] if p["colours"]]
    assert len(glb["prims"]) == 2 and len(body) == 1
    pos, tris, cols = body[0]["positions"], body[0]["triangles"], body[0]["colours"]

    assert len(tris) <= prof["triangle_budget"]
    assert len(tris) > prof["triangle_budget"] * 0.5  # decimated to the budget, not gutted
    bad_edges, parts = edge_stats(pos, tris)
    assert bad_edges == 0, "mesh is not manifold"
    assert parts == 1
    assert 1 < len({tuple(round(c, 3) for c in c4[:3]) for c4 in cols}) <= prof["palette_size"]
    assert_colours_are_swatches(asset, cols, out["result"]["steps"]["vertex_colour_palette"]["swatches_used"])

    # glTF is Y-up: height is Y, pivot at the bottom centre, largest dimension = the brief's size.
    xs, ys, zs = zip(*pos)
    dims = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))
    assert max(dims) == pytest.approx(SIZE_M, rel=0.01)
    assert min(ys) == pytest.approx(0.0, abs=0.01)
    assert (max(xs) + min(xs)) / 2 == pytest.approx(0.0, abs=0.02)
    assert (max(zs) + min(zs)) / 2 == pytest.approx(0.0, abs=0.02)

    # The collision helper is a small convex hull Godot imports as a shape.
    names = [n.get("name", "") for n in glb["nodes"]]
    assert any(n.endswith("-convcolonly") for n in names)

    # Manifest: lineage entry, recipe, commit, measured result.
    m = Manifest.load(asset / "assets" / "models" / "blob" / "asset.yaml")
    rec = m.cleanups[0]
    assert m.stage == "cleanup" and rec.source == "r1_mock" and rec.id == out["id"]
    assert rec.recipe == prof["cleanup_recipe"]
    assert rec.script_sha256 == cleanup.script_digest()
    assert rec.blender.startswith("4.5")
    assert rec.result["triangles"] == len(tris) and rec.result["non_manifold"] == 0
    assert rec.params["size_from"] == "brief"
    assert m.entry(out["id"]).parent == "r1_mock"
    # Re-running cleans again under a fresh id.
    assert run("cleanup", "blob", "--source", "r1_mock") == 0
    assert json.loads(capsys.readouterr().out)["id"] == "c2"
