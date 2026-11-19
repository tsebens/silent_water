class_name SonarSeat
extends StationSeat
## The sonar operator's seat. Sitting puts the headset on; standing takes it
## off. A seated operator can reach and crank the hydrophone wheel.

@export var headset: Wearable


func _init() -> void:
	super._init()
	allows_grabbing = true


func station_name() -> String:
	return "SONAR"


func seated_hint() -> String:
	return "hold click on the wheel and circle to train the hydrophone · E to stand"


func interaction_hint() -> String:
	return "press E to sit at sonar (puts the headset on)"
