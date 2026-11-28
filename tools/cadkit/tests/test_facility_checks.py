"""cadkit.facility_checks: each helper passes on a good fixture and fails on a broken one, naming the part."""
import textwrap

import build123d as bd
import pytest

from cadkit import build, facility_checks as fc
from cadkit.solids import GeometryError


def box(x0, y0, z0, x1, y1, z1):
    b = bd.Box(x1 - x0, y1 - y0, z1 - z0, align=bd.Align.MIN)
    return b.moved(bd.Location((x0, y0, z0)))


def wall(door_w=1200, door_h=2200):
    """A wall along X, 200 mm thick, 6 m long and 3 m high, with a door centred at x=3000."""
    w = box(0, 0, 0, 6000, 3000, 200)
    return w - box(3000 - door_w / 2, -1, -1, 3000 + door_w / 2, door_h, 201)


def test_opening_passes_and_measures():
    w, h = fc.expect_opening(wall(), "workshop door", (3000, 1000, 100), "x", 1000, 2100)
    assert 1180 <= w <= 1220 and 2180 <= h <= 2220


def test_narrow_opening_names_part():
    with pytest.raises(GeometryError, match=r"workshop door: opening is [78]\d\d mm wide.*needs 1000"):
        fc.expect_opening(wall(door_w=800), "workshop door", (3000, 1000, 100), "x", 1000, 2100)


def test_low_opening_names_part():
    with pytest.raises(GeometryError, match="workshop door: opening is .* high"):
        fc.expect_opening(wall(door_h=2000), "workshop door", (3000, 1000, 100), "x", 1000, 2100)


def test_grounded():
    fc.expect_grounded(box(0, 0, 0, 1000, 1000, 1000), "tower")
    with pytest.raises(GeometryError, match="tower: base is \\+500 mm"):
        fc.expect_grounded(box(0, 500, 0, 1000, 1000, 1000), "tower")


def test_overhang_needs_struts_to_ground_or_cliff():
    arm = box(0, 8000, -9000, 4000, 9000, 0)
    good = {"s1": box(0, 0, -400, 400, 8000, 0)}
    fc.expect_overhang_supported(arm, "arm", good)
    with pytest.raises(GeometryError, match="arm: a declared overhang has no struts"):
        fc.expect_overhang_supported(arm, "arm", {})
    with pytest.raises(GeometryError, match="arm: strut s2 stops 3000 mm above the ground"):
        fc.expect_overhang_supported(arm, "arm", {"s2": box(0, 3000, -400, 400, 8000, 0)})
    with pytest.raises(GeometryError, match="strut s3 does not touch the overhang"):
        fc.expect_overhang_supported(arm, "arm", {"s3": box(2000, 0, 1000, 2400, 500, 1400)})
    cliff = box(-3000, 0, 0, 0, 12000, 5000)
    fc.expect_overhang_supported(arm, "arm", {"s4": box(0, 4000, -400, 400, 8000, 0)}, cliff=cliff)


def test_interior_inside_exterior():
    ext = box(0, 0, 0, 10000, 6000, 10000)
    fc.expect_interior_inside(box(500, 500, 500, 9500, 5500, 9500), ext, "hub")
    with pytest.raises(GeometryError, match="hub: interior pokes 200 mm through the exterior's X max face"):
        fc.expect_interior_inside(box(500, 500, 500, 10200, 5500, 9500), ext, "hub")
    with pytest.raises(GeometryError, match=r"hub: interior is 0 mm from the exterior's Y min face \(coplanar\)"):
        fc.expect_interior_inside(box(500, 0, 500, 9500, 5500, 9500), ext, "hub")
    with pytest.raises(GeometryError, match="hub: interior is 100 mm"):
        fc.expect_interior_inside(box(100, 500, 500, 9500, 5500, 9500), ext, "hub")


def test_collar_clear():
    fc.expect_collar_clear(1200, 900)
    with pytest.raises(GeometryError, match="docking collar: clear diameter 1000 mm does not take the 900 mm"):
        fc.expect_collar_clear(1000, 900)


HATCH = (0.0, 8000.0, 0.0)


def test_dock_envelope_and_tower():
    fc.expect_dock_envelope(HATCH, {"strut": box(8000, 0, -400, 8400, 8000, 0)}, tower_mm=500, collar_depth_mm=600)
    with pytest.raises(GeometryError, match="500 mm tower fitting does not fit the 300 mm deep collar"):
        fc.expect_dock_envelope(HATCH, {}, tower_mm=500, collar_depth_mm=300)
    with pytest.raises(GeometryError, match="keel enter the docked sub's 10 x 3.8 x 3 m envelope"):
        fc.expect_dock_envelope(HATCH, {"keel": box(-200, 5500, -200, 200, 8000, 200)})


def test_straight_approach_clear_of_struts():
    start = (0.0, 0.0, -12000.0)
    far = {"strut": box(8000, 0, -9000, 8400, 8000, -8600)}
    fc.expect_clear_approach(start, HATCH, far)
    across = {"strut_a": box(-3000, 0, -9000, 3000, 8000, -8600)}
    with pytest.raises(GeometryError, match="strut_a block the sub's straight approach"):
        fc.expect_clear_approach(start, HATCH, across)


SCENE = '''
from cadkit.library import out_dir, write_entry
from cadkit.solids import Solid, box, export_solids_glb
from cadkit import facility_checks as fc

SLUG, GROUP = "fixture", "{group}"
USES: list[str] = []


def build() -> dict:
    s = box(500, 100, 500)
    fc.expect_grounded(s, "fixture", ground_y=s.bounding_box().min.Y)
    rep = export_solids_glb([Solid(s, "trim_black")], out_dir(GROUP, SLUG) / "fixture.glb", "N")
    write_entry(GROUP, SLUG, {{"kind": "element", "summary": "t", "tags": [], "triangles": rep["triangles"]}})
    return {{"slug": SLUG}}
'''


def _run(tmp_path, group):
    scenes, models = tmp_path / "scenes", tmp_path / "models"
    scenes.mkdir()
    models.mkdir()
    (scenes / "fixture.py").write_text(textwrap.dedent(SCENE.format(group=group)))
    return build.run("check", scenes, models)


def test_checks_run_in_facilities_scene(tmp_path):
    assert _run(tmp_path, "facilities")["ok"]


def test_checks_refused_in_other_groups(tmp_path):
    r = _run(tmp_path, "kit")
    assert not r["ok"] and "run only for facilities" in r["error"]
