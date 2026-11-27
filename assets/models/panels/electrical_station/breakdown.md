# Breakdown (concept #534)

Revised after plan review (round 1). I read this as one asset concept with a gated panel (the electrical station) plus the ordinary work it needs: a gauge change, three new behaviours (each now its own arc, chained because all three touch `src/interact` and `existing.yaml`), three new kit scenes (breaker module, spares drawer, junction box), the panel's assembly, and its placement in the sub. The library was scanned fresh with `cadkit catalogue`: there is no breaker, spares or junction scene, and no behaviour for a three-state handle; `gauge` has no red zone. `src/power` does not exist yet, so every binding waits on M14 (#541, #542, #543, #545). The art (primary: the distribution board, with variant 3's analogue meter in place of the small load indicator) matches `functions`: nine breakers in a 3 x 3 grid, generator section at the top, battery column on the right, spares drawer at the bottom. The generator itself is not built. All arcs go under M12 (#354), the open content milestone. The board is `kind: panel`, the library's first `panels` scene, with the 4,000 triangle budget.

Changes from round 1: Arc 2 is split into three behaviour arcs (2, 3, 4), the blocked-by lines of the scene arcs and the panel are re-pointed to the arcs they actually use, the panel's reach criterion is concrete, and `circuit` is assigned to the panel arc only.

### Breakdown

| Function / structure | Part | Catalogue match | Decision |
| --- | --- | --- | --- |
| breakers (x9): handle states, lamp, label | breaker module | none (`lit_toggle` is two-state, its lamp only follows the switch) | new scene `breaker_module` (Arc 5) |
| breakers: state from PowerSystem, click requests | `BreakerSwitch` | not in `behaviours` | new behaviour (Arc 2) |
| replace_breaker: interact on a blown one swaps in a spare | `BreakerSwitch` | not in `behaviours` | new behaviour (Arc 2, same script) |
| replace_breaker: drawer shows remaining modules | clear-fronted drawer, 4 slots | none | new scene `spares_drawer` (Arc 6) + new behaviour `SparesDrawer` (Arc 3) |
| generator: guarded START/STOP | `guarded_toggle` | `guarded_toggle` (SwitchLever) | reuse |
| generator: switch sends request, follows running state | `GeneratorLink` | not in `behaviours` | new behaviour (Arc 4) |
| generator: RUNNING lamp | `indicator_lamp` | `indicator_lamp` | reuse; its `ThresholdLamp` driver on `generator_running` is wired in Arc 9 |
| generator: HEAT gauge | `gauge` | `gauge`, readout `generator_heat` | reuse, tier 1 |
| battery: tall vertical bar, 0 to 100% | `linear_gauge` | `linear_gauge`; low-is-bad bands need `descending` | reuse, after #503 |
| load: analogue meter with red zone | `gauge` | `gauge`, no red zone | variant: `Gauge` zone exports (Arc 1), then reuse |
| junction_box | bolted box with a spark anchor | none | new scene `junction_box` (Arc 7; static, #543 owns the sparking) |
| structure: board face, section plates, orange grab rails, engraved label plates, cable-tray stubs | board | none | local solids in the assembly (Arc 8) |

Local solids: the board and section plates, the two grab rails, the label plates, the cable-tray stubs.

Size check: the board is at most 1.2 m wide and 0.45 m deep. The battery column and `linear_gauge` take about 0.2 m, which leaves about 0.9 m for the 3 x 3 grid and the rails, so a breaker module must fit about 150 x 150 mm and stand out under 60 mm. Height runs knee to head (about 1.3 m): generator section about 0.3 m, grid about 0.55 m, spares about 0.25 m. Triangles: nine modules at 200 or fewer each (about 1,800), plus `gauge` 320, `linear_gauge`, `guarded_toggle`, a lamp and the drawer. Tight against 4,000, so Arc 5 sets a hard cap of 200 per module.

### Arc 1: M12.? · Gauge red zone
Scope: `Gauge` gets a tier-1 export for a coloured zone on its scale: a start value and, optionally, an end value and a swatch. It defaults to none and draws as a band along the scale, so existing gauges are unchanged. The LOAD meter needs a red zone at the top of its scale. The catalogue's `gauge` `set_on_instance` and the `Gauge` entry in `existing.yaml` document it.
Acceptance:
- [ ] `tests/unit/test_gauge_zone.gd`: with no zone set, a gauge draws exactly as before; with `zone_from` set the zone covers from that value to `max_value` and uses the given swatch (a palette swatch, no colour literal).
- [ ] The `gauge` entry's `set_on_instance` names the zone exports; `cadkit build`, `cadkit check` and `tools/check.sh` pass.
Touches: src/interact, tests/unit/test_gauge_zone.gd, tools/cadkit/scenes/gauge.py, assets/models/kit/gauge, tools/cadkit/catalogue/existing.yaml
Blocked by: #503, #543
Size: S

### Arc 2: M12.? · BreakerSwitch behaviour
Scope: `BreakerSwitch` is a click toggle with a `circuit` export. It shows the breaker's state from `readout`: on (handle up, lamp ok), off (handle down, lamp off), tripped (handle mid-way, lamp warn), blown (handle limp, lamp alarm). Clicking sends a switch request to `PowerSystem` (a reset when tripped); interacting with a blown one sends the replace request and is refused at 0 spares. Listed in `existing.yaml`.
Acceptance:
- [ ] `tests/unit/test_breaker_switch.gd`: the four states give the handle angle and lamp swatch above; a click on on, off and tripped sends the right request to a stub PowerSystem; a click on blown sends replace, and nothing when spares are 0.
- [ ] `BreakerSwitch` appears in `cadkit catalogue` (`behaviours`); no colour literals; `tools/check.sh` passes.
Touches: src/interact, tools/cadkit/catalogue/existing.yaml, tests/unit/test_breaker_switch.gd
Blocked by: Arc 1, #542
Size: S

### Arc 3: M12.? · SparesDrawer behaviour
Scope: `SparesDrawer` shows the first N of its slot nodes, N being the `spares` readout, clamped to the slot count. Listed in `existing.yaml`.
Acceptance:
- [ ] `tests/unit/test_spares_drawer.gd`: slots shown equal the readout, clamped to the slot count; zero shows none.
- [ ] `SparesDrawer` appears in `cadkit catalogue` (`behaviours`); `tools/check.sh` passes.
Touches: src/interact, tools/cadkit/catalogue/existing.yaml, tests/unit/test_spares_drawer.gd
Blocked by: Arc 2, #542
Size: XS

### Arc 4: M12.? · GeneratorLink behaviour
Scope: `GeneratorLink` takes a `SwitchLever` and sends the generator start/stop request to `PowerSystem`, and makes the switch follow the generator's running state (a stop from a trip or heat shutdown flips it back without sending a request). Listed in `existing.yaml`.
Acceptance:
- [ ] `tests/unit/test_generator_link.gd`: the switch sends start and stop; a running-state change from the readout moves the switch without sending a request.
- [ ] `GeneratorLink` appears in `cadkit catalogue` (`behaviours`); `tools/check.sh` passes.
Touches: src/interact, tools/cadkit/catalogue/existing.yaml, tests/unit/test_generator_link.gd
Blocked by: Arc 3, #541
Size: XS

### Arc 5: M12.? · breaker_module kit scene
Scope: A chunky breaker module: a base plate, a chunky toggle handle (its own GLB, pivot through the origin) that `BreakerSwitch` swings between up, mid and limp, and a status lamp (`indicator_lamp`, wired in the scene to the switch's lamp export). A static recess for an engraved label plate. It mounts on a flat face, at most 150 x 150 mm and standing out at most 60 mm. Powder-coated grey, matching life support.
Acceptance:
- [ ] `cadkit build` passes; `expect`s for the footprint (at most 150 x 150 mm), the stand-out (at most 60 mm) and `expect_in_front`; a hard cap of 200 triangles for the whole module.
- [ ] `tests/unit/test_kit_breaker_module.gd`: the scene loads, root is `BreakerSwitch`, the handle and lamp nodes are wired, the meshes fit the entry's footprint and stand-out, and the handle reaches up, mid and limp.
- [ ] The catalogue entry gives `set_on_instance` (`circuit`, `label`) and the states in `behaviour.values`; `review/views.png` is committed.
Touches: assets/models/kit/breaker_module, tools/cadkit/scenes/breaker_module.py, tests/unit/test_kit_breaker_module.gd
Blocked by: Arc 2
Size: S

### Arc 6: M12.? · spares_drawer kit scene
Scope: A clear-fronted drawer at the foot of the board holding up to 4 spare breaker modules (the `spares` start count is 4, #542). The modules are stand-ins built from `breaker_module`'s body GLB, each in its own slot node. A clear front of glass over a recessed tray; label plate SPARES.
Acceptance:
- [ ] `cadkit build` passes; `expect`s for the footprint (at most 0.9 m wide and 0.25 m tall) and stand-out (at most 0.3 m); the triangle total is at most 700.
- [ ] `tests/unit/test_kit_spares_drawer.gd`: root is `SparesDrawer`, 4 slot nodes, the meshes fit the footprint.
- [ ] The entry names the slot node names and the count; `review/views.png` is committed.
Touches: assets/models/kit/spares_drawer, tools/cadkit/scenes/spares_drawer.py, tests/unit/test_kit_spares_drawer.gd
Blocked by: Arc 3, Arc 5
Size: S

### Arc 7: M12.? · junction_box kit scene
Scope: A bolted steel junction box with cable glands for the cable trays: grey body, a hinged lid shown closed (static), a hazard stripe, and a marked spark anchor node where #543's sparks spawn. Static: the sparking and the hold-E repair are #543's. A single body GLB.
Acceptance:
- [ ] `cadkit build` passes; `expect`s for the stand-out and `expect_in_front`; at most 1,500 triangles (kit).
- [ ] `tests/unit/test_kit_junction_box.gd`: the scene loads, has no script, has the `SparkAnchor` node, its meshes fit the entry's footprint and stand-out.
- [ ] The entry documents the mount (back on Z=0, faces +Z), the anchor node, and `uses`; `review/views.png` is committed.
Touches: assets/models/kit/junction_box, tools/cadkit/scenes/junction_box.py, tests/unit/test_kit_junction_box.gd
Blocked by: none
Size: XS

### Arc 8: M12.? · electrical_station panel
Scope: Assemble the board from the brief: a tall flat board, back on Z=0, controls toward +Z, from knee to head height (about 0.45 to 1.75 m) and at most 1.2 x 0.45 m. From the top: the generator section (guarded START/STOP with `GeneratorLink`, RUNNING lamp, HEAT gauge), the 3 x 3 breaker grid (nine `breaker_module`s with `circuit` and `label` set here: MOTOR, THRUSTERS, BILGE PUMP, CABIN LTS, EXT LTS, SONAR, FANS, HELM, DISPLAYS), the spares drawer, the battery bar down the right edge with the analogue LOAD meter (`gauge`, red zone) beside it, orange grab rails either side, engraved label plates, cable-tray stubs leaving the top. Everything is a palette swatch; the cyan band is not used. No new scripts: `readout`, `source_group` and the like are set on the instances. Also commits `brief.yaml` (from this issue) and `breakdown.md` (from the approved proposal), and writes `review/cameras.json` (a camera per concept image, the operator's eye under white and red light, orthographic front and profile).
Acceptance:
- [ ] `cadkit build` passes with `expect`s for: size (at most 1.2 m wide, 0.45 m deep, knee to head height), no part behind the mount face, sight lines from `operator_eye_m` to every lamp, the battery bar and the LOAD meter, grab boxes apart, and a total of at most 4,000 triangles.
- [ ] Reach: every control (the nine breakers, the generator switch) is within `reach_m` of <the measuring point chosen in the answer to open question 1>, and the spares drawer is in view of the eye. The build `expect`s and the Godot test both check it.
- [ ] `tests/unit/test_panel_electrical_station.gd`: nine breakers with the right circuit names and labels, the generator toggle with `GeneratorLink`, RUNNING lamp and HEAT gauge, battery `linear_gauge` set `descending`, LOAD `gauge` with a red zone, the drawer with 4 slots, the reach and sight checks above, displays face the eye.
- [ ] The lamps and the battery bar read under the red cabin light (checked in the red-light render).
- [ ] `review/views.png` and `*_vs_concept.png` (from `camera: concept_primary` and `concept_load_meter`) are committed.
Touches: assets/models/panels/electrical_station, tools/cadkit/scenes/electrical_station.py, tests/unit/test_panel_electrical_station.gd
Blocked by: Arc 1, Arc 4, Arc 5, Arc 6, #503
Size: M
Look gate: yes
Playtest: how the state read feels from the aisle (handle plus lamp, amber against off) and how chunky the toggles feel to click.

### Arc 9: M12.? · Place the electrical station in the sub
Scope: Replace today's starboard `Engineering` stub (it holds only `EngineGauge`) in `src/sub/interior.tscn` with the panel, at `program.yaml` `engineering` (starboard, z 2.3, across from life support). Wire it to `PowerSystem`: set `source_group` on the gauges and the lamp, and the `ThresholdLamp` on `generator_running` for RUNNING (each module's `circuit` is already set by Arc 8). Instance `junction_box` at #543's junction box nodes. Mount the emergency light fixtures on the wall above, on the nodes #545 drives (check what #545 provides first, and build only what is missing). Re-home the engine gauge if something else uses it.
Acceptance:
- [ ] `tests/unit/test_electrical_station_placement.gd`: the panel is at the program position and clears the aisle (the footprint check); every breaker, the generator and the readouts are bound to the `PowerSystem` in the interior; a junction box sits at each of #543's nodes; the emergency light fixtures exist where #545 expects them.
- [ ] `tools/check.sh` passes, including the three-instance autotest.
Touches: src/sub, tests/unit/test_electrical_station_placement.gd
Blocked by: Arc 7, Arc 8, #543, #545
Size: M
Playtest: switching the nine breakers in order for silent running, resetting a trip, swapping a blown module, and whether the aisle feels clear.

### Design doc
None. The *Power and electrics* section already records the station (Decision #533).

### Open questions
1. **(approval)** `reach_m: 0.75` is measured, as on life support and the other briefs, from the standing eye (`operator_eye_m` [0.0, 0.55, 0.5], 1.65 m above the floor). With the eye 0.5 m from the board that reaches only controls 0.55 m or less below the eye, i.e. above about 1.05 m high. The grid's lower rows and the generator are around 0.85 to 1.5 m, so some breakers fail it, and the spares drawer (about 0.45 to 0.7 m) fails it clearly. Options: (a) **recommended:** measure reach for the controls from the shoulder, 0.25 m below the eye (about 1.4 m high), and make the drawer a display (the replace control is the blown breaker itself) that only has to be in view from the eye; (b) raise `reach_m` to about 1.2 m from the eye; (c) lift the board so its lower edge is higher, which cuts into the knee-to-head height. Without an answer, Arc 8's reach check would fail or be quietly loosened.

### Discovered work
- `src/power` does not exist yet; M14 (#541, #542, #543, #545) is the dependency, nothing to file.
- This is the first scene in the `panels` group. If `cadkit` has a gap there (cameras, `operator_eye_m` checks), Arc 8 should file it rather than work around it.
