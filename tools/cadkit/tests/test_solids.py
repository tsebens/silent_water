import numpy as np
import pytest

from cadkit import library
from cadkit.solids import (GeometryError, Solid, at, box, expect, expect_in_front, export_solids_glb, prism, read_glb,
                           srgb_to_linear)


@pytest.fixture
def staging(tmp_path):
    library.set_root(tmp_path)
    library.take_written()
    yield tmp_path
    library.set_root(library.MODELS)
    library.take_written()


def test_roles_come_from_the_godot_palette():
    roles = library.roles()
    sw = library.swatches()
    assert "control_interface" in roles and roles["control_interface"]["swatch"] == "sub_orange"
    assert sw["sub_orange"] == pytest.approx((1.0, 0x90 / 255, 0x40 / 255), abs=1e-6)
    for name, r in roles.items():
        for field in ("swatch", "glow", "stripe"):
            assert not r[field] or r[field] in sw, f"{name}.{field} names a swatch that does not exist"


def test_a_glb_has_one_surface_per_role_named_by_the_role(staging):
    path = staging / "kit" / "thing" / "thing.glb"
    solids = [Solid(box(100, 50, 20), "control_interface"), Solid(at(box(10, 10, 10), x=80), "trim_black"),
              Solid(at(box(10, 10, 10), x=-80), "control_interface")]
    rep = export_solids_glb(solids, path, "Thing")
    assert rep["triangles"] == 36
    assert rep["glb"] == "res://assets/models/kit/thing/thing.glb"
    glb = read_glb(path)
    assert glb["surfaces"] == {"control_interface": 24, "trim_black": 12}, "solids of one role share a surface"
    assert np.allclose(glb["bounds"], [[-0.085, -0.025, 0.0], [0.085, 0.025, 0.02]], atol=1e-6)
    assert (staging / "kit" / "thing" / "thing.glb.import").read_text().count("vertex_color_import.gd") == 1
    assert library.take_written() == [path]


def test_the_preview_colour_is_linear_and_a_glowing_role_shows_its_glow(staging):
    import json, struct
    path = staging / "kit" / "ink" / "ink.glb"
    export_solids_glb([Solid(box(10, 10, 10), "readout_ink")], path, "Ink")
    data = path.read_bytes()
    doc = json.loads(data[20:20 + struct.unpack_from("<I", data, 12)[0]])
    want = srgb_to_linear(library.swatches()["light_readout"])
    assert doc["materials"][0]["name"] == "readout_ink"
    assert doc["materials"][0]["pbrMetallicRoughness"]["baseColorFactor"][:3] == pytest.approx(want, abs=1e-5)


def test_an_unknown_role_is_refused(staging):
    with pytest.raises(ValueError, match="not a palette role"):
        export_solids_glb([Solid(box(10, 10, 10), "brass")], staging / "kit" / "x" / "x.glb", "X")


def test_prisms_stay_low_poly_at_any_tolerance(staging):
    a = export_solids_glb([Solid(prism(12, 20, 30), "trim_black")], staging / "kit" / "a" / "a.glb", "A", tol_mm=0.01, ang=0.05)
    b = export_solids_glb([Solid(prism(12, 20, 30), "trim_black")], staging / "kit" / "b" / "b.glb", "B", tol_mm=1.0, ang=1.0)
    assert a["triangles"] == b["triangles"] == 44


def test_expect_and_expect_in_front():
    expect(True, "fine")
    with pytest.raises(GeometryError, match="knob clears the guard"):
        expect(False, "knob clears the guard")
    expect_in_front([Solid(box(10, 10, 10), "trim_black")], "part")
    with pytest.raises(GeometryError, match="behind the mount face"):
        expect_in_front([Solid(at(box(10, 10, 10), z=-3), "trim_black")], "part")
