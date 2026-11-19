class_name AudioBuses
extends RefCounted
## Audio buses, created at startup so the layout lives in code.
##
## Inside      in-sub sounds; ducked under the sonar operator's headphones
## Hull        outside sounds heard through the hull: muffled and quiet
## Felt        vibration-like cues (rumble); never ducked
## Hydrophone  what the sonar operator hears; only fed on their machine

const INSIDE: StringName = &"Inside"
const HULL: StringName = &"Hull"
const FELT: StringName = &"Felt"
const HYDROPHONE: StringName = &"Hydrophone"
## How much the operator's headphones cut the room (dB).
const HEADPHONE_DUCK_DB: float = -14.0


static func ensure() -> void:
	_bus(INSIDE, [])
	var hull_lp: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
	hull_lp.cutoff_hz = 320.0
	_bus(HULL, [hull_lp])
	_bus(FELT, [])
	var hydro_hp: AudioEffectHighPassFilter = AudioEffectHighPassFilter.new()
	hydro_hp.cutoff_hz = 35.0
	var hydro_lp: AudioEffectLowPassFilter = AudioEffectLowPassFilter.new()
	hydro_lp.cutoff_hz = 4000.0
	_bus(HYDROPHONE, [hydro_hp, hydro_lp])


## Ducks the room while the local player wears the sonar headset.
static func set_headphones(on: bool) -> void:
	var duck: float = HEADPHONE_DUCK_DB if on else 0.0
	for bus_name: StringName in [INSIDE, HULL]:
		var i: int = AudioServer.get_bus_index(bus_name)
		if i != -1:
			AudioServer.set_bus_volume_db(i, duck)


static func _bus(bus_name: StringName, effects: Array) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, &"Master")
	for e: Variant in effects:
		AudioServer.add_bus_effect(i, e as AudioEffect)
