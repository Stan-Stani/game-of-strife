extends Node2D

const ZOOM_STEP = 0.1
# https://gdscript.com/projects/game-of-life/
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			place_cell(event.position)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			remove_cell(event.position)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change_zoom(ZOOM_STEP)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change_zoom(-ZOOM_STEP)
			
