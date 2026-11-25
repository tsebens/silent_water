extends TestCase
## The sonar panel: the bearing chart is a flat viewport screen, and the SIGNAL and BRG RATE dials sit beside the
## hydrophone wheel, all facing the seat.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game
var model: SubModel
var sonar: Node


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	model = game.get_node("Interior/Model") as SubModel
	sonar = game.get_node("Interior/Stations/Sonar")


func after_each() -> void:
	game.end_session()
	game.free()


## The panel mounts its parts one frame after ready.
func _mounted() -> void:
	await runner.get_tree().process_frame


func _in_model(node: Node3D) -> Vector3:
	return model.global_transform.affine_inverse() * node.global_position


func _faces_seat(node: Node3D) -> bool:
	var normal: Vector3 = model.global_transform.basis.inverse() * (node.global_transform.basis * Vector3(0, 0, 1))
	return normal.z < -0.9


func test_the_hull_has_no_old_panel_parts() -> void:
	for n: String in ["Bezel", "Bezel2", "Bezel3", "HydrophoneWheel", "Display"]:
		expect(model.part(n) == null, "%s is gone" % n)


func test_screen_is_a_viewport_quad_facing_the_seat() -> void:
	await _mounted()
	var screen: FlatChart = sonar.get_node_or_null("BearingScreen") as FlatChart
	expect(screen != null, "screen stays under the Sonar station")
	if screen == null:
		return
	expect(screen.mesh is QuadMesh, "flat quad")
	var mat: StandardMaterial3D = screen.material_override as StandardMaterial3D
	expect(mat != null and mat.albedo_texture is ViewportTexture, "SubViewport texture")
	expect(screen.get_node_or_null("Viewport") is SubViewport, "has a SubViewport")
	expect(_faces_seat(screen), "quad normal faces the seat")
	expect(_in_model(screen).distance_to((sonar.get_node("Wheel") as Node3D).position) < 0.6, "screen is at the wheel")


func test_gauges_sit_beside_the_wheel_facing_the_seat() -> void:
	await _mounted()
	var wheel: Node3D = sonar.get_node("Wheel") as Node3D
	for n: String in ["SignalGauge", "BearingRateGauge"]:
		var g: Gauge = sonar.get_node_or_null(n) as Gauge
		expect(g != null, "%s stays under the Sonar station" % n)
		if g == null:
			continue
		expect(_in_model(g).distance_to(wheel.position) < 0.6, "%s is at the wheel" % n)
		expect(_faces_seat(g), "%s faces the seat" % n)


func test_other_station_parts_stay() -> void:
	await _mounted()
	expect(sonar.find_child("BearingDisplay", true, false) == null, "no BearingDisplay")
	for n: String in ["NoiseGauge", "BearingGauge", "Seat", "Wheel", "Headset"]:
		expect(sonar.get_node_or_null(n) != null, "%s stays" % n)
