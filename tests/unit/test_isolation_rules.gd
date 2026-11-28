extends TestCase
## Isolation: a zone with a breach or an open path to one (or the sea) cannot be pumped; closing doors or
## patching isolates it. Door and patch actions make noise.

var det: SoundDetector
var got: Array[SoundEvent] = []


func before_each() -> void:
	Acoustics.reset()
	Acoustics.seed_events(1)
	got.clear()
	det = SoundDetector.new()
	det.threshold_db = -100.0
	runner.add_child(det)
	det.heard.connect(func(e: SoundEvent) -> void: got.append(e))


func after_each() -> void:
	det.free()


func _fz() -> FloodZones:
	var fz: FloodZones = FloodZones.load_program()
	expect(fz != null, "program loads")
	return fz


func test_dry_closed_zone_can_be_pumped() -> void:
	var fz: FloodZones = _fz()
	expect(fz.can_pump(&"main"), "no breach")
	expect(not fz.can_pump(&"nowhere"), "unknown zone")


func test_breached_zone_cannot_be_pumped() -> void:
	var fz: FloodZones = _fz()
	fz.set_breach(&"main")
	expect(not fz.can_pump(&"main"), "breached")
	expect(IsolationRules.patch_breach(fz, &"main", Vector3.ZERO), "patched")
	expect(fz.can_pump(&"main"), "patched zone pumpable")


func test_open_path_to_breach_blocks_pumping_until_door_closed() -> void:
	var fz: FloodZones = _fz()
	fz.set_door_open("link_tunnel|main", true)
	fz.set_door_open("link_tunnel|maintenance", true)
	fz.set_breach(&"maintenance")
	expect(not fz.can_pump(&"link_tunnel"), "open path to breach")
	expect(not fz.can_pump(&"main"), "open path through tunnel")
	IsolationRules.set_door(fz, "link_tunnel|maintenance", false, Vector3.ZERO)
	expect(fz.can_pump(&"link_tunnel"), "tunnel isolated")
	expect(fz.can_pump(&"main"), "main isolated")
	expect(not fz.can_pump(&"maintenance"), "breached zone itself still cannot")


func test_open_door_to_sea_blocks_pumping() -> void:
	var fz: FloodZones = _fz()
	IsolationRules.set_door(fz, "lockout|sea", true, Vector3.ZERO)
	expect(not fz.can_pump(&"lockout"), "open to sea")
	IsolationRules.set_door(fz, "lockout|sea", false, Vector3.ZERO)
	expect(fz.can_pump(&"lockout"), "sealed")


func test_door_action_emits_noise_event() -> void:
	var fz: FloodZones = _fz()
	var at: Vector3 = Vector3(1, 0, 0)
	expect(IsolationRules.toggle_door(fz, "link_tunnel|main", at), "toggled")
	expect_eq(got.size(), 1, "one event")
	expect_eq(got[0].kind, IsolationRules.DOOR_SOUND.kind, "door kind")
	expect(got[0].true_position.is_equal_approx(at), "at the door")
	got.clear()
	expect(not IsolationRules.set_door(fz, "nope|nope", true, at), "unknown door")
	expect_eq(got.size(), 0, "no noise for no change")


func test_patch_emits_noise_event() -> void:
	var fz: FloodZones = _fz()
	expect(not IsolationRules.patch_breach(fz, &"main", Vector3.ZERO), "nothing to patch")
	expect_eq(got.size(), 0, "silent")
	fz.set_breach(&"main")
	IsolationRules.patch_breach(fz, &"main", Vector3.ZERO)
	expect_eq(got.size(), 1, "one event")
	expect_eq(got[0].kind, IsolationRules.PATCH_SOUND.kind, "patch kind")
	expect_near(got[0].emitted_intensity, IsolationRules.PATCH_SOUND.scaled_intensity(IsolationRules.PATCH_SCALE), 1e-9)
