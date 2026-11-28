extends TestCase
## DiveGenerator fills a size's budget from work options, deterministically, prerequisites first.

const COSTS_PATH: String = "res://src/dive/presets/work_costs.tres"
const SIZES_PATH: String = "res://src/dive/presets/dive_sizes.tres"


func _table() -> WorkCostTable:
	var t: WorkCostTable = load(COSTS_PATH) as WorkCostTable
	t.sizes = (load(SIZES_PATH) as WorkCostTable).sizes
	return t


func _opt(name: StringName, kind: StringName, main: bool = false, pre: StringName = &"", flag: StringName = &"") -> WorkOption:
	var o: WorkOption = WorkOption.new()
	o.option_name = name
	o.kind = kind
	o.can_be_main = main
	o.prerequisite_kind = pre
	o.state_flag = flag
	return o


## A varied site: plenty of cheap and dear work, one chained main objective.
func _site() -> Array[WorkOption]:
	var out: Array[WorkOption] = []
	out.append(_opt(&"survey", &"multibeam_survey", true))
	out.append(_opt(&"repair", &"sensor_station_repair", true, &"scan"))
	out.append(_opt(&"charges", &"set_charges", true, &"multibeam_survey"))
	for i: int in 10:
		out.append(_opt(StringName("scan%d" % i), &"scan"))
		out.append(_opt(StringName("coil%d" % i), &"data_coil"))
	for i: int in 3:
		out.append(_opt(StringName("survey_b%d" % i), &"multibeam_survey"))
	out.append(_opt(&"power", &"restore_power", false, &"", &"power_off"))
	out.append(_opt(&"flood", &"recover_flooding", false, &"", &"flooding"))
	return out


func _gen(size: StringName, seed_value: int, options: Array[WorkOption], flags: Array[StringName] = []) -> DivePlan:
	return DiveGenerator.new().generate(size, _table(), seed_value, options, flags)


func test_never_exceeds_budget_and_fills_it() -> void:
	for size: StringName in [&"light", &"medium", &"large"]:
		for s: int in 40:
			var plan: DivePlan = _gen(size, s, _site())
			expect(plan.total_cost() <= plan.budget, "%s seed %d within budget" % [size, s])
			expect(plan.total_cost() * 5 >= plan.budget * 4, "%s seed %d reaches 80%% (%d/%d)" % [size, s, plan.total_cost(), plan.budget])
			expect_eq(plan.leftover(), plan.budget - plan.total_cost())


func test_same_seed_same_plan_other_seed_differs() -> void:
	var a: DivePlan = _gen(&"medium", 7, _site())
	var b: DivePlan = _gen(&"medium", 7, _site())
	expect_eq(a.names(), b.names())
	expect_eq(a.costs, b.costs)
	var differs: bool = false
	for s: int in range(8, 30):
		if _gen(&"medium", s, _site()).names() != a.names():
			differs = true
	expect(differs, "some other seed gives a different plan")


func test_prerequisite_precedes_dependant() -> void:
	for s: int in 40:
		var plan: DivePlan = _gen(&"large", s, _site())
		for i: int in plan.items.size():
			var o: WorkOption = plan.items[i]
			if o.prerequisite_kind == &"":
				continue
			var found: bool = false
			for j: int in i:
				if plan.items[j].kind == o.prerequisite_kind:
					found = true
			expect(found, "seed %d: %s has its %s before it" % [s, o.option_name, o.prerequisite_kind])


func test_state_flag() -> void:
	var off: DivePlan = _gen(&"large", 3, _site())
	expect(not off.has_item(&"power"), "power flag off adds nothing")
	expect(not off.has_item(&"flood"))
	var flags: Array[StringName] = [&"power_off"]
	var on: DivePlan = _gen(&"large", 3, _site(), flags)
	var i: int = on.index_of(&"power")
	expect(i >= 0, "power flag on adds the item")
	if i >= 0:
		expect_eq(on.costs[i], _table().cost_for(&"restore_power", 3))
	expect(not on.has_item(&"flood"), "other flag stays off")
	var count: int = 0
	for o: WorkOption in on.items:
		if o.option_name == &"power":
			count += 1
	expect_eq(count, 1)


func test_main_objective_of_one_to_three_steps() -> void:
	for size: StringName in [&"light", &"medium", &"large"]:
		for s: int in 40:
			var plan: DivePlan = _gen(size, s, _site())
			expect(plan.main_steps >= 1 and plan.main_steps <= 3, "%s seed %d main steps %d" % [size, s, plan.main_steps])
			expect(plan.items[plan.main_steps - 1].can_be_main, "last main step is the objective")


func test_short_plan_without_error() -> void:
	var few: Array[WorkOption] = [_opt(&"only", &"scan", true)]
	var plan: DivePlan = _gen(&"large", 1, few)
	expect_eq(plan.items.size(), 1)
	expect(plan.leftover() > 0)
	var none: Array[WorkOption] = []
	var empty: DivePlan = _gen(&"light", 1, none)
	expect_eq(empty.items.size(), 0)
	expect_eq(empty.main_steps, 0)
	expect_eq(_gen(&"huge", 1, few).items.size(), 0)
