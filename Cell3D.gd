extends RigidBody3D

var collision_enabled_with_owner = false

func _ready():
	# Start with collision disabled for owner
	if has_meta("owner_player"):
		var owner_player = get_meta("owner_player")
		if is_instance_valid(owner_player):
			add_collision_exception_with(owner_player)
	
	# Check distance from owner every physics frame to enable collision
	set_physics_process(true)

func _physics_process(_delta):
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
				set_physics_process(false)  # Stop checking distance