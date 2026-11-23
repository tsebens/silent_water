"""Reference images for `asset concept --reference`: validated, hashed, converted to PNG, scaled to the
provider's input limit and copied under `.asset_work/<slug>/references/`."""
from __future__ import annotations

import hashlib
import io
from dataclasses import dataclass
from pathlib import Path

from . import paths

MODES = ("paint-over", "inspire")
DEFAULT_MODE = "paint-over"
SUFFIXES = (".png", ".jpg", ".jpeg", ".webp")
DEFAULT_MAX_PX = 2048  # longest side; a provider overrides with a `max_input_px` attribute


@dataclass
class Reference:
    name: str  # the original file's name only, never its location
    sha256: str  # of the original file's bytes
    path: Path  # the stored PNG under .asset_work/<slug>/references/

    def record(self) -> dict[str, str]:
        return {"name": self.name, "sha256": self.sha256}


def references_dir(root: Path, slug: str) -> Path:
    return paths.work_dir(root, slug) / "references"


def stored_path(root: Path, slug: str, sha256: str) -> Path:
    return references_dir(root, slug) / f"{sha256[:12]}.png"


def ingest(root: Path, slug: str, src: Path, max_px: int = DEFAULT_MAX_PX) -> Reference:
    """Copy `src` into the asset's references folder as a PNG no larger than `max_px` on its longest side."""
    from PIL import Image, UnidentifiedImageError

    if not src.is_file():
        raise ValueError(f"reference {str(src)!r} is not a file")
    if src.suffix.lower() not in SUFFIXES:
        raise ValueError(f"reference {src.name!r}: only PNG, JPEG and WebP are accepted")
    data = src.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    try:
        with Image.open(io.BytesIO(data)) as img:
            img.load()
            mode = "RGBA" if img.mode in ("RGBA", "LA", "P", "PA") or "transparency" in img.info else "RGB"
            out_img = img.convert(mode)
    except (UnidentifiedImageError, OSError) as e:
        raise ValueError(f"reference {src.name!r} is not a readable image") from e
    if max(out_img.size) > max_px:
        out_img.thumbnail((max_px, max_px), Image.LANCZOS)
    dst = stored_path(root, slug, digest)
    dst.parent.mkdir(parents=True, exist_ok=True)
    out_img.save(dst, format="PNG")
    return Reference(name=src.name, sha256=digest, path=dst)


def load_stored(root: Path, slug: str, record: dict[str, str]) -> Reference:
    """The stored copy of a reference recorded in a lineage entry (for `refine`)."""
    p = stored_path(root, slug, record["sha256"])
    if not p.is_file():
        raise ValueError(f"reference {record['name']!r} is no longer in .asset_work/{slug}/references/; "
                         "the refine cannot keep its geometry")
    return Reference(name=record["name"], sha256=record["sha256"], path=p)
