extends Node2D

# Rules for Conway’s Game of Life

#     A cell continues to live if it has two or three live neighbors
#     A dead cell with three live neighbors is re-born
#     All other visualCells die or remain dead

# Command line testing flags
var headless_mode = false
var test_conway = false
var skip_ui = false
var debug_mode = false
var pattern_to_load = ""

class GridPos:
## Contains a vector that represents a position in grid units (not pixels)
	var vector: Vector2

var visualCells: Dictionary = {}
func stub():
	for key in visualCells.keys():
		var _cell = visualCells[key]

const CELL_SIZE = 64.0

var grids = {"active": {}, "future": {}}

func _ready():
	parse_command_line_args()
	if pattern_to_load != "":
		load_pattern(pattern_to_load)
	if test_conway:
		run_conway_tests()
	if headless_mode:
		print("Running in headless mode")
		# Exit immediately after processing in headless mode
		call_deferred("_exit_headless")

func parse_command_line_args():
	var args = OS.get_cmdline_args()
	for i in range(args.size()):
		var arg = args[i]
		match arg:
			"--headless":
				headless_mode = true
			"--test-conway":
				test_conway = true
			"--skip-ui":
				skip_ui = true
			"--debug":
				debug_mode = true
			"--pattern":
				if i + 1 < args.size():
					pattern_to_load = args[i + 1]
	
	if debug_mode:
		print("Command line args parsed: ", args)
		print("Headless: ", headless_mode)
		print("Test Conway: ", test_conway)
		print("Pattern: ", pattern_to_load)

func load_pattern(pattern_name: String):
	var patterns = get_predefined_patterns()
	if patterns.has(pattern_name):
		clear_grid()
		var pattern = patterns[pattern_name]
		for pos in pattern:
			var gridPos = GridPos.new()
			gridPos.vector = pos
			place_data_cell(gridPos)
			if not headless_mode:
				place_visual_cell(gridPos)
		print("Loaded pattern: ", pattern_name)
	else:
		print("Unknown pattern: ", pattern_name)

func get_predefined_patterns() -> Dictionary:
	return {
		"glider": [
			Vector2(1, 0),
			Vector2(2, 1),
			Vector2(0, 2),
			Vector2(1, 2),
			Vector2(2, 2)
		],
		"block": [
			Vector2(0, 0),
			Vector2(1, 0),
			Vector2(0, 1),
			Vector2(1, 1)
		],
		"blinker": [
			Vector2(0, 0),
			Vector2(1, 0),
			Vector2(2, 0)
		],
		"toad": [
			Vector2(1, 0),
			Vector2(2, 0),
			Vector2(3, 0),
			Vector2(0, 1),
			Vector2(1, 1),
			Vector2(2, 1)
		],
		"beacon": [
			Vector2(0, 0),
			Vector2(1, 0),
			Vector2(0, 1),
			Vector2(3, 2),
			Vector2(2, 3),
			Vector2(3, 3)
		],
		"pulsar": [
			Vector2(2, 0), Vector2(3, 0), Vector2(4, 0),
			Vector2(8, 0), Vector2(9, 0), Vector2(10, 0),
			Vector2(0, 2), Vector2(5, 2), Vector2(7, 2), Vector2(12, 2),
			Vector2(0, 3), Vector2(5, 3), Vector2(7, 3), Vector2(12, 3),
			Vector2(0, 4), Vector2(5, 4), Vector2(7, 4), Vector2(12, 4),
			Vector2(2, 5), Vector2(3, 5), Vector2(4, 5),
			Vector2(8, 5), Vector2(9, 5), Vector2(10, 5),
			Vector2(2, 7), Vector2(3, 7), Vector2(4, 7),
			Vector2(8, 7), Vector2(9, 7), Vector2(10, 7),
			Vector2(0, 8), Vector2(5, 8), Vector2(7, 8), Vector2(12, 8),
			Vector2(0, 9), Vector2(5, 9), Vector2(7, 9), Vector2(12, 9),
			Vector2(0, 10), Vector2(5, 10), Vector2(7, 10), Vector2(12, 10),
			Vector2(2, 12), Vector2(3, 12), Vector2(4, 12),
			Vector2(8, 12), Vector2(9, 12), Vector2(10, 12)
		]
	}

func clear_grid():
	for key in visualCells.keys():
		visualCells[key].queue_free()
	visualCells.clear()
	grids.active.clear()
	grids.future.clear()

func run_conway_tests():
	print("Running Conway's Game of Life tests...")
	test_glider_pattern()
	test_block_pattern()
	test_blinker_pattern()
	print("Conway tests completed")

func test_glider_pattern():
	print("Testing glider pattern...")
	load_pattern("glider")
	# Run a few iterations to verify glider movement
	for i in range(4):
		calculate_future_of_grid()
		grids.active = grids.future.duplicate()
		grids.future = {}
	print("Glider test completed")

func test_block_pattern():
	print("Testing block pattern...")
	load_pattern("block")
	# Blocks should remain stable
	var _initial_state = grids.active.duplicate()
	calculate_future_of_grid()
	grids.active = grids.future.duplicate()
	grids.future = {}
	# Verify it's still the same
	print("Block test completed")

func test_blinker_pattern():
	print("Testing blinker pattern...")
	load_pattern("blinker")
	# Blinkers should oscillate
	var _initial_state = grids.active.duplicate()
	calculate_future_of_grid()
	grids.active = grids.future.duplicate()
	grids.future = {}
	# After 2 iterations, should return to initial state
	calculate_future_of_grid()
	grids.active = grids.future.duplicate()
	grids.future = {}
	print("Blinker test completed")

func _exit_headless():
	print("Headless mode complete - exiting")
	get_tree().quit()


func calculate_future_of_grid():
	# Process all active cells and their neighbors
	var cells_to_check = {}
	
	# Add all active cells
	for cellKey in grids.active.keys():
		cells_to_check[cellKey] = true
		
		# Add all neighbors of active cells
		for y in [-1, 0, 1]:
			for x in [-1, 0, 1]:
				var neighbor_pos = cellKey + Vector2(x, y)
				cells_to_check[neighbor_pos] = true
	
	# Calculate future for all cells that need checking
	for cellKey in cells_to_check.keys():
		calculate_future_of_cell(grids.active.has(cellKey) && grids.active[cellKey], cellKey)

var to_check = []
func calculate_future_of_cell(alive: bool, cell_key: Vector2, looking_at_neighbors = false):
	var num_live_neighbors = 0
	for y in [-1, 0, 1]:
		for x in [-1, 0, 1]:
			if x != 0 or y != 0:
				var neighbor_pos = cell_key + Vector2(x, y)
				# if !grids.active.has(neighbor_pos):
				# 	grids.future[neighbor_pos] = false
				if grids.active.has(neighbor_pos):
					if grids.active[neighbor_pos]:
						num_live_neighbors += 1

				if !looking_at_neighbors:
					calculate_future_of_cell(grids.active.has(neighbor_pos) && grids.active[neighbor_pos], neighbor_pos, true)
	## @todo use place data cell instead of manually modifying grids here
	if (alive && (num_live_neighbors == 2 or num_live_neighbors == 3)):
		grids.future[cell_key] = true
	elif !alive && num_live_neighbors == 3:
		grids.future[cell_key] = true
	else:
		grids.future[cell_key] = false
	


const ZOOM_STEP = 0.1
# https://gdscript.com/projects/game-of-life/
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			place_or_remove_cell(event.position)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			GameState.colony = grids.active
			get_tree().change_scene_to_file("res://Game3D.tscn")
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change_zoom(-ZOOM_STEP)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change_zoom(ZOOM_STEP)
	if event is InputEventMouseMotion && event.button_mask == MOUSE_BUTTON_MASK_MIDDLE:
		move_camera(event.relative)
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
	if event.is_action_pressed("ui_accept"):
		start_stop()
	if event.is_action_pressed("ui_reset"):
		reset()
		
var zoom: float = 1.0

func change_zoom(dz: float):
	zoom = clamp(zoom + dz, 0.1, 8.0)
	$Camera2D.zoom = Vector2(zoom, zoom)
	
func move_camera(dv: Vector2):
	$Camera2D.offset -= dv


func place_or_remove_cell(pos: Vector2):
	pos = mouse_pos_to_cam_pos(pos)
	var gridPos: GridPos = get_pos_in_grid_units(pos)
	if not visualCells.has(gridPos.vector):
		place_data_cell(gridPos)
		place_visual_cell(gridPos)
	else:
		remove_data_cell(gridPos)
		remove_visual_cell(gridPos)

var num_placed_cells = 0
func place_data_cell(gridPos: GridPos, grid = grids.active):
	grid[gridPos.vector] = true
	num_placed_cells += 1

func place_visual_cell(gridPos: GridPos):
	var cell = $Cell.duplicate()
	cell.position = gridPos.vector * CELL_SIZE
	add_child(cell)
	cell.show()
	visualCells[gridPos.vector] = cell
	var rich_text_label: RichTextLabel = cell.get_child(0)
	rich_text_label.text = str(gridPos.vector)
	
	
func remove_data_cell(gridPos: GridPos):
	if visualCells.has(gridPos.vector):
		grids.future.erase(gridPos.vector)
		num_placed_cells -= 1

func remove_visual_cell(gridPos: GridPos):
	visualCells[gridPos.vector].queue_free()
	visualCells.erase(gridPos.vector)

func get_pos_in_grid_units(pos: Vector2) -> GridPos:
	var gridPos: GridPos = GridPos.new()
	var pixelsPerCellSide = CELL_SIZE  * $Camera2D.zoom.x
	gridPos.vector = (pos / pixelsPerCellSide).floor()
	return gridPos
	
func start_stop():
	if $Timer.is_stopped() && visualCells.size() > 0:
		$Timer.start()
		print('start timer')
	else:
		$Timer.stop()
		print('stop timer')
	
func reset():
	$Timer.stop()
	for key in visualCells.keys():
		visualCells[key].queue_free()
		grids.future.clear()
		visualCells.clear()
		print('reset stage')

func mouse_pos_to_cam_pos(pos):
	return pos + $Camera2D.offset / $Camera2D.zoom - get_viewport_rect().size / 2

func _on_timer_timeout():
	print("tick")



	
	calculate_future_of_grid()
	grids.active = grids.future.duplicate()
	
	grids.future = {}

	for cellKey in grids.active:
		var cellGridPos = GridPos.new()
		cellGridPos.vector = cellKey
		if grids.active[cellKey] == true && !visualCells.has(cellKey):
			place_visual_cell(cellGridPos)
		elif grids.active[cellKey] == false && visualCells.has(cellKey):
			remove_visual_cell(cellGridPos)
