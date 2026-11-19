class_name CabinLights
extends Node
## Interior lighting: the dimmer lever sets the level for every cabin light,
## and threat cues add flicker on top. The headlight is not a cabin light
## and is left alone.

## Lowest level the dimmer reaches: near dark, controls still faintly visible.
const MIN_LEVEL: float = 0.03

@export var lights_root: Node3D
@export var dimmer: Interactable
## Lights the dimmer doesn't touch (the headlight).
@export var excluded: Array[Light3D] = []

## Multiplier from threat cues; 1.0 = steady. Per-light, by instance id.
var flicker: Dictionary = {}

var _base: Dictionary = {}
## Glowing strip materials and their full emission energy.
var _strips: Dictionary = {}


func _ready() -> void:
	add_to_group(&"cabin_lights")
	for l: Light3D in cabin_lights():
		_base[l.get_instance_id()] = l.light_energy
	if lights_root != null:
		for n: Node in lights_root.get_children():
			var mi: MeshInstance3D = n as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var mat: StandardMaterial3D = mi.mesh.surface_get_material(0) as StandardMaterial3D
			if mat != null and mat.emission_enabled:
				# Own copy so dimming doesn't touch other users of the material.
				mat = mat.duplicate() as StandardMaterial3D
				mi.material_override = mat
				_strips[mat] = mat.emission_energy_multiplier


func cabin_lights() -> Array[Light3D]:
	var out: Array[Light3D] = []
	if lights_root == null:
		return out
	for n: Node in lights_root.get_children():
		var l: Light3D = n as Light3D
		if l != null and not excluded.has(l):
			out.append(l)
	return out


## Current dimmer level, MIN_LEVEL..1.
func level() -> float:
	var v: float = dimmer.get_normalized() if dimmer != null else 1.0
	return lerpf(MIN_LEVEL, 1.0, v)


func _process(_delta: float) -> void:
	var lvl: float = level()
	for l: Light3D in cabin_lights():
		var id: int = l.get_instance_id()
		l.light_energy = float(_base.get(id, l.light_energy)) * lvl * float(flicker.get(id, 1.0))
	for mat: StandardMaterial3D in _strips:
		mat.emission_energy_multiplier = float(_strips[mat]) * lvl
