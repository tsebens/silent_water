@tool
class_name AssetProviderChoice
extends RefCounted
## Which provider or writer a dropdown shows: the value last chosen (remembered per dropdown,
## per machine), else the effective selection from `asset list` (providers.local.yaml over
## providers.yaml). A remembered value that is no longer configured is ignored.

const MOCK: String = "mock"
const MOCK_LABEL: String = "mock (no cost, placeholder output)"
const META_KEY: String = "asset_studio"
const META_SECTION: String = "provider_choice"

## Environment variable each keyed provider needs. A provider not listed here that is not
## in NO_KEY is treated as not configured, so the mock label stays off when unsure.
const KEY_ENV: Dictionary = {
	"openai": "OPENAI_API_KEY",
	"google": "GEMINI_API_KEY",
	"google-pro": "GEMINI_API_KEY",
	"fal": "FAL_KEY",
	"tripo": "TRIPO_API_KEY",
	"meshy": "MESHY_API_KEY",
	"rodin": "RODIN_API_KEY",
	"trellis": "FAL_KEY",
	"trellis-multi": "FAL_KEY",
	"anthropic-api": "ANTHROPIC_API_KEY",
}
const NO_KEY: PackedStringArray = ["claude-cli"]

## dropdown id -> remembered provider name.
var remembered: Dictionary = {}
## Environment variable names known to be set (from the process environment or .env).
var keys_set: PackedStringArray = PackedStringArray()


## An empty value is ignored for a dropdown; `allow_empty` is for a choice that may be cleared.
func remember(dropdown: String, value: String, allow_empty: bool = false) -> void:
	if value == "" and not allow_empty:
		return
	remembered[dropdown] = value
	_save()


## The value a dropdown should select among `options`: remembered, else `effective`, else "".
func resolve(dropdown: String, options: PackedStringArray, effective: String) -> String:
	var mem: String = str(remembered.get(dropdown, ""))
	if mem != "" and options.has(mem):
		return mem
	return effective if options.has(effective) else ""


func is_configured(provider: String) -> bool:
	if provider == MOCK:
		return false
	if NO_KEY.has(provider):
		return true
	return KEY_ENV.has(provider) and keys_set.has(str(KEY_ENV[provider]))


## True when a real (non-mock) provider among `options` has its key set.
func has_real_provider(options: PackedStringArray) -> bool:
	for o: String in options:
		if is_configured(o):
			return true
	return false


## Item text: the mock entry reads as free placeholder output when a real provider could be used.
func label(provider: String, options: PackedStringArray, effective: String) -> String:
	if provider == MOCK and effective == MOCK and has_real_provider(options):
		return MOCK_LABEL
	return provider


## Which of KEY_ENV's variables are set in the environment or the given .env text.
static func keys_from(env_text: String) -> PackedStringArray:
	var names: Dictionary = {}
	for v: Variant in KEY_ENV.values():
		names[str(v)] = true
	var out: PackedStringArray = PackedStringArray()
	for n: Variant in names:
		if OS.get_environment(str(n)) != "":
			out.append(str(n))
	for line: String in env_text.split("\n"):
		var s: String = line.strip_edges()
		if s.begins_with("export "):
			s = s.substr(7).strip_edges()
		var eq: int = s.find("=")
		if eq <= 0 or s.begins_with("#"):
			continue
		var key: String = s.substr(0, eq).strip_edges()
		var val: String = s.substr(eq + 1).strip_edges().trim_prefix("\"").trim_suffix("\"").trim_prefix("'").trim_suffix("'")
		if names.has(key) and val != "" and not out.has(key):
			out.append(key)
	return out


## Reads the remembered choices from the editor's per-project metadata (editor only).
func load_saved() -> void:
	if not Engine.is_editor_hint():
		return
	var v: Variant = EditorInterface.get_editor_settings().get_project_metadata(META_KEY, META_SECTION, {})
	if v is Dictionary:
		remembered = (v as Dictionary).duplicate()


func _save() -> void:
	if Engine.is_editor_hint():
		EditorInterface.get_editor_settings().set_project_metadata(META_KEY, META_SECTION, remembered)
