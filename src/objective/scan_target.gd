class_name ScanTarget
extends Node3D
## A Raindrop sensor array: the thing the crew came to scan. Overbuilt,
## labelled, a dim red beacon, and an acoustic pinger the sonar operator can
## home in on. Lives under the world root (world space).

## Pinger level at 1 m. Audible on the hydrophone from a few hundred metres.
const PINGER_DB: float = 105.0


func _ready() -> void:
	# The array sits where the site spec's objective constraint puts it.
	var site: CanyonSite = get_node_or_null("../Site") as CanyonSite
	if site != null and site.spec != null:
		var at: Vector3 = site.spec.objective_position()
		if at.is_finite():
			position = at
	add_to_group(&"scan_target")
	add_to_group(&"outside_sources")
	_build()


func outside_db() -> float:
	return PINGER_DB


func outside_stream() -> AudioStream:
	return ProceduralSounds.pinger()


func _build() -> void:
	var steel: StandardMaterial3D = StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.5, 0.3)
	steel.metallic = 0.6
	steel.roughness = 0.5
	var dark: StandardMaterial3D = StandardMaterial3D.new()
	dark.albedo_color = Color(0.15, 0.16, 0.15)
	dark.roughness = 0.7
	var parts: Array[Array] = [
		# [size, position, material]
		[Vector3(6.0, 0.5, 6.0), Vector3(0, 0.25, 0), dark],       # base plate
		[Vector3(0.4, 6.0, 0.4), Vector3(-2.6, 3.0, -2.6), steel],  # legs
		[Vector3(0.4, 6.0, 0.4), Vector3(2.6, 3.0, -2.6), steel],
		[Vector3(0.4, 6.0, 0.4), Vector3(-2.6, 3.0, 2.6), steel],
		[Vector3(0.4, 6.0, 0.4), Vector3(2.6, 3.0, 2.6), steel],
		[Vector3(5.6, 0.4, 5.6), Vector3(0, 6.0, 0), steel],       # top frame
		[Vector3(2.0, 2.0, 2.0), Vector3(0, 1.5, 0), dark],        # instrument housing
		[Vector3(0.2, 4.0, 0.2), Vector3(0, 8.0, 0), steel],       # mast
	]
	for p: Array in parts:
		var mi: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = p[0] as Vector3
		box.material = p[2] as StandardMaterial3D
		mi.mesh = box
		mi.position = p[1] as Vector3
		add_child(mi)
	var label: Label3D = Label3D.new()
	label.text = "RAINDROP\nARRAY S-7"
	label.pixel_size = 0.02
	label.position = Vector3(0, 4.0, 2.75)
	label.modulate = Color(0.95, 0.9, 0.7)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(label)
	var beacon: OmniLight3D = OmniLight3D.new()
	beacon.light_color = Color(1.0, 0.15, 0.1)
	beacon.light_energy = 2.0
	beacon.omni_range = 10.0
	beacon.position = Vector3(0, 10.2, 0)
	add_child(beacon)
	var tween: Tween = create_tween().set_loops()
	tween.tween_property(beacon, "light_energy", 0.1, 0.8)
	tween.tween_property(beacon, "light_energy", 2.0, 0.2)
