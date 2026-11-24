"""The catalogue a breakdown reads: every generated scene's entry, plus the hand-built scenes and the control
behaviours the game already has. Always read it fresh; never work from a remembered copy.
"""
from __future__ import annotations

from pathlib import Path

import yaml

from cadkit import library

EXISTING = Path(__file__).resolve().parents[1] / "catalogue" / "existing.yaml"


def load(models: Path = library.MODELS) -> dict:
    generated = [yaml.safe_load(p.read_text()) for p in sorted(models.glob("*/*/component.yaml"))]
    existing = yaml.safe_load(EXISTING.read_text())
    return {"generated": generated, "existing": existing["scenes"], "behaviours": existing["behaviours"]}


def _mentions(text: str, words: list[str]) -> bool:
    return all(w.lower() in text.lower() for w in words)


def search(cat: dict, words: list[str]) -> dict:
    """Entries and behaviours that mention every word (slug, kind, summary and tags; a behaviour's name and what it does)."""
    def hit(e: dict) -> bool:
        return _mentions(" ".join([str(e.get("slug", "")), str(e.get("kind", "")), str(e.get("summary", "")),
                                   " ".join(e.get("tags", []))]), words)
    return {"generated": [e for e in cat["generated"] if hit(e)], "existing": [e for e in cat["existing"] if hit(e)],
            "behaviours": [b for b in cat["behaviours"] if _mentions(f"{b['script']} {b['does']}", words)]}


def table(cat: dict) -> str:
    lines = []
    for group in ("generated", "existing"):
        if not cat[group]:
            continue
        lines.append(f"## {group} scenes: slug | kind | script | footprint (mm) or size | summary")
        for e in cat[group]:
            beh = e.get("behaviour") or {}
            script = beh.get("script") or e.get("script") or "-"
            size = e.get("footprint_mm") or e.get("size") or "-"
            lines.append(f"- {e['slug']} | {e['kind']} | {script} | {size} | {e['summary']}")
    if cat["behaviours"]:
        lines.append("## behaviours (scripts a scene may use; one not listed here is a development arc): script | does")
        lines += [f"- {b['script']} | {b['does']}" for b in cat["behaviours"]]
    return "\n".join(lines) if lines else "nothing matches"
