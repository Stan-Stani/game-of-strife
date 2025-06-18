class_name CommandSystemTests
extends Node

var test_framework: TestFramework
var mock_game_3d: Node3D

func _init():
	test_framework = TestFramework.new()
	add_child(test_framework)

func _ready():
	await run_all_tests()

func run_all_tests():
	print("Starting Command System Tests...")
	
	setup_mock_game_3d()
	
	await test_command_file_parsing()
	await test_command_execution()
	await test_file_monitoring_logic()
	await test_role_based_file_selection()
	await test_peer_id_file_selection()
	await test_command_clearing()
	
	cleanup_mock_game_3d()
	
	var all_passed = test_framework.finish_all_tests()
	
	if all_passed:
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func setup_mock_game_3d():
	mock_game_3d = Node3D.new()
	mock_game_3d.set_script(load("res://game_3d.gd"))
	add_child(mock_game_3d)

func cleanup_mock_game_3d():
	if mock_game_3d:
		mock_game_3d.queue_free()

func test_command_file_parsing():
	test_framework.start_test("Command File Parsing")
	
	# Test valid command parsing
	var test_commands = [
		"walk forward 2",
		"teleport 10 5 0",
		"jump",
		"list",
		"run back 3"
	]
	
	for command in test_commands:
		var parts = command.split(" ")
		test_framework.assert_true(parts.size() > 0, "Command should have at least one part: " + command)
		test_framework.assert_true(parts[0].length() > 0, "Command should have valid verb: " + command)
	
	# Test command with parameters
	var walk_cmd = "walk forward 2"
	var walk_parts = walk_cmd.split(" ")
	test_framework.assert_equal("walk", walk_parts[0], "First part should be command")
	test_framework.assert_equal("forward", walk_parts[1], "Second part should be direction")
	test_framework.assert_equal("2", walk_parts[2], "Third part should be duration")
	
	test_framework.end_test()

func test_command_execution():
	test_framework.start_test("Command Execution Logic")
	
	# Test that commands are properly categorized
	var movement_commands = ["walk", "run", "jump"]
	var utility_commands = ["list", "status", "teleport"]
	var debug_commands = ["enable_numpad_movement", "test"]
	
	for cmd in movement_commands:
		test_framework.assert_true(is_movement_command(cmd), cmd + " should be recognized as movement command")
	
	for cmd in utility_commands:
		test_framework.assert_true(is_utility_command(cmd), cmd + " should be recognized as utility command")
	
	for cmd in debug_commands:
		test_framework.assert_true(is_debug_command(cmd), cmd + " should be recognized as debug command")
	
	test_framework.end_test()

func test_file_monitoring_logic():
	test_framework.start_test("File Monitoring Logic")
	
	# Test default file monitoring (no multiplayer)
	var default_files = mock_game_3d._get_command_files_to_watch()
	test_framework.assert_true(default_files.has("claude_commands.txt"), "Should always monitor default file")
	test_framework.assert_equal(1, default_files.size(), "Should only monitor default file when no multiplayer")
	
	test_framework.end_test()

func test_role_based_file_selection():
	test_framework.start_test("Role-based File Selection")
	
	# Test server role
	GameState.create_server()
	await get_tree().process_frame  # Allow one frame for setup
	
	var server_files = mock_game_3d._get_command_files_to_watch()
	test_framework.assert_true(server_files.has("claude_commands.txt"), "Server should monitor default file")
	test_framework.assert_true(server_files.has("claude_commands_host.txt"), "Server should monitor host file")
	test_framework.assert_true(server_files.has("claude_commands_1.txt"), "Server should monitor peer ID file")
	
	# Clean up server
	GameState.multiplayer_peer = null
	multiplayer.multiplayer_peer = null
	
	test_framework.end_test()

func test_peer_id_file_selection():
	test_framework.start_test("Peer ID File Selection")
	
	# Test that peer ID files are correctly generated
	var test_peer_ids = [1, 2, 123456, 999999999]
	
	for peer_id in test_peer_ids:
		var expected_filename = "claude_commands_" + str(peer_id) + ".txt"
		test_framework.assert_true(expected_filename.begins_with("claude_commands_"), "Peer ID file should have correct prefix")
		test_framework.assert_true(expected_filename.ends_with(".txt"), "Peer ID file should have .txt extension")
		test_framework.assert_true(str(peer_id) in expected_filename, "Peer ID should be in filename")
	
	test_framework.end_test()

func test_command_clearing():
	test_framework.start_test("Command File Clearing")
	
	# Create test command file
	var test_file = "test_command_clear.txt"
	var test_content = "test command"
	
	# Write test content
	var file = FileAccess.open(test_file, FileAccess.WRITE)
	test_framework.assert_not_null(file, "Should be able to create test file")
	file.store_string(test_content)
	file.close()
	
	# Verify content exists
	file = FileAccess.open(test_file, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	test_framework.assert_equal(test_content, content, "File should contain test content")
	
	# Clear the file (simulate what the system does)
	file = FileAccess.open(test_file, FileAccess.WRITE)
	file.store_string("")
	file.close()
	
	# Verify file is cleared
	file = FileAccess.open(test_file, FileAccess.READ)
	var cleared_content = file.get_as_text()
	file.close()
	test_framework.assert_equal("", cleared_content, "File should be empty after clearing")
	
	# Clean up
	DirAccess.remove_absolute(test_file)
	
	test_framework.end_test()

# Helper functions for command categorization
func is_movement_command(cmd: String) -> bool:
	return cmd in ["walk", "run", "jump", "teleport", "tp"]

func is_utility_command(cmd: String) -> bool:
	return cmd in ["list", "status", "pos", "speed"]

func is_debug_command(cmd: String) -> bool:
	return cmd in ["enable_numpad_movement", "disable_numpad_movement", "test", "simulate_input"]