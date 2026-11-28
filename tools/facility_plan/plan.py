# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml>=6", "pillow>=10"]
# ///
"""Check and draw a facility floorplan program. A thin wrapper: the work is in cadkit.facility.

    uv run tools/facility_plan/plan.py <program.yaml> [out_dir]
    (the same as: cadkit plan <program.yaml> [out_dir])

Exits non-zero when a check fails.
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "cadkit"))
from cadkit import facility  # noqa: E402


def main() -> int:
    failed, lines, _ = facility.run(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else None)
    print(facility.summary(failed, lines))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
