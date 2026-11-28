extends TestCase
## Door wheel and patch kit nodes drive the flood model on the host and report through signals.

var got: Array[SoundEvent] = []
var det: SoundDetector


func before_each() -> void:
	Acoustics.reset()
	got.clear()
	det = SoundDetector.new()
	det.threshold_db = -100.0
	runner.add_child(det)
	det.heard.connect(func(e: SoundEvent) -> void: got.append(e))


func after_each() -> void:
	det.free()


func test_door_wheel_toggles_state_and_makes_noise() -> void:
	var fz: FloodZones = FloodZones.load_program()
	var door: WatertightDoor = WatertightDoor.new()
	door.door_key = "link_tunnel|main"
	door.zones = fz
	runner.add_child(door)
	var was: bool = door.is_open()
	door.interact()
	expect(door.is_open() != was, "toggled")
	expect_eq(got.size(), 1, "noise")
	door.interact()
	expect_eq(door.is_open(), was, "toggled back")
	door.free()


func test_patch_clears_breach() -> void:
	var fz: FloodZones = FloodZones.load_program()
	fz.set_breach(&"maintenance")
	var patch: BreachPatch = BreachPatch.new()
	patch.zone = &"maintenance"
	patch.zones = fz
	runner.add_child(patch)
	expect(patch.is_breached(), "breached")
	patch.interact()
	expect(not fz.is_breached(&"maintenance"), "cleared")
	expect_eq(got.size(), 1, "noise")
	patch.free()


func test_state_replicates_as_dict() -> void:
	var fz: FloodZones = FloodZones.load_program()
	fz.set_breach(&"main")
	fz.set_door_open("link_tunnel|main", false)
	var client: FloodZones = FloodZones.load_program()
	client.state = FloodZoneState.from_dict(fz.state.to_dict())
	expect(client.is_breached(&"main"), "breach replicated")
	expect(not client.is_door_open("link_tunnel|main"), "door replicated")
	expect_eq(client.can_pump(&"main"), fz.can_pump(&"main"))
