class_name IsolationRules
extends RefCounted
## What the crew does to isolate a breach: shut or open a watertight door, patch a breach. These act on a
## [FloodZones] model, host side only, and make the noise that goes with them through [Acoustics]. A zone can
## be pumped only once isolated ([method FloodZones.can_pump]). The nodes ([WatertightDoor], [BreachPatch])
## call these on the host and replicate the resulting [FloodZoneState].

const DOOR_SOUND: SoundType = preload("res://src/noise/sound_types/hatch_clank.tres")
const PATCH_SOUND: SoundType = preload("res://src/noise/sound_types/impact.tres")
## A patch is quieter than a hull strike.
const PATCH_SCALE: float = 0.5


static func can_pump(fz: FloodZones, zone: StringName) -> bool:
	return fz != null and fz.can_pump(zone)


## Opens or closes the door(s) with this key and emits the door sound at [param at]. False if no such door
## or it is already in that state (no noise then).
static func set_door(fz: FloodZones, key: String, open: bool, at: Vector3, source: Object = null) -> bool:
	if fz == null or not fz.door_keys().has(key) or fz.is_door_open(key) == open:
		return false
	fz.set_door_open(key, open)
	Acoustics.emit_event(DOOR_SOUND, at, source)
	return true


static func toggle_door(fz: FloodZones, key: String, at: Vector3, source: Object = null) -> bool:
	if fz == null:
		return false
	return set_door(fz, key, not fz.is_door_open(key), at, source)


## Clears the breach flag on a zone and emits the patch sound. False if the zone is not breached.
static func patch_breach(fz: FloodZones, zone: StringName, at: Vector3, source: Object = null) -> bool:
	if fz == null or not fz.is_breached(zone):
		return false
	fz.set_breach(zone, false)
	Acoustics.emit_event(PATCH_SOUND, at, source, PATCH_SCALE)
	return true
