extends TestCase
## The seated pilot's eye sits at the dome's centre, give or take the stated offset (#605): the sphere's centre is
## DOME_EYE_OFFSET_M under the eye so the floor keeps a disc of glass underfoot, and the player fits: the step down into
## the cockpit, the sit point and the eye height.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")
## Tristan's ruling on #605: the eye may sit about 0.1 m off the centre; the tolerance covers the 1 mm the ring is snapped to a hull ring.
const DOME_EYE_OFFSET_M: float = 0.1
const TOLERANCE_M: float = 0.005
## The player capsule (CLAUDE.md, program.yaml clearances): radius 0.3 m.
const CAPSULE_RADIUS_M: float = 0.3
## The cockpit floor is one step down; a step this deep or less is walkable.
const MAX_STEP_M: float = 0.25

var game: Game


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	(game.get_node("SubController") as SubController).enabled = false
	runner.add_child(game)
	game.start_session()


func after_each() -> void:
	game.end_session()
	game.free()


func _seat() -> PilotSeat:
	return game.get_node("Interior/Stations/Pilot/Seat") as PilotSeat


func _eye() -> Vector3:
	var seat: PilotSeat = _seat()
	return seat.sit_point.global_position + Vector3.UP * seat.eye_height


func test_eye_is_within_tolerance_of_the_dome_centre() -> void:
	var d: Dictionary = SubLayout.dome()
	var centre: Vector3 = d["centre"]
	var eye: Vector3 = _eye()
	expect_near(eye.x, centre.x, TOLERANCE_M, "eye on the sphere's centreline")
	expect_near(eye.z, centre.z, TOLERANCE_M, "eye in the ring's plane (z)")
	expect_near(eye.y - centre.y, DOME_EYE_OFFSET_M, TOLERANCE_M, "eye %.3f m above the centre (stated offset %.2f m)" % [eye.y - centre.y, DOME_EYE_OFFSET_M])
	expect(eye.distance_to(centre) <= DOME_EYE_OFFSET_M + TOLERANCE_M, "eye within %.3f m of the centre (is %.3f)" % [DOME_EYE_OFFSET_M + TOLERANCE_M, eye.distance_to(centre)])


func test_player_fits_the_floor_disc_step_and_sit_point() -> void:
	var d: Dictionary = SubLayout.dome()
	var seat: PilotSeat = _seat()
	var sit: Vector3 = seat.sit_point.global_position
	expect_near(sit.y, float(d["floor_y"]), TOLERANCE_M, "the sit point is on the cockpit floor the sphere is cut by")
	expect(float(d["floor_radius"]) >= CAPSULE_RADIUS_M, "the glass disc (%.3f m) holds the player's capsule (%.2f m)" % [float(d["floor_radius"]), CAPSULE_RADIUS_M])
	expect(float(d["floor_radius"]) < float(d["radius"]), "the floor is a disc inside the sphere with glass rising round it")
	expect(absf(SubLayout.cockpit_floor_offset()) <= MAX_STEP_M, "the step down into the cockpit (%.2f m) is walkable" % SubLayout.cockpit_floor_offset())
	expect_near(_seat().eye_height, 1.15, 0.0001, "eye height 1.15 m above the sit point")
