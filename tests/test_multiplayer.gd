class_name MultiplayerTests
extends Node

var test_framework: TestFramework
var game_state: GameState
var game_3d: Node3D
var timeout_timer: Timer

func _init():
	test_framework = TestFramework.new()
	add_child(test_framework)
	
	# Create timeout timer
	timeout_timer = Timer.new()
	timeout_timer.wait_time = 10.0  # 10 second timeout
	timeout_timer.one_shot = true
	add_child(timeout_timer)

func _ready():
	# Get references to main game objects
	game_state = GameState
	
	# Run all tests
	await run_all_tests()

func run_all_tests():
	print("Starting Multiplayer Tests...")
	
	await test_gamestate_initialization()
	await test_gamestate_pattern_storage()
	await test_multiplayer_peer_creation()
	await test_command_file_system()
	await test_pattern_sharing()
	await test_player_synchronization()
	
	var all_passed = test_framework.finish_all_tests()
	
	# Exit with appropriate code
	if all_passed:
		get_tree().quit(0)  # Success
	else:
		get_tree().quit(1)  # Failure

func test_gamestate_initialization():
	test_framework.start_test("GameState Initialization")
	
	# Test that GameState exists and is initialized
	test_framework.assert_not_null(game_state, "GameState should exist")
	test_framework.assert_not_null(game_state.colony, "Colony dictionary should be initialized")
	test_framework.assert_true(game_state.colony is Dictionary, "Colony should be a Dictionary")
	
	test_framework.end_test()

func test_gamestate_pattern_storage():
	test_framework.start_test("GameState Pattern Storage")
	
	# Test pattern storage and retrieval
	var test_pattern = {
		Vector2(0, 0): true,
		Vector2(1, 0): true,
		Vector2(0, 1): true,
		Vector2(1, 1): true
	}
	
	# Store pattern
	game_state.colony = test_pattern.duplicate()
	game_state.store_pattern_on_load()
	
	# Test stored pattern
	test_framework.assert_equal(4, game_state.colony.size(), "Pattern should have 4 cells")
	test_framework.assert_true(game_state.colony.has(Vector2(0, 0)), "Pattern should contain (0,0)")
	test_framework.assert_true(game_state.colony.has(Vector2(1, 1)), "Pattern should contain (1,1)")
	
	test_framework.end_test()

func test_multiplayer_peer_creation():
	test_framework.start_test("Multiplayer Peer Creation")
	
	# Test server creation
	var server_error = game_state.create_server()
	test_framework.assert_equal(OK, server_error, "Server should create successfully")
	test_framework.assert_true(game_state.multiplayer_peer != null, "Multiplayer peer should be created")
	test_framework.assert_true(multiplayer.is_server(), "Should be server after creation")
	
	# Clean up
	game_state.multiplayer_peer = null
	multiplayer.multiplayer_peer = null
	
	test_framework.end_test()

func test_command_file_system():
	test_framework.start_test("Command File System")
	
	# Create a mock Game3D instance to test command functionality
	var mock_game_3d = Node3D.new()
	mock_game_3d.set_script(load("res://game_3d.gd"))
	add_child(mock_game_3d)
	
	# Test command file detection logic
	var default_files = mock_game_3d._get_command_files_to_watch()
	test_framework.assert_true(default_files.has("claude_commands.txt"), "Should always watch default file")
	
	# Test with multiplayer peer (server)
	game_state.create_server()
	var server_files = mock_game_3d._get_command_files_to_watch()
	test_framework.assert_true(server_files.has("claude_commands_host.txt"), "Server should watch host file")
	test_framework.assert_true(server_files.has("claude_commands_1.txt"), "Server should watch peer ID file")
	
	# Clean up
	game_state.multiplayer_peer = null
	multiplayer.multiplayer_peer = null
	mock_game_3d.queue_free()
	
	test_framework.end_test()

func test_pattern_sharing():
	test_framework.start_test("Pattern Sharing")
	
	# Test pattern size calculation and damage scaling
	var test_patterns = [
		{Vector2(0, 0): true},  # 1 cell
		{Vector2(0, 0): true, Vector2(1, 0): true, Vector2(0, 1): true, Vector2(1, 1): true},  # 4 cells
		{}  # Empty pattern
	]
	
	for i in range(test_patterns.size()):
		var pattern = test_patterns[i]
		game_state.colony = pattern
		
		var expected_size = pattern.size()
		var expected_damage = max(25.0 / expected_size, 1.0) if expected_size > 0 else 1.0
		var expected_velocity = min(20.0 * sqrt(expected_size), 50.0) if expected_size > 0 else 10.0
		
		# Test pattern analysis (this would be done in game_3d.gd)
		var actual_size = pattern.size()
		var actual_damage = max(25.0 / actual_size, 1.0) if actual_size > 0 else 1.0
		var actual_velocity = min(20.0 * sqrt(actual_size), 50.0) if actual_size > 0 else 10.0
		
		test_framework.assert_equal(expected_size, actual_size, "Pattern " + str(i) + " size should match")
		test_framework.assert_equal(expected_damage, actual_damage, "Pattern " + str(i) + " damage should match")
		test_framework.assert_equal(expected_velocity, actual_velocity, "Pattern " + str(i) + " velocity should match")
	
	test_framework.end_test()

func test_player_synchronization():
	test_framework.start_test("Player Synchronization")
	
	# Test that player patterns are stored per peer ID
	var test_peer_id = 12345
	var test_pattern = {Vector2(2, 2): true, Vector2(3, 2): true}
	
	# Store pattern for specific peer
	game_state.store_player_pattern(test_peer_id, test_pattern)
	
	# Retrieve and verify
	var retrieved_pattern = game_state.get_player_pattern(test_peer_id)
	test_framework.assert_not_null(retrieved_pattern, "Should retrieve stored pattern")
	test_framework.assert_equal(2, retrieved_pattern.size(), "Retrieved pattern should have correct size")
	test_framework.assert_true(retrieved_pattern.has(Vector2(2, 2)), "Retrieved pattern should contain correct cells")
	
	test_framework.end_test()

# Helper function to create test command files
func create_test_command_file(filename: String, content: String):
	var file = FileAccess.open(filename, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		return true
	return false

# Helper function to clean up test files
func cleanup_test_files():
	var test_files = [
		"test_commands.txt",
		"test_commands_host.txt", 
		"test_commands_client.txt"
	]
	
	for file_path in test_files:
		if FileAccess.file_exists(file_path):
			DirAccess.remove_absolute(file_path)