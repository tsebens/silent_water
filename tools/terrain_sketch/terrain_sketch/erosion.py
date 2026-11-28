"""Stage 1b, macro erosion on the coarse grid: flow routing, channel incision, sediment fans, talus slump
and mudflat fill. All pure functions over (nz, nx) height arrays in metres; cell is the grid spacing."""
from __future__ import annotations
import numpy as np
from scipy import ndimage
from .grid import slope_deg, smoothstep

_NEIGH = [(-1, -1, 1.4142), (-1, 0, 1.0), (-1, 1, 1.4142), (0, -1, 1.0), (0, 1, 1.0), (1, -1, 1.4142), (1, 0, 1.0), (1, 1, 1.4142)]


def flow_route(h: np.ndarray, cell: float) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """D8: each cell's receiver (flat index, or itself at a sink) and steepest slope, plus flow accumulation
    (cells drained, including itself) by visiting cells from high to low."""
    nz, nx = h.shape
    best_slope = np.zeros_like(h)
    recv = np.arange(h.size).reshape(h.shape)
    for dj, di, dist in _NEIGH:
        nb = np.roll(np.roll(h, -dj, axis=0), -di, axis=1)
        # Edges: cells whose neighbour wraps are masked out.
        valid = np.ones_like(h, dtype=bool)
        if dj == -1: valid[0, :] = False
        if dj == 1: valid[-1, :] = False
        if di == -1: valid[:, 0] = False
        if di == 1: valid[:, -1] = False
        s = np.where(valid, (h - nb) / (cell * dist), -np.inf)
        better = s > best_slope
        best_slope = np.where(better, s, best_slope)
        jj = (np.arange(nz)[:, None] + dj) * nx + (np.arange(nx)[None, :] + di)
        recv = np.where(better, jj, recv)
    acc = np.ones(h.size)
    order = np.argsort(h.ravel())[::-1]
    r = recv.ravel()
    for k in order:
        if r[k] != k:
            acc[r[k]] += acc[k]
    return recv, best_slope, acc.reshape(h.shape)


def incise(h: np.ndarray, cell: float, iterations: int, k: float, m: float = 0.5, n: float = 1.0,
           max_cut: float = 6.0) -> tuple[np.ndarray, np.ndarray]:
    """Stream-power incision: lower each cell by k * A^m * S^n per iteration, capped, never below its receiver.
    Carves a drainage network into the macro shape. Returns the new heights and the last accumulation."""
    out = h.copy()
    acc = np.ones_like(h)
    for _ in range(iterations):
        recv, s, acc = flow_route(out, cell)
        # Channels form on slopes; gentle ground keeps its flats for mudflats and pads.
        gentle = smoothstep(0.03, 0.08, s)
        # Only cells with real drainage above them cut: a gully per cell on a bare cliff reads as a comb.
        fed = smoothstep(25.0, 120.0, acc)
        cut = np.minimum(k * (acc ** m) * (np.maximum(s, 0.0) ** n), max_cut) * gentle * fed
        floor = out.ravel()[recv.ravel()].reshape(h.shape)
        new = np.maximum(out - cut, floor + 0.05)
        out = np.where(recv == np.arange(h.size).reshape(h.shape), out, new)
    return out, acc


def fans(h: np.ndarray, cell: float, acc: np.ndarray, steep_deg: float = 14.0, flat_deg: float = 5.0,
         min_acc: float = 400.0, max_fans: int = 14, height_frac: float = 0.012, radius_k: float = 6.5) -> tuple[np.ndarray, list]:
    """Sediment fans: where a well-fed channel leaves steep ground for gentle ground, pile a low cone.
    The cone's radius grows with the drainage area, its height with the drop behind it."""
    out = h.copy()
    s = slope_deg(h, cell)
    steep_up = ndimage.maximum_filter(s, size=5)
    seed_mask = (acc > min_acc) & (s < flat_deg) & (steep_up > steep_deg)
    js, iss = np.nonzero(seed_mask)
    if len(js) == 0:
        return out, []
    order = np.argsort(acc[js, iss])[::-1]
    placed: list[tuple[float, float, float]] = []
    zz, xx = np.mgrid[0:h.shape[0], 0:h.shape[1]]
    for k in order:
        j, i = js[k], iss[k]
        radius = radius_k * np.sqrt(acc[j, i]) * cell / 10.0
        if any(np.hypot(i - pi, j - pj) * cell < (radius + pr) * 0.8 for pi, pj, pr in placed):
            continue
        local_drop = steep_up[j, i]
        height = height_frac * radius * max(local_drop / steep_deg, 1.0)
        r = np.hypot((xx - i) * cell, (zz - j) * cell) / max(radius, cell)
        cone = np.clip(1.0 - r, 0.0, 1.0) ** 1.3
        out = out + height * cone
        placed.append((i, j, radius))
        if len(placed) >= max_fans:
            break
    return out, placed


def thermal(h: np.ndarray, cell: float, talus_deg: float, iterations: int, rate: float = 0.12) -> np.ndarray:
    """Slump material downhill wherever the drop to any of the 8 neighbours exceeds the talus angle.
    Mass-conserving; using diagonals as well avoids axis-aligned combs on steep faces."""
    out = h.copy()
    tan_t = np.tan(np.radians(talus_deg))
    pairs = [((0, 1), 1.0), ((1, 0), 1.0), ((1, 1), 1.4142), ((1, -1), 1.4142)]
    for _ in range(iterations):
        delta = np.zeros_like(out)
        for (dj, di), dist in pairs:
            nb = np.roll(np.roll(out, -dj, axis=0), -di, axis=1)
            d = out - nb
            excess = np.abs(d) - tan_t * cell * dist
            moved = np.where(excess > 0, excess * rate * 0.5 * np.sign(d), 0.0)
            # Drop pairs that wrapped round an edge.
            if dj: moved[-dj:, :] = 0.0
            if di > 0: moved[:, -di:] = 0.0
            if di < 0: moved[:, :-di] = 0.0
            delta -= moved
            delta += np.roll(np.roll(moved, dj, axis=0), di, axis=1)
        out = out + delta
    return out


def mudflat_fill(h: np.ndarray, cell: float, flat_deg: float = 3.5, iterations: int = 18, strength: float = 0.65,
                 basin_sigma: float = 4.0) -> np.ndarray:
    """Sediment settles on gentle low ground: relax flat cells toward a smoothed local level, strongest in
    basins, leaving slopes alone. Produces mudflats and plains between the landforms.
    The weight is computed once, from the slope of smoothed ground and then smoothed itself: a per-cell
    threshold recomputed each pass feeds on itself (a filled cell gets flatter and fills more) and breaks
    the foot of every cliff into teeth."""
    out = h.copy()
    s = slope_deg(ndimage.gaussian_filter(h, 1.5), cell)
    w = (1.0 - smoothstep(flat_deg * 0.5, flat_deg * 2.5, s)) * strength
    w = ndimage.gaussian_filter(w, 2.0)
    for _ in range(iterations):
        local = ndimage.gaussian_filter(out, basin_sigma)
        # Fill upward more readily than shave: sediment comes from above.
        target = np.where(local > out, local, out + (local - out) * 0.35)
        out = out + (target - out) * w
    return out


def sediment_route(h: np.ndarray, cell: float, iterations: int, kc: float, erode: float = 0.25,
                   deposit: float = 0.35, max_cut: float = 4.0, sed: np.ndarray | None = None,
                   steep_deg: float = 22.0, spread: float = 1.5) -> tuple[np.ndarray, np.ndarray]:
    """Transport-limited fluvial erosion and deposition along the flow graph. Each pass routes sediment from
    high to low: a cell's carrying capacity is kc * A^0.5 * S; below capacity the flow picks up material,
    above it the flow drops some. Where a channel leaves steep ground the capacity falls and sediment drops,
    which raises the cell and pushes the next pass's flow sideways: fans build by avulsion. Sinks keep all
    they receive, so pits and closed basins fill with flat sediment. Returns heights and deposit thickness."""
    out = h.copy()
    thick = np.zeros_like(h) if sed is None else sed.copy()
    n = h.size
    for _ in range(iterations):
        recv, slope, acc = flow_route(out, cell)
        r = recv.ravel().tolist()
        cap = (kc * np.sqrt(acc) * np.maximum(slope, 0.0)).ravel().tolist()
        hf = out.ravel()
        order = np.argsort(hf)[::-1].tolist()
        qs = [0.0] * n
        dh = [0.0] * n
        hl = hf.tolist()
        steep = (slope > np.tan(np.radians(steep_deg))).ravel().tolist()
        for k in order:
            q = qs[k]
            rk = r[k]
            if rk == k:                       # sink: everything settles here
                dh[k] += q
                continue
            c = cap[k]
            if q > c and steep[k]:
                qs[rk] += q                   # no resting place on a cliff: carry on down
                continue
            if q > c:
                d = (q - c) * deposit
                dh[k] += d
                q -= d
            else:
                e = min((c - q) * erode, max_cut, max(hl[k] - hl[rk] - 0.05, 0.0) * 0.5)
                dh[k] -= e
                q += e
            qs[rk] += q
        dh = np.array(dh).reshape(h.shape)
        # Deposits spread over neighbouring cells rather than stacking on the one where the flow slowed.
        dep = ndimage.gaussian_filter(np.maximum(dh, 0.0), spread)
        dh = np.minimum(dh, 0.0) + dep
        out = out + dh
        thick = np.maximum(thick + dh, 0.0)
    return out, thick


def pond(h: np.ndarray, cell: float, leave_m: float = 2.0, max_fill_m: float = 25.0, iterations: int = 400,
         fill_frac: float = 0.3, min_cells: int = 12) -> tuple[np.ndarray, np.ndarray]:
    """Fill closed depressions toward their spill level with flat sediment, leaving a shallow hollow, so pit
    floors, chasm pools and low basins become mudflats. The spill surface is found by morphological
    reconstruction by erosion from the map edge."""
    big = h.max() + 1.0
    filled = np.full_like(h, big)
    filled[0, :] = h[0, :]; filled[-1, :] = h[-1, :]; filled[:, 0] = h[:, 0]; filled[:, -1] = h[:, -1]
    for _ in range(iterations):
        nxt = np.maximum(h, ndimage.grey_erosion(filled, size=(3, 3)))
        if np.array_equal(nxt, filled):
            break
        filled = nxt
    depth = filled - h
    basins, nb = ndimage.label(depth > leave_m)
    if nb == 0:
        return h.copy(), np.zeros_like(h)
    idx = np.arange(1, nb + 1)
    bottom = np.array(ndimage.minimum(h, basins, idx))
    spill = np.array(ndimage.maximum(filled, basins, idx))
    size = np.array(ndimage.sum(np.ones_like(h), basins, idx))
    # Each basin's floor rises a fraction of its depth, capped, to a flat level: a mudflat with the basin's
    # walls still standing above it. Tiny basins (noise hollows) are left alone.
    level = bottom + np.minimum((spill - bottom) * fill_frac, max_fill_m)
    level = np.where(size >= min_cells, level, -np.inf)
    lut = np.concatenate([[-np.inf], level])
    floor = lut[basins]
    fill = np.maximum(floor - h, 0.0)
    return h + fill, fill


def fans_directional(h: np.ndarray, cell: float, acc: np.ndarray, steep_deg: float = 16.0, flat_deg: float = 7.0,
                     min_acc: float = 150.0, max_fans: int = 18, apex_frac: float = 0.045, radius_k: float = 9.0,
                     spread_deg: float = 55.0, seed: int = 0) -> tuple[np.ndarray, np.ndarray, list]:
    """Sediment fans at channel mouths. Where a channel with real drainage leaves steep ground for gentle
    ground, build a fan: apex at the mouth, opening downslope over +/- spread_deg, thickest at the apex and
    thinning to nothing at the rim, with faint distributary ribs. Radius grows with the square root of the
    drainage area. Returns heights, deposit thickness, and the fans (i, j, radius)."""
    from . import noise
    rng = np.random.default_rng(seed)
    sm = ndimage.gaussian_filter(h, 2.0)
    s = slope_deg(sm, cell)
    steep_up = ndimage.maximum_filter(s, size=7)
    seed_mask = (acc > min_acc) & (s < flat_deg) & (steep_up > steep_deg)
    js, iss = np.nonzero(seed_mask)
    dep = np.zeros_like(h)
    placed: list[tuple[int, int, float]] = []
    if len(js) == 0:
        return h.copy(), dep, placed
    gz, gx = np.gradient(sm, cell)
    zz, xx = np.mgrid[0:h.shape[0], 0:h.shape[1]]
    order = np.argsort(acc[js, iss])[::-1]
    for k in order:
        j, i = int(js[k]), int(iss[k])
        radius = radius_k * np.sqrt(acc[j, i]) * cell / 10.0
        radius = float(np.clip(radius, 80.0, 420.0))
        if any(np.hypot(i - pi, j - pj) * cell < (radius + pr) * 0.55 for pi, pj, pr in placed):
            continue
        # Downslope direction at the mouth, from the smoothed gradient averaged over a few cells.
        sl = (slice(max(j - 3, 0), j + 4), slice(max(i - 3, 0), i + 4))
        dx, dz = -gx[sl].mean(), -gz[sl].mean()
        if np.hypot(dx, dz) < 1e-6:
            continue
        ang = np.arctan2(dz, dx)
        rx, rz = (xx - i) * cell, (zz - j) * cell
        r = np.hypot(rx, rz) / radius
        theta = np.angle(np.exp(1j * (np.arctan2(rz, rx) - ang)))
        sector = 1.0 - smoothstep(np.radians(spread_deg) * 0.6, np.radians(spread_deg), np.abs(theta))
        body = np.clip(1.0 - r, 0.0, 1.0) ** 1.6
        ribs = 1.0 + 0.25 * np.cos(theta * rng.uniform(7.0, 11.0) + noise.fbm(xx * 1.0, zz * 1.0, seed + k, wavelength=12.0, octaves=2) * 2.0)
        thick = apex_frac * radius * body * sector * ribs
        # Fans rest on the ground: no deposit where the ground rises above the apex (the fan wraps obstacles).
        thick = np.where(h > h[j, i] + 2.0, 0.0, thick)
        dep = np.maximum(dep, thick)
        placed.append((i, j, radius))
        if len(placed) >= max_fans:
            break
    return h + dep, dep, placed


def run_macro_erosion(h: np.ndarray, cell: float, log: list[str]) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Macro erosion. Returns heights, the last flow accumulation, and sediment thickness (for rendering now,
    and later for choosing sediment or rock materials)."""
    out, acc = incise(h, cell, iterations=6, k=0.018)
    log.append(f"incise: max cut {np.max(h - out):.1f} m, max acc {acc.max():.0f} cells")
    out = thermal(out, cell, talus_deg=38.0, iterations=4)
    before = out.copy()
    out, sed = sediment_route(out, cell, iterations=10, kc=0.25)
    log.append(f"sediment: moved {np.abs(out - before).sum() * cell * cell / 1e6:.2f} M m3, max deposit {sed.max():.1f} m")
    _, _, acc_now = flow_route(out, cell)
    out, fan_dep, fan_list = fans_directional(out, cell, acc_now)
    sed = sed + fan_dep
    log.append(f"fans: {len(fan_list)}, max apex {fan_dep.max():.1f} m")
    out, ponded = pond(out, cell)
    sed = sed + ponded
    log.append(f"ponds: {(ponded > 0).sum()} cells filled, max {ponded.max():.1f} m")
    out = mudflat_fill(out, cell)
    out = thermal(out, cell, talus_deg=40.0, iterations=2)
    sed = np.maximum(sed + (out - before) * 0.0, sed)
    _, _, acc = flow_route(out, cell)
    return out, acc, sed
