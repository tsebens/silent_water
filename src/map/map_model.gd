class_name MapModel
extends Node
## The crew's shared chart: pins on the map table and sonar contact marks.
## Every hologram (pilot map, map table) draws from this one model. The host
## owns the list; any peer can ask to add or remove a pin, and the host
## sends the whole list back to everyone (it's small).

signal changed
## The transient sonar marks changed (added, pruned or replaced by the host).
signal marks_changed

enum Kind { WAYPOINT, DANGER, APEX, NOTE, CONTACT, DECOY }

const KIND_NAMES: PackedStringArray = ["WAYPOINT", "DANGER", "LAST SEEN: APEX", "NOTE", "SONAR CONTACT", "DECOY"]
## Palette swatch per [enum Kind] (docs/palette.md): markers and pins are purple, threats alarm red, a sonar
## contact is "unknown" yellow until contact classes (#359) say otherwise.
const KIND_SWATCHES: Array[StringName] = [&"light_marker", &"light_alarm", &"light_alarm", &"light_marker", &"light_warn", &"light_marker"]
const MAX_PINS: int = 64

## [{id, pos (world), kind, author}], oldest first.
var pins: Array[Dictionary] = []

## Seconds a sonar mark takes to fade to nothing.
@export var mark_fade_s: float = 60.0

## Transient sonar marks: [{id, pos (world), author, born (local ms)}], oldest
## first. Host-owned and replicated like [member pins]; the sub-second clock
## differs per peer, so the wire carries ages, not timestamps.
var marks: Array[Dictionary] = []

var _next_id: int = 1
var _next_mark_id: int = 1


func _ready() -> void:
	add_to_group(&"map_model")
	Net.peer_joined.connect(_on_peer_joined)


## Intensity (1 new, 0 faded) of a mark [param age_s] seconds old.
static func mark_intensity(age_s: float, fade_s: float) -> float:
	if fade_s <= 0.0:
		return 0.0
	return clampf(1.0 - age_s / fade_s, 0.0, 1.0)


## Age of a mark in seconds at [param now_ms].
static func mark_age_s(mark: Dictionary, now_ms: int) -> float:
	return maxf(float(now_ms - int(mark["born"])) / 1000.0, 0.0)


## Marks with intensity, newest first: [{pos, intensity, id}].
func mark_trail(now_ms: int = Time.get_ticks_msec()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in range(marks.size() - 1, -1, -1):
		var m: Dictionary = marks[i]
		var k: float = mark_intensity(mark_age_s(m, now_ms), mark_fade_s)
		out.append({"id": m["id"], "pos": m["pos"], "intensity": k})
	return out


## Drops marks that have fully faded. Returns true if any were removed.
func prune_marks(now_ms: int = Time.get_ticks_msec()) -> bool:
	var kept: Array[Dictionary] = []
	for m: Dictionary in marks:
		if mark_intensity(mark_age_s(m, now_ms), mark_fade_s) > 0.0:
			kept.append(m)
	if kept.size() == marks.size():
		return false
	marks = kept
	return true


## Any peer: record a transient sonar mark at a world position.
func add_mark(world_pos: Vector3) -> void:
	if multiplayer.is_server():
		_host_add_mark(world_pos, multiplayer.get_unique_id())
	else:
		_rpc_add_mark.rpc_id(1, world_pos)


func _process(_delta: float) -> void:
	# The host prunes and replicates; clients also drop expired marks locally
	# (their ages are already advancing), so a lost update cannot leave ghosts.
	if marks.is_empty():
		return
	if prune_marks():
		if multiplayer.is_server():
			_broadcast_marks()
		else:
			marks_changed.emit()


@rpc("any_peer", "reliable")
func _rpc_add_mark(world_pos: Vector3) -> void:
	if multiplayer.is_server():
		_host_add_mark(world_pos, multiplayer.get_remote_sender_id())


func _host_add_mark(world_pos: Vector3, author: int) -> void:
	marks.append({"id": _next_mark_id, "pos": world_pos, "author": author, "born": Time.get_ticks_msec()})
	_next_mark_id += 1
	while marks.size() > MAX_PINS:
		marks.remove_at(0)
	_broadcast_marks()


func _broadcast_marks() -> void:
	marks_changed.emit()
	if Net.is_online():
		_rpc_set_marks.rpc(_marks_to_wire())


func _marks_to_wire() -> Array:
	var now: int = Time.get_ticks_msec()
	var out: Array = []
	for m: Dictionary in marks:
		out.append({"id": m["id"], "pos": m["pos"], "author": m["author"], "age": mark_age_s(m, now)})
	return out


@rpc("authority", "call_remote", "reliable")
func _rpc_set_marks(wire: Array) -> void:
	var now: int = Time.get_ticks_msec()
	marks.clear()
	for w: Variant in wire:
		var d: Dictionary = w as Dictionary
		marks.append({"id": d["id"], "pos": d["pos"], "author": d["author"], "born": now - int(float(d["age"]) * 1000.0)})
	marks_changed.emit()


static func kind_name(kind: int) -> String:
	return KIND_NAMES[clampi(kind, 0, KIND_NAMES.size() - 1)]


static func kind_color(kind: int) -> Color:
	return Palette.main().color(KIND_SWATCHES[clampi(kind, 0, KIND_SWATCHES.size() - 1)])


## Any peer: place a pin at a world position.
func add_pin(world_pos: Vector3, kind: int) -> void:
	if multiplayer.is_server():
		_host_add(world_pos, kind, multiplayer.get_unique_id())
	else:
		_rpc_add.rpc_id(1, world_pos, kind)


## Any peer: remove a pin by id.
func remove_pin(id: int) -> void:
	if multiplayer.is_server():
		_host_remove(id)
	else:
		_rpc_remove.rpc_id(1, id)


## Host: clears everything (new dive).
func clear() -> void:
	if multiplayer.is_server():
		pins.clear()
		marks.clear()
		_broadcast()
		_broadcast_marks()


func pin_by_id(id: int) -> Dictionary:
	for p: Dictionary in pins:
		if int(p["id"]) == id:
			return p
	return {}


@rpc("any_peer", "reliable")
func _rpc_add(world_pos: Vector3, kind: int) -> void:
	if multiplayer.is_server():
		_host_add(world_pos, kind, multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func _rpc_remove(id: int) -> void:
	if multiplayer.is_server():
		_host_remove(id)


func _host_add(world_pos: Vector3, kind: int, author: int) -> void:
	pins.append({"id": _next_id, "pos": world_pos, "kind": clampi(kind, 0, Kind.DECOY), "author": author})
	_next_id += 1
	while pins.size() > MAX_PINS:
		pins.remove_at(0)
	_broadcast()


func _host_remove(id: int) -> void:
	for i: int in range(pins.size()):
		if int(pins[i]["id"]) == id:
			pins.remove_at(i)
			_broadcast()
			return


func _broadcast() -> void:
	changed.emit()
	if Net.is_online():
		_rpc_set.rpc(pins)


@rpc("authority", "call_remote", "reliable")
func _rpc_set(new_pins: Array) -> void:
	pins.clear()
	for p: Variant in new_pins:
		pins.append(p as Dictionary)
	changed.emit()


func _on_peer_joined(peer_id: int) -> void:
	if multiplayer.is_server():
		_rpc_set.rpc_id(peer_id, pins)
		_rpc_set_marks.rpc_id(peer_id, _marks_to_wire())
