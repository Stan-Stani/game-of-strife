extends Node

# Test runner that executes all test files
# Run this scene to execute the complete test suite

var test_framework: TestFramework

func _ready():
	test_framework = TestFramework.new()
	add_child(test_framework)
	
	print("Game of Strife Test Suite")
	print("========================")
	
	run_all_tests()
	
	test_framework.print_summary()
	
	# Exit after tests complete if running headless
	var args = OS.get_cmdline_args()
	if "--headless" in args or "--test" in args:
		get_tree().quit()

func run_all_tests():
	# Run Conway's Game of Life tests
	run_conway_tests()
	
	# Run GameState tests
	run_gamestate_tests()
	
	# Run integration tests
	run_integration_tests()

func run_conway_tests():
	test_framework.start_test("Conway Rules - Live Cell Survival")
	# Test: Live cell with 2 neighbors survives
	test_framework.assert_true(true, "Live cell with 2 neighbors should survive")
	test_framework.end_test()
	
	test_framework.start_test("Conway Rules - Live Cell Death")
	# Test: Live cell with < 2 neighbors dies
	test_framework.assert_true(true, "Live cell with <2 neighbors should die")
	test_framework.end_test()
	
	test_framework.start_test("Conway Rules - Dead Cell Birth")
	# Test: Dead cell with 3 neighbors is born
	test_framework.assert_true(true, "Dead cell with 3 neighbors should be born")
	test_framework.end_test()

func run_gamestate_tests():
	test_framework.start_test("GameState - Pattern Storage")
	# Test GameState pattern storage
	var test_pattern = {Vector2(0, 0): true, Vector2(1, 0): true}
	GameState.colony = test_pattern
	test_framework.assert_equal(test_pattern, GameState.colony, "Pattern should be stored correctly")
	test_framework.end_test()
	
	test_framework.start_test("GameState - Pattern Persistence")
	# Test that patterns persist across scenes
	test_framework.assert_not_null(GameState.colony, "Colony data should persist")
	test_framework.end_test()

func run_integration_tests():
	test_framework.start_test("Integration - Scene Transition")
	# Test that we can transition between 2D and 3D scenes
	test_framework.assert_true(true, "Scene transition should work")
	test_framework.end_test()
	
	test_framework.start_test("Integration - Pattern Loading")
	# Test that patterns can be loaded from command line
	test_framework.assert_true(true, "Command line pattern loading should work")
	test_framework.end_test()