class_name AssetCostModel
extends RefCounted
## View model for what an asset has cost (the manifest's append-only `costs` ledger) and for
## the estimate shown beside each paid action (the backend's `--estimate`). Pure data: the
## panel only formats what this returns.

## Paid actions that show an estimate before running.
const ACTIONS: PackedStringArray = ["more", "refine", "turnaround", "view", "send", "bakeoff"]

var slug: String = ""
var total_usd: float = 0.0
## True when any counted entry is an estimate, so the total is shown with a "~".
var estimated: bool = false
var unknown_count: int = 0
var budget_usd: float = -1.0
## Rows of {name, usd, count, estimated, unknown}, sorted by name.
var by_stage: Array[Dictionary] = []
var by_provider: Array[Dictionary] = []
## Action key -> estimate text, filled from `--estimate` results.
var estimates: Dictionary = {}


## `asset` is one manifest from `list`; `list` also adds the effective `budget_usd`.
func load_asset(asset: Dictionary) -> void:
	slug = str(asset.get("slug", ""))
	var costs: Array = asset.get("costs", [])
	total_usd = total_of(costs)
	estimated = false
	unknown_count = 0
	for c: Variant in costs:
		var d: Dictionary = c
		if str(d.get("basis", "")) == "estimated":
			estimated = true
		elif str(d.get("basis", "")) == "unknown":
			unknown_count += 1
	var budget: Variant = asset.get("budget_usd")
	budget_usd = float(budget) if budget != null else -1.0
	by_stage = _group(costs, "stage")
	by_provider = _group(costs, "provider")
	estimates.clear()


## Spend in a ledger: every entry with a USD figure except subscription ones.
static func total_of(costs: Array) -> float:
	var t: float = 0.0
	for c: Variant in costs:
		var d: Dictionary = c
		if d.get("usd") != null and str(d.get("basis", "")) != "subscription":
			t += float(d["usd"])
	return snappedf(t, 0.000001)


static func has_estimated(costs: Array) -> bool:
	for c: Variant in costs:
		if str((c as Dictionary).get("basis", "")) == "estimated":
			return true
	return false


func over_budget() -> bool:
	return budget_usd >= 0.0 and total_usd > budget_usd


func warning() -> String:
	if not over_budget():
		return ""
	return "%s has spent %s, over its %s budget" % [slug, money(total_usd), money(budget_usd)]


func total_text() -> String:
	return money(total_usd, estimated)


## "$1.23", or "~$1.23" when `approx`. Under a cent, three decimals so cheap calls don't read $0.00.
static func money(usd: float, approx: bool = false) -> String:
	var s: String = "$%.2f" % usd if usd >= 0.01 or usd == 0.0 else "$%.3f" % usd
	return "~" + s if approx else s


func _group(costs: Array, key: String) -> Array[Dictionary]:
	var buckets: Dictionary = {}
	for c: Variant in costs:
		var d: Dictionary = c
		if str(d.get("basis", "")) == "subscription":
			continue
		var name: String = str(d.get(key, ""))
		if not buckets.has(name):
			buckets[name] = {"name": name, "usd": 0.0, "count": 0, "estimated": false, "unknown": 0}
		var b: Dictionary = buckets[name]
		b["count"] = int(b["count"]) + 1
		if str(d.get("basis", "")) == "unknown":
			b["unknown"] = int(b["unknown"]) + 1
		elif d.get("usd") != null:
			b["usd"] = float(b["usd"]) + float(d["usd"])
		if str(d.get("basis", "")) == "estimated":
			b["estimated"] = true
	var out: Array[Dictionary] = []
	for n: Variant in buckets:
		out.append(buckets[n])
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["name"]) < str(y["name"]))
	return out


## The cost panel's lines: one per stage then one per provider, estimated figures "~".
func panel_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if by_stage.is_empty():
		lines.append("No paid calls recorded yet.")
		return lines
	lines.append("Total %s" % total_text())
	lines.append("By stage")
	for r: Dictionary in by_stage:
		lines.append("  " + _line(r))
	lines.append("By provider")
	for r: Dictionary in by_provider:
		lines.append("  " + _line(r))
	if unknown_count > 0:
		lines.append("%d call(s) could not be priced (not counted)" % unknown_count)
	return lines


static func _line(r: Dictionary) -> String:
	var s: String = "%s  %s  (%d call%s)" % [r["name"], money(float(r["usd"]), bool(r["estimated"])), int(r["count"]), "" if int(r["count"]) == 1 else "s"]
	if int(r["unknown"]) > 0:
		s += "  + %d unknown" % int(r["unknown"])
	return s


# --- estimates -------------------------------------------------------------------------------

## The same command asking the backend for its estimate instead of running. Empty stays empty.
static func estimate_args(args: PackedStringArray) -> PackedStringArray:
	if args.is_empty():
		return PackedStringArray()
	var a: PackedStringArray = args.duplicate()
	a.append("--estimate")
	return a


## Short text for an `--estimate` result's `data`. Unknown prices are never shown as zero.
static func estimate_text(data: Dictionary) -> String:
	var est: Variant = data.get("estimate")
	if not est is Dictionary:
		return ""
	var e: Dictionary = est
	var calls: Array = e.get("calls", [])
	var unknown: Array = e.get("unknown", [])
	var usd: float = float(e.get("usd", 0.0))
	var free: bool = not calls.is_empty()
	for c: Variant in calls:
		var b: String = str((c as Dictionary).get("basis", ""))
		if b != "mock" and b != "subscription":
			free = false
	if free:
		return "free"
	if not unknown.is_empty():
		return "cost unknown" if usd <= 0.0 else "%s + unknown" % money(usd, true)
	return money(usd, true)


func set_estimate(action: String, data: Dictionary) -> void:
	estimates[action] = estimate_text(data)


## A button label with its estimate appended once known.
func label(action: String, base: String) -> String:
	var t: String = str(estimates.get(action, ""))
	return base if t == "" else "%s (%s)" % [base, t]
