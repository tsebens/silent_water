extends TestCase
## What is built stays clear of the program's reserved footprints, the status board sits at its
## program entries inside the hull, and every interior light is a palette light inside the hull.

const INTERIOR_SCENE: PackedScene = preload("res://src/sub/interior.tscn")

## Floor space the program reserves for stations and features that other arcs build (the map table is M12.8).
const RESERVED: Array[StringName] = [
	&"countermeasures", &"lock_out_trunk", &"tower_ladder", &"lockers", &"map_table",
	&"science",
]

var interior: Node3D


func before_each() -> void:
	interior = INTERIOR_SCENE.instantiate() as Node3D
	runner.add_child(interior)


func after_each() -> void:
	interior.free()


## True when `n` is inside the map table's, the science station's or the countermeasures station's subtree, which their reserved footprints stand for.
func _is_map_table(n: Node) -> bool:
	return interior.get_node("Stations/Maps").is_ancestor_of(n) or interior.get_node("Stations/Science").is_ancestor_of(n) or interior.get_node("Stations/Countermeasures").is_ancestor_of(n)


func test_nothing_built_overlaps_a_reserved_footprint() -> void:
	var checked: int = 0
	for n: Node in interior.get_node("Stations").find_children("*", "Node3D", true, false):
		if _is_map_table(n):
			continue
		var p: Vector3 = (n as Node3D).global_position
		for id: StringName in RESERVED:
			var fp: Rect2 = SubLayout.footprint(id)
			if SubLayout.top_footprint(id) != fp:
				fp = fp.merge(SubLayout.top_footprint(id))
			expect(not fp.has_point(Vector2(p.x, p.z)) or p.y > 1.0 + SubLayout.position(id).y, "%s (%s) is inside %s's reserved footprint" % [n.get_path(), p, id])
		checked += 1
	expect(checked > 20, "the check covered the built stations (%d nodes)" % checked)


func test_the_map_tables_footprint_is_reserved_and_empty() -> void:
	var fp: Rect2 = SubLayout.top_footprint(&"map_table")
	expect(fp.size.x > 0.8 and fp.size.y > 2.0, "the map table's reservation is the program's (%s)" % fp)
	for id: StringName in [&"sonar", &"engineering", &"ballast", &"bilge"]:
		expect(not SubLayout.footprint(id).grow(-0.001).intersects(fp), "%s does not overlap the map table" % id)


func test_the_science_stations_footprint_is_reserved_and_empty() -> void:
	var fp: Rect2 = SubLayout.top_footprint(&"science")
	expect(fp.size.x > 0.2 and fp.size.y > 1.1 and fp.position.x > 0.0, "the science reservation is the program's long starboard one (%s)" % fp)
	for id: StringName in [&"map_table", &"lock_out_trunk", &"tower_ladder", &"sonar", &"sonar_seat", &"countermeasures", &"lockers"]:
		expect(not SubLayout.footprint(id).grow(-0.001).intersects(fp), "%s does not overlap the science station" % id)


func test_program_footprints_do_not_overlap_each_other() -> void:
	var ids: Array[StringName] = [&"science", &"engineering", &"life_support", &"ballast", &"bilge", &"lockers", &"countermeasures", &"lock_out_trunk", &"tower_ladder", &"sonar"]
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			# Shrunk by a millimetre: footprints that touch end to end are not overlapping (float rounding).
			var a: Rect2 = SubLayout.footprint(ids[i]).grow(-0.001)
			expect(not a.intersects(SubLayout.footprint(ids[j]).grow(-0.001)), "%s overlaps %s" % [ids[i], ids[j]])


func test_the_scanner_panel_is_retired() -> void:
	expect(not SubLayout.has(&"scanner"), "the program has no scanner panel")
	expect(interior.get_node_or_null("Stations/Scanner") == null, "the engineering wall has no scanner switch or gauge")


func test_status_board_is_on_the_bulkhead_above_the_hatch() -> void:
	var board: Label3D = interior.get_node("Stations/StatusBoard") as Label3D
	var p: Vector3 = board.position
	var span: Vector2 = SubLayout.compartment_span(&"bulkhead")
	expect(p.z < span.x and p.z > span.x - 0.2, "on the forward face of the bulkhead (z %.2f, bulkhead from %.2f)" % [p.z, span.x])
	expect(p.y - 0.15 > SubLayout.clearance("hatch_height_m"), "above the hatch lintel (y %.2f)" % p.y)
	expect(SubLayout.inside_hull(p.x, p.y + 0.2, p.z), "inside the hull")


func test_every_interior_light_is_a_palette_light_inside_the_hull() -> void:
	for l: Node in interior.get_node("Lights").get_children():
		var light: Light3D = l as Light3D
		expect(l.get_node_or_null("PaletteLight") is PaletteLight, "%s has a PaletteLight" % l.name)
		if l.name == &"Headlight":
			continue
		expect(SubLayout.inside_hull(light.position.x, light.position.y, light.position.z), "%s inside the hull (%s)" % [l.name, light.position])
	for f: Node in interior.get_node("Fascia").get_children():
		var p: Vector3 = (f as Node3D).position
		expect(SubLayout.inside_hull(p.x, p.y + 0.11, p.z), "%s inside the hull (%s)" % [f.name, p])
