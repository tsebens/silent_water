# Breakdown (concept #530)

Revised after plan review (round 2). The split is unchanged: one panel-kind assembly (the plumbing-style engineering station, locked as variant 2) on three leaves that need a scene (the valve wheel, used twice; the guarded drop-weights button; the hand-pump lever) and two new behaviours, because no drop-weight release or manual pump exists in `src/`. Everything else is reused. Placement in the sub is ordinary development work (spec 6.1). The content milestone **M12** may be closed between stations; plan review needs to reopen it when it files these. The two objections are answered as follows:
- **Overlaps:** each code arc's `Touches:` now names the files it edits, and each is chained behind the tail of the open chain it still overlaps (`src/sub` and `src/damage` behind #545, `src/interact` behind #546, `existing.yaml` behind #559, the sim-model edit behind #448, and the placement arc behind #563). The behaviours must be listed in `existing.yaml` (the catalogue lists only listed behaviours), so that chaining stays.
- **Size:** Arc 6 is re-sized to M (see the arc).

### Breakdown
| Function / structure | Part | Catalogue match | Decision |
| --- | --- | --- | --- |
| flood_wheel, blow_wheel | handwheel on a valve body | `Valve` behaviour; no generated wheel scene (`hydrophone_wheel` is hand-built, a different control) | new scene `valve_wheel` (used twice), reusing `Valve` |
| ballast_gauges, bilge_level | TANK LEVEL, AIR REMAINING, BILGE LEVEL | `gauge` | reuse (readouts `tank_fraction`, `air_fraction`, `bilge_water_t`) |
| noise_repeater | NOISE | `noise_gauge` | reuse |
| electric_bilge_pump | switch and RUNNING lamp | `lit_toggle` | reuse; wired to `LeakSystem.pump` in placement |
| drop_weights (button) | button under a hinged hazard-striped flip guard | `push_button` for the button; no guard scene | new scene `drop_weights_button` |
| drop_weights (release) | shed mass, once per dive, signal, dive record | none | new behaviour (Arc 1) |
| manual_bilge_pump (control) | lever with spring-back and refill beat | `Lever`, `SpringAxis` do not give hold-E strokes | new scene `hand_pump`, new behaviour (Arc 2) |
| manual_bilge_pump (effect) | 0.035 t/s in `LeakSystem` | none | new behaviour (Arc 2) |
| structure | ballast pipework, console, gauge plate, grab rails, label plates, hose stub | n/a | local solids in the assembly |

Local solids: pipes and pipe brackets, low console body, gauge plate, grab rails, engraved label plates, hose stub.

### Arc 1: M12.? · DropWeights release behaviour
Scope: A host-authoritative drop-weights release. When the guard is open and the button is pressed, once per dive, it sheds the drop weights' mass from the sub model so it turns strongly buoyant and rises. It emits a `released` signal and records the drop in the dive's results. No cost is attached yet; the signal and the record are the hook for one. A small `DropWeightsButton` script gates the press on the guard being open (a two-position hinge). Replicated to clients.
Acceptance:
- [ ] `tests/unit/test_drop_weights.gd`: the button does nothing while the guard is closed; with it open, one press sheds the mass (sub total mass drops by the drop weights' mass) and emits `released`; a second press is ignored; `reset` re-arms it for the next dive; the drop is recorded in the session log.
- [ ] A sub in neutral trim with weights shed has positive net buoyancy in the physics model (unit test).
- [ ] The state is replicated: the host applies, a client request is accepted once.
- [ ] `DropWeightsButton` is listed under `behaviours` in `tools/cadkit/catalogue/existing.yaml`.
- [ ] `tools/check.sh` passes.
Touches: src/sub/drop_weights_button.gd, src/sub/sub_physics_model.gd, src/dive/session_log.gd, tools/cadkit/catalogue/existing.yaml, tests/unit/test_drop_weights.gd
Blocked by: #448, #545, #559
Size: M
Playtest: how fast the rise feels, and whether the mass shed is right.

### Arc 2: M12.? · HandPump behaviour and LeakSystem manual pump
Scope: A manual bilge pump that works by occupying a lever. Hold E for the down stroke; releasing springs it back; a refill beat follows (a cycle of about 1.5 s). While worked steadily it removes about 0.035 t/s of bilge water through `LeakSystem`, adds no powered noise (nearly silent) and needs no power. The electric pump's path is unchanged.
Acceptance:
- [ ] `tests/unit/test_hand_pump.gd`: one steady cycle removes the expected water; nothing is removed while the lever is idle or in the refill beat; the lever springs back on release; the average over 10 s of steady working is within 10% of 0.035 t/s.
- [ ] The manual pump contributes no noise to `LeakSystem.noise_intensity()`; the existing leaks and noise test still passes.
- [ ] State and water removal are host-authoritative and replicated.
- [ ] `HandPump` is listed under `behaviours` in `existing.yaml`.
- [ ] `tools/check.sh` passes.
Touches: src/interact/hand_pump.gd, src/damage/leak_system.gd, tools/cadkit/catalogue/existing.yaml, tests/unit/test_hand_pump.gd
Blocked by: Arc 1, #546
Size: M
Playtest: whether the stroke rhythm feels like work and not a chore.

### Arc 3: M12.? · valve_wheel kit scene
Scope: A handwheel on a heavy valve body, mounted on a pipe run, with the wheel as its own GLB turning about its axis. It carries the existing `Valve` script, so one drag turns it and `get_normalized()` drives the wheel visual. Used twice (FLOOD and BLOW). The label is set per instance. Colour: interaction orange per the palette; the look review may keep the art's dark steel.
Acceptance:
- [ ] `cadkit build` passes, with `expect`s for the footprint and stand-out, nothing behind the mount face, a grab box that clears the wheel rim, and the wheel's turn at both ends.
- [ ] `tests/unit/test_kit_valve_wheel.gd`: loads, root is `Valve` with `wheel` bound, mesh fits the stated footprint, driving to 0 and 1 puts the wheel at its two end angles, grab box present.
- [ ] Triangles within the kit budget (1,500).
- [ ] `review/views.png` is committed.
Touches: assets/models/kit/valve_wheel, tools/cadkit/scenes/valve_wheel.py, tests/unit/test_kit_valve_wheel.gd
Blocked by: none
Size: M

### Arc 4: M12.? · drop_weights_button kit scene
Scope: The DROP WEIGHTS - EMERGENCY control: a `push_button` (reused) on a plate under a hinged flip guard in the `hazard_stripe` swatch. The guard is its own GLB with its hinge on the origin, a two-position hinge that Arc 1's script reads. The scene carries the `DropWeightsButton` script.
Acceptance:
- [ ] `cadkit build` passes, with `expect`s for the footprint and stand-out, the guard closed covering the button, the guard fully open clearing the button from the standing eye, and nothing behind the mount face.
- [ ] `tests/unit/test_kit_drop_weights_button.gd`: root has `DropWeightsButton`; the guard is wired as its gate; the button cannot be reached by a click ray while the guard is closed; guard and button grab boxes apart.
- [ ] All colours are palette roles; `hazard_stripe` on the guard.
- [ ] Triangles within 1,500.
- [ ] `review/views.png` is committed.
Touches: assets/models/kit/drop_weights_button, tools/cadkit/scenes/drop_weights_button.py, tests/unit/test_kit_drop_weights_button.gd
Blocked by: Arc 1
Size: M

### Arc 5: M12.? · hand_pump kit scene
Scope: The manual pump's end of the console: a pump housing with a long lever on a pivot (its own GLB) that swings up and down, ending in a handle in `sub_yellow` (large lever). It carries the `HandPump` script from Arc 2. The scene's `stand_out_mm` records the furthest sweep, so a parent can check the aisle.
Acceptance:
- [ ] `cadkit build` passes, with `expect`s for the lever's travel at both ends, `stand_out_mm` taken from the extremes of the sweep, and nothing behind the mount face.
- [ ] `tests/unit/test_kit_hand_pump.gd`: root has `HandPump`; the lever is bound; at both ends of travel the handle position matches the entry; grab box present.
- [ ] Triangles within 1,500.
- [ ] `review/views.png` is committed.
Touches: assets/models/kit/hand_pump, tools/cadkit/scenes/hand_pump.py, tests/unit/test_kit_hand_pump.gd
Blocked by: Arc 2
Size: M

### Arc 6: M12.? · engineering_station panel
Scope: Assemble the engineering station from the brief as a panel: two `valve_wheel`s (FLOOD, BLOW) on visible ballast pipework along the hull at chest height, a gauge plate between them (`gauge` TANK LEVEL and AIR REMAINING), and a low console beneath. The console carries the `drop_weights_button`, the `lit_toggle` BILGE PUMP with its RUNNING lamp, the BILGE LEVEL `gauge` and the `noise_gauge`, tilted up to read from the standing eye. The `hand_pump` lever comes out of the console's end toward the bilge well. Orange grab rails, label plates, matte grey body. Also commits `brief.yaml` and `breakdown.md`, and writes `review/cameras.json`. No new scripts: readouts and labels are set on the instances. It is M, not L, because every leaf (wheel, guard button, pump lever, gauges, toggle) is a finished scene and the arc only places them and builds simple local solids; it matches the electrical station assembly (#562, M). Leaves are not rebuilt here, so a failing constraint is fixed by moving instances, not by new geometry.
Acceptance:
- [ ] `cadkit build` passes, with `expect`s for: at most 1.2 m along the hull, nothing behind the mount face, sight lines from `operator_eye_m` ([0, 0.55, 0.5]) to every gauge and the lamp, every control within `reach_m` 1.1 m of the shoulder (0.25 m below the eye), grab boxes apart, the pump lever's whole sweep leaving at least 0.8 m of aisle (`aisle_min_m`) clear, and at most 4,000 triangles.
- [ ] `tests/unit/test_panel_engineering_station.gd`: two `Valve` wheels, the three bound gauges (tank, air, bilge level) with the right readouts, the noise gauge, the `lit_toggle` (a `SwitchLever`), `DropWeightsButton` and `HandPump` present; reach and sight checks; displays face the eye; controls work in place.
- [ ] The RUNNING lamp and the gauges read under the stealth red light (checked in the red-light render).
- [ ] The drop-weights guard uses `hazard_stripe`; every colour is a palette swatch.
- [ ] `review/views.png` and `*_vs_concept.png` (from `camera: concept_primary`) are committed.
Touches: assets/models/panels/engineering_station, tools/cadkit/scenes/engineering_station.py, tests/unit/test_panel_engineering_station.gd
Blocked by: Arc 3, Arc 4, Arc 5
Size: M
Look gate: yes
Playtest: whether the gauges read from the aisle, whether the pump lever's sweep feels cramped, and the wheel colour (orange, or the art's dark steel).

### Arc 7: M12.? · Place the engineering station in the sub
Scope: Place the finished panel at the program's ballast position (port, z 3.275). Retire the Ballast panel, the starboard drop-weights placeholder and the Bilge stub. Re-point `PilotSeat`'s `flood_valve` and `blow_valve` and `SubController`'s at the new wheels, bind `LeakSystem.pump` to the lit toggle, bind the pump lever and drop-weights button to their systems, run the pump's hose to the bilge well (centre, z 4.1), and update `program.yaml` (the drop weights move to this station).
Acceptance:
- [ ] `tests/unit/test_sub_layout.gd` and `tests/unit/test_station_clearance.gd` pass with the station in place and the old nodes gone (aisle at least `aisle_min_m` with the lever at both ends of its sweep).
- [ ] The pilot's Numpad 2 and 8 turn the new wheels (the existing pilot-seat test, updated).
- [ ] The bilge switch turns the electric pump on and off; working the hand pump lowers bilge water (a test).
- [ ] The drop weights release once per dive from the new button (a test) and the dive record shows it.
- [ ] `program.yaml` and its derived layout are updated to match.
- [ ] `tools/check.sh` passes.
Touches: src/game/game.tscn, src/sub/interior.tscn, src/sub/sub_controller.gd, assets/models/vehicles/sub_interior/program.yaml, assets/models/vehicles/sub_interior/layout.json, tests/unit/test_sub_layout.gd, tests/unit/test_station_clearance.gd
Blocked by: Arc 1, Arc 2, Arc 6, #563
Size: M

### Design doc
none (the drop-weights cost is not settled; no section changes until it is).

### Open questions
- **(decision)** What does dropping the weights cost? Intent only so far: bearable, expensive enough that crews don't do it lightly, possibly a replacement charge at the hub. Arc 1 builds the signal and the dive record so a cost can attach later. Needs a `Decision:` issue when the hub economy exists.
- **(decision)** The hand pump's numbers are taken from the brief (about 0.035 t/s, about 1.5 s per stroke); they need tuning in play.
- The wheel colour (orange for touch, or the art's dark steel) is left to the look review and is not blocking.

### Discovered work
- The RUNNING lamp follows the switch (`lit_toggle`), not whether the pump is actually powered; #545 (BILGE PUMP circuit) should make it follow the running pump once it lands.

