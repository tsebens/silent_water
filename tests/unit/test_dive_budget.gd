extends TestCase
## Work costs and dive sizes load from their presets with the design doc's numbers.

const COSTS_PATH: String = "res://src/dive/presets/work_costs.tres"
const SIZES_PATH: String = "res://src/dive/presets/dive_sizes.tres"

## Design doc "Dive size and the point budget": kind, min, max.
const ROWS: Array = [
	[&"scan", 10, 10],
	[&"multibeam_survey", 20, 20],
	[&"sensor_station_repair", 30, 35],
	[&"restore_power", 15, 15],
	[&"recover_flooding", 20, 25],
	[&"data_coil", 10, 15],
	[&"set_charges", 30, 30],
	[&"rescue_crew", 40, 40],
]


func _costs() -> WorkCostTable:
	return load(COSTS_PATH) as WorkCostTable


func test_every_cost_row_loads() -> void:
	var table: WorkCostTable = _costs()
	expect(table != null, "work_costs.tres loads as a WorkCostTable")
	if table == null:
		return
	expect_eq(table.costs.size(), ROWS.size())
	for row: Array in ROWS:
		var kind: StringName = row[0]
		expect(table.has_kind(kind), "has %s" % kind)
		var entry: WorkCost = table.cost_entry(kind)
		if entry == null:
			continue
		expect_eq(entry.points_min, row[1], "min of %s" % kind)
		expect_eq(entry.points_max, row[2], "max of %s" % kind)


func test_fixed_cost_ignores_seed() -> void:
	var table: WorkCostTable = _costs()
	for s: int in 5:
		expect_eq(table.cost_for(&"scan", s), 10)
		expect_eq(table.cost_for(&"rescue_crew", s), 40)


func test_ranged_cost_stays_in_range_and_is_deterministic() -> void:
	var table: WorkCostTable = _costs()
	for row: Array in ROWS:
		for s: int in 50:
			var a: int = table.cost_for(row[0], s)
			expect(a >= row[1] and a <= row[2], "%s seed %d gave %d" % [row[0], s, a])
			expect_eq(table.cost_for(row[0], s), a, "repeat of %s seed %d" % [row[0], s])
	var seen: Dictionary = {}
	for s: int in 200:
		seen[table.cost_for(&"sensor_station_repair", s)] = true
	expect_eq(seen.size(), 6, "all of 30..35 appear across seeds")


func test_sizes_load() -> void:
	var table: WorkCostTable = load(SIZES_PATH) as WorkCostTable
	expect(table != null, "dive_sizes.tres loads")
	if table == null:
		return
	expect_eq(table.budget_for(&"light"), 50)
	expect_eq(table.budget_for(&"medium"), 100)
	expect_eq(table.budget_for(&"large"), 200)


func test_unknown_is_reported() -> void:
	var table: WorkCostTable = _costs()
	expect(not table.has_kind(&"nope"))
	expect_eq(table.cost_for(&"nope", 1), WorkCostTable.UNKNOWN)
	var sizes: WorkCostTable = load(SIZES_PATH) as WorkCostTable
	expect(not sizes.has_size(&"huge"))
	expect_eq(sizes.budget_for(&"huge"), WorkCostTable.UNKNOWN)
