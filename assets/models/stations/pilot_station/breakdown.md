# Breakdown (concept #446)

The pilot station is a generated station built from leaf scenes, behaviour arcs and two assembly arcs. The plan was
approved with Tristan's answer on reach (2026-11-25): the switches move nearer the gap, so the right wing, from the gap
outward, is **navball, the four light switches, the three warning lamps, noise repeater**.

| Arc | Title |
| --- | --- |
| #474 | M12.37 · Pilot helm behaviours (`JoystickIndicator`, wheel zoom, ballast keys) |
| #475 | M12.38 · Speed gauge scale from the physics model |
| #476 | M12.39 · `DepthFinder` behaviour |
| #477 | Pilot light switches and lamp drivers |
| #478 | M12.41 · `joystick` kit scene |
| #479 | M12.42 · `pilot_seat` furniture scene |
| #480 | M12.43 · `depth_finder` kit scene |
| #481 | M12.44 · pilot_station: strip shell and seat (this scene) |
| #482 | M12.45 · pilot_station: instruments and checks (look gate) |
| #483 | M12.46 · Place the pilot station in the sub |

| Function / structure | Part | Catalogue match | Decision |
| --- | --- | --- | --- |
| seat | Pilot seat: operator seat, headrest, footrest | `pilot_seat` | reuse (#479) |
| throttle, planes_and_rudder | Armrest joysticks | `joystick` | reuse, in `pilot_seat` (#478) |
| pedals | Two decorative pedals on a grating | in `pilot_seat` | local solids there |
| ballast | Numpad 8 and 2 | `PilotSeat` | behaviour arc #474 |
| depth_finder | Letterbox bezel and trace | `depth_finder` | reuse (#480, #476) |
| hologram | Pilot hologram above the depth finder | `HoloMap` | an anchor and a projector pad on the strip (this scene) |
| multidisplay | Pilot preset | `multidisplay` | reuse |
| speed_throttle | Two-needle gauge | `gauge` | reuse |
| navball | Navball | `navball` | reuse, with a bore in its facet (this scene) |
| noise_repeater | Noise gauge | `noise_gauge` | reuse |
| warning_lamps | Three lamps in a row | `indicator_lamp` | reuse x3, on a dark plate (this scene) |
| light_switches | Four toggles | `guarded_toggle` | reuse x4 (#518 swaps in the lit toggle) |
| structure | Tilted fascia, two wings, orange-edged end caps, clear apex gap | none | local solids in the strip GLB |

## What the shell arc (#481) built

- One faceted fascia per wing: a flat facet per instrument group, so every instrument lies flat; wings follow the dome
  glass from the hull's `layout.json`, placed at the program's pilot position; an orange end cap on each side of a
  600 mm gap; a raked back, a short ledge and a fascia tilted 40 degrees toward the eye.
- Anchors for every instrument under `Anchors/`, in the order Tristan set. The anchor's frame is the instrument's mount
  frame (+Z out of the fascia). The lamps' anchors sit on a dark plate, 8 mm proud.
- A bore in the navball's facet for its rear half (the entry's `panel_cutout`).
- The hologram's projector pad on the left wing's top, and its anchor above the depth finder.

## Found while building (for #482 and the look gate)

- **Reach.** From the seated eye, every anchor is about 1.05 m away (the dome's bow is a metre ahead of the program's
  pilot position). The brief's `reach_m: 0.75` cannot hold for a strip against the glass there. The measured
  distances are in the entry's `checks`.
- **Triangles.** The instruments alone come to about 12,800 triangles (the navball is 9,702), so the shell and seat
  plus the instruments reach about 14,300: over the station's 12,000. The shell and seat are 1,544. A larger budget
  needs Tristan's approval at the look gate (as life_support's 24,000 did).
