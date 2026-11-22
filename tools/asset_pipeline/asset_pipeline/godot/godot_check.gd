extends SceneTree
## Driven by `asset godot-check`. Loads an imported asset GLB and either verifies
## its materials (--verify) or renders it in game-like lighting (--render).
## Usage: godot --path <root> --script <this> -- <verify|render> <res://model.glb> <out_prefix>
## Prints one line starting with ASSET_CHECK: followed by a JSON object.

const SHOTS: Array[String] = ["fog", "white", "red"]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 3:
		_finish({"ok": false, "error": "usage: <verify|render> <res://model.glb> <out_prefix>"})
		return
	var res: Resource = load(args[1])
	var packed: PackedScene = res as PackedScene
	if packed == null:
		_finish({"ok": false, "error": "could not load %s as a scene (import failed?)" % args[1]})
		return
	var inst: Node = packed.instantiate()
	if args[0] == "verify":
		_finish(_verify(inst))
	else:
		_render(inst, args[2])


func _meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null and mi.mesh != null:
		out.append(mi)
	for c: Node in node.get_children():
		_meshes(c, out)


func _verify(inst: Node) -> Dictionary:
	var meshes: Array[MeshInstance3D] = []
	_meshes(inst, meshes)
	var surfaces: int = 0
	var with_flag: int = 0
	for mi: MeshInstance3D in meshes:
		for s: int in mi.mesh.get_surface_count():
			surfaces += 1
			var mat: BaseMaterial3D = mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat != null and mat.vertex_color_use_as_albedo:
				with_flag += 1
	return {"ok": surfaces > 0 and with_flag == surfaces, "meshes": meshes.size(), "surfaces": surfaces,
			"vertex_color_use_as_albedo": with_flag}


func _bounds(inst: Node) -> AABB:
	var meshes: Array[MeshInstance3D] = []
	_meshes(inst, meshes)
	var box: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in meshes:
		var b: AABB = mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _render(inst: Node, prefix: String) -> void:
	if DisplayServer.get_name() == "headless":
		_finish({"ok": false, "error": "no rendering device: Godot is running with the headless display server"})
		return
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.05, 0.12, 0.16)
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.10, 0.14)
	env.fog_density = 0.04
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	root.add_child(inst)
	var box: AABB = _bounds(inst)
	var radius: float = maxf(box.size.length() * 0.5, 0.01)
	var centre: Vector3 = box.get_center()
	var cam: Camera3D = Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(centre + Vector3(0.6, 0.35, 1.0).normalized() * radius * 2.6, centre)
	cam.make_current()
	var light: OmniLight3D = OmniLight3D.new()
	light.omni_range = radius * 12.0
	light.light_energy = 6.0
	root.add_child(light)
	light.position = cam.position + Vector3(0.0, radius * 0.5, 0.0)
	root.size = Vector2i(640, 480)
	var written: Array[String] = []
	for shot: String in SHOTS:
		light.visible = shot != "fog"
		light.light_color = Color(1, 0.05, 0.03) if shot == "red" else Color(1, 1, 1)
		for i: int in 3:
			await process_frame
		var img: Image = root.get_texture().get_image()
		var path: String = "%s_%s.png" % [prefix, shot]
		if img == null or img.save_png(path) != OK:
			_finish({"ok": false, "error": "could not write %s" % path})
			return
		written.append(path)
	_finish({"ok": true, "renders": written})


func _finish(result: Dictionary) -> void:
	print("ASSET_CHECK:" + JSON.stringify(result))
	quit(0 if result.get("ok", false) else 1)
