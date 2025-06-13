extends Node3D

var Cell3D = load("res://Cell3D.tscn")
var PlayerCharacterScene = load("res://addons/PlayerCharacter/PlayerCharacterScene.tscn")


func _ready():
	# Store the pattern immediately when scene loads (before multiplayer overwrites it)
	_store_pattern_on_load()
	
	for cellPos in GameState.colony:
				if GameState.colony[cellPos] == true:
					var cell_3d = Cell3D.instantiate()
					var position_3d = Vector3(cellPos.x, -cellPos.y, 0)
					cell_3d.position = position_3d
					add_child(cell_3d)

	# Don't spawn local player here - wait for multiplayer connection
	
	# Auto-connect for development
	_check_dev_auto_connect()
	
	
var peer = ENetMultiplayerPeer.new()
var PORT = 3006
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("be_server"):
		var error = peer.create_server(PORT)
		multiplayer.multiplayer_peer = peer
		print(error_string(error))

		DisplayServer.window_set_title("Host")

		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		
		# Configure existing player for multiplayer
		_configure_local_player()
		
		# Store local player's pattern
		_store_local_player_pattern()
		
	if Input.is_action_just_pressed("be_client"):
		var error = peer.create_client('127.0.0.1', PORT)
		print(error_string(error))


		multiplayer.multiplayer_peer = peer
		DisplayServer.window_set_title("Client")
		
		multiplayer.connected_to_server.connect(_on_connected_to_server)

var remote_player_dictionary: Dictionary = {}
var player_patterns: Dictionary = {}

@rpc("call_local")
func _add_remote_player_character(new_peer_id: int):
	var new_player_character = PlayerCharacterScene.instantiate()
	new_player_character.is_remote = true
	new_player_character.player_peer_id = new_peer_id
	new_player_character.name = "RemotePlayer_" + str(new_peer_id)
	add_child(new_player_character)
	remote_player_dictionary[new_peer_id] = new_player_character
	print("Added remote player for peer: " + str(new_peer_id) + " at position: " + str(new_player_character.position))
	
	# Request initial position after a brief delay to ensure everything is set up
	call_deferred("_request_position_for_peer", new_peer_id)

@rpc("any_peer", "unreliable")
func receive_player_input(peer_id: int, input_data: Dictionary):
	if remote_player_dictionary.has(peer_id):
		var player = remote_player_dictionary[peer_id]
		player.apply_remote_input(input_data)
	else:
		print("No remote player found for peer " + str(peer_id))

func _on_peer_connected(peer_id: int):
	print("Player connected: " + str(peer_id))
	# Tell everyone except the new peer to add the new peer as remote
	for existing_peer in multiplayer.get_peers():
		if existing_peer != peer_id:
			_add_remote_player_character.rpc_id(existing_peer, peer_id)
	
	# Tell the new peer to add the host as remote
	_add_remote_player_character.rpc_id(peer_id, multiplayer.get_unique_id())
	
	# Add the new peer locally on the host
	if multiplayer.is_server():
		_add_remote_player_character(peer_id)
		
		# Send all existing patterns to the new peer
		_request_all_patterns.rpc_id(peer_id)
	

func _on_peer_disconnected(peer_id: int):
	print("Player disconnected: " + str(peer_id))
	if remote_player_dictionary.has(peer_id):
		remote_player_dictionary[peer_id].queue_free()
		remote_player_dictionary.erase(peer_id)
	
	# Clean up pattern data
	if player_patterns.has(peer_id):
		player_patterns.erase(peer_id)

var local_player_ref: CharacterBody3D

func _configure_local_player():
	var local_player = get_node("Player")
	print("Looking for Player node, found: " + str(local_player))
	if local_player:
		local_player.is_remote = false
		local_player.player_peer_id = multiplayer.get_unique_id()
		local_player.name = "LocalPlayer_" + str(multiplayer.get_unique_id())
		local_player.set_multiplayer_authority(multiplayer.get_unique_id())
		local_player_ref = local_player  # Store reference for later use
		print("Configured local player with authority: " + str(multiplayer.get_unique_id()))
		print("Local player name: " + local_player.name)
		print("Local player position: " + str(local_player.position))
		print("Stored local_player_ref: " + str(local_player_ref))
	else:
		print("Failed to find Player node")

func _on_connected_to_server():
	print("Connected to server")
	_configure_local_player()
	
	# Store local player's pattern and send to server
	_store_local_player_pattern()
	_send_pattern_to_server()
	
	# Request all existing patterns from server
	_request_all_patterns.rpc_id(1)

@rpc("any_peer", "call_remote")
func _request_initial_position():
	print("Received position request from peer: " + str(multiplayer.get_remote_sender_id()))
	# Send our current position to whoever requested it
	if local_player_ref:
		var initial_data = {
			"position": local_player_ref.position,
			"velocity": local_player_ref.velocity,
			"rotation": local_player_ref.rotation
		}
		print("Sending position " + str(local_player_ref.position) + " to peer " + str(multiplayer.get_remote_sender_id()))
		_sync_initial_position.rpc_id(multiplayer.get_remote_sender_id(), multiplayer.get_unique_id(), initial_data)
	else:
		print("Could not find local player reference to send position")

@rpc("any_peer", "call_remote")
func _sync_initial_position(peer_id: int, position_data: Dictionary):
	print("Attempting to sync position for peer " + str(peer_id) + " to " + str(position_data.get("position")))
	if remote_player_dictionary.has(peer_id):
		var remote_player = remote_player_dictionary[peer_id]
		remote_player.position = position_data.get("position", Vector3.ZERO)
		remote_player.velocity = position_data.get("velocity", Vector3.ZERO)
		remote_player.rotation = position_data.get("rotation", Vector3.ZERO)
		print("Successfully synced initial position for peer " + str(peer_id) + ": " + str(position_data.get("position")))
	else:
		print("Could not find remote player for peer " + str(peer_id))

func _request_position_for_peer(peer_id: int):
	print("Requesting position for peer: " + str(peer_id))
	_request_initial_position.rpc_id(peer_id)

func _store_local_player_pattern():
	var local_peer_id = multiplayer.get_unique_id()
	# Use the pattern that was stored on load
	var pattern_to_store = player_patterns.get("local_pattern", GameState.colony.duplicate())
	player_patterns[local_peer_id] = pattern_to_store
	print("Stored pattern for local player " + str(local_peer_id) + " with " + str(pattern_to_store.size()) + " cells")
	
	# Clean up the temporary pattern
	if player_patterns.has("local_pattern"):
		player_patterns.erase("local_pattern")

func _send_pattern_to_server():
	var local_peer_id = multiplayer.get_unique_id()
	if player_patterns.has(local_peer_id):
		_sync_player_pattern.rpc_id(1, local_peer_id, player_patterns[local_peer_id])

@rpc("any_peer", "call_remote")
func _sync_player_pattern(peer_id: int, pattern_data: Dictionary):
	player_patterns[peer_id] = pattern_data
	print("Received pattern from peer " + str(peer_id) + " with " + str(pattern_data.size()) + " cells")
	
	# If this is the server, forward the pattern to all other clients
	if multiplayer.is_server():
		for client_id in multiplayer.get_peers():
			if client_id != peer_id:
				_sync_player_pattern.rpc_id(client_id, peer_id, pattern_data)

@rpc("any_peer", "call_remote")
func _request_all_patterns():
	var sender_id = multiplayer.get_remote_sender_id()
	print("Sending all patterns to new peer: " + str(sender_id))
	
	# Send all stored patterns to the requesting peer (excluding temp patterns)
	for stored_peer_id in player_patterns.keys():
		if str(stored_peer_id) != "local_pattern":  # Don't sync temporary pattern
			_sync_player_pattern.rpc_id(sender_id, stored_peer_id, player_patterns[stored_peer_id])

func _store_pattern_on_load():
	# Store the current pattern in a temporary key to preserve it before multiplayer
	var temp_key = "local_pattern"
	player_patterns[temp_key] = GameState.colony.duplicate()
	print("Stored initial pattern on load with " + str(GameState.colony.size()) + " cells under temp key")

func get_player_pattern(peer_id: int) -> Dictionary:
	print("Getting pattern for peer " + str(peer_id) + ". Available patterns: " + str(player_patterns.keys()))

	if player_patterns.has(peer_id):
		print("Found stored pattern for peer " + str(peer_id) + " with " + str(player_patterns[peer_id].size()) + " cells")
		return player_patterns[peer_id]
	else:
		print("No stored pattern for peer " + str(peer_id) + ", using GameState.colony with " + str(GameState.colony.size()) + " cells")
		# Fallback to current GameState.colony if no stored pattern
		return GameState.colony

func _check_dev_auto_connect():
	# Check for development auto-connect based on command line arguments or debug mode
	var args = OS.get_cmdline_args()
	
	# Check if running in debug mode (in editor) or specific command line args
	var is_debug = OS.is_debug_build()
	var auto_server = "--server" in args or "--host" in args
	var auto_client = "--client" in args
	
	# For easy testing: test if server is actually running and accepting connections
	if is_debug and not auto_server and not auto_client:
		call_deferred("_test_server_connection")
	elif auto_server:
		call_deferred("_dev_start_server")
	elif auto_client:
		call_deferred("_dev_start_client")

func _test_server_connection():
	print("Development mode: Testing for existing server...")
	
	# Create a test multiplayer peer to check connection
	var test_peer = ENetMultiplayerPeer.new()
	var test_multiplayer = MultiplayerAPI.create_default_interface()
	
	# Try to connect
	var result = test_peer.create_client('127.0.0.1', PORT)
	if result != OK:
		print("Development mode: Could not create test client, becoming server")
		_dev_start_server()
		return
	
	test_multiplayer.multiplayer_peer = test_peer
	
	# Wait for connection result
	var connection_timeout = 2.0  # 2 second timeout
	var start_time = Time.get_unix_time_from_system()
	
	while Time.get_unix_time_from_system() - start_time < connection_timeout:
		test_multiplayer.poll()
		
		if test_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			print("Development mode: Found existing server, auto-connecting as client")
			test_peer.close()
			_dev_start_client()
			return
		elif test_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			print("Development mode: Connection failed, becoming server")
			test_peer.close()
			_dev_start_server()
			return
		
		await get_tree().process_frame
	
	# Timeout reached
	print("Development mode: Connection test timed out, becoming server")
	test_peer.close()
	_dev_start_server()

func _dev_start_server():
	var error = peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer
	print("Dev server started: " + error_string(error))
	
	DisplayServer.window_set_title("Dev Host")
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	_configure_local_player()
	_store_local_player_pattern()

func _dev_start_client():
	# Wait a moment for server to start up
	await get_tree().create_timer(1.0).timeout
	
	var error = peer.create_client('127.0.0.1', PORT)
	print("Dev client connecting: " + error_string(error))
	
	multiplayer.multiplayer_peer = peer
	DisplayServer.window_set_title("Dev Client")
	
	multiplayer.connected_to_server.connect(_on_connected_to_server)



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
