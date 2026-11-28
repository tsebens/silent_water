class_name DecoyBuoy
extends Node3D
## A launched decoy in the water. It instances the `decoy` scene for its look only
## (the [DecoyItem] in it cannot be picked up), travels [member travel_m] out from
## its exit point along [member direction] over [member travel_s], then hangs there
## for the rest of the dive: a continuous [SoundEmitter] of the `decoy` sound type
## and a DECOY pin on the [MapModel].
##
## Replication: [method attach] puts a [MultiplayerSpawner] beside a [LaunchTube];
## when the host's tube fires, the spawner makes one buoy on every peer from the
## same data (origin, direction), and each peer plays the same deterministic
## motion. Only the host emits sound events and owns the pin.

const DECOY_SCENE: PackedScene = preload("res://assets/models/furniture/decoy/decoy.tscn")
const SOUND: SoundType = preload("res://src/noise/sound_types/decoy.tres")
const SPAWNER_NAME: String = "DecoyBuoySpawner"

## Distance the buoy travels from its exit point (m).
@export var travel_m: float = 4.0
## Seconds the trip takes (eased out).
@export var travel_s: float = 3.0
## World direction of travel (normalised on use).
@export var direction: Vector3 = Vector3.FORWARD
## Unset: the node named DiveDirector in the scene. The buoy goes when the dive resets.
@export var director: DiveDirector
## Tests: act as the host without a multiplayer peer.
var simulate_host: bool = false

var origin: Vector3 = Vector3.ZERO
var emitter: SoundEmitter = null
var item: DecoyItem = null
var pin_id: int = -1

var _t: float = 0.0
var _pin_chart: MapModel = null


## Wires [param tube] so that firing it (on the host) puts a buoy in the water on
## every peer, as a child of [param parent]. Call on every peer, same parent.
## [param dir_node], if given, sets the travel direction (its -Z, in world space).
static func attach(tube: LaunchTube, parent: Node, dir_node: Node3D = null) -> MultiplayerSpawner:
	var sp: MultiplayerSpawner = parent.get_node_or_null(SPAWNER_NAME) as MultiplayerSpawner
	if sp == null:
		sp = MultiplayerSpawner.new()
		sp.name = SPAWNER_NAME
		sp.spawn_function = Callable(DecoyBuoy, "_make")
		parent.add_child(sp)
		sp.spawn_path = sp.get_path_to(parent)
	tube.fired.connect(func(at: Vector3) -> void:
		var dir: Vector3 = Vector3.FORWARD
		if dir_node != null:
			dir = -(dir_node.global_transform.basis.z if dir_node.is_inside_tree() else dir_node.transform.basis.z)
		if tube._is_host():
			sp.spawn({"origin": at, "dir": dir, "host": tube.simulate_host}))
	return sp


static func _make(data: Variant) -> Node:
	var d: Dictionary = data as Dictionary
	var b: DecoyBuoy = DecoyBuoy.new()
	b.origin = d["origin"]
	b.direction = d["dir"]
	b.simulate_host = bool(d.get("host", false))
	return b


func _ready() -> void:
	add_to_group(&"decoy_buoys")
	item = DECOY_SCENE.instantiate() as DecoyItem
	if item != null:
		item.pickable = false
		var grab: Node = item.get_node_or_null("Grab")
		if grab != null:
			grab.queue_free()
		add_child(item)
	emitter = SoundEmitter.new()
	emitter.sound_type = SOUND
	emitter.active = true
	add_child(emitter)
	global_position = origin
	_orient()
	if director == null:
		director = get_tree().root.find_child("DiveDirector", true, false) as DiveDirector
	if director != null:
		director.dive_reset.connect(queue_free)
	if _is_host():
		var chart: MapModel = get_tree().get_first_node_in_group(&"map_model") as MapModel
		if chart != null:
			_pin_chart = chart
			chart.add_pin(hang_position(), MapModel.Kind.DECOY)
			if not chart.pins.is_empty():
				pin_id = int(chart.pins.back()["id"])
	_apply()


func _exit_tree() -> void:
	if _pin_chart != null and is_instance_valid(_pin_chart) and pin_id >= 0 and _is_host():
		_pin_chart.remove_pin(pin_id)
	pin_id = -1


func _physics_process(delta: float) -> void:
	if _t < travel_s:
		_t = minf(_t + delta, travel_s)
		_apply()


func is_hanging() -> bool:
	return _t >= travel_s


## The point the buoy hangs at.
func hang_position() -> Vector3:
	return origin + _dir() * travel_m


## Moves the buoy [param delta] seconds along its trip (tests; the physics tick does it too).
func advance(delta: float) -> void:
	_t = clampf(_t + delta, 0.0, travel_s)
	_apply()


func _dir() -> Vector3:
	return direction.normalized() if direction.length() > 0.0001 else Vector3.FORWARD


func _apply() -> void:
	var k: float = 1.0 if travel_s <= 0.0 else _t / travel_s
	var eased: float = 1.0 - (1.0 - k) * (1.0 - k)
	global_position = origin + _dir() * travel_m * eased
	if emitter != null:
		emitter.world_position = global_position
		# Always on, host-side events only (the host owns acoustics).
		emitter.active = true
		emitter.field_events = _is_host()


func _orient() -> void:
	var d: Vector3 = _dir()
	if absf(d.dot(Vector3.UP)) < 0.999:
		look_at(origin + d, Vector3.UP)


func _is_host() -> bool:
	return simulate_host or (is_inside_tree() and multiplayer.is_server())
