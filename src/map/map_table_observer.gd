class_name MapTableObserver
extends StationSeat
## A standing point beside the map table's operator. Stepping up (E) gives the
## same leaning view, but only the operator drives the camera; an observer can
## place and remove pins (1-4 pick the type, click places, right-click removes).
## Pins go to the shared [MapModel] through the [member table].
## Each point has its own occupancy: stepping back frees only this one.

@export var table: MapTable

var pin_kind: int = MapModel.Kind.WAYPOINT


func _init() -> void:
	super._init()
	eye_height = 1.65


func station_name() -> String:
	return "MAP TABLE (OBSERVER)"


func seated_hint() -> String:
	return "1-4 pin: %s · click place · right-click remove · E leave" % MapModel.kind_name(pin_kind)


func interaction_hint() -> String:
	return "press E to step up to the map table"


func has_table_view() -> bool:
	return true


func table_view() -> Transform3D:
	return table.view_transform_from(seat_transform().origin + Vector3.UP * eye_height)


func begin_interaction() -> void:
	super.begin_interaction()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func end_interaction() -> void:
	super.end_interaction()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not is_held_locally() or table == null or table.holo == null:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			table.place_pin_at(mb.position, pin_kind)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			table.remove_pin_at(mb.position)
		else:
			return
		get_viewport().set_input_as_handled()
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode >= KEY_1 and key.keycode <= KEY_4:
		pin_kind = MapTable.KEY_KINDS[key.keycode - KEY_1]
		get_viewport().set_input_as_handled()
