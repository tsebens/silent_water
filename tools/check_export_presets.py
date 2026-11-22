#!/usr/bin/env python3
"""Every export preset must exclude the editor plugin and tools folders. Passes when export_presets.cfg is absent.
Usage: check_export_presets.py [root]"""
import re
import sys
from pathlib import Path

REQUIRED = ("addons/asset_studio", "tools")


def problems(root: Path) -> list[str]:
    cfg = root / "export_presets.cfg"
    if not cfg.is_file():
        return []
    errs: list[str] = []
    name = ""
    exclude: str | None = None
    sections: list[tuple[str, str | None]] = []
    for line in cfg.read_text().splitlines():
        m = re.match(r"^\[preset\.(\d+)\]$", line.strip())
        if m:
            if name:
                sections.append((name, exclude))
            name, exclude = f"preset.{m.group(1)}", None
        elif re.match(r"^\[preset\.\d+\.options\]$", line.strip()):
            continue
        elif line.startswith("exclude_filter="):
            exclude = line.split("=", 1)[1].strip().strip('"')
    if name:
        sections.append((name, exclude))
    for name, exclude in sections:
        patterns = [p.strip() for p in (exclude or "").split(",")]
        for folder in REQUIRED:
            if not any(p.startswith(folder) or p.startswith(folder + "/") or p.startswith("res://" + folder) for p in patterns):
                errs.append(f"{name}: exclude_filter does not exclude {folder}/ (needs e.g. \"{folder}/*\")")
    return errs


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    errs = problems(root)
    for e in errs:
        print(e)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
