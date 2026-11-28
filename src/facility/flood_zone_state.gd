class_name FloodZoneState
extends RefCounted
## Mutable flood state for a facility: which zones are breached, which are flooded, and which zone-to-zone
## doors are open. Plain data, so it replicates host to client as one Dictionary ([method to_dict],
## [method from_dict]). The rules that act on it live in [FloodZones].

## Zone id -> true while the zone has a breach to the sea.
var breached: Dictionary = {}
## Zone id -> true once the zone holds water.
var flooded: Dictionary = {}
## Door key -> bool, for doors whose state differs from [FloodZones]' default for their kind.
var door_open: Dictionary = {}


func to_dict() -> Dictionary:
	return {"breached": breached.duplicate(), "flooded": flooded.duplicate(), "door_open": door_open.duplicate()}


static func from_dict(d: Dictionary) -> FloodZoneState:
	var s: FloodZoneState = FloodZoneState.new()
	s.breached = (d.get("breached", {}) as Dictionary).duplicate()
	s.flooded = (d.get("flooded", {}) as Dictionary).duplicate()
	s.door_open = (d.get("door_open", {}) as Dictionary).duplicate()
	return s
