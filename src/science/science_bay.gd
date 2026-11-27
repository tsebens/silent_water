class_name ScienceBay
extends Node3D
## One bay of the science station. Holds at most one [ScienceModule], built from its [ModuleLoadout] slot.

## The fitted module, or null for an empty bay.
var module: ScienceModule = null
## Module scenes by type, used when fitting into an adopted anchor (the visible, authored scene).
const MODULE_SCENES: Dictionary = {
	ModuleLoadout.Type.SCAN: "res://assets/models/kit/scan_module/scan_module.tscn",
	ModuleLoadout.Type.SWEEP: "res://assets/models/kit/sweep_module/sweep_module.tscn",
	ModuleLoadout.Type.PROBE: "res://assets/models/kit/probe_module/probe_module.tscn",
	ModuleLoadout.Type.CAMERA: "res://assets/models/kit/camera_module/camera_module.tscn",
}
## When set, modules live under this node (a bay of an authored scene) instead of under the bay itself.
var anchor: Node3D = null


## Adopts the module scene already sitting under [param node]: its [ScienceModule] child becomes this bay's module, and
## later fits swap scenes under the same anchor rather than building script-only modules.
func adopt(node: Node3D) -> void:
	anchor = node
	module = null
	for c: Node in node.get_children():
		if c is ScienceModule:
			module = c as ScienceModule
			break


func is_empty() -> bool:
	return module == null


## Fits a module of type [param t] (replacing any fitted one); [constant ModuleLoadout.Type.NONE] empties the bay.
func fit(t: int) -> ScienceModule:
	if module != null:
		if module.module_type == t:
			return module
		module.get_parent().remove_child(module)
		module.queue_free()
		module = null
	if t != ModuleLoadout.Type.NONE and anchor != null and MODULE_SCENES.has(t):
		var scene: PackedScene = load(MODULE_SCENES[t]) as PackedScene
		module = scene.instantiate() as ScienceModule
		module.module_type = t
		module.name = "Module"
		anchor.add_child(module)
	elif t != ModuleLoadout.Type.NONE:
		match t:
			ModuleLoadout.Type.SCAN:
				module = ScanModule.new()
			ModuleLoadout.Type.SWEEP:
				module = SweepModule.new()
			ModuleLoadout.Type.PROBE:
				module = ProbeModule.new()
			ModuleLoadout.Type.CAMERA:
				module = CameraModule.new()
			_:
				module = ScienceModule.new()
		module.module_type = t
		module.name = ModuleLoadout.type_name(t).capitalize()
		add_child(module)
	return module
