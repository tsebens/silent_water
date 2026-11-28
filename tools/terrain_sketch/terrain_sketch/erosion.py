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


def run_macro_erosion(h: np.ndarray, cell: float, log: list[str]) -> tuple[np.ndarray, np.ndarray, list]:
    out, acc = incise(h, cell, iterations=8, k=0.018)
    log.append(f"incise: max cut {np.max(h - out):.1f} m, max acc {acc.max():.0f} cells")
    out = thermal(out, cell, talus_deg=38.0, iterations=4)
    out, fan_list = fans(out, cell, acc)
    log.append(f"fans: {len(fan_list)}")
    out = mudflat_fill(out, cell)
    out = thermal(out, cell, talus_deg=40.0, iterations=2)
    return out, acc, fan_list
