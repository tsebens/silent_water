# Breakdown (concept #758)

One **panel** (brief `kind: panel`) assembled from existing kit parts, the decoy rack and three local solids' worth of
structure. Everything binds to the decoy loader's arcs (#746 family). Agreed with Tristan, 2026-11-27: the reservation
grows to 1.0 m along the hull, and the panel's `triangle_budget` is 10,000 with the six decoys counted (#758).

### Breakdown
| Function / structure | Part | Catalogue match | Decision |
| --- | --- | --- | --- |
| rack | six cradles, each seating a decoy | `decoy_rack` (furniture; `DecoyCradle` x6, `decoy` x6) | reuse, instanced beside the panel |
| fire | guarded FIRE button, one per tube | `fire_button` (`FireButton`) | reuse x2; `tube` set on the instance by the placing arc |
| tube_state | three lamps per tube (EMPTY alarm, LOADED warn, PRIMED ok) | `led_strip_alarm`, `led_strip_warn`, `led_strip` (`IndicatorLamp`) | reuse; a `TubeLamps` node drives each set |
| status_screen | runtime-drawn list of decoys, bearing, distance, noise bar | `DecoyStatusScreen` behaviour | reuse; the quad is scaled on a local bezel |
| air | AIR gauge | `gauge` (readout `air_fraction`) | reuse, instance settings |
| noise_repeater | NOISE gauge | `noise_gauge` | reuse |
| structure | panel body, dais, section insets, screen bezel, grab rail, label plates, hazard strip | none | local solids |

### Decisions made in the build
- **Dais.** The rack's lowest cradle is 0.31 m off the floor, which is 1.1 m of reach from the shoulder at the eye 0.5 m out
  (`reach_m`) with no allowance for the sideways distance. The whole assembly stands on a 100 mm dais (the shared rack is
  not changed to suit this parent), so all six cradles are within reach.
- **Reach to a cradle** is measured to the middle of its decoy's grab box, the point a player clicks; to every other
  control it is measured to the farthest corner.
- **Lamps.** Three per tube, matching the loader's own. EMPTY is `led_strip_alarm`, LOADED `led_strip_warn`, PRIMED `led_strip`.
- **Red light.** The lamps and the screen readout are emitters: they keep their swatch colour under the cabin light, while the
  panel's body is lit by it. The Godot test checks the 3:1 contrast on that basis.

### Placing it
Not part of this arc: moving the program's countermeasures reservation to 1.0 m, checking the lock-out trunk's clearance and
setting each `tube` are the placement arc's work.
