extends Node3D

var Cell3D = load("res://Cell3D.tscn")
var PlayerCharacterScene = load("res://addons/PlayerCharacter/PlayerCharacterScene.tscn")


func _ready():
	# Store the pattern immediately when scene loads (before multiplayer overwrites it)
	GameState.store_pattern_on_load()
	
	# Skip spawning world decoration blocks to avoid visual clutter
	# for cellPos in GameState.colony:
	#			if GameState.colony[cellPos] == true:
	#				var cell_3d = Cell3D.instantiate()
	#				var position_3d = Vector3(cellPos.x, -cellPos.y, 0)
	#				cell_3d.position = position_3d
	#				add_child(cell_3d)
	
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
	
	# Handle command line auto-connections
	_check_command_line_actions()
	
	# Start listening for Claude Code movement commands
	_start_claude_command_listener()
	
	# Create mouse capture toggle button
	_create_mouse_capture_button()
	
	
var HealthUI = preload("res://HealthUI.tscn")
var health_ui_instance = null

# Mouse capture toggle button
var mouse_capture_button: Button = null

# Placeholder menu
var placeholder_menu: Control = null

# Spectate mode
var spectate_mode: bool = false
var spectate_camera: Camera3D = null
var spectate_speed: float = 10.0
func _process(_delta: float) -> void:
	# Handle spectate mode movement
	if spectate_mode and spectate_camera:
		_handle_spectate_movement(_delta)
	
	# Update mouse capture button visibility
	_update_mouse_capture_button()
	
	# Check claude commands
	_check_claude_commands()
	
	# Maintain simulated inputs
	for key in simulated_inputs:
		if simulated_inputs[key]:
			var parts = key.split("_")
			if parts.size() >= 3:
				var action = parts[2]
				# For actions that need more parts
				for i in range(3, parts.size()):
					action += "_" + parts[i]
				
				# Keep the action pressed
				if not Input.is_action_pressed(action):
					Input.action_press(action)
	
	# Handle pattern selection mode inputs (but don't return early)
	if pattern_selection_overlay != null:
		if Input.is_action_just_pressed("ragdoll"):  # 'R' key
			# Mark player as entering actual pattern editing
			var local_player = get_local_player()
			if local_player:
				local_player.set_meta("in_death_menu", false)
				local_player.set_meta("in_pattern_selection", true)
			
			# Transition to 2D pattern editor
			GameState.colony = GameState.get_player_pattern(multiplayer.get_unique_id())
			get_tree().change_scene_to_file("res://Main.tscn")
		elif Input.is_action_just_pressed("ui_accept"):  # Enter key
			# Respawn immediately with current pattern (no changes needed)
			var local_player = get_local_player()
			if local_player and local_player.has_method("_request_respawn"):
				# Clear death menu flag since we're respawning
				local_player.set_meta("in_death_menu", false)
				local_player.set_meta("in_pattern_selection", false)
				local_player._request_respawn.rpc(true)
				_hide_pattern_selection_overlay()
	
	# Check for Claude Code commands every 0.1 seconds
	if Time.get_unix_time_from_system() - claude_last_command_time > 0.1:
		claude_last_command_time = Time.get_unix_time_from_system()
		_check_claude_commands()
	
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
	
	# Toggle spectate mode with 'T' key
	if Input.is_physical_key_pressed(KEY_T):
		if not get_meta("t_key_pressed", false):
			set_meta("t_key_pressed", true)
			_toggle_spectate_mode()
	else:
		set_meta("t_key_pressed", false)
	
	# Handle escape key
	if Input.is_action_just_pressed("ui_cancel"):
		if placeholder_menu != null and placeholder_menu.visible:
			# Close placeholder menu
			_hide_placeholder_menu()
		else:
			# Open placeholder menu and uncapture mouse (if no other UI is open)
			if server_ui_instance == null and pattern_selection_overlay == null:
				# Uncapture mouse if captured
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				_show_placeholder_menu()

var remote_player_dictionary: Dictionary = {}

# Spawn point management
var spawn_radius: float = 10.0  # Distance from center for spawn points
var next_spawn_index: int = 0   # Track which spawn point to use next

func get_spawn_position(player_index: int) -> Vector3:
	# Distribute players in a circle around the origin
	# This ensures players don't spawn on top of each other
	var angle = (player_index * TAU) / 8.0  # Support up to 8 players evenly distributed
	var x = sin(angle) * spawn_radius
	var z = cos(angle) * spawn_radius
	return Vector3(x, 0, z)

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
	
	# Set spawn position for remote player
	next_spawn_index += 1
	new_player_character.position = get_spawn_position(next_spawn_index)
	
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
		
		# Set spawn position for local player
		# Host gets position 0, clients get subsequent positions
		if multiplayer.is_server():
			local_player.position = get_spawn_position(0)
		else:
			# For clients, use their unique ID to determine spawn position
			# This gives a somewhat deterministic but distributed spawn
			var spawn_slot = multiplayer.get_unique_id() % 8
			local_player.position = get_spawn_position(spawn_slot)
		
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
	
	# Check the player's state when returning from pattern editing
	var local_player = get_local_player()
	var was_in_death_menu = false
	var was_in_pattern_selection = false
	
	if local_player:
		if local_player.has_meta("in_death_menu"):
			was_in_death_menu = local_player.get_meta("in_death_menu")
		if local_player.has_meta("in_pattern_selection"):
			was_in_pattern_selection = local_player.get_meta("in_pattern_selection")
	
	# GameState handles pattern storage
	
	# Handle different return states
	if was_in_pattern_selection and local_player:
		# Player is returning from actual pattern editing - auto-respawn with new pattern
		print("Player returned from pattern editing - auto-respawning...")
		local_player.set_meta("in_death_menu", false)
		local_player.set_meta("in_pattern_selection", false)
		if local_player.has_method("_exit_pattern_selection"):
			local_player._exit_pattern_selection()
	elif was_in_death_menu and local_player:
		# Player was in death menu - restore death menu state
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

# === CLAUDE CODE PLAYER CONTROL API ===

func claude_get_local_player():
	"""Get reference to the local player character"""
	return get_local_player()

func claude_get_all_players() -> Array:
	"""Get references to all player characters (local and remote)"""
	var players = []
	
	# Add local player
	var local_player = get_local_player()
	if local_player:
		players.append(local_player)
	
	# Add remote players
	for peer_id in remote_player_dictionary:
		if remote_player_dictionary[peer_id]:
			players.append(remote_player_dictionary[peer_id])
	
	return players

func claude_move_player_to(target: Vector3, player_index: int = 0):
	"""Move a player to specific position (0 = local player, 1+ = remote players)"""
	var players = claude_get_all_players()
	if player_index < players.size():
		var player = players[player_index]
		if player.has_method("claude_move_to"):
			player.claude_move_to(target)
			print("Claude moving player " + str(player_index) + " to " + str(target))
		else:
			print("Player doesn't support Claude movement API")
	else:
		print("Player index " + str(player_index) + " not found. Available players: " + str(players.size()))

func claude_teleport_player_to(target: Vector3, player_index: int = 0):
	"""Teleport a player to specific position"""
	var players = claude_get_all_players()
	if player_index < players.size():
		var player = players[player_index]
		if player.has_method("claude_teleport_to"):
			player.claude_teleport_to(target)
			print("Claude teleported player " + str(player_index) + " to " + str(target))

func claude_get_player_status(player_index: int = 0) -> Dictionary:
	"""Get comprehensive status of a player"""
	var players = claude_get_all_players()
	if player_index < players.size():
		var player = players[player_index]
		if player.has_method("claude_get_status"):
			return player.claude_get_status()
		else:
			return {"error": "Player doesn't support status API"}
	else:
		return {"error": "Player index not found", "available_players": players.size()}

func claude_enable_player_debug_movement(enabled: bool = true, player_index: int = 0):
	"""Enable debug movement controls for a player"""
	var players = claude_get_all_players()
	if player_index < players.size():
		var player = players[player_index]
		if player.has_method("claude_enable_debug_movement"):
			player.claude_enable_debug_movement(enabled)

func claude_list_players():
	"""Print info about all available players"""
	var players = claude_get_all_players()
	print("=== Available Players ===")
	for i in range(players.size()):
		var player = players[i]
		var is_local = (player == get_local_player())
		var pos = player.position if player else Vector3.ZERO
		var health = player.current_health if player and "current_health" in player else "unknown"
		print("Player " + str(i) + ": " + ("LOCAL" if is_local else "REMOTE") + " at " + str(pos) + " (Health: " + str(health) + ")")

func claude_test_movement():
	"""Run a simple movement test with the local player"""
	var local_player = claude_get_local_player()
	if local_player:
		print("Starting Claude movement test...")
		
		# Enable debug movement
		claude_enable_player_debug_movement(true, 0)
		
		# Get starting position
		var start_pos = local_player.claude_get_position()
		print("Starting position: " + str(start_pos))
		
		# Move to a few different positions
		await get_tree().create_timer(1.0).timeout
		claude_move_player_to(start_pos + Vector3(5, 0, 0), 0)
		
		await get_tree().create_timer(3.0).timeout
		claude_move_player_to(start_pos + Vector3(0, 0, 5), 0)
		
		await get_tree().create_timer(3.0).timeout
		claude_teleport_player_to(start_pos, 0)
		
		print("Claude movement test completed!")
	else:
		print("No local player found for movement test")

func claude_aim_at_player(target_player_index: int, aiming_player_index: int = 0):
	"""Aim at another player by rotating the camera"""
	var players = claude_get_all_players()
	
	if aiming_player_index >= players.size():
		print("Aiming player index " + str(aiming_player_index) + " not found")
		return false
	
	if target_player_index >= players.size():
		print("Target player index " + str(target_player_index) + " not found")
		return false
	
	if aiming_player_index == target_player_index:
		print("Cannot aim at yourself")
		return false
	
	var aiming_player = players[aiming_player_index]
	var target_player = players[target_player_index]
	
	# Only work with local player for now (remote player camera control is complex)
	if aiming_player_index != 0:
		print("Can only aim with local player (player 0)")
		return false
	
	# Get positions
	var aiming_pos = aiming_player.position
	var target_pos = target_player.position
	
	# Calculate direction vector
	var direction = (target_pos - aiming_pos).normalized()
	
	# Calculate angles for aiming
	# In Godot, Y rotation of 0 points forward (-Z), so we calculate angle to look toward target
	# Add PI to flip the direction so we actually face the target
	var horizontal_angle = atan2(direction.x, direction.z) + PI
	var distance_2d = Vector2(direction.x, direction.z).length()
	var vertical_angle = atan2(direction.y, distance_2d)
	
	# Get camera system
	var camera_system = aiming_player.get_node("OrbitView")
	if camera_system:
		# Store current rotation for debugging
		var old_rotation = camera_system.rotation
		
		# Rotate camera to look at target
		camera_system.rotation.y = horizontal_angle
		camera_system.rotation.x = -vertical_angle  # Negative because camera X rotation is inverted
		
		print("Aiming player " + str(aiming_player_index) + " at player " + str(target_player_index))
		print("Target position: " + str(target_pos))
		print("Aiming angles: horizontal=" + str(rad_to_deg(horizontal_angle)) + "°, vertical=" + str(rad_to_deg(vertical_angle)) + "°")
		print("Camera rotation changed from " + str(old_rotation) + " to " + str(camera_system.rotation))
		return true
	else:
		print("Camera system not found for player " + str(aiming_player_index))
		return false

func claude_shoot_at_player(target_player_index: int, shooting_player_index: int = 0):
	"""Aim at a player and shoot"""
	var players = claude_get_all_players()
	
	if shooting_player_index >= players.size():
		print("Shooting player index " + str(shooting_player_index) + " not found")
		return false
	
	if target_player_index >= players.size():
		print("Target player index " + str(target_player_index) + " not found")
		return false
	
	if shooting_player_index == target_player_index:
		print("Cannot shoot at yourself")
		return false
	
	# First aim at the target
	if not claude_aim_at_player(target_player_index, shooting_player_index):
		print("Failed to aim at target")
		return false
	
	# Wait a moment for aiming to stabilize
	await get_tree().create_timer(0.2).timeout
	
	# Simulate shoot action
	_simulate_player_input("shoot", true, shooting_player_index)
	await get_tree().create_timer(0.1).timeout
	_simulate_player_input("shoot", false, shooting_player_index)
	
	print("Player " + str(shooting_player_index) + " shot at player " + str(target_player_index))
	return true

func claude_get_nearest_enemy_player(player_index: int = 0) -> int:
	"""Find the nearest enemy player to the given player"""
	var players = claude_get_all_players()
	
	if player_index >= players.size():
		print("Player index " + str(player_index) + " not found")
		return -1
	
	var base_player = players[player_index]
	var base_pos = base_player.position
	var nearest_index = -1
	var nearest_distance = INF
	
	for i in range(players.size()):
		if i == player_index:
			continue  # Skip self
		
		var other_player = players[i]
		var distance = base_pos.distance_to(other_player.position)
		
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = i
	
	if nearest_index != -1:
		print("Nearest enemy to player " + str(player_index) + " is player " + str(nearest_index) + " at distance " + str(nearest_distance))
	else:
		print("No enemy players found for player " + str(player_index))
	
	return nearest_index

func claude_get_camera_direction(player_index: int = 0):
	"""Get the current camera direction and rotation for a player"""
	var players = claude_get_all_players()
	
	if player_index >= players.size():
		print("Player index " + str(player_index) + " not found")
		return
	
	var player = players[player_index]
	var camera_system = player.get_node("OrbitView")
	
	if camera_system:
		var rotation = camera_system.rotation
		var camera = camera_system.get_node("Camera3D")
		
		if camera:
			var forward = -camera.global_transform.basis.z  # Forward direction in world space
			var right = camera.global_transform.basis.x     # Right direction
			var up = camera.global_transform.basis.y        # Up direction
			
			print("Player " + str(player_index) + " camera info:")
			print("  Position: " + str(player.position))
			print("  Camera rotation: " + str(rotation) + " (degrees: " + str(Vector3(rad_to_deg(rotation.x), rad_to_deg(rotation.y), rad_to_deg(rotation.z))) + ")")
			print("  Forward direction: " + str(forward))
			print("  Right direction: " + str(right))
			print("  Up direction: " + str(up))
		else:
			print("Camera3D not found for player " + str(player_index))
	else:
		print("Camera system not found for player " + str(player_index))

# === INPUT SIMULATION FUNCTIONS ===

var simulated_inputs = {}  # Track which inputs are being simulated per player

func _simulate_player_input(action: String, pressed: bool, player_index: int = 0):
	"""Simulate input for a specific player"""
	var players = claude_get_all_players()
	if player_index >= players.size():
		print("Player index " + str(player_index) + " not found")
		return
	
	var player = players[player_index]
	if player_index == 0 and not player.is_remote:
		# For local player, we need to simulate actual input events
		var key = "player_" + str(player_index) + "_" + action
		
		if pressed:
			simulated_inputs[key] = true
			# Immediately trigger the action
			Input.action_press(action)
		else:
			simulated_inputs.erase(key)
			Input.action_release(action)
		
		# Get player position before and after
		var pos_before = player.claude_get_position() if player.has_method("claude_get_position") else player.position
		print("Simulating input '" + action + "' = " + str(pressed) + " for player " + str(player_index) + " at position " + str(pos_before))
	else:
		print("Cannot simulate input for remote players")

func _simulate_walk(direction: String, duration: float, player_index: int = 0):
	"""Simulate walking in a direction for a duration"""
	var action = ""
	match direction:
		"forward": action = "move_forward"
		"back", "backward": action = "move_backward"
		"left": action = "move_left"
		"right": action = "move_right"
		_:
			print("Invalid direction: " + direction)
			return
	
	_simulate_player_input(action, true, player_index)
	
	# Stop after duration
	get_tree().create_timer(duration).timeout.connect(func():
		_simulate_player_input(action, false, player_index)
	)

func _simulate_run(direction: String, duration: float, player_index: int = 0):
	"""Simulate running in a direction for a duration"""
	# First press run action
	_simulate_player_input("run", true, player_index)
	
	# Then walk in direction
	_simulate_walk(direction, duration, player_index)
	
	# Release run after duration
	get_tree().create_timer(duration).timeout.connect(func():
		_simulate_player_input("run", false, player_index)
	)

# (Removed duplicate _process - merged into main _process above)

# === CLAUDE CODE COMMAND LISTENER ===

var claude_command_file_paths = [
	"claude_commands.txt",       # Default/shared commands
	"claude_commands_host.txt",  # Host-specific commands
	"claude_commands_client.txt", # Client-specific commands
	"claude_commands_1.txt",     # Player 1 specific
	"claude_commands_2.txt",     # Player 2 specific
	"claude_commands_3.txt",     # Player 3 specific
	"claude_commands_4.txt"      # Player 4 specific
]
var claude_last_command_time = 0.0
var processed_commands = {}  # Track processed commands per file

func _start_claude_command_listener():
	# Determine which command files this instance should watch
	var files_to_watch = ["claude_commands.txt"]  # Always watch the default
	
	# Add role-specific file
	if multiplayer.is_server():
		files_to_watch.append("claude_commands_host.txt")
	else:
		files_to_watch.append("claude_commands_client.txt")
	
	# Add player ID specific file (peer ID based)
	var peer_id = multiplayer.get_unique_id()
	if peer_id <= 4:  # Support up to 4 players
		files_to_watch.append("claude_commands_" + str(peer_id) + ".txt")
	
	print("Claude Code command listener started - watching: " + str(files_to_watch))


func _check_claude_commands():
	# Get list of files to check based on instance role
	var files_to_check = _get_command_files_to_watch()
	
	for file_path in files_to_check:
		# Check if command file exists and read it
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file == null:
			continue
		
		var content = file.get_as_text().strip_edges()
		var file_mod_time = file.get_modified_time(file_path)
		file.close()
		
		if content.length() == 0:
			continue
		
		# Check if we've already processed this command
		var command_key = file_path + ":" + content + ":" + str(file_mod_time)
		if processed_commands.has(command_key):
			continue
		
		# Mark as processed
		processed_commands[command_key] = Time.get_unix_time_from_system()
		
		# Clear the file after reading
		var clear_file = FileAccess.open(file_path, FileAccess.WRITE)
		if clear_file:
			clear_file.store_string("")
			clear_file.close()
		
		# Parse and execute the command
		print("Processing command from " + file_path + ": " + content)
		_execute_claude_command(content, file_path)

func _get_command_files_to_watch() -> Array:
	var files = ["claude_commands.txt"]  # Always watch default
	
	# Add role-specific file based on current multiplayer state
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		files.append("claude_commands_host.txt")
	elif multiplayer.has_multiplayer_peer():
		files.append("claude_commands_client.txt")
	
	# Add peer ID specific file
	if multiplayer.has_multiplayer_peer():
		var peer_id = multiplayer.get_unique_id()
		files.append("claude_commands_" + str(peer_id) + ".txt")
	
	return files

func _execute_claude_command(command: String, source_file: String = ""):
	print("Executing Claude command: " + command + ((" from " + source_file) if source_file != "" else ""))
	
	var parts = command.split(" ")
	if parts.size() == 0:
		return
	
	var cmd = parts[0].to_lower()
	
	match cmd:
		"teleport", "tp":
			if parts.size() >= 4:
				var x = parts[1].to_float()
				var y = parts[2].to_float()
				var z = parts[3].to_float()
				var player_index = parts[4].to_int() if parts.size() > 4 else 0
				claude_teleport_player_to(Vector3(x, y, z), player_index)
			else:
				print("Usage: teleport x y z [player_index]")
		
		
		"enable_numpad_movement":
			var player_index = parts[1].to_int() if parts.size() > 1 else 0
			claude_enable_player_debug_movement(true, player_index)
		
		"disable_numpad_movement":
			var player_index = parts[1].to_int() if parts.size() > 1 else 0
			claude_enable_player_debug_movement(false, player_index)
		
		"simulate_input":
			if parts.size() >= 3:
				var action = parts[1]
				var pressed = parts[2].to_lower() == "true" or parts[2] == "1"
				var player_index = parts[3].to_int() if parts.size() > 3 else 0
				_simulate_player_input(action, pressed, player_index)
			else:
				print("Usage: simulate_input action true/false [player_index]")
		
		"walk":
			if parts.size() >= 2:
				var direction = parts[1].to_lower()
				var duration = parts[2].to_float() if parts.size() > 2 else 1.0
				var player_index = parts[3].to_int() if parts.size() > 3 else 0
				_simulate_walk(direction, duration, player_index)
				# Check position after a short delay
				get_tree().create_timer(0.5).timeout.connect(func():
					var player = claude_get_all_players()[player_index] if player_index < claude_get_all_players().size() else null
					if player and player.has_method("claude_get_position"):
						print("Player position after walk: " + str(player.claude_get_position()))
				)
			else:
				print("Usage: walk forward/back/left/right [duration] [player_index]")
		
		"run":
			if parts.size() >= 2:
				var direction = parts[1].to_lower()
				var duration = parts[2].to_float() if parts.size() > 2 else 1.0
				var player_index = parts[3].to_int() if parts.size() > 3 else 0
				_simulate_run(direction, duration, player_index)
			else:
				print("Usage: run forward/back/left/right [duration] [player_index]")
		
		"jump":
			var player_index = parts[1].to_int() if parts.size() > 1 else 0
			_simulate_player_input("jump", true, player_index)
			await get_tree().create_timer(0.1).timeout
			_simulate_player_input("jump", false, player_index)
		
		"status", "pos":
			var player_index = parts[1].to_int() if parts.size() > 1 else 0
			var status = claude_get_player_status(player_index)
			print("Player " + str(player_index) + " status: " + str(status))
		
		"list":
			claude_list_players()
		
		"speed":
			if parts.size() >= 2:
				var speed = parts[1].to_float()
				var player_index = parts[2].to_int() if parts.size() > 2 else 0
				var player = claude_get_all_players()[player_index] if player_index < claude_get_all_players().size() else null
				if player:
					player.claude_set_move_speed(speed)
			else:
				print("Usage: speed value [player_index]")
		
		"test":
			claude_test_movement()
		
		"aim", "aim_at":
			if parts.size() >= 2:
				var target_player = parts[1].to_int()
				var aiming_player = parts[2].to_int() if parts.size() > 2 else 0
				claude_aim_at_player(target_player, aiming_player)
			else:
				print("Usage: aim target_player [aiming_player]")
		
		"shoot", "shoot_at":
			if parts.size() >= 2:
				var target_player = parts[1].to_int()
				var shooting_player = parts[2].to_int() if parts.size() > 2 else 0
				claude_shoot_at_player(target_player, shooting_player)
			else:
				print("Usage: shoot target_player [shooting_player]")
		
		"nearest", "nearest_enemy":
			var player_index = parts[1].to_int() if parts.size() > 1 else 0
			var nearest = claude_get_nearest_enemy_player(player_index)
			if nearest != -1:
				print("Nearest enemy to player " + str(player_index) + " is player " + str(nearest))
			else:
				print("No enemies found for player " + str(player_index))
		
		"shoot_nearest":
			var shooting_player = parts[1].to_int() if parts.size() > 1 else 0
			var nearest = claude_get_nearest_enemy_player(shooting_player)
			if nearest != -1:
				claude_shoot_at_player(nearest, shooting_player)
			else:
				print("No enemies found to shoot at for player " + str(shooting_player))
		
		"look_dir", "camera_dir", "rotation":
			var player_index = parts[1].to_int() if parts.size() > 1 else 0
			claude_get_camera_direction(player_index)
		
		"help":
			print("Claude Code movement commands:")
			print("=== Emergency Position Control ===")
			print("  teleport x y z [player] - Teleport to position")
			print("=== Character Control (State Machine) ===")
			print("  walk forward/back/left/right [duration] [player] - Walk with animation")
			print("  run forward/back/left/right [duration] [player] - Run with animation")
			print("  jump [player] - Make character jump")
			print("  simulate_input action true/false [player] - Simulate input action")
			print("  enable_numpad_movement [player] - Enable numpad controls")
			print("  disable_numpad_movement [player] - Disable numpad controls")
			print("=== Combat Commands ===")
			print("  aim target_player [aiming_player] - Aim at another player")
			print("  shoot target_player [shooting_player] - Aim and shoot at another player")
			print("  nearest [player] - Find nearest enemy player")
			print("  shoot_nearest [player] - Shoot at nearest enemy")
			print("=== Info Commands ===")
			print("  status/pos [player] - Show player status")
			print("  list - List all players")
			print("  speed value [player] - Set movement speed")
			print("  test - Run movement test")
			print("  help - Show this help")
		
		_:
			print("Unknown command: " + cmd + " (type 'help' for commands)")


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

# Handle command line actions
func _check_command_line_actions():
	# Check for auto-start server from command line
	if GameState.has_meta("auto_start_server"):
		print("Auto-starting server from command line...")
		call_deferred("_auto_start_server_now")
		GameState.remove_meta("auto_start_server")
	
	# Check for auto-connect IP from command line
	elif GameState.has_meta("auto_connect_ip"):
		var ip = GameState.get_meta("auto_connect_ip")
		print("Auto-connecting to: " + ip)
		call_deferred("_connect_to_server", ip)
		GameState.remove_meta("auto_connect_ip")
	
	# Check for local multiplayer test
	elif GameState.has_meta("test_local_multiplayer"):
		print("Starting local multiplayer test...")
		call_deferred("_start_local_multiplayer_test")
		GameState.remove_meta("test_local_multiplayer")
	
	# Check for spectate mode
	if GameState.has_meta("spectate_mode"):
		print("Starting in spectate mode...")
		call_deferred("_enable_spectate_mode")
		GameState.remove_meta("spectate_mode")
	
	# Check for debug logging
	if GameState.has_meta("debug_multiplayer"):
		print("Debug multiplayer logging enabled")
		# Could add more verbose logging here

func _auto_start_server_now():
	# Actually start the server (same as pressing 'I')
	var error = GameState.create_server()
	if error == OK:
		DisplayServer.window_set_title("Host")
		# Configure existing player for multiplayer
		_configure_local_player()
		# Create health UI for local player
		_create_health_ui()
		print("Server started successfully via command line")
	else:
		print("Failed to start server via command line: " + error_string(error))

# Start local multiplayer test (both server and client)
func _start_local_multiplayer_test():
	print("Creating server for local test...")
	var error = GameState.create_server()
	if error == OK:
		DisplayServer.window_set_title("Host (Test Mode)")
		_configure_local_player()
		_create_health_ui()
		
		# Wait a moment then test connection to ourselves
		await get_tree().create_timer(1.0).timeout
		print("Testing connection to local server...")
		var connection_test = await GameState.test_server_at_ip("127.0.0.1", 2.0)
		print("Local server test result: " + ("✅ Success" if connection_test else "❌ Failed"))
		
		# Could automatically spawn a second client instance here for full testing
		print("Local multiplayer test complete. Use 'O' on another instance to connect.")
	else:
		print("Failed to start local multiplayer test: " + error_string(error))

# Mouse capture button management
func _create_mouse_capture_button():
	if mouse_capture_button != null:
		return
	
	# Create button
	mouse_capture_button = Button.new()
	mouse_capture_button.text = "Click to Capture Mouse"
	mouse_capture_button.size = Vector2(200, 40)
	
	# Position in bottom right
	mouse_capture_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	mouse_capture_button.position = Vector2(-220, -60)  # Offset from bottom right
	
	# Style the button
	mouse_capture_button.add_theme_font_size_override("font_size", 14)
	
	# Connect button signal
	mouse_capture_button.pressed.connect(_on_mouse_capture_button_pressed)
	
	# Add to scene
	add_child(mouse_capture_button)
	
	# Initially hidden - will be shown by _update_mouse_capture_button()
	mouse_capture_button.visible = false

func _update_mouse_capture_button():
	if mouse_capture_button == null:
		return
	
	# Show button only when mouse is not captured and no UI is open
	var should_show = (Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and 
					   server_ui_instance == null and 
					   pattern_selection_overlay == null and
					   (placeholder_menu == null or not placeholder_menu.visible))
	
	mouse_capture_button.visible = should_show

func _on_mouse_capture_button_pressed():
	# Capture the mouse when button is clicked
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# Placeholder menu management
func _show_placeholder_menu():
	if placeholder_menu != null:
		return
	
	# Create menu background
	placeholder_menu = Control.new()
	placeholder_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(placeholder_menu)
	
	# Semi-transparent background
	var background = ColorRect.new()
	background.color = Color(0, 0, 0, 0.7)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	placeholder_menu.add_child(background)
	
	# Menu panel
	var panel = Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.size = Vector2(400, 300)
	panel.position = Vector2(-200, -150)  # Center it
	placeholder_menu.add_child(panel)
	
	# Menu content
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "Game Menu"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)
	
	# Resume button (with mouse captured)
	var resume_btn = Button.new()
	resume_btn.text = "Resume Game"
	resume_btn.custom_minimum_size = Vector2(200, 40)
	resume_btn.pressed.connect(_resume_game_with_mouse_captured)
	vbox.add_child(resume_btn)
	
	# Resume with mouse unlocked button
	var resume_unlocked_btn = Button.new()
	resume_unlocked_btn.text = "Resume with Mouse Unlocked"
	resume_unlocked_btn.custom_minimum_size = Vector2(200, 40)
	resume_unlocked_btn.pressed.connect(_resume_game_with_mouse_unlocked)
	vbox.add_child(resume_unlocked_btn)
	
	# Spectate mode toggle
	var spectate_btn = Button.new()
	spectate_btn.text = "Toggle Spectate Mode (T)"
	spectate_btn.custom_minimum_size = Vector2(200, 40)
	spectate_btn.pressed.connect(_toggle_spectate_from_menu)
	vbox.add_child(spectate_btn)
	
	# Settings button (placeholder)
	var settings_btn = Button.new()
	settings_btn.text = "Settings (Coming Soon)"
	settings_btn.custom_minimum_size = Vector2(200, 40)
	settings_btn.disabled = true
	vbox.add_child(settings_btn)
	
	# Exit button
	var exit_btn = Button.new()
	exit_btn.text = "Exit Game"
	exit_btn.custom_minimum_size = Vector2(200, 40)
	exit_btn.pressed.connect(_on_exit_game_pressed)
	vbox.add_child(exit_btn)
	
	# Make sure mouse is visible for menu interaction
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _hide_placeholder_menu():
	if placeholder_menu != null:
		placeholder_menu.queue_free()
		placeholder_menu = null

func _resume_game_with_mouse_captured():
	_hide_placeholder_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _resume_game_with_mouse_unlocked():
	_hide_placeholder_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _toggle_spectate_from_menu():
	_hide_placeholder_menu()
	_toggle_spectate_mode()

func _on_exit_game_pressed():
	get_tree().quit()

# Spectate mode functions
func _toggle_spectate_mode():
	if spectate_mode:
		_disable_spectate_mode()
	else:
		_enable_spectate_mode()

func _enable_spectate_mode():
	if spectate_mode:
		return
	
	print("Spectate mode enabled - Press T to toggle, WASD to fly, mouse to look")
	spectate_mode = true
	
	# Create spectate camera
	spectate_camera = Camera3D.new()
	spectate_camera.name = "SpectateCamera"
	add_child(spectate_camera)
	
	# Position camera at a good starting point
	spectate_camera.global_position = Vector3(0, 5, 10)
	spectate_camera.look_at(Vector3.ZERO, Vector3.UP)
	
	# Make it the current camera
	spectate_camera.current = true
	
	# Disable the player if we have one
	var player = get_local_player()
	if player:
		player.visible = false
		# Disable player processing and input
		player.process_mode = Node.PROCESS_MODE_DISABLED
	
	# Ensure mouse is captured for camera control
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _disable_spectate_mode():
	if not spectate_mode:
		return
	
	print("Spectate mode disabled")
	spectate_mode = false
	
	# Remove spectate camera
	if spectate_camera:
		spectate_camera.queue_free()
		spectate_camera = null
	
	# Re-enable and show the player again
	var player = get_local_player()
	if player:
		player.visible = true
		# Re-enable player processing and input
		player.process_mode = Node.PROCESS_MODE_INHERIT
		# Restore player's camera
		var player_camera = player.get_node_or_null("OrbitView/CameraContainer/Camera3D")
		if player_camera:
			player_camera.current = true

var spectate_mouse_sensitivity = 0.002

func _handle_spectate_movement(delta: float):
	if not spectate_camera:
		return
	
	# Handle mouse look
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# This will be handled in _unhandled_input for mouse events
		pass
	
	# Handle WASD movement
	var movement = Vector3.ZERO
	var transform = spectate_camera.global_transform
	
	if Input.is_action_pressed("move_forward"):
		movement -= transform.basis.z  # Forward is -Z
	if Input.is_action_pressed("move_backward"):
		movement += transform.basis.z  # Backward is +Z
	if Input.is_action_pressed("move_left"):
		movement -= transform.basis.x  # Left is -X
	if Input.is_action_pressed("move_right"):
		movement += transform.basis.x  # Right is +X
	
	# Vertical movement
	if Input.is_action_pressed("jump"):  # Space
		movement += transform.basis.y  # Up is +Y
	if Input.is_action_pressed("run"):  # Shift for down movement
		movement -= transform.basis.y  # Down is -Y
	
	# Apply movement
	if movement.length() > 0:
		movement = movement.normalized() * spectate_speed * delta
		spectate_camera.global_position += movement

func _unhandled_input(event: InputEvent):
	if spectate_mode and spectate_camera and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			# Rotate camera based on mouse movement
			var mouse_delta = event.relative * spectate_mouse_sensitivity
			
			# Horizontal rotation (Y-axis)
			spectate_camera.rotate_y(-mouse_delta.x)
			
			# Vertical rotation (local X-axis)
			var current_rotation = spectate_camera.rotation.x
			var new_rotation = current_rotation - mouse_delta.y
			# Clamp vertical rotation to prevent flipping
			new_rotation = clamp(new_rotation, -PI/2 + 0.1, PI/2 - 0.1)
			spectate_camera.rotation.x = new_rotation

