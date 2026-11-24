# CAD spike: AI-authored parametric kit parts

Experimental (issue #343). An AI agent writes a **build123d** script per part; the script exports an Onshape-shaped
glTF that the existing kit route (`asset import` → `check` → `export`) accepts unchanged. Findings are in
[`docs/research/ai_code_cad_spike.md`](../../docs/research/ai_code_cad_spike.md).

```
cd tools/cad_spike
uv run python toggle_switch.py ai_toggle_switch.glb            # geometry + self-checks + GLB
cd ../asset_pipeline
uv run asset import ai_toggle_switch ../cad_spike/ai_toggle_switch.glb --pivot Switch --limits -40 40
uv run asset check ai_toggle_switch && uv run asset export ai_toggle_switch
/opt/blender/blender -b --factory-startup -P ../cad_spike/render_views.py -- \
    ../../.asset_work/ai_toggle_switch/import/i4.glb renders 384       # six views + contact sheet for critique
```

- `kitcad.py`: the kit frame and conventions (X right, Y up, Z out of the panel, back face on Z=0; a moving part is
  modelled with its hinge on local X and placed with `hinge=`), `ngon_prism` (polygonal cylinders with an explicit
  segment count, so tessellation stays low-poly), the Onshape-shaped glTF export (`occurrence of <Part>` → `<Part>`,
  materials named by RGB so the importer snaps them to `kit_palette.yaml`) and the geometric self-checks
  (`expect_one_solid`, `expect_bbox`).
- `toggle_switch.py`: the first part. Parameters at the top, one function per part, assertions before export.
- `render_views.py`: headless Blender Workbench renders (front, left, right, top, back, iso + contact sheet), about a
  second per view on CPU, for the AI to look at what it made.

Pinned to build123d 0.13.0: the API moves between minor versions (`add()` → `insert()` in 0.13) and a model's
training data is older than the installed library. `uv.lock` is committed.

## Scene assembly (#345)

`build.py` builds a tree of Godot scenes under `assets/models/spike/` from one script per scene in `components/`:
CAD solids, checks against the brief, GLBs, the `.tscn` and a catalogue entry (`component.yaml`). The build is all or
nothing. Findings: [`docs/research/scene_assembly_spike.md`](../../docs/research/scene_assembly_spike.md); draft
rules: [`docs/research/scene_assembly_policy.md`](../../docs/research/scene_assembly_policy.md).

```
uv run python build.py                # every scene, in dependency order (a few seconds)
uv run python catalogue.py            # what the breakdown step reads
cd ../.. && godot --headless --path . --import
xvfb-run -a godot --path . --rendering-driver vulkan res://tests/scene_shot.tscn -- \
    res://assets/models/spike/stations/sonar_console/sonar_console.tscn <out_dir> \
    assets/models/spike/stations/sonar_console/review/cameras.json
cd tools/cad_spike && uv run python review_sheet.py <out_dir> <sheets_dir>     # renders beside the concept
```

- `spike.py`: frames, the 60 mm panel module, catalogue entries. `tscn.py`: a small `.tscn` writer.
- `components/gauge.py` makes the solids of the game's shared `Gauge` (`src/interact/gauge.gd` preloads them).
