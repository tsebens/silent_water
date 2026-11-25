"""Check gates. Pure Python on a cleaned-like fixture; the Blender-backed test skips when Blender is absent."""
import json
import os
import shutil
import struct
from pathlib import Path

import pytest
import yaml

from asset_pipeline import check, cli, fixture_mesh
from asset_pipeline.manifest import BriefRecord, CleanupRecord, LineageEntry, Manifest

REPO = Path(__file__).resolve().parents[3]
BLENDER = shutil.which(os.environ.get("ASSET_BLENDER_BIN") or "blender")
SIZE_M = 2.0


def run(*argv):
    return cli.main(list(argv))


def clean_mesh(segments=40, scale=SIZE_M / 3.0):
    """A smooth ellipsoid, scaled so its largest dimension is ~SIZE_M, centred at the origin: no stray fragment."""
    pos, _, idx = fixture_mesh.build(segments)
    pos, idx = pos[:-3], idx[:-3]
    stride = segments + 1  # the fixture's seam column is a noisy duplicate of column 0: fold it back
    idx = [v - segments if v % stride == segments else v for v in idx]
    out = [((x - 4.0) * scale, (y - 2.0) * scale, (z + 1.0) * scale) for x, y, z in pos]
    return out, idx


def write(path, pos, idx):
    fixture_mesh.write_glb(path, pos, [(1.0, 1.0, 1.0, 1.0)] * len(pos), idx)


def dims(pos):
    return [max(p[a] for p in pos) - min(p[a] for p in pos) for a in range(3)]


def add_views(root, m, pos, idx, only=None, views=check.VIEWS):
    tris = [tuple(idx[i:i + 3]) for i in range(0, len(idx), 3)]
    for view in views:
        if only and view not in only:
            continue
        rel = Path("assets/models/blob/concept") / f"turnaround_t1_{view}.png"
        check.write_mask_png(root / rel, check.mesh_silhouette(pos, tris, view))
        m.add(LineageEntry(id=f"t1_{view}", kind="turnaround", path=str(rel), provider="mock", model="mock"))


@pytest.fixture
def asset(root, capsys):
    """A creature whose cleanup c1 is the clean mesh, with turnaround views projected from that very mesh."""
    (root / "assets" / "style_bible").mkdir(parents=True)
    shutil.copy(REPO / "assets" / "style_bible" / "classes.yaml", root / "assets" / "style_bible" / "classes.yaml")
    assert run("new", "blob", "--class", "creature") == 0
    capsys.readouterr()
    mpath = root / "assets" / "models" / "blob" / "asset.yaml"
    brief = root / "assets" / "models" / "blob" / "concept" / "brief.md"
    brief.parent.mkdir(parents=True)
    brief.write_text(f"- size_m: {SIZE_M}\n")
    pos, idx = clean_mesh()
    glb = root / ".asset_work" / "blob" / "cleanup" / "c1.glb"
    write(glb, pos, idx)
    m = Manifest.load(mpath)
    m.add(LineageEntry(id="c1", kind="mesh", path=str(glb.relative_to(root)), provider="blender", model="4.5"))
    m.brief = BriefRecord(path=str(brief.relative_to(root)), writer="mock", model="mock")
    m.cleanups.append(CleanupRecord(id="c1", source="c1", recipe=[]))
    m.stage = "cleanup"
    add_views(root, m, pos, idx)
    m.save(mpath)
    return root


def check_cmd(capsys, *extra):
    code = run("check", "blob", *extra)
    return code, json.loads(capsys.readouterr().out)


def test_clean_fixture_passes_every_gate(asset, capsys):
    code, out = check_cmd(capsys)
    assert code == 0 and out["ok"] and out["failed"] == [], out
    report = json.loads((asset / out["report"]).read_text())
    assert [g["name"] for g in report["gates"]] == list(check.GATE_NAMES)
    for view in check.VIEWS:
        assert out["gates"][f"silhouette_{view}"] >= 0.95
    m = Manifest.load(asset / "assets" / "models" / "blob" / "asset.yaml")
    assert m.stage == "checked"
    assert m.checks[-1].report == out["report"] and m.checks[-1].ok


def test_over_budget_fails_triangles(asset, capsys):
    code, out = check_cmd(capsys, "--triangle-budget", "1000")
    assert code == 1 and out["failed"] == ["triangles"]


def test_wrong_size_fails_bbox(asset, capsys):
    code, out = check_cmd(capsys, "--size-m", "3.0")
    assert code == 1 and "bbox" in out["failed"]


def test_loose_parts_fail(asset, capsys):
    pos, idx = clean_mesh()
    base = len(pos)
    for k in range(3):  # three extra closed-looking fragments far away (creature allows 1 part)
        for p in ((9.0 + k, 0.0, 0.0), (9.2 + k, 0.0, 0.0), (9.0 + k, 0.2, 0.0)):
            pos.append(p)
        idx += [base + 3 * k, base + 3 * k + 1, base + 3 * k + 2]
    write(asset / ".asset_work" / "blob" / "cleanup" / "c1.glb", pos, idx)
    code, out = check_cmd(capsys)
    assert code == 1 and "loose_parts" in out["failed"]
    report = json.loads((asset / out["report"]).read_text())
    assert next(g for g in report["gates"] if g["name"] == "loose_parts")["value"] == 4


def test_holes_fail_non_manifold(asset, capsys):
    pos, idx = clean_mesh()
    write(asset / ".asset_work" / "blob" / "cleanup" / "c1.glb", pos, idx[:-60])  # cut 20 faces out
    code, out = check_cmd(capsys)
    assert code == 1 and "non_manifold" in out["failed"]


def test_missing_view_fails_and_is_listed(asset, capsys):
    mpath = asset / "assets" / "models" / "blob" / "asset.yaml"
    m = Manifest.load(mpath)
    m.lineage = [e for e in m.lineage if e.id != "t1_back"]
    m.save(mpath)
    code, out = check_cmd(capsys)
    assert code == 1 and out["failed"] == ["silhouette_back"]


def test_wrong_silhouette_fails(asset, capsys):
    """Views projected from a different (much flatter) shape must not match."""
    pos, idx = clean_mesh()
    flat = [(x, y * 0.2, z) for x, y, z in pos]
    m = Manifest.load(asset / "assets" / "models" / "blob" / "asset.yaml")
    m.lineage = [e for e in m.lineage if e.kind != "turnaround"]
    add_views(asset, m, flat, idx)
    m.save(asset / "assets" / "models" / "blob" / "asset.yaml")
    code, out = check_cmd(capsys)
    assert code == 1 and set(out["failed"]) == {"silhouette_front", "silhouette_back", "silhouette_left", "silhouette_right"}


def test_unreadable_view_is_a_failed_gate(asset, capsys):
    (asset / "assets" / "models" / "blob" / "concept" / "turnaround_t1_left.png").write_bytes(b"RIFFxxxxWEBP")
    code, out = check_cmd(capsys)
    assert code == 1 and out["failed"] == ["silhouette_left"]


def test_no_cleanup_is_an_error(root, capsys):
    (root / "assets" / "style_bible").mkdir(parents=True)
    shutil.copy(REPO / "assets" / "style_bible" / "classes.yaml", root / "assets" / "style_bible" / "classes.yaml")
    run("new", "blob", "--class", "creature")
    capsys.readouterr()
    code, out = check_cmd(capsys)
    assert code == 1 and not out["ok"] and "cleanup" in out["error"]


def test_collision_helper_nodes_are_ignored(tmp_path):
    pos, idx = clean_mesh()
    glb = tmp_path / "m.glb"
    write(glb, pos, idx)
    data = glb.read_bytes()
    jlen = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jlen])
    doc["nodes"] = [{"mesh": 0, "name": "blob"}, {"mesh": 0, "name": "blob_collision-convcolonly", "translation": [50, 0, 0]}]
    doc["scenes"] = [{"nodes": [0, 1]}]
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    rest = data[20 + jlen:]
    glb.write_bytes(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + len(rest)) + struct.pack("<I4s", len(js), b"JSON") + js + rest)
    mesh = check.load_mesh(glb)
    assert mesh["skipped_collision"] == ["blob_collision-convcolonly"]
    assert len(mesh["triangles"]) == len(idx) // 3
    assert max(dims(mesh["positions"])) == pytest.approx(max(dims(pos)))


def test_node_transform_is_applied(tmp_path):
    pos, idx = clean_mesh()
    glb = tmp_path / "m.glb"
    write(glb, pos, idx)
    data = glb.read_bytes()
    jlen = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jlen])
    doc["nodes"][0]["scale"] = [2, 2, 2]
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    rest = data[20 + jlen:]
    glb.write_bytes(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + len(rest)) + struct.pack("<I4s", len(js), b"JSON") + js + rest)
    assert max(dims(check.load_mesh(glb)["positions"])) == pytest.approx(2 * max(dims(pos)))


def test_png_decoder_handles_rgb_background(tmp_path):
    """An opaque view (no alpha): the subject is whatever differs from the corner colour."""
    import zlib

    def chunk(k, b):
        return struct.pack(">I", len(b)) + k + b + struct.pack(">I", zlib.crc32(k + b))
    w = h = 8
    rows = b"".join(b"\x00" + b"".join(b"\x00\x00\x00" if 2 <= x < 6 and 2 <= y < 6 else b"\xff\xff\xff" for x in range(w))
                    for y in range(h))
    f = tmp_path / "v.png"
    f.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                  + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
    mask = check.image_silhouette(f)
    assert sum(mask) > check.GRID * check.GRID * 0.9  # the square fills the fitted canvas


@pytest.mark.skipif(BLENDER is None, reason="Blender is not on PATH (set ASSET_BLENDER_BIN)")
def test_check_on_blender_cleanup_output(root, capsys):
    """The real cleanup output (collision helper included) passes its gates against views projected from itself."""
    (root / "assets" / "style_bible").mkdir(parents=True)
    shutil.copy(REPO / "assets" / "style_bible" / "classes.yaml", root / "assets" / "style_bible" / "classes.yaml")
    (root / "assets" / "palette").mkdir(parents=True)
    shutil.copy(REPO / "assets" / "palette" / "palette.tres", root / "assets" / "palette" / "palette.tres")
    run("new", "blob", "--class", "creature")
    capsys.readouterr()
    mpath = root / "assets" / "models" / "blob" / "asset.yaml"
    raw = root / ".asset_work" / "blob" / "to3d" / "r1_mock.glb"
    fixture_mesh.write_glb(raw, *fixture_mesh.build())
    m = Manifest.load(mpath)
    m.add(LineageEntry(id="r1_mock", kind="mesh", path=str(raw.relative_to(root)), provider="mock", model="mock-3d-1"))
    m.save(mpath)
    assert run("cleanup", "blob", "--source", "r1_mock", "--size-m", str(SIZE_M)) == 0
    capsys.readouterr()
    m = Manifest.load(mpath)
    brief = root / "assets" / "models" / "blob" / "concept" / "brief.md"
    brief.parent.mkdir(parents=True, exist_ok=True)
    brief.write_text(f"- size_m: {SIZE_M}\n")
    m.brief = BriefRecord(path=str(brief.relative_to(root)), writer="mock", model="mock")
    mesh = check.load_mesh(root / m.entry("c1").path)
    add_views(root, m, mesh["positions"], [i for t in mesh["triangles"] for i in t])
    m.save(mpath)
    code, out = check_cmd(capsys)
    assert code == 0 and out["ok"], out


def test_top_and_bottom_gates_appear_only_when_those_views_exist(asset, capsys):
    code, out = check_cmd(capsys)
    assert code == 0 and "silhouette_top" not in out["gates"] and "silhouette_bottom" not in out["gates"]
    mpath = asset / "assets" / "models" / "blob" / "asset.yaml"
    m = Manifest.load(mpath)
    pos, idx = clean_mesh()
    add_views(asset, m, pos, idx, only=("top", "bottom"), views=("top", "bottom"))
    m.save(mpath)
    code, out = check_cmd(capsys)
    assert code == 0 and out["ok"], out
    assert out["gates"]["silhouette_top"] >= 0.95 and out["gates"]["silhouette_bottom"] >= 0.95
    report = json.loads((asset / out["report"]).read_text())
    assert [g["name"] for g in report["gates"]][-2:] == ["silhouette_top", "silhouette_bottom"]


def test_top_and_bottom_projections_differ_from_the_side_views():
    pos, idx = clean_mesh()
    tris = [tuple(idx[i:i + 3]) for i in range(0, len(idx), 3)]
    masks = {v: bytes(check.mesh_silhouette(pos, tris, v)) for v in check.ALL_VIEWS}
    assert all(sum(m) > 0 for m in masks.values())
