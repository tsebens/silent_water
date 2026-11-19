class_name SonarSeat
extends StationSeat
## The sonar operator's seat. Sitting puts the headset on; standing takes it
## off. A seated operator can reach and crank the hydrophone wheel.

const RANGE_STEPS: PackedFloat32Array = [50.0, 100.0, 200.0, 300.0, 500.0, 800.0]

@export var headset: Wearable

## Estimated range for the next contact mark (m), set with the mouse wheel.
var contact_range_m: float = 200.0


func _init() -> void:
	super._init()
	allows_grabbing = true


func station_name() -> String:
	return "SONAR"


func seated_hint() -> String:
	return "circle the wheel to train · wheel scroll: range %d m · M mark contact · E to stand" % int(contact_range_m)


func _unhandled_input(event: InputEvent) -> void:
	if not is_held_locally():
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var i: int = RANGE_STEPS.find(contact_range_m)
		i = clampi(i + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1), 0, RANGE_STEPS.size() - 1)
		contact_range_m = RANGE_STEPS[i]
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"sonar_mark"):
		mark_contact()
		get_viewport().set_input_as_handled()


## Marks a contact on the shared chart at the hydrophone's bearing and the
## estimated range, at the sub's depth.
func mark_contact() -> void:
	var station: SonarStation = get_tree().get_first_node_in_group(&"sonar") as SonarStation
	var frame: SubFrame = get_tree().get_first_node_in_group(&"sub_frame") as SubFrame
	var chart: MapModel = get_tree().get_first_node_in_group(&"map_model") as MapModel
	if station == null or frame == null or chart == null:
		return
	var dir: Vector3 = SonarStation.bearing_to_world(frame.sub_transform, station.bearing_deg())
	chart.add_pin(frame.sub_transform.origin + dir * contact_range_m, MapModel.Kind.CONTACT)


func interaction_hint() -> String:
	return "press E to sit at sonar (puts the headset on)"
