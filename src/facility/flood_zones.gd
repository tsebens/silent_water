class_name FloodZones
extends RefCounted
## Per-zone flood model for a facility, authored from its floorplan program (rooms, tunnels, doors).
## A zone is the watertight unit: a room's `zone:` or else its structure; each tunnel is its own zone.
## Water spreads between zones only through open doors; a closed watertight door cuts it. Godot cannot read
## YAML, so [method load_program] parses the small subset the program uses (flow mappings in block lists).

const PROGRAM_PATH: String = "res://assets/models/facilities/research_station/program.yaml"
## The outside. A door to it is a way in for the sea.
const SEA: StringName = &"sea"
## Door kinds that start closed; every other kind starts open.
const CLOSED_KINDS: Array[String] = ["hatch"]

## Zone id -> true.
var zones: Dictionary = {}
## Zone id -> Array of room ids.
var rooms_of: Dictionary = {}
## Each: {key, a, b, kind}. a and b are zone ids (b may be SEA). Only doors that join different zones.
var doors: Array[Dictionary] = []
var state: FloodZoneState = FloodZoneState.new()


## Build the model from a program file. Returns null if it cannot be read.
static func load_program(path: String = PROGRAM_PATH) -> FloodZones:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var fz: FloodZones = FloodZones.new()
	fz._parse(f.get_as_text())
	return fz


func zone_ids() -> Array:
	var ids: Array = zones.keys()
	ids.sort()
	return ids


func has_zone(zone: StringName) -> bool:
	return zones.has(String(zone))


## The zone a room is in ("" if unknown).
func zone_of_room(room: StringName) -> StringName:
	for z: String in rooms_of:
		if (rooms_of[z] as Array).has(String(room)):
			return StringName(z)
	return &""


## Door keys are "<zone a>|<zone b>"; several doors between the same two zones share one key and one state.
func door_keys() -> Array:
	var keys: Array = []
	for d: Dictionary in doors:
		if not keys.has(d.key):
			keys.append(d.key)
	return keys


func door_kinds(key: String) -> Array:
	var kinds: Array = []
	for d: Dictionary in doors:
		if d.key == key:
			kinds.append(d.kind)
	return kinds


func is_door_open(key: String) -> bool:
	if state.door_open.has(key):
		return state.door_open[key]
	for d: Dictionary in doors:
		if d.key == key:
			return not CLOSED_KINDS.has(d.kind)
	return false


func set_door_open(key: String, open: bool) -> void:
	state.door_open[key] = open
	spread()


## Close or open the door(s) between two zones (order does not matter).
func set_between(a: StringName, b: StringName, open: bool) -> bool:
	for k: Variant in door_keys():
		var key: String = k
		var parts: PackedStringArray = key.split("|")
		if (parts[0] == String(a) and parts[1] == String(b)) or (parts[0] == String(b) and parts[1] == String(a)):
			set_door_open(key, open)
			return true
	return false


func set_breach(zone: StringName, breached: bool = true) -> void:
	if not has_zone(zone):
		return
	state.breached[String(zone)] = breached
	spread()


func is_breached(zone: StringName) -> bool:
	return state.breached.get(String(zone), false)


func is_flooded(zone: StringName) -> bool:
	return state.flooded.get(String(zone), false)


## How full of water a zone is, 0 (dry) to 1 (flooded), for presentation. Falls while the zone is pumped.
func water_level(zone: StringName) -> float:
	if not is_flooded(zone):
		return 0.0
	return clampf(state.level.get(String(zone), 1.0), 0.0, 1.0)


## "flooded" or "dry".
func zone_status(zone: StringName) -> StringName:
	return &"flooded" if is_flooded(zone) else &"dry"


## Pump a zone dry. It floods again if it is still connected to the sea.
func drain(zone: StringName) -> void:
	state.flooded.erase(String(zone))
	state.level.erase(String(zone))
	spread()


## True while the zone has a breach, or an open path (through open doors) to a zone with one or to the sea.
func connected_to_sea(zone: StringName) -> bool:
	return _connected_to_sea_set().has(String(zone))


## True when the zone can be pumped dry: no breach in it and no open path (through open doors) to a breach
## or to the sea. Unknown zones cannot be pumped.
func can_pump(zone: StringName) -> bool:
	return has_zone(zone) and not connected_to_sea(zone)


## Flood every zone the sea can reach: from breached zones, zones with an open door to the sea, and zones
## already holding water, through open doors. Flooding stays until [method drain].
func spread() -> void:
	var open_adj: Dictionary = _open_adjacency()
	var sources: Array = []
	for z: String in zones:
		if is_breached(StringName(z)) or is_flooded(StringName(z)) or _open_to_sea(z):
			sources.append(z)
	for z: String in _reach(sources, open_adj):
		state.flooded[z] = true


func _connected_to_sea_set() -> Dictionary:
	var sources: Array = []
	for z: String in zones:
		if is_breached(StringName(z)) or _open_to_sea(z):
			sources.append(z)
	return _reach(sources, _open_adjacency())


func _open_to_sea(zone: String) -> bool:
	for d: Dictionary in doors:
		if d.b == String(SEA) and d.a == zone and is_door_open(d.key):
			return true
	return false


func _open_adjacency() -> Dictionary:
	var adj: Dictionary = {}
	for d: Dictionary in doors:
		if d.b == String(SEA) or not is_door_open(d.key):
			continue
		if not adj.has(d.a):
			adj[d.a] = []
		if not adj.has(d.b):
			adj[d.b] = []
		(adj[d.a] as Array).append(d.b)
		(adj[d.b] as Array).append(d.a)
	return adj


func _reach(sources: Array, adj: Dictionary) -> Dictionary:
	var seen: Dictionary = {}
	var queue: Array = sources.duplicate()
	for s: String in sources:
		seen[s] = true
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for n: String in adj.get(cur, []):
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


# ---- Program parsing -----------------------------------------------------------------------------------------

func _parse(text: String) -> void:
	var structures: Array[Dictionary] = []
	var rooms: Array[Dictionary] = []
	var tunnels: Array[Dictionary] = []
	var raw_doors: Array[Dictionary] = []
	var section: String = ""
	var structure: Dictionary = {}
	for raw: String in text.split("\n"):
		var line: String = _strip_comment(raw)
		if line.strip_edges().is_empty():
			continue
		if not line.begins_with(" "):
			section = line.strip_edges().trim_suffix(":")
			continue
		var s: String = line.strip_edges()
		if section == "structures":
			if s.begins_with("- id:"):
				structure = {"id": s.substr(5).strip_edges()}
				structures.append(structure)
			elif s.begins_with("rect:") and not structure.is_empty() and not structure.has("rect"):
				structure["rect"] = _parse_value(s.substr(5).strip_edges())
			continue
		if not s.begins_with("- {"):
			continue
		var m: Dictionary = _parse_value(s.substr(2).strip_edges())
		match section:
			"rooms":
				rooms.append(m)
			"tunnels":
				tunnels.append(m)
			"doors":
				raw_doors.append(m)
	var zone_of: Dictionary = {}
	for r: Dictionary in rooms:
		var z: String = str(r.get("zone", _structure_of(r.get("rect", []), structures)))
		zone_of[str(r.id)] = z
		_add_zone(z, str(r.id))
	for t: Dictionary in tunnels:
		zone_of[str(t.id)] = str(t.id)
		_add_zone(str(t.id), "")
	zone_of[String(SEA)] = String(SEA)
	for d: Dictionary in raw_doors:
		var pair: Array = d.between
		var a: String = zone_of.get(str(pair[0]), "")
		var b: String = zone_of.get(str(pair[1]), "")
		if a.is_empty() or b.is_empty() or a == b:
			continue  # unknown ends (the sub) and doors inside one zone do not matter for flooding
		if a == String(SEA):
			a = b
			b = String(SEA)
		var key: String = "%s|%s" % [a, b] if b == String(SEA) or a < b else "%s|%s" % [b, a]
		var za: String = key.split("|")[0]
		var zb: String = key.split("|")[1]
		doors.append({"key": key, "a": za, "b": zb, "kind": str(d.get("kind", "open"))})


func _add_zone(zone: String, room: String) -> void:
	zones[zone] = true
	if not rooms_of.has(zone):
		rooms_of[zone] = []
	if not room.is_empty():
		(rooms_of[zone] as Array).append(room)


func _structure_of(rect: Variant, structures: Array[Dictionary]) -> String:
	var r: Array = rect
	if r.size() < 4:
		return ""
	for s: Dictionary in structures:
		var sr: Array = s.get("rect", [])
		if sr.size() == 4 and r[0] >= sr[0] and r[1] <= sr[1] and r[2] >= sr[2] and r[3] <= sr[3]:
			return str(s.id)
	return ""


static func _strip_comment(line: String) -> String:
	var i: int = line.find(" #")
	if line.strip_edges().begins_with("#"):
		return ""
	return line.substr(0, i) if i >= 0 else line


## Parse a YAML flow value: {k: v, ...}, [a, b], number, bool or bare string.
static func _parse_value(s: String) -> Variant:
	s = s.strip_edges()
	if s.begins_with("{") or s.begins_with("["):
		var is_map: bool = s.begins_with("{")
		var inner: String = s.substr(1, s.length() - 2)
		var parts: PackedStringArray = _split_top(inner)
		if is_map:
			var m: Dictionary = {}
			for p: String in parts:
				var c: int = p.find(":")
				if c < 0:
					continue
				m[p.substr(0, c).strip_edges()] = _parse_value(p.substr(c + 1))
			return m
		var a: Array = []
		for p: String in parts:
			if not p.strip_edges().is_empty():
				a.append(_parse_value(p))
		return a
	if s == "true":
		return true
	if s == "false":
		return false
	if s.is_valid_float():
		return s.to_float()
	return s


static func _split_top(s: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var depth: int = 0
	var cur: String = ""
	for ch: String in s:
		if ch == "{" or ch == "[":
			depth += 1
		elif ch == "}" or ch == "]":
			depth -= 1
		if ch == "," and depth == 0:
			out.append(cur)
			cur = ""
		else:
			cur += ch
	if not cur.strip_edges().is_empty():
		out.append(cur)
	return out
