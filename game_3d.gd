extends Node3D

var Cell3D = load("res://Cell3D.tscn")


func _ready():
	for cellPos in GameState.colony:
				if GameState.colony[cellPos] == true:
					var cell_3d = Cell3D.instantiate()
					var position_3d = Vector3(cellPos.x, cellPos.y, 0)
					cell_3d.position = position_3d
					add_child(cell_3d)


# var has_loaded_cells = false
# func _unhandled_input(event: InputEvent) -> void:
# 	if event is InputEventMouseButton:
# 		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed && not has_loaded_cells:
# 			for cellPos in GameState.colony:
# 				if GameState.colony[cellPos] == true:
# 					var cell_3d = Cell3D.instantiate()
# 					var position_3d = Vector3(cellPos.x, cellPos.y, 0)
# 					cell_3d.position = position_3d
# 					add_child(cell_3d)
# 			has_loaded_cells = true

		# if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# 	GameState.colony = grids.active
		# 	get_tree().change_scene_to_file("res://node_3d.tscn")
		# if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		# 	change_zoom(-ZOOM_STEP)
		# if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		# 	change_zoom(ZOOM_STEP)
