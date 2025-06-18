class_name TestRunner
extends Node

var total_tests = 0
var passed_tests = 0
var failed_tests = 0

func _ready():
	print("=== MULTIPLAYER FUNCTIONALITY TEST SUITE ===")
	print("Starting all tests...")
	
	await run_all_test_suites()
	
	print_final_results()

func run_all_test_suites():
	# Run multiplayer core tests
	print("\n--- Running Multiplayer Core Tests ---")
	await run_test_suite("res://tests/test_multiplayer.gd")
	
	# Run command system tests  
	print("\n--- Running Command System Tests ---")
	await run_test_suite("res://tests/test_command_system.gd")

func run_test_suite(test_script_path: String):
	var test_scene = Node.new()
	var test_script = load(test_script_path)
	test_scene.set_script(test_script)
	
	add_child(test_scene)
	
	# Connect to test completion signals if they exist
	if test_scene.has_signal("all_tests_completed"):
		test_scene.all_tests_completed.connect(_on_test_suite_completed)
	
	# Wait for test to complete
	if test_scene.has_method("run_all_tests"):
		await test_scene.run_all_tests()
	else:
		await get_tree().process_frame
	
	# Clean up
	test_scene.queue_free()

func _on_test_suite_completed(total: int, passed: int, failed: int):
	total_tests += total
	passed_tests += passed  
	failed_tests += failed

func print_final_results():
	print("\n=== FINAL TEST RESULTS ===")
	print("Total Test Suites: 2")
	print("Total Tests: " + str(total_tests))
	print("Passed: " + str(passed_tests))
	print("Failed: " + str(failed_tests))
	
	if failed_tests == 0:
		print("🎉 ALL TESTS PASSED! 🎉")
		get_tree().quit(0)
	else:
		print("❌ SOME TESTS FAILED ❌")
		print("Success Rate: " + str(float(passed_tests) / float(total_tests) * 100.0) + "%")
		get_tree().quit(1)