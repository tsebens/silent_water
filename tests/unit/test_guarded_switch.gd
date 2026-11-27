extends TestCase
## GuardedSwitch: two-click arm, cap closes on off, auto-drop, replicated cap, hints.


func _make() -> GuardedSwitch:
	var s: GuardedSwitch = GuardedSwitch.new()
	var cap: Node3D = Node3D.new()
	cap.name = "Cap"
	s.add_child(cap)
	runner.add_child(s)
	return s


func _click(s: GuardedSwitch) -> void:
	s.begin_interaction()
	s.click_action()
	s.end_interaction()


func test_first_click_lifts_cap_value_unchanged() -> void:
	var s: GuardedSwitch = _make()
	_click(s)
	expect(s.cap_open, "cap open")
	expect_eq(s.get_value(), s.min_value, "still off")
	expect(absf((s.get_node("Cap") as Node3D).rotation.x) > 0.1, "cap posed open")
	s.queue_free()


func test_second_click_sets_on_cap_stays_open() -> void:
	var s: GuardedSwitch = _make()
	_click(s)
	_click(s)
	expect_eq(s.get_value(), s.max_value, "on")
	expect(s.cap_open, "cap stays open")
	s.step_cap(30.0)
	expect(s.cap_open, "no auto-drop while on")
	s.queue_free()


func test_click_from_on_sets_off_and_closes() -> void:
	var s: GuardedSwitch = _make()
	_click(s)
	_click(s)
	_click(s)
	expect_eq(s.get_value(), s.min_value, "off")
	expect(not s.cap_open, "cap closed")
	expect_near((s.get_node("Cap") as Node3D).rotation.x, 0.0, 0.0001)
	s.queue_free()


func test_open_cap_over_off_drops_after_timeout() -> void:
	var s: GuardedSwitch = _make()
	expect_eq(s.drop_timeout, 5.0, "default 5 s")
	_click(s)
	s.step_cap(4.9)
	expect(s.cap_open, "still up before the timeout")
	s.step_cap(0.2)
	expect(not s.cap_open, "dropped")
	expect_eq(s.get_value(), s.min_value, "value untouched")
	s.queue_free()


func test_cap_replicates_to_other_peer() -> void:
	var host: GuardedSwitch = _make()
	var other: GuardedSwitch = _make()
	host._host_set_cap(true)
	other._rpc_cap(true)  # what the wire delivers
	expect(other.cap_open, "client sees it open")
	host._host_set_cap(false)
	other._rpc_cap(false)
	expect(not other.cap_open, "and closed")
	host.queue_free()
	other.queue_free()


func test_hints() -> void:
	var s: GuardedSwitch = _make()
	expect_eq(s.interaction_hint(), "click to lift the cap")
	_click(s)
	expect_eq(s.interaction_hint(), "click to switch")
	s.queue_free()
