"""Hillshade renders of a macro grid, with depth tint, contours, landform outlines and station markers."""
from __future__ import annotations
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from .grid import MapPreset

# Bathymetric tint from shallow (sandy grey) to deep (teal-black); the game's own palette comes later.
_STOPS = [(0.0, (22, 36, 50)), (0.35, (40, 72, 88)), (0.65, (92, 112, 112)), (0.85, (146, 138, 116)), (1.0, (196, 184, 156))]


def _tint(t: np.ndarray) -> np.ndarray:
    out = np.zeros(t.shape + (3,))
    for (t0, c0), (t1, c1) in zip(_STOPS[:-1], _STOPS[1:]):
        m = (t >= t0) & (t <= t1)
        u = ((t - t0) / (t1 - t0))[m][:, None]
        out[m] = np.array(c0) * (1 - u) + np.array(c1) * u
    return out / 255.0


def hillshade(h: np.ndarray, cell: float, az_deg: float = 315.0, el_deg: float = 42.0) -> np.ndarray:
    gz, gx = np.gradient(h, cell)
    slope = np.arctan(np.hypot(gx, gz))
    aspect = np.arctan2(-gx, gz)
    az, el = np.radians(az_deg), np.radians(el_deg)
    return np.clip(np.sin(el) * np.cos(slope) + np.cos(el) * np.sin(slope) * np.cos(az - aspect), 0.0, 1.0)


def render(h: np.ndarray, preset: MapPreset, scale: int = 3, contours_m: float = 50.0, placements=None,
           landforms=None, candidates: dict | None = None, title: str = "") -> Image.Image:
    t = (h - preset.depth_deep) / (preset.depth_shallow - preset.depth_deep)
    shade = hillshade(h, preset.cell_m)
    rgb = _tint(np.clip(t, 0, 1)) * (0.55 + 0.85 * shade[..., None])
    # Contours: darken cells where a level crosses between neighbours.
    lev = np.floor(h / contours_m)
    cross = (lev != np.roll(lev, 1, axis=0)) | (lev != np.roll(lev, 1, axis=1))
    cross[0, :] = False; cross[:, 0] = False
    major = (np.floor(h / (contours_m * 4)) != np.floor(np.roll(h, 1, axis=0) / (contours_m * 4))) | \
            (np.floor(h / (contours_m * 4)) != np.floor(np.roll(h, 1, axis=1) / (contours_m * 4)))
    rgb[cross] *= 0.78
    rgb[major] *= 0.7
    if candidates:
        # Tint candidate cells of the hardest class faintly so the gate is visible.
        name, m = min(candidates.items(), key=lambda kv: kv[1].sum())
        rgb[m] = rgb[m] * 0.6 + np.array([0.9, 0.6, 0.2]) * 0.4
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).resize((h.shape[1] * scale, h.shape[0] * scale), Image.NEAREST)
    d = ImageDraw.Draw(img)

    def to_px(wx: float, wz: float) -> tuple[float, float]:
        return ((wx + preset.width_m / 2) / preset.cell_m * scale, (wz + preset.length_m / 2) / preset.cell_m * scale)

    if landforms:
        colours = {"chasm": (80, 200, 255), "tributary": (80, 160, 220), "scarp": (255, 120, 80), "pit": (255, 220, 80), "seamount": (120, 255, 120)}
        for f in landforms:
            c = colours.get(f.kind, (255, 255, 255))
            if len(f.pts) == 1:
                px, pz = to_px(*f.pts[0]); r = f.size / preset.cell_m * scale
                d.ellipse([px - r, pz - r, px + r, pz + r], outline=c, width=1)
            else:
                d.line([to_px(*p) for p in f.pts], fill=c, width=1)
    if placements:
        for p in placements:
            px, pz = to_px(p.x, p.z)
            d.ellipse([px - 5, pz - 5, px + 5, pz + 5], outline=(255, 255, 255), width=2)
            d.text((px + 7, pz - 6), f"{p.name} {p.y:.0f}", fill=(255, 255, 255))
    if title:
        d.rectangle([0, 0, img.width, 16], fill=(0, 0, 0))
        d.text((4, 2), title, fill=(230, 230, 230))
    return img


def hypsometry(h: np.ndarray, preset: MapPreset, bins: int = 12) -> str:
    """Text histogram of depth: how much ground sits in each band."""
    edges = np.linspace(preset.depth_deep, preset.depth_shallow, bins + 1)
    counts, _ = np.histogram(h, bins=edges)
    total = counts.sum()
    lines = []
    for k in range(bins - 1, -1, -1):
        bar = "#" * int(40 * counts[k] / max(counts.max(), 1))
        lines.append(f"{edges[k]:7.0f}..{edges[k+1]:5.0f} {100*counts[k]/total:5.1f}% {bar}")
    return "\n".join(lines)
