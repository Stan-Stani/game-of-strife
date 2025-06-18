extends Node3D

var Cell3D = load("res://Cell3D.tscn")
var PlayerCharacterScene = load("res://addons/PlayerCharacter/PlayerCharacterScene.tscn")


func _ready():
	# Store the pattern immediately when scene loads (before multiplayer overwrites it)
	GameState.store_pattern_on_load()
	
	for cellPos in GameState.colony:
				if GameState.colony[cellPos] == true:
					var cell_3d = Cell3D.instantiate()
					var position_3d = Vector3(cellPos.x, -cellPos.y, 0)
					cell_3d.position = position_3d
					add_child(cell_3d)
	
	# Connect to GameState signals
	GameState.peer_connected.connect(_on_peer_connected)
	GameState.peer_disconnected.connect(_on_peer_disconnected)
	GameState.connected_to_server.connect(_on_connected_to_server)
	GameState.connection_failed.connect(_on_connection_failed)
	GameState.server_disconnected.connect(_on_server_disconnected)
	GameState.player_pattern_received.connect(_on_player_pattern_received)
	GameState.add_remote_player.connect(_add_remote_player_character)

	# Restore multiplayer connection if it exists
	if GameState.restore_multiplayer_peer():
		# We're returning from pattern selection, restore multiplayer state
		_restore_multiplayer_state()
	
	# Don't spawn local player here - wait for multiplayer connection
	
	# Auto-connect for development
	# _check_dev_auto_connect()
	
	
var HealthUI = preload("res://HealthUI.tscn")
var health_ui_instance = null
func _process(_delta: float) -> void:
	# Handle pattern selection mode inputs (but don't return early)
	if pattern_selection_overlay != null:
		if Input.is_action_just_pressed("ragdoll"):  # 'R' key
			# Transition to 2D pattern editor
			GameState.colony = GameState.get_player_pattern(multiplayer.get_unique_id())
			get_tree().change_scene_to_file("res://Main.tscn")
		elif Input.is_action_just_pressed("ui_accept"):  # Enter key
			# Respawn immediately with current pattern (no changes needed)
			var local_player = get_local_player()
			if local_player and local_player.has_method("_request_respawn"):
				local_player._request_respawn.rpc(true)
				_hide_pattern_selection_overlay()
	
	if Input.is_action_just_pressed("be_server"):
		var error = GameState.create_server()
		if error == OK:
			DisplayServer.window_set_title("Host")
			# Configure existing player for multiplayer
			_configure_local_player()
			# Create health UI for local player
			_create_health_ui()
		
	if Input.is_action_just_pressed("be_client"):
		_show_server_selection_ui()

var remote_player_dictionary: Dictionary = {}

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
	# GameState already handles most of the logic, we just ensure visual updates
	print("[Game3D] Handling peer connected: " + str(peer_id))
	

func _on_peer_disconnected(peer_id: int):
	print("[Game3D] Handling peer disconnected: " + str(peer_id))
	if remote_player_dictionary.has(peer_id):
		remote_player_dictionary[peer_id].queue_free()
		remote_player_dictionary.erase(peer_id)

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
	print("[Game3D] Connected to server")
	_configure_local_player()
	
	# Create health UI for client
	_create_health_ui()
	
	# Notify server list of successful connection
	if GameState.multiplayer_peer and GameState.multiplayer_peer.has_meta("connecting_ip") and server_ui_instance:
		server_ui_instance.server_connection_succeeded(GameState.multiplayer_peer.get_meta("connecting_ip"))

func _on_connection_failed():
	print("[Game3D] Connection to server failed")
	
	# Notify server list of failed connection
	if GameState.multiplayer_peer and GameState.multiplayer_peer.has_meta("connecting_ip") and server_ui_instance:
		server_ui_instance.server_connection_failed(GameState.multiplayer_peer.get_meta("connecting_ip"))

func _on_server_disconnected():
	print("[Game3D] Disconnected from server")
	# Could add logic here to mark server as unreliable

func _on_player_pattern_received(peer_id: int, pattern_data: Dictionary):
	# Update the visual model for this peer if they have a player character
	_update_player_pattern_model(peer_id)

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

func get_player_pattern(peer_id: int) -> Dictionary:
	return GameState.get_player_pattern(peer_id)

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
	return GameState.get_local_ip()

func _test_server_at_ip(ip_address: String) -> bool:
	# Check for cancellation before starting the connection test
	if server_ui_instance != null and server_ui_instance.is_scan_cancelled():
		return false
	
	# Use GameState's test function
	var result = await GameState.test_server_at_ip(ip_address)
	
	# Check for cancellation after the test
	if server_ui_instance != null and server_ui_instance.is_scan_cancelled():
		return false
	
	return result

func _connect_to_server(ip_address: String):
	var error = GameState.create_client(ip_address)
	if error == OK:
		print("Connecting to " + ip_address)
		DisplayServer.window_set_title("Client")
		
		# Store IP for success/failure callbacks
		if GameState.multiplayer_peer:
			GameState.multiplayer_peer.set_meta("connecting_ip", ip_address)
	else:
		print("Failed to connect: " + error_string(error))

# Development functions removed - can be re-added if needed

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
	# Update the player's pattern in GameState
	var local_peer_id = multiplayer.get_unique_id()
	GameState.player_patterns[local_peer_id] = GameState.colony.duplicate()
	
	# Sync the new pattern with other players
	if multiplayer.is_server():
		for client_id in multiplayer.get_peers():
			GameState._sync_player_pattern.rpc_id(client_id, local_peer_id, GameState.player_patterns[local_peer_id])
	else:
		GameState._sync_player_pattern.rpc_id(1, local_peer_id, GameState.player_patterns[local_peer_id])
	
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
	
	# Set window title based on host/client status
	if GameState.is_host:
		DisplayServer.window_set_title("Host")
	else:
		DisplayServer.window_set_title("Client")
	
	# Configure local player
	_configure_local_player()
	
	# Check if the player should still be in pattern selection mode
	var local_player = get_local_player()
	var was_in_pattern_selection = false
	if local_player and local_player.has_meta("in_pattern_selection"):
		was_in_pattern_selection = local_player.get_meta("in_pattern_selection")
	
	# GameState handles pattern storage
	
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
	var local_pattern = GameState.get_player_pattern(local_peer_id)
	if local_pattern.size() > 0:
		print("DEBUG: Syncing updated pattern to other players. Pattern size: " + str(local_pattern.size()))
		# Sync new pattern to all other players
		if GameState.is_host:
			for client_id in multiplayer.get_peers():
				GameState._sync_player_pattern.rpc_id(client_id, local_peer_id, local_pattern)
		else:
			GameState._sync_player_pattern.rpc_id(1, local_peer_id, local_pattern)
	
	# Request all patterns from other players and notify we're back
	if GameState.is_host:
		# If we're the host, tell other players we're back
		GameState._notify_player_returned.rpc()
	else:
		# If we're a client, request current game state from server
		GameState._request_current_game_state.rpc_id(1)
	
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

# RPC functions have been moved to GameState

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
