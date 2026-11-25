extends TestCase
## The sonar desk in the sub: the generated sonar_console is the whole station (bearing chart screen, dials,
## trackball, headset, seat). Nothing of the old model-mounted panel remains.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game
var model: SubModel
var sonar: SonarStation


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	model = game.get_node("Interior/Model") as SubModel
	sonar = game.get_node("Interior/Stations/Sonar") as SonarStation


func after_each() -> void:
	game.end_session()
	game.free()


func _faces_seat(node: Node3D) -> bool:
	var seat: Node3D = sonar.get_node("Seat") as Node3D
	var to_seat: Vector3 = (seat.global_position + Vector3(0, 1.0, 0) - node.global_position).normalized()
	return (node.global_transform.basis * Vector3(0, 0, 1)).normalized().dot(to_seat) > 0.6


func test_the_hull_has_no_old_panel_parts() -> void:
	for n: String in ["Bezel", "Bezel2", "Bezel3", "HydrophoneWheel", "Display"]:
		expect(model.part(n) == null, "%s is gone" % n)
	expect(sonar.find_child("SonarPanel", true, false) == null, "no SonarPanel node")
	expect(sonar.get_node_or_null("BearingScreen") == null, "no loose BearingScreen")


func test_the_station_is_the_generated_console() -> void:
	expect(sonar.scene_file_path == "res://assets/models/stations/sonar_console/sonar_console.tscn", "console instance")
	expect(sonar.wheel is Trackball, "hydrophone is the trackball")
	expect(sonar.headset != null, "headset wired")
	for n: String in ["Seat", "Headset", "Controls/Trackball", "Controls/ActiveSonar"]:
		expect(sonar.get_node_or_null(n) != null, "%s present" % n)


func test_screen_is_a_viewport_quad_facing_the_seat() -> void:
	var screen: FlatChart = sonar.get_node_or_null("ScreenMount/Chart") as FlatChart
	expect(screen != null, "chart is on the console's screen mount")
	if screen == null:
		return
	expect(screen.mesh is QuadMesh, "flat quad")
	var mat: StandardMaterial3D = screen.material_override as StandardMaterial3D
	expect(mat != null and mat.albedo_texture is ViewportTexture, "SubViewport texture")
	expect(screen.get_node_or_null("Viewport") is SubViewport, "has a SubViewport")
	expect(_faces_seat(screen), "quad faces the seat")


func test_gauges_face_the_seat_and_the_trackball_is_in_reach() -> void:
	var eye: Vector3 = (sonar.get_node("Seat/Model/SitPoint") as Node3D).global_position + Vector3(0, 1.2, 0)
	for n: String in ["SignalGauge", "BearingGauge", "NoiseGauge", "BearingRateGauge"]:
		var g: Node3D = sonar.get_node_or_null("Gauges/" + n) as Node3D
		expect(g != null, "%s present" % n)
		if g != null:
			expect(_faces_seat(g), "%s faces the seat" % n)
	var ball: Node3D = sonar.wheel
	expect(ball.global_position.distance_to(eye) < 0.75, "trackball within reach of the seated eye")
