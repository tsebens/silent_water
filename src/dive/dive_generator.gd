class_name DiveGenerator
extends RefCounted
## Builds a [DivePlan] that fills a dive size's budget from a site's [WorkOption]s. Costs are read only through the
## [WorkCostTable]. A main objective (1 to 3 steps) is chosen first, then facility problems whose flag is set, then
## side work until nothing else fits. The same inputs and seed give the same plan.

const MAX_MAIN_STEPS: int = 3

var _table: WorkCostTable
var _rng: RandomNumberGenerator
var _seed: int = 0
var _options: Array[WorkOption] = []
var _flags: Array[StringName] = []
var _plan: DivePlan
var _remaining: int = 0


## [param flags] are the facility state flags set for this dive. An unknown size returns an empty plan.
func generate(size_name: StringName, table: WorkCostTable, seed_value: int, options: Array[WorkOption], flags: Array[StringName] = []) -> DivePlan:
	_table = table
	_seed = seed_value
	_options = options
	_flags = flags
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	_plan = DivePlan.new()
	_plan.size_name = size_name
	_plan.seed_value = seed_value
	var budget: int = table.budget_for(size_name)
	if budget == WorkCostTable.UNKNOWN:
		return _plan
	_plan.budget = budget
	_remaining = budget

	_choose_main()
	_plan.main_steps = _plan.items.size()
	# Facility problems that are on for this dive.
	for o: WorkOption in _shuffled(_eligible()):
		if o.state_flag != &"" and not _plan.has_item(o.option_name):
			_try_add(o)
	# Side work: keep adding something that fits until nothing does.
	while true:
		var fits: Array[WorkOption] = []
		for o: WorkOption in _eligible():
			if not _plan.has_item(o.option_name) and _chain_for(o).size() > 0:
				fits.append(o)
		if fits.is_empty():
			break
		_try_add(fits[_rng.randi_range(0, fits.size() - 1)])
	return _plan


func _eligible() -> Array[WorkOption]:
	var out: Array[WorkOption] = []
	for o: WorkOption in _options:
		if o == null or not _table.has_kind(o.kind):
			continue
		if o.state_flag != &"" and not _flags.has(o.state_flag):
			continue
		out.append(o)
	return out


func _choose_main() -> void:
	var candidates: Array[WorkOption] = []
	for o: WorkOption in _eligible():
		if not o.can_be_main or o.state_flag != &"":
			continue
		var chain: Array[WorkOption] = _chain_for(o)
		if not chain.is_empty() and chain.size() <= MAX_MAIN_STEPS:
			candidates.append(o)
	if candidates.is_empty():
		return
	_try_add(candidates[_rng.randi_range(0, candidates.size() - 1)])


## Options to add so [param o] can be done: missing prerequisites first, then [param o]. Empty if it does not fit
## the remaining budget or a prerequisite cannot be found.
func _chain_for(o: WorkOption) -> Array[WorkOption]:
	var chain: Array[WorkOption] = []
	var cost: int = 0
	var cur: WorkOption = o
	var guard: int = 0
	while cur != null and guard < 8:
		guard += 1
		if _plan.has_item(cur.option_name):
			break
		chain.push_front(cur)
		cost += _cost(cur)
		if cur.prerequisite_kind == &"":
			cur = null
		else:
			cur = _prerequisite(cur)
			if cur == null:
				return []
	if cur != null:  # loop ended on a cycle or an item already planned
		if not _plan.has_item(cur.option_name):
			return []
	if cost > _remaining:
		return []
	return chain


## The option of the required kind: one already planned, else the first of that kind in a seeded order.
func _prerequisite(o: WorkOption) -> WorkOption:
	var matches: Array[WorkOption] = []
	for p: WorkOption in _eligible():
		if p.kind == o.prerequisite_kind and p != o:
			if _plan.has_item(p.option_name):
				return p
			matches.append(p)
	if matches.is_empty():
		return null
	var r: RandomNumberGenerator = RandomNumberGenerator.new()
	r.seed = hash([_seed, String(o.option_name)])
	return matches[r.randi_range(0, matches.size() - 1)]


func _try_add(o: WorkOption) -> bool:
	var chain: Array[WorkOption] = _chain_for(o)
	if chain.is_empty():
		return false
	for c: WorkOption in chain:
		var cost: int = _cost(c)
		_plan.items.append(c)
		_plan.costs.append(cost)
		_remaining -= cost
	return true


func _cost(o: WorkOption) -> int:
	return _table.cost_for(o.kind, _seed)


func _shuffled(list: Array[WorkOption]) -> Array[WorkOption]:
	var out: Array[WorkOption] = list.duplicate()
	for i: int in range(out.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var t: WorkOption = out[i]
		out[i] = out[j]
		out[j] = t
	return out
