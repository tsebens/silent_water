class_name LaunchArgs
extends RefCounted
## Parses user command-line arguments (the ones after `--`).
##
## Supported:
##   --host                start hosting immediately
##   --join [address]      join a host (default 127.0.0.1)
##   --port <n>            port for host or join
##   --name <s>            display name for this player
## Both `--key value` and `--key=value` forms are accepted.

var host: bool = false
var join: bool = false
var address: String = Net.DEFAULT_ADDRESS
var port: int = Net.DEFAULT_PORT
var player_name: String = ""
var errors: PackedStringArray = PackedStringArray()


static func parse(args: PackedStringArray) -> LaunchArgs:
	var result: LaunchArgs = LaunchArgs.new()
	var i: int = 0
	while i < args.size():
		var key: String = args[i]
		var value: String = ""
		var has_inline_value: bool = false
		var eq: int = key.find("=")
		if key.begins_with("--") and eq != -1:
			value = key.substr(eq + 1)
			key = key.substr(0, eq)
			has_inline_value = true
		var next_is_value: bool = (
			not has_inline_value
			and i + 1 < args.size()
			and not args[i + 1].begins_with("--")
		)
		match key:
			"--host":
				result.host = true
			"--join":
				result.join = true
				if has_inline_value:
					result.address = value
				elif next_is_value:
					i += 1
					result.address = args[i]
			"--port":
				if not has_inline_value and next_is_value:
					i += 1
					value = args[i]
				if value.is_valid_int() and int(value) > 0 and int(value) < 65536:
					result.port = int(value)
				else:
					result.errors.append("invalid port: '%s'" % value)
			"--name":
				if not has_inline_value and next_is_value:
					i += 1
					value = args[i]
				result.player_name = value
			_:
				pass  # Unknown args are ignored so tools can add their own.
		i += 1
	if result.host and result.join:
		result.errors.append("--host and --join are mutually exclusive")
	return result
