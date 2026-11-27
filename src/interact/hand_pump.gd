class_name HandPump
extends Interactable
## Manual bilge pump worked by occupying a lever. Holding the lever is the down
## stroke; releasing springs it back; a refill beat follows before the next
## stroke can start. A full cycle is DOWN + SPRING + REFILL = 1.5 s and removes
## [constant TONNES_PER_STROKE] of bilge water through the leak system's
## `manual_bail`, so steady work averages about 0.035 t/s. It needs no power
## and makes no noise.
##
## Host-authoritative: the host runs the cycle from the lever's holder and
## streams the value; clients only display it. Holding is the existing grab.

enum Phase { IDLE, DOWN, SPRING, REFILL }

## Down stroke at full travel (s), spring back (s), refill beat (s).
const DOWN_SEC: float = 0.6
const SPRING_SEC: float = 0.4
const REFILL_SEC: float = 0.5
const CYCLE_SEC: float = DOWN_SEC + SPRING_SEC + REFILL_SEC
## Steady removal rate (t/s) and the water one full stroke moves.
const STEADY_FLOW: float = 0.035
const TONNES_PER_STROKE: float = STEADY_FLOW * CYCLE_SEC

## Node with `manual_bail(tonnes)` (a [LeakSystem]). Unset: the first node in
## the leak_system group.
@export var leaks: Node
@export var pivot: Node3D
@export var swing_deg: float = 50.0

var phase: Phase = Phase.IDLE
var _refill_left: float = 0.0


func _init() -> void:
	super._init()
	min_value = 0.0
	max_value = 1.0
	initial_value = 0.0


func _ready() -> void:
	super._ready()
	if leaks == null and is_inside_tree():
		leaks = get_tree().get_first_node_in_group(&"leak_system")


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if multiplayer.is_server():
		step(delta, state.holder != InteractableState.NO_HOLDER)


## Host: advances the cycle by `delta` s with the lever `held` or not.
func step(delta: float, held: bool) -> void:
	var v: float = state.value
	match phase:
		Phase.IDLE:
			if held:
				phase = Phase.DOWN
		Phase.DOWN:
			if not held:
				phase = Phase.SPRING
			else:
				var nv: float = minf(v + delta / DOWN_SEC, 1.0)
				_bail((nv - v) * TONNES_PER_STROKE)
				_set_stroke(nv)
				if nv >= 1.0:
					phase = Phase.SPRING
		Phase.SPRING:
			var nv: float = maxf(v - delta / SPRING_SEC, 0.0)
			_set_stroke(nv)
			if nv <= 0.0:
				phase = Phase.REFILL
				_refill_left = REFILL_SEC
				host_set_value(0.0)
		Phase.REFILL:
			_refill_left -= delta
			if _refill_left <= 0.0:
				phase = Phase.IDLE


func _bail(tonnes: float) -> void:
	if leaks == null and is_inside_tree():
		# The leak system comes later in the tree than a panel instanced in the interior, so it had not joined its group at _ready.
		leaks = get_tree().get_first_node_in_group(&"leak_system")
	if tonnes > 0.0 and leaks != null and leaks.has_method(&"manual_bail"):
		leaks.call(&"manual_bail", tonnes)


func _set_stroke(v: float) -> void:
	state.set_value_silent(v)
	_after_change()
	_rpc_value_stream.rpc(v)


## The lever moves only by the host's cycle; a holder's requested values are ignored.
func _host_apply(_sender: int, _v: float, _silent: bool = false) -> void:
	pass


## Clients display whatever the host streams, held or not.
func _receive_value(v: float, _authoritative: bool) -> void:
	_set_local(v, true)


func _drag_to_value(current: float, _relative: Vector2) -> float:
	return current


func _apply_visual(v: float) -> void:
	if pivot != null:
		pivot.rotation.x = deg_to_rad(lerpf(-swing_deg * 0.5, swing_deg * 0.5, v))


func interaction_hint() -> String:
	return "hold to pump, release and repeat"
