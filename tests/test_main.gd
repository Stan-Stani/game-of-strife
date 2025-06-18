extends Node

# Simple test runner that can be executed directly

func _ready():
	print("=== MULTIPLAYER FUNCTIONALITY TESTS ===")
	print("Running unit tests...")
	
	await run_basic_tests()
	
	print("=== TESTS COMPLETED ===")
	get_tree().quit()

func run_basic_tests():
	var test_framework = TestFramework.new()
	add_child(test_framework)
	
	# Test 1: GameState functionality
	test_framework.start_test("GameState Basic Functionality")
	test_framework.assert_not_null(GameState, "GameState should exist")
	test_framework.assert_not_null(GameState.colony, "Colony should be initialized")
	test_framework.assert_true(GameState.colony is Dictionary, "Colony should be a Dictionary")
	test_framework.end_test()
	
	# Test 2: Multiplayer peer creation
	test_framework.start_test("Multiplayer Peer Creation")
	var server_error = GameState.create_server()
	test_framework.assert_equal(OK, server_error, "Server should create successfully")
	test_framework.assert_true(GameState.multiplayer_peer != null, "Multiplayer peer should be created")
	GameState.multiplayer_peer = null
	multiplayer.multiplayer_peer = null
	test_framework.end_test()
	
	# Test 3: Pattern storage
	test_framework.start_test("Pattern Storage and Retrieval")
	var test_pattern = {Vector2(0, 0): true, Vector2(1, 0): true}
	GameState.colony = test_pattern.duplicate()
	test_framework.assert_equal(2, GameState.colony.size(), "Pattern should have 2 cells")
	test_framework.assert_true(GameState.colony.has(Vector2(0, 0)), "Pattern should contain (0,0)")
	test_framework.end_test()
	
	# Test 4: Command file system basics
	test_framework.start_test("Command File System")
	var test_file = "test_command.txt"
	var test_content = "list"
	
	# Create test file
	var file = FileAccess.open(test_file, FileAccess.WRITE)
	if file:
		file.store_string(test_content)
		file.close()
		test_framework.assert_true(true, "Should create test command file")
		
		# Read back
		file = FileAccess.open(test_file, FileAccess.READ)
		var content = file.get_as_text()
		file.close()
		test_framework.assert_equal(test_content, content, "File should contain correct command")
		
		# Clean up
		DirAccess.remove_absolute(test_file)
	else:
		test_framework.assert_true(false, "Failed to create test file")
	
	test_framework.end_test()
	
	# Test 5: Game3D command file logic
	test_framework.start_test("Game3D Command File Logic")
	var game_3d = Node3D.new()
	game_3d.set_script(load("res://game_3d.gd"))
	add_child(game_3d)
	
	# Test default file watching
	var default_files = game_3d._get_command_files_to_watch()
	test_framework.assert_true(default_files.has("claude_commands.txt"), "Should always watch default file")
	
	# Test with server
	GameState.create_server()
	await get_tree().process_frame
	var server_files = game_3d._get_command_files_to_watch()
	test_framework.assert_true(server_files.has("claude_commands_host.txt"), "Server should watch host file")
	
	# Clean up
	GameState.multiplayer_peer = null
	multiplayer.multiplayer_peer = null
	game_3d.queue_free()
	test_framework.end_test()
	
	# Finish tests
	var success = test_framework.finish_all_tests()
	
	if success:
		print("\n🎉 ALL TESTS PASSED! 🎉")
	else:
		print("\n❌ SOME TESTS FAILED ❌")
	
	return success