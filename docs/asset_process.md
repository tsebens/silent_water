# Asset process: generated mechanical assets

**Alpha.** How Silent Water's mechanical and industrial assets are made: the sub's controls, displays, panels,
furniture and stations. Agents write parametric CAD scripts for the solids, Godot scenes assemble them, and the
development pipeline ([`process.md`](process.md)) builds a station from a brief and concept art, one scene per arc.

This document is the spec for asset work. The role prompts in `.github/agents/` point here; when a prompt and this
document disagree, this document wins. The evidence behind each rule is in
[`research/scene_assembly_spike.md`](research/scene_assembly_spike.md).

Out of scope: organic assets (creatures, terrain), which use the image-to-3D route in Asset Studio
([`asset_pipeline.md`](asset_pipeline.md)), and the hull, which is generated from `program.yaml` by a parametric script.

## 1. The split

- **CAD makes solids only.** A build script writes one GLB per rigid set: every static solid of a scene that shares
  one frame: one mesh with a surface per palette role ([`palette.md`](palette.md)). A moving part gets its own GLB, modelled in its own
  frame with its motion axis through the origin.
- **Godot scenes do the assembly.** Hinges, slides, springs and every other behaviour live in the scene's control
  script and node tree, never in a GLB. Scenes instance other scenes: base → control → panel → station → sub.
- **One build script per scene**, `tools/cadkit/scenes/<slug>.py`. It makes the scene's solids, checks them against
  its brief, and writes its GLBs, its `.tscn` and its catalogue entry into `assets/models/<group>/<slug>/`.
- **Generated files are never edited by hand.** A change is a change to the build script, followed by a rebuild. CI
  fails a pull request whose generated files differ from what their scripts make.
- **A solid that will be addressed on its own gets its own GLB now**, even while it is static: a lens a later
  behaviour will light, a needle, a cap. One mesh cannot have one of its parts lit or moved alone.
- **Low-poly by construction.** Round things are prisms with an explicit side count. Edges are chamfered, never
  filleted. **Solids name palette roles, never colours** (`Solid(shape, "control_interface")`): on import each surface
  gets the role's shared material, so a palette change reaches every asset with no rebuild. Pick roles by the
  palette's rules (orange for interaction, light grey for switches and selectors, red for buttons, yellow for large
  levers). `cadkit palette` lists them.

Frames (metres in Godot, millimetres in CAD): X right, Y up, Z out of the mount face.

| Group | What | Frame |
| --- | --- | --- |
| `kit` | Controls, displays and their shared parts | Back on Z=0, centred on the origin, front toward +Z |
| `panels` | A board of controls that mounts on something (a rail, a wall, a desk) | As a kit part: back on Z=0, centred |
| `furniture` | Seats and the like | On the floor at Y=0; an occupant faces -Z |
| `stations` | Floor-standing, with an operator's position | Floor at Y=0, back on Z=0, operator at +Z facing -Z |

## 2. The library, and scanning it

The asset library is whatever is on the branch you are working from, and it changes with every merge. **Never work
from a remembered picture of it.** Scan it at the start of every breakdown and again at the start of every build:

```
cadkit catalogue                 # everything: generated scenes, hand-built scenes, control behaviours
cadkit catalogue toggle lamp     # entries that mention every word
cadkit catalogue --json          # the full entries
```

It reads three things, fresh each time:

- every generated scene's `component.yaml` (written by its build script);
- `tools/cadkit/catalogue/existing.yaml`: hand-built scenes the game already has (the headset, the chart screen);
- the same file's `behaviours`: the control scripts an asset may use.

A catalogue entry says what a parent needs to know without opening the scene:

| Field | Why |
| --- | --- |
| `slug`, `group`, `kind`, `summary`, `tags` | Matching. Kinds are listed below |
| `scene` | What to instance |
| `behaviour`: script, values, signal, wiring | Whether it fits a function, and how the parent connects it |
| `base`, `footprint_mm`, `stand_out_mm` | Layout and clearance checks in the parent. `footprint_mm` is [X, Y] in the mount plane: the bounding box of a rectangular part, the corner-to-corner diameter of a prism or round part (so a parent may turn it). `stand_out_mm` is the furthest point from the mount face, moving parts at their extremes included |
| `extent_radii`, `depth_mm` | For parts sized per instance: the envelope as multiples of the size |
| `mount` | The frame convention, in words |
| `set_on_instance` | Exports the parent may set: the tier-1 variations (section 4) |
| `uses` | Which scenes to recheck when a shared part changes |
| `keep_clear_mm`, `panel_cutout` | What a parent must avoid or provide |
| `triangles` | The parent's budget check |
| `built_by`, `files` | The build script, and exactly which files it generates |

| Kind | What it is |
| --- | --- |
| `solid_set` | Shared static solids with no scene; parents instance the GLBs (the control base) |
| `element` | A touched part with no base of its own; mounts on a plate or a panel (a push button) |
| `control` | A touched part on a control base (a toggle, a trackball) |
| `control_group` | Several controls reused as a unit (the map keypad) |
| `display` | Shows something and is not touched, with or without a base (a gauge, a lamp) |
| `furniture` | A seat and the like; its behaviour is bound by the parent |
| `panel` | A board of controls and displays that mounts on something |
| `station` | Floor-standing, with an operator's position |

A **behaviour** is any script a generated scene needs, for a control or a display. The catalogue's `behaviours`
list is the whole of what an asset arc may use.

## 3. When something is its own scene

Make it a scene if **any** of these hold:

1. **It moves or is touched.** It needs a control script, a pivot or a grab box.
2. **It is used twice.** A second user exists, or is in the brief being built. "Another station could plausibly use
   it" is not enough: build it as a local solid and promote it on its second use. The controls catalogue (switches,
   keys, knobs, dials, trackballs, lamps) counts as used twice by default.
3. **It is tunable content**, which the design doc wants as a Resource.

Otherwise it is a **local solid** in its parent's GLB.

Refinements:

- **A reused static solid is a shared GLB, not a scene.** Parents instance the GLB directly (the control base).
- **Behaviour goes where it is decided.** A scene carries its behaviour only when it is intrinsic (a toggle is always
  a `SwitchLever`). When it depends on context (a seat is a `SonarSeat` at sonar), the scene is furniture with no
  script, and the parent binds the behaviour on a node above the instance.
- **A group of controls with no behaviour of its own is still a scene** when it is reused as a unit (the map keypad).
  It exposes its controls by node name.
- **A part needs nothing from its parent but a flat mount face.** Design it so (the trackball's ball rests on its ring
  rather than sinking into a panel hole). When that is impossible, the part declares the cutout in its entry and the
  parent's build reads it.
- **A solid that needs more than a handful of CAD operations, or blows its triangle budget, is split.**

Budgets (triangles, everything a scene instances included): kit 1,500; furniture 3,000; panels 4,000; stations
12,000. `cadkit build` fails a scene over its group's budget. A scene whose look gate approved a larger budget
records it as `triangle_budget` in its catalogue entry (the life_support station: 24,000; the navball: 10,000, #467), and that replaces the group's.

## 4. When a part needs to differ: three tiers

A request like "the same gauge, but its scale starts lower down" is answered at the cheapest tier that can express it.

| Tier | What changes | Where | Cost | Example |
| --- | --- | --- | --- | --- |
| 1. **Instance setting** | A detail the scene's script already exposes | An export set on the instance, in the parent's build script | None: no CAD, no rebuild of the part | A gauge's range, sweep, where its scale starts and stops, title, radius, colours |
| 2. **Build parameter** | The shape, for every user or for a named size | The part's build script; a named variant if both shapes must exist | Its own arc; every user is rechecked by the rebuild | A deeper bezel on every gauge; the control base in 1x1, 1x2, 2x2 |
| 3. **New scene** | The footprint, the mount or the behaviour | A new slug, usually sharing helpers with the old one | A new build script and entry | A square gauge; a linear bar meter |

- **If tier 1 can't express it but should, extend the script, don't fork the shape.** Adding an export is a small
  development arc. Its default must leave existing instances exactly as they were.
- **Anything that varies per instance must not be baked into shared geometry.** The gauge's tick marks depend on its
  sweep, so the script draws them; the bezel doesn't, so it is CAD.
- **A shared part keeps its mount and footprint when it is restyled.** A restyle that can't is tier 3.
- **A part that offers more than the brief asks for is reused as it is** ("no guard needed" still takes the guarded
  toggle). Say so in the breakdown. Only an explicit "without X" makes it a tier-2 variant.

## 5. The station brief

A station, a panel or any other composite asset enters the pipeline as a **concept issue whose body is a brief**, written by the
head developer with Tristan from the template `.github/ISSUE_TEMPLATE/station_brief.md`. The station's assembly arc
commits a copy as `brief.yaml` beside the scene.

- `summary`: what the station is, in the art direction's words.
- `concept.images`: each with its repo `path`, its `role` (primary or context), its `view` in words and a `camera`
  name for the review. **Concept art must be committed before the issue is labelled**: agents cannot fetch images
  attached to an issue. `concept.doc` if there is one.
- `concept.compare_on`: what the review may judge (massing, screen size, where controls sit and in what order, seat
  position, colour blocking). Name only things the asset itself contains: the review renders the asset alone, so
  "size relative to the rail" can't be judged unless the brief asks for that piece of rail as a context solid.
  `concept.ignore`: what it must not flag (the number, type and labels of controls; screen content; lighting mood;
  people; surroundings).
- `functions`: one entry per real game function, with its control or display, what it binds to, and whether the
  function is implemented. **Authoritative.** If the concept art draws six switches and `functions` lists one, the
  station has one.
- `constraints`: `kind` (station or panel), the frame, the triangle budget, any size limit, and where the operator
  is. Reach and sight lines are measured from the operator's eye: for a station with a seat, `seated_eye_height_m`
  above the seat; for a panel, `operator_eye_m`, the eye's position in the panel's own frame. Without one of these,
  reach and sight lines can't be checked.

A bind that follows the sub's pose as drawn (a render-space bind) names `SubFrame.render_transform()`, the
smoothed pose used for rendering this frame. `SubFrame.sub_transform` is the raw replicated pose and lags or leads what
the player sees on a client, so a brief never names it for something that must line up with the rendered sub.

Every `status:` and `binds:` in a brief is a claim about the game's code. The breakdown checks each against the code
and reports what is wrong.

Worked example: [`assets/models/stations/sonar_console/brief.yaml`](../assets/models/stations/sonar_console/brief.yaml).

## 6. The loop, stage by stage

The recursion is the pipeline's arc graph. The organization agent breaks the whole station down at once, every level,
and each new scene becomes an arc that is blocked by the arcs it depends on. Leaves build first; the station's
assembly arc builds last.

| Stage | Who | What happens |
| --- | --- | --- |
| Brief | Head developer with Tristan | The concept issue, labelled `concept` when final |
| Breakdown | Organization agent | Scans the library; maps every function; proposes the arcs (6.1) |
| Plan review | Plan-review agent | Checks the breakdown (6.2) and creates the arcs; stops for Tristan only on (approval) questions (6.3) |
| Build | Development agent, one run per arc | Scans again; builds, tests, renders (6.4) |
| **Look** | **Tristan** | On the arc that delivers what the concept asked for: approves the rendered look, or sends it back, before the PR (6.5) |
| Sync and tests | CI | `cadkit verify`, the cadkit tests, `tools/check.sh` |
| Review | Review agent | Asset checklist; compares renders with the concept where Tristan did not already approve the look (6.6); merges |
| After the merge | Tristan | Later feedback is a short follow-up concept (6.7) |

### 6.1 Breakdown (organization agent)

For each entry in `functions`, and for the station's structure, decide against a **fresh** catalogue scan:

- **reuse**: a catalogue scene fits as it is, perhaps with instance settings (tier 1);
- **variant**: a catalogue scene needs a build parameter or a named size (tier 2), which is its own arc;
- **new scene**: by the rule in section 3. Recurse: what does that scene need?
- **new behaviour**: a script the catalogue's `behaviours` lacks, for a control or a display. This is an ordinary
  development arc (game code under `src/`), and it blocks the scene that needs it. An asset arc never adds
  behaviour. Several new behaviours for one brief may share one arc when they would be chained anyway (the same
  folder under `src/`, the same `existing.yaml`) and fit one job;
- **local solid**: everything else, built inside its parent's arc.

The proposal's comment carries, before the arcs, a `### Breakdown` table: function → part → catalogue match →
decision. Then the arcs, shaped like this:

| Arc | `Touches:` | Blocked by |
| --- | --- | --- |
| A new or changed scene | `assets/models/<group>/<slug>`, `tools/cadkit/scenes/<slug>.py`, `tests/unit/test_<...>.gd` | The arcs for the scenes and behaviours it uses |
| A new behaviour | `src/...` as for any code arc, plus `tools/cadkit/catalogue/existing.yaml` | Usually nothing |
| The assembly (station or panel) | `assets/models/<stations or panels>/<slug>`, `tools/cadkit/scenes/<slug>.py`, `tests/unit/test_<station or panel>_<slug>.gd` | Every scene arc it instances |

Before proposing, check from the entries' footprints that the parts can fit the brief's size limit at all; an
assembly that cannot fit is a wasted run.

List **files** under `tools/cadkit/` and `tests/`, never the folders, so sibling arcs can run at once. Each scene
gets its own test file (`test_kit_<slug>.gd`, `test_panel_<slug>.gd`, `test_station_<slug>.gd`), and each behaviour
its own (`test_<script>.gd`); an arc never extends a test file another arc might touch. Two arcs that
both edit `tools/cadkit/catalogue/existing.yaml` are chained. Changes to the cadkit library itself
(`tools/cadkit/cadkit/`) are their own arc, and every scene arc that needs them is blocked by it.

Nothing is settled silently. `### Open questions` has two kinds, and each item says which:

- **(approval)**: Tristan must answer in a line before the arcs are created (6.3). Raise one only when building
  without the answer would waste a run. A conflict between the concept art and `functions`;
  a `status:` the code contradicts; an input the brief lacks that a check needs (an eye position, a size). An arc
  that depends on the answer says so in its acceptance list, and the answer is written into the arc when it is
  created.
- **(decision)**: a design question that outlives this asset and needs a `Decision:` issue.

Problems found along the way that belong to other code or other scenes go under `### Discovered work`, one line
each; plan review files them as issues on approval.

Placing the finished station in the sub (`src/sub/interior.tscn`, wiring it to game systems, retiring what it
replaces) is **not** part of the breakdown. It is ordinary development work with its own concept.

### 6.2 Plan review

On top of the usual checks:

- every `functions` entry is mapped to exactly one part, and nothing is added that the brief did not ask for;
- the break-off rule (section 3) is applied: nothing that moves is a local solid, nothing used once is a scene;
- no asset arc adds or changes a control script; each new behaviour has its own arc and blocks its users;
- reuse claims are true: the named catalogue scenes exist on `dev` and their entries fit;
- dependencies follow `uses`: a scene arc is blocked by the arc of every scene it instances that does not exist yet.

### 6.3 Questions for Tristan

The breakdown is **not** gated: plan review creates a station's arcs as soon as the plan passes. Tristan's gate on
assets is the look, at the end (6.5). (Changed on 2026-11-25, #422: the look is where his input is worth most.)

The one stop: a proposal with an open question marked **(approval)**.

1. Plan review posts `## Plan review: questions for Tristan` (each question numbered, with the options and the
   organizer's recommendation), removes `plan-proposed`, applies `needs-human` and assigns Tristan. That notifies
   him (`docs/process.md`, "Notifying Tristan"). No arcs exist yet.
2. Tristan answers in a comment, removes `needs-human` and re-applies `plan-proposed`. Plan review writes his answers
   into the arcs they affect and creates them.
3. To send the plan back instead, he comments, removes `needs-human` and applies `plan-rejected`; his rejections
   don't count toward the cap of two.

### 6.4 Build (development agent)

For an arc that creates or changes a generated scene:

1. **Scan.** `cadkit catalogue`. If something the arc was to create now exists, or a closer match has landed, use it
   and say so in the plan comment.
2. **Write or change the build script.** Parameters at the top, in millimetres. Take sizes of the scenes you use
   from their entries (`entry("<slug>")`), never from memory, and list them in `USES`. Write an `expect(...)` for
   every constraint of the brief or the arc that geometry can express: fits, clearances, reach, sight lines, travel
   at both ends of a motion, nothing behind a mount face (`expect_in_front`, which counts as an `expect`). Measure
   the solids (`bbox_mm`), not just the parameters. A constraint without a check is not met.
3. **Build.** `cadkit build`. It always builds the whole tree, in a staging folder, and writes nothing unless every
   scene passes, so a change to a shared part is checked against all its users. A failure names the scene and the
   check. Fix the cause; never weaken a check to pass.
4. **Test in Godot.** One test file per scene. A static part or display: it loads, has the script it should (or
   none), and its meshes fit its stated footprint and stand-out. A control: its parts are wired and it works at both
   ends of its travel. A station or panel: the wiring, every function's control present, reach and line of sight from the seated eye,
   grab boxes apart, displays facing the eye, controls working in place. `tools/check.sh` must pass.
5. **Render.** `cadkit sheet <slug>` renders the scene afresh and writes `review/views.png` beside it (and, for a station, each concept
   image beside the render from its camera). Look at the result. Fix what is plainly wrong before anyone else has to.
6. **Commit** the script, the generated files, the test and the `review/` sheets, **after** Godot has imported the
   project (`tools/check.sh` and `cadkit sheet` both do): commit each new GLB's `.import` as Godot completed it and
   each new script's `.uid`, as the existing scenes have them. In the pull request body, embed the sheets by
   commit permalink (`https://github.com/tsebens/silent_water/blob/<sha>/<path>?raw=true`).

Rules:

- **A missed leaf.** If the build needs a small scene the breakdown missed, the arc may add it in the same pull
  request when it is an `element` (no base, an existing behaviour) used only by this arc's scene. Say so in the plan
  comment and the Handoff. Anything larger, or anything needing a new behaviour, is discovered work: file it and
  escalate the arc.
- **Never change a shared part to suit one parent.** That is a tier-2 change with its own arc.
- **The functional spec outranks the concept art.** The concept governs arrangement, proportion and massing.
- An assembly arc (station or panel) also commits `brief.yaml` (from the concept issue) and `breakdown.md` (from the approved
  proposal) beside the scene, and writes `review/cameras.json` from its build script: one camera per concept image,
  the operator's eye under white and red light, and orthographic front and profile. A context solid the brief asks
  for (a piece of rail) is built as a local solid and named as context in the entry.

### 6.5 Tristan's look review

Tristan approves the look of what he asked for, before it becomes a pull request. **The level is set by the
concept**: a station brief gates the station's assembly arc and he sees the finished station; a concept for one new
button gates the button's arc and he sees the button. Leaves under a gated arc are not gated.

1. **Marking.** The organization agent writes `Look gate: yes` on the arc (or arcs, if the concept asked for several
   separate assets) that delivers what the concept asked for. Plan review checks the placement and creates that arc
   with the `look-gate` label. Tristan may add or remove `look-gate` on an arc himself before it is built.
2. **Build.** The development agent builds as in 6.4, pushes, renders the sheets from the pushed head, and posts
   `## Look review: ready for approval` on the arc: what was built, every sheet by commit permalink (for a station,
   the `*_vs_concept.png` sheets first), the check summaries, and anything it judged doubtful. Then it applies
   `look-review`, which notifies Tristan, and ends with the arc still `claimed`. No pull request yet.
3. **Tristan's answer**, given in the session the notification opens, or by hand:
   - **Approve:** a `## Look review: approved` comment (with any small notes), then remove `look-review` and add
     `look-approved`. A development run integrates `dev`, does the small notes, opens the pull request and hands it
     to review as usual.
   - **Change:** a `## Look review: changes requested` comment with numbered points, then remove `look-review` and
     add `look-changes`. A look-rework run fixes them in the build script on the same branch, re-renders and posts
     the next round. There is no round cap; each round is Tristan's.
4. **While it waits**, the arc holds its `Touches:` (overlapping arcs stay queued) but no worker slot, and the
   dispatcher never treats it as an orphan. The board shows it In review.

A point that belongs to another scene, the palette or game code is discovered work, filed and named in the next
round, never a shared part bent to suit one parent.

### 6.6 Review

For a pull request that touches generated assets, on top of the usual checks:

1. **Sync.** CI ran `cadkit verify`. No generated file was edited by hand; nothing under `assets/models/` changed
   without its build script (or a script it `uses`) changing.
2. **Checks exist.** Each constraint in the arc and the brief has an `expect` in the build script or an assertion in
   the Godot test. A build script with no checks is changes requested.
3. **Scope.** No control script added or changed in an asset arc. No shared part changed for one parent. A missed
   leaf follows the rule above.
4. **Entry.** The catalogue entry is complete enough for a parent to place the scene without opening it.
5. **Look**, from the committed `review/` sheets (open the images):
   - any scene: it reads as what it is, in the art direction's terms (modern, overbuilt, not antique), under white
     and red light; nothing floats, intersects or faces the wrong way;
   - a station: compare each `*_vs_concept.png` on the brief's `compare_on` list **only**. Differences on the
     `ignore` list are not findings. Each finding names its owner.
   - a `look-gate` arc: Tristan has approved the look (6.5). Don't re-judge it against the concept; check only that
     the committed sheets are the approved ones, or that the pull request says why they were re-rendered, and that
     nothing is plainly broken.

Routing a finding:

| Owner | Action |
| --- | --- |
| The scene this pull request builds | Changes requested, through the usual rework loop and its cap |
| Another generated scene, the palette, or game code | A new issue (discovered work); not a reason to block |
| The brief or the concept art itself | A comment on the concept issue for Tristan; not a reason to block |

On accepting a station's assembly arc, the review agent also comments on the concept issue with the sheets and the
routed findings, so Tristan sees the result in one place.

### 6.7 After the merge

Most look feedback is given at the gate (6.5). Feedback after the merge (something only seen in play, or on a scene
that was a leaf under a gated arc) is a short follow-up concept that names the asset ("the wheel is too small"). The
organization agent routes it to the scene that owns the problem, at the cheapest tier, and that concept's own arc is
gated at its level.

## 7. Tooling

`tools/cadkit/` is its own `uv` project (build123d, pinned). In the pipeline, `cadkit` is on `PATH` for the roles that
need it; locally, `uv run --project tools/cadkit cadkit ...`.

| Command | What it does |
| --- | --- |
| `cadkit catalogue [words] [--json]` | The library, read fresh |
| `cadkit check` | Build everything in staging; write nothing; non-zero if a check fails |
| `cadkit build` | The same, then write the result if every scene passed |
| `cadkit verify` | The same, then report generated files that are stale or hand-edited (CI runs this) |
| `cadkit render <slug>` | PNGs of a scene from its review cameras, into `build/renders/<slug>/` (not committed) |
| `cadkit sheet <slug>` | Review sheets in `<scene>/review/` (committed) |

A build script (`tools/cadkit/scenes/<slug>.py`) declares `SLUG`, `GROUP` (`kit`, `furniture`, `stations`), `USES`
and `build()`. There is no list of scenes: adding a scene adds files and edits none. The helpers are in
`cadkit.solids` (shapes, `expect`, GLB export), `cadkit.tscn` (the scene writer) and `cadkit.library` (paths, entries,
the panel module). Read an existing script of the same kind before writing one:

| Kind | Example |
| --- | --- |
| Shared solids | `control_base.py`, `gauge.py` |
| Element (no base) | `push_button.py` |
| Control on a base, with a moving part | `guarded_toggle.py`, `trackball.py` |
| Control group | `map_keypad.py` |
| Furniture | `operator_seat.py` |
| Station | `sonar_console.py` |

### Anatomy of a build script

```python
"""indicator_lamp: what it is, and the brief's limits in one paragraph."""
from cadkit.solids import Solid, at, box, prism, bbox_mm, expect, expect_in_front, export_solids_glb
from cadkit.library import PLATE_T_MM, base_glb, base_size_mm, entry, out_dir, quiet_noise, res, scene_path, write_entry
from cadkit.tscn import NodePath, Scene, Xform, grab_box

SLUG, GROUP = "indicator_lamp", "kit"      # SLUG is the file's name
USES: list[str] = []                       # generated scenes this one instances or reads: entry("<slug>")
BEZEL_R, BEZEL_H = 10.0, 4.0               # parameters, in millimetres

def solids() -> list[Solid]:               # shapes, then every check, before anything is written
    bezel = prism(8, BEZEL_R, BEZEL_H, chamfer_top=1.0)       # radius is to the corners
    lo, hi = bbox_mm(bezel)
    expect(hi[2] <= 10.0, f"stands {hi[2]:.1f} mm out; the brief allows 10")
    body = [Solid(bezel, "trim_black")]                        # a palette role (docs/palette.md), never a colour
    expect_in_front(body, SLUG)
    return body

def build() -> dict:
    d = out_dir(GROUP, SLUG)
    rep = export_solids_glb(solids(), d / f"{SLUG}_body.glb", "IndicatorLampBody")   # -> glb, triangles, bbox_m
    s = Scene("IndicatorLamp")             # script="res://src/..." for a behaviour; none for a static scene
    s.node("Body", instance=rep["glb"])    # a moving part: its own GLB under a pivot node at its axis
    s.write(d / f"{SLUG}.tscn")
    write_entry(GROUP, SLUG, {             # last: it lists the files this build wrote
        "kind": "element", "summary": "...", "tags": [...], "scene": res(d / f"{SLUG}.tscn"),
        "footprint_mm": [2 * BEZEL_R, 2 * BEZEL_R], "stand_out_mm": BEZEL_H,
        "mount": "back on Z=0, centred; faces +Z", "triangles": rep["triangles"]})
    return {"slug": SLUG, "triangles": rep["triangles"]}
```

For a control, add `s.set(".", noise_profile=quiet_noise(s), pivot=NodePath("Pivot"))`, the base
(`s.node("Base", instance=base_glb(1, 2))`) and `grab_box(s, ".", size_m, centre_m)`. Shapes are build123d objects:
combine with `+` and `-`, move with `at(shape, x, y, z, rx, ry, rz)`.

Rendering uses Godot (`$GODOT`, else `godot`) with the Vulkan renderer, under `xvfb-run` when there is no display.
The game's tests need only Godot: the GLBs are committed.

## 8. Milestones

- Changes to this process, to cadkit or to the role prompts: **M11 · CAD asset process**.
- Stations and other content built with the process: the open content milestone, **M12 · Sub interior stations**.
  The organization agent uses it for **every** arc of a concept that carries a brief, the behaviour arcs included,
  and does not escalate for want of a milestone. The dispatcher closes a milestone once all its sub-issues are
  closed, so M12 may be closed between stations; plan review reopens it when it files the next station's arcs.

## 9. Known limits of the alpha

- None of this has run on a GitHub runner yet: the cadkit environment, rendering under Xvfb, and the CI sync check.
- `cadkit verify` accepts a GLB that differs in bytes but not in triangles per role and bounds, because
  byte-identical tessellation across machines is unproven.
- Renders show a blank chart screen (it draws only in a running game) and no figure for scale.
- The review agent judges the look from committed sheets; it does not re-render.
- One station has been built with the process, by hand in one session. The first pipeline-built station is the test.
