class_name TestFramework
extends Node

# Simple unit test framework for Godot
var test_results = []
var current_test = ""
var test_count = 0
var passed_count = 0
var failed_count = 0

signal test_completed(test_name: String, passed: bool, message: String)
signal all_tests_completed(total: int, passed: int, failed: int)

func start_test(test_name: String):
	current_test = test_name
	test_count += 1
	print("=== Starting Test: " + test_name + " ===")

func assert_true(condition: bool, message: String = ""):
	var full_message = current_test + ": " + message
	if condition:
		print("PASS: " + full_message)
		test_results.append({"test": current_test, "passed": true, "message": full_message})
		test_completed.emit(current_test, true, full_message)
	else:
		print("FAIL: " + full_message)
		test_results.append({"test": current_test, "passed": false, "message": full_message})
		test_completed.emit(current_test, false, full_message)

func assert_false(condition: bool, message: String = ""):
	assert_true(!condition, message)

func assert_equal(expected, actual, message: String = ""):
	var full_message = message + " (Expected: " + str(expected) + ", Actual: " + str(actual) + ")"
	assert_true(expected == actual, full_message)

func assert_not_null(value, message: String = ""):
	assert_true(value != null, message + " should not be null")

func assert_null(value, message: String = ""):
	assert_true(value == null, message + " should be null")

func end_test():
	var test_result = test_results[test_results.size() - 1]
	if test_result.passed:
		passed_count += 1
		print("=== Test " + current_test + " PASSED ===\n")
	else:
		failed_count += 1
		print("=== Test " + current_test + " FAILED ===\n")

func finish_all_tests():
	print("=== TEST SUMMARY ===")
	print("Total Tests: " + str(test_count))
	print("Passed: " + str(passed_count))
	print("Failed: " + str(failed_count))
	print("Success Rate: " + str(float(passed_count) / float(test_count) * 100.0) + "%")
	
	all_tests_completed.emit(test_count, passed_count, failed_count)
	
	if failed_count == 0:
		print("ALL TESTS PASSED!")
		return true
	else:
		print("SOME TESTS FAILED!")
		return false

func get_test_results() -> Array:
	return test_results