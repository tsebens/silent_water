#!/usr/bin/env python3
"""Checks AUTOTEST_REPORT lines from a multi-instance run.

Usage: compare_autotest.py <log> <expected_instances>
Every peer must agree on players, lever and valve; the lever must end at max
(the second grabber was rejected) and the valve near half open.
"""
import json
import sys


def main() -> int:
    log_path, expected = sys.argv[1], int(sys.argv[2])
    reports = []
    with open(log_path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("AUTOTEST_REPORT "):
                reports.append(json.loads(line[len("AUTOTEST_REPORT "):]))
    errors = []
    if len(reports) != expected:
        errors.append(f"expected {expected} reports, got {len(reports)}")
    for r in reports:
        if len(r["players"]) != expected:
            errors.append(f"{r['role']} sees {len(r['players'])} players, expected {expected}")
        if abs(r["lever"] - 1.0) > 0.01:
            errors.append(f"{r['role']} lever={r['lever']} (expected 1.0: Crew3 must be rejected)")
        if r["lever_holder"] != 0:
            errors.append(f"{r['role']} lever still held by {r['lever_holder']}")
        if abs(r["valve"] - 0.5) > 0.1:
            errors.append(f"{r['role']} valve={r['valve']} (expected ~0.5)")
    if reports:
        ref = reports[0]
        for r in reports[1:]:
            for key in ("lever", "valve"):
                if abs(r[key] - ref[key]) > 0.005:
                    errors.append(f"{key} disagrees: {ref['role']}={ref[key]} {r['role']}={r[key]}")
            for pid, pos in ref["players"].items():
                other = r["players"].get(pid)
                if other is None:
                    continue
                dist = sum((a - b) ** 2 for a, b in zip(pos, other)) ** 0.5
                if dist > 0.1:
                    errors.append(f"player {pid} position disagrees by {dist:.2f} m ({ref['role']} vs {r['role']})")
    for e in errors:
        print("  " + e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
