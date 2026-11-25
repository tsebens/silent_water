@tool
extends EditorScenePostImport
## Shared post-import script for every asset GLB (see docs/asset_pipeline.md and docs/palette.md).
## Surfaces named after a palette role get the shared role material; the rest show their vertex colours.
## Godot imports glTF vertex colours but does not apply them to the albedo by
## default; this turns that on for every material in the imported scene, and
## gives untextured surfaces a material that shows them.


func _post_import(scene: Node) -> Object:
	VertexColorFix.apply(scene)
	return scene
