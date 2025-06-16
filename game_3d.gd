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

	# Restore multiplayer connection if it exists
	if GameState.restore_multiplayer_peer():
		# We're returning from pattern selection, restore multiplayer state
		_restore_multiplayer_state()
	
	# Don't spawn local player here - wait for multiplayer connection
	
	# Auto-connect for development
	# _check_dev_auto_connect()
	
	
var peer = ENetMultiplayerPeer.new()
var PORT = 3006
var HealthUI = preload("res://HealthUI.tscn")
var health_ui_instance = null
func _process(_delta: float) -> void:
	# Handle pattern selection mode inputs (but don't return early)
	if pattern_selection_overlay != null:
		if Input.is_action_just_pressed("ragdoll"):  # 'R' key
			# Transition to 2D pattern editor
			GameState.colony = get_player_pattern(multiplayer.get_unique_id())
			get_tree().change_scene_to_file("res://Main.tscn")
		elif Input.is_action_just_pressed("ui_accept"):  # Enter key
			# Respawn immediately with current pattern (no changes needed)
			var local_player = get_local_player()
			if local_player and local_player.has_method("_request_respawn"):
				local_player._request_respawn.rpc(true)
				_hide_pattern_selection_overlay()
	
	if Input.is_action_just_pressed("be_server"):
		var error = peer.create_server(PORT)
		GameState.set_multiplayer_peer(peer, true)  # Store in GameState
		print(error_string(error))

		DisplayServer.window_set_title("Host")

		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		
		# Configure existing player for multiplayer
		_configure_local_player()
		
		# Store local player's pattern
		_store_local_player_pattern()
		
	if Input.is_action_just_pressed("be_client"):
		_show_server_selection_ui()

var remote_player_dictionary: Dictionary = {}
var player_patterns: Dictionary = {}

# UI Management
var ServerSelectionUI = preload("res://ServerSelectionUI.tscn")
var server_ui_instance = null

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
		
		# Create health UI for local player
		_create_health_ui()
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
	
	# Create health UI for client
	_create_health_ui()
	
	# Notify server list of successful connection
	if peer.has_meta("connecting_ip") and server_ui_instance:
		server_ui_instance.server_connection_succeeded(peer.get_meta("connecting_ip"))

func _on_connection_failed():
	print("Connection to server failed")
	
	# Notify server list of failed connection
	if peer.has_meta("connecting_ip") and server_ui_instance:
		server_ui_instance.server_connection_failed(peer.get_meta("connecting_ip"))
		
	# Clean up
	peer.close()

func _on_server_disconnected():
	print("Disconnected from server")
	# Could add logic here to mark server as unreliable

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

func _show_server_selection_ui():
	# Release mouse cursor for UI interaction
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Create and show the server selection UI
	if server_ui_instance == null:
		server_ui_instance = ServerSelectionUI.instantiate()
		add_child(server_ui_instance)
		
		# Connect UI signals
		server_ui_instance.server_selected.connect(_on_server_selected)
		server_ui_instance.cancelled.connect(_on_server_ui_cancelled)
		server_ui_instance.refresh_requested.connect(_on_refresh_requested)
	
	# Show scanning indicator and start scan
	server_ui_instance.start_scanning()
	_scan_lan_for_games_ui()

func _on_server_selected(ip_address: String):
	print("User selected server: " + ip_address)
	_connect_to_server(ip_address)
	_hide_server_selection_ui()

func _on_server_ui_cancelled():
	print("Server selection cancelled")
	_hide_server_selection_ui()

func _on_refresh_requested():
	print("Refreshing server list...")
	server_ui_instance.start_scanning()
	_scan_lan_for_games_ui()

func _hide_server_selection_ui():
	# Restore mouse capture for camera control
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if server_ui_instance != null:
		server_ui_instance.queue_free()
		server_ui_instance = null

func _scan_lan_for_games_ui():
	# Modified version that updates UI instead of auto-connecting
	
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
	
	# Add current network range IPs 
	var local_ip = _get_local_ip()
	if local_ip != "":
		var ip_parts = local_ip.split(".")
		if ip_parts.size() == 4:
			var base_ip = ip_parts[0] + "." + ip_parts[1] + "." + ip_parts[2] + "."
			
			# Choose scanning approach based on preference
			var full_network_scan = false  # Set to true for complete network scan
			
			if full_network_scan:
				# Scan entire subnet (warning: slower but comprehensive)
				for i in range(1, 255):
					ips_to_scan.append(base_ip + str(i))
			else:
				# Targeted scan - entire last byte (1-254)
				for i in range(1, 255):
					ips_to_scan.append(base_ip + str(i))
	
	var found_servers = []
	
	# Scan each IP with proper error handling - show servers as they're found
	for ip_address in ips_to_scan:
		# Check for cancellation before each IP test
		if server_ui_instance != null and server_ui_instance.is_scan_cancelled():
			break
		
		if ip_address == local_ip:  # Skip scanning our own IP
			if server_ui_instance != null:
				server_ui_instance.update_scanning_status(ip_address, "SKIPPED")
				server_ui_instance.log_scan_attempt(ip_address, "SKIPPED (own IP)")
			continue
		
		if server_ui_instance != null:
			server_ui_instance.update_scanning_status(ip_address, "TESTING")
			server_ui_instance.log_scan_attempt(ip_address, "TESTING...")
		
		var is_server_active = await _test_server_at_ip(ip_address)
		
		# Check for cancellation after each test (in case user cancelled during the test)
		if server_ui_instance != null and server_ui_instance.is_scan_cancelled():
			break
		
		if is_server_active:
			found_servers.append(ip_address)
			
			# Update status and log with success result
			if server_ui_instance != null:
				server_ui_instance.update_scanning_status(ip_address, "SUCCESS")
				server_ui_instance.update_last_log_entry(ip_address, "SUCCESS - Server found!")
				server_ui_instance.add_server_to_list(ip_address)
		else:
			if server_ui_instance != null:
				server_ui_instance.update_scanning_status(ip_address, "FAILED")
				server_ui_instance.update_last_log_entry(ip_address, "FAILED - No server")
		
		# Small delay between scans to prevent resource exhaustion, but check for cancellation first
		if server_ui_instance != null and server_ui_instance.is_scan_cancelled():
			break
		await get_tree().create_timer(0.01).timeout
	
	# Finish scanning
	if server_ui_instance != null:
		server_ui_instance.finish_scanning()

func _scan_lan_for_games():
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
		var ip_parts = local_ip.split(".")
		if ip_parts.size() == 4:
			var base_ip = ip_parts[0] + "." + ip_parts[1] + "." + ip_parts[2] + "."
			# Scan a few IPs around the local machine
			for i in range(1, 20):  # Just scan first 20 IPs in local range
				ips_to_scan.append(base_ip + str(i))
	
	var found_servers = []
	
	# Scan each IP with proper error handling
	for ip_address in ips_to_scan:
		if ip_address == local_ip:  # Skip scanning our own IP
			continue
		
		var is_server_active = await _test_server_at_ip(ip_address)
		if is_server_active:
			found_servers.append(ip_address)
			# Stop scanning after finding the first server for faster connection
			break
		
		# Small delay between scans to prevent resource exhaustion
		await get_tree().create_timer(0.01).timeout
	
	# Display results
	if found_servers.size() > 0:
		# For now, auto-connect to the first server found
		_connect_to_server(found_servers[0])
	else:
		# Connecting to localhost as fallback
		_connect_to_server("127.0.0.1")

func _get_local_ip() -> String:
	# Try to get the local IP address
	var ip_addresses = IP.get_local_addresses()
	
	# Prioritize 192.168.x.x range (most common home networks)
	for ip in ip_addresses:
		if ip.begins_with("192.168."):
			return ip
	
	# Then try 10.x.x.x range
	for ip in ip_addresses:
		if ip.begins_with("10."):
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
						return ip
	
	return ""

func _test_server_at_ip(ip_address: String) -> bool:
	# Check for cancellation before starting the connection test
	if server_ui_instance != null and server_ui_instance.is_scan_cancelled():
		return false
	
	# Create a new peer for each test to avoid conflicts
	var test_peer = ENetMultiplayerPeer.new()
	
	# Try to create client connection
	var result = test_peer.create_client(ip_address, PORT)
	if result != OK:
		test_peer.close()
		return false
	
	# Use a shorter timeout but check more frequently for better responsiveness
	var timeout = 0.2  # 200ms timeout - faster response
	var start_time = Time.get_unix_time_from_system()
	
	# Simple polling loop with timeout AND cancellation check - much more frequent checks
	while Time.get_unix_time_from_system() - start_time < timeout:
		# Check for cancellation during the connection test
		if server_ui_instance != null and server_ui_instance.is_scan_cancelled():
			test_peer.close()
			return false
		
		# IMPORTANT: Poll the peer to process network events
		test_peer.poll()
		
		var status = test_peer.get_connection_status()
		
		# Only print status changes to reduce spam, but check for results
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			test_peer.close()
			return true
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			test_peer.close()
			return false
		
		# Check for cancellation again before the frame wait
		if server_ui_instance != null and server_ui_instance.is_scan_cancelled():
			test_peer.close()
			return false
		
		# Much shorter wait for faster cancellation response
		await get_tree().create_timer(0.01).timeout
	
	# Cleanup and return false for timeout
	test_peer.close()
	return false

func _connect_to_server(ip_address: String):
	var error = peer.create_client(ip_address, PORT)
	print("Connecting to " + ip_address + ": " + error_string(error))
	
	GameState.set_multiplayer_peer(peer, false)  # Store in GameState
	DisplayServer.window_set_title("Client")
	
	# Store IP for success/failure callbacks
	peer.set_meta("connecting_ip", ip_address)
	
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

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
	GameState.set_multiplayer_peer(peer, true)
	print("Dev server started: " + error_string(error))
	
	DisplayServer.window_set_title("Dev Host")
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	_configure_local_player()
	_store_local_player_pattern()
	_create_health_ui()

func _dev_start_client():
	# Wait a moment for server to start up
	await get_tree().create_timer(1.0).timeout
	
	var error = peer.create_client('127.0.0.1', PORT)
	print("Dev client connecting: " + error_string(error))
	
	GameState.set_multiplayer_peer(peer, false)
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

func _create_health_ui():
	if health_ui_instance == null:
		health_ui_instance = HealthUI.instantiate()
		add_child(health_ui_instance)
		print("Health UI created")

var pattern_selection_overlay = null

func _show_pattern_selection_overlay():
	if pattern_selection_overlay != null:
		return
	
	# Create a simple Control overlay with instructions
	pattern_selection_overlay = Control.new()
	pattern_selection_overlay.name = "PatternSelectionOverlay"
	pattern_selection_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Create background
	var background = ColorRect.new()
	background.color = Color(0, 0, 0, 0.8)  # Semi-transparent black
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pattern_selection_overlay.add_child(background)
	
	# Create instruction label
	var instruction_label = Label.new()
	instruction_label.text = "PATTERN SELECTION MODE\n\nPress 'R' to enter 2D pattern editor\nOr press 'Enter' to respawn with current pattern"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	instruction_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	instruction_label.position = Vector2(-200, -50)
	instruction_label.size = Vector2(400, 100)
	
	# Style the label
	instruction_label.add_theme_font_size_override("font_size", 18)
	instruction_label.add_theme_color_override("font_color", Color.WHITE)
	
	pattern_selection_overlay.add_child(instruction_label)
	add_child(pattern_selection_overlay)
	
	# Show mouse cursor for UI interaction
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	print("Pattern selection overlay created")

func _on_pattern_selected():
	# Called when player finishes selecting a pattern
	# Update the player's pattern in our storage
	var local_peer_id = multiplayer.get_unique_id()
	player_patterns[local_peer_id] = GameState.colony.duplicate()
	
	# Sync the new pattern with other players
	if multiplayer.is_server():
		for client_id in multiplayer.get_peers():
			_sync_player_pattern.rpc_id(client_id, local_peer_id, player_patterns[local_peer_id])
	else:
		_sync_player_pattern.rpc_id(1, local_peer_id, player_patterns[local_peer_id])
	
	_hide_pattern_selection_overlay()
	
	# Find the local player and tell them to respawn
	var local_player = get_local_player()
	if local_player and local_player.has_method("_exit_pattern_selection"):
		local_player._exit_pattern_selection()

func _hide_pattern_selection_overlay():
	if pattern_selection_overlay != null:
		pattern_selection_overlay.queue_free()
		pattern_selection_overlay = null
		
		# Restore mouse capture for 3D camera
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
		print("Pattern selection overlay removed")

func get_local_player():
	# Find the local player character
	if local_player_ref:
		return local_player_ref
	
	# Fallback: look for Player node
	var player = get_node_or_null("Player")
	if player and not player.is_remote:
		return player
	
	return null

func _restore_multiplayer_state():
	# Restore multiplayer state after returning from pattern selection
	print("Restoring multiplayer state...")
	
	# Reconnect signals that were lost during scene change
	if GameState.is_host:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		DisplayServer.window_set_title("Host")
	else:
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)
		DisplayServer.window_set_title("Client")
	
	# Configure local player
	_configure_local_player()
	
	# Check if the player should still be in pattern selection mode
	var local_player = get_local_player()
	var was_in_pattern_selection = false
	if local_player and local_player.has_meta("in_pattern_selection"):
		was_in_pattern_selection = local_player.get_meta("in_pattern_selection")
	
	# Store local player's pattern (updated from pattern selection)
	_store_local_player_pattern()
	
	# If player was in pattern selection, keep them invisible and show overlay
	if was_in_pattern_selection and local_player:
		local_player.visible = false
		local_player.set_physics_process(false)
		local_player.set_process(false)
		_show_pattern_selection_overlay()
	
	# Recreate all remote players that are still connected
	_recreate_remote_players()
	
	# IMPORTANT: Send the updated pattern to other players AFTER recreating players
	var local_peer_id = multiplayer.get_unique_id()
	if player_patterns.has(local_peer_id):
		print("DEBUG: Syncing updated pattern to other players. Pattern size: " + str(player_patterns[local_peer_id].size()))
		# Sync new pattern to all other players
		if GameState.is_host:
			for client_id in multiplayer.get_peers():
				_sync_player_pattern.rpc_id(client_id, local_peer_id, player_patterns[local_peer_id])
		else:
			_sync_player_pattern.rpc_id(1, local_peer_id, player_patterns[local_peer_id])
	
	# Request all patterns from other players and notify we're back
	if GameState.is_host:
		# If we're the host, tell other players we're back
		_notify_player_returned.rpc()
	else:
		# If we're a client, request current game state from server
		_request_current_game_state.rpc_id(1)
	
	# Give a moment for network sync, then update our own model
	await get_tree().create_timer(0.1).timeout
	if local_player_ref and local_player_ref.has_method("create_pattern_model"):
		local_player_ref.create_pattern_model()
		print("DEBUG: Updated local player pattern model after restoration")

func _recreate_remote_players():
	# Recreate remote player characters for all connected peers
	print("Recreating remote players...")
	
	# Clear existing remote players first
	for peer_id in remote_player_dictionary.keys():
		if remote_player_dictionary[peer_id] and is_instance_valid(remote_player_dictionary[peer_id]):
			remote_player_dictionary[peer_id].queue_free()
	remote_player_dictionary.clear()
	
	# Get list of currently connected peers
	var connected_peers = multiplayer.get_peers()
	print("Connected peers: " + str(connected_peers))
	
	# Create remote player for each connected peer (except ourselves)
	for peer_id in connected_peers:
		if peer_id != multiplayer.get_unique_id():
			print("Creating remote player for peer: " + str(peer_id))
			_add_remote_player_character(peer_id)

@rpc("any_peer", "call_local")
func _notify_player_returned():
	# Called when a player returns from pattern selection
	var sender_id = multiplayer.get_remote_sender_id()
	print("Player " + str(sender_id) + " returned from pattern selection")
	
	# If we don't have this player as a remote, add them
	if not remote_player_dictionary.has(sender_id):
		_add_remote_player_character(sender_id)
	else:
		# Update their pattern model with the latest pattern
		_update_player_pattern_model(sender_id)

@rpc("any_peer", "call_remote")
func _request_current_game_state():
	# Server sends current game state to the requesting client
	var requester_id = multiplayer.get_remote_sender_id()
	print("Sending current game state to peer: " + str(requester_id))
	
	# Send list of all connected players
	var connected_peers = multiplayer.get_peers()
	_sync_connected_players.rpc_id(requester_id, connected_peers)
	
	# Send all stored patterns
	for stored_peer_id in player_patterns.keys():
		if str(stored_peer_id) != "local_pattern":  # Don't sync temporary pattern
			_sync_player_pattern.rpc_id(requester_id, stored_peer_id, player_patterns[stored_peer_id])

@rpc("any_peer", "call_remote")
func _sync_connected_players(connected_peers: Array):
	# Receive list of connected players and create remote players for them
	print("Received connected players list: " + str(connected_peers))
	
	for peer_id in connected_peers:
		if peer_id != multiplayer.get_unique_id() and not remote_player_dictionary.has(peer_id):
			print("Adding missing remote player: " + str(peer_id))
			_add_remote_player_character(peer_id)

# Note: Removed _notify_player_pattern_selection - no longer needed since respawn timer is properly managed via _sync_health


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
