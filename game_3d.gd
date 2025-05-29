extends Node3D

var Cell3D = load("res://Cell3D.tscn")
var PlayerCharacterScene = load("res://addons/PlayerCharacter/PlayerCharacterScene.tscn")


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

		DisplayServer.window_set_title("Host")

		multiplayer.peer_connected.connect(func(new_peer_id):
			print('hello ' + str(new_peer_id))
			_add_remote_player_character.rpc(new_peer_id)
		)
		
	if Input.is_action_just_pressed("be_client"):
		var error = peer.create_client('127.0.0.1', PORT)
		print(error_string(error))


		multiplayer.multiplayer_peer = peer
		DisplayServer.window_set_title("Client")

var remote_player_dictionary: Dictionary = {}
@rpc("call_local")
func _add_remote_player_character(new_peer_id: int):
	var new_player_character = PlayerCharacterScene.instantiate()
	new_player_character.is_remote = true
	$"/root".add_child(new_player_character)
	remote_player_dictionary.set(new_peer_id, new_player_character)

@rpc("any_peer", "call_remote")
func send_input():
	pass



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
