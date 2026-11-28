import json
import struct

import numpy as np
import pytest

from cadkit import catalogue, library, render
from cadkit.skeleton import Bone, Chain, Rigid, Skeleton, lay_chain
from cadkit.skin_checks import (check_skinned_glb, expect_bone_count, expect_no_far_binding, expect_rest_matches,
                                expect_weighted, rest_positions_mm, skeleton_of)
from cadkit.solids import GeometryError, Solid, at, box, export_solids_glb, read_glb, read_skinned, skinned_surfaces


@pytest.fixture
def staging(tmp_path):
    library.set_root(tmp_path)
    library.take_written()
    yield tmp_path
    library.set_root(library.MODELS)
    library.take_written()


def spine():
    return Skeleton(lay_chain("spine", [(0, 0, 0), (100, 0, 0), (100, 100, 0)], 4))


def rig(sk):
    solids = [Solid(at(box(100, 20, 20), x=50), "control_interface", Chain(sk.names())),
              Solid(at(box(10, 10, 10), x=100, y=100), "trim_black", Rigid("spine3"))]
    (a, pos_a, _, ja, wa), (b, pos_b, _, jb, wb) = skinned_surfaces(solids, sk)
    return (np.concatenate([pos_a, pos_b]) * 1000.0, np.concatenate([ja, jb]).astype(int),
            np.concatenate([wa, wb]).astype(float))


def test_a_good_rig_passes_every_check():
    sk = spine()
    pos, j, w = rig(sk)
    expect_weighted(j, w, 4, "fish")
    expect_bone_count(sk, "fish", 8)
    expect_no_far_binding(sk, pos, j, w, "fish", 120.0)
    expect_rest_matches(pos, pos.copy(), "fish")


def test_an_unweighted_vertex_fails():
    _, j, w = rig(spine())
    w[3] = 0.0
    with pytest.raises(GeometryError, match="unweighted"):
        expect_weighted(j, w, 4, "fish")


def test_weights_not_summing_to_one_fail():
    _, j, w = rig(spine())
    w[5] *= 0.5
    with pytest.raises(GeometryError, match="not summing to 1"):
        expect_weighted(j, w, 4, "fish")


def test_a_bone_that_does_not_exist_fails():
    _, j, w = rig(spine())
    j[0, 0] = 9
    with pytest.raises(GeometryError, match="bone 9"):
        expect_weighted(j, w, 4, "fish")


def test_a_far_binding_fails():
    sk = spine()
    pos, j, w = rig(sk)
    j[0], w[0] = [0, 0, 0, 0], [1, 0, 0, 0]
    pos[0] = [100, 400, 0]          # bound to spine0 (head at the origin) but 400 mm away
    with pytest.raises(GeometryError, match="spine0"):
        expect_no_far_binding(sk, pos, j, w, "fish", 120.0)


def test_too_many_bones_fail():
    with pytest.raises(GeometryError, match="4 bones"):
        expect_bone_count(spine(), "fish", 3)


def test_a_rest_pose_that_differs_fails():
    pos, _, _ = rig(spine())
    moved = pos.copy()
    moved[7, 1] += 2.0
    with pytest.raises(GeometryError, match="differs"):
        expect_rest_matches(pos, moved, "fish")
    with pytest.raises(GeometryError, match="vertices"):
        expect_rest_matches(pos, pos[:-1], "fish")


def build(staging, sk=None):
    sk = sk or spine()
    solids = [Solid(at(box(100, 20, 20), x=50), "control_interface", Chain(sk.names())),
              Solid(at(box(10, 10, 10), x=100, y=100), "trim_black", Rigid("spine3"))]
    path = staging / "organics" / "fish" / "fish.glb"
    export_solids_glb(solids, path, "Fish", skeleton=sk)
    return path, solids


def test_a_written_skinned_glb_passes_the_file_checks(staging):
    path, solids = build(staging)
    skel = check_skinned_glb(path, "fish", max_bones=8)
    assert skel.names() == spine().names()
    from cadkit.solids import surfaces
    static = np.concatenate([s[1] for s in surfaces(solids)]) * 1000.0
    check_skinned_glb(path, "fish", static_mm=static)
    with pytest.raises(GeometryError, match="bones"):
        check_skinned_glb(path, "fish", max_bones=2)


def corrupt(path, edit):
    data = path.read_bytes()
    jlen = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jlen])
    blob = bytearray(data[20 + jlen + 8:])
    edit(doc, blob)
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    body = struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(blob), b"BIN\0") + bytes(blob)
    path.write_bytes(struct.pack("<4sII", b"glTF", 2, 12 + len(body)) + body)


def test_a_file_whose_inverse_bind_matrices_disagree_fails_rest(staging):
    path, _ = build(staging)

    def edit(doc, blob):
        acc = doc["accessors"][doc["skins"][0]["inverseBindMatrices"]]
        off = doc["bufferViews"][acc["bufferView"]]["byteOffset"]
        ibm = np.frombuffer(blob, np.float32, 64, off).copy().reshape(4, 16)
        ibm[:, 13] += 0.01
        blob[off:off + 256] = ibm.tobytes()
    corrupt(path, edit)
    with pytest.raises(GeometryError, match="at rest"):
        check_skinned_glb(path, "fish")


def test_a_file_with_an_unweighted_vertex_fails(staging):
    path, _ = build(staging)

    def edit(doc, blob):
        acc = doc["accessors"][doc["meshes"][0]["primitives"][0]["attributes"]["WEIGHTS_0"]]
        off = doc["bufferViews"][acc["bufferView"]]["byteOffset"]
        blob[off:off + 16] = np.zeros(4, np.float32).tobytes()
    corrupt(path, edit)
    with pytest.raises(GeometryError, match="unweighted"):
        check_skinned_glb(path, "fish")


def test_the_glb_is_structurally_valid_gltf(staging):
    path, _ = build(staging)
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", data)
    assert magic == b"glTF" and version == 2 and length == len(data) and length % 4 == 0
    jlen = struct.unpack_from("<I", data, 12)[0]
    assert jlen % 4 == 0
    doc = json.loads(data[20:20 + jlen])
    blen = struct.unpack_from("<I", data, 20 + jlen)[0]
    assert doc["buffers"][0]["byteLength"] <= blen
    for v in doc["bufferViews"]:
        assert v["byteOffset"] % 4 == 0 and v["byteOffset"] + v["byteLength"] <= blen
    for a in doc["accessors"]:
        assert a["bufferView"] < len(doc["bufferViews"]) and a["count"] > 0
    nodes, skin = doc["nodes"], doc["skins"][0]
    assert all(0 <= j < len(nodes) for j in skin["joints"]) and len(set(skin["joints"])) == len(skin["joints"])
    assert doc["accessors"][skin["inverseBindMatrices"]]["count"] == len(skin["joints"])
    assert all(0 <= c < len(nodes) for n in nodes for c in n.get("children", []))
    assert all(0 <= n < len(nodes) for n in doc["scenes"][0]["nodes"])
    seen = list(doc["scenes"][0]["nodes"])   # the node graph is a forest: every node reachable once
    for n in seen:
        seen += nodes[n].get("children", [])
    assert sorted(seen) == list(range(len(nodes)))
    for p in doc["meshes"][0]["primitives"]:
        assert doc["accessors"][p["attributes"]["JOINTS_0"]]["count"] == doc["accessors"][p["attributes"]["POSITION"]]["count"]
        assert p["material"] < len(doc["materials"])


def test_read_glb_reports_bones_and_parents_and_unskinned_is_unchanged(staging):
    path, solids = build(staging)
    g = read_glb(path)
    assert [b["name"] for b in g["bones"]] == spine().names()
    assert [b["parent"] for b in g["bones"]] == [None, "spine0", "spine1", "spine2"]
    assert g["skin"]["joints"] == spine().names()
    plain = staging / "plain.glb"
    export_solids_glb([Solid(box(10, 10, 10), "trim_black")], plain, "P")
    assert set(read_glb(plain)) == {"bounds", "surfaces"}
    with pytest.raises(ValueError):
        read_skinned(plain)
    d = read_skinned(path)
    assert [b["name"] for b in d["bones"]] == spine().names()
    assert d["bones"][1]["head"] * 1000 == pytest.approx(spine().bone("spine1").head)
    assert skeleton_of(d["bones"]).bone("spine2").parent == "spine1"


def test_a_catalogue_entry_carries_bone_names_only_when_there_are_some(staging):
    library.write_entry("organics", "fish", {"kind": "creature", "summary": "a fish"}, bones=spine().names())
    library.write_entry("organics", "rock", {"kind": "prop", "summary": "a rock"})
    cat = catalogue.load(staging)
    by = {e["slug"]: e for e in cat["generated"]}
    assert by["fish"]["bones"] == spine().names()
    assert "bones" not in by["rock"]


def test_posing_maths():
    assert render.parse_pose(["spine3=0,0,90", "spine1=10,0,0"]) == {"spine3": (0, 0, 90), "spine1": (10, 0, 0)}
    with pytest.raises(ValueError):
        render.parse_pose(["spine3=1,2"])
    r = render.rotation_matrix(0, 0, 90)
    assert r @ np.array([1.0, 0, 0]) == pytest.approx([0, 1, 0])
    assert render.rotation_matrix(90, 0, 0) @ np.array([0, 1.0, 0]) == pytest.approx([0, 0, 1])
    assert np.linalg.det(render.rotation_matrix(20, 30, 40)) == pytest.approx(1.0)


def test_a_posed_skinned_scene_moves_what_follows_the_bone(staging):
    path, _ = build(staging)
    rest = render.posed_surfaces(path, {})
    posed = render.posed_surfaces(path, {"spine3": (0, 0, 90)})
    assert len(rest) == len(posed) == 2
    d = read_skinned(path)
    for sf, r in zip(d["surfaces"], rest):
        assert r[1] == pytest.approx(sf["pos"], abs=1e-6)       # no pose is the rest pose
    moved = np.abs(posed[0][1] - rest[0][1]).max(axis=1) > 1e-4
    assert moved.any() and not moved.all()                      # only the tail end of the body follows spine3
    still = np.isclose(posed[0][1][:, 0], rest[0][1][:, 0]) & (rest[0][1][:, 0] < 0.03)
    assert still.any()
    with pytest.raises(ValueError):
        render.posed_surfaces(path, {"nope": (0, 0, 1)})


def test_the_rest_positions_helper_is_identity_for_a_consistent_rig(staging):
    path, _ = build(staging)
    d = read_skinned(path)
    sf = d["surfaces"][0]
    out = rest_positions_mm(d["bones"], sf["pos"], sf["joints"].astype(int), sf["weights"].astype(float))
    assert out == pytest.approx(sf["pos"] * 1000.0, abs=1e-3)
