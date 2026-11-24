import numpy as np
import pytest
import trimesh

from cadkit import library
from cadkit.solids import GeometryError, Solid, at, box, expect, expect_in_front, export_solids_glb, prism, srgb_to_linear


@pytest.fixture
def staging(tmp_path):
    library.set_root(tmp_path)
    library.take_written()
    yield tmp_path
    library.set_root(library.MODELS)
    library.take_written()


def test_a_box_exports_flat_shaded_in_metres_with_a_linear_palette_colour(staging):
    path = staging / "kit" / "thing" / "thing.glb"
    rep = export_solids_glb([Solid(box(100, 50, 20), "safety_orange")], path, "Thing")
    assert rep["triangles"] == 12
    assert rep["glb"] == "res://assets/models/kit/thing/thing.glb"
    assert np.allclose(rep["bbox_m"], [[-0.05, -0.025, 0.0], [0.05, 0.025, 0.02]], atol=1e-6)
    mesh = trimesh.load(path, force="mesh", process=False)
    assert len(mesh.vertices) == 36, "every triangle has its own vertices: flat shading"
    srgb = library.palette()["safety_orange"]
    want = np.round(np.array(srgb_to_linear(srgb)) * 255)
    assert np.allclose(np.asarray(mesh.visual.vertex_colors)[0][:3], want, atol=1)
    assert want[1] < srgb[1] * 255 - 30, "the green channel is darker in linear than in sRGB"
    assert (staging / "kit" / "thing" / "thing.glb.import").read_text().count("vertex_color_import.gd") == 1
    assert library.take_written() == [path]


def test_an_unknown_colour_is_refused(staging):
    with pytest.raises(ValueError, match="not a palette role"):
        export_solids_glb([Solid(box(10, 10, 10), "brass")], staging / "kit" / "x" / "x.glb", "X")


def test_prisms_stay_low_poly_at_any_tolerance(staging):
    a = export_solids_glb([Solid(prism(12, 20, 30), "black")], staging / "kit" / "a" / "a.glb", "A", tol_mm=0.01, ang=0.05)
    b = export_solids_glb([Solid(prism(12, 20, 30), "black")], staging / "kit" / "b" / "b.glb", "B", tol_mm=1.0, ang=1.0)
    assert a["triangles"] == b["triangles"] == 44


def test_expect_and_expect_in_front():
    expect(True, "fine")
    with pytest.raises(GeometryError, match="knob clears the guard"):
        expect(False, "knob clears the guard")
    expect_in_front([Solid(box(10, 10, 10), "black")], "part")
    with pytest.raises(GeometryError, match="behind the mount face"):
        expect_in_front([Solid(at(box(10, 10, 10), z=-3), "black")], "part")
