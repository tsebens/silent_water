extends TestCase
## The gauge draws in palette colours: readout ink on an info-black face, dark text on the label plate.


func _labels(g: Gauge) -> Array[Label3D]:
	var out: Array[Label3D] = []
	for child: Node in g.get_children():
		if child is Label3D:
			out.append(child as Label3D)
	return out


func test_drawn_colours_follow_the_palette() -> void:
	var pal: Palette = Palette.main()
	var old_ink: Color = pal.color(&"light_readout")
	var old_face: Color = pal.color(&"info_black")
	var g: Gauge = Gauge.new()
	g.readout_b = &"speed"
	runner.add_child(g)

	var ink: Color = Color(1.0, 0.0, 0.0)
	var face: Color = Color(0.0, 0.0, 0.5)
	pal.set_color(&"light_readout", ink)
	pal.set_color(&"info_black", face)

	var face_mat: StandardMaterial3D = (g.get_node("Face") as MeshInstance3D).mesh.material as StandardMaterial3D
	expect(face_mat.albedo_color.is_equal_approx(face), "face follows info_black")
	var marks_mat: StandardMaterial3D = (g.get_node("Marks") as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
	expect(marks_mat.emission.is_equal_approx(ink), "tick marks follow light_readout")
	for n: String in ["Needle", "NeedleB"]:
		var found: bool = false
		for child: Node in g.get_node(n).get_child(0).get_children():
			var mi: MeshInstance3D = child as MeshInstance3D
			if mi != null and mi.material_override != null:
				found = true
				expect((mi.material_override as StandardMaterial3D).emission.is_equal_approx(ink), n + " follows light_readout")
		expect(found, n + " has a role material")
	for l: Label3D in _labels(g):
		var want: Color = face if l.name == "Title" else ink
		expect(l.modulate.is_equal_approx(want), "label '%s' follows the palette" % l.text)

	pal.set_color(&"light_readout", old_ink)
	pal.set_color(&"info_black", old_face)
	expect(_labels(g)[0].modulate.is_equal_approx(old_face), "restored")


func test_gauge_script_has_no_colour_literal() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/interact/gauge.gd")
	expect(not src.contains("Color("), "gauge.gd has no Color( literal")
