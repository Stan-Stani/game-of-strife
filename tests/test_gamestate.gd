extends Node

# Comprehensive GameState unit tests
# Tests pattern storage, persistence, and data integrity

class_name TestGameState

var test_framework: TestFramework

func _ready():
	test_framework = TestFramework.new()
	add_child(test_framework)
	
	run_all_gamestate_tests()
	
	test_framework.print_summary()
	
	# Exit if running headless
	var args = OS.get_cmdline_args()
	if "--headless" in args:
		get_tree().quit()

func run_all_gamestate_tests():
	print("Running GameState Tests")
	print("======================")
	
	test_pattern_storage()
	test_pattern_persistence()
	test_data_integrity()
	test_pattern_operations()
	test_empty_patterns()
	test_large_patterns()

func test_pattern_storage():
	test_framework.start_test("Pattern Storage - Basic")
	
	# Test storing a simple pattern
	var test_pattern = {
		Vector2(0, 0): true,
		Vector2(1, 0): true,
		Vector2(0, 1): true
	}
	
	GameState.colony = test_pattern
	
	test_framework.assert_equal(test_pattern, GameState.colony, "Pattern should be stored correctly")
	test_framework.assert_equal(3, GameState.colony.size(), "Pattern should have correct size")
	test_framework.end_test()
	
	test_framework.start_test("Pattern Storage - Overwrite")
	
	# Test overwriting existing pattern
	var new_pattern = {
		Vector2(5, 5): true,
		Vector2(6, 6): true
	}
	
	GameState.colony = new_pattern
	
	test_framework.assert_equal(new_pattern, GameState.colony, "New pattern should overwrite old pattern")
	test_framework.assert_equal(2, GameState.colony.size(), "New pattern should have correct size")
	test_framework.end_test()

func test_pattern_persistence():
	test_framework.start_test("Pattern Persistence - Non-null")
	
	# Test that GameState.colony exists and is accessible
	test_framework.assert_not_null(GameState, "GameState should exist")
	
	# Set a pattern and verify it persists
	var persistence_pattern = {
		Vector2(10, 10): true,
		Vector2(11, 11): true,
		Vector2(12, 12): true
	}
	
	GameState.colony = persistence_pattern
	
	# Access it again to verify persistence
	var retrieved_pattern = GameState.colony
	test_framework.assert_equal(persistence_pattern, retrieved_pattern, "Pattern should persist in GameState")
	test_framework.end_test()
	
	test_framework.start_test("Pattern Persistence - Reference")
	
	# Test that GameState.colony maintains reference integrity
	var original_pattern = GameState.colony
	original_pattern[Vector2(20, 20)] = true
	
	test_framework.assert_has_key(GameState.colony, Vector2(20, 20), "Pattern modifications should persist")
	test_framework.end_test()

func test_data_integrity():
	test_framework.start_test("Data Integrity - Vector2 Keys")
	
	# Test that Vector2 keys work correctly
	var vector_pattern = {}
	var test_vectors = [
		Vector2(0, 0), Vector2(-5, 10), Vector2(100, -50), Vector2(999, 999)
	]
	
	for vec in test_vectors:
		vector_pattern[vec] = true
	
	GameState.colony = vector_pattern
	
	for vec in test_vectors:
		test_framework.assert_has_key(GameState.colony, vec, "Vector2 key " + str(vec) + " should be preserved")
		test_framework.assert_true(GameState.colony[vec], "Vector2 key " + str(vec) + " should have correct value")
	
	test_framework.end_test()
	
	test_framework.start_test("Data Integrity - Boolean Values")
	
	# Test that boolean values are preserved correctly
	var bool_pattern = {
		Vector2(0, 0): true,
		Vector2(1, 0): false,
		Vector2(0, 1): true,
		Vector2(1, 1): false
	}
	
	GameState.colony = bool_pattern
	
	test_framework.assert_true(GameState.colony[Vector2(0, 0)], "True values should be preserved")
	test_framework.assert_false(GameState.colony[Vector2(1, 0)], "False values should be preserved")
	test_framework.assert_true(GameState.colony[Vector2(0, 1)], "True values should be preserved")
	test_framework.assert_false(GameState.colony[Vector2(1, 1)], "False values should be preserved")
	
	test_framework.end_test()

func test_pattern_operations():
	test_framework.start_test("Pattern Operations - Add Cells")
	
	# Test adding cells to existing pattern
	var base_pattern = {Vector2(0, 0): true}
	GameState.colony = base_pattern
	
	# Add more cells
	GameState.colony[Vector2(1, 1)] = true
	GameState.colony[Vector2(2, 2)] = true
	
	test_framework.assert_equal(3, GameState.colony.size(), "Should be able to add cells to pattern")
	test_framework.assert_has_key(GameState.colony, Vector2(1, 1), "New cell should be added")
	test_framework.assert_has_key(GameState.colony, Vector2(2, 2), "New cell should be added")
	test_framework.end_test()
	
	test_framework.start_test("Pattern Operations - Remove Cells")
	
	# Test removing cells from pattern
	var initial_size = GameState.colony.size()
	GameState.colony.erase(Vector2(1, 1))
	
	test_framework.assert_equal(initial_size - 1, GameState.colony.size(), "Should be able to remove cells from pattern")
	test_framework.assert_false(GameState.colony.has(Vector2(1, 1)), "Removed cell should not exist")
	test_framework.end_test()
	
	test_framework.start_test("Pattern Operations - Clear Pattern")
	
	# Test clearing entire pattern
	GameState.colony.clear()
	
	test_framework.assert_equal(0, GameState.colony.size(), "Should be able to clear entire pattern")
	test_framework.assert_empty(GameState.colony, "Cleared pattern should be empty")
	test_framework.end_test()

func test_empty_patterns():
	test_framework.start_test("Empty Patterns - Null Assignment")
	
	# Test assigning null
	GameState.colony = null
	test_framework.assert_null(GameState.colony, "Should be able to assign null to colony")
	test_framework.end_test()
	
	test_framework.start_test("Empty Patterns - Empty Dictionary")
	
	# Test assigning empty dictionary
	GameState.colony = {}
	test_framework.assert_not_null(GameState.colony, "Empty dictionary should not be null")
	test_framework.assert_empty(GameState.colony, "Empty dictionary should be empty")
	test_framework.end_test()

func test_large_patterns():
	test_framework.start_test("Large Patterns - Performance")
	
	# Test with larger patterns to ensure performance is acceptable
	var large_pattern = {}
	var pattern_size = 100
	
	# Create a large pattern
	for x in range(pattern_size):
		for y in range(pattern_size):
			if (x + y) % 2 == 0:  # Checkerboard pattern
				large_pattern[Vector2(x, y)] = true
	
	# Measure time to store and retrieve
	var start_time = Time.get_ticks_msec()
	GameState.colony = large_pattern
	var retrieved_pattern = GameState.colony
	var end_time = Time.get_ticks_msec()
	
	test_framework.assert_equal(large_pattern.size(), retrieved_pattern.size(), "Large pattern should be stored correctly")
	test_framework.assert_true(end_time - start_time < 1000, "Large pattern operations should be fast (< 1 second)")
	test_framework.end_test()
	
	test_framework.start_test("Large Patterns - Memory Integrity")
	
	# Test that large patterns don't corrupt data
	var test_key = Vector2(50, 50)
	test_framework.assert_has_key(GameState.colony, test_key, "Large pattern should maintain data integrity")
	test_framework.assert_true(GameState.colony[test_key], "Large pattern cell values should be correct")
	test_framework.end_test()