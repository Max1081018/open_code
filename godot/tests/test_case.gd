class_name TestCase
extends RefCounted
## Base for test suites. Every method named test_* is run by run_tests.gd.

var failures: Array[String] = []
var current := ""


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("%s: %s" % [current, message])


func check_eq(actual, expected, message: String) -> void:
	if actual != expected:
		failures.append("%s: %s (expected %s, got %s)" % [current, message, expected, actual])


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s: %s (expected %s ± %s, got %s)" % [current, message, expected,
			tolerance, actual])
