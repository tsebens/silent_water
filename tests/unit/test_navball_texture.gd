extends TestCase
## The navball's marking mask (tools/navball_texture.py): R upper hemisphere, G lower hemisphere, B markings.

const MASK: String = "res://assets/textures/navball_mask.png"
const TOOL: String = "res://tools/navball_texture.py"
const WIDTH: int = 2048
const HEIGHT: int = 1024
const HORIZON_ROW: int = 512


func _load() -> Image:
	var img: Image = Image.new()
	var err: int = img.load(ProjectSettings.globalize_path(MASK))
	expect_eq(err, OK, "mask PNG loads")
	return img


func _row_has_mark(img: Image, y: int) -> bool:
	for x in range(WIDTH):
		if img.get_pixel(x, y).b > 0.5:
			return true
	return false


func test_size_and_format() -> void:
	var img: Image = _load()
	expect_eq(img.get_width(), WIDTH)
	expect_eq(img.get_height(), HEIGHT)


func test_channels_are_masks_and_hemispheres_complementary() -> void:
	var img: Image = _load()
	for y in range(0, HEIGHT, 8):
		for x in range(0, WIDTH, 16):
			var c: Color = img.get_pixel(x, y)
			expect_near(c.r + c.g, 1.0, 0.001, "R + G at %d,%d" % [x, y])
			expect(c.r < 0.001 or c.r > 0.999, "R is a mask value")
			expect(c.b < 0.001 or c.b > 0.999, "B is a mask value")
			expect_eq(c.r > 0.5, y < HORIZON_ROW, "upper hemisphere is above the horizon at row %d" % y)


func test_ladder_rows_marked() -> void:
	var img: Image = _load()
	for n in range(1, 9):
		for sign: int in [1, -1]:
			var lat: float = float(sign * n * 10)
			var y: int = int(round((90.0 - lat) * HEIGHT / 180.0 - 0.5))
			expect(_row_has_mark(img, y), "ladder row at %d degrees" % int(lat))
	expect(_row_has_mark(img, 0), "north pole row")
	expect(_row_has_mark(img, HEIGHT - 1), "south pole row")


func test_heading_marks() -> void:
	var img: Image = _load()
	for h in range(0, 360, 10):
		var x: int = int(round(((360 - h) % 360) * WIDTH / 360.0))
		var found: bool = false
		for dy: int in [-12, 12]:
			if img.get_pixel(x % WIDTH, HORIZON_ROW + dy).b > 0.5:
				found = true
		expect(found, "heading mark at %d" % h)


func test_committed_png_matches_tool() -> void:
	var tmp: String = OS.get_temp_dir().path_join("silent_water_navball_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(tmp)
	var out: String = tmp.path_join("navball_mask.png")
	var output: Array = []
	var rc: int = OS.execute("uv", ["run", ProjectSettings.globalize_path(TOOL), out], output, true)
	expect_eq(rc, 0, "navball_texture.py failed or uv is missing: %s" % str(output))
	if rc != 0:
		return
	expect(FileAccess.get_file_as_bytes(out) == FileAccess.get_file_as_bytes(MASK), "navball_mask.png is stale: run tools/navball_texture.py and commit")
