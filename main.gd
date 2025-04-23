extends Node2D

# Rules for Conway’s Game of Life

#     A cell continues to live if it has two or three live neighbors
#     A dead cell with three live neighbors is re-born
#     All other visualCells die or remain dead

class GridPos:
## Contains a vector that represents a position in grid units (not pixels)
	var vector: Vector2

var visualCells: Dictionary = {}
func stub():
	for key in visualCells.keys():
		var cell = visualCells[key]

const CELL_SIZE = 64.0

var grids = {"active": {}, "future": {}}


func calculate_future_of_grid():
	print('grid state before calculating future')
	print('active', grids.active)
	print('future', grids.future)
	for cellKey in visualCells.keys():
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
	
	print('calculatedFuture', cell_key, grids.future[cell_key])


const ZOOM_STEP = 0.1
# https://gdscript.com/projects/game-of-life/
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		print('mouse', event.pressed)
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			place_or_remove_cell(event.position)
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
	print(pos)
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
			print('visual place')
			place_visual_cell(cellGridPos)
		elif grids.active[cellKey] == false && visualCells.has(cellKey):
			print('visual removing')
			remove_visual_cell(cellGridPos)

	print(num_placed_cells)
	print(grids.active)
