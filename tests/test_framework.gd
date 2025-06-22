extends Node

# Simple testing framework for Game of Strife
# Provides assertion methods and test result tracking

class_name TestFramework

var test_results = []
var current_test_name = ""
var passed_tests = 0
var failed_tests = 0

func start_test(test_name: String):
	current_test_name = test_name
	print("Starting test: ", test_name)

func end_test():
	print("Completed test: ", current_test_name)
	current_test_name = ""

func assert_true(condition: bool, message: String = ""):
	if condition:
		_test_passed(message)
	else:
		_test_failed("Expected true but got false. " + message)

func assert_false(condition: bool, message: String = ""):
	if not condition:
		_test_passed(message)
	else:
		_test_failed("Expected false but got true. " + message)

func assert_equal(expected, actual, message: String = ""):
	if expected == actual:
		_test_passed(message)
	else:
		_test_failed("Expected %s but got %s. %s" % [str(expected), str(actual), message])

func assert_not_equal(expected, actual, message: String = ""):
	if expected != actual:
		_test_passed(message)
	else:
		_test_failed("Expected values to be different but both were %s. %s" % [str(expected), message])

func assert_null(value, message: String = ""):
	if value == null:
		_test_passed(message)
	else:
		_test_failed("Expected null but got %s. %s" % [str(value), message])

func assert_not_null(value, message: String = ""):
	if value != null:
		_test_passed(message)
	else:
		_test_failed("Expected non-null value but got null. " + message)

func assert_has_key(dictionary: Dictionary, key, message: String = ""):
	if dictionary.has(key):
		_test_passed(message)
	else:
		_test_failed("Dictionary does not contain key %s. %s" % [str(key), message])

func assert_empty(collection, message: String = ""):
	var is_empty = false
	if collection is Array:
		is_empty = collection.size() == 0
	elif collection is Dictionary:
		is_empty = collection.size() == 0
	elif collection is String:
		is_empty = collection.length() == 0
	
	if is_empty:
		_test_passed(message)
	else:
		_test_failed("Expected empty collection but got size %d. %s" % [collection.size(), message])

func assert_not_empty(collection, message: String = ""):
	var is_empty = false
	if collection is Array:
		is_empty = collection.size() == 0
	elif collection is Dictionary:
		is_empty = collection.size() == 0
	elif collection is String:
		is_empty = collection.length() == 0
	
	if not is_empty:
		_test_passed(message)
	else:
		_test_failed("Expected non-empty collection but got empty collection. " + message)

func _test_passed(message: String):
	passed_tests += 1
	var result = {
		"test": current_test_name,
		"status": "PASSED",
		"message": message,
		"timestamp": Time.get_unix_time_from_system()
	}
	test_results.append(result)
	if message != "":
		print("  ✓ PASS: ", message)
	else:
		print("  ✓ PASS")

func _test_failed(message: String):
	failed_tests += 1
	var result = {
		"test": current_test_name,
		"status": "FAILED",
		"message": message,
		"timestamp": Time.get_unix_time_from_system()
	}
	test_results.append(result)
	print("  ✗ FAIL: ", message)

func print_summary():
	print("\n" + "=".repeat(50))
	print("TEST SUMMARY")
	print("=".repeat(50))
	print("Total tests: ", passed_tests + failed_tests)
	print("Passed: ", passed_tests)
	print("Failed: ", failed_tests)
	print("Success rate: %.1f%%" % (float(passed_tests) / float(passed_tests + failed_tests) * 100.0))
	print("=".repeat(50))
	
	if failed_tests > 0:
		print("\nFAILED TESTS:")
		for result in test_results:
			if result["status"] == "FAILED":
				print("  - %s: %s" % [result["test"], result["message"]])

func get_test_results() -> Array:
	return test_results

func reset():
	test_results.clear()
	current_test_name = ""
	passed_tests = 0
	failed_tests = 0