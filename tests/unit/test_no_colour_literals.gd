extends TestCase
## Code names palette swatches, never colour values (docs/palette.md). Scans src/ for colour literals.

const ROOT: String = "res://src"
## Files and folders where colour values are allowed.
const ALLOWED: PackedStringArray = [
	"res://src/palette/",
	"res://src/debug/",
	"res://src/lab/",
	"res://src/ui/reticle.gd",
]
## Named colours that are neutral rather than a design choice.
const NEUTRAL: PackedStringArray = ["WHITE", "BLACK", "TRANSPARENT"]
## A line carrying this marker is exempt, with the reason after it.
const MARKER: String = "palette-ok"

var _literal: RegEx
var _named: RegEx


func before_each() -> void:
	_literal = RegEx.create_from_string("\\bColor8?\\(\\s*[-+.\\d\"']|\\bColor\\.from_[a-z_]+\\(")
	_named = RegEx.create_from_string("\\bColor\\.([A-Z][A-Z_0-9]*)\\b")


## The lines of one script's text that hold a colour literal, as "line: text".
func violations(text: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var n: int = 0
	for line: String in text.split("\n"):
		n += 1
		var code: String = line.get_slice("#", 0)
		if line.contains(MARKER):
			continue
		var bad: bool = _literal.search(code) != null
		for m: RegExMatch in _named.search_all(code):
			if not NEUTRAL.has(m.get_string(1)):
				bad = true
		if bad:
			out.append("%d: %s" % [n, line.strip_edges()])
	return out


func _scripts(dir: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d: String in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + "/" + d))
	return out


func _allowed(path: String) -> bool:
	for a: String in ALLOWED:
		if path == a or (a.ends_with("/") and path.begins_with(a)):
			return true
	return false


func test_src_has_no_colour_literals() -> void:
	var scripts: PackedStringArray = _scripts(ROOT)
	expect(scripts.size() > 20, "found the scripts under src/")
	for path: String in scripts:
		if _allowed(path):
			continue
		for v: String in violations(FileAccess.get_file_as_string(path)):
			expect(false, "%s:%s (ask Palette.main().color(&\"<swatch>\") instead)" % [path, v])


func test_detector_catches_literals() -> void:
	expect(not violations("var c := Color(0.2, 0.3, 0.4)").is_empty(), "numeric constructor")
	expect(not violations("var c := Color(1, 0, 0)").is_empty(), "integer constructor")
	expect(not violations("var c := Color(\"#ff0000\")").is_empty(), "string constructor")
	expect(not violations("var c := Color.RED").is_empty(), "named colour")
	expect(not violations("var c := Color.from_hsv(0.1, 0.5, 0.8)").is_empty(), "hsv")
	expect(not violations("var c := Color8(255, 0, 0)").is_empty(), "8-bit")


func test_detector_allows_palette_use() -> void:
	expect(violations("var c := Color(Palette.main().color(&\"light_alarm\"), 0.6)").is_empty(), "alpha wrap")
	expect(violations("var c := Color.WHITE").is_empty(), "white")
	expect(violations("var c := Color.TRANSPARENT").is_empty(), "transparent")
	expect(violations("var c := Color(0.2, 0.3, 0.4) # palette-ok: per-peer tint").is_empty(), "marker")
	expect(violations("# Color(0.2, 0.3, 0.4) in a comment").is_empty(), "comment")
