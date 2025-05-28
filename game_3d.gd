extends Node3D

var Cell3D = load("res://Cell3D.tscn")


func _ready():
	for cellPos in GameState.colony:
				if GameState.colony[cellPos] == true:
					var cell_3d = Cell3D.instantiate()
					var position_3d = Vector3(cellPos.x, -cellPos.y, 0)
					cell_3d.position = position_3d
					add_child(cell_3d)

	# Create client.
	
	
var peer = ENetMultiplayerPeer.new()
var PORT = 3006
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("be_server"):
		var error = peer.create_server(PORT)
		multiplayer.multiplayer_peer = peer
		print(error_string(error))
		multiplayer.peer_connected.connect(_on_player_connected)
		
	if Input.is_action_just_pressed("be_client"):
		var error = peer.create_client('127.0.0.1', PORT)
		print(error_string(error))
		multiplayer.peer_connected.connect(_on_player_connected)
		multiplayer.connected_to_server.connect(_on_player_connected)
		multiplayer.multiplayer_peer = peer


func _on_player_connected(arg):
	print('someone connected')
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
