#!/usr/bin/env python3
"""Checks AUTOTEST_REPORT lines from a multi-instance run (see src/debug/autotest.gd).

Usage: compare_autotest.py <log> <expected_instances>
"""
import json
import sys


TOUR = ["pilot", "sonar", "map_table", "engineering", "ballast", "life_support"]


def near(a, b, tol):
    return abs(a - b) <= tol


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
    by_role = {r["role"]: r for r in reports}
    for r in reports:
        who = r["role"]
        if len(r["players"]) != expected:
            errors.append(f"{who} sees {len(r['players'])} players, expected {expected}")
        if r["throttle"] < 0.9:
            errors.append(f"{who} throttle={r['throttle']} (Crew3 held W from the helm)")
        if not near(r["flood"], 0.5, 0.1):
            errors.append(f"{who} flood={r['flood']} (expected ~0.5)")
        if r["rudder"] > -0.8:
            errors.append(f"{who} rudder={r['rudder']} (expected hard to port)")
        if r["engine"] <= 0.2:
            errors.append(f"{who} engine={r['engine']} (should be spooling up)")
    if "Crew3" in by_role and expected >= 3:
        crew3 = by_role["Crew3"]
        for r in reports:
            if r["seat_holder"] != crew3["peer"]:
                errors.append(f"{r['role']} thinks seat holder is {r['seat_holder']}, expected Crew3 {crew3['peer']}")
        pos = crew3["players"].get(str(crew3["peer"]))
        if pos and sum((a - b) ** 2 for a, b in zip(pos, crew3["seat_point"])) ** 0.5 > 0.05:
            errors.append(f"Crew3 is at {pos}, not in the seat {crew3['seat_point']}")
    host = next((r for r in reports if r.get("is_host")), None)
    if host and "Crew2" in by_role:
        crew2_voice = host.get("voices_db", {}).get(str(by_role["Crew2"]["peer"]))
        if crew2_voice is None or not near(crew2_voice, 75.0, 0.5):
            errors.append(f"host hears Crew2's voice at {crew2_voice} dB, expected 75")
        if host["sub_db"] < 75.0:
            errors.append(f"sub noise {host['sub_db']} dB should include Crew2's 75 dB voice")
    for r in reports:
        if r.get("pins") != 1:
            errors.append(f"{r['role']} sees {r.get('pins')} chart pins, expected Crew2's one")
        if not r.get("is_host") and r.get("host_events", 0) < 1:
            errors.append(f"{r['role']} got no host game events in its developer log")
    if "Crew2" in by_role:
        for r in reports:
            if r["headset_holder"] != by_role["Crew2"]["peer"]:
                errors.append(f"{r['role']} thinks the headset is on {r['headset_holder']}, expected Crew2")
    if reports:
        ref = reports[0]
        for r in reports[1:]:
            for key, tol in (("throttle", 0.01), ("flood", 0.005), ("rudder", 0.05), ("depth", 0.5), ("tank", 0.02), ("sub_db", 1.5), ("ambient_db", 0.1)):
                if not near(r[key], ref[key], tol):
                    errors.append(f"{key} disagrees: {ref['role']}={ref[key]} {r['role']}={r[key]}")
            if r["apex_state"] != ref["apex_state"]:
                errors.append(f"apex state disagrees: {ref['role']}={ref['apex_state']} {r['role']}={r['apex_state']}")
            apex_gap = sum((a - b) ** 2 for a, b in zip(r["apex_pos"], ref["apex_pos"])) ** 0.5
            if apex_gap > 3.0:
                errors.append(f"apex position disagrees by {apex_gap:.1f} m ({ref['role']} vs {r['role']})")
            for pid, pos in ref["players"].items():
                other = r["players"].get(pid)
                if other is None:
                    continue
                dist = sum((a - b) ** 2 for a, b in zip(pos, other)) ** 0.5
                if dist > 0.1:
                    errors.append(f"player {pid} position disagrees by {dist:.2f} m ({ref['role']} vs {r['role']})")
    # Crew1 tours every placed station (src/debug/autotest.gd TOUR); the other instances tour nothing.
    if "Crew1" in by_role:
        visits = by_role["Crew1"].get("visits", [])
        for station in TOUR:
            if station not in visits:
                errors.append(f"Crew1 never visited {station} (visits: {visits})")
    for e in errors:
        print("  " + e)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
