"""Seeded 2D gradient noise on numpy grids: Perlin, fBm, ridged, domain warp. Deterministic for a seed,
so the GDScript port can reproduce it (FastNoiseLite's Perlin differs in detail but not in character)."""
from __future__ import annotations
import numpy as np

_GRAD = np.array([[1, 1], [-1, 1], [1, -1], [-1, -1], [1, 0], [-1, 0], [0, 1], [0, -1]], dtype=np.float64)


def _perm(seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    p = rng.permutation(256)
    return np.concatenate([p, p])


def perlin(x: np.ndarray, y: np.ndarray, seed: int) -> np.ndarray:
    """Perlin noise in about [-1, 1] at coordinates x, y (same shape, in noise units)."""
    p = _perm(seed)
    xi = np.floor(x).astype(np.int64)
    yi = np.floor(y).astype(np.int64)
    xf = x - xi
    yf = y - yi
    xi &= 255
    yi &= 255
    u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
    v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)

    def g(ix: np.ndarray, iy: np.ndarray, dx: np.ndarray, dy: np.ndarray) -> np.ndarray:
        h = p[p[ix] + iy] & 7
        return _GRAD[h, 0] * dx + _GRAD[h, 1] * dy

    n00 = g(xi, yi, xf, yf)
    n10 = g(xi + 1, yi, xf - 1, yf)
    n01 = g(xi, yi + 1, xf, yf - 1)
    n11 = g(xi + 1, yi + 1, xf - 1, yf - 1)
    nx0 = n00 + u * (n10 - n00)
    nx1 = n01 + u * (n11 - n01)
    return (nx0 + v * (nx1 - nx0)) * 1.414


def fbm(x: np.ndarray, y: np.ndarray, seed: int, wavelength: float, octaves: int = 5, gain: float = 0.5,
        lacunarity: float = 2.0) -> np.ndarray:
    """Fractal sum of Perlin octaves, normalised to about [-1, 1]. wavelength is the first octave's period in metres."""
    out = np.zeros_like(x, dtype=np.float64)
    amp = 1.0
    freq = 1.0 / wavelength
    total = 0.0
    for o in range(octaves):
        out += amp * perlin(x * freq, y * freq, seed + o * 101)
        total += amp
        amp *= gain
        freq *= lacunarity
    return out / total


def ridged(x: np.ndarray, y: np.ndarray, seed: int, wavelength: float, octaves: int = 4, gain: float = 0.5) -> np.ndarray:
    """Ridged multifractal in [0, 1]: sharp crests, for mountain flanks and crag."""
    out = np.zeros_like(x, dtype=np.float64)
    amp = 1.0
    freq = 1.0 / wavelength
    weight = 1.0
    total = 0.0
    for o in range(octaves):
        n = 1.0 - np.abs(perlin(x * freq, y * freq, seed + o * 131))
        n = n * n * weight
        weight = np.clip(n * 2.0, 0.0, 1.0)
        out += n * amp
        total += amp
        amp *= gain
        freq *= 2.0
    return out / total


def warp(x: np.ndarray, y: np.ndarray, seed: int, wavelength: float, amount: float) -> tuple[np.ndarray, np.ndarray]:
    """Domain warp: offset the coordinates by two fBm fields, amount in metres."""
    dx = fbm(x, y, seed + 7, wavelength, octaves=3) * amount
    dy = fbm(x + 1000.0, y - 1000.0, seed + 13, wavelength, octaves=3) * amount
    return x + dx, y + dy
