class_name ScienceStation
extends StationSeat
## The science station: a row of [ScienceBay]s over a hand ledge. The operator stands at it like at the map table
## (there is no seat; [member sit_point] is where they stand). Left/right pick the active module among the fitted
## ones, wrapping; the work key arms it; E or Esc steps back. One operator at a time (the Interactable grab lock).

## The work key arms or stops the active module.
const ARM_KEY: Key = KEY_F

@export var loadout: ModuleLoadout:
	set(v):
		if loadout != null and loadout.changed.is_connected(refit):
			loadout.changed.disconnect(refit)
		loadout = v
		if loadout != null:
			loadout.changed.connect(refit)
		if is_inside_tree():
			refit()

var bays: Array[ScienceBay] = []
## Index of the active bay (always a fitted one while any is fitted), else -1.
var active: int = -1

signal active_changed(bay: int)


func _init() -> void:
	super._init()
	eye_height = 1.65


func _ready() -> void:
	super._ready()
	if loadout == null:
		loadout = ModuleLoadout.new()
	refit()


## Builds (or rebuilds) the bays from the loadout: one bay per slot, modules matching their types.
func refit() -> void:
	for i: int in ModuleLoadout.BAY_COUNT:
		if i >= bays.size():
			var bay: ScienceBay = ScienceBay.new()
			bay.name = "Bay%d" % i
			add_child(bay)
			bays.append(bay)
		bays[i].fit(loadout.type_at(i) if loadout != null else ModuleLoadout.Type.NONE)
	if active < 0 or active >= bays.size() or bays[active].is_empty():
		_set_active(_first_fitted())


## Indices of bays with a module, in order.
func fitted() -> Array[int]:
	var out: Array[int] = []
	for i: int in bays.size():
		if not bays[i].is_empty():
			out.append(i)
	return out


func _first_fitted() -> int:
	var f: Array[int] = fitted()
	return f[0] if not f.is_empty() else -1


func active_module() -> ScienceModule:
	return bays[active].module if active >= 0 and active < bays.size() else null


## Moves the active selection by [param dir] (+1 right, -1 left) among fitted modules, wrapping.
func select_step(dir: int) -> void:
	var f: Array[int] = fitted()
	if f.is_empty():
		return
	var pos: int = f.find(active)
	_set_active(f[posmod((pos if pos >= 0 else 0) + dir, f.size())])


func _set_active(bay: int) -> void:
	if bay == active:
		return
	active = bay
	active_changed.emit(bay)


## Whether [param peer] is the operator.
func is_operator(peer: int) -> bool:
	return state.holder == peer


## Host-side: [param peer] asks to step up. Refused when someone else is the operator.
func request_operator(peer: int) -> bool:
	return state.try_grab(peer)


## [param peer] steps back; only the operator can.
func release_operator(peer: int) -> bool:
	return state.release(peer)


func station_name() -> String:
	return "SCIENCE"


func interaction_hint() -> String:
	return "press E to use the science station"


func seated_hint() -> String:
	var m: ScienceModule = active_module()
	return "A/D select module · F arm/stop %s · E leave" % (m.display_name() if m != null else "(none)")


## Key handling for the operator; returns true if the event was used.
func handle_event(event: InputEvent) -> bool:
	if event.is_action_pressed(&"move_left"):
		select_step(-1)
		return true
	if event.is_action_pressed(&"move_right"):
		select_step(1)
		return true
	var key: InputEventKey = event as InputEventKey
	var m: ScienceModule = active_module()
	if key != null and key.pressed and not key.echo and key.keycode == ARM_KEY and m != null:
		m.toggle_armed()
		return true
	return m != null and m.work(event)


func _unhandled_input(event: InputEvent) -> void:
	if not is_held_locally():
		return
	if handle_event(event):
		get_viewport().set_input_as_handled()
