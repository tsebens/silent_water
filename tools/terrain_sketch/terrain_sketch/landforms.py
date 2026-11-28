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
    # The rise between levels is a cliff in one place and a long ramp in another: its width varies in space.
    wvar = noise.fbm(x, z, seed + 3, wavelength=700.0, octaves=3) * 0.5 + 0.5
    width = 0.015 + 0.09 * wvar ** 1.5
    # Each rim wanders on its own, so a step does not follow one contour of the field.
    s0 = steps[0] + noise.fbm(x, z, seed + 4, wavelength=500.0, octaves=3) * 0.05
    s1 = steps[1] + noise.fbm(x, z, seed + 5, wavelength=500.0, octaves=3) * 0.05
    t = levels[0] + (levels[1] - levels[0]) * smoothstep(0.0, 1.0, (u - s0 + width) / (2 * width)) \
        + (levels[2] - levels[1]) * smoothstep(0.0, 1.0, (u - s1 + width) / (2 * width))
    # Relief within a level: broad swales and low rises (about 15 m on the plain, 30 m on the shelf),
    # with a medium-scale ridged texture on higher ground so the shelf reads as worn rock, the plain as sediment.
    swale = noise.fbm(wx, wz, seed + 6, wavelength=450.0, octaves=4, gain=0.55)
    rough = noise.ridged(wx, wz, seed + 8, wavelength=220.0, octaves=3) - 0.35
    t = t + swale * (0.025 + 0.03 * t) + rough * 0.03 * t * t
    tilt_dir = rng.uniform(0.0, 2 * np.pi)
    tilt = (x * np.cos(tilt_dir) + z * np.sin(tilt_dir)) / max(preset.width_m, preset.length_m)
    t = np.clip(t + tilt * rng.uniform(0.04, 0.12), 0.0, 1.0)
    return preset.depth_deep + t * (preset.depth_shallow - preset.depth_deep)


def _chasm(h: np.ndarray, x: np.ndarray, z: np.ndarray, pts: np.ndarray, half_width: float, depth: float,
           seed: int, head_fade: float = 0.15) -> np.ndarray:
    """A trough along a spline. The edge is warped so it never runs parallel to the centreline; the width swells
    and pinches along its length; one wall is a cliff and the other a steep ramp, swapping sides along it; the
    floor undulates, with deeper pools."""
    wx, wz = noise.warp(x, z, seed + 1, wavelength=260.0, amount=55.0)
    d, t, side = polyline_distance(wx, wz, pts)
    along = smoothstep(0.0, head_fade, t) * (1.0 - smoothstep(0.88, 1.0, t))
    swell = 1.0 + 0.45 * noise.fbm(t * 9.0, np.zeros_like(t) + 3.7, seed + 2, wavelength=1.0, octaves=2)
    w = half_width * (0.5 + 0.5 * t) * swell
    # Asymmetry: which side is the cliff flips slowly along the chasm.
    which = noise.fbm(t * 4.0, np.zeros_like(t) + 9.1, seed + 3, wavelength=1.0, octaves=1)
    cliff_side = np.sign(which) * side
    sharp = np.where(cliff_side > 0, 2.6, 0.9)
    r = np.clip(d / np.maximum(w, 1.0), 0.0, 1.5)
    profile = (1.0 - smoothstep(0.35, 1.0, r)) ** (1.0 / sharp)
    floor_var = 1.0 + 0.18 * noise.fbm(x, z, seed + 4, wavelength=160.0, octaves=3)
    depth_here = depth * (0.5 + 0.5 * t) * along * floor_var
    return smin(h, h - depth_here * profile, 10.0)


def _pit(h: np.ndarray, x: np.ndarray, z: np.ndarray, c: np.ndarray, radius: float, depth: float, seed: int,
         ellipse: float, angle: float) -> np.ndarray:
    """A collapse pit: two or three overlapping lobes on warped coordinates, so the rim is scalloped, with a
    ledge part way down on some."""
    rng = np.random.default_rng(seed)
    wx, wz = noise.warp(x, z, seed + 1, wavelength=140.0, amount=0.35 * radius)
    r = np.full(x.shape, np.inf)
    for k in range(rng.integers(2, 4)):
        off = rng.normal(0.0, 0.45 * radius, size=2) if k else np.zeros(2)
        rad = radius * (rng.uniform(0.55, 0.85) if k else 1.0)
        a = angle + rng.normal(0.0, 0.6)
        dx, dz = wx - (c[0] + off[0]), wz - (c[1] + off[1])
        ex = dx * np.cos(a) + dz * np.sin(a)
        ez = -dx * np.sin(a) + dz * np.cos(a)
        r = np.minimum(r, np.hypot(ex / rad, ez / (rad * ellipse)))
    profile = 1.0 - smoothstep(0.62, 1.0, r)
    if rng.random() < 0.5:
        # A ledge at about a third of the depth: material that slumped and stuck.
        profile = np.maximum(profile * 0.35, 1.0 - smoothstep(0.35, 0.75, r))
    return smin(h, h - depth * profile, 8.0)


def _seamount(h: np.ndarray, x: np.ndarray, z: np.ndarray, c: np.ndarray, radius: float, height: float,
              seed: int) -> np.ndarray:
    """A mountain: an elongated cone on warped coordinates, ridged flanks with spurs, and a flat or cratered top."""
    rng = np.random.default_rng(seed)
    wx, wz = noise.warp(x, z, seed + 1, wavelength=300.0, amount=0.25 * radius)
    a = rng.uniform(0, np.pi)
    stretch = rng.uniform(1.0, 1.8)
    dx, dz = wx - c[0], wz - c[1]
    ex = dx * np.cos(a) + dz * np.sin(a)
    ez = -dx * np.sin(a) + dz * np.cos(a)
    r = np.hypot(ex / (radius * stretch), ez / radius)
    cone = np.clip(1.0 - r, 0.0, 1.0) ** 1.2
    ridge = noise.ridged(wx, wz, seed + 5, wavelength=150.0, octaves=4)
    shape = cone * (0.65 + 0.6 * ridge * (0.4 + 0.6 * cone))
    top = rng.uniform(0.72, 0.9)
    shape = np.minimum(shape, top + (shape - top) * 0.15)          # summit plateau
    if rng.random() < 0.35:
        shape = shape - 0.12 * (1.0 - smoothstep(0.0, 0.18, r))    # a summit crater
    return smax(h, h + height * shape, 10.0)


def _scarp_field(x: np.ndarray, z: np.ndarray, pts: np.ndarray, blend: float, seed: int) -> np.ndarray:
    """A fault line's influence, 0..1: 1 on the left of travel across a narrow blend, fading at both ends. Added
    to the base noise before the staircase, it lifts or drops a whole block by part of a level, so the fault
    reads as the cliff between two flats."""
    wx, wz = noise.warp(x, z, seed + 1, wavelength=350.0, amount=90.0)
    d, t, side = polyline_distance(wx, wz, pts)
    ends = smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.88, 1.0, t))
    wob = noise.fbm(x, z, seed, wavelength=150.0, octaves=3) * blend * 1.5
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
        radius = rng.uniform(260.0, 460.0)
        height = rng.uniform(0.45, 0.7) * span
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
