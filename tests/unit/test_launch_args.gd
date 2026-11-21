extends TestCase


func test_defaults() -> void:
	var a: LaunchArgs = LaunchArgs.parse(PackedStringArray())
	expect(not a.host and not a.join)
	expect_eq(a.port, Net.DEFAULT_PORT)
	expect_eq(a.address, Net.DEFAULT_ADDRESS)
	expect_eq(a.errors.size(), 0)


func test_host_with_port() -> void:
	var a: LaunchArgs = LaunchArgs.parse(PackedStringArray(["--host", "--port", "5000"]))
	expect(a.host)
	expect_eq(a.port, 5000)


func test_join_inline_forms() -> void:
	var a: LaunchArgs = LaunchArgs.parse(PackedStringArray(["--join=10.0.0.2", "--port=6000"]))
	expect(a.join)
	expect_eq(a.address, "10.0.0.2")
	expect_eq(a.port, 6000)


func test_join_without_address_uses_default() -> void:
	var a: LaunchArgs = LaunchArgs.parse(PackedStringArray(["--join", "--name", "Ada"]))
	expect(a.join)
	expect_eq(a.address, Net.DEFAULT_ADDRESS)
	expect_eq(a.player_name, "Ada")


func test_bad_port_reports_error() -> void:
	var a: LaunchArgs = LaunchArgs.parse(PackedStringArray(["--port", "99999"]))
	expect_eq(a.port, Net.DEFAULT_PORT)
	expect_eq(a.errors.size(), 1)


func test_host_and_join_conflict() -> void:
	var a: LaunchArgs = LaunchArgs.parse(PackedStringArray(["--host", "--join"]))
	expect_eq(a.errors.size(), 1)


func test_terrain_lab_flag() -> void:
	expect(LaunchArgs.parse(PackedStringArray(["--terrain-lab"])).terrain_lab)
	expect(not LaunchArgs.parse(PackedStringArray()).terrain_lab)
