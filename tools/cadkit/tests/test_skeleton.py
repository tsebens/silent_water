import json
import struct

import numpy as np
import pytest

from cadkit import library
from cadkit.skeleton import Bone, Chain, Rigid, Skeleton, lay_chain, limit_influences, skin_positions
from cadkit.solids import Solid, at, box, export_solids_glb, read_glb, surfaces, write_glb


@pytest.fixture
def staging(tmp_path):
    library.set_root(tmp_path)
    library.take_written()
    yield tmp_path
    library.set_root(library.MODELS)
    library.take_written()


def spine():
    return Skeleton(lay_chain("spine", [(0, 0, 0), (100, 0, 0), (100, 100, 0)], 4))


def parse(path):
    data = path.read_bytes()
    jlen = struct.unpack_from("<I", data, 12)[0]
    doc = json.loads(data[20:20 + jlen])
    blob = data[20 + jlen + 8:]
    return doc, blob


def test_chain_is_laid_along_a_polyline_in_equal_lengths():
    bones = lay_chain("s", [(0, 0, 0), (100, 0, 0), (100, 100, 0)], 4, parent="root")
    assert [b.name for b in bones] == ["s0", "s1", "s2", "s3"]
    assert [b.parent for b in bones] == ["root", "s0", "s1", "s2"]
    assert bones[0].head == (0, 0, 0) and bones[1].head == pytest.approx((50, 0, 0))
    assert bones[2].head == pytest.approx((100, 0, 0)) and bones[3].head == pytest.approx((100, 50, 0))
    assert bones[3].tail == pytest.approx((100, 100, 0))
    for a, b in zip(bones, bones[1:]):
        assert a.tail == pytest.approx(b.head)


def test_vertex_at_a_joint_is_one_bone_and_between_joints_it_blends():
    sk = spine()
    pos = np.array([[50, 0, 0], [25, 0, 0], [75, 10, 0], [-20, 0, 0], [100, 200, 0], [0, 5, 0]], dtype=float)
    j, w = sk.weights(Chain(sk.names()), pos)
    def of(i):
        return {int(a): round(float(b), 5) for a, b in zip(j[i], w[i]) if b > 0}
    assert of(0) == {1: 1.0}
    assert of(1) == {0: 0.5, 1: 0.5}
    assert of(2) == {1: 0.5, 2: 0.5}
    assert of(3) == {0: 1.0}, "before the chain: the first bone"
    assert of(4) == {3: 1.0}, "past the chain: the last bone"
    assert of(5) == {0: 1.0}


def test_rigid_binding_is_one_bone_fully():
    sk = spine()
    j, w = sk.weights(Rigid("spine2"), np.zeros((5, 3)))
    assert (j[:, 0] == 2).all() and (w[:, 0] == 1).all() and (w[:, 1:] == 0).all()


def test_at_most_four_influences_normalised():
    full = np.array([[0.1, 0.4, 0.2, 0.05, 0.25, 0.0], [1.0, 0, 0, 0, 0, 0]])
    j, w = limit_influences(full)
    assert j.shape == (2, 4) and w.shape == (2, 4)
    assert set(j[0].tolist()) == {1, 4, 2, 0}
    assert w.sum(axis=1) == pytest.approx([1.0, 1.0])
    assert w[0, 0] == pytest.approx(0.4 / 0.95)
    with pytest.raises(ValueError):
        limit_influences(np.zeros((1, 3)))


def test_skeleton_rejects_bad_hierarchy():
    with pytest.raises(ValueError):
        Skeleton([Bone("a", (0, 0, 0), (1, 0, 0), "b"), Bone("b", (1, 0, 0), (2, 0, 0))])
    with pytest.raises(ValueError):
        Skeleton([Bone("a", (0, 0, 0), (1, 0, 0)), Bone("a", (1, 0, 0), (2, 0, 0))])


def test_rotating_a_bone_moves_what_follows_it_and_leaves_the_rest():
    sk = spine()
    pos = np.array([[0, 0, 0], [100, 0, 0], [100, 100, 0]], dtype=float)
    j, w = sk.weights(Chain(sk.names()), pos)
    assert skin_positions(sk, j, w, pos) == pytest.approx(pos)
    rz = np.array([[0, -1, 0], [1, 0, 0], [0, 0, 1]], dtype=float)  # 90 degrees about Z
    moved = skin_positions(sk, j, w, pos, {"spine2": rz})
    assert moved[0] == pytest.approx(pos[0])
    assert not np.allclose(moved[2], pos[2])


def test_a_skinned_glb_reads_back(staging):
    sk = spine()
    solids = [Solid(at(box(100, 20, 20), x=50), "control_interface", Chain(sk.names())),
              Solid(at(box(10, 10, 10), x=100, y=100), "trim_black", Rigid("spine3")),
              Solid(at(box(10, 10, 10), x=-80), "control_interface", Rigid("spine0"))]
    path = staging / "kit" / "fish" / "fish.glb"
    rep = export_solids_glb(solids, path, "Fish", skeleton=sk)
    assert rep["bones"] == sk.names()
    doc, blob = parse(path)
    skin = doc["skins"][0]
    assert [doc["nodes"][j]["name"] for j in skin["joints"]] == sk.names()
    assert doc["nodes"][0]["skin"] == 0 and doc["nodes"][0]["mesh"] == 0
    # hierarchy: spine0 is a scene root, each bone the child of the one before
    assert 1 in doc["scenes"][0]["nodes"]
    for i in range(1, 4):
        assert (1 + i) in doc["nodes"][i].get("children", [])
    ibm_acc = doc["accessors"][skin["inverseBindMatrices"]]
    assert ibm_acc["type"] == "MAT4" and ibm_acc["count"] == 4
    view = doc["bufferViews"][ibm_acc["bufferView"]]
    ibm = np.frombuffer(blob, np.float32, 64, view["byteOffset"]).reshape(4, 16)
    for i, b in enumerate(sk.bones):
        assert ibm[i, 12:15] == pytest.approx(-np.array(b.head) / 1000.0)
        assert ibm[i, [0, 5, 10, 15]] == pytest.approx(1.0)
    for p in doc["meshes"][0]["primitives"]:
        n = doc["accessors"][p["attributes"]["POSITION"]]["count"]
        ja, wa = doc["accessors"][p["attributes"]["JOINTS_0"]], doc["accessors"][p["attributes"]["WEIGHTS_0"]]
        assert ja["componentType"] == 5123 and ja["type"] == "VEC4" and ja["count"] == n
        assert wa["componentType"] == 5126 and wa["count"] == n
        v = doc["bufferViews"][wa["bufferView"]]
        w = np.frombuffer(blob, np.float32, n * 4, v["byteOffset"]).reshape(n, 4)
        v = doc["bufferViews"][ja["bufferView"]]
        j = np.frombuffer(blob, np.uint16, n * 4, v["byteOffset"]).reshape(n, 4)
        assert w.sum(axis=1) == pytest.approx(1.0, abs=1e-5)
        assert j.max() < 4
    glb = read_glb(path)
    assert [b["name"] for b in glb["bones"]] == sk.names()
    assert glb["bones"][0]["parent"] is None and glb["bones"][2]["parent"] == "spine1"
    assert glb["skin"]["inverse_bind_matrices"] == 4


def test_bindings_survive_the_per_role_merge(staging):
    sk = spine()
    solids = [Solid(box(10, 10, 10), "control_interface", Rigid("spine0")),
              Solid(at(box(10, 10, 10), x=100), "control_interface", Rigid("spine3"))]
    from cadkit.solids import skinned_surfaces
    (role, pos, nrm, j, w), = skinned_surfaces(solids, sk)
    assert len(pos) == len(j) == len(w) == 72
    assert set(j[:36, 0]) == {0} and set(j[36:, 0]) == {3}


def test_an_unbound_solid_in_a_skinned_scene_is_refused(staging):
    with pytest.raises(ValueError):
        export_solids_glb([Solid(box(10, 10, 10), "trim_black")], staging / "a.glb", "A", skeleton=spine())


def test_without_a_skeleton_the_glb_is_unchanged(staging):
    solids = [Solid(box(100, 50, 20), "control_interface"), Solid(at(box(10, 10, 10), x=80), "trim_black")]
    a, b = staging / "a.glb", staging / "b.glb"
    write_glb(a, "T", surfaces(solids))
    export_solids_glb(solids, b, "T")
    assert a.read_bytes() == b.read_bytes()
    doc, _ = parse(a)
    assert "skins" not in doc and doc["nodes"] == [{"name": "T", "mesh": 0}]
    assert "JOINTS_0" not in doc["meshes"][0]["primitives"][0]["attributes"]
    assert "bones" not in read_glb(a)
