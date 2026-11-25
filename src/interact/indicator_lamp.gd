class_name IndicatorLamp
extends Node3D
## A display lamp bound to a bool: lit or unlit. Set it from game logic with
## [method set_lit], or bind it to a bool-valued source with [method bind].
## It has no input. The lamp mesh's emission is switched between
## [member lit_energy] and [member unlit_energy]; the colour comes from the
## material, so it follows the palette.

signal lit_changed(lit: bool)

@export var lit: bool = false:
	set(v):
		if lit == v:
			return
		lit = v
		_apply_visual()
		lit_changed.emit(lit)
## The mesh whose material emission is switched.
@export var lamp: MeshInstance3D
@export var lit_energy: float = 2.0
@export var unlit_energy: float = 0.0


func _ready() -> void:
	_apply_visual()


func set_lit(v: bool) -> void:
	lit = v


func is_lit() -> bool:
	return lit


## Follows a signal that carries a bool.
func bind(source: Object, signal_name: StringName) -> void:
	source.connect(signal_name, set_lit)


func _apply_visual() -> void:
	if lamp == null:
		return
	var mat: BaseMaterial3D = lamp.get_active_material(0) as BaseMaterial3D
	if mat == null:
		return
	mat = mat.duplicate() as BaseMaterial3D
	mat.emission_enabled = lit
	mat.emission_energy_multiplier = lit_energy if lit else unlit_energy
	lamp.material_override = mat
