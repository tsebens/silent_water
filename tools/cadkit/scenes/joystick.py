"""joystick: a small armrest joystick: a rubber boot, and a stick with a grip and two thumb buttons. Display only.

Brief: the stick is its own GLB with its pivot at the origin, in the scene's `Frame` node, whose Y axis runs along the
stick (that is the frame `JoystickIndicator` tilts in: pitch about X, roll about Z). The boot stands on the back plane
(Z=0) and the stick rises from the origin toward +Z, so the scene mounts like every other kit part. At the tilt limit
the stick must stay inside the hole in the boot's top. Used twice by the pilot seat (throttle; planes and rudder).
Behaviour: none here; the seat binds a JoystickIndicator with `stick` = `Frame/Stick`.
"""
import math

from cadkit.solids import Solid, at, bbox_mm, expect, expect_in_front, export_solids_glb, prism
from cadkit.library import out_dir, res, write_entry
from cadkit.tscn import Scene, Xform

SLUG, GROUP = "joystick", "kit"
USES: list[str] = []
TILT_DEG = 20.0                 # JoystickIndicator.max_deg
BOOT_R, BOOT_H, BOOT_CHAMFER = 26.0, 18.0, 7.0
HOLE_R, HOLE_FLOOR = 13.0, 5.0   # the opening in the boot top, and how deep it goes
SHAFT_R, SHAFT_TOP = 4.5, 62.0
GRIP_R, GRIP_Z0, GRIP_Z1 = 11.0, 50.0, 100.0
BUTTON_R, BUTTON_H = 3.5, 3.0
BUTTON_ZS = (86.0, 72.0)
MAX_STAND_OUT = 120.0
PIVOT_TOL = 0.5                  # the stick's lowest point may sit at most this far from the pivot, mm


def solids() -> tuple[list[Solid], list[Solid]]:
    """(boot, stick) in a Z-up frame, both with their checks. `to_frame` turns the stick to Y-up."""
    boot = prism(12, BOOT_R, BOOT_H, chamfer_top=BOOT_CHAMFER)
    boot = boot - at(prism(12, HOLE_R, BOOT_H), z=HOLE_FLOOR)
    shaft = prism(8, SHAFT_R, SHAFT_TOP)
    grip = at(prism(8, GRIP_R, GRIP_Z1 - GRIP_Z0, chamfer_top=5.0), z=GRIP_Z0)
    stick = shaft + grip
    apothem = GRIP_R * math.cos(math.pi / 8)
    buttons = [at(prism(8, BUTTON_R, BUTTON_H + 0.5), y=-(apothem - 0.5), z=z, rx=90.0) for z in BUTTON_ZS]

    expect(len(boot.solids()) == 1, "boot is one solid")
    expect(len(stick.solids()) == 1, "stick is one solid")
    expect(bbox_mm(boot)[0][2] >= -0.01, "boot back is on Z=0 (base mount)")
    lo, hi = bbox_mm(stick)
    expect(abs(lo[2]) <= PIVOT_TOL and abs(lo[0] + hi[0]) < 0.1 and abs(lo[1] + hi[1]) < 0.1,
           "the stick's pivot is at the origin (its base centred on it)")
    # the shaft leaves the boot through the hole; at the tilt limit it leans H*tan(tilt) off axis at the top
    lean = BOOT_H * math.tan(math.radians(TILT_DEG))
    need = lean + SHAFT_R / math.cos(math.radians(TILT_DEG))
    expect(need <= HOLE_R, f"stick inside the boot at {TILT_DEG:.0f} deg: needs {need:.1f} mm, the hole is {HOLE_R} mm")
    expect(HOLE_FLOOR < BOOT_H and HOLE_R < BOOT_R - BOOT_CHAMFER, "the opening leaves a rim on the boot")
    expect(GRIP_Z0 > BOOT_H + lean, "the grip stays above the boot at full tilt")
    for z in BUTTON_ZS:
        expect(GRIP_Z0 + 5 < z < GRIP_Z1 - 10, f"button at {z} sits on the grip's flat")
    expect(hi[2] <= MAX_STAND_OUT, f"stands {hi[2]:.1f} mm out; limit {MAX_STAND_OUT}")
    boot_s = [Solid(boot, "trim_black")]
    expect_in_front(boot_s, SLUG)
    return boot_s, [Solid(shaft, "hull_metal"), Solid(grip, "control_grey")] + [Solid(b, "button") for b in buttons]


def to_frame(parts: list[Solid]) -> list[Solid]:
    """Z-up CAD to the stick's frame, where Y runs along the stick."""
    return [Solid(at(p.shape, rx=-90.0), p.role) for p in parts]


def build() -> dict:
    d = out_dir(GROUP, SLUG)
    boot, stick = solids()
    rb = export_solids_glb(boot, d / f"{SLUG}_boot.glb", "JoystickBoot")
    rs = export_solids_glb(to_frame(stick), d / f"{SLUG}_stick.glb", "JoystickStick")
    s = Scene("Joystick")
    s.node("Boot", instance=rb["glb"])
    # Frame's Y is the stick axis (root +Z); Frame's -Z is root +Y.
    s.node("Frame", props={"transform": Xform.frame((1, 0, 0), (0, 0, 1), (0, -1, 0))})
    s.node("Stick", parent="Frame", instance=rs["glb"])
    s.write(d / f"{SLUG}.tscn")
    tris = rb["triangles"] + rs["triangles"]
    top = max(p.shape.bounding_box().max.Z for p in stick)
    write_entry(GROUP, SLUG, {
        "kind": "display",
        "summary": "Armrest joystick: black rubber boot and a stick with a grip and two thumb buttons. The stick is its own "
                   "GLB with its pivot at the origin under `Frame` (Y along the stick), so a JoystickIndicator with "
                   "`stick` = Frame/Stick can tilt it. No base.",
        "tags": ["joystick", "stick", "throttle", "rudder", "planes", "armrest", "pilot"],
        "scene": res(d / f"{SLUG}.tscn"),
        "footprint_mm": [2 * BOOT_R, 2 * BOOT_R],
        "stand_out_mm": top,
        "mount": "back on Z=0, centred; stick rises toward +Z; thumb buttons face -Y; tilt +/-20 deg",
        "triangles": tris,
    })
    return {"slug": SLUG, "triangles": tris}
