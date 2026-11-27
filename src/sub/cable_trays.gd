class_name CableTrays
extends Node3D
## The cable trays that carry each circuit's line from the electrical board to its junction boxes (#581, concept #577).
## Every run is computed from the program (SubLayout), so nothing here is a hull-frame literal: a feed from the board's
## top up to the overhead, a starboard trunk and a port trunk along the walls at [constant TRAY_Y], and one crossover
## aft of the bulkhead joining them. The trays hang above head clearance, so they leave the aisle and every station
## clear. Circuit [code]c[/code]'s boxes sit on the trunks at [method box_z]: box 0 on the port trunk, box 1 on the
## starboard trunk. The node builds the tray meshes and places the [JunctionBox] children of [member boxes].

## Tray centre height in the interior frame: its underside (TRAY_HEIGHT / 2 lower) stays above head clearance.
const TRAY_Y: float = 2.1
const TRAY_WIDTH: float = 0.2
const TRAY_HEIGHT: float = 0.06
## Gap kept between the tray's outer edge and the hull's inner surface.
const WALL_GAP: float = 0.05
## Spacing of the vertices along a trunk (the hull curves, so a trunk is a polyline).
const STEP: float = 0.2
## Where the first circuit's boxes sit along the hull, and the spacing between circuits (m).
const BOX_Z0: float = -1.6
const BOX_DZ: float = 0.4
## Where the crossover joins the two trunks, aft of the bulkhead (the board is further aft still).
const CROSS_Z: float = 2.0
## Height the feed leaves the board at, above its top (m).
const FEED_RISE: float = 0.65

## Path of the electrical board's node (a Node3D whose origin is the board's centre).
@export var board: NodePath
## Path of the node whose [JunctionBox] children are placed on the trunks (a sibling at the same origin).
@export var boxes: NodePath


## z of circuit [param circuit]'s boxes.
static func box_z(circuit: int) -> float:
	return BOX_Z0 + BOX_DZ * float(circuit)


## Centre x of a trunk at hull station [param z]: [param side] 1 starboard, -1 port; the tray's outer edge a gap off the wall.
static func wall_x(side: float, z: float) -> float:
	var lo: float = 0.0
	var hi: float = SubLayout.hull_size().x / 2.0
	for i: int in 24:
		var mid: float = (lo + hi) / 2.0
		if SubLayout.inside_hull(mid, TRAY_Y + TRAY_HEIGHT / 2.0, z):
			lo = mid
		else:
			hi = mid
	return side * (lo - WALL_GAP - TRAY_WIDTH / 2.0)


## A trunk's centre line, aft to fore, from the board's z to the first box.
static func trunk(side: float, from_z: float) -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	pts.append(Vector3(wall_x(side, from_z), TRAY_Y, from_z))
	var z: float = CROSS_Z
	while z >= BOX_Z0 - 0.001:
		pts.append(Vector3(wall_x(side, z), TRAY_Y, z))
		z -= STEP
	return pts


## The point on the tray where circuit [param circuit]'s box [param index] sits.
static func box_point(circuit: int, index: int) -> Vector3:
	var side: float = 1.0 if index == 1 else -1.0
	var z: float = box_z(circuit)
	return Vector3(wall_x(side, z), TRAY_Y, z)


## Every run of the network for a board centred at [param board_pos]: the feed, the starboard trunk, the crossover and
## the port trunk, each a polyline of tray centre points. The feed starts above the board and ends on the starboard
## trunk's first point; the crossover joins the trunks at [constant CROSS_Z].
static func runs(board_pos: Vector3) -> Array[PackedVector3Array]:
	var wx: float = wall_x(1.0, board_pos.z)
	var top: float = board_pos.y + FEED_RISE
	var feed: PackedVector3Array = PackedVector3Array([
		Vector3(board_pos.x, top, board_pos.z), Vector3(wx, top, board_pos.z), Vector3(wx, TRAY_Y, board_pos.z)])
	var out: Array[PackedVector3Array] = [feed]
	out.append(trunk(1.0, board_pos.z))
	out.append(PackedVector3Array([Vector3(wall_x(1.0, CROSS_Z), TRAY_Y, CROSS_Z), Vector3(wall_x(-1.0, CROSS_Z), TRAY_Y, CROSS_Z)]))
	out.append(trunk(-1.0, CROSS_Z))
	return out


func _ready() -> void:
	var board_node: Node3D = get_node_or_null(board) as Node3D
	assert(board_node != null, "CableTrays: no board at '%s'" % board)
	if board_node == null:
		return
	var pos: Vector3 = to_local(board_node.global_position)
	for run: PackedVector3Array in runs(pos):
		_build(run)
	var holder: Node = get_node_or_null(boxes)
	if holder == null:
		return
	for n: Node in holder.get_children():
		var jb: JunctionBox = n as JunctionBox
		if jb != null:
			jb.position = box_point(jb.circuit, jb.box_index)


func _build(run: PackedVector3Array) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Palette.main().color(&"sub_grey_dark")
	for i: int in range(run.size() - 1):
		var a: Vector3 = run[i]
		var b: Vector3 = run[i + 1]
		var seg: float = a.distance_to(b)
		if seg < 0.001:
			continue
		var m: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(TRAY_WIDTH, TRAY_HEIGHT, seg)
		box.material = mat
		m.mesh = box
		add_child(m)
		m.position = (a + b) / 2.0
		m.look_at_from_position(m.position, b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
