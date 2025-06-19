extends Node

var colony

# Network configuration (can be overridden by command line)
var PORT = 3006

# Multiplayer persistence across scenes
var multiplayer_peer: ENetMultiplayerPeer = null
var is_host: bool = false
var is_connected: bool = false

# Testing flags
var disable_mouse_capture: bool = false

# Player management
var remote_player_dictionary: Dictionary = {}
var player_patterns: Dictionary = {}
var local_player_ref: CharacterBody3D = null

# Scene references
var current_game_scene: Node3D = null

# Signals for game_3d to connect to
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connected_to_server()
signal connection_failed()
signal server_disconnected()
signal player_pattern_received(peer_id: int, pattern_data: Dictionary)
signal add_remote_player(peer_id: int)

func set_multiplayer_peer(peer: ENetMultiplayerPeer, host: bool = false):
	multiplayer_peer = peer
	is_host = host
	is_connected = true
	multiplayer.multiplayer_peer = peer
	print("GameState: Multiplayer peer set (host: " + str(host) + ")")

func get_multiplayer_peer() -> ENetMultiplayerPeer:
	return multiplayer_peer

func clear_multiplayer():
	if multiplayer_peer:
		multiplayer_peer.close()
	multiplayer_peer = null
	is_host = false
	is_connected = false
	multiplayer.multiplayer_peer = null
	print("GameState: Multiplayer cleared")

func restore_multiplayer_peer():
	if multiplayer_peer and is_connected:
		multiplayer.multiplayer_peer = multiplayer_peer
		print("GameState: Multiplayer peer restored")
		return true
	return false

# Server/Client creation
func create_server() -> int:
	if not multiplayer_peer:
		multiplayer_peer = ENetMultiplayerPeer.new()
	
	var error = multiplayer_peer.create_server(PORT)
	if error == OK:
		set_multiplayer_peer(multiplayer_peer, true)
		print("Server created on port " + str(PORT))
		_connect_multiplayer_signals()
	else:
		print("Failed to create server: " + error_string(error))
	
	return error

func create_client(ip_address: String) -> int:
	if not multiplayer_peer:
		multiplayer_peer = ENetMultiplayerPeer.new()
	
	var error = multiplayer_peer.create_client(ip_address, PORT)
	if error == OK:
		set_multiplayer_peer(multiplayer_peer, false)
		print("Connecting to server at " + ip_address + ":" + str(PORT))
		_connect_multiplayer_signals()
	else:
		print("Failed to create client: " + error_string(error))
	
	return error

func _connect_multiplayer_signals():
	if is_host:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	else:
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)

# Multiplayer callbacks
func _on_peer_connected(peer_id: int):
	print("Player connected: " + str(peer_id))
	peer_connected.emit(peer_id)
	
	# Tell everyone except the new peer to add the new peer as remote
	for existing_peer in multiplayer.get_peers():
		if existing_peer != peer_id:
			add_remote_player.emit(peer_id)
	
	# Tell the new peer to add the host as remote
	_notify_add_remote_player.rpc_id(peer_id, multiplayer.get_unique_id())
	
	# Add the new peer locally on the host
	if multiplayer.is_server():
		add_remote_player.emit(peer_id)
		
		# Send all existing patterns to the new peer
		_request_all_patterns.rpc_id(peer_id)

func _on_peer_disconnected(peer_id: int):
	print("Player disconnected: " + str(peer_id))
	peer_disconnected.emit(peer_id)
	
	# Clean up pattern data
	if player_patterns.has(peer_id):
		player_patterns.erase(peer_id)

func _on_connected_to_server():
	print("Connected to server")
	connected_to_server.emit()
	
	# Store local player's pattern and send to server
	_store_local_player_pattern()
	_send_pattern_to_server()
	
	# Request all existing patterns from server
	_request_all_patterns.rpc_id(1)

func _on_connection_failed():
	print("Connection to server failed")
	connection_failed.emit()
	
	# Clean up
	if multiplayer_peer:
		multiplayer_peer.close()

func _on_server_disconnected():
	print("Disconnected from server")
	server_disconnected.emit()

# Pattern management
func store_pattern_on_load():
	# Store the current pattern in a temporary key to preserve it before multiplayer
	var temp_key = "local_pattern"
	player_patterns[temp_key] = colony.duplicate()

func _store_local_player_pattern():
	var local_peer_id = multiplayer.get_unique_id()
	# Use the pattern that was stored on load
	var pattern_to_store = player_patterns.get("local_pattern", colony.duplicate())
	player_patterns[local_peer_id] = pattern_to_store
	
	# Clean up the temporary pattern
	if player_patterns.has("local_pattern"):
		player_patterns.erase("local_pattern")

func _send_pattern_to_server():
	var local_peer_id = multiplayer.get_unique_id()
	if player_patterns.has(local_peer_id):
		_sync_player_pattern.rpc_id(1, local_peer_id, player_patterns[local_peer_id])

func get_player_pattern(peer_id: int) -> Dictionary:
	if player_patterns.has(peer_id):
		return player_patterns[peer_id]
	else:
		# Fallback to current colony if no stored pattern
		return colony

# RPC functions
@rpc("any_peer", "call_remote")
func _notify_add_remote_player(peer_id: int):
	add_remote_player.emit(peer_id)

@rpc("any_peer", "call_remote")
func _sync_player_pattern(peer_id: int, pattern_data: Dictionary):
	player_patterns[peer_id] = pattern_data
	print("Received pattern from peer " + str(peer_id) + " with " + str(pattern_data.size()) + " cells")
	
	# Emit signal for game_3d to handle visual updates
	player_pattern_received.emit(peer_id, pattern_data)
	
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

@rpc("any_peer", "call_remote")
func _request_initial_position():
	# This will be handled by game_3d since it has access to the player nodes
	pass

@rpc("any_peer", "call_remote")
func _sync_initial_position(peer_id: int, position_data: Dictionary):
	# This will be handled by game_3d since it has access to the player nodes
	pass

@rpc("any_peer", "unreliable")
func receive_player_input(peer_id: int, input_data: Dictionary):
	# This will be handled by game_3d since it has access to the player nodes
	pass

@rpc("any_peer", "call_local")
func _notify_player_returned():
	# Called when a player returns from pattern selection
	var sender_id = multiplayer.get_remote_sender_id()
	print("Player " + str(sender_id) + " returned from pattern selection")
	# Emit signal for game_3d to handle
	add_remote_player.emit(sender_id)

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
	# Receive list of connected players and emit signal for game_3d to create remote players
	print("Received connected players list: " + str(connected_peers))
	
	for peer_id in connected_peers:
		if peer_id != multiplayer.get_unique_id():
			add_remote_player.emit(peer_id)

# Helper functions for network testing
func test_server_at_ip(ip_address: String, timeout: float = 0.2) -> bool:
	# Create a new peer for each test to avoid conflicts
	var test_peer = ENetMultiplayerPeer.new()
	
	# Try to create client connection
	var result = test_peer.create_client(ip_address, PORT)
	if result != OK:
		test_peer.close()
		return false
	
	# Use a shorter timeout but check more frequently for better responsiveness
	var start_time = Time.get_unix_time_from_system()
	
	# Simple polling loop with timeout
	while Time.get_unix_time_from_system() - start_time < timeout:
		# IMPORTANT: Poll the peer to process network events
		test_peer.poll()
		
		var status = test_peer.get_connection_status()
		
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			test_peer.close()
			return true
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			test_peer.close()
			return false
		
		await Engine.get_main_loop().create_timer(0.01).timeout
	
	# Cleanup and return false for timeout
	test_peer.close()
	return false

func get_local_ip() -> String:
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

# ===== MULTIPLAYER TESTING FUNCTIONS =====

# Test all network functionality
func test_all_network_functions():
	print("=== Starting Comprehensive Network Tests ===")
	
	# Test 1: IP discovery
	var local_ip = get_local_ip()
	print("Local IP: " + local_ip)
	if local_ip == "":
		print("❌ FAILED: Could not determine local IP")
	else:
		print("✅ PASSED: Local IP detected")
	
	# Test 2: Server creation
	var test_server_result = await test_server_creation()
	print("Server Creation Test: " + ("✅ PASSED" if test_server_result else "❌ FAILED"))
	
	# Test 3: Connection test to localhost
	var localhost_test = await test_server_at_ip("127.0.0.1", 0.5)
	print("Localhost Connection Test: " + ("✅ PASSED" if localhost_test else "❌ FAILED"))
	
	# Test 4: Pattern sync functionality
	var pattern_test = test_pattern_synchronization()
	print("Pattern Sync Test: " + ("✅ PASSED" if pattern_test else "❌ FAILED"))
	
	# Test 5: Network performance benchmark
	await benchmark_network_performance()
	
	print("=== Network Tests Complete ===")

# Test server creation and cleanup
func test_server_creation() -> bool:
	print("Testing server creation...")
	
	# Store current state
	var original_peer = multiplayer_peer
	var original_host = is_host
	var original_connected = is_connected
	
	# Create test server
	var test_peer = ENetMultiplayerPeer.new()
	var result = test_peer.create_server(PORT + 1000)  # Use different port for testing
	
	if result != OK:
		print("  Failed to create test server: " + error_string(result))
		return false
	
	# Cleanup test server
	test_peer.close()
	
	# Restore original state
	multiplayer_peer = original_peer
	is_host = original_host
	is_connected = original_connected
	
	print("  Server creation test successful")
	return true

# Test pattern synchronization without network
func test_pattern_synchronization() -> bool:
	print("Testing pattern synchronization...")
	
	# Create test patterns
	var test_pattern_1 = {Vector2(0,0): true, Vector2(1,0): true, Vector2(0,1): true}
	var test_pattern_2 = {Vector2(2,2): true, Vector2(3,2): true, Vector2(2,3): true}
	
	# Store original patterns
	var original_patterns = player_patterns.duplicate()
	
	# Test pattern storage
	player_patterns[1] = test_pattern_1
	player_patterns[2] = test_pattern_2
	
	# Test pattern retrieval
	var retrieved_1 = get_player_pattern(1)
	var retrieved_2 = get_player_pattern(2)
	
	var success = (retrieved_1 == test_pattern_1) and (retrieved_2 == test_pattern_2)
	
	# Restore original patterns
	player_patterns = original_patterns
	
	if success:
		print("  Pattern synchronization test successful")
	else:
		print("  Pattern synchronization test failed")
	
	return success

# Benchmark network performance
func benchmark_network_performance():
	print("Benchmarking network performance...")
	
	var test_ips = ["127.0.0.1", get_local_ip()]
	var results = {}
	
	for ip in test_ips:
		if ip == "":
			continue
			
		print("  Testing " + ip + "...")
		var start_time = Time.get_unix_time_from_system()
		
		# Test connection with short timeout
		var connection_result = await test_server_at_ip(ip, 0.1)
		
		var end_time = Time.get_unix_time_from_system()
		var response_time = (end_time - start_time) * 1000  # Convert to milliseconds
		
		results[ip] = {
			"connected": connection_result,
			"response_time_ms": response_time
		}
		
		print("    " + ip + ": " + str(response_time) + "ms (" + ("connected" if connection_result else "no server") + ")")
	
	print("  Network performance benchmark complete")

# Simulate multiplayer scenario for testing
func simulate_multiplayer_scenario():
	print("Simulating multiplayer scenario...")
	
	# Create mock players
	var mock_players = [1, 2, 3]
	var mock_patterns = {
		1: {Vector2(0,0): true, Vector2(1,0): true},
		2: {Vector2(2,0): true, Vector2(3,0): true},
		3: {Vector2(0,2): true, Vector2(1,2): true}
	}
	
	# Store original state
	var original_patterns = player_patterns.duplicate()
	
	# Simulate player connections
	for player_id in mock_players:
		player_patterns[player_id] = mock_patterns[player_id]
		print("  Mock player " + str(player_id) + " connected with " + str(mock_patterns[player_id].size()) + " cells")
		
		# Simulate pattern sync
		player_pattern_received.emit(player_id, mock_patterns[player_id])
	
	# Wait a moment
	await get_tree().create_timer(1.0).timeout
	
	# Simulate disconnections
	for player_id in mock_players:
		if player_patterns.has(player_id):
			player_patterns.erase(player_id)
		print("  Mock player " + str(player_id) + " disconnected")
		peer_disconnected.emit(player_id)
	
	# Restore original state
	player_patterns = original_patterns
	
	print("Multiplayer scenario simulation complete")

# Test server scanning functionality
func test_server_scanning():
	print("Testing server scanning functionality...")
	
	var test_ips = ["127.0.0.1", "192.168.1.1", "10.0.0.1"]
	var scan_results = []
	
	for ip in test_ips:
		print("  Scanning " + ip + "...")
		var result = await test_server_at_ip(ip, 0.2)
		scan_results.append({"ip": ip, "active": result})
		print("    " + ip + ": " + ("✅ Server found" if result else "❌ No server"))
	
	print("Server scanning test complete")
	return scan_results

# Test local multiplayer setup (both server and client on same machine)
func test_local_multiplayer_setup():
	print("Testing local multiplayer setup...")
	
	# This would typically be called from Game3D to actually create server/client
	print("  Starting server on localhost...")
	var server_result = create_server()
	
	if server_result == OK:
		print("  ✅ Server started successfully")
		
		# Wait a moment for server to fully initialize
		await get_tree().create_timer(0.5).timeout
		
		# Test connection to our own server
		var connection_test = await test_server_at_ip("127.0.0.1", 1.0)
		print("  Connection to own server: " + ("✅ Success" if connection_test else "❌ Failed"))
		
		# Cleanup
		clear_multiplayer()
		print("  Server cleaned up")
		
		return connection_test
	else:
		print("  ❌ Failed to start server: " + error_string(server_result))
		return false

# Stress test the multiplayer system
func stress_test_multiplayer():
	print("Running multiplayer stress test...")
	
	# Simulate rapid pattern updates
	var stress_patterns = []
	for i in range(50):
		var pattern = {}
		for j in range(10):
			pattern[Vector2(i % 10, j)] = (i + j) % 2 == 0
		stress_patterns.append(pattern)
	
	# Store original patterns
	var original_patterns = player_patterns.duplicate()
	
	# Rapid pattern updates
	print("  Testing rapid pattern updates...")
	var start_time = Time.get_unix_time_from_system()
	
	for i in range(stress_patterns.size()):
		player_patterns[i] = stress_patterns[i]
		player_pattern_received.emit(i, stress_patterns[i])
		
		# Brief pause to prevent system overload
		if i % 10 == 0:
			await get_tree().process_frame
	
	var end_time = Time.get_unix_time_from_system()
	var total_time = end_time - start_time
	
	print("  Processed " + str(stress_patterns.size()) + " patterns in " + str(total_time) + " seconds")
	print("  Average: " + str(total_time / stress_patterns.size()) + " seconds per pattern")
	
	# Cleanup
	player_patterns = original_patterns
	
	print("Stress test complete")

# Get network diagnostics
func get_network_diagnostics() -> Dictionary:
	var diagnostics = {
		"local_ip": get_local_ip(),
		"port": PORT,
		"is_host": is_host,
		"is_connected": is_connected,
		"connected_peers": [],
		"player_patterns_count": player_patterns.size(),
		"multiplayer_peer_status": "none"
	}
	
	if multiplayer_peer:
		diagnostics.multiplayer_peer_status = str(multiplayer_peer.get_connection_status())
		diagnostics.connected_peers = multiplayer.get_peers()
	
	return diagnostics

# Print current network status
func print_network_status():
	var diagnostics = get_network_diagnostics()
	
	print("=== Network Status ===")
	print("Local IP: " + diagnostics.local_ip)
	print("Port: " + str(diagnostics.port))
	print("Is Host: " + str(diagnostics.is_host))
	print("Is Connected: " + str(diagnostics.is_connected))
	print("Connected Peers: " + str(diagnostics.connected_peers))
	print("Player Patterns: " + str(diagnostics.player_patterns_count))
	print("Peer Status: " + diagnostics.multiplayer_peer_status)
	print("=====================")
