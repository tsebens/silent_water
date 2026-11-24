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

The importer is `tools/kit/onshape_import_bpy.py`, run in headless Blender:

```
blender -b --factory-startup --python-exit-code 1 -P tools/kit/onshape_import_bpy.py -- \
    assets/media/kit/<part>/<part>.gltf assets/models/kit/<part>/<part>.glb <moving part name>
```

It does the following:
- puts the origin at the centre of the back face
- puts the moving part under a `Pivot` node on its hinge, with no rotation
- welds the CAD mesh and dissolves coplanar faces
- flat-shades the mesh
- writes the GLB

The part's Godot scene (`<part>.tscn`) sets the control script, for example `SwitchLever` with `swing_deg`, and a
grab box on collision layer 2.

## Parts

| Part | Moving part | Limits | Triangles (in → out) |
| --- | --- | --- | --- |
| `toggle_switch` | `Switch` (bat), revolute about X | ±40° from upright (`swing_deg` 80) | 4,060 → 3,190 (knurls removed; grip texture later) |
