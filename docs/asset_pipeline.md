# Asset pipeline: Godot side

Backend usage is in [`tools/asset_pipeline/README.md`](../tools/asset_pipeline/README.md). This covers what Godot and the repo checks do with an asset.

## Vertex colours

Cleaned meshes carry a small vertex-colour palette. Godot imports glTF vertex colours but does not apply them to albedo by default. Every asset GLB therefore uses the shared post-import script `res://assets/import/vertex_color_import.gd`, which sets `vertex_color_use_as_albedo` on every material (and gives material-less surfaces one). `asset export` writes `<slug>.glb.import` selecting it (`import_script/path`); Godot fills in the remaining import settings on first import.

## `asset godot-check <slug>`

Copies the cleaned GLB to `build/asset_check/<slug>/` (git-ignored), imports it headless, and checks that every surface has `vertex_color_use_as_albedo`. It then renders three shots into the log dir (`$LOG_DIR`, `--log-dir`, else `./logs`): `<slug>_fog.png` (fog and ambient only), `<slug>_white.png` and `<slug>_red.png` (white and red light). Rendering needs a real display server; without `DISPLAY` it runs under `xvfb-run` when installed. `--no-render` skips the shots. The result is recorded in the manifest (`godot_checks`).

## `asset export <slug>`

Needs a mesh that passed `asset check`. Writes to `assets/models/<slug>/`: `<slug>.glb`, `<slug>.glb.import`, `<slug>.tscn` (an instance of the GLB), `concept/` (locked concept as `locked.<ext>`, the turnaround views and `brief.md`, with a `.gdignore`; PNGs over 2048 px are shrunk, other formats over 2048 px are an error) and `asset.yaml`.

## Repo gates (`tools/check.sh`)

- `asset_sizes`: fails on any file over 5 MB under `assets/` (`tools/check_asset_sizes.py`). Files already committed over the limit are listed in `tools/asset_size_allowlist.txt`; do not add to it.
- `export_presets`: if `export_presets.cfg` exists, every preset's `exclude_filter` must exclude `addons/asset_studio/*` and `tools/*` (`tools/check_export_presets.py`). Passes when there is no presets file. When creating presets, set `exclude_filter="addons/asset_studio/*, tools/*"` so the plugin and backend never ship with the game.
