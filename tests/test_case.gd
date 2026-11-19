class_name TestCase
extends RefCounted
## Base class for headless unit tests. Methods named `test_*` are run in order.
## `before_each` / `after_each` run around every test if defined.

## The test runner node, for tests that need the scene tree.
var runner: Node

var _failures: PackedStringArray = PackedStringArray()
var _current: String = ""


func expect(condition: bool, message: String = "expectation failed") -> void:
	if not condition:
		_failures.append("%s: %s" % [_current, message])


func expect_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		_failures.append(
			"%s: expected %s, got %s %s" % [_current, str(expected), str(actual), message]
		)


func expect_near(actual: float, expected: float, tolerance: float = 0.0001, message: String = "") -> void:
	if absf(actual - expected) > tolerance:
		_failures.append(
			"%s: expected %f ± %f, got %f %s" % [_current, expected, tolerance, actual, message]
		)


func before_each() -> void:
	pass


func after_each() -> void:
	pass
