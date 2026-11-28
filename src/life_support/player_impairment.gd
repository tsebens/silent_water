class_name PlayerImpairment
extends Node
## One player's bad-air state. The host runs an [ImpairmentModel] for this player
## against the shared cabin air ([LifeSupportReadouts]) and replicates
## [member impairment] and [member incapacitated] to every peer. The owning peer
## uses [member impairment] for local effects; everyone else needs only
## [member incapacitated]. Child of a [Player]; the host owns this node.

const GROUP: StringName = &"player_impairments"
const SNAPSHOT_INTERVAL: float = 0.25
const DEFAULT_PARAMS: String = "res://src/life_support/impairment_params.tres"

@export var params: ImpairmentParams
## Test seam: behave as a client even where the peer is offline (offline counts as host).
var simulate_client: bool = false
## Test seam: read the cabin air from here instead of the group's readouts.
var readouts_override: LifeSupportReadouts

## Effect strength, 0 to 1.
var impairment: float = 0.0
var incapacitated: bool = false
var model: ImpairmentModel
## Blur left after standing up (1 just after, fading to 0). Tracked on every
## peer from the replicated flag, so the owner's view can use it.
var linger_blur: float = 0.0
## Test seam (host): use this CO2 (ppm) instead of the cabin's when it is 0 or more.
var force_co2_ppm: float = -1.0
var _linger_left: float = 0.0
var _timer: float = 0.0


func _enter_tree() -> void:
	set_multiplayer_authority(1)


func _ready() -> void:
	if params == null:
		params = load(DEFAULT_PARAMS) as ImpairmentParams
	model = ImpairmentModel.new(params)
	add_to_group(GROUP)
	if is_inside_tree():
		Net.peer_joined.connect(_on_peer_joined)


## Crew id of the owning player (its peer id).
func crew_id() -> int:
	var p: Node = get_parent()
	return p.name.to_int() if p != null else 0


func _is_host() -> bool:
	return not simulate_client and (not is_inside_tree() or multiplayer.is_server())


func _online() -> bool:
	return is_inside_tree() and Net.is_online()


func _physics_process(delta: float) -> void:
	tick_linger(delta)
	if not _is_host():
		return
	var r: LifeSupportReadouts = readouts_override
	if r == null:
		r = get_tree().get_first_node_in_group(LifeSupportReadouts.GROUP) as LifeSupportReadouts
	if r == null:
		return
	var co2: float = r.co2_ppm if force_co2_ppm < 0.0 else force_co2_ppm
	var air: Array[float] = ambient_for_wearer(co2, r.cabin_o2)
	step(delta, air[0], air[1])
	if _online():
		_timer += delta
		if _timer >= SNAPSHOT_INTERVAL:
			_timer = 0.0
			_rpc_snapshot.rpc(snapshot())


## The air this player breathes: the suit's while they wear one with air in it,
## else the cabin's. Returns [co2_ppm, o2].
func ambient_for_wearer(co2_ppm: float, cabin_o2: float) -> Array[float]:
	if is_inside_tree():
		for n: Node in get_tree().get_nodes_in_group(DiveSuit.GROUP):
			var suit: DiveSuit = n as DiveSuit
			if suit.wearer() == crew_id() and suit.model != null:
				return suit.model.filter_ambient(co2_ppm, cabin_o2)
	return [co2_ppm, cabin_o2]


## Host: advance this player's model with the cabin air.
func step(delta: float, co2_ppm: float, cabin_o2: float) -> void:
	model.step(delta, co2_ppm, cabin_o2)
	impairment = model.strength
	_set_incapacitated(model.incapacitated)


## Counts the lingering blur down.
func tick_linger(delta: float) -> void:
	if incapacitated or _linger_left <= 0.0:
		return
	_linger_left = maxf(_linger_left - delta, 0.0)
	linger_blur = params.linger_blur_start * _linger_left / maxf(params.linger_blur_seconds, 0.0001)


## Sets the flag; standing up starts the lingering blur.
func _set_incapacitated(value: bool) -> void:
	if incapacitated and not value:
		linger_blur = params.linger_blur_start
		_linger_left = params.linger_blur_seconds
	elif value:
		linger_blur = 0.0
		_linger_left = 0.0
	incapacitated = value


func snapshot() -> Dictionary:
	return {"impairment": impairment, "incapacitated": incapacitated}


func apply_snapshot(snap: Dictionary) -> void:
	impairment = float(snap["impairment"])
	_set_incapacitated(bool(snap["incapacitated"]))


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(snap: Dictionary) -> void:
	apply_snapshot(snap)


func _on_peer_joined(peer_id: int) -> void:
	if _is_host() and _online():
		_rpc_snapshot.rpc_id(peer_id, snapshot())


## The crew of the dive: every [PlayerImpairment] in the tree.
class Crew:
	extends CrewIncapacitation
	var tree: SceneTree

	func _init(t: SceneTree = null) -> void:
		tree = t

	func _nodes() -> Array[PlayerImpairment]:
		var out: Array[PlayerImpairment] = []
		if tree == null:
			return out
		for n: Node in tree.get_nodes_in_group(GROUP):
			out.append(n as PlayerImpairment)
		return out

	func crew_ids() -> Array[int]:
		var ids: Array[int] = []
		for n: PlayerImpairment in _nodes():
			ids.append(n.crew_id())
		return ids

	func is_incapacitated(id: int) -> bool:
		for n: PlayerImpairment in _nodes():
			if n.crew_id() == id:
				return n.incapacitated
		return false
