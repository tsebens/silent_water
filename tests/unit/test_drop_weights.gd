extends TestCase
## DropWeightsButton: gated on the guard, once per dive, sheds mass, replicated state.


func _make() -> Array:
	var ctrl: SubController = SubController.new()
	runner.add_child(ctrl)
	var guard: Lever = Lever.new()
	runner.add_child(guard)
	var btn: PushButton = PushButton.new()
	runner.add_child(btn)
	var d: DropWeightsButton = DropWeightsButton.new()
	d.simulate_host = true
	d.guard = guard
	d.button = btn
	d.controller = ctrl
	runner.add_child(d)
	return [d, ctrl, guard, btn]


func _free(a: Array) -> void:
	for n: Node in a:
		n.queue_free()


func _open(guard: Lever) -> void:
	guard.begin_interaction()
	guard.drive_to(guard.max_value)
	guard.end_interaction()


func test_closed_guard_does_nothing() -> void:
	var a: Array = _make()
	var d: DropWeightsButton = a[0]
	var m: SubPhysicsModel = (a[1] as SubController).model
	var before: float = m.total_mass_t()
	d.request_release()
	expect(not d.is_released())
	expect_eq(m.total_mass_t(), before)
	_free(a)


func test_open_guard_press_sheds_once_and_signals() -> void:
	var a: Array = _make()
	var d: DropWeightsButton = a[0]
	var m: SubPhysicsModel = (a[1] as SubController).model
	_open(a[2])
	var count: Array = [0]
	d.released.connect(func() -> void: count[0] += 1)
	var before: float = m.total_mass_t()
	d.request_release()
	expect_eq(m.total_mass_t(), before - m.drop_weights_t)
	expect_eq(count[0], 1)
	d.request_release()
	expect_eq(m.total_mass_t(), before - m.drop_weights_t)
	expect_eq(count[0], 1)
	_free(a)


func test_button_press_by_holder_releases() -> void:
	var a: Array = _make()
	var d: DropWeightsButton = a[0]
	_open(a[2])
	var btn: PushButton = a[3]
	btn.begin_interaction()
	btn.end_interaction()
	expect(d.is_released())
	_free(a)


func test_reset_rearms() -> void:
	var a: Array = _make()
	var d: DropWeightsButton = a[0]
	var ctrl: SubController = a[1]
	_open(a[2])
	d.request_release()
	ctrl.model = SubPhysicsModel.new()
	d.reset()
	expect(not d.is_released())
	var before: float = ctrl.model.total_mass_t()
	d.request_release()
	expect_eq(ctrl.model.total_mass_t(), before - ctrl.model.drop_weights_t)
	_free(a)


func test_drop_recorded_in_session_log() -> void:
	var log: SessionLog = SessionLog.new()
	log.record_drop_weights(6.0, 40.0)
	expect_eq(log.drops_recorded, 1)
	log.free()


func test_neutral_sub_with_weights_shed_rises() -> void:
	var m: SubPhysicsModel = SubPhysicsModel.new()
	m.position = Vector3(0.0, -50.0, 0.0)
	m.tank_water_t = 10.0
	expect(absf(m.buoyancy_accel()) < 0.05)
	m.shed_drop_weights()
	expect(m.buoyancy_accel() > 0.2)
	expect_eq(m.shed_drop_weights(), 0.0)


func test_client_receives_state_from_host_once() -> void:
	# A client takes the host's state broadcast; a repeat does not re-emit.
	var a: Array = _make()
	var d: DropWeightsButton = a[0]
	var count: Array = [0]
	d.released.connect(func() -> void: count[0] += 1)
	d._rpc_state(true)
	d._rpc_state(true)
	expect(d.is_released())
	expect_eq(count[0], 1)
	_free(a)
