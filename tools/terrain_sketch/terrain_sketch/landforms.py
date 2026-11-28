"""Stage 1a, the macro shape: a base field in the map's depth range, then landforms pressed into it.
Every landform is a planar footprint (distance to a point, ellipse or polyline) with a profile across it,
combined with smooth min/max so edges stay organic. All counts and positions come from the seed."""
from __future__ import annotations
from dataclasses import dataclass, field
import numpy as np
from . import noise
from .grid import MapPreset, smin, smax, smoothstep, polyline_distance


@dataclass
class Landform:
    kind: str
    pts: np.ndarray            # (n, 2) world x, z: a centre (1 point) or a polyline
    size: float                # radius or half-width in metres
    amount: float              # depth (chasm, pit), height (seamount) or step (scarp), metres
    note: str = ""


@dataclass
class MacroResult:
    h: np.ndarray
    landforms: list[Landform] = field(default_factory=list)
    log: list[str] = field(default_factory=list)


def _catmull_rom(pts: np.ndarray, per_segment: int = 8) -> np.ndarray:
    """Resample a polyline through its points as a Catmull-Rom spline."""
    if len(pts) < 3:
        return pts
    p = np.vstack([pts[0], pts, pts[-1]])
    out = []
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        for k in range(per_segment):
            s = k / per_segment
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s * s + (-p0 + 3 * p1 - 3 * p2 + p3) * s ** 3))
    out.append(p[-2])
    return np.array(out)


def _random_walk(rng: np.random.Generator, preset: MapPreset, n: int, start: np.ndarray, heading: float,
                 step: float, wiggle: float) -> np.ndarray:
    """A meandering smooth curve that stays inside the map."""
    pts = [start.copy()]
    p = start.copy()
    hw, hl = preset.width_m / 2 - 80, preset.length_m / 2 - 80
    for _ in range(n - 1):
        heading += rng.normal(0.0, wiggle)
        p = p + step * np.array([np.cos(heading), np.sin(heading)])
        if abs(p[0]) > hw or abs(p[1]) > hl:
            heading = np.arctan2(-p[1], -p[0]) + rng.normal(0.0, 0.3)
            p = np.array([np.clip(p[0], -hw, hw), np.clip(p[1], -hl, hl)])
        pts.append(p.copy())
    return _catmull_rom(np.array(pts))


def base_field(preset: MapPreset, seed: int, x: np.ndarray, z: np.ndarray, u_offset: np.ndarray | None = None) -> np.ndarray:
    """Broad structure across the whole depth range: a shallow shelf, a mid terrace and a deep plain, as
    three soft steps of a warped noise field (shelf, slope, plain, like a continental margin), with gentle
    relief on each level and a regional tilt. Levels and their shares vary with the seed."""
    rng = np.random.default_rng(seed)
    wx, wz = noise.warp(x, z, seed + 1, wavelength=1500.0, amount=300.0)
    n = noise.fbm(wx, wz, seed + 2, wavelength=1400.0, octaves=4, gain=0.5)
    u = n * 0.5 + 0.5
    if u_offset is not None:
        u = u + u_offset   # faults shift ground up or down a level before the staircase
    u = np.clip(u, 0.0, 1.0)
    # Three levels as fractions of the range (0 deep, 1 shallow) and where in u each step sits.
    # The three flats sit where stations need ground: one in the deep band, one in the middle band, one shallow.
    span = preset.depth_shallow - preset.depth_deep
    levels = np.array([(rng.uniform(*b) - preset.depth_deep) / span for b in preset.terrace_bands])
    # Area shares of plain, terrace and shelf set the step positions as quantiles of the field, so every level
    # has real ground whatever the noise happens to span this seed.
    shares = rng.dirichlet([6.0, 6.0, 5.0])
    steps = np.quantile(u, [shares[0], shares[0] + shares[1]])
    width = 0.04 + 0.03 * rng.random()
    t = levels[0] + (levels[1] - levels[0]) * smoothstep(steps[0] - width, steps[0] + width, u) \
        + (levels[2] - levels[1]) * smoothstep(steps[1] - width, steps[1] + width, u)
    # Relief on the levels: a little of the raw field, more on the shelf than the plain.
    t = t + (u - 0.5) * (0.02 + 0.04 * t)
    tilt_dir = rng.uniform(0.0, 2 * np.pi)
    tilt = (x * np.cos(tilt_dir) + z * np.sin(tilt_dir)) / max(preset.width_m, preset.length_m)
    t = np.clip(t + tilt * rng.uniform(0.04, 0.12), 0.0, 1.0)
    return preset.depth_deep + t * (preset.depth_shallow - preset.depth_deep)


def _chasm(h: np.ndarray, x: np.ndarray, z: np.ndarray, pts: np.ndarray, half_width: float, depth: float,
           seed: int, head_fade: float = 0.15) -> np.ndarray:
    """A trough along a polyline: U-shaped floor, walls steepening with depth, depth and width varying along it."""
    d, t, _ = polyline_distance(x, z, pts)
    # Width and depth grow from the head toward the mouth, with meander noise on the edge.
    along = smoothstep(0.0, head_fade, t) * (1.0 - smoothstep(0.9, 1.0, t))
    wobble = 1.0 + 0.35 * noise.fbm(x, z, seed, wavelength=180.0, octaves=3)
    w = half_width * (0.55 + 0.45 * t) * wobble
    depth_here = depth * (0.5 + 0.5 * t) * along
    # Cross profile: flat floor inside 0.45 w, then a rounded wall to the rim at w.
    r = d / np.maximum(w, 1.0)
    profile = 1.0 - smoothstep(0.45, 1.0, r) ** 0.8
    floor = h - depth_here * profile
    return smin(h, floor, 12.0)


def _pit(h: np.ndarray, x: np.ndarray, z: np.ndarray, c: np.ndarray, radius: float, depth: float, seed: int,
         ellipse: float, angle: float) -> np.ndarray:
    """A steep-walled hole with a flat floor: a collapse pit or sinkhole."""
    dx, dz = x - c[0], z - c[1]
    ex = dx * np.cos(angle) + dz * np.sin(angle)
    ez = -dx * np.sin(angle) + dz * np.cos(angle)
    r = np.hypot(ex / radius, ez / (radius * ellipse))
    r = r * (1.0 + 0.18 * noise.fbm(x, z, seed, wavelength=120.0, octaves=3))
    profile = 1.0 - smoothstep(0.7, 1.0, r)
    return smin(h, h - depth * profile, 8.0)


def _seamount(h: np.ndarray, x: np.ndarray, z: np.ndarray, c: np.ndarray, radius: float, height: float,
              seed: int) -> np.ndarray:
    """A cone with ridged flanks: a seamount or mountain."""
    r = np.hypot(x - c[0], z - c[1]) / radius
    r = r * (1.0 + 0.25 * noise.fbm(x, z, seed, wavelength=220.0, octaves=3))
    cone = np.clip(1.0 - r, 0.0, 1.0) ** 1.4
    ridge = noise.ridged(x, z, seed + 5, wavelength=160.0, octaves=3)
    shape = cone * (0.75 + 0.5 * ridge)
    return smax(h, h + height * shape, 10.0)


def _scarp_field(x: np.ndarray, z: np.ndarray, pts: np.ndarray, blend: float, seed: int) -> np.ndarray:
    """A fault line's influence, 0..1: 1 on the left of travel across a narrow blend, fading at both ends. Added
    to the base noise before the staircase, it lifts or drops a whole block by part of a level, so the fault
    reads as the cliff between two flats."""
    d, t, side = polyline_distance(x, z, pts)
    ends = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.88, 1.0, t))
    wob = noise.fbm(x, z, seed, wavelength=150.0, octaves=3) * blend * 0.8
    s = side * d + wob
    return smoothstep(-blend, blend, s) * ends


def build_macro(preset: MapPreset, seed: int) -> MacroResult:
    rng = np.random.default_rng(seed * 7919 + 17)
    x, z = preset.coords()
    forms: list[Landform] = []
    log: list[str] = []
    area_km2 = preset.width_m * preset.length_m / 1e6
    span = preset.depth_shallow - preset.depth_deep

    def pick_start(margin: float = 150.0) -> np.ndarray:
        return np.array([rng.uniform(-preset.width_m / 2 + margin, preset.width_m / 2 - margin),
                         rng.uniform(-preset.length_m / 2 + margin, preset.length_m / 2 - margin)])

    # Scarps first, as offsets in level units: they decide which blocks sit a level up or down.
    u_off = np.zeros_like(x)
    for i in range(rng.integers(1, 3)):
        pts = _random_walk(rng, preset, 6, pick_start(), rng.uniform(0, 2 * np.pi), 420.0, 0.35)
        step = rng.uniform(0.2, 0.4) * rng.choice([-1.0, 1.0])
        u_off += _scarp_field(x, z, pts, 45.0, seed + 300 + i) * step
        forms.append(Landform("scarp", pts, 45.0, step * span))
    h = base_field(preset, seed, x, z, u_off)

    # Seamounts: one or two, rising toward the shallow limit.
    for i in range(rng.integers(1, 3)):
        c = pick_start(250.0)
        radius = rng.uniform(220.0, 420.0)
        height = rng.uniform(0.3, 0.55) * span
        h = _seamount(h, x, z, c, radius, height, seed + 400 + i)
        forms.append(Landform("seamount", c[None, :], radius, height))

    # Chasms: one main trough crossing much of the map, with one or two tributaries joining it.
    n_chasm = 1 + int(area_km2 > 3.5)
    for i in range(n_chasm):
        start = pick_start()
        pts = _random_walk(rng, preset, 7, start, rng.uniform(0, 2 * np.pi), 380.0, 0.4)
        hw = rng.uniform(90.0, 170.0)
        depth = rng.uniform(0.35, 0.6) * span
        h = _chasm(h, x, z, pts, hw, depth, seed + 500 + i)
        forms.append(Landform("chasm", pts, hw, depth))
        for j in range(rng.integers(1, 3)):
            k = rng.integers(len(pts) // 4, len(pts) - len(pts) // 4)
            heading = np.arctan2(pts[k][1] - pts[k - 1][1], pts[k][0] - pts[k - 1][0]) + rng.choice([-1, 1]) * rng.uniform(0.9, 1.6)
            tpts = _random_walk(rng, preset, 4, pts[k], heading, 260.0, 0.4)[::-1]  # runs toward the junction
            h = _chasm(h, x, z, tpts, hw * 0.5, depth * 0.55, seed + 550 + 10 * i + j, head_fade=0.3)
            forms.append(Landform("tributary", tpts, hw * 0.5, depth * 0.55))

    # Pits: a few collapse holes, some to the floor of the range.
    for i in range(rng.integers(2, 5)):
        c = pick_start(200.0)
        radius = rng.uniform(70.0, 160.0)
        depth = rng.uniform(0.18, 0.4) * span
        h = _pit(h, x, z, c, radius, depth, seed + 600 + i, rng.uniform(0.6, 1.0), rng.uniform(0, np.pi))
        forms.append(Landform("pit", c[None, :], radius, depth))

    # Keep inside the promised range: soft clamp.
    h = smax(h, np.full_like(h, preset.depth_deep), 15.0)
    h = smin(h, np.full_like(h, preset.depth_shallow), 15.0)
    log.append(f"base+landforms: {len(forms)} forms, y {h.min():.0f}..{h.max():.0f}")
    return MacroResult(h, forms, log)
