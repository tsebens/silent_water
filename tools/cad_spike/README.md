# CAD spike: AI-authored parametric kit parts

Experimental (issue #343). An AI agent writes a **build123d** script per part; the script exports an Onshape-shaped
glTF that the existing kit route (`asset import` → `check` → `export`) accepts unchanged. Findings are in
[`docs/research/ai_code_cad_spike.md`](../../docs/research/ai_code_cad_spike.md).

```
cd tools/cad_spike
uv run python toggle_switch.py ai_toggle_switch.gltf           # geometry + self-checks + glTF
cd ../asset_pipeline
uv run asset import ai_toggle_switch ../cad_spike/ai_toggle_switch.gltf --pivot Switch --limits -40 40
uv run asset check ai_toggle_switch && uv run asset export ai_toggle_switch
/opt/blender/blender -b --factory-startup -P ../cad_spike/render_views.py -- \
    ../../.asset_work/ai_toggle_switch/import/i2.glb renders 384       # six views + contact sheet for critique
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
