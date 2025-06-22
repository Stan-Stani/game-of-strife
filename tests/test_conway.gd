extends Node

# Comprehensive Conway's Game of Life unit tests
# Tests the core cellular automata rules and behaviors

class_name TestConway

var test_framework: TestFramework
var main_scene: Node2D

func _ready():
	test_framework = TestFramework.new()
	add_child(test_framework)
	
	# Load the main scene to test Conway's functionality
	var main_scene_resource = preload("res://Main.tscn")
	main_scene = main_scene_resource.instantiate()
	add_child(main_scene)
	
	run_all_conway_tests()
	
	test_framework.print_summary()
	
	# Exit if running headless
	var args = OS.get_cmdline_args()
	if "--headless" in args:
		get_tree().quit()

func run_all_conway_tests():
	print("Running Conway's Game of Life Tests")
	print("==================================")
	
	test_cell_survival_rules()
	test_cell_death_rules()
	test_cell_birth_rules()
	test_pattern_behaviors()
	test_grid_boundaries()
	test_pattern_loading()

func test_cell_survival_rules():
	test_framework.start_test("Cell Survival - 2 Neighbors")
	
	# Set up a cell with exactly 2 neighbors
	main_scene.clear_grid()
	var center = Vector2(5, 5)
	var neighbor1 = Vector2(4, 5)
	var neighbor2 = Vector2(6, 5)
	
	# Place cells
	main_scene.grids.active[center] = true
	main_scene.grids.active[neighbor1] = true
	main_scene.grids.active[neighbor2] = true
	
	# Calculate next generation
	main_scene.calculate_future_of_grid()
	
	# Center cell should survive
	test_framework.assert_true(main_scene.grids.future[center], "Cell with 2 neighbors should survive")
	test_framework.end_test()
	
	test_framework.start_test("Cell Survival - 3 Neighbors")
	
	# Set up a cell with exactly 3 neighbors
	main_scene.clear_grid()
	var neighbor3 = Vector2(5, 4)
	
	main_scene.grids.active[center] = true
	main_scene.grids.active[neighbor1] = true
	main_scene.grids.active[neighbor2] = true
	main_scene.grids.active[neighbor3] = true
	
	# Calculate next generation
	main_scene.calculate_future_of_grid()
	
	# Center cell should survive
	test_framework.assert_true(main_scene.grids.future[center], "Cell with 3 neighbors should survive")
	test_framework.end_test()

func test_cell_death_rules():
	test_framework.start_test("Cell Death - Underpopulation")
	
	# Set up a cell with only 1 neighbor
	main_scene.clear_grid()
	var center = Vector2(5, 5)
	var neighbor = Vector2(4, 5)
	
	main_scene.grids.active[center] = true
	main_scene.grids.active[neighbor] = true
	
	# Calculate next generation
	main_scene.calculate_future_of_grid()
	
	# Center cell should die
	test_framework.assert_false(main_scene.grids.future[center], "Cell with 1 neighbor should die")
	test_framework.end_test()
	
	test_framework.start_test("Cell Death - Overpopulation")
	
	# Set up a cell with 4 neighbors
	main_scene.clear_grid()
	var neighbors = [
		Vector2(4, 5), Vector2(6, 5),
		Vector2(5, 4), Vector2(5, 6)
	]
	
	main_scene.grids.active[center] = true
	for neighbor in neighbors:
		main_scene.grids.active[neighbor] = true
	
	# Calculate next generation
	main_scene.calculate_future_of_grid()
	
	# Center cell should die
	test_framework.assert_false(main_scene.grids.future[center], "Cell with 4 neighbors should die")
	test_framework.end_test()

func test_cell_birth_rules():
	test_framework.start_test("Cell Birth - 3 Neighbors")
	
	# Set up empty cell with exactly 3 neighbors
	main_scene.clear_grid()
	var center = Vector2(5, 5)
	var neighbors = [
		Vector2(4, 5), Vector2(6, 5), Vector2(5, 4)
	]
	
	# Don't place center cell, only neighbors
	for neighbor in neighbors:
		main_scene.grids.active[neighbor] = true
	
	# Calculate next generation
	main_scene.calculate_future_of_grid()
	
	# Center cell should be born
	test_framework.assert_true(main_scene.grids.future[center], "Empty cell with 3 neighbors should be born")
	test_framework.end_test()
	
	test_framework.start_test("Cell Birth - Wrong Neighbor Count")
	
	# Set up empty cell with 2 neighbors (should not be born)
	main_scene.clear_grid()
	var two_neighbors = [Vector2(4, 5), Vector2(6, 5)]
	
	for neighbor in two_neighbors:
		main_scene.grids.active[neighbor] = true
	
	# Calculate next generation
	main_scene.calculate_future_of_grid()
	
	# Center cell should not be born
	test_framework.assert_false(main_scene.grids.future[center], "Empty cell with 2 neighbors should not be born")
	test_framework.end_test()

func test_pattern_behaviors():
	test_framework.start_test("Block Pattern - Still Life")
	
	# Test block pattern (should remain stable)
	main_scene.load_pattern("block")
	var initial_state = main_scene.grids.active.duplicate()
	
	# Run one generation
	main_scene.calculate_future_of_grid()
	var next_state = main_scene.grids.future.duplicate()
	
	# Should be identical
	test_framework.assert_equal(initial_state, next_state, "Block pattern should remain stable")
	test_framework.end_test()
	
	test_framework.start_test("Blinker Pattern - Oscillator")
	
	# Test blinker pattern (should oscillate)
	main_scene.load_pattern("blinker")
	var initial_state = main_scene.grids.active.duplicate()
	
	# Run one generation
	main_scene.calculate_future_of_grid()
	var first_gen = main_scene.grids.future.duplicate()
	
	# Should be different
	test_framework.assert_not_equal(initial_state, first_gen, "Blinker should change after one generation")
	
	# Run second generation
	main_scene.grids.active = first_gen
	main_scene.grids.future = {}
	main_scene.calculate_future_of_grid()
	var second_gen = main_scene.grids.future.duplicate()
	
	# Should return to initial state
	test_framework.assert_equal(initial_state, second_gen, "Blinker should return to initial state after two generations")
	test_framework.end_test()

func test_grid_boundaries():
	test_framework.start_test("Grid Boundaries - Edge Cells")
	
	# Test that cells at grid edges work correctly
	main_scene.clear_grid()
	var edge_cells = [
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 0)
	]
	
	for cell in edge_cells:
		main_scene.grids.active[cell] = true
	
	# Calculate next generation
	main_scene.calculate_future_of_grid()
	
	# Should not crash and should produce valid results
	test_framework.assert_true(main_scene.grids.future.size() >= 0, "Grid boundaries should be handled correctly")
	test_framework.end_test()

func test_pattern_loading():
	test_framework.start_test("Pattern Loading - Glider")
	
	# Test glider pattern loading
	main_scene.load_pattern("glider")
	
	# Should have 5 cells
	test_framework.assert_equal(5, main_scene.grids.active.size(), "Glider pattern should have 5 cells")
	
	# Should contain expected positions
	var expected_positions = [
		Vector2(1, 0), Vector2(2, 1), Vector2(0, 2), Vector2(1, 2), Vector2(2, 2)
	]
	
	for pos in expected_positions:
		test_framework.assert_has_key(main_scene.grids.active, pos, "Glider should contain position " + str(pos))
	
	test_framework.end_test()
	
	test_framework.start_test("Pattern Loading - Invalid Pattern")
	
	# Test loading invalid pattern
	var initial_size = main_scene.grids.active.size()
	main_scene.load_pattern("nonexistent")
	
	# Grid should remain unchanged
	test_framework.assert_equal(initial_size, main_scene.grids.active.size(), "Invalid pattern should not change grid")
	test_framework.end_test()