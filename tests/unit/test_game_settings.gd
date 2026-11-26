extends TestCase
## GameSettings: persistence, clamping, schema-driven entries, FOV conversion.

const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")
const TMP: String = "user://test_settings_tmp.cfg"


func _make() -> GameSettings:
	var s: GameSettings = GameSettings.new()
	s.path = TMP
	return s


func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func test_round_trip_and_defaults() -> void:
	var s: GameSettings = _make()
	s.load_settings()
	expect_near(float(s.get_value(&"fov_horizontal")), 112.0, 0.001, "default when file missing")
	s.set_value(&"fov_horizontal", 95.0)
	expect_eq(s.save_settings(), OK)
	var t: GameSettings = _make()
	t.load_settings()
	expect_near(float(t.get_value(&"fov_horizontal")), 95.0, 0.001, "round trip")
	s.free()
	t.free()


func test_clamping() -> void:
	var s: GameSettings = _make()
	s.load_settings()
	s.set_value(&"fov_horizontal", 500.0)
	expect_near(float(s.get_value(&"fov_horizontal")), 120.0)
	s.set_value(&"fov_horizontal", 1.0)
	expect_near(float(s.get_value(&"fov_horizontal")), 70.0)
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value(GameSettings.SECTION, "fov_horizontal", 999.0)
	cfg.save(TMP)
	s.load_settings()
	expect_near(float(s.get_value(&"fov_horizontal")), 120.0, 0.001, "out-of-range file value clamped")
	s.free()


func test_new_setting_is_only_a_schema_entry() -> void:
	var s: GameSettings = _make()
	s.schema.append({"tab": "Audio", "key": &"dummy", "label": "Dummy", "type": TYPE_INT, "min": 0, "max": 10, "default": 3})
	s.load_settings()
	expect_eq(s.get_value(&"dummy"), 3)
	s.set_value(&"dummy", 7)
	s.save_settings()
	var t: GameSettings = _make()
	t.schema.append(s.schema[s.schema.size() - 1])
	t.load_settings()
	expect_eq(t.get_value(&"dummy"), 7)
	s.free()
	t.free()


func test_fov_conversion() -> void:
	var aspect: float = 16.0 / 9.0
	expect_near(GameSettings.vertical_to_horizontal(80.0, aspect), 112.6, 0.5)
	expect_near(GameSettings.horizontal_to_vertical(GameSettings.vertical_to_horizontal(80.0, aspect), aspect), 80.0, 0.001)
	expect_near(GameSettings.vertical_to_horizontal(80.0, 1.0), 80.0, 0.001, "square")
	expect(GameSettings.vertical_to_horizontal(80.0, 21.0 / 9.0) > 112.6, "wider aspect, wider horizontal")


func test_change_updates_player_camera() -> void:
	var s: GameSettings = _make()
	runner.add_child(s)
	var emitted: Array = []
	s.changed.connect(func(k: StringName, v: Variant) -> void: emitted.append([k, v]))
	var p: Player = PLAYER_SCENE.instantiate() as Player
	p.name = "1"
	runner.add_child(p)
	var cam: Camera3D = p.get_node("Head/Camera3D") as Camera3D
	var size: Vector2 = p.get_viewport().get_visible_rect().size
	var aspect: float = size.x / size.y
	s.set_value(&"fov_horizontal", 90.0)
	expect_eq(emitted.size(), 1)
	expect_near(cam.fov, GameSettings.horizontal_to_vertical(90.0, aspect), 0.001)
	p.queue_free()
	s.queue_free()


func test_player_without_settings_uses_fallback() -> void:
	var p: Player = PLAYER_SCENE.instantiate() as Player
	p.name = "1"
	runner.add_child(p)
	expect_near((p.get_node("Head/Camera3D") as Camera3D).fov, 80.0)
	p.queue_free()
