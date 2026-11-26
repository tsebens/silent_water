extends TestCase
## SparesDrawer: slots shown follow the spares readout.


class StubPower:
	extends Node
	var spares: int = 0

	func readout(_n: StringName) -> float:
		return float(spares)


func _make(spares: int, slot_count: int) -> Array:
	var p: StubPower = StubPower.new()
	p.spares = spares
	runner.add_child(p)
	var d: SparesDrawer = SparesDrawer.new()
	d.power = p
	for i: int in slot_count:
		var s: Node3D = Node3D.new()
		d.add_child(s)
		d.slots.append(s)
	runner.add_child(d)
	return [d, p]


func _visible(d: SparesDrawer) -> Array:
	var out: Array = []
	for s: Node3D in d.slots:
		out.append(s.visible)
	return out


func _free(a: Array) -> void:
	(a[0] as Node).free()
	(a[1] as Node).free()


func test_shown_equals_readout() -> void:
	var a: Array = _make(2, 4)
	expect_eq(_visible(a[0]), [true, true, false, false])
	_free(a)


func test_zero_shows_none() -> void:
	var a: Array = _make(0, 4)
	expect_eq(_visible(a[0]), [false, false, false, false])
	_free(a)


func test_clamped_to_slot_count() -> void:
	var a: Array = _make(9, 3)
	expect_eq(_visible(a[0]), [true, true, true])
	_free(a)


func test_follows_readout() -> void:
	var a: Array = _make(3, 4)
	(a[1] as StubPower).spares = 1
	(a[0] as SparesDrawer).refresh()
	expect_eq(_visible(a[0]), [true, false, false, false])
	_free(a)


func test_no_power_shows_none() -> void:
	var d: SparesDrawer = SparesDrawer.new()
	d.power = Node.new()
	var s: Node3D = Node3D.new()
	d.slots.append(s)
	runner.add_child(d)
	runner.add_child(s)
	expect_eq(d.shown_count(), 0)
	d.power.free()
	d.free()
	s.free()
