# Draft policy: building composite assets from scenes

Draft from the scene-assembly spike (#345), written to be folded into
[`docs/roles/graphic_designer.md`](../roles/graphic_designer.md) once Tristan accepts it. The evidence for each rule
is in [`scene_assembly_spike.md`](scene_assembly_spike.md).

## The split

- **CAD makes solids only.** A build script writes one GLB per rigid set: every static solid of a scene that shares
  one frame, several palette colours allowed (as vertex colours). A moving part gets its own GLB, modelled in its own
  frame with its motion axis through the origin.
- **Godot scenes do the assembly.** Hinges, slides, springs and every other behaviour live in the scene's control
  script and node tree, never in a GLB. glTF carries no mates.
- **One build script per scene.** It makes the scene's solids, checks them against the brief, writes its GLBs, its
  `.tscn` and its catalogue entry, and writes nothing if any check fails.

## When something is its own scene

Make it a scene if **any** of these hold:

1. **It moves or is touched.** It needs a control script, a pivot or a grab box.
2. **It is used twice.** A second user exists, or is in a brief being built now. "Another station could plausibly use
   it" is not enough: build it local and promote it on its second use (the rule of two). The controls catalogue
   (switches, keys, knobs, dials, trackballs, lamps) counts as used twice by default.
3. **It is tunable content**, which the design doc wants as a Resource.

Otherwise it is a local solid in its parent's GLB.

Refinements:

- **A reused static solid is a shared GLB, not a scene.** Parents instance the GLB directly (the control base).
- **Behaviour goes where it is decided.** A scene carries its behaviour only when the behaviour is intrinsic (a
  toggle is always a `SwitchLever`). When it depends on context (a seat is a `SonarSeat` at sonar and a
  `StationSeat` elsewhere), the scene is furniture with no script, and the parent binds the behaviour on a node above
  the instance.
- **A group of controls with no behaviour of its own is still a scene** when it is reused as a unit (the map keypad).
  It exposes its controls by node name.
- **A component needs nothing from its parent but a flat mount face.** Design it so (the trackball's ball rests on its
  ring rather than sinking into a panel hole). When that is impossible, the component declares the cutout in its
  catalogue entry and the parent's build reads it.

## What the asset agent may not do

- **Add behaviour.** A control that needs a script the catalogue lacks is blocked by a development arc for that script.
- **Change a shared component to suit one parent.** That is a change to the component, with its own issue, and the
  whole tree is rebuilt and rechecked.
- **Overrule the functional spec.** Which controls exist and what they do comes from the brief's `functions`, not
  from the concept art.
- **Fix out-of-scope findings.** A review finding owned by game code, the palette or another scene is filed as an
  issue against that owner.

## The loop, per level

1. **Read** the brief and the final goal; note which level this is.
2. **Match** each function against the catalogue: reuse, variant (same design, new parameters; a new slug if the
   footprint or behaviour changes), new scene, new behaviour (a development arc), or local solid. Write the result as
   `breakdown.md`. At the top level the human approves it.
3. **Recurse** into each new scene, leaves first.
4. **Build** this level's local solids and assemble its scene from the catalogue entries' footprints, mount frames
   and wiring.
5. **Check:** the build script's geometric checks, then a headless Godot test (wiring, reach and line of sight from
   the seated eye, grab boxes apart, displays facing the eye, controls working in place).
6. **Render** from the brief's concept viewpoints and the operator's eye, under white and red light.
7. **Review** against the concept (stations and anything with concept art): at most two rounds, then route the rest.
8. **Rebuild the whole tree** after any change to a shared part. It takes seconds, and unchanged scenes come out
   byte-identical.

## The station brief

Written or approved by the human; the agent fills the rest.

- `summary`: what the station is, in the art direction's words.
- `concept`: images with their role (primary or context) and viewpoint, the concept doc, and two lists: `compare_on`
  (massing, screen size, where controls sit and in what order, seat position, colour blocking) and `ignore` (control
  count, type and labels; screen content; lighting mood; people; surroundings).
- `functions`: one entry per real game function, with its control or display, what it binds to, and whether the
  function is implemented yet. **Authoritative.**
- `constraints`: frame, seated eye height, reach, triangle budget, palette.

## The catalogue entry

Every generated scene writes `component.yaml`; hand-built game scenes and behaviours are listed in one file beside
them. Fields the spike needed:

| Field | Why |
| --- | --- |
| `slug`, `kind`, `summary`, `tags` | Matching (kinds: solid_set, element, control, control_group, furniture, display, station) |
| `scene` | What to instance |
| `behaviour`: script, values, signal, wiring | Whether it fits a function, and how the parent connects it |
| `base`, `footprint_mm`, `stand_out_mm` | Layout and clearance checks in the parent |
| `mount` | The frame convention, in words |
| `set_on_instance` | Exports the parent sets (label, radius...) |
| `uses` | What to recheck when a shared part changes |
| `keep_clear_mm`, `panel_cutout` | What a parent must avoid or provide |
| `triangles` | The parent's budget check |
