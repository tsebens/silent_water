"""Providers return JPEG or WebP as often as PNG; every saved image must be a real PNG."""
from __future__ import annotations

import io
from pathlib import Path

import pytest
from PIL import Image

from asset_pipeline.adapters import _net


def _encode(fmt: str, mode: str = "RGB") -> bytes:
    img = Image.new(mode, (8, 6), (200, 40, 30, 128) if mode == "RGBA" else (200, 40, 30))
    buf = io.BytesIO()
    img.save(buf, format=fmt)
    return buf.getvalue()


@pytest.mark.parametrize("fmt", ["JPEG", "WEBP"])
def test_non_png_bytes_are_saved_as_png(tmp_path: Path, fmt: str) -> None:
    out = _net.write_image(tmp_path / "v1.png", _encode(fmt))
    data = out.read_bytes()
    assert data.startswith(_net.PNG_SIGNATURE)
    with Image.open(out) as img:
        assert img.format == "PNG"
        assert img.size == (8, 6)


def test_alpha_survives_conversion(tmp_path: Path) -> None:
    out = _net.write_image(tmp_path / "t.png", _encode("WEBP", "RGBA"))
    with Image.open(out) as img:
        assert img.mode == "RGBA"


def test_png_bytes_are_written_unchanged(tmp_path: Path) -> None:
    raw = _encode("PNG")
    out = _net.write_image(tmp_path / "v1.png", raw)
    assert out.read_bytes() == raw


def test_non_image_reply_is_an_error(tmp_path: Path) -> None:
    with pytest.raises(_net.ImageProviderError, match="not an image"):
        _net.write_image(tmp_path / "v1.png", b'{"error": {"message": "quota exceeded"}}')
    assert not (tmp_path / "v1.png").exists()
