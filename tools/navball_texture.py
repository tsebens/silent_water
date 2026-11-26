"""Generate the navball's equirectangular marking mask (assets/textures/navball_mask.png).

    uv run tools/navball_texture.py [out.png]      # default assets/textures/navball_mask.png

Needs only the Python standard library, and is deterministic: the same script writes the same bytes.

The PNG is 2048 x 1024, 8-bit RGB, grey-scale MASKS, not colours. Every channel value is 0 or 255. The shader
(the Navball behaviour arc) picks the colours from the palette:

    R  upper hemisphere (latitude > 0, toward the apex)  255 above the horizon, 0 below
    G  lower hemisphere (latitude < 0)                    255 below the horizon, 0 above   (R + G == 255 everywhere)
    B  markings: horizon line, pitch ladder with numbers, heading ticks with numbers      255 on a mark

Layout. u = x / 2048 is longitude, 0 at the left edge, 360 degrees round, so heading h degrees is at
x = (360 - h) / 360 * 2048. v = y / 1024 is latitude from the apex (y = 0, +90 degrees) down to the nadir (y = 1023,
-90 degrees). The horizon lies between rows 511 and 512. One degree is about 5.7 px across and 5.7 px down.

Markings:
    horizon line   a thin line along the horizon, full width
    heading ticks  every 10 degrees, straddling the horizon; every 30 degrees longer, with the heading number
                   (0, 30 ... 330) printed just above the horizon
    pitch ladder   a line at every 10 degrees of latitude, +-10 to +-80, in short segments centred on
                   headings 45, 135, 225 and 315 so they miss the heading numbers; each is numbered in its
                   middle (the magnitude: the hemisphere colour says the sign), the line broken round it. Each
                   segment is about 16 degrees long on the sphere, widened toward the poles and capped at 70
                   degrees of longitude
    poles          the first and last rows are marked (the +-90 ladder rows, a point on the sphere)
On a 110 mm ball, 1 degree of arc is 0.96 mm: lines are about 1 mm thick and numbers about 4.5 mm tall, which
reads clearly to about +-40 degrees. Numbers are pre-stretched by 1 / cos(latitude) so they look upright.
"""
from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

W = 2048
H = 1024
PX_PER_DEG_X = W / 360.0
PX_PER_DEG_Y = H / 180.0
HORIZON_ROW = H // 2  # rows < HORIZON_ROW are the upper hemisphere

LINE_PX = 5           # thickness of ladder and horizon lines
TICK_PX = 5           # width of heading ticks
TICK_SHORT = 14       # half-length of a 10 degree tick, rows
TICK_LONG = 22        # half-length of a 30 degree tick, rows
GLYPH_SCALE = 4       # font pixel -> texture pixels
LADDER_HALF_DEG = 8.0       # half length of a ladder segment, degrees of arc
LADDER_MAX_HALF_DEG = 35.0  # cap of its longitude half-width
LADDER_CENTRES = (45, 135, 225, 315)
HEADING_NUMBER_BASE_DEG = 4.2  # lowest edge of heading numbers above the horizon

# 5 x 7 digit font, one string per row.
FONT = {
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "11110", "00001", "00001", "10001", "01110"),
    "6": ("00110", "01000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00010", "01100"),
}
GLYPH_W = 5
GLYPH_H = 7
GLYPH_GAP = 1


def lat_to_row(lat: float) -> int:
    """Row whose centre is nearest `lat` degrees."""
    return min(H - 1, max(0, int(round((90.0 - lat) * PX_PER_DEG_Y - 0.5))))


class Mask:
    def __init__(self) -> None:
        self.rows = [bytearray(W) for _ in range(H)]

    def set(self, x: int, y: int) -> None:
        if 0 <= y < H:
            self.rows[y][x % W] = 255

    def fill_cols(self, x0: int, x1: int, y: int) -> None:
        for x in range(x0, x1 + 1):
            self.set(x, y)

    def row_lat(self, y: int) -> float:
        return 90.0 - (y + 0.5) / PX_PER_DEG_Y

    def text(self, s: str, cx: int, cy: int) -> None:
        """Draw digit string `s` centred on column cx, row cy, stretched for its latitude."""
        cols = len(s) * GLYPH_W + (len(s) - 1) * GLYPH_GAP
        half_h = GLYPH_H * GLYPH_SCALE // 2
        for y in range(cy - half_h, cy - half_h + GLYPH_H * GLYPH_SCALE):
            if not 0 <= y < H:
                continue
            fy = (y - (cy - half_h)) // GLYPH_SCALE
            c = max(math.cos(math.radians(self.row_lat(y))), 0.12)
            half_w = int(cols * GLYPH_SCALE / c / 2)
            for x in range(cx - half_w, cx + half_w + 1):
                fx = int((x - (cx - half_w)) * c / GLYPH_SCALE)
                if fx >= cols:
                    continue
                gi, gx = divmod(fx, GLYPH_W + GLYPH_GAP)
                if gx < GLYPH_W and FONT[s[gi]][fy][gx] == "1":
                    self.set(x, y)


def build() -> Mask:
    m = Mask()

    # Horizon line.
    for dy in range(-(LINE_PX // 2), LINE_PX // 2 + 1):
        m.fill_cols(0, W - 1, HORIZON_ROW + dy)

    # Heading ticks and numbers.
    for h in range(0, 360, 10):
        x = int(round(((360 - h) % 360) * PX_PER_DEG_X))
        half = TICK_LONG if h % 30 == 0 else TICK_SHORT
        for y in range(HORIZON_ROW - half, HORIZON_ROW + half):
            m.fill_cols(x - TICK_PX // 2, x + TICK_PX // 2, y)
        if h % 30 == 0:
            base = lat_to_row(HEADING_NUMBER_BASE_DEG)
            m.text(str(h), x, base - GLYPH_H * GLYPH_SCALE // 2)

    # Pitch ladder.
    for n in range(1, 9):
        lat = n * 10
        for sign in (1, -1):
            row = lat_to_row(sign * lat)
            c = math.cos(math.radians(lat))
            half_px = int(min(LADDER_HALF_DEG / c, LADDER_MAX_HALF_DEG) * PX_PER_DEG_X)
            gap_px = int((2 * GLYPH_W + GLYPH_GAP) * GLYPH_SCALE / c / 2) + 8
            for centre in LADDER_CENTRES:
                cx = int(round(centre * PX_PER_DEG_X))
                for dy in range(-(LINE_PX // 2), LINE_PX // 2 + 1):
                    m.fill_cols(cx - half_px, cx - gap_px, row + dy)
                    m.fill_cols(cx + gap_px, cx + half_px, row + dy)
                m.text(str(lat), cx, row)

    # Poles.
    for y in (0, H - 1):
        m.fill_cols(0, W - 1, y)
    return m


def png_bytes(mask: Mask) -> bytes:
    raw = bytearray()
    for y in range(H):
        upper = 255 if y < HORIZON_ROW else 0
        row = bytearray()
        for v in mask.rows[y]:
            row += bytes((upper, 255 - upper, v))
        raw += b"\x00" + row

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def main() -> None:
    default = Path(__file__).resolve().parent.parent / "assets" / "textures" / "navball_mask.png"
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else default
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(png_bytes(build()))


if __name__ == "__main__":
    main()
