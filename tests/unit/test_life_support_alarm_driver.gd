extends TestCase
## LifeSupportAlarmDriver: the station's O2 and CO2 lamps follow the alarm levels; the gauges read the source.

const SCENE: String = "res://assets/models/stations/life_support/life_support.tscn"

var st: Node3D
var src: LifeSupportReadouts
var drv: LifeSupportAlarmDriver


func before_each() -> void:
	st = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(st)
	src = LifeSupportReadouts.new()
	runner.add_child(src)
	drv = LifeSupportAlarmDriver.new()
	drv.station = st
	runner.add_child(drv)


func after_each() -> void:
	drv.free()
	src.free()
	st.free()


func _lamp(n: String) -> IndicatorLamp:
	return st.get_node(n) as IndicatorLamp


## Lit states sampled over one second at 20 ms steps.
func _samples(n: String) -> Array[bool]:
	var out: Array[bool] = []
	for i: int in 50:
		drv.advance(0.02)
		out.append(_lamp(n).is_lit())
	return out


func test_off_at_defaults() -> void:
	drv.advance(0.1)
	expect(not _lamp("Co2AlarmLamp").is_lit(), "CO2 lamp off")
	expect(not _lamp("O2AlarmLamp").is_lit(), "O2 lamp off")


func test_co2_steady_then_flash_then_off() -> void:
	src.co2_ppm = 7000.0
	var s: Array[bool] = _samples("Co2AlarmLamp")
	expect(not s.has(false), "steady at 7000 ppm")
	expect(not _lamp("O2AlarmLamp").is_lit(), "O2 lamp independent")
	src.co2_ppm = 25000.0
	s = _samples("Co2AlarmLamp")
	expect(s.has(true) and s.has(false), "flashes at 25000 ppm")
	var toggles: int = 0
	for i: int in range(1, s.size()):
		if s[i] != s[i - 1]:
			toggles += 1
	expect(toggles >= 3 and toggles <= 5, "about 2 Hz (%d toggles in 1 s)" % toggles)
	src.co2_ppm = 400.0
	drv.advance(0.02)
	expect(not _lamp("Co2AlarmLamp").is_lit(), "off again when normal")


func test_o2_steady_then_flash_and_independent() -> void:
	src.o2_level = 0.2
	var s: Array[bool] = _samples("O2AlarmLamp")
	expect(not s.has(false), "steady at 0.2")
	expect(not _lamp("Co2AlarmLamp").is_lit(), "CO2 lamp independent")
	src.o2_level = 0.05
	s = _samples("O2AlarmLamp")
	expect(s.has(true) and s.has(false), "flashes at 0.05")
	src.o2_level = 1.0
	drv.advance(0.02)
	expect(not _lamp("O2AlarmLamp").is_lit(), "off again when normal")


func test_gauges_read_the_source() -> void:
	src.co2_ppm = 7000.0
	src.o2_level = 0.8
	for n: String in ["O2Gauge", "Co2LevelGauge"]:
		var g: Gauge = st.get_node(n) as Gauge
		expect(g.source_group == LifeSupportReadouts.GROUP, "%s reads the life support source" % n)
		expect(float(src.readout(g.readout)) > 0.0, "%s readout is nonzero" % n)
