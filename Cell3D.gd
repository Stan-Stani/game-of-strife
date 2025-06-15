extends RigidBody3D

var collision_enabled_with_owner = false

func _ready():
	print("DEBUG: Cell3D _ready called - bullet spawned")
	
	# Start with collision disabled for owner
	if has_meta("owner_player"):
		var owner_player = get_meta("owner_player")
		if is_instance_valid(owner_player):
			add_collision_exception_with(owner_player)
			print("DEBUG: Added collision exception with owner: " + str(owner_player.name))
	
	# Connect collision signals for better response
	print("DEBUG: Cell3D _ready - contact_monitor: " + str(contact_monitor))
	if contact_monitor:
		print("DEBUG: Connecting collision signals")
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)
		print("DEBUG: Collision signals connected")
	else:
		print("DEBUG: Contact monitoring not enabled, cannot connect signals")
	
	# Check distance from owner every physics frame to enable collision
	set_physics_process(true)
	
	print("DEBUG: Cell3D setup complete - position: " + str(global_position))

func _physics_process(delta):
	# Check bullet lifetime and cleanup if expired
	if has_meta("spawn_time") and has_meta("lifetime"):
		var spawn_time = get_meta("spawn_time")
		var lifetime = get_meta("lifetime")
		var current_time = Time.get_unix_time_from_system()
		
		if current_time - spawn_time >= lifetime:
			queue_free()
			return
	
	# Check if we should enable collision with owner based on distance (one-time only)
	if not collision_enabled_with_owner and has_meta("owner_player") and has_meta("min_separation_distance"):
		var owner_player = get_meta("owner_player")
		var min_distance = get_meta("min_separation_distance")
		
		if is_instance_valid(owner_player):
			var distance = global_position.distance_to(owner_player.global_position)
			
			# Once far enough away, enable collision permanently
			if distance >= min_distance:
				remove_collision_exception_with(owner_player)
				collision_enabled_with_owner = true
				# Don't stop physics process - still need it for lifetime checking

func _on_body_entered(body):
	print("DEBUG: Bullet collision with: " + str(body.name) + " (type: " + str(body.get_class()) + ")")
	
	# Handle collision with players or other objects
	if body.get_class() == "CharacterBody3D":
		# Hit a player - deal damage
		_deal_damage_to_player(body)
		_create_impact_effect()
		print("DEBUG: Destroying bullet after hitting player")
		queue_free()  # Destroy bullet on player impact
	elif body.get_class() == "StaticBody3D" or body.get_class() == "RigidBody3D":
		# Hit environment or another bullet
		print("DEBUG: Bullet hit environment/other bullet - slowing down")
		_create_impact_effect()
		# Could make bullets bounce or stick instead of destroying
		linear_velocity *= 0.1  # Drastically reduce velocity on impact

func _deal_damage_to_player(player_body):
	print("Bullet hit player: " + str(player_body.name))
	
	# Make sure it's actually a player character with health system
	if player_body.has_method("take_damage"):
		var damage_amount = 25.0  # Each bullet does 25 damage (4 shots to kill)
		var shooter_id = get_meta("owner_peer_id") if has_meta("owner_peer_id") else -1
		
		# Prevent self-damage
		if shooter_id != -1 and player_body.player_peer_id == shooter_id:
			print("Prevented self-damage")
			return
		
		# Deal damage to other players
		player_body.call("take_damage", damage_amount, shooter_id)
		print("Dealt " + str(damage_amount) + " damage to player " + str(player_body.player_peer_id))
	else:
		print("Target doesn't have take_damage method")

func _on_body_exited(body):
	# Optional: handle when bullet stops touching something
	pass

func _create_impact_effect():
	# Impact effect without color change - bullets stay green
	pass