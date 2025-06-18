extends Node

var colony

# Constants
const PORT = 3006

# Multiplayer persistence across scenes
var multiplayer_peer: ENetMultiplayerPeer = null
var is_host: bool = false
var is_connected: bool = false

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
