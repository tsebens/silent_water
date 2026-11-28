extends TestCase
## A remote peer sees a player go down and get back up, from the host's snapshots.

const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")


var _made: Array[Node] = []


func after_each() -> void:
	for n: Node in _made:
		if is_instance_valid(n):
			n.free()
	_made.clear()


func _player(id: String) -> Player:
	var p: Player = PLAYER_SCENE.instantiate() as Player
	p.name = id
	runner.add_child(p)
	_made.append(p)
	p.set_physics_process(false)
	p.set_process(false)
	p.get_node("Impairment").set_physics_process(false)
	return p


func test_remote_sees_down_and_recovery() -> void:
	# "1" is the local (authoritative) copy on the host; "2" is how it looks
	# on another peer: not its authority.
	var host_copy: Player = _player("1")
	var remote_copy: Player = _player("2")
	expect(not remote_copy.is_multiplayer_authority())
	var host_imp: PlayerImpairment = host_copy.get_node("Impairment") as PlayerImpairment
	var remote_imp: PlayerImpairment = remote_copy.get_node("Impairment") as PlayerImpairment
	host_imp.step(1.0, 90000.0, 1.0)
	remote_imp.apply_snapshot(host_imp.snapshot())
	expect(remote_copy.is_down(), "remote sees the down flag")
	remote_copy._update_collapse(Player.FALL_S * 2.0)
	expect_near(remote_copy.down_blend, 1.0)
	expect(absf(remote_copy._body_mesh.rotation.x) > 1.0, "avatar is tilted onto its back")
	host_imp.step(1.0, 400.0, 1.0)
	remote_imp.apply_snapshot(host_imp.snapshot())
	expect(not remote_copy.is_down(), "remote sees recovery")
	remote_copy._update_collapse(Player.STAND_UP_S * 2.0)
	expect_near(remote_copy.down_blend, 0.0)
	expect_near(remote_copy._body_mesh.rotation.x, 0.0)
