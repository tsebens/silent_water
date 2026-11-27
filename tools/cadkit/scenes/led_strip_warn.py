"""led_strip_warn: the led_strip bar with its lens in the indicator_warn role. Geometry is led_strip's."""
from cadkit.library import scene_module

SLUG, GROUP = "led_strip_warn", "kit"
USES: list[str] = ["led_strip"]
LENS_ROLE = "indicator_warn"


def build() -> dict:
    return scene_module("led_strip").build_strip(SLUG, LENS_ROLE, USES, "yellow", "warning, unknown")
