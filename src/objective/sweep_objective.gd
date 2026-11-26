class_name SweepObjective
extends Node
## Host-side bathymetry sweep. A marked area (a box on the horizontal plane) is split into a grid of cells. While the
## sounder is armed, every cell the sub passes over (within [constant SWATH_M]) fills in. The sweep is complete when the
## covered fraction reaches [member target_fraction]. The sounder pings: each ping is loud and gives the sub's position
## away, as active sonar does, so the noise system (and the creatures listening to it) hears it.

signal sweep_started
signal ping(world_position: Vector3)
signal sweep_completed

## Grid cells along each side of the area.
const GRID: int = 8
## Cells within this horizontal distance of the sub are sounded.
const SWATH_M: float = 12.0
## Loud ping (~90 dB), louder than the scanner.
const PING_INTENSITY: float = 0.1
const PING_INTERVAL_SEC: float = 4.0
const PING_LENGTH_SEC: float = 1.0

@export var controller: SubController
## A SWEEP science module that arms the sounder (set by the module).
var module: ScienceModule
## Centre of the marked area (world x and z are used).
@export var area_center: Vector3 = Vector3.ZERO
## Size of the marked area on x and z, metres.
@export var area_size: Vector2 = Vector2(120.0, 120.0)
## Fraction of cells to cover to finish.
@export_range(0.05, 1.0) var target_fraction: float = 0.8

## Per cell: 1 once sounded. Replicated state for the module's screen.
var covered: PackedByteArray = PackedByteArray()
var complete: bool = false

var _ping_clock: float = 0.0
var _ping_left: float = 0.0
var _was_on: bool = false


func _init() -> void:
	covered.resize(GRID * GRID)


func _ready() -> void:
	add_to_group(&"noise_sources")
	add_to_group(&"sweep_objectives")


func sounder_on() -> bool:
	return not complete and module != null and module.armed


## True while a ping is sounding: the sub is audible and located.
func revealing() -> bool:
	return _ping_left > 0.0


func noise_intensity() -> float:
	return PING_INTENSITY if revealing() else 0.0


func noise_breakdown() -> Dictionary:
	return {"sounder ping": noise_intensity()}


func inside_area(p: Vector3) -> bool:
	var half: Vector2 = area_size * 0.5
	return absf(p.x - area_center.x) <= half.x and absf(p.z - area_center.z) <= half.y


func cell_center(ix: int, iz: int) -> Vector3:
	var step: Vector2 = area_size / float(GRID)
	return Vector3(area_center.x - area_size.x * 0.5 + (ix + 0.5) * step.x, area_center.y, area_center.z - area_size.y * 0.5 + (iz + 0.5) * step.y)


func is_covered(ix: int, iz: int) -> bool:
	return covered[iz * GRID + ix] != 0


## Fraction of cells sounded, 0..1.
func coverage() -> float:
	var n: int = 0
	for c: int in covered:
		n += c
	return float(n) / float(GRID * GRID)


## Progress toward the target, 0..1.
func progress() -> float:
	return minf(coverage() / target_fraction, 1.0)


func readout(property: StringName) -> float:
	return progress() if property == &"progress" else 0.0


func reset() -> void:
	covered.fill(0)
	complete = false
	_was_on = false
	_ping_clock = 0.0
	_ping_left = 0.0
	if module != null:
		module.armed = false


## Marks the cells within the swath of [param p]; only while the sub is over the area.
func sound_at(p: Vector3) -> void:
	if not inside_area(p):
		return
	for iz: int in GRID:
		for ix: int in GRID:
			var c: Vector3 = cell_center(ix, iz)
			if Vector2(c.x - p.x, c.z - p.z).length() <= SWATH_M:
				covered[iz * GRID + ix] = 1


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or complete:
		return
	var on: bool = sounder_on()
	if on and not _was_on:
		_ping_clock = 0.0
		sweep_started.emit()
	_was_on = on
	if _ping_left > 0.0:
		_ping_left = maxf(_ping_left - delta, 0.0)
	if not on or controller == null:
		return
	_ping_clock -= delta
	if _ping_clock <= 0.0:
		_ping_clock = PING_INTERVAL_SEC
		_ping_left = PING_LENGTH_SEC
		ping.emit(controller.model.position)
	sound_at(controller.model.position)
	if coverage() >= target_fraction:
		complete = true
		module.armed = false
		sweep_completed.emit()
		var log: Node = get_tree().get_first_node_in_group(&"session_log")
		if log != null:
			log.call(&"write", "SEABED SWEPT  %.0f%% covered" % (coverage() * 100.0))
