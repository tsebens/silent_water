# Kit parts: Onshape sources

Raw Onshape glTF exports of the sub's kit of parts: the toggles, switches, lamps, bezels and levers that stations
are built from. The game-ready models live in `assets/models/kit/<part>/`. Godot ignores this folder
(`assets/media/.gdignore`).

## Modelling in Onshape

- **Frame.** Put the part's back face (where it sits on a panel) on the **Top plane**, centred on the origin. The
  front stands out along **+Z**, and up is **+Y**. The importer then needs no rotation.
- **Moving parts.** Each moving piece, such as a toggle's bat, is its own Part Studio, with **its origin on the
  hinge axis** and the hinge along the Part Studio's **X axis**. Build the assembly with a revolute mate. The export
  keeps each part's own frame, so the hinge arrives as the pivot. The mate itself, and its limits, are not exported:
  note the limits below.
- **Rest pose.** Leave the assembly in any pose. The importer resets the moving part to 0°, standing straight out
  of the plate.
- **Edges.** Use chamfers rather than fillets, and keep fine texture (knurling, grip ridges) shallow and sparse:
  each ridge costs triangles.
- **Colours.** Use part appearances. They come through as materials named by their RGB values.

## Exporting

Right-click the **Assembly** tab and choose Export. Set the format to GLTF, export as one file (not one per part),
at Medium resolution. Save it here as `<part>/<part>.gltf`.

## Importing

Run `asset import` in `tools/asset_pipeline/` (see `docs/asset_pipeline.md`):

```
uv run asset import <part> assets/media/kit/<part>/<part>.gltf --pivot "<moving part name>" --limits -40 40
```

It copies the export here, converts it in headless Blender with `tools/asset_pipeline/asset_pipeline/blender/onshape_import_bpy.py`
and records the result in `assets/models/kit/<part>/asset.yaml`. The conversion does the following:
- puts the origin at the centre of the back face
- puts the moving part under a `Pivot` node on its hinge, with no rotation
- welds the CAD mesh and dissolves coplanar faces
- flat-shades the mesh
- snaps the Onshape material colours to the nearest palette role (`docs/palette.md`) and names the material by it; the shared role material supplies the colour on import

`uv run asset check <part>` and `uv run asset export <part>` then write the part's Godot scene (`<part>.tscn`), with the
control script, for example `SwitchLever` with `swing_deg`, and a grab box on collision layer 2.

## Parts

| Part | Moving part | Limits | Triangles (in → out) |
| --- | --- | --- | --- |
| `toggle_switch` | `Switch` (bat), revolute about X | ±40° from upright (`swing_deg` 80) | 5,476 → 4,606; the source is now the knurl-free re-export, re-import pending (#377) |
