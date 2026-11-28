"""The macro grid and small helpers shared by the stages."""
from __future__ import annotations
from dataclasses import dataclass
import numpy as np


@dataclass
class MapPreset:
    """What a map promises before any generation: its size and the depth range its ground spans."""
    width_m: float = 1700.0           # x extent; the golden-ratio short side of about 4.6 km²
    length_m: float = 2750.0          # z extent
    cell_m: float = 10.0              # macro grid spacing
    depth_shallow: float = -60.0      # the highest ground (world y)
    depth_deep: float = -650.0        # the lowest ground (world y)
    # Depth bands (deep, shallow) the three base levels are drawn from: deep plain, mid terrace, shallow shelf.
    # They follow the station classes, so the flats land where stations need ground.
    terrace_bands: tuple = ((-520.0, -400.0), (-320.0, -210.0), (-160.0, -90.0))

    @property
    def nx(self) -> int:
        return int(round(self.width_m / self.cell_m)) + 1

    @property
    def nz(self) -> int:
        return int(round(self.length_m / self.cell_m)) + 1

    def coords(self) -> tuple[np.ndarray, np.ndarray]:
        """World x and z of every cell, centred on the origin; shape (nz, nx)."""
        xs = np.linspace(-self.width_m / 2, self.width_m / 2, self.nx)
        zs = np.linspace(-self.length_m / 2, self.length_m / 2, self.nz)
        return np.meshgrid(xs, zs)


def smin(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    """Polynomial smooth minimum with blend radius k (the same form CanyonSite uses)."""
    t = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b + (a - b) * t - k * t * (1.0 - t)


def smax(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    return -smin(-a, -b, k)


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def slope_deg(h: np.ndarray, cell: float) -> np.ndarray:
    gz, gx = np.gradient(h, cell)
    return np.degrees(np.arctan(np.hypot(gx, gz)))


def polyline_distance(x: np.ndarray, z: np.ndarray, pts: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Distance from every cell to a polyline, the parameter 0..1 along it at the nearest point, and the signed
    side (+1 left of travel). pts is (n, 2) in world x, z."""
    best = np.full(x.shape, np.inf)
    best_t = np.zeros(x.shape)
    best_side = np.zeros(x.shape)
    seg_len = np.hypot(np.diff(pts[:, 0]), np.diff(pts[:, 1]))
    cum = np.concatenate([[0.0], np.cumsum(seg_len)])
    total = cum[-1] if cum[-1] > 0 else 1.0
    for i in range(len(pts) - 1):
        ax, az = pts[i]
        bx, bz = pts[i + 1]
        dx, dz = bx - ax, bz - az
        ll = dx * dx + dz * dz
        if ll == 0:
            continue
        u = np.clip(((x - ax) * dx + (z - az) * dz) / ll, 0.0, 1.0)
        px, pz = ax + u * dx, az + u * dz
        d = np.hypot(x - px, z - pz)
        closer = d < best
        side = np.sign(dx * (z - az) - dz * (x - ax))
        best = np.where(closer, d, best)
        best_t = np.where(closer, (cum[i] + u * seg_len[i]) / total, best_t)
        best_side = np.where(closer, side, best_side)
    return best, best_t, best_side
