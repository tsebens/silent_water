"""cadkit.facility: the research station passes; broken fixtures fail naming the part."""
from pathlib import Path

import pytest

from cadkit import facility, library

FIX = Path(__file__).parent / "fixtures" / "facility"
STATION = library.MODELS / "facilities" / "research_station" / "program.yaml"


def failures(path: Path) -> list[str]:
    return facility.check(facility.load(path))[0]


def test_research_station_passes():
    assert failures(STATION) == []


def test_ok_fixture_passes():
    assert failures(FIX / "ok.yaml") == []


def test_narrow_door_named():
    msgs = failures(FIX / "narrow_door.yaml")
    assert any("door dock-hall" in m and "0.8 m" in m for m in msgs)


def test_powered_door_on_dark_route_named():
    msgs = failures(FIX / "powered_dark.yaml")
    assert any("route dark" in m and "powered door hall-lab" in m for m in msgs)


def test_non_watertight_zone_door_named():
    msgs = failures(FIX / "dry_zone_door.yaml")
    assert any("door hall-lab" in m and "zones" in m and "manual" in m for m in msgs)


def test_program_is_exposed():
    plan = facility.load(FIX / "ok.yaml")
    assert set(plan.rooms) == {"dock", "hall", "lab"} and len(plan.doors) == 3


def test_cli_plan_writes_images_and_report(tmp_path):
    from cadkit import cli
    assert cli.main(["plan", str(STATION), str(tmp_path)]) == 0
    for name in ("site.png", "report.txt", "layout.json", "plan_main_L1.png"):
        assert (tmp_path / name).exists()
    assert "0 problem(s)" in (tmp_path / "report.txt").read_text()


def test_cli_plan_fails_on_broken(tmp_path):
    from cadkit import cli
    assert cli.main(["plan", str(FIX / "narrow_door.yaml"), str(tmp_path)]) == 1
