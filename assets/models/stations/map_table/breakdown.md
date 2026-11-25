# Breakdown (approved proposal, #380)

## Plan review: approved

Approved with Tristan's answers, which are written into every arc they affect (standing operator and no seat; plain backdrop panel; decorative shelf modules allowed; knob is static decoration and `RotaryKnob` is dropped, rotation by mouse and keys; aisle clearance check; 12,000 triangle budget). All arcs are sub-issues of M12 (#354).

| Arc | Title | Blocked by |
| --- | --- | --- |
| #383 | M12.1 · Map table control behaviours | none (ready now) |
| #384 | M12.2 · Hologram display model: terrain relief and dots | none (ready now) |
| #385 | M12.3 · Hologram display model: curved back panel | #384 |
| #386 | M12.4 · pan_trackball scene | #383 |
| #387 | M12.5 · zoom_lever scene | #383 |
| #388 | M12.6 · rotary_knob and indicator_lamp scenes | #383 |
| #389 | M12.7 · map_table station (assembly) | #386, #387, #388 |
| #390 | M12.8 · Place the map table in the sub | #385, #389 |

The catalogue was re-scanned: none of the new scenes exist yet, so no arc was dropped. No `Decision:` or discovered-work issues were needed.

## Proposed breakdown

I read this as a station brief with a development arc, a display-model pair and a placement arc on top. This revision answers the three plan-review objections: the display model is split into relief (arc 2) and back panel (arc 3), the relief heights are numeric, and the rotation control's default is stated in scope instead of as a criterion. The table is a generated `map_table` station that reuses what the catalogue has (guarded toggle, noise gauge, operator seat). It needs four new kit scenes: a pan trackball, a zoom lever, a rotation knob and an indicator lamp, because the catalogue's trackball trains the hydrophone and there is no lever, knob or lamp scene. One development arc supplies the missing behaviours. A last arc places the station in the sub and rewires `MapTable`. #378 is merged and #379 is still open, so every arc is blocked by #379. #360 and #361 are not open. All arcs go under M12 (#354), which is open now.

### Breakdown
| Function / structure | Part | Catalogue match | Decision |
| --- | --- | --- | --- |
| chart_pan | desk trackball for panning | `trackball` (script `Trackball` trains the hydrophone) | new scene `pan_trackball` (shares the trackball's helpers), plus new behaviour `PanBall` |
| chart_zoom | zoom lever, spring-centred | none (`Lever` script only) | new scene `zoom_lever`, plus new behaviour `ZoomLever` |
| chart_rotate | rotation knob | none (`Valve` is a handwheel script) | new scene `rotary_knob`, plus new behaviour `RotaryKnob` (see open question 4) |
| follow_sub | guarded toggle | `guarded_toggle` (`SwitchLever`) | reuse |
| follow_sub indicator | lamp that lights | none (`guarded_toggle`'s lens is static) | new scene `indicator_lamp`, plus new behaviour `IndicatorLamp` |
| pins | mouse and keys | none needed | no part |
| table_hologram | display filling the tabletop | none | new behaviour (HoloMap relief and back panel, arcs 2 and 3); the station only leaves a mount node |
| pilot_hologram | the same model at about 20 cm | none | same arcs; its place is unchanged here |
| noise_repeater | shelf dial | `noise_gauge` | reuse (tier 1 `radius`) |
| task_lights | two work lamps on arms | none | local solid: static arms and heads with lit `lamp_cabin` faces. The `light_cabin` light nodes are added in the placement arc |
| operator_seat | seat facing the console | `operator_seat` (furniture, faces -Z) | reuse; `StationSeat` is bound by the parent in the placement arc |
| structure | D-shaped top, orange edge rail, plinth, braces, console housing, instrument shelf and its rail | none | local solids |

Local solids: table body, top, rail, plinth, braces, console housing, shelf and its rail, lamp arms.

### Arc 1: M12.? · Map table control behaviours
Scope: Four scripts, none of which exist: `PanBall` (a trackball that emits a 2D roll delta, not hydrophone bearing), `ZoomLever` (a lever that emits a spring-centred -1..1 zoom rate), `RotaryKnob` (a knob turned by circling the mouse, emitting an angle) and `IndicatorLamp` (a lit/unlit display bound to a bool). Each is registered in `tools/cadkit/catalogue/existing.yaml`. They are networked the same way as the existing controls. The `MapTable` rewiring is arc 8, not here.
Acceptance:
- [ ] Each script has a unit test (a signal fires with the expected value): `tests/unit/test_map_controls.gd` passes.
- [ ] `cadkit catalogue` lists all four behaviours.
- [ ] Existing `Trackball`, `Lever` and `Valve` behaviour is unchanged (existing tests pass).
- [ ] `tools/check.sh` passes.
Touches: src/interact, tools/cadkit/catalogue/existing.yaml, tests/unit/test_map_controls.gd
Blocked by: #379
Size: M

### Arc 2: M12.? · Hologram display model: terrain relief and dots
Scope: `HoloMap` stops drawing a 0.7 m volume and draws a low terrain relief of glowing `light_readout` contours on a dark base, with pins and contacts as small glowing dots (`light_marker` for pins, the indicator colours for contacts). The relief is configurable (size, D-shaped table or round disc) so the table (full tabletop) and the pilot's small disc (about 20 cm, heading-up, centred) both use it. The existing `HoloMap` API, and the pick/ray maths `MapTable` uses, keep working. All colours come from the palette. The back panel is arc 3.
Acceptance:
- [ ] `tests/unit/test_holo_relief.gd` passes. It builds a relief from `MapModel` and asserts the relief's maximum height is at most 0.03 m in the table configuration and at most 0.01 m in the pilot disc configuration, and that each pin maps to a marker node in `light_marker`.
- [ ] Table and pilot configurations both construct headless without errors.
- [ ] Pick/ray maths tests for `MapTable` (existing) still pass.
- [ ] No colour literals (palette test passes).
- [ ] `tools/check.sh` passes.
Touches: src/map, tests/unit/test_holo_relief.gd
Blocked by: #379
Size: M
Playtest: how the contours read from a seated eye and a standing eye, and legibility of the pilot's disc.

### Arc 3: M12.? · Hologram display model: curved back panel
Scope: A translucent, faintly glowing curved panel of light stands along the back edge of the relief, following the hull. It has no enclosure, lid or posts. It is configurable (curve radius, width, height) for the table; the pilot's disc has no panel by default. Its content follows open question 2 (default: a plain backdrop).
Acceptance:
- [ ] `tests/unit/test_holo_back_panel.gd` passes. It asserts the panel node exists in the table configuration and is absent in the pilot configuration, its width is within the table's back edge, its height is at most 0.6 m, and its material is translucent (alpha below 1).
- [ ] Panel colours come from the palette (palette test passes).
- [ ] Arc 2's relief tests still pass.
- [ ] `tools/check.sh` passes.
Touches: src/map, tests/unit/test_holo_back_panel.gd
Blocked by: Arc 2
Size: S
Playtest: whether the panel's curvature and glow read as light, not as a screen.

### Arc 4: M12.? · pan_trackball scene
Scope: A desk trackball in the kit style that uses `PanBall`. It shares the trackball's helpers and base mount, and keeps its footprint.
Acceptance:
- [ ] `cadkit build` passes, with an `expect` for each geometric constraint (ball rests on the ring, within the 116 mm footprint).
- [ ] `tests/unit/test_kit_pan_trackball.gd` passes.
- [ ] `review/views.png` is committed.
Touches: assets/models/kit/pan_trackball, tools/cadkit/scenes/pan_trackball.py, tests/unit/test_kit_pan_trackball.gd
Blocked by: Arc 1
Size: S

### Arc 5: M12.? · zoom_lever scene
Scope: A short lever on a control base that uses `ZoomLever`, with its pivot axis through the origin.
Acceptance:
- [ ] `cadkit build` passes, with an `expect` for the throw and clearance.
- [ ] `tests/unit/test_kit_zoom_lever.gd` passes.
- [ ] `review/views.png` is committed.
Touches: assets/models/kit/zoom_lever, tools/cadkit/scenes/zoom_lever.py, tests/unit/test_kit_zoom_lever.gd
Blocked by: Arc 1
Size: S

### Arc 6: M12.? · rotary_knob and indicator_lamp scenes
Scope: Two small kit parts. `rotary_knob` is a grippable knob that uses `RotaryKnob`, modelled in its own frame; the default for the rotation control is a knob, to be overridden by Tristan's answer to open question 4 at approval. `indicator_lamp` is a bezel and lens that uses `IndicatorLamp`, with `lamp` colours from the palette. They share one arc because both are small and neither touches existing code.
Acceptance:
- [ ] `cadkit build` passes for both, with an `expect` for each constraint.
- [ ] `tests/unit/test_kit_rotary_knob.gd` and `tests/unit/test_kit_indicator_lamp.gd` pass.
- [ ] `review/views.png` is committed for both.
Touches: assets/models/kit/rotary_knob, assets/models/kit/indicator_lamp, tools/cadkit/scenes/rotary_knob.py, tools/cadkit/scenes/indicator_lamp.py, tests/unit/test_kit_rotary_knob.gd, tests/unit/test_kit_indicator_lamp.gd
Blocked by: Arc 1
Size: S

### Arc 7: M12.? · map_table station (assembly)
Scope: The generated station, to round 6 and the brief: a D-shaped table (about 2.2 x 0.9 m, top at about 0.75 m) with an orange edge rail, plinth and braces, and a console jutting from the middle of the front edge. The console carries the pan trackball, zoom lever, rotary knob, guarded toggle and indicator lamp, all within 0.75 m of the operator's eye. Above the table is an orange-railed shelf holding the noise gauge (and set dressing only if question 3 allows). Two work-lamp arms are local solids. The operator seat is instanced. A mount node is left for `HoloMap` and a back-panel anchor. The station adds no scripts.
Acceptance:
- [ ] `cadkit build` passes, with `expect`s for: floor at Y=0, back on Z=0, top height, each control within `reach_m` 0.75 of the eye (1.2 m seated or 1.65 m standing per open question 1), and the table's footprint within the bay.
- [ ] Triangles are at most 12,000 including every instance, and `cadkit build` enforces this.
- [ ] `tests/unit/test_station_map_table.gd` passes: it checks the node names for each control and the mount nodes, and the seat's sit point.
- [ ] `review/views.png` is committed, including the `concept_round6_view` camera.
Touches: assets/models/stations/map_table, tools/cadkit/scenes/map_table.py, tests/unit/test_station_map_table.gd
Blocked by: Arc 4, Arc 5, Arc 6
Size: M
Playtest: how closely it matches the round 6 art.

### Arc 8: M12.? · Place the map table in the sub
Scope: Replace the old centre map table in `src/sub/interior.tscn` with the generated station at the port-bay position from `program.yaml` (#378). Rewire `MapTable` so that the trackball pans, the lever zooms, the knob rotates (rotation becomes real in `HoloMap`), and the toggle sets follow_sub. The indicator lamp tracks follow state. The key and mouse inputs keep working for pins. The seat uses `StationSeat` (or the standing point, per question 1). Both `TableHolo` and `PilotHolo` use the new display model, and the two work-lamp lights are added. The old slab and projector are removed.
Acceptance:
- [ ] `tests/unit/test_map_table_placement.gd` passes: the scene loads headless, the station is at the program position, each control changes `HoloMap` pan, zoom, rotation and follow state, and the lamp matches follow.
- [ ] The existing `test_maps.gd` and `test_palette_interior.gd` pass.
- [ ] The three-instance autotest in `tools/check.sh` passes with the table in place.
- [ ] No overlap with the walkway clearances (`program.yaml` `aisle_min_m`) in the existing sub layout checks.
Touches: src/sub, src/map, tests/unit/test_map_table_placement.gd
Blocked by: Arc 3, Arc 7
Size: M
Playtest: pan, zoom and rotate feel; whether observers can reach the tabletop to pin.

### Design doc
The map table and hologram paragraphs (the 0.7 m slab and the standing operator). The edit goes in arc 8 only if question 1 changes it; otherwise none.

### Open questions
1. **(approval)** Seated or standing operator. Default: seated, as the art shows; arc 7 uses 1.2 m eye height and arc 8 binds `StationSeat`.
2. **(approval)** The back panel's job. Default: a plain translucent backdrop, with no content, unless you want a depth profile.
3. **(approval)** Non-functional shelf modules. Default: none beyond the noise repeater, because `functions` is authoritative. A blank screen or panel blank could be allowed.
4. **(approval)** Rotation control form. Default: a knob.
5. **(approval)** The seated operator, console and seat project into the aisle beyond the 0.9 m program footprint. The brief's size limit is the footprint of the table body only. Default: the station is about 2.2 x 1.5 m including the seat, as the sonar console is 0.94 x 1.28 m. Confirm that it fits the walkway clearances at z -1.25.
6. **(approval)** The pilot's disc is only restyled and stays where it is. Its new place on the elbow rail is the cockpit concept (#328), not built yet.
7. **(approval)** Triangle budget risk. Four controls, gauge and seat at their kit maximums come to about 10,500 of the 12,000, leaving about 1,500 for the table. Arc 7 may need the local solids kept simple. Say so if you prefer a larger budget.

### Discovered work
none


## Tristan's answers: approved

Approved by Tristan on 2026-11-25, with these answers to the open questions. Each answer goes into every arc it affects. They are also recorded in `assets/models/map_table/concept/map_table_concept.md` and the design doc (PR #382).

1. **Standing operator**, so the operator and the observers share one perspective. **No seat**: do not reuse `operator_seat`.
   - Arc 7: check reach and sight lines from a **standing eye of 1.65 m**.
   - Arc 8: `MapTable` keeps its standing point.
2. **The back panel is a plain backdrop** for now (the default). Making that space useful for instruments is a later idea, so arc 3 builds it to be easy to extend but adds no content.
3. **Yes: the shelf may carry non-functional modules** as set dressing beside the noise repeater (screens, gauge clusters, switch panels). Arc 7 may build them as local solids or instance catalogue scenes without behaviour.
4. **A knob, but decoration only.** Rotation is controlled by **mouse and keyboard**.
   - Arc 1 **drops `RotaryKnob`** and builds three behaviours: `PanBall`, `ZoomLever`, `IndicatorLamp`.
   - Arc 6's `rotary_knob` is a **static, decorative scene with no script and no grab box**.
   - Arc 8 implements rotation in `HoloMap` and `MapTable`, driven by keys or the mouse. Use bindings that clash with none of today's: WASD pan, the wheel zooms, F follows, 1-4 choose a pin, click and right-click place and remove pins, E and Esc leave. Show them in the seated hint.
5. **Footprint:** with no seat, this is the console's projection only. Arc 7 checks that the whole station stays clear of the walkway: `aisle_min_m` from `assets/models/vehicles/sub_interior/program.yaml`, at the map table's position there.
6. **The pilot's disc** is restyled only and stays where it is (the default).
7. **Triangle budget:** keep 12,000 (the default). With no seat the margin is larger; keep the local solids simple anyway.

**Ordering:** #378 (the new position) and #379 (the art) have both merged, so `Blocked by: none` is right where the proposal said `#379`.

---
_Generated by [Claude Code](https://claude.ai/code)_
