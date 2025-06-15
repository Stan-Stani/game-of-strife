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
	# _check_dev_auto_connect()
	
	
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
		_scan_lan_for_games()

var remote_player_dictionary: Dictionary = {}
var player_patterns: Dictionary = {}

@rpc("call_local")
func _add_remote_player_character(new_peer_id: int):
	var new_player_character = PlayerCharacterScene.instantiate()
	new_player_character.is_remote = true
	new_player_character.player_peer_id = new_peer_id
	new_player_character.name = "RemotePlayer_" + str(new_peer_id)
	
	# Simple collision system: all players on same layer, can collide with each other
	new_player_character.collision_layer = 4  # All players on layer 4
	new_player_character.collision_mask = 7   # Collide with environment (1), floor (2), and other players (4)
	
	add_child(new_player_character)
	remote_player_dictionary[new_peer_id] = new_player_character
	
	# Create pattern-based model for remote player (deferred to allow pattern sync)
	call_deferred("_create_pattern_model_for_player", new_player_character)
	
	# Request initial position after a brief delay to ensure everything is set up
	call_deferred("_request_position_for_peer", new_peer_id)

@rpc("any_peer", "unreliable")
func receive_player_input(peer_id: int, input_data: Dictionary):
	if remote_player_dictionary.has(peer_id):
		var player = remote_player_dictionary[peer_id]
		player.apply_remote_input(input_data)
	else:
		pass

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
	if local_player:
		local_player.is_remote = false
		local_player.player_peer_id = multiplayer.get_unique_id()
		local_player.name = "LocalPlayer_" + str(multiplayer.get_unique_id())
		local_player.set_multiplayer_authority(multiplayer.get_unique_id())
		local_player_ref = local_player  # Store reference for later use
		
		# Simple collision system: all players on same layer, can collide with each other
		local_player.collision_layer = 4  # All players on layer 4
		local_player.collision_mask = 7   # Collide with environment (1), floor (2), and other players (4)
		
		# Create pattern-based model for local player
		call_deferred("_create_pattern_model_for_player", local_player)
	else:
		pass

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
	# Send our current position to whoever requested it
	if local_player_ref:
		var initial_data = {
			"position": local_player_ref.position,
			"velocity": local_player_ref.velocity,
			"rotation": local_player_ref.rotation
		}
		_sync_initial_position.rpc_id(multiplayer.get_remote_sender_id(), multiplayer.get_unique_id(), initial_data)
	else:
		pass

@rpc("any_peer", "call_remote")
func _sync_initial_position(peer_id: int, position_data: Dictionary):
	if remote_player_dictionary.has(peer_id):
		var remote_player = remote_player_dictionary[peer_id]
		remote_player.position = position_data.get("position", Vector3.ZERO)
		remote_player.velocity = position_data.get("velocity", Vector3.ZERO)
		remote_player.rotation = position_data.get("rotation", Vector3.ZERO)
	else:
		pass

func _request_position_for_peer(peer_id: int):
	_request_initial_position.rpc_id(peer_id)

func _store_local_player_pattern():
	var local_peer_id = multiplayer.get_unique_id()
	# Use the pattern that was stored on load
	var pattern_to_store = player_patterns.get("local_pattern", GameState.colony.duplicate())
	player_patterns[local_peer_id] = pattern_to_store
	
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
	
	# Update the visual model for this peer if they have a player character
	_update_player_pattern_model(peer_id)
	
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

func get_player_pattern(peer_id: int) -> Dictionary:

	if player_patterns.has(peer_id):
		return player_patterns[peer_id]
	else:
		pass
		# Fallback to current GameState.colony if no stored pattern
		return GameState.colony

func _scan_lan_for_games():
	print("Scanning LAN for active games...")
	
	# Scan a smaller, more targeted range to avoid resource exhaustion
	var ips_to_scan = [
		"127.0.0.1",      # Localhost
		"192.168.1.1",    # Common router IPs
		"192.168.0.1",
		"192.168.1.100",  # Common static IPs
		"192.168.0.100",
		"10.0.0.1",
		"10.0.0.100"
	]
	
	# Add current network range IPs (more targeted approach)
	var local_ip = _get_local_ip()
	if local_ip != "":
		print("Detected local IP: " + local_ip)
		var ip_parts = local_ip.split(".")
		if ip_parts.size() == 4:
			var base_ip = ip_parts[0] + "." + ip_parts[1] + "." + ip_parts[2] + "."
			# Scan a few IPs around the local machine
			for i in range(1, 20):  # Just scan first 20 IPs in local range
				ips_to_scan.append(base_ip + str(i))
	else:
		print("Could not detect local IP, using default ranges only")
	
	print("Scanning " + str(ips_to_scan.size()) + " IP addresses:")
	for ip in ips_to_scan:
		print("  " + ip + ":" + str(PORT))
	
	var found_servers = []
	
	# Scan each IP with proper error handling
	for ip_address in ips_to_scan:
		if ip_address == local_ip:  # Skip scanning our own IP
			print("Skipping own IP: " + ip_address)
			continue
		
		print("Testing: " + ip_address)
		var is_server_active = await _test_server_at_ip(ip_address)
		if is_server_active:
			print("Found server at: " + ip_address)
			found_servers.append(ip_address)
			# Stop scanning after finding the first server for faster connection
			print("Stopping scan - found active server")
			break
		else:
			print("No server at: " + ip_address)
		
		# Small delay between scans to prevent resource exhaustion
		await get_tree().create_timer(0.01).timeout
	
	# Display results
	if found_servers.size() > 0:
		print("Found " + str(found_servers.size()) + " active game(s):")
		for i in range(found_servers.size()):
			print("  [" + str(i + 1) + "] " + found_servers[i] + ":" + str(PORT))
		
		# For now, auto-connect to the first server found
		print("Connecting to: " + found_servers[0])
		_connect_to_server(found_servers[0])
	else:
		print("No active games found on LAN")
		print("Connecting to localhost (127.0.0.1) as fallback...")
		_connect_to_server("127.0.0.1")

func _get_local_ip() -> String:
	# Try to get the local IP address
	var ip_addresses = IP.get_local_addresses()
	print("Detected IP addresses: " + str(ip_addresses))
	
	# Prioritize 192.168.x.x range (most common home networks)
	for ip in ip_addresses:
		if ip.begins_with("192.168."):
			print("Using 192.168.x IP: " + ip)
			return ip
	
	# Then try 10.x.x.x range
	for ip in ip_addresses:
		if ip.begins_with("10."):
			print("Using 10.x IP: " + ip)
			return ip
	
	# Finally try 172.16-31.x.x range (but exclude WSL virtual networks)
	for ip in ip_addresses:
		if ip.begins_with("172."):
			# Check if it's in the valid private range (172.16.0.0 to 172.31.255.255)
			var parts = ip.split(".")
			if parts.size() == 4:
				var second_octet = int(parts[1])
				if second_octet >= 16 and second_octet <= 31:
					# Skip WSL ranges that are typically 172.30.x.x
					if second_octet != 30:
						print("Using 172.x IP: " + ip)
						return ip
	
	print("No suitable LAN IP found")
	return ""

func _test_server_at_ip(ip_address: String) -> bool:
	# Create a new peer for each test to avoid conflicts
	var test_peer = ENetMultiplayerPeer.new()
	
	# Try to create client connection
	var result = test_peer.create_client(ip_address, PORT)
	if result != OK:
		print("  Failed to create client for " + ip_address + ": " + error_string(result))
		test_peer.close()
		return false
	
	print("  Created client connection attempt to " + ip_address)
	
	# Use a longer timeout for more reliable detection
	var timeout = 0.5  # 500ms timeout - much more generous
	var start_time = Time.get_unix_time_from_system()
	
	# Simple polling loop with timeout
	while Time.get_unix_time_from_system() - start_time < timeout:
		# IMPORTANT: Poll the peer to process network events
		test_peer.poll()
		
		var status = test_peer.get_connection_status()
		var status_name = ""
		match status:
			MultiplayerPeer.CONNECTION_DISCONNECTED:
				status_name = "DISCONNECTED"
			MultiplayerPeer.CONNECTION_CONNECTING:
				status_name = "CONNECTING"
			MultiplayerPeer.CONNECTION_CONNECTED:
				status_name = "CONNECTED"
			_:
				status_name = "UNKNOWN"
		
		print("  Status for " + ip_address + ": " + str(status) + " (" + status_name + ")")
		
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			print("  SUCCESS: Connected to " + ip_address)
			test_peer.close()
			return true
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			print("  FAILED: Disconnected from " + ip_address)
			test_peer.close()
			return false
		
		# Very short frame wait
		await get_tree().process_frame
	
	# Cleanup and return false for timeout
	print("  TIMEOUT: No response from " + ip_address + " after " + str(timeout) + "s")
	test_peer.close()
	return false

func _connect_to_server(ip_address: String):
	var error = peer.create_client(ip_address, PORT)
	print("Connecting to " + ip_address + ": " + error_string(error))
	
	multiplayer.multiplayer_peer = peer
	DisplayServer.window_set_title("Client")
	
	multiplayer.connected_to_server.connect(_on_connected_to_server)

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
	
	# Create a test multiplayer peer to check connection
	var test_peer = ENetMultiplayerPeer.new()
	var test_multiplayer = MultiplayerAPI.create_default_interface()
	
	# Try to connect
	var result = test_peer.create_client('127.0.0.1', PORT)
	if result != OK:
		_dev_start_server()
		return
	
	test_multiplayer.multiplayer_peer = test_peer
	
	# Wait for connection result
	var connection_timeout = 2.0  # 2 second timeout
	var start_time = Time.get_unix_time_from_system()
	
	while Time.get_unix_time_from_system() - start_time < connection_timeout:
		test_multiplayer.poll()
		
		if test_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			test_peer.close()
			_dev_start_client()
			return
		elif test_peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			test_peer.close()
			_dev_start_server()
			return
		
		await get_tree().process_frame
	
	# Timeout reached
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

func _create_pattern_model_for_player(player_character):
	if player_character and player_character.has_method("create_pattern_model"):
			player_character.create_pattern_model()
	else:
		pass

func _update_player_pattern_model(peer_id: int):
	# Find the player character for this peer and update their model
	var player_character = null
	
	# Check if it's the local player
	if local_player_ref and local_player_ref.player_peer_id == peer_id:
		player_character = local_player_ref
	# Check remote players
	elif remote_player_dictionary.has(peer_id):
		player_character = remote_player_dictionary[peer_id]
	
	if player_character:
		_create_pattern_model_for_player(player_character)
	else:
		pass

# Collision layer mapping for peer IDs
var peer_to_layer_map = {}
var next_layer_id = 1

func get_collision_layer_for_peer(peer_id: int) -> int:
	# Map peer IDs to collision layers 1-4 (supports up to 4 players)
	if not peer_to_layer_map.has(peer_id):
		if next_layer_id > 4:
			return 4
		peer_to_layer_map[peer_id] = next_layer_id
		next_layer_id += 1
	
	return peer_to_layer_map[peer_id]


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
