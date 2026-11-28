class_name DiveSuit
extends Wearable
## A dive suit the player puts on and takes off with the interact path (E).
## Worn, it slows walking, narrows the view and breathes its own air (see
## [DiveSuitModel]); empty, it stops protecting. The host steps the air and
## replicates it; who wears it is the control's holder, which already replicates.
## A suit stays on however far its wearer walks.

const GROUP: StringName = &"dive_suits"
const SNAPSHOT_INTERVAL: float = 0.25
const DEFAULT_PARAMS: String = "res://src/life_support/dive_suit_params.tres"

@export var params: DiveSuitParams
## True where the suit refills when it is off (a dive locker's air line).
@export var refilling: bool = false
## Test seam: behave as a client even where the peer is offline.
var simulate_client: bool = false

var model: DiveSuitModel
var _timer: float = 0.0


func _init() -> void:
	super._init()
	cord_length = 1.0e9


func _ready() -> void:
	super._ready()
	if params == null:
		params = load(DEFAULT_PARAMS) as DiveSuitParams
	model = DiveSuitModel.new(params)
	add_to_group(GROUP)
	holder_changed.connect(_on_holder)


## Peer wearing the suit, or [constant InteractableState.NO_HOLDER].
func wearer() -> int:
	return state.holder


func is_worn() -> bool:
	return model != null and model.worn


func _is_host() -> bool:
	return not simulate_client and (not is_inside_tree() or multiplayer.is_server())


func _on_holder(peer_id: int) -> void:
	model.set_worn(peer_id != InteractableState.NO_HOLDER)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not _is_host():
		return
	model.set_worn(state.holder != InteractableState.NO_HOLDER)
	model.step(delta, refilling)
	if is_inside_tree() and Net.is_online():
		_timer += delta
		if _timer >= SNAPSHOT_INTERVAL:
			_timer = 0.0
			_rpc_snapshot.rpc(snapshot())


func snapshot() -> Dictionary:
	return {"worn": model.worn, "air": model.air}


func apply_snapshot(snap: Dictionary) -> void:
	model.set_worn(bool(snap["worn"]))
	model.air = float(snap["air"])


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(snap: Dictionary) -> void:
	apply_snapshot(snap)


func _on_peer_joined(peer_id: int) -> void:
	super._on_peer_joined(peer_id)
	if multiplayer.is_server():
		_rpc_snapshot.rpc_id(peer_id, snapshot())


func interaction_hint() -> String:
	return "press E to put the suit on · E again to take it off"
