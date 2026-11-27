extends TestCase
## Whole-sub audit: the built interior against the program. No two stations overlap, nothing is in the hull wall or
## below the deck, the aisle, the bulkhead hatch and head clearance hold, the hand pump's lever clears at both ends of its
## sweep, the reserved footprints are empty, and the retired placeholders are gone (arc #580, concept #577).

const INTERIOR_SCENE: PackedScene = preload("res://src/sub/interior.tscn")

## Built station roots (under Stations) and the program ids whose footprint each stands for.
const BUILT: Dictionary = {
	"Stations/Sonar": &"sonar",
	"Stations/Ballast/Panel": &"ballast",
	"Stations/Engineering/Panel": &"engineering",
	"Stations/LifeSupport/Station": &"life_support",
	"Stations/Maps/MapTable/Station": &"map_table",
}

## Program reservations nothing may be built in.
const RESERVED: Array[StringName] = [&"countermeasures", &"lock_out_trunk", &"tower_ladder", &"lockers", &"science"]

## Nodes the old scene carried as placeholders; each was replaced by a placed station.
const RETIRED: Array[String] = [
	"Stations/Bilge", "Stations/BilgeSign", "Stations/Ballast/FloodValve", "Stations/Ballast/TankGauge",
	"Stations/Pilot/CenterPod", "Stations/Pilot/LeftPod", "Stations/Pilot/RightPod", "Hull/GaugePanel",
]

## How far (m) a wall-hugging console's back corner may sink past the hull's inner surface: the plating (0.12) plus the curve.
const FLANGE_M: float = 0.4

var interior: Node3D


func before_each() -> void:
	interior = INTERIOR_SCENE.instantiate() as Node3D
	runner.add_child(interior)


func after_each() -> void:
	interior.free()


## World-space boxes of the visible meshes under `n`.
func _boxes(n: Node) -> Array[AABB]:
	var out: Array[AABB] = []
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = c as MeshInstance3D
		if m.mesh != null and m.visible:
			out.append(m.global_transform * m.get_aabb())
	return out


func _plan(boxes: Array[AABB]) -> Rect2:
	var r: Rect2 = Rect2()
	for i: int in boxes.size():
		var b: Rect2 = Rect2(boxes[i].position.x, boxes[i].position.z, boxes[i].size.x, boxes[i].size.z)
		r = b if i == 0 else r.merge(b)
	return r


## True when `c` is not far past the hull's inner surface: pulled toward the hull's axis by FLANGE_M it is
## inside it. Consoles are boxes set against a curved wall, so their back corners legitimately sink into the plating.
func _in_hull(c: Vector3) -> bool:
	var d: Vector2 = Vector2(c.x, c.y - SubLayout.hull_centre_y())
	var pulled: Vector2 = d - d.normalized() * FLANGE_M
	return SubLayout.inside_hull(pulled.x, pulled.y + SubLayout.hull_centre_y(), c.z)


## Every mesh vertex under `n`, in world space (sampled to keep the sweep quick on dense meshes).
func _vertices(n: Node) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = c as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var faces: PackedVector3Array = m.mesh.get_faces()
		for i: int in range(0, faces.size(), 3):
			out.append(m.global_transform * faces[i])
	return out


func test_no_two_built_stations_overlap() -> void:
	var ids: Array = BUILT.keys()
	var plans: Dictionary = {}
	for path: String in ids:
		var node: Node = interior.get_node_or_null(path)
		expect(node != null, "%s is built" % path)
		if node != null:
			plans[path] = _plan(_boxes(node))
	for i: int in ids.size():
		for j: int in range(i + 1, ids.size()):
			if plans.has(ids[i]) and plans.has(ids[j]):
				expect(not (plans[ids[i]] as Rect2).grow(-0.001).intersects((plans[ids[j]] as Rect2).grow(-0.001)),
					"%s overlaps %s" % [ids[i], ids[j]])


func test_nothing_is_inside_the_hull_wall_or_below_the_deck() -> void:
	var checked: int = 0
	for path: String in BUILT:
		for v: Vector3 in _vertices(interior.get_node(path)):
			expect(_in_hull(v), "%s vertex %s is outside the hull's inner surface" % [path, v])
		for b: AABB in _boxes(interior.get_node(path)):
			expect(b.position.y > -0.05, "%s sits on the deck (y %.2f)" % [path, b.position.y])
			checked += 1
	expect(checked > 10, "the check covered the built meshes (%d)" % checked)


func test_nothing_built_is_in_a_reserved_footprint() -> void:
	for path: String in BUILT:
		var fp: Rect2 = _plan(_boxes(interior.get_node(path)))
		for id: StringName in RESERVED:
			var r: Rect2 = SubLayout.top_footprint(id).grow(-0.001)
			expect(not fp.intersects(r), "%s intrudes on %s's reservation" % [path, id])


func test_the_aisle_stays_open_along_the_whole_walkway() -> void:
	var port: Array[Rect2] = []
	var starboard: Array[Rect2] = []
	for path: String in BUILT:
		var fp: Rect2 = _plan(_boxes(interior.get_node(path)))
		(starboard if fp.get_center().x > 0.0 else port).append(fp)
	# Floor items on either side too: the trunk is flush, the ladder and lockers are reserved.
	for id: StringName in [&"lockers", &"tower_ladder"]:
		port.append(SubLayout.footprint(id))
	for id: StringName in [&"countermeasures", &"science"]:
		starboard.append(SubLayout.footprint(id))
	var aisle: float = SubLayout.clearance("aisle_min_m")
	var z: float = SubLayout.compartment_span(&"midships").x
	var end: float = SubLayout.compartment_span(&"engineering").y - 1.0
	while z < end:
		var left: float = -INF
		var right: float = INF
		for r: Rect2 in port:
			if z >= r.position.y and z <= r.end.y:
				left = maxf(left, r.end.x)
		for r: Rect2 in starboard:
			if z >= r.position.y and z <= r.end.y:
				right = minf(right, r.position.x)
		if left > -INF and right < INF:
			expect(right - left >= aisle - 0.001, "aisle %.2f m at z %.2f (need %.2f)" % [right - left, z, aisle])
		z += 0.05


func test_the_bulkhead_hatch_stays_clear() -> void:
	var span: Vector2 = SubLayout.compartment_span(&"bulkhead")
	var half: float = SubLayout.clearance("hatch_width_m") * 0.5
	var lintel: float = SubLayout.clearance("hatch_height_m")
	var hatch: Rect2 = Rect2(-half, span.x - 0.3, half * 2.0, span.y - span.x + 0.6)
	for path: String in BUILT:
		for b: AABB in _boxes(interior.get_node(path)):
			if b.position.y < lintel:
				expect(not Rect2(b.position.x, b.position.z, b.size.x, b.size.z).intersects(hatch), "%s blocks the bulkhead hatch" % path)


func test_head_clearance_above_the_walkway() -> void:
	var head: float = SubLayout.clearance("head_clear_m")
	for z: float in [-2.5, -1.0, 0.0, 1.0, 2.5, 3.5]:
		var half: Vector2 = SubLayout.hull_inner_half(z)
		expect(SubLayout.inside_hull(0.0, SubLayout.main_deck_y() + head, z), "2 m of headroom on the centreline at z %.1f (half height %.2f)" % [z, half.y])


func test_the_hand_pump_lever_clears_everything_at_both_ends_of_its_sweep() -> void:
	var pump: HandPump = interior.get_node("Stations/Ballast/Panel/HandPump") as HandPump
	var bilge: Rect2 = SubLayout.footprint(&"bilge")
	var scanner: Rect2 = SubLayout.footprint(&"engineering")
	var aisle: float = SubLayout.clearance("aisle_min_m")
	for v: float in [0.0, 1.0]:
		pump._apply_visual(v)
		var r: Rect2 = _plan(_boxes(pump.pivot))
		expect(not r.intersects(bilge), "the lever at %.0f is clear of the bilge well" % v)
		for id: StringName in RESERVED:
			expect(not r.intersects(SubLayout.top_footprint(id).grow(-0.001)), "the lever at %.0f is clear of %s" % [v, id])
		expect(scanner.position.x - r.end.x >= aisle, "aisle %.2f m with the lever at %.0f" % [scanner.position.x - r.end.x, v])
		for c: Vector3 in _vertices(pump.pivot):
			expect(_in_hull(c), "the lever at %.0f is inside the hull (%s)" % [v, c])
	pump._apply_visual(0.0)


func test_the_science_and_countermeasures_footprints_are_clear() -> void:
	for id: StringName in [&"science", &"countermeasures"]:
		var fp: Rect2 = SubLayout.top_footprint(id).grow(-0.001)
		for n: Node in interior.get_node("Stations").find_children("*", "Node3D", true, false):
			if interior.get_node("Stations/Maps").is_ancestor_of(n):
				continue
			var p: Vector3 = (n as Node3D).global_position
			expect(not (fp.has_point(Vector2(p.x, p.z)) and p.y < 1.0 + SubLayout.position(id).y), "%s is inside %s" % [n.get_path(), id])


func test_retired_placeholders_are_gone() -> void:
	for path: String in RETIRED:
		expect(interior.get_node_or_null(path) == null, "%s is retired" % path)
