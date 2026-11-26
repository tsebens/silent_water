extends TestCase
## The generated hand pump: a HandPump with its lever bound; the handle sits where the entry says at both ends of travel.

const SCENE: String = "res://assets/models/kit/hand_pump/hand_pump.tscn"
const PIVOT_Z: float = 0.082
const SHAFT_LEN: float = 0.420
## component.yaml handle_tip_mm: up (value 0) and down (value 1), as (y, z).
const UP_YZ: Vector2 = Vector2(0.17750, 0.46265)
const DOWN_YZ: Vector2 = Vector2(-0.17750, 0.46265)
const STAND_OUT: float = 0.51509


func _make() -> HandPump:
	var p: HandPump = (load(SCENE) as PackedScene).instantiate() as HandPump
	runner.add_child(p)
	return p


## The handle's centre in the root's frame: the pivot's transform applied to the end of the shaft.
func _handle(p: HandPump) -> Vector2:
	var tip: Vector3 = p.pivot.transform * Vector3(0.0, 0.0, SHAFT_LEN)
	return Vector2(tip.y, tip.z)


func _meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c: Node in n.get_children():
		_meshes(c, out)


func test_root_is_a_hand_pump_with_the_lever_bound() -> void:
	var p: HandPump = _make()
	expect(p != null, "root is a HandPump")
	expect(p.pivot != null and p.pivot.name == &"Pivot", "pivot bound")
	expect(p.pivot.get_node_or_null("Lever") != null, "lever under the pivot")
	expect_near(p.pivot.position.z, PIVOT_Z, 0.0001, "pivot height")
	p.queue_free()


func test_handle_matches_the_entry_at_both_ends() -> void:
	var p: HandPump = _make()
	p.host_set_value(0.0)
	var up: Vector2 = _handle(p)
	expect_near(up.x, UP_YZ.x, 0.001, "up y")
	expect_near(up.y, UP_YZ.y, 0.001, "up z")
	p.host_set_value(1.0)
	var down: Vector2 = _handle(p)
	expect_near(down.x, DOWN_YZ.x, 0.001, "down y")
	expect_near(down.y, DOWN_YZ.y, 0.001, "down z")
	expect(up.x > 0.0 and down.x < 0.0, "up at rest, down at the end of the stroke")
	p.queue_free()


func test_nothing_behind_the_mount_face_or_past_the_stand_out() -> void:
	var p: HandPump = _make()
	var ms: Array[MeshInstance3D] = []
	_meshes(p, ms)
	expect(ms.size() >= 2, "body and lever meshes")
	for v: float in [0.0, 0.5, 1.0]:
		p.host_set_value(v)
		for m: MeshInstance3D in ms:
			var box: AABB = p.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
			expect(box.position.z >= -0.0001, "nothing behind the mount face at %s: %s" % [v, box])
			expect(box.end.z <= STAND_OUT + 0.0005, "within the stand-out at %s: %s" % [v, box])
	p.queue_free()


func test_grab_box_covers_the_sweep() -> void:
	var p: HandPump = _make()
	var grab: Node = p.get_node_or_null("Grab/Shape")
	expect(grab != null, "grab box present")
	var cs: CollisionShape3D = grab as CollisionShape3D
	var shape: BoxShape3D = cs.shape as BoxShape3D
	var lo: float = cs.position.y - shape.size.y / 2.0
	var hi: float = cs.position.y + shape.size.y / 2.0
	expect(lo < DOWN_YZ.x and hi > UP_YZ.x, "box spans both handle ends: %s" % shape.size)
	expect(shape.size.z >= STAND_OUT - 0.001, "box reaches the stand-out")
	p.queue_free()
