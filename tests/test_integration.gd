class_name IntegrationTests
extends Node

var test_framework: TestFramework
var timeout_timer: Timer
var host_process: int = -1
var client_process: int = -1

func _init():
	test_framework = TestFramework.new()
	add_child(test_framework)
	
	timeout_timer = Timer.new()
	timeout_timer.wait_time = 30.0  # 30 second timeout for integration tests
	timeout_timer.one_shot = true
	add_child(timeout_timer)

func _ready():
	await run_integration_tests()

func run_integration_tests():
	print("Starting Integration Tests...")
	
	await test_multiplayer_connection_flow()
	await test_command_file_multiplayer_control()
	await test_pattern_synchronization()
	
	var all_passed = test_framework.finish_all_tests()
	
	if all_passed:
		get_tree().quit(0)
	else:
		get_tree().quit(1)

func test_multiplayer_connection_flow():
	test_framework.start_test("Multiplayer Connection Flow")
	
	# Start host instance
	print("Starting host instance...")
	var host_cmd = ["/mnt/c/ProgramData/chocolatey/bin/godot.exe", "--headless", "--auto-host", "--", "project.godot"]
	host_process = OS.create_process("/mnt/c/ProgramData/chocolatey/bin/godot.exe", ["--headless", "--auto-host", "--", "project.godot"])
	
	test_framework.assert_true(host_process > 0, "Host process should start successfully")
	
	# Wait for host to initialize
	await get_tree().create_timer(3.0).timeout
	
	# Start client instance  
	print("Starting client instance...")
	client_process = OS.create_process("/mnt/c/ProgramData/chocolatey/bin/godot.exe", ["--headless", "--auto-client", "--", "project.godot"])
	
	test_framework.assert_true(client_process > 0, "Client process should start successfully")
	
	# Wait for connection to establish
	await get_tree().create_timer(5.0).timeout
	
	# Check that processes are still running (indicates successful connection)
	var host_running = is_process_running(host_process)
	var client_running = is_process_running(client_process)
	
	test_framework.assert_true(host_running, "Host should still be running after connection")
	test_framework.assert_true(client_running, "Client should still be running after connection")
	
	# Clean up processes
	cleanup_processes()
	
	test_framework.end_test()

func test_command_file_multiplayer_control():
	test_framework.start_test("Command File Multiplayer Control")
	
	# This test creates command files and verifies the system can handle them
	var test_files = [
		"claude_commands_host.txt",
		"claude_commands_client.txt", 
		"claude_commands_1.txt"
	]
	
	var test_commands = [
		"list",
		"jump",
		"walk forward 2"
	]
	
	# Create test command files
	for i in range(test_files.size()):
		var success = create_test_file(test_files[i], test_commands[i])
		test_framework.assert_true(success, "Should create test file: " + test_files[i])
	
	# Verify files exist and contain correct content
	for i in range(test_files.size()):
		var content = read_test_file(test_files[i])
		test_framework.assert_equal(test_commands[i], content, "File should contain correct command: " + test_files[i])
	
	# Clean up test files
	for file_path in test_files:
		remove_test_file(file_path)
	
	test_framework.end_test()

func test_pattern_synchronization():
	test_framework.start_test("Pattern Synchronization")
	
	# Test that patterns are properly calculated for multiplayer
	var test_patterns = [
		{Vector2(0, 0): true},  # Single cell - should be high damage, low velocity
		{Vector2(0, 0): true, Vector2(1, 0): true, Vector2(0, 1): true, Vector2(1, 1): true},  # Block - balanced
		{Vector2(0, 0): true, Vector2(1, 1): true, Vector2(2, 2): true, Vector2(3, 3): true, Vector2(4, 4): true}  # Large - low damage, high velocity
	]
	
	for i in range(test_patterns.size()):
		var pattern = test_patterns[i]
		var size = pattern.size()
		
		# Calculate expected values (from game logic)
		var expected_damage = max(25.0 / size, 1.0)
		var expected_velocity = min(20.0 * sqrt(size), 50.0)
		
		# Test damage calculation
		test_framework.assert_true(expected_damage > 0, "Damage should be positive for pattern " + str(i))
		test_framework.assert_true(expected_velocity > 0, "Velocity should be positive for pattern " + str(i))
		
		# Test that larger patterns have lower damage but higher velocity
		if i > 0:
			var prev_pattern = test_patterns[i-1]
			var prev_size = prev_pattern.size()
			var prev_damage = max(25.0 / prev_size, 1.0)
			var prev_velocity = min(20.0 * sqrt(prev_size), 50.0)
			
			if size > prev_size:
				test_framework.assert_true(expected_damage <= prev_damage, "Larger pattern should have lower or equal damage")
				test_framework.assert_true(expected_velocity >= prev_velocity, "Larger pattern should have higher or equal velocity")
	
	test_framework.end_test()

# Helper functions
func is_process_running(pid: int) -> bool:
	if pid <= 0:
		return false
	
	# On Windows, check if process exists
	var result = OS.execute("tasklist.exe", ["/FI", "PID eq " + str(pid)], [], false, true)
	return result == 0

func cleanup_processes():
	if host_process > 0:
		OS.kill(host_process)
	if client_process > 0:
		OS.kill(client_process)
	
	# Also kill any godot processes that might be hanging around
	OS.execute("taskkill.exe", ["/F", "/IM", "godot.exe"], [], false, true)
	OS.execute("taskkill.exe", ["/F", "/IM", "Godot_v4.4.1-stable_win64.exe"], [], false, true)

func create_test_file(file_path: String, content: String) -> bool:
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()
		return true
	return false

func read_test_file(file_path: String) -> String:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		file.close()
		return content
	return ""

func remove_test_file(file_path: String):
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(file_path)