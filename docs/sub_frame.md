# Sub frame: still interior, moving world

**Decision:** the submarine's interior never moves. The outside world is moved around it.

## How it works

- The redesigned sub's hull is generated from `assets/models/vehicles/sub_interior/program.yaml` by a parametric script (decision #395; hull arc under #396). `SubModel` loads it (#401); the old Onshape model and `tools/convert_sub.py` are gone. The hull is about 10 m × 4 m; the pilot floor is 0.2 m below the main deck.
- `Game/Interior` sits at the origin with an identity transform, permanently. Players, controls, interior lights, and the sub's exterior lights (the headlight) live here. Everything inside the sub is in **sub-local space**.
- `Game/World` holds everything outside the sub: terrain, creatures, objectives. Its children use **world space** as their local space.
- `SubFrame` owns the sub's pose in the world (`sub_transform`, host-authoritative, replicated). Each frame it sets `World.transform = render_transform().affine_inverse()`, where `render_transform()` is the pose smoothed toward `sub_transform` on clients (and equal to it on the host). Anything that must line up with the rendered sub reads `render_transform()`, not `sub_transform`. In render space the sub is always at the origin, and the world moves past it.
- Players sync `sync_position`, `sync_yaw` and `sync_pitch` in sub-local space. The sub's motion can't jitter, slide or desync the crew, because it never touches their transforms.

## Gravity and tilt

`SubFrame.gravity_in_sub()` returns world gravity expressed in the sub's frame. The deck stays physically flat (the player's `up_direction` is the sub's up), so `Player` treats the tilt itself:

- Below `Player.SLIDE_ANGLE_DEG` (30°), boots grip. A standing player doesn't move, walking uphill is slower and walking downhill is faster.
- Past 30°, the along-deck part of gravity acts and the crew slides.

## Collision layers

| Layer | Bit | Contents |
| --- | --- | --- |
| 1 | 1 | Interior hull and fixtures |
| 2 | 2 | Interactable grab volumes (raycast only) |
| 3 | 4 | Players |
| 4 | 8 | Exterior world (terrain, rocks) |

Players collide with layers 1 and 3 only, so exterior geometry moving through render space never touches the crew.

## Consequences for later systems

- **Sub physics (M2)** is a custom integrator on `sub_transform`. For collisions with terrain, cast the hull shape from the origin along the sub's velocity (rotated into render space) against layer 4. In render space the sub is always at the origin.
- **Audio (M3/M4):** world sound sources live under `World`. The listener is the local player's camera in the interior. Both share render space, so 3D audio positions are correct with no extra work.
- **Exterior particles** such as marine snow must be anchored in world space. A particle system emitting in render space would travel with the sub.
- **Floating point:** the sub's absolute world position stays small in prototype maps. Large maps may need origin shifting of `sub_transform`.

## Clients

The host writes `sub_transform` at physics rate. Clients receive it at 20 Hz and smooth toward it (`SubFrame.CLIENT_SMOOTHING`), so the world on a client lags the host by a few tens of milliseconds. A slow, heavy sub hides this.

## Bilge

`SubPhysicsModel.bilge_water_t` (tonnes) is uncapped above and floored at 0. Leaks add it, the pump removes it, and every tonne adds mass, so enough bilge water keeps the sub from surfacing even with the tanks blown. It never destroys the sub by itself. Height over the floor is `bilge_height_m(t) = t / INTERIOR_FOOTPRINT_M2` (1 t = 1 m³; footprint 20 m², tunable), so 3 t is 0.15 m and 4 t is 0.20 m. The controller replicates `bilge_water_t`; clients derive height from it. The bilge gauge reads 0..8 t and pins at full scale above that.

### Bilge water surface

`BilgeWater` (`src/sub/bilge_water.tscn`) is a child of the still `Interior`. It sits at `bilge_height_m(bilge_water_t)` above the floor, is hidden when dry, and eases toward the replicated tonnage on every peer. Its shader (`bilge_water.gdshader`) is a minimal translucent rippling surface, clipped to the hull cylinder; the ocean surface can adopt it.

## Program frame and the interior frame

The sub interior program (`assets/models/vehicles/sub_interior/program.yaml`) is written in the **program frame**: origin at the hull's centre, +X starboard, +Y up, +Z toward the stern, with the main deck at y = -0.95. The game's interior frame (everything under `Interior`, above) has its origin on the main cabin floor at the centreline. The two differ only in height:

| Interior | = Program |
| --- | --- |
| x | x |
| y | y + 0.95 (the program's `main_deck_y`, negated) |
| z | z |

So the main deck is y = 0, the sunken cockpit floor (`floor_offset_m: -0.20`) is y = -0.20, and a standing eye (1.65 m) is y = 1.65.

`plan.py` resolves the program into `layout.json` (stations, features, footprints, floors, clearances, cameras). `SubLayout` (`src/sub/sub_layout.gd`) reads it and is the **only** code that converts between the frames: `to_interior`, `to_program`, `position(id)`, `footprint(id)`, `floor_y(compartment)`, `cockpit_floor_offset()`, `clearance(key)`. Other systems ask it; none repeat the offset. After changing `program.yaml`, run `uv run --project tools/asset_pipeline python assets/models/vehicles/sub_interior/plan.py` and commit `layout.json`; `tests/unit/test_layout_in_sync.gd` fails when it is stale.

## The generated hull (`assets/sub/sub_hull.glb`)

`tools/build_sub_hull.py` builds the redesigned hull from `layout.json` (which `plan.py` generates from `program.yaml`). It needs only numpy: `python3 tools/build_sub_hull.py` rewrites `assets/sub/sub_hull.glb`, in the interior frame. Change the program, run `plan.py`, then the hull script, and commit all three outputs. `SubModel` loads it, gives each part its worn-metal, trim or glass look, and adds no collision of its own. Surfaces are named after palette roles. Nodes ending `-col` get trimesh collision (a `StaticBody3D`) on import.

| Part | What it is | Role |
| --- | --- | --- |
| `hull_shell-col` | The cabin wall from the cockpit rim to the stern, seen from inside | `hull_metal` |
| `dome_glass-col` | The cockpit bubble: a true 2.2 m hemisphere (`layout.json` `dome`, built from `program.yaml`'s `dome` block), about 60 x 30 quads with a radial normal on every vertex, bulging forward of the ring; the hull's bow ends at the ring. The cockpit floor plane cuts its lower part, so glass rises round a floor disc (`tests/unit/test_dome_sphere.gd`) | `glass` |
| `dome_rim` | The steel ring at the dome's edge, out to the cabin wall, its lip hiding the glass's edge | `trim_black` |

**The seated eye and the dome (#605).** The sphere is 2.2 m across (radius 1.1 m), its ring plane at the pilot's z (-3.901 m, the nearest hull ring to the seat at -3.9 m) and its centre on the centreline `dome.centre_below_eye_m` = 0.10 m under the seated eye (`program.yaml` `dome`: `eye_height_m` 1.15, the pilot seat's eye height). So the eye sits 0.10 m above the centre, not on it: the eye is 1.15 m above the cockpit floor, and a centre 1.15 m up would leave the sphere's bottom 0.05 m clear of the floor; at 0.10 m the floor plane cuts the glass and a disc of glass 0.328 m in radius (`floor_radius_m`) is left underfoot, enough for the player's 0.3 m capsule. The floor sits 0.20 m below the main deck (one step down). `tests/unit/test_pilot_eye_at_dome_centre.gd` asserts the offset, the disc, the sit point and the step. The pilot's strip reads the sphere from `layout.json`; its wings follow the glass. The true hemisphere leaves each wing about 520 mm of facet, so the stopgap (#605) keeps the multidisplay, navball, four switches, speed gauge, noise repeater and three lamps by stacking (gauges one over the other; lamps over the switches) with smaller dials (radius 0.055 m, was 0.10 and 0.11 m), a 66 mm switch pitch (was 84 mm) and 14 mm facet margins (was 30 mm), and drops the depth finder. #633 redesigns the strip to restore it.
| `deck_cockpit-col` | The pilot's floor, 0.2 m below the main deck, narrowing toward the bow | `interior_dark` |
| `cockpit_step-col` | A 0.25 m ramp up from the cockpit floor to the main deck (a vertical 0.2 m riser would stop the capsule) | `interior_dark` |
| `deck_midships-col`, `deck_bulkhead-col`, `deck_engineering-col` | The main deck, one slab per compartment; `deck_bulkhead` is the hatch sill | `interior_dark` |
| `bulkhead-col` | The watertight bulkhead with its opening (`hatch_width_m` by `hatch_height_m`) | `interior_panel` |
| `hatch_frame` | The coaming round the opening | `trim_black` |
| `tower`, `tower_hatch` | The conning tower on the roof over the ladder, with its top hatch. The shaft through the roof belongs to the ladder's arc | `hull_metal`, `interior_panel` |

The hatch is 1.85 m high, not the draft program's 1.7 m: the player capsule is 1.75 m tall, and its dome jams under a 1.7 m lintel. `tests/unit/test_sub_hull.gd` checks the envelope, deck heights, step, hatch opening and 2.0 m head room, and walks a capsule from the cockpit through the hatch and back.

## Pilot station and spawn points

The pilot's station is the generated `pilot_station` scene, instanced as `Interior/Stations/Pilot` and moved to the program's pilot position by its `StationPlacement` (the placement entry `.` is the node itself, so the seat's sit point lands on the program's pilot position, on the cockpit floor 0.20 m below the main deck). Its seat is re-bound to `PilotSeat` (eye height 1.15 m, sit point on the centreline) with `Throttle`, `Rudder` and `Planes` (`SpringAxis`) beside it and a `JoystickIndicator` on each stick; the strip carries the speed gauge (scale from the model's top speed), the multidisplay, the navball, the BILGE, CO2 and O2 lamps and the noise repeater (the four light switches are lit toggles on the seat armrests: right external on/off and colour, left cabin on/off and colour; the CO2 and O2 lamp drivers read `life_support_readouts`). The depth finder is dropped until the strip is redesigned (#633), and the two gauges and the lamps share facets (see the dome paragraph below). The headlight switches (`Stations/Pilot/HeadlightSwitch`) and cabin switches (`CabinSwitch` in `game.tscn`) drive the lights, and `StationPlacement.follow` puts the pilot hologram at the station's `HologramAnchor`. The cabin lights have no dimmer: `CabinLights` holds them at a fixed level and the strip switch turns them on and off. `tests/unit/test_pilot_station_placement.gd` checks all of this. `Game.SPAWN_POINTS` are in the midships aisle between the map table and the sonar desk; `tests/unit/test_spawn_points.gd` checks them against the footprints and `aisle_min_m`. `Player.INTERIOR_BOUNDS` reaches z -5.0 to cover the dome.

The sonar desk is the generated `sonar_console` station instanced at `Interior/Stations/Sonar`; a `StationPlacement` (`SonarPlacement`) puts its back edge at the program's sonar footprint (z -3.3) and its centre at the desk's x. `tests/unit/test_sonar_placement.gd` checks its footprint against the program.

## Ballast, engineering and bilge stations

The engineering station panel (`Stations/Ballast/Panel`, port, z 3.4: the FLOOD and BLOW wheels, the tank, air and bilge gauges, the noise gauge, the guarded drop-weights button, the BILGE PUMP switch and the hand pump) and the electrical station panel (`Stations/Engineering/Panel`, starboard, z 2.3) are placed by `StationPlacement` from the program's `ballast` and `engineering` entries; a hose from the hand pump runs aft along the floor to the bilge well (`bilge`, centre, z 4.35, moved aft from 4.1 so the 1.2 m panel fits between life support and the well). `BilgeWater` takes its floor height from the bilge well (`SubLayout.position(&"bilge").y`). The aft-port leak is placed relative to the ballast panel, and the three fore leaks sit just inside the hull surface; `test_every_leak_is_inside_the_hull` guards all four.

## Science station, status board and lights

The science station (`science`: the `science_bay` panel on the starboard wall between sonar and countermeasures; its SCAN module replaced the old engineering-wall scanner switch and gauge) and the wall-mounted status board (forward face of the bulkhead, above the hatch) are program entries (`science`, `status_board`; a `mounted: true` item takes no floor). The interior's lights and fascia sit inside the hull; `tests/unit/test_station_clearance.gd` checks that nothing built overlaps a reserved footprint.

The map table (`Interior/Stations/Maps/MapTable`, a `MapTable` over the generated `map_table` station) is placed by a `StationPlacement` (`Stations/MapTablePlacement`): its back sits on the hull end of the program's `top_box` for `map_table`, turned 90 degrees so the operator side faces the aisle, and the two work lamps (`Lights/WorkLamp*`, cabin lights) are offset from the same station. `tests/unit/test_map_table_placement.gd` checks the footprint against the bay and `aisle_min_m`.

The countermeasures station (`countermeasures`: the `countermeasures_station` panel and decoy rack on the starboard wall at the aft end of midships, against the bulkhead) fills its reservation, the full 1.0 m along the hull by 0.45 m deep (z 0.5 to 1.5; #767). It runs alongside the lock-out trunk, whose hatch is flush with the deck and on the centreline, so `plan.py` treats a `floor_hatch` as taking no aisle (it still checks its own). Its FIRE buttons and lamp sets name their tubes by node path (`ForeLoader/Tube`, `AftLoader/Tube`, siblings of `Countermeasures` under `Stations`), which resolve once the decoy loaders are placed there (#777).
