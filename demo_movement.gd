extends Node

# Auto-demo script for Claude Code player movement system
# This script will automatically run movement demonstrations when the game starts

var demo_running = false
var demo_step = 0

func _ready():
	# Wait a moment for the game to fully load, then start demo
	await get_tree().create_timer(3.0).timeout
	start_movement_demo()

func start_movement_demo():
	if demo_running:
		return
		
	demo_running = true
	print("=== CLAUDE CODE MOVEMENT DEMO STARTING ===")
	
	# Get the Game3D scene
	var game_3d = get_node("/root/Game3D")
	if not game_3d:
		print("No Game3D scene found - demo cancelled")
		return
	
	# List available players
	game_3d.claude_list_players()
	
	# Get local player
	var player = game_3d.claude_get_local_player()
	if not player:
		print("No local player found - demo cancelled")
		return
	
	# Enable debug movement
	game_3d.claude_enable_player_debug_movement(true, 0)
	
	# Get starting position
	var start_pos = player.claude_get_position()
	print("Demo starting at position: " + str(start_pos))
	
	# Run the movement sequence
	await _run_demo_sequence(game_3d, player, start_pos)
	
	print("=== CLAUDE CODE MOVEMENT DEMO COMPLETED ===")
	demo_running = false

func _run_demo_sequence(game_3d, player, start_pos: Vector3):
	# Step 1: Move right
	print("DEMO STEP 1: Moving right (+X)")
	game_3d.claude_move_player_to(start_pos + Vector3(8, 0, 0), 0)
	await get_tree().create_timer(4.0).timeout
	
	# Step 2: Move forward
	print("DEMO STEP 2: Moving forward (-Z)")  
	game_3d.claude_move_player_to(start_pos + Vector3(8, 0, -8), 0)
	await get_tree().create_timer(4.0).timeout
	
	# Step 3: Move up
	print("DEMO STEP 3: Moving up (+Y)")
	game_3d.claude_move_player_to(start_pos + Vector3(8, 5, -8), 0)
	await get_tree().create_timer(4.0).timeout
	
	# Step 4: Teleport to origin
	print("DEMO STEP 4: Teleporting to origin")
	game_3d.claude_teleport_player_to(Vector3.ZERO, 0)
	await get_tree().create_timer(2.0).timeout
	
	# Step 5: Circle movement
	print("DEMO STEP 5: Circle movement pattern")
	var radius = 5.0
	for i in range(8):
		var angle = i * PI / 4.0  # 45 degree steps
		var circle_pos = Vector3(cos(angle) * radius, 2, sin(angle) * radius)
		game_3d.claude_move_player_to(circle_pos, 0)
		await get_tree().create_timer(2.0).timeout
	
	# Step 6: Return to start
	print("DEMO STEP 6: Returning to starting position")
	game_3d.claude_teleport_player_to(start_pos, 0)
	await get_tree().create_timer(1.0).timeout
	
	# Show final status
	var final_status = game_3d.claude_get_player_status(0)
	print("Final player status: " + str(final_status))