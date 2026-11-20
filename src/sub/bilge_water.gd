class_name BilgeWater
extends MeshInstance3D
## Standing water on the interior floor. A flat surface at the height from
## SubPhysicsModel.bilge_height_m(bilge_water_t), hidden when dry. It is a
## child of the still interior, so it does not slosh with hull motion. Purely
## client-side: it reads the replicated tonnage from the `sub_readouts` node.

const HULL_RADIUS: float = 1.86
const HULL_AXIS_Y: float = 0.98
## Rise/fall smoothing (1/s), so leaks and the pump move the surface smoothly.
const RESPONSE: float = 4.0

## Floor level in the interior frame (cabin floor is y = 0).
@export var floor_y: float = 0.0
@export var source_group: StringName = &"sub_readouts"

## Tonnage currently shown.
var water_t: float = 0.0
var _source: Node


func _ready() -> void:
	set_tonnage(0.0)


func _process(delta: float) -> void:
	if _source == null or not is_instance_valid(_source):
		_source = get_tree().get_first_node_in_group(source_group)
		if _source == null:
			return
	var target: float = float(_source.call(&"readout", &"bilge_water_t"))
	set_tonnage(lerpf(water_t, target, 1.0 - exp(-RESPONSE * delta)))


## Sets the shown tonnage immediately: height, visibility and hull clip.
func set_tonnage(tonnes: float) -> void:
	water_t = maxf(tonnes, 0.0)
	var h: float = SubPhysicsModel.bilge_height_m(water_t)
	position.y = floor_y + h
	visible = h > 0.0005
	var mat: ShaderMaterial = material_override as ShaderMaterial
	if mat != null:
		# The node sits at the floor + h, so the hull axis is that far below it.
		mat.set_shader_parameter(&"clip_axis_y", HULL_AXIS_Y - position.y)


## Height of the surface above the floor.
func height_m() -> float:
	return position.y - floor_y
