"""Stage 3, the slow detail pass, run only on a map that passed the gate: upsample the macro grid to a fine
cell, classify ground as rock or sediment, add detail by material, slump it, scatter boulders, and level the
station pads into the result. Everything is seeded from the map seed."""
from __future__ import annotations
from dataclasses import dataclass, field
import time
import numpy as np
from scipy import ndimage
from . import noise
from .grid import MapPreset, smoothstep, slope_deg
from .erosion import thermal
from .stations import Placement, StationClass, DEFAULT_STATIONS


@dataclass
class DetailParams:
    factor: int = 5                    # fine cells per macro cell: 10 m -> 2 m
    rock_slope: tuple = (24.0, 38.0)   # slope (deg) over which ground turns from sediment to rock
    crag_amp: float = 7.0              # ridged crag relief on rock (m)
    crag_wavelength: float = 55.0
    strata_height: float = 10.0        # band height on cliffs (m)
    strata_strength: float = 0.5
    rugosity_amp: float = 2.5          # general unevenness everywhere (m), halved on sediment
    ripple_amp: float = 0.8            # sand waves on flat sediment (m)
    ripple_wavelength: float = 22.0
    scree_amp: float = 1.6             # lumpy talus below cliffs (m)
    talus_deg: float = 42.0            # fine slump angle
    boulders_per_km2: float = 260.0
    pad_falloff: float = 1.6           # pad blend reaches natural ground at this multiple of the footprint radius


@dataclass
class Boulder:
    x: float
    z: float
    y: float
    size: float


@dataclass
class PadReport:
    name: str
    y: float
    cut_m3: float
    fill_m3: float
    max_cut: float
    max_fill: float


@dataclass
class DetailResult:
    h: np.ndarray
    rock: np.ndarray                   # 0..1 rock weight per fine cell (sediment is 1 - rock)
    sediment: np.ndarray               # sediment thickness per fine cell (m)
    cell: float
    boulders: list[Boulder] = field(default_factory=list)
    pads: list[PadReport] = field(default_factory=list)
    timings: dict = field(default_factory=dict)


def fine_coords(preset: MapPreset, factor: int) -> tuple[np.ndarray, np.ndarray, float]:
    cell = preset.cell_m / factor
    nx = (preset.nx - 1) * factor + 1
    nz = (preset.nz - 1) * factor + 1
    xs = np.linspace(-preset.width_m / 2, preset.width_m / 2, nx)
    zs = np.linspace(-preset.length_m / 2, preset.length_m / 2, nz)
    x, z = np.meshgrid(xs, zs)
    return x, z, cell


def upsample(a: np.ndarray, factor: int, order: int) -> np.ndarray:
    nz, nx = a.shape
    jj = np.arange((nz - 1) * factor + 1) / factor
    ii = np.arange((nx - 1) * factor + 1) / factor
    J, I = np.meshgrid(jj, ii, indexing="ij")
    return ndimage.map_coordinates(a, [J, I], order=order, mode="nearest")


def run_detail(macro_h: np.ndarray, sediment: np.ndarray, preset: MapPreset, seed: int,
               placements: list[Placement], classes: list[StationClass] = DEFAULT_STATIONS,
               p: DetailParams = DetailParams()) -> DetailResult:
    tm: dict = {}
    t = time.perf_counter()
    x, z, cell = fine_coords(preset, p.factor)
    h = upsample(macro_h, p.factor, order=3)
    sed = np.maximum(upsample(sediment, p.factor, order=1), 0.0)
    tm["upsample"] = time.perf_counter() - t

    # Materials: steep ground is rock unless sediment is piled on it; thick sediment is never rock.
    t = time.perf_counter()
    s = slope_deg(ndimage.gaussian_filter(h, 1.0), cell)
    rock = smoothstep(p.rock_slope[0], p.rock_slope[1], s) * (1.0 - smoothstep(1.0, 4.0, sed))
    rock = ndimage.gaussian_filter(rock, 1.5)
    soft = 1.0 - rock
    flat_sed = soft * (1.0 - smoothstep(4.0, 9.0, s))
    # Below a cliff: within about 40 m downhill of rock, on moderate slopes.
    near_rock = ndimage.maximum_filter(rock, size=int(40 / cell)) > 0.5
    scree = near_rock * (1.0 - rock) * smoothstep(8.0, 18.0, s) * (1.0 - smoothstep(30.0, 40.0, s))
    tm["materials"] = time.perf_counter() - t

    t = time.perf_counter()
    wx, wz = noise.warp(x, z, seed + 901, wavelength=120.0, amount=18.0)
    # Rock: crags, then strata ledges on cliffs (height quantised into bands, each band nudged by noise).
    crag = (noise.ridged(wx, wz, seed + 902, wavelength=p.crag_wavelength, octaves=4) - 0.35) * p.crag_amp
    h = h + crag * rock
    # Band thickness varies across the map and the bands warp, so ledges are not a regular fingerprint.
    thick = p.strata_height * (1.0 + 0.45 * noise.fbm(x, z, seed + 909, wavelength=400.0, octaves=2))
    q = (h + noise.fbm(wx, wz, seed + 910, wavelength=150.0, octaves=3) * p.strata_height * 0.8) / thick
    band = np.floor(q)
    f = smoothstep(0.25, 0.75, q - band)
    off = noise.fbm(x, band * 37.0 + z * 0.0, seed + 903, wavelength=60.0, octaves=2) * 1.5
    strata = (band + f) * thick - noise.fbm(wx, wz, seed + 910, wavelength=150.0, octaves=3) * p.strata_height * 0.8 + off
    cliff = rock * smoothstep(28.0, 45.0, s)
    h = h + (strata - h) * p.strata_strength * cliff
    # Everywhere: rugosity from 70 m down to about 6 m (gain 0.6 keeps the small scales visible), half as
    # strong on sediment; and a fine rock texture (blocky ridged noise at 18 m) on rock only.
    rug = noise.fbm(wx, wz, seed + 904, wavelength=70.0, octaves=5, gain=0.6) * p.rugosity_amp * (0.45 + 0.55 * rock)
    blocks = (noise.ridged(x, z, seed + 908, wavelength=18.0, octaves=2) - 0.4) * 1.8
    h = h + rug + blocks * rock
    # Scree: lumpy talus below cliffs.
    lump = noise.fbm(x, z, seed + 905, wavelength=9.0, octaves=2) * p.scree_amp
    h = h + lump * scree
    # Sediment: sand waves on flats, crests across a seeded current direction, phase warped so they branch.
    rng = np.random.default_rng(seed + 906)
    ang = rng.uniform(0, np.pi)
    phase = (x * np.cos(ang) + z * np.sin(ang)) / p.ripple_wavelength * 2 * np.pi
    phase = phase + noise.fbm(x, z, seed + 907, wavelength=90.0, octaves=3) * 4.0
    ripple = (np.abs(np.sin(phase * 0.5)) - 0.6) * 2.0 * p.ripple_amp
    # Sand waves on all gentle soft ground, strongest on fresh deposits.
    h = h + ripple * flat_sed * (0.55 + 0.45 * smoothstep(0.3, 2.0, sed))
    tm["detail"] = time.perf_counter() - t

    t = time.perf_counter()
    h = thermal(h, cell, talus_deg=p.talus_deg, iterations=3, rate=0.2)
    tm["slump"] = time.perf_counter() - t

    # Boulders: below cliffs and on rock, denser on scree.
    t = time.perf_counter()
    area_km2 = preset.width_m * preset.length_m / 1e6
    n_try = int(p.boulders_per_km2 * area_km2 * 4)
    js = rng.integers(0, h.shape[0], n_try)
    iss = rng.integers(0, h.shape[1], n_try)
    weight = np.clip(scree[js, iss] * 1.0 + rock[js, iss] * 0.25, 0.0, 1.0)
    keep = rng.random(n_try) < weight
    boulders: list[Boulder] = []
    for j, i in zip(js[keep], iss[keep]):
        size = float(rng.lognormal(np.log(2.5), 0.45))
        boulders.append(Boulder(float(x[j, i]), float(z[j, i]), float(h[j, i]), size))
        if len(boulders) >= int(p.boulders_per_km2 * area_km2):
            break
    tm["boulders"] = time.perf_counter() - t

    # Station pads: level each footprint to the median ground inside it, blending to natural ground.
    t = time.perf_counter()
    radius = {c.name: c.footprint_m for c in classes}
    pads: list[PadReport] = []
    for pl in placements:
        r = radius.get(pl.name, 20.0)
        d = np.hypot(x - pl.x, z - pl.z)
        inside = d <= r
        if not inside.any():
            continue
        y = float(np.median(h[inside]))
        w = 1.0 - smoothstep(r, r * p.pad_falloff, d)
        new = h + (y - h) * w
        delta = new - h
        a = cell * cell
        pads.append(PadReport(pl.name, y, float(-delta[delta < 0].sum() * a), float(delta[delta > 0].sum() * a),
                              float(max(-delta.min(), 0.0)), float(max(delta.max(), 0.0))))
        h = new
        rock = rock * (1.0 - w)                 # a levelled pad is graded sediment
    tm["pads"] = time.perf_counter() - t
    return DetailResult(h, rock, sed, cell, boulders, pads, tm)
