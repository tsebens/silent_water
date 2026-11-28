"""Exploratory, no commitment (#952): overhangs and caves as a 3D density patch on a cliff. A heightfield holds
one height per column, so it cannot hold rock above water. Here a patch of voxels starts as the heightfield
(density = ground height minus y, solid where positive), gets 3D noise near steep rock so the face bulges and
recedes into overhangs, and one tunnel is bored into the face as a cave. The perturbation fades to nothing at
the patch's sides, so the patch meets the surrounding heightfield exactly."""
from __future__ import annotations
from dataclasses import dataclass
import numpy as np
from scipy import ndimage
from . import noise
from .grid import smoothstep


@dataclass
class CavePatch:
    density: np.ndarray        # (ny, nz, nx): positive is rock
    y0: float                  # world y of layer 0
    cell: float
    origin: tuple              # world x, z of column (0, 0)
    surface: np.ndarray        # (nz, nx) the heightfield under the patch
    tunnel_row: int            # z row the tunnel starts on, for a slice through it
    overhang_cols: float       # share of columns with water under rock
    cave_m3: float             # water volume below the heightfield (overhangs and the cave)


def noise3(x: np.ndarray, y: np.ndarray, z: np.ndarray, seed: int, wavelength: float) -> np.ndarray:
    """Cheap stand-in for 3D noise: the mean of 2D noise on the three axis planes. Good enough to show the
    idea; the port would use FastNoiseLite's real 3D noise."""
    return (noise.fbm(x, y, seed, wavelength, octaves=3) + noise.fbm(y, z, seed + 1, wavelength, octaves=3)
            + noise.fbm(z, x, seed + 2, wavelength, octaves=3)) / 1.5


def build_patch(h: np.ndarray, rock: np.ndarray, cell: float, origin_xz: tuple, ij0: tuple, size_cells: int,
                seed: int, bulge_m: float = 6.0, lip_m: float = 9.0, tunnel_r: float = 7.0) -> CavePatch:
    j0, i0 = ij0
    surf = h[j0:j0 + size_cells, i0:i0 + size_cells]
    rk = rock[j0:j0 + size_cells, i0:i0 + size_cells]
    nz, nx = surf.shape
    y_lo, y_hi = float(surf.min()) - 8.0, float(surf.max()) + 8.0
    ny = int((y_hi - y_lo) / cell) + 1
    ys = y_lo + np.arange(ny) * cell
    xs = origin_xz[0] + (i0 + np.arange(nx)) * cell
    zs = origin_xz[1] + (j0 + np.arange(nz)) * cell
    Y, Z, X = np.meshgrid(ys, zs, xs, indexing="ij")
    d = surf[None, :, :] - Y
    # Steep rock only, faded to zero at the patch's sides so it meets the heightfield.
    edge = np.minimum.reduce([np.arange(nx)[None, :] * np.ones((nz, 1)), (nx - 1 - np.arange(nx))[None, :] * np.ones((nz, 1)),
                              np.arange(nz)[:, None] * np.ones((1, nx)), (nz - 1 - np.arange(nz))[:, None] * np.ones((1, nx))])
    fade = smoothstep(4.0, 14.0, edge)
    # Cliff-steep rock only: beds and bulges on gentle rock just roughen the floor.
    from .grid import slope_deg
    cliff = smoothstep(38.0, 55.0, slope_deg(ndimage.gaussian_filter(surf, 1.0), cell)) * rk
    near = ndimage.gaussian_filter(cliff, 2.0) * fade
    # Only near the surface: deep rock stays solid, open water stays open.
    shell = np.exp(-(d / (bulge_m * 1.6)) ** 2)
    d = d + bulge_m * noise3(X, Y, Z, seed, 28.0) * near[None, :, :] * shell
    # Layered rock: hard beds stand proud, soft beds are eaten back. A near-square wave in height (bed thickness
    # varying across the patch) raises the surface in hard beds and lowers it in soft ones; where a hard bed
    # sits on a soft one the face steps out past vertical, which is a lip over an undercut.
    rng = np.random.default_rng(seed)
    bed = 11.0 * (1.0 + 0.25 * noise.fbm(X, Z, seed + 5, 120.0, octaves=2))
    wave = np.tanh(3.0 * np.sin(2 * np.pi * (Y + noise3(X, Y, Z, seed + 6, 60.0) * 3.0) / bed))
    d = d + lip_m * wave * near[None, :, :] * shell
    band_y = rng.uniform(y_lo + 0.3 * (y_hi - y_lo), y_lo + 0.6 * (y_hi - y_lo))
    # One tunnel: from a point on the face at the band's height, into the rock, wandering.
    face = np.argwhere(near > 0.5)
    tunnel_j = -1
    if len(face):
        fj, fi = face[np.argmin(np.abs(surf[face[:, 0], face[:, 1]] - band_y))]
        band_y = float(surf[fj, fi]) - 4.0
        tunnel_j = int(fj)
        gz, gx = np.gradient(surf, cell)
        into = -np.array([gx[fj, fi], gz[fj, fi]])
        into = into / (np.linalg.norm(into) + 1e-6)
        p = np.array([xs[fi], band_y, zs[fj]])
        hd = np.arctan2(into[1], into[0])
        for _ in range(14):
            dist = np.sqrt((X - p[0]) ** 2 + (Y - p[1]) ** 2 + (Z - p[2]) ** 2)
            d = np.minimum(d, dist - tunnel_r)
            hd += rng.normal(0.0, 0.35)
            p = p + np.array([np.cos(hd) * 4.0, rng.normal(0.0, 0.8), np.sin(hd) * 4.0])
    solid = d > 0
    below_surface = Y < surf[None, :, :]
    water_under = (~solid) & below_surface
    overhang = (water_under & (np.cumsum(solid[::-1], axis=0)[::-1] > 0)).any(axis=0)
    return CavePatch(d, y_lo, cell, (xs[0], zs[0]), surf, tunnel_j, float(overhang.mean()),
                     float(water_under.sum() * cell ** 3))


def render_slices(p: CavePatch, n_slices: int = 3, scale: int = 4):
    """Vertical slices through the patch along x: rock grey, water blue, the heightfield as a red line."""
    from PIL import Image, ImageDraw
    ny, nz, nx = p.density.shape
    imgs = []
    rows = [int((s + 1) * nz / (n_slices + 1)) for s in range(n_slices)]
    if p.tunnel_row >= 0:
        rows[-1] = p.tunnel_row
    for s, j in enumerate(rows):
        sl = p.density[::-1, j, :] > 0
        rgb = np.where(sl[..., None], np.array([92, 90, 86]), np.array([24, 52, 70])).astype(np.uint8)
        img = Image.fromarray(rgb).resize((nx * scale, ny * scale), Image.NEAREST)
        dr = ImageDraw.Draw(img)
        pts = [(i * scale + scale / 2, (ny - 1 - (p.surface[j, i] - p.y0) / p.cell) * scale) for i in range(nx)]
        dr.line(pts, fill=(230, 80, 60), width=2)
        dr.text((4, 4), f"slice {s + 1}: z = {p.origin[1] + j * p.cell:.0f} m" + (" (tunnel)" if j == p.tunnel_row else ""), fill=(240, 240, 240))
        imgs.append(img)
    w, h = imgs[0].size
    sheet = Image.new("RGB", (w * n_slices + 8 * (n_slices - 1), h), (0, 0, 0))
    for k, im in enumerate(imgs):
        sheet.paste(im, (k * (w + 8), 0))
    return sheet
