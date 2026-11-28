class_name DemolitionBlast
extends Node
## Host-side consequence of a [DemolitionObjective] detonating. One very loud [SoundEvent] goes out through
## [Acoustics] (raw linear intensity, summed with everything else as intensity, never dB) and attracts threats.
## Everything in [member targets] within [member blast_radius_m] of [member blast_position] takes damage that
## falls off linearly with distance, reported through [signal target_damaged]. The sub is hurt only when it is
## inside the radius ([signal sub_damaged]). Numbers are placeholders, tuned by playtest.

signal target_damaged(target: Node3D, amount: float)
signal sub_damaged(amount: float)
signal blasted(intensity: float)

## About 140 dB at 1 m: far louder than anything else in the game.
const BLAST_DB: float = 140.0
const KIND: StringName = &"explosion"

@export var objective: DemolitionObjective:
	set(value):
		if objective != null and objective.detonated.is_connected(detonate):
			objective.detonated.disconnect(detonate)
		objective = value
		if objective != null:
			objective.detonated.connect(detonate)
## Distance from the blast centre (m) beyond which nothing is hurt.
@export var blast_radius_m: float = 60.0
## Damage at the centre; zero at the radius.
@export var max_damage: float = 100.0
## Damage the sub takes at the centre, when it is inside the radius.
@export var sub_max_damage: float = 50.0
@export var blast_position: Vector3 = Vector3.ZERO
## Players and other things that can be caught in the blast.
var targets: Array[Node3D] = []
## World position of the sub. Tests set it; otherwise the sub frame is used.
var sub_position_override: Variant = null

var has_blasted: bool = false


## Linear intensity of the blast at 1 m.
static func blast_intensity() -> float:
	return NoiseLevel.from_db(BLAST_DB)


## 0..1: full at the centre, none at and beyond the radius.
func falloff(dist: float) -> float:
	return clampf(1.0 - dist / maxf(blast_radius_m, 0.001), 0.0, 1.0)


func damage_at(dist: float) -> float:
	return max_damage * falloff(dist)


func sub_damage_at(dist: float) -> float:
	return sub_max_damage * falloff(dist)


func sub_position() -> Vector3:
	if sub_position_override != null:
		return sub_position_override as Vector3
	if is_inside_tree():
		var frame: SubFrame = get_tree().get_first_node_in_group(&"sub_frame") as SubFrame
		if frame != null:
			return frame.sub_transform.origin
	return Vector3.ZERO


## Host only, once. Sends the noise event and applies damage. Returns the number of detectors that heard it.
func detonate() -> int:
	if has_blasted or (is_inside_tree() and not multiplayer.is_server()):
		return 0
	has_blasted = true
	var heard: int = Acoustics.emit_raw(blast_position, blast_intensity(), KIND, self)
	blasted.emit(blast_intensity())
	for t: Node3D in targets:
		if not is_instance_valid(t):
			continue
		var d: float = (t.global_position if t.is_inside_tree() else t.position).distance_to(blast_position)
		var dmg: float = damage_at(d)
		if dmg > 0.0:
			target_damaged.emit(t, dmg)
	var sub_dmg: float = sub_damage_at(sub_position().distance_to(blast_position))
	if sub_dmg > 0.0:
		sub_damaged.emit(sub_dmg)
	return heard
