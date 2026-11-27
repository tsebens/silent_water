# Breakdown (concept #529)

Latest proposal as approved by plan review (arcs #612–#626; the panel is #625). Placement in the sub is #626.


I read this as one panel station, a row of three bays with four module types, built as a shared module frame, four module scenes (each with its own screen behaviour and objective), and one `science_bay` panel assembly. Placing it in the sub is separate from the assets, as `docs/asset_process.md` 6.1 says. The split follows the break-off rule: a module is a thing that moves, is swapped and is used in four types, so it gets its own scenes. Every behaviour is new, so each is an ordinary development arc that blocks the scene using it. Behaviour arcs edit `tools/cadkit/catalogue/existing.yaml`, so they are chained. All arcs go under M12 (#354, open). The panel is the gated arc (it is what the concept asked for); the module scenes under it are not. Catalogue scan done just now: no module, bay, frame or science behaviour exists, and `Gauge`, `IndicatorLamp`, `SwitchLever`, `PushButton` and `control_base` are the reusable parts.

**Revision (round 2), answering plan review:** (1) `existing.yaml`: Arc 1 is now blocked by #602, the tail of the open chain #503 → #556 → #557 → #558 → #559 → #566 → #567 → #602, so every open arc touching that file lands first; the 1→3→4→5→6 chain then covers Arcs 3-6. (2) Arc 2 is blocked by #543 (itself behind #542), the later of the two `src/power` arcs. The power concept #539 has no instrument-load arc (its arcs cover circuits, faults and loads on the nine fixed breakers), so Arc 2 adds an unbreakered load API that #585 will replace with per-instrument breakers. (3) Arc 13's `Touches:` is widened and it is chained behind every named arc. (4) Arc 14 is blocked by #566 explicitly. (5) Results logging stays inside the objectives (`src/objective`, `src/science`); Arc 13 wires it into the dive.

### Breakdown
| Function / structure | Part | Catalogue match | Decision |
| --- | --- | --- | --- |
| bays (three, any module type, loadout Resource) | bay API, `ModuleLoadout` resource, default SCAN/SWEEP/CAMERA | none | new behaviour (Arc 1) |
| bay housing, sloped hand ledge, plate, running strip, empty-bay look | local solids of `science_bay` | none | local solid |
| module chassis (rails, latches, orange side handles, bolt-in) | `science_module_frame` | none | new scene (Arc 7), used by all four modules |
| operator (step up, left/right select, work, E/Esc) | `ScienceStation` extending `StationSeat` | `StationSeat`, `MapTable` pattern | new behaviour (Arc 1) |
| module_screens (health, time left, "closer" hint) | per-module screen drawing, shared `ScienceModule` contract | `DepthFinder` is the quad-texture pattern | new behaviour (Arcs 1, 3-6) |
| scan_module | `scan_module` scene, ring + range + arm switch; `ScanModule` behaviour re-driving `ScanObjective` | `ScanObjective` (exists, switch-driven), `lit_toggle`/`SwitchLever` | new behaviour (Arc 3), new scene (Arc 8) |
| sweep_module | `sweep_module` scene, coverage grid + arm switch; `SweepModule` + `SweepObjective` | none | new behaviour (Arc 4), new scene (Arc 9) |
| camera_module | `camera_module` scene, hooded viewfinder, light meter, stillness indicator, shutter; `CameraModule` + `PhotoObjective` | none | new behaviour (Arc 5), new scene (Arc 10) |
| probe_module | `probe_module` scene, turning reel (own GLB), mechanical depth counter, winch switch; `ProbeModule` + `ProbeObjective` | none | new behaviour (Arc 6), new scene (Arc 11) |
| results | each objective logs complete readings; surfaces in dive status | `DiveDirector` status | in the objectives only (Arcs 3-6); Arc 13 wires it into the dive |
| power | unbreakered instrument draw | `PowerSystem` has nine fixed circuits and no instrument load | new behaviour (Arc 2) |
| noise_repeater | shared noise repeater | `noise_gauge` | reuse |
| assembly | `science_bay` panel | `control_base`, `noise_gauge`, the module scenes | new scene (Arc 12) |

Local solids: bay recesses, housing, hand ledge, SCIENCE BAY plate, running strip, station-seat marker. Fit check: three bays of about 0.35 m plus the housing fits the 1.2 m x 0.45 m limit. The 4000-triangle panel budget leaves roughly 1000 triangles per fitted module including its frame, so module scenes carry a per-scene triangle target.

### Arc 1: M12.? · Science core: bays, module contract, loadout, operator
Scope: A `ScienceBay` that holds up to three `ScienceModule` nodes, a `ModuleLoadout` Resource (default SCAN, SWEEP, CAMERA; any module type may be fitted in any bay), and `ScienceStation` extending `StationSeat` (stand like `MapTable`; left/right select the active module, mapped keys arm and work it, E/Esc step back). `ScienceModule` is the base contract: `armed`, a health 0..1, time left, and a "what would help" hint string, which the module scripts turn into a screen readout.
Acceptance:
- [ ] Unit test: a loadout of three types builds three bays; changing the loadout changes the fitted modules; an empty bay is valid.
- [ ] Unit test: left/right select wraps within fitted modules; E/Esc step back; a second operator is refused.
- [ ] `tools/cadkit/catalogue/existing.yaml` lists `ScienceBay`, `ScienceModule`, `ScienceStation`, `ModuleLoadout`; `tools/check.sh` passes.
Touches: src/science, tests/unit/test_science_core.gd, tools/cadkit/catalogue/existing.yaml
Blocked by: #602 (last of the open `existing.yaml` chain #503, #556-#559, #566, #567, #602)
Size: M
Playtest: how stepping up and switching modules feels.

### Arc 2: M12.? · Instrument load on the power system
Scope: An unbreakered instrument draw on `PowerSystem`: modules register a load while running, it is added to the draw and the battery, and it is gone during blackout. No breaker (that is #585).
Acceptance:
- [ ] Unit test: a running instrument raises `draw_per_minute()`; stopped it returns to the prior value; a blackout stops it.
- [ ] Existing power tests and `tools/check.sh` pass.
Touches: src/power, tests/unit/test_power_instrument_load.gd
Blocked by: #543 (behind #542; both touch `src/power`)
Size: S

### Arc 3: M12.? · ScanModule: SCAN driven from a module
Scope: `ScanModule` (a `ScienceModule`) arms `ScanObjective` in place of the engineering wall switch: the objective accepts an arm from the module as well as `switch`. The screen shows a progress ring, range and a CLOSER hint; the scan's noise is unchanged (about 83 dB), and the module registers its power load.
Acceptance:
- [ ] Unit test: arming the module builds progress in range and nearly still, and drains otherwise, as today.
- [ ] Unit test: the hint reads CLOSER out of range and the ring tracks progress.
- [ ] `ScanObjective` still works with a switch; existing dive tests pass; `existing.yaml` updated; `tools/check.sh` passes.
Touches: src/objective/scan_objective.gd, src/science, tests/unit/test_scan_module.gd, tools/cadkit/catalogue/existing.yaml
Blocked by: Arc 1, Arc 2
Size: M

### Arc 4: M12.? · SweepModule and SweepObjective
Scope: A bathymetry sweep objective (marked area, coverage target); coverage fills in as the sub passes over while the sounder is armed. Pings are loud and give the sub's position away, as active sonar does. `SweepModule` shows the coverage grid; depth colours come from palette swatches.
Acceptance:
- [ ] Unit test: coverage grows only inside the area while armed, completes at the target, and is logged.
- [ ] Unit test: armed pings add noise intensity and reveal the sub as active sonar does.
- [ ] `existing.yaml` updated; `tools/check.sh` passes.
Touches: src/objective, src/science, tests/unit/test_sweep_module.gd, tools/cadkit/catalogue/existing.yaml
Blocked by: Arc 3
Size: M

### Arc 5: M12.? · CameraModule and PhotoObjective
Scope: A photo objective (subjects); the operator aims the external camera with the mouse and takes the shot with the shutter. Quality comes from range, light and stillness, shown live on a light meter and a stillness indicator. Needs EXT LTS or a flash, which is bright.
Acceptance:
- [ ] Unit test: quality rises with closeness, light and stillness, and a shot of a subject in range logs the reading.
- [ ] Unit test: no external light, no flash gives poor quality; the flash adds light noise or brightness as designed.
- [ ] `existing.yaml` updated; `tools/check.sh` passes.
Touches: src/objective, src/science, tests/unit/test_camera_module.gd, tools/cadkit/catalogue/existing.yaml
Blocked by: Arc 4
Size: M

### Arc 6: M12.? · ProbeModule and ProbeObjective
Scope: A probe objective (a list of points). At a marked point, within a radius and depth band, the winch lowers the probe (the reel turns, the depth counter runs) and holds a few seconds to log a reading. Quiet, but the sub must be still.
Acceptance:
- [ ] Unit test: lowering in the radius/depth band while still logs a reading after the hold; moving resets the hold.
- [ ] Unit test: reel angle and counter value follow the lowered depth.
- [ ] `existing.yaml` updated; `tools/check.sh` passes.
Touches: src/objective, src/science, tests/unit/test_probe_module.gd, tools/cadkit/catalogue/existing.yaml
Blocked by: Arc 5
Size: M

### Arc 7: M12.? · science_module_frame kit scene
Scope: The shared bolt-in module chassis: a face plate with rails, two quick-release latches, orange side handles and a mount that fits a bay of about 0.35 m. Static; no script. Faces +Z, back on Z=0.
Acceptance:
- [ ] `cadkit build` passes; the build script has an `expect` for width within 0.35 m and for standing out from the bay.
- [ ] `tests/unit/test_kit_science_module_frame.gd` passes (loads, no script, fits footprint).
- [ ] `review/views.png` committed.
Touches: assets/models/kit/science_module_frame, tools/cadkit/scenes/science_module_frame.py, tests/unit/test_kit_science_module_frame.gd
Blocked by: none
Size: S

### Arc 8: M12.? · scan_module kit scene
Scope: The SCAN module: the frame plus a recessed screen quad (ring, range, hint) and an arm switch (`lit_toggle` or `guarded_toggle`, chosen by the build). Face distinct from the other three: ring screen and a large switch. Under about 1000 triangles.
Acceptance:
- [ ] `cadkit build` passes with `expect`s for fit in the bay, screen facing the eye and switch reach.
- [ ] `tests/unit/test_kit_scan_module.gd`: has the `ScanModule` script, switch works at both ends, screen drawn.
- [ ] `review/views.png` committed.
Touches: assets/models/kit/scan_module, tools/cadkit/scenes/scan_module.py, tests/unit/test_kit_scan_module.gd
Blocked by: Arc 3, Arc 7
Size: S

### Arc 9: M12.? · sweep_module kit scene
Scope: The SWEEP module: the frame, a coverage grid screen and an arm switch.
Acceptance:
- [ ] `cadkit build` passes with `expect`s for bay fit and screen facing the eye.
- [ ] `tests/unit/test_kit_sweep_module.gd`: script present, switch works, screen drawn.
- [ ] `review/views.png` committed.
Touches: assets/models/kit/sweep_module, tools/cadkit/scenes/sweep_module.py, tests/unit/test_kit_sweep_module.gd
Blocked by: Arc 4, Arc 7
Size: S

### Arc 10: M12.? · camera_module kit scene
Scope: The CAMERA module: the frame, a hooded viewfinder screen, a light meter, a stillness indicator and a shutter button (`push_button` reuse).
Acceptance:
- [ ] `cadkit build` passes with `expect`s for bay fit, hood not blocking the neighbour bay, and shutter reach.
- [ ] `tests/unit/test_kit_camera_module.gd`: script present, shutter springs back, indicators wired.
- [ ] `review/views.png` committed.
Touches: assets/models/kit/camera_module, tools/cadkit/scenes/camera_module.py, tests/unit/test_kit_camera_module.gd
Blocked by: Arc 5, Arc 7
Size: S

### Arc 11: M12.? · probe_module kit scene
Scope: The PROBE module: the frame, a visible cable reel as its own GLB under a pivot (turns with depth), a mechanical depth counter, a sample-point list screen and a winch switch.
Acceptance:
- [ ] `cadkit build` passes with `expect`s for bay fit and reel travel at both ends.
- [ ] `tests/unit/test_kit_probe_module.gd`: script present, reel pivot turns, counter reads depth, switch works.
- [ ] `review/views.png` committed.
Touches: assets/models/kit/probe_module, tools/cadkit/scenes/probe_module.py, tests/unit/test_kit_probe_module.gd
Blocked by: Arc 6, Arc 7
Size: M

### Arc 12: M12.? · science_bay panel (assembly)
Scope: The panel: a long low housing about 1.2 m by 0.45 m, three bays at chest height with the default fit (SCAN, SWEEP, CAMERA, PROBE swappable through the loadout), a sloped hand ledge, a SCIENCE BAY plate, a running strip, the shared noise repeater and the `ScienceStation` operator with its station seat. Commits `brief.yaml` and `breakdown.md` and writes `review/cameras.json`.
Acceptance:
- [ ] `cadkit build` passes; `expect`s for size limit, bays between waist and eye height, reach 1.1 m from the shoulder to every control, sight line from the eye to every screen, and the triangle budget of 4000 with three modules fitted.
- [ ] `tests/unit/test_station_science_bay.gd`: every function's control present, grab boxes apart, displays face the eye, a different loadout fits any bay, an empty bay renders.
- [ ] Review sheets and the `*_vs_concept.png` sheets committed.
Touches: assets/models/stations/science_bay, tools/cadkit/scenes/science_bay.py, tests/unit/test_station_science_bay.gd
Blocked by: Arc 1, Arc 8, Arc 9, Arc 10, Arc 11
Size: M
Look gate: yes
Playtest: how the row reads against the primary art, and operating it standing.

### Arc 13: M12.? · Place the science station in the sub
Scope: At the starboard-wall reservation from #598, place the panel, retire the engineering wall's scanner panel (switch and SCAN gauge), wire the modules to their objectives and the dive director, and update the reserved footprint and `science_view` in the program.
Acceptance:
- [ ] Placement test: the station sits on the reservation without clearance faults (`test_station_clearance.gd` passes).
- [ ] Unit test: the engineering scanner panel is gone, the dive still completes via the SCAN module.
- [ ] `tools/check.sh` including the three-instance autotest passes.
Touches: src/sub, src/dive/session_log.gd, src/dive, src/sub/interior.tscn, assets/models/vehicles/sub_interior/program.yaml, assets/models/vehicles/sub_interior/layout.json, tests/unit/test_science_placement.gd, tests/unit/test_sub_layout.gd, tests/unit/test_station_clearance.gd, tests/unit/test_full_dive.gd, tests/unit/test_dive_flow.gd
Blocked by: #598, #572, #579, #580, #581, #604, #605, #609, Arc 6, Arc 12
Size: M

### Arc 14: M12.? · Example targets for sweep, probe and photo
Scope: One authored example target per new objective type (a sweep area, a probe point list, a photo subject) in the dive content, enough to test each module, as Godot Resources.
Acceptance:
- [ ] Unit test: each example objective can be completed headless by its module and logs.
- [ ] `tools/check.sh` passes.
Touches: src/site, src/dive, tests/unit/test_science_example_targets.gd
Blocked by: Arc 13, #566 (`src/dive/session_log.gd`)
Size: S

### Design doc
Add the science station (module bays, four instruments) to the stations section.

### Open questions
- (decision) The brief says power binds to "the power system's load (#539)", but `PowerSystem` has nine fixed circuits and no instrument load. Arc 2 adds an unbreakered draw for now; per-instrument breakers (#585) will replace it. Confirm the draw levels when tuning.
- (decision) The default fit leaves PROBE out, so PROBE is built but unexercised by default dives. Fine for now; revisit when the hub exists.
No (approval) items.

### Discovered work
- `program.yaml` still reserves the science station on the port wall (footprint 0.9 x 0.5); #598 supersedes this, and Arc 13 updates it only if #598 has not.
