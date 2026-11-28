"""Stage 2, the viability gate and placement. The terrain knows one kind of station: something with an id, a
depth band, a footprint radius and the most relief its levelled pad can absorb. The game hands over a list of
them at runtime (one entry per station, attributes filled in); what a station is (a lab, a sensor array) is
the game's business, not the terrain's. A map is viable when every station has ground and the arrangement is
spread, not clumped or with an outlier. Placement is greedy, capped farthest-point over the candidate cells,
tried from several starts."""
from __future__ import annotations
from dataclasses import dataclass, field
import json
from pathlib import Path
import numpy as np
from scipy import ndimage
from .grid import MapPreset


@dataclass(frozen=True)
class StationSpec:
    """One station's needs of the ground. The game levels a pad under it, so the gate asks for ground that can
    be padded: within footprint_m of the centre the height range stays under max_relief_m."""
    id: str
    depth_band: tuple[float, float]   # world y, (deep, shallow)
    footprint_m: float
    max_relief_m: float


def load_stations(path: str | Path) -> list[StationSpec]:
    """A JSON list of {"id", "depth_band": [deep, shallow], "footprint_m", "max_relief_m"}."""
    data = json.loads(Path(path).read_text())
    return [StationSpec(str(d["id"]), (float(d["depth_band"][0]), float(d["depth_band"][1])),
                        float(d["footprint_m"]), float(d["max_relief_m"])) for d in data]


EXAMPLE_STATIONS = Path(__file__).resolve().parent.parent / "stations_example.json"


def terrace_bands(stations: list[StationSpec], preset: MapPreset, max_levels: int = 5) -> tuple:
    """Depth bands for the base field's flats, derived from the station list so the flats land where stations
    need ground. Interval stabbing: walk the bands from deep to shallow by their shallow end, and open a new
    flat whenever a band is not yet served; each flat serves every band that contains it, and its band is the
    overlap of the bands it serves, trimmed to the middle 60%. This gives the fewest flats such that every
    station's band contains one. With no stations, three flats spread through the map's range."""
    span = (preset.depth_deep, preset.depth_shallow)
    if not stations:
        third = (span[1] - span[0]) / 3.0
        return tuple((span[0] + third * (k + 0.3), span[0] + third * (k + 0.7)) for k in range(3))
    bands = sorted({s.depth_band for s in stations}, key=lambda b: b[1])
    groups: list[list[tuple]] = []
    stab: list[float] = []
    for b in bands:
        if stab and b[0] <= stab[-1] <= b[1]:
            groups[-1].append(b)
            continue
        stab.append(b[1])
        groups.append([b])
    # A later band can also contain an earlier stab point; give each band to the first flat it contains.
    out = []
    for g in groups:
        lo = max(b[0] for b in g); hi = min(b[1] for b in g)
        mid, half = (lo + hi) / 2.0, (hi - lo) / 2.0 * 0.6
        out.append((max(mid - half, span[0]), min(mid + half, span[1])))
    if len(out) > max_levels:
        out = out[:max_levels]
    return tuple(out)


@dataclass
class Placement:
    id: str
    x: float
    z: float
    y: float
    footprint_m: float


@dataclass
class Viability:
    ok: bool
    reasons: list[str] = field(default_factory=list)
    placements: list[Placement] = field(default_factory=list)
    candidates: dict = field(default_factory=dict)   # station id -> bool mask
    metrics: dict = field(default_factory=dict)


def candidate_masks(h: np.ndarray, preset: MapPreset, stations: list[StationSpec], edge_margin_m: float = 220.0) -> dict:
    """Where each station could go. Stations with the same needs share one computation."""
    nz, nx = h.shape
    jj, ii = np.mgrid[0:nz, 0:nx]
    edge = np.minimum.reduce([ii, nx - 1 - ii, jj, nz - 1 - jj]) * preset.cell_m >= edge_margin_m
    relief_by_r: dict[int, np.ndarray] = {}
    by_need: dict[tuple, np.ndarray] = {}
    out = {}
    for s in stations:
        need = (s.depth_band, s.footprint_m, s.max_relief_m)
        if need not in by_need:
            r = max(int(round(s.footprint_m / preset.cell_m)), 1)
            if r not in relief_by_r:
                yy, xx = np.ogrid[-r:r + 1, -r:r + 1]
                disc = (xx * xx + yy * yy) <= r * r
                relief_by_r[r] = ndimage.maximum_filter(h, footprint=disc) - ndimage.minimum_filter(h, footprint=disc)
            band = (h >= s.depth_band[0]) & (h <= s.depth_band[1])
            by_need[need] = band & (relief_by_r[r] <= s.max_relief_m) & edge
        out[s.id] = by_need[need]
    return out


def place(h: np.ndarray, preset: MapPreset, stations: list[StationSpec], seed: int,
          min_separation_m: float = 350.0, max_nearest_m: float = 1100.0, min_spread: float = 0.5,
          tries: int = 12) -> Viability:
    masks = candidate_masks(h, preset, stations)
    x, z = preset.coords()
    reasons: list[str] = []
    slots: list[StationSpec] = list(stations)
    for c in stations:
        if not masks[c.id].any():
            band = (h >= c.depth_band[0]) & (h <= c.depth_band[1])
            reasons.append(f"{c.id}: no ground in {c.depth_band} within {c.max_relief_m:.0f} m relief over a {c.footprint_m:.0f} m footprint "
                           f"(in band {band.sum()} cells)")
    if reasons:
        return Viability(False, reasons, [], masks, {})
    rng = np.random.default_rng(seed)
    best: Viability | None = None
    # Hardest stations first: fewest candidate cells.
    slots.sort(key=lambda c: masks[c.id].sum())
    for t in range(tries):
        placed: list[Placement] = []
        ok = True
        for c in slots:
            cand = masks[c.id].copy()
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
            placed.append(Placement(c.id, float(x[j, i]), float(z[j, i]), float(h[j, i]), c.footprint_m))
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
