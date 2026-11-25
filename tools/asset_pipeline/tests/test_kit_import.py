"""`asset import`: the cad route for kit parts. Blender is replaced by a stub that hands back the committed toggle GLB
(converted once by the real converter), so nothing here needs Blender, Godot or a network."""
import json
import re
import shutil
from pathlib import Path

import pytest
import yaml

from asset_pipeline import check, cli, kit_import, paths
from asset_pipeline.manifest import Manifest

REPO = Path(__file__).resolve().parents[3]
EXPORT = REPO / "assets" / "media" / "kit" / "toggle_switch" / "toggle_switch.gltf"
CONVERTED = REPO / "assets" / "models" / "kit" / "toggle_switch" / "toggle_switch.glb"


def run(capsys, *argv):
    code = cli.main(list(argv))
    return code, json.loads(capsys.readouterr().out)


@pytest.fixture
def kit(root, monkeypatch):
    sb = root / "assets" / "style_bible"
    sb.mkdir(parents=True)
    shutil.copy(REPO / "assets" / "style_bible" / "classes.yaml", sb / "classes.yaml")
    shutil.copytree(REPO / "assets" / "palette", root / "assets" / "palette")
    src = root / "incoming" / "Toggle Switch.gltf"  # an export saved anywhere, with an Onshape-style name
    src.parent.mkdir()
    shutil.copy(EXPORT, src)
    calls = []

    def fake(root_, src_, dst, pivot):
        calls.append({"src": src_, "dst": dst, "pivot": pivot})
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(CONVERTED, dst)
        return {"blender_version": "4.5.9", "runner": "native", "image": "", "script_sha256": "abc"}

    monkeypatch.setattr(kit_import, "run_converter", fake)
    return src, calls


def do_import(capsys, src, *extra):
    return run(capsys, "import", "toggle_switch", str(src), "--pivot", "Switch", *extra)


def glb_node(glb, name):
    return next(n for n in kit_import.glb_nodes(glb) if n.get("name") == name)


def test_import_records_a_mesh_with_the_source_hash_and_a_second_adds_another(kit, root, capsys):
    src, calls = kit
    code, out = do_import(capsys, src)
    assert code == 0, out
    m = Manifest.load(paths.manifest_path(root, "toggle_switch"))
    assert m.asset_class == "kit" and m.stage == "cleanup"
    e = m.entry("i1")
    assert e.kind == "mesh" and e.provider == "onshape"
    import hashlib
    digest = hashlib.sha256(src.read_bytes()).hexdigest()
    assert e.source == {"path": "assets/media/kit/toggle_switch/toggle_switch.gltf", "sha256": digest}
    assert m.imports[0].sha256 == digest
    assert (root / e.source["path"]).read_bytes() == src.read_bytes()
    assert calls[0]["pivot"] == "Switch"
    # a changed export imports as a second mesh, with its own hash
    src.write_text(src.read_text().replace('"Toggle Switch"', '"Toggle Switch v2"'))
    code, out = do_import(capsys, src)
    assert code == 0 and out["id"] == "i2"
    m = Manifest.load(paths.manifest_path(root, "toggle_switch"))
    assert [e.id for e in m.lineage] == ["i1", "i2"]
    assert m.entry("i1").source["sha256"] != m.entry("i2").source["sha256"]


def test_converted_glb_has_pivot_at_hinge_and_origin_at_back_face_centre(kit, root, capsys):
    do_import(capsys, kit[0])
    glb = root / ".asset_work" / "toggle_switch" / "import" / "i1.glb"
    pivot = glb_node(glb, "Pivot")
    assert "rotation" not in pivot or pivot["rotation"] == [0, 0, 0, 1]
    assert pivot["translation"] == pytest.approx([-0.0205, 0, 0.02], abs=1e-4)  # the hinge, on the part's own frame
    assert kit_import.find_pivot(glb, "Switch") is not None
    doc, acc = check.glb_document(glb)
    housing = next(n for n in doc["nodes"] if n.get("name") == "Housing")
    pts = acc(doc["meshes"][housing["mesh"]]["primitives"][0]["attributes"]["POSITION"])
    lo = [min(p[a] for p in pts) for a in range(3)]
    hi = [max(p[a] for p in pts) for a in range(3)]
    assert (lo[0] + hi[0]) / 2 == pytest.approx(0, abs=1e-3)  # centred on the back face
    assert (lo[1] + hi[1]) / 2 == pytest.approx(0, abs=1e-3)
    assert lo[2] == pytest.approx(0, abs=1e-3)  # the back face is the origin plane; the front stands out along +Z


def test_material_names_snap_to_the_nearest_palette_role(kit, root, capsys):
    palette = kit_import.load_palette(root)
    assert {"control_grey", "control_interface", "button", "lever", "indicator_ok", "screen_off"} <= set(palette)
    swatches = kit_import._swatches(root)
    assert palette["control_interface"] == swatches["sub_orange"]
    assert palette["indicator_ok"] == swatches["light_ok"]  # a lit role shows its glow
    for role in ("control_interface", "button", "indicator_ok", "indicator_alarm"):
        assert kit_import.snap_colour(palette[role], palette) == role
    assert kit_import.snap_colour([1.0, 0.55, 0.25], palette) == "control_interface"
    assert kit_import.snap_colour([0.03, 0.03, 0.04], palette) in ("screen_off", "indicator_off")  # roles can share a swatch
    assert kit_import.material_rgb("0.231373_0.380392_0.705882_0.000000_0.000000", None) == pytest.approx([0.231373, 0.380392, 0.705882])
    code, out = do_import(capsys, kit[0])
    assert out["materials"]["0.647059_0.647059_0.647059_0.000000_0.000000"] in palette
    glb = root / ".asset_work" / "toggle_switch" / "import" / "i1.glb"
    doc, _ = kit_import.read_glb(glb)
    names = [x["name"] for x in doc["materials"]]
    assert names and set(names) <= set(palette)
    assert len(set(names)) == len(names)  # materials that snap to one role are merged
    for mat in doc["materials"]:
        assert "baseColorFactor" not in mat["pbrMetallicRoughness"]  # roles carry the colour, not the asset
    for mesh in doc["meshes"]:
        assert all(p["material"] < len(doc["materials"]) for p in mesh["primitives"])
    assert check.load_mesh(glb)["triangles"]  # still a readable mesh


def test_manifest_records_pivot_and_check_and_export_pass(kit, root, capsys):
    do_import(capsys, kit[0], "--limits", "-40", "40")
    m = Manifest.load(paths.manifest_path(root, "toggle_switch"))
    assert [(p.part, p.axis, p.limits_deg, p.control) for p in m.pivots] == [("Switch", "x", [-40.0, 40.0], "switch_lever")]
    assert set(m.imports[0].parts) == {"Switch", "Housing", "Indicator Light"}
    # the class budget (about 1,500 triangles) is a target the first toggle (4,606) misses
    code, out = run(capsys, "check", "toggle_switch")
    assert code == 1 and out["failed"] == ["triangles"]
    assert not any(g.startswith("silhouette") for g in out["gates"])  # no turnaround on the cad route
    code, out = run(capsys, "check", "toggle_switch", "--triangle-budget", "5000")
    assert code == 0 and out["ok"], out
    assert Manifest.load(paths.manifest_path(root, "toggle_switch")).stage == "checked"
    code, out = run(capsys, "export", "toggle_switch")
    assert code == 0, out
    assert out["dir"] == "assets/models/kit/toggle_switch"
    assert "assets/models/kit/toggle_switch/toggle_switch.tscn" in out["files"]
    assert not any("concept" in f for f in out["files"])
    assert all("\\" not in f and not Path(f).is_absolute() for f in out["files"])


def test_export_writes_a_scene_with_a_resolving_pivot_and_grab_box_on_layer_2(kit, root, capsys):
    do_import(capsys, kit[0], "--limits", "-40", "40")
    run(capsys, "check", "toggle_switch", "--triangle-budget", "5000")
    assert run(capsys, "export", "toggle_switch")[0] == 0
    tscn = (root / "assets" / "models" / "kit" / "toggle_switch" / "toggle_switch.tscn").read_text()
    assert 'path="res://src/interact/switch_lever.gd"' in tscn
    assert "swing_deg = 80" in tscn
    assert 'path="res://assets/models/kit/toggle_switch/toggle_switch.glb"' in tscn
    pivot = re.search(r'pivot = NodePath\("([^"]+)"\)', tscn).group(1)
    glb = root / "assets" / "models" / "kit" / "toggle_switch" / "toggle_switch.glb"
    # the path is Model/<node in the GLB>: walk the GLB's node tree from its root
    nodes = kit_import.glb_nodes(glb)
    assert pivot == "Model/Pivot" and any(n.get("name") == "Pivot" for n in nodes)
    grab = re.search(r'\[node name="Grab" type="StaticBody3D" parent="."\]\ncollision_layer = (\d+)\ncollision_mask = 0', tscn)
    assert grab and grab.group(1) == "2"
    size = re.search(r"size = Vector3\(([^)]+)\)", tscn).group(1).split(",")
    assert all(float(v) > 0.01 for v in size)
    ext = len(re.findall(r"^\[ext_resource", tscn, re.M)) + len(re.findall(r"^\[sub_resource", tscn, re.M))
    assert f"load_steps={ext + 1}" in tscn


def test_unknown_pivot_part_is_rejected_with_a_clear_error(kit, root, capsys):
    src, calls = kit
    code, out = run(capsys, "import", "toggle_switch", str(src), "--pivot", "Bat")
    assert code == 1 and "no part named 'Bat'" in out["error"] and "Switch" in out["error"]
    assert not calls and not paths.find_asset_dir(root, "toggle_switch")  # nothing was copied or created
    assert not (root / "assets" / "media").exists()
    m = Manifest(slug="x", asset_class="kit")
    with pytest.raises(ValueError, match="no part named 'Bat'"):
        m.set_pivots([cli.PivotRecord(part="Bat")], parts=["Switch"])
    code, out = do_import(capsys, src, "--limits", "40", "-40")
    assert code == 1 and "limits" in out["error"] and not calls
    with pytest.raises(SystemExit):  # argparse rejects an unknown axis
        do_import(capsys, src, "--axis", "q")


def test_paths_stay_posix_and_repo_relative(kit, root, capsys):
    code, out = do_import(capsys, kit[0])
    mpath = paths.manifest_path(root, "toggle_switch")
    text = mpath.read_text()
    assert "\\" not in text and str(root) not in text
    for p in (out["path"], out["source"], out["manifest"]):
        assert not Path(p).is_absolute() and "\\" not in p
    # a manifest written with backslashes is normalised on load
    raw = yaml.safe_load(text)
    raw["lineage"][0]["source"]["path"] = raw["lineage"][0]["source"]["path"].replace("/", "\\")
    raw["imports"][0]["source"] = raw["imports"][0]["source"].replace("/", "\\")
    m = Manifest.from_dict(raw)
    assert "\\" not in m.lineage[0].source["path"] and "\\" not in m.imports[0].source


def test_other_classes_cannot_import_and_kit_has_no_image_stages(kit, root, capsys):
    run(capsys, "new", "rock", "--class", "prop")
    assert "cad route" in run(capsys, "import", "rock", str(kit[0]))[1]["error"]
    run(capsys, "new", "knob", "--class", "kit")
    for cmd in (["concept", "knob", "--brief", "x"], ["turnaround", "knob"], ["brief", "knob"], ["to3d", "knob"],
                ["cleanup", "knob", "--source", "r1"]):
        code, out = run(capsys, *cmd)
        assert code == 1 and "cad route" in out["error"], cmd


def test_fixed_part_import_has_no_pivot_and_a_plain_scene(kit, root, capsys):
    code, out = run(capsys, "import", "toggle_switch", str(kit[0]))
    assert code == 0 and out["pivots"] == []
    run(capsys, "check", "toggle_switch", "--triangle-budget", "5000")
    assert run(capsys, "export", "toggle_switch")[0] == 0
    tscn = (root / "assets" / "models" / "kit" / "toggle_switch" / "toggle_switch.tscn").read_text()
    assert "switch_lever" not in tscn and "collision_layer = 2" in tscn


def test_converter_script_lives_under_the_pipeline():
    import ast
    assert kit_import.SCRIPT.is_file() and not (REPO / "tools" / "kit").exists()
    ast.parse(kit_import.SCRIPT.read_text())  # Blender is not here to run it; at least it parses
    assert kit_import.SCRIPT_REL == kit_import.SCRIPT.relative_to(REPO).as_posix()
