class_name ScienceBay
extends Node3D
## One bay of the science station. Holds at most one [ScienceModule], built from its [ModuleLoadout] slot.

## The fitted module, or null for an empty bay.
var module: ScienceModule = null


func is_empty() -> bool:
	return module == null


## Fits a module of type [param t] (replacing any fitted one); [constant ModuleLoadout.Type.NONE] empties the bay.
func fit(t: int) -> ScienceModule:
	if module != null:
		if module.module_type == t:
			return module
		remove_child(module)
		module.queue_free()
		module = null
	if t != ModuleLoadout.Type.NONE:
		match t:
			ModuleLoadout.Type.SCAN:
				module = ScanModule.new()
			ModuleLoadout.Type.SWEEP:
				module = SweepModule.new()
			ModuleLoadout.Type.CAMERA:
				module = CameraModule.new()
			_:
				module = ScienceModule.new()
		module.module_type = t
		module.name = ModuleLoadout.type_name(t).capitalize()
		add_child(module)
	return module
