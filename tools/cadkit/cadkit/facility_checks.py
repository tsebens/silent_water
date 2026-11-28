"""Facility geometry checks: `expect` helpers a `facilities` build script calls on the geometry it built.

`cadkit.facility` checks the program's numbers (rooms, doors, routes). These check the built solids, in the site
frame of `docs/asset_process.md` (millimetres in CAD: ground at Y=0, X along the ledge, the chasm toward -Z):

- `expect_opening`        the clear width and height of an opening cut in a generated wall, measured on the solid
- `expect_grounded`       a structure's base meets the ground
- `expect_overhang_supported`  a declared overhang has struts that reach the ground or the cliff face
- `expect_interior_inside` the interior sits inside the exterior with a minimum wall and no coplanar faces
- `expect_collar_clear`, `expect_dock_envelope`, `expect_clear_approach`  the docking arm and the sub

Each raises `GeometryError` (like `solids.expect`) with a message that names the part. Each use is logged;
`cadkit.build` takes the log after every scene and fails a scene outside the `facilities` group that used one, so
the checks never run for other groups.
"""
from __future__ import annotations

import build123d as bd

from cadkit.solids import expect

SUB_LENGTH_MM, SUB_WIDTH_MM, SUB_HEIGHT_MM = 10000.0, 3800.0, 3000.0   # the sub's hull envelope (sub_interior program)
GROUND_TOL_MM = 50.0        # a base within this of the ground meets it
MIN_WALL_MM = 300.0         # the least wall between interior and exterior
COLLAR_MARGIN_MM = 200.0    # clear diameter beyond the dorsal hatch, in total
PROBE_STEP_MM = 10.0

_log: list[str] = []


def take_log() -> list[str]:
    """The checks called since the last take (cadkit.build reads this after every scene)."""
    out = list(_log)
    _log.clear()
    return out


def _bounds(shape: bd.Shape) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    b = shape.bounding_box()
    return (b.min.X, b.min.Y, b.min.Z), (b.max.X, b.max.Y, b.max.Z)


def _solid(point: tuple[float, float, float], shape: bd.Shape) -> bool:
    return bool(shape.is_inside(bd.Vector(*point)))


def _march(wall: bd.Shape, start: tuple[float, float, float], axis: int, sign: int, limit: float) -> float:
    """How far from `start` along an axis (sign +-1) before the wall's material, up to `limit` (mm)."""
    d = 0.0
    while d < limit:
        p = list(start)
        p[axis] += sign * (d + PROBE_STEP_MM)
        if _solid(tuple(p), wall):
            return d + PROBE_STEP_MM / 2   # the wall starts somewhere within this step
        d += PROBE_STEP_MM
    return limit


def measure_opening(wall: bd.Shape, centre: tuple[float, float, float], along: str, sill_y: float,
                    limit_mm: float = 4000.0) -> tuple[float, float]:
    """(clear width, clear height) mm of the opening in `wall` through `centre`, a point inside the opening.

    `along` is the wall's run, "x" or "z". Width is measured across the opening at the centre point's height; height
    from `sill_y` up through the centre point. Raises if the centre is not in the open."""
    axis = 0 if along == "x" else 2
    if _solid(centre, wall):
        raise ValueError("centre of the opening is inside the wall")
    w = _march(wall, centre, axis, -1, limit_mm) + _march(wall, centre, axis, 1, limit_mm)
    base = (centre[0], sill_y + PROBE_STEP_MM, centre[2])
    h = PROBE_STEP_MM + _march(wall, base, 1, 1, limit_mm)
    return w, h


def expect_opening(wall: bd.Shape, what: str, centre: tuple[float, float, float], along: str, min_width_mm: float,
                   min_height_mm: float, sill_y: float = 0.0) -> tuple[float, float]:
    """A wall's opening, measured on the built solid, is at least as wide and high as the program says."""
    _log.append("opening")
    width, height = measure_opening(wall, centre, along, sill_y)
    expect(width >= min_width_mm, f"{what}: opening is {width:.0f} mm wide in the built wall; the program needs {min_width_mm:.0f} mm")
    expect(height >= min_height_mm, f"{what}: opening is {height:.0f} mm high in the built wall; the program needs {min_height_mm:.0f} mm")
    return width, height


def expect_grounded(shape: bd.Shape, what: str, ground_y: float = 0.0, tol_mm: float = GROUND_TOL_MM) -> None:
    """A structure's base meets the ground: its lowest point is within `tol_mm` of `ground_y`."""
    _log.append("grounded")
    low = _bounds(shape)[0][1]
    expect(abs(low - ground_y) <= tol_mm,
           f"{what}: base is {low - ground_y:+.0f} mm from the ground (Y={ground_y:.0f}); it floats or is buried beyond {tol_mm:.0f} mm")


def _touches(a: bd.Shape, b: bd.Shape, tol_mm: float) -> bool:
    (alo, ahi), (blo, bhi) = _bounds(a), _bounds(b)
    if any(alo[i] > bhi[i] + tol_mm or blo[i] > ahi[i] + tol_mm for i in range(3)):
        return False
    return a.distance_to(b) <= tol_mm


def expect_overhang_supported(overhang: bd.Shape, what: str, struts: dict[str, bd.Shape], ground_y: float = 0.0,
                              cliff: bd.Shape | None = None, tol_mm: float = GROUND_TOL_MM) -> None:
    """A declared overhang has struts, each touching the overhang and reaching the ground or the cliff face."""
    _log.append("overhang")
    expect(bool(struts), f"{what}: a declared overhang has no struts to the ground or the cliff face")
    for name, strut in struts.items():
        expect(_touches(strut, overhang, tol_mm), f"{what}: strut {name} does not touch the overhang")
        reaches = _bounds(strut)[0][1] <= ground_y + tol_mm or (cliff is not None and _touches(strut, cliff, tol_mm))
        expect(reaches, f"{what}: strut {name} stops {_bounds(strut)[0][1] - ground_y:.0f} mm above the ground and does not reach the cliff face")


def expect_interior_inside(interior: bd.Shape, exterior: bd.Shape, what: str, min_wall_mm: float = MIN_WALL_MM) -> None:
    """The interior sits inside the exterior's bounds with at least `min_wall_mm` on every side.

    A margin on every side also rules out coplanar faces (the mount-gap rule), which would flicker."""
    _log.append("interior")
    (ilo, ihi), (elo, ehi) = _bounds(interior), _bounds(exterior)
    for i, axis in enumerate("XYZ"):
        for side, gap in (("min", ilo[i] - elo[i]), ("max", ehi[i] - ihi[i])):
            if gap < 0:
                expect(False, f"{what}: interior pokes {-gap:.0f} mm through the exterior's {axis} {side} face")
            expect(gap >= min_wall_mm, f"{what}: interior is {gap:.0f} mm from the exterior's {axis} {side} face"
                   f"{' (coplanar)' if gap < 1 else ''}; the wall must be at least {min_wall_mm:.0f} mm")


def expect_collar_clear(collar_clear_mm: float, hatch_mm: float, what: str = "docking collar", margin_mm: float = COLLAR_MARGIN_MM) -> None:
    """The collar's clear diameter takes the sub's dorsal hatch with `margin_mm` to spare (in total)."""
    _log.append("collar")
    expect(collar_clear_mm >= hatch_mm + margin_mm,
           f"{what}: clear diameter {collar_clear_mm:.0f} mm does not take the {hatch_mm:.0f} mm dorsal hatch with {margin_mm:.0f} mm margin")


def _envelope(hatch: tuple[float, float, float], heading: str, tower_mm: float, hatch_offset_mm: float) -> bd.Shape:
    """The docked sub's hull envelope, its top at the hatch's Y (the collar underside), centred on the hatch in plan."""
    sx, sz = (SUB_LENGTH_MM, SUB_WIDTH_MM) if heading == "x" else (SUB_WIDTH_MM, SUB_LENGTH_MM)
    box = bd.Box(sx, SUB_HEIGHT_MM, sz, align=(bd.Align.CENTER, bd.Align.MAX, bd.Align.CENTER))
    return box.moved(bd.Location((hatch[0] + (hatch_offset_mm if heading == "x" else 0), hatch[1], hatch[2] + (hatch_offset_mm if heading == "z" else 0))))


def _hits(obstacles: dict[str, bd.Shape], volume: bd.Shape) -> list[str]:
    lo, hi = _bounds(volume)
    out = []
    for name, shape in obstacles.items():
        slo, shi = _bounds(shape)
        if any(slo[i] >= hi[i] or shi[i] <= lo[i] for i in range(3)):
            continue
        common = shape.intersect(volume)
        if common and sum(c.volume for c in common) > 1.0:
            out.append(name)
    return out


def expect_dock_envelope(hatch: tuple[float, float, float], under_arm: dict[str, bd.Shape], what: str = "docking arm",
                         tower_mm: float = 0.0, collar_depth_mm: float = 0.0, heading: str = "z",
                         hatch_offset_mm: float = 0.0) -> None:
    """The 10 x 3.8 x 3 m hull envelope fits under the arm with its dorsal hatch on the collar at `hatch` (mm, the
    collar's underside). `under_arm` is what hangs or stands below the arm's floor (struts, keels, fins), by name;
    none may enter the envelope. The tower fitting (`tower_mm` high) stands in the collar, so it needs `collar_depth_mm`."""
    _log.append("dock_envelope")
    expect(tower_mm <= collar_depth_mm,
           f"{what}: the {tower_mm:.0f} mm tower fitting does not fit the {collar_depth_mm:.0f} mm deep collar")
    hit = _hits(under_arm, _envelope(hatch, heading, tower_mm, hatch_offset_mm))
    expect(not hit, f"{what}: {', '.join(hit)} enter the docked sub's {SUB_LENGTH_MM/1000:g} x {SUB_WIDTH_MM/1000:g} x {SUB_HEIGHT_MM/1000:g} m envelope")


def expect_clear_approach(start: tuple[float, float, float], hatch: tuple[float, float, float], obstacles: dict[str, bd.Shape],
                          what: str = "docking arm", heading: str = "z", hatch_offset_mm: float = 0.0, step_mm: float = 250.0) -> None:
    """A straight approach from `start` (the sub's hatch position in the chasm) to the docked position is clear of
    `obstacles` (struts, keels, fins), sweeping the hull envelope along the line."""
    _log.append("dock_approach")
    d = [hatch[i] - start[i] for i in range(3)]
    length = sum(c * c for c in d) ** 0.5
    steps = max(1, int(length / step_mm))
    for k in range(steps + 1):
        t = k / steps
        p = (start[0] + d[0] * t, start[1] + d[1] * t, start[2] + d[2] * t)
        hit = _hits(obstacles, _envelope(p, heading, 0.0, hatch_offset_mm))
        expect(not hit, f"{what}: {', '.join(hit)} block the sub's straight approach, {t * length:.0f} mm along it")
