"""Stage 2, the viability gate and placement: every station class has a depth band, a footprint and a slope
limit; a map is viable when each station has somewhere to go and the arrangement is spread, not clumped or
with an outlier. Placement is greedy farthest-point over the candidate cells, tried from several starts."""
from __future__ import annotations
from dataclasses import dataclass, field
import numpy as np
from scipy import ndimage
from .grid import MapPreset, slope_deg


@dataclass
class StationClass:
    """A station's needs of the ground. The game levels a pad under a station (FlatPad), so the gate asks for
    ground that can be padded: within the footprint the height range stays under max_relief_m."""
    name: str
    depth_band: tuple[float, float]   # world y, (deep, shallow)
    footprint_m: float                # radius the ground must suit
    max_relief_m: float               # highest minus lowest ground inside the footprint
    count: int = 1


DEFAULT_STATIONS: list[StationClass] = [
    StationClass("research_station", (-320.0, -200.0), 60.0, 16.0),
    StationClass("outpost", (-160.0, -80.0), 30.0, 8.0),
    StationClass("lab", (-240.0, -120.0), 35.0, 9.0),
    StationClass("sensor_array", (-520.0, -340.0), 20.0, 8.0, count=3),
    StationClass("relay", (-110.0, -60.0), 12.0, 5.0),
    StationClass("vent_field", (-650.0, -500.0), 30.0, 25.0),
]


@dataclass
class Placement:
    name: str
    x: float
    z: float
    y: float


@dataclass
class Viability:
    ok: bool
    reasons: list[str] = field(default_factory=list)
    placements: list[Placement] = field(default_factory=list)
    candidates: dict = field(default_factory=dict)   # class name -> bool mask
    metrics: dict = field(default_factory=dict)


def candidate_masks(h: np.ndarray, preset: MapPreset, classes: list[StationClass], edge_margin_m: float = 220.0) -> dict:
    nz, nx = h.shape
    jj, ii = np.mgrid[0:nz, 0:nx]
    edge = np.minimum.reduce([ii, nx - 1 - ii, jj, nz - 1 - jj]) * preset.cell_m >= edge_margin_m
    out = {}
    for c in classes:
        r = max(int(round(c.footprint_m / preset.cell_m)), 1)
        yy, xx = np.ogrid[-r:r + 1, -r:r + 1]
        disc = (xx * xx + yy * yy) <= r * r
        relief = ndimage.maximum_filter(h, footprint=disc) - ndimage.minimum_filter(h, footprint=disc)
        band = (h >= c.depth_band[0]) & (h <= c.depth_band[1])
        out[c.name] = band & (relief <= c.max_relief_m) & edge
    return out


def place(h: np.ndarray, preset: MapPreset, classes: list[StationClass], seed: int,
          min_separation_m: float = 350.0, max_nearest_m: float = 1100.0, min_spread: float = 0.5,
          tries: int = 12) -> Viability:
    masks = candidate_masks(h, preset, classes)
    x, z = preset.coords()
    reasons: list[str] = []
    slots: list[StationClass] = []
    for c in classes:
        if not masks[c.name].any():
            band = (h >= c.depth_band[0]) & (h <= c.depth_band[1])
            reasons.append(f"{c.name}: no ground in {c.depth_band} within {c.max_relief_m:.0f} m relief over a {c.footprint_m:.0f} m footprint "
                           f"(in band {band.sum()} cells)")
        slots.extend([c] * c.count)
    if reasons:
        return Viability(False, reasons, [], masks, {})
    rng = np.random.default_rng(seed)
    best: Viability | None = None
    # Hardest classes first: fewest candidate cells.
    slots.sort(key=lambda c: masks[c.name].sum())
    for t in range(tries):
        placed: list[Placement] = []
        ok = True
        for c in slots:
            cand = masks[c.name].copy()
            for p in placed:
                cand &= np.hypot(x - p.x, z - p.z) >= min_separation_m
            js, iss = np.nonzero(cand)
            if len(js) == 0:
                ok = False
                break
            if placed:
                # Farthest-point: prefer cells far from everything placed so far, with some randomness.
                dmin = np.min([np.hypot(x[js, iss] - p.x, z[js, iss] - p.z) for p in placed], axis=0)
                # Farthest-point alone drives every station to the margins: cap the reward for distance at the
                # spacing we want, then prefer the interior among cells far enough away.
                spacing = np.minimum(dmin, max_nearest_m * 0.75)
                edge = np.minimum(preset.width_m / 2 - np.abs(x[js, iss]), preset.length_m / 2 - np.abs(z[js, iss]))
                interior = 0.55 + 0.45 * np.clip(edge / 500.0, 0.0, 1.0)
                score = spacing * interior * rng.uniform(0.85, 1.0, size=dmin.shape)
                k = int(np.argmax(score))
            else:
                # First station: anywhere, weighted toward the interior.
                edge = np.minimum(preset.width_m / 2 - np.abs(x[js, iss]), preset.length_m / 2 - np.abs(z[js, iss]))
                k = int(np.argmax(np.clip(edge / 500.0, 0.0, 1.0) * rng.uniform(0.0, 1.0, size=len(js))))
            j, i = js[k], iss[k]
            placed.append(Placement(c.name, float(x[j, i]), float(z[j, i]), float(h[j, i])))
        if not ok:
            continue
        px = np.array([p.x for p in placed]); pz = np.array([p.z for p in placed])
        spread_x = (px.max() - px.min()) / preset.width_m
        spread_z = (pz.max() - pz.min()) / preset.length_m
        d = np.hypot(px[:, None] - px[None, :], pz[:, None] - pz[None, :]) + np.eye(len(px)) * 1e9
        nearest = d.min(axis=1)
        metrics = {"spread_x": spread_x, "spread_z": spread_z, "min_pair": float(d.min()), "max_nearest": float(nearest.max())}
        v = Viability(True, [], placed, masks, metrics)
        good = spread_x >= min_spread and spread_z >= min_spread and nearest.max() <= max_nearest_m
        if good:
            return v
        if best is None or (metrics["spread_x"] + metrics["spread_z"]) > (best.metrics["spread_x"] + best.metrics["spread_z"]):
            best = v
    if best is None:
        return Viability(False, ["no arrangement keeps every station apart"], [], masks, {})
    best.ok = False
    m = best.metrics
    best.reasons.append(f"lopsided: spread {m['spread_x']:.2f} x {m['spread_z']:.2f} of the map, farthest nearest-neighbour {m['max_nearest']:.0f} m")
    return best
