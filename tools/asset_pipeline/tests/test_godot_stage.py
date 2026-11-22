"""godot-check, export, and the check.sh gates for assets/. The Godot-backed test skips without Godot."""
import json
import os
import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path

import pytest

from asset_pipeline import check, cli, godot_stage
from asset_pipeline.manifest import LineageEntry, Manifest

from test_check import REPO, asset, run, write, clean_mesh  # noqa: F401  (asset is a fixture)

GODOT = shutil.which(os.environ.get("GODOT") or "godot")
TOOLS = REPO / "tools"


def make_png(path: Path, w: int, h: int) -> None:
    raw = b"".join(b"\x00" + b"".join(bytes((x * 255 // w, y * 255 // h, 90, 255)) for x in range(w)) for y in range(h))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


@pytest.mark.skipif(GODOT is None, reason="Godot not found (set GODOT)")
def test_godot_check_imports_fixture_and_renders(tmp_path):
    pos, idx = clean_mesh()
    glb = tmp_path / "fx.glb"
    write(glb, pos, idx)
    logs = tmp_path / "logs"
    res = godot_stage.godot_check(REPO, "gdtest_fixture", glb, logs)
    assert res["ok"], res
    assert res["material"]["surfaces"] >= 1
    assert res["material"]["vertex_color_use_as_albedo"] == res["material"]["surfaces"]
    for shot in ("fog", "white", "red"):
        png = logs / f"gdtest_fixture_{shot}.png"
        assert png.is_file() and png.stat().st_size > 1000
    assert not (REPO / "build" / "asset_check" / "gdtest_fixture").exists()


def test_import_script_is_the_shared_one():
    stub = godot_stage.import_stub("res://assets/models/x", "x")
    assert f'import_script/path="{godot_stage.IMPORT_SCRIPT}"' in stub
    assert (REPO / "assets" / "import" / "vertex_color_import.gd").is_file()


def test_export_writes_committed_layout(asset, capsys):  # noqa: F811
    root = asset
    mpath = root / "assets" / "models" / "blob" / "asset.yaml"
    big = root / ".asset_work" / "blob" / "concept" / "v1.png"
    make_png(big, 2600, 1300)
    m = Manifest.load(mpath)
    m.add(LineageEntry(id="v1", kind="concept", path=str(big.relative_to(root)), provider="mock", model="mock"))
    m.lock("v1", reviewer="t")
    m.stage = "cleanup"
    m.save(mpath)
    assert run("check", "blob") == 0
    capsys.readouterr()
    # one oversized turnaround view too
    view = root / "assets" / "models" / "blob" / "concept" / "turnaround_t1_front.png"
    make_png(view, 2300, 2300)
    assert run("export", "blob") == 0
    out = json.loads(capsys.readouterr().out)
    d = root / "assets" / "models" / "blob"
    for f in ("blob.glb", "blob.glb.import", "blob.tscn", "asset.yaml", "concept/.gdignore", "concept/locked.png",
              "concept/brief.md", "concept/turnaround_t1_front.png"):
        assert (d / f).exists(), f
    assert 'path="res://assets/import/vertex_color_import.gd"' in (d / "blob.glb.import").read_text()
    assert 'res://assets/models/blob/blob.glb' in (d / "blob.tscn").read_text()
    for f in (d / "concept").glob("*.png"):
        assert max(godot_stage.png_size(f)) <= 2048, f
    assert "assets/models/blob/concept/locked.png" in out["resized"]
    assert Manifest.load(mpath).stage == "exported"
    assert Manifest.load(mpath).exports[-1].id == "c1"


def test_export_refuses_unchecked_mesh(asset, capsys):  # noqa: F811
    assert run("export", "blob") == 1
    assert "asset check" in json.loads(capsys.readouterr().out)["error"]


def sh(script, root):
    return subprocess.run([sys.executable, str(TOOLS / script), str(root)], capture_output=True, text=True)


def test_size_check_fails_over_5mb_and_passes_otherwise(tmp_path):
    (tmp_path / "assets" / "m").mkdir(parents=True)
    (tmp_path / "assets" / "m" / "ok.bin").write_bytes(b"\0" * (5 * 1024 * 1024))  # exactly 5 MB is allowed
    assert sh("check_asset_sizes.py", tmp_path).returncode == 0
    (tmp_path / "assets" / "m" / "big.glb").write_bytes(b"\0" * (5 * 1024 * 1024 + 1))
    r = sh("check_asset_sizes.py", tmp_path)
    assert r.returncode == 1 and "assets/m/big.glb" in r.stdout
    (tmp_path / "tools").mkdir()
    (tmp_path / "tools" / "asset_size_allowlist.txt").write_text("# grandfathered\nassets/m/big.glb\n")
    assert sh("check_asset_sizes.py", tmp_path).returncode == 0


def test_repo_assets_are_within_limit():
    assert sh("check_asset_sizes.py", REPO).returncode == 0


PRESET = '[preset.0]\n\nname="Linux"\nexclude_filter="%s"\n\n[preset.0.options]\n\nx=1\n'


def test_export_presets_check(tmp_path):
    assert sh("check_export_presets.py", tmp_path).returncode == 0  # no presets file
    cfg = tmp_path / "export_presets.cfg"
    cfg.write_text(PRESET % "tools/*, addons/asset_studio/*")
    assert sh("check_export_presets.py", tmp_path).returncode == 0
    cfg.write_text(PRESET % "tools/*")
    r = sh("check_export_presets.py", tmp_path)
    assert r.returncode == 1 and "addons/asset_studio" in r.stdout
    cfg.write_text(PRESET % "")
    assert sh("check_export_presets.py", tmp_path).returncode == 1
    assert sh("check_export_presets.py", REPO).returncode == 0
