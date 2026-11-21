extends TestCase
## The sonar panel: the bearing chart is a flat viewport screen on the large
## bezel, and the SIGNAL and BRG RATE dials sit in the two small bezels.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")
const SCREEN_PART: String = "Bezel"
const SMALL_PARTS: PackedStringArray = ["Bezel2", "Bezel3"]

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


func _radius(part: MeshInstance3D) -> float:
	return part.mesh.get_aabb().size.x


func test_pinned_bezels_are_the_large_one_and_two_small_ones() -> void:
	await _mounted()
	var large: MeshInstance3D = model.part(SCREEN_PART)
	expect(large != null, "large bezel exists")
	for n: String in SMALL_PARTS:
		var small: MeshInstance3D = model.part(n)
		expect(small != null and large != null and _radius(small) < _radius(large) * 0.5, "%s is a small bezel" % n)
	# All three are at the sonar panel, beside the hydrophone wheel.
	var wheel: Node3D = model.part("HydrophoneWheel")
	for n: String in [SCREEN_PART] + Array(SMALL_PARTS):
		expect(model.part(n).position.distance_to(wheel.position) < 0.6, "%s is at the sonar panel" % n)


func test_screen_is_a_viewport_quad_on_the_large_bezel() -> void:
	await _mounted()
	var screen: FlatChart = sonar.get_node_or_null("BearingScreen") as FlatChart
	expect(screen == null, "no longer a Stations/Sonar child")
	var large: MeshInstance3D = model.part(SCREEN_PART)
	screen = large.get_node_or_null("BearingScreen") as FlatChart
	expect(screen != null, "screen is a child of the large bezel")
	if screen == null:
		return
	expect(screen.mesh is QuadMesh, "flat quad")
	var mat: StandardMaterial3D = screen.material_override as StandardMaterial3D
	expect(mat != null and mat.albedo_texture is ViewportTexture, "SubViewport texture")
	expect(screen.get_node_or_null("Viewport") is SubViewport, "has a SubViewport")
	expect(screen.position.z < 0.0 and large.mesh.get_aabb().has_point(screen.position), "on the seat-facing face, inside the bezel bounds")
	# Faces the seat (sub-local +Z), not away from it.
	expect(screen.global_transform.basis * Vector3(0, 0, 1) != Vector3.ZERO)
	var normal: Vector3 = model.global_transform.basis.inverse() * (screen.global_transform.basis * Vector3(0, 0, 1))
	expect(normal.z < -0.9, "quad normal faces the seat (%s)" % normal)


func test_hologram_node_is_gone_and_gauges_left_the_station_root() -> void:
	await _mounted()
	expect(sonar.find_child("BearingDisplay", true, false) == null, "no BearingDisplay")
	expect(sonar.find_child("BearingBezel", true, false) == null, "no placeholder bezel")
	expect(sonar.get_node_or_null("SignalGauge") == null, "SIGNAL not a Sonar child")
	expect(sonar.get_node_or_null("BearingRateGauge") == null, "BRG RATE not a Sonar child")
	for n: String in ["NoiseGauge", "BearingGauge", "Seat", "Wheel", "Headset"]:
		expect(sonar.get_node_or_null(n) != null, "%s stays" % n)


func test_gauges_sit_in_the_small_bezels() -> void:
	await _mounted()
	var small_a: MeshInstance3D = model.part(SMALL_PARTS[0])
	var small_b: MeshInstance3D = model.part(SMALL_PARTS[1])
	var gauge_a: Gauge = small_a.get_node_or_null("SignalGauge") as Gauge
	var gauge_b: Gauge = small_b.get_node_or_null("BearingRateGauge") as Gauge
	expect(gauge_a != null, "SignalGauge in %s" % SMALL_PARTS[0])
	expect(gauge_b != null, "BearingRateGauge in %s" % SMALL_PARTS[1])
	for pair: Array in [[gauge_a, small_a], [gauge_b, small_b]]:
		var g: Gauge = pair[0] as Gauge
		var part: MeshInstance3D = pair[1] as MeshInstance3D
		if g == null:
			continue
		expect(part.mesh.get_aabb().has_point(g.position), "%s inside its bezel bounds (%s)" % [g.name, g.position])
		expect(g.radius <= _radius(part) * 0.5, "%s fits the bezel" % g.name)
		var normal: Vector3 = model.global_transform.basis.inverse() * (g.global_transform.basis * Vector3(0, 0, 1))
		expect(normal.z < -0.9, "%s faces the seat" % g.name)
