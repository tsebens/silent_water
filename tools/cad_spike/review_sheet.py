"""Side-by-side review sheets: concept image beside the render from the matching camera.

    uv run python review_sheet.py <renders_dir> <out_dir>
Pairs come from the station's brief (concept images) and the camera names that start with `concept_`.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

from kitcad import REPO

PAIRS = {  # camera name -> concept image (repo path)
    "concept_console_view": "assets/models/cockpit/concept/cockpit_sonar_console_reference.png",
    "concept_primary_view": "assets/models/cockpit/concept/cockpit_primary.png",
}
H = 520


def label(im: Image.Image, text: str) -> Image.Image:
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 8 * len(text) + 16, 26], fill=(0, 0, 0))
    d.text((8, 7), text, fill=(255, 255, 255))
    return im


def fit(path: Path) -> Image.Image:
    im = Image.open(path).convert("RGB")
    return im.resize((round(im.width * H / im.height), H))


def sheet(renders: Path, out: Path) -> list[Path]:
    out.mkdir(parents=True, exist_ok=True)
    made = []
    for cam, concept in PAIRS.items():
        a = label(fit(REPO / concept), "concept")
        b = label(fit(renders / f"{cam}.png"), f"render: {cam}")
        s = Image.new("RGB", (a.width + b.width + 8, H), (40, 40, 40))
        s.paste(a, (0, 0))
        s.paste(b, (a.width + 8, 0))
        p = out / f"{cam}_vs_concept.png"
        s.save(p, optimize=True)
        made.append(p)
    rest = [p for p in sorted(renders.glob("*.png")) if not p.stem.startswith("concept_")]
    if rest:
        tiles = [label(Image.open(p).convert("RGB").resize((480, 300)), p.stem) for p in rest]
        cols = 2
        g = Image.new("RGB", (cols * 480, ((len(tiles) + cols - 1) // cols) * 300))
        for i, t in enumerate(tiles):
            g.paste(t, ((i % cols) * 480, (i // cols) * 300))
        p = out / "views.png"
        g.save(p, optimize=True)
        made.append(p)
    return made


if __name__ == "__main__":
    for p in sheet(Path(sys.argv[1]), Path(sys.argv[2])):
        print(p)
