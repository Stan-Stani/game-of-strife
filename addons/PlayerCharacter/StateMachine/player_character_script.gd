extends CharacterBody3D

# Health and death signals
signal health_changed(new_health: float, max_health: float)
signal player_died(player: CharacterBody3D)
signal player_respawned(player: CharacterBody3D)

# multiplayer variables
var is_remote = false
var player_peer_id = 1  # Which peer this player represents (for pattern shooting)
var remote_input_data = {}
var remote_camera_rotation = Vector3.ZERO
var remote_camera_transform = Transform3D.IDENTITY
var input_buffer = []

# shooting variables
var shoot_cooldown_time = 0.5  # Half second between shots
var last_shoot_time = 0.0

# health variables
var max_health: float = 100.0
var current_health: float = 100.0
var is_dead: bool = false
var respawn_timer: float = 0.0
var respawn_delay: float = 3.0  # 3 seconds respawn delay
var death_time: float = 0.0

#movement variables
var move_speed : float
var move_accel : float
var move_deccel : float
var move_dir : Vector2
var target_angle : float
var last_input_dir : Vector2
var last_frame_position : Vector3
var last_frame_velocity : Vector3
var was_on_floor : bool = false
var walk_or_run : String = "WalkState" #keep in memory if play char was walking or running before being in the air


@export_group("Walk variables")
@export var walk_speed : float
@export var walk_accel : float
@export var walk_deccel : float

@export_group("Run variables")
@export var run_speed : float
@export var run_accel : float
@export var run_deccel : float
@export var continious_run : bool = false #if true, doesn't need to keep run button on to run

@export_group("Jump variables")
@export var jump_height : float
@export var jump_time_to_peak : float
@export var jump_time_to_descent : float
@onready var jump_velocity : float = ((2.0 * jump_height) / jump_time_to_peak) * -1.0
var has_cut_jump : bool = false
@export var jump_cut_multiplier : float
@export var jump_cooldown : float
var jump_cooldown_ref : float 
@export var nb_jumps_in_air_allowed : int 
var nb_jumps_in_air_allowed_ref : int
var jump_buff_on : bool = false
var buffered_jump : bool = false
@export var coyote_jump_cooldown : float
var coyote_jump_cooldown_ref : float
var coyote_jump_on : bool = false
@export var auto_jump : bool = false
 
@export_group("In air variables")
@export var in_air_move_speed : Array[Curve]
@export var in_air_accel : Array[Curve]
@export var hit_wall_cut_velocity : bool = false

#gravity variables
@onready var jump_gravity : float = ((-2.0 * jump_height) / (jump_time_to_peak * jump_time_to_peak)) * -1.0
@onready var fall_gravity : float = ((-2.0 * jump_height) / (jump_time_to_descent * jump_time_to_descent)) * -1.0

@export_group("Keybinding variables")
@export var moveForwardAction : String = "move_forward"
@export var moveBackwardAction : String = "move_backward"
@export var moveLeftAction : String = "move_left"
@export var moveRightAction : String = "move_right"
@export var runAction : String = "run"
@export var jumpAction : String = "jump"
@export var shootAction : String = "shoot"

@export_group("Model variables")
@export var model_rot_speed : float
@export var ragdoll_gravity : float
@export var ragdoll_on_floor_only : bool = false
@export var follow_cam_pos_when_aimed : bool = true

#references variables
@onready var visual_root = %VisualRoot
@onready var godot_plush_skin = %GodotPlushSkin
@onready var particles_manager = %ParticlesManager
@onready var cam_holder = $OrbitView
@onready var state_machine = $StateMachine
@onready var debug_hud = %DebugHUD
@onready var foot_step_audio = %FootStepAudio
@onready var impact_audio = %ImpactAudio
@onready var wave_audio = %WaveAudio
@onready var collision_shape_3d = %CollisionShape3D
@onready var floor_check : RayCast3D = %FloorRaycast

#particles variables
@onready var movement_dust = %MovementDust
@onready var jump_particles = preload("res://addons/PlayerCharacter/Vfx/jump_particles.tscn")
@onready var land_particles = preload("res://addons/PlayerCharacter/Vfx/land_particles.tscn")

var Cell3D = load("res://Cell3D.tscn")
var pattern_model_cells: Array[Node3D] = []
var pattern_collision_box: Node3D = null
var pattern_container: Node3D = null

@onready var cR: CharacterBody3D = $"."

@onready var Game3D = $"/root/Game3D"

@onready var player_camera = $"./OrbitView/Camera3D"

func _ready():
	#set move variables, and value references
	move_speed = walk_speed
	move_accel = walk_accel
	move_deccel = walk_deccel
	
	jump_cooldown_ref = jump_cooldown
	nb_jumps_in_air_allowed_ref = nb_jumps_in_air_allowed
	coyote_jump_cooldown_ref = coyote_jump_cooldown
	
	# Initialize health
	current_health = max_health
	is_dead = false
	
	# No need for special collision layers - bullets handle collision exceptions
	
	# Make local player translucent to themselves
	if !is_remote:
		_make_player_translucent()
	
	
	#set char model audios effects
	godot_plush_skin.footstep.connect(func(intensity : float = 1.0):
		foot_step_audio.volume_db = linear_to_db(intensity)
		foot_step_audio.play()
		)
		
func _process(delta: float):
	modify_model_orientation(delta)
	
	# Update board orientation to match camera (like an FPS weapon)
	if pattern_container:
		var camera_transform = get_camera_transform()
		pattern_container.transform.basis = camera_transform.basis
	
	# Update collision shape orientation to match camera as well
	if collision_shape_3d:
		var camera_transform = get_camera_transform()
		# Apply rotation and position offset in world space to match visual board
		collision_shape_3d.transform.basis = camera_transform.basis
		# The collision shape needs to be offset to match the visual board position when rotated
		var board_offset = Vector3(0, 1.25, 0)
		collision_shape_3d.position = camera_transform.basis * board_offset
	
	display_properties()
	
func _physics_process(delta : float):
	modify_physics_properties()
	
	# Handle respawn timer for dead players
	if is_dead and respawn_timer > 0.0:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_handle_respawn()
	
	if !is_remote and is_multiplayer_authority():
		# Collect and send input data
		var input_data = collect_input_data()
		Game3D.receive_player_input.rpc(multiplayer.get_unique_id(), input_data)
	
	# Debug: Check for collisions after move_and_slide
	var collision_count_before = get_slide_collision_count()
	move_and_slide()
	var collision_count_after = get_slide_collision_count()
	
	if collision_count_after > 0:
		# Log collisions with pattern boxes and other players
		for i in range(collision_count_after):
			var collision = get_slide_collision(i)
			var collider = collision.get_collider()
			if collider:
				if collider.get_class() == "CharacterBody3D":
					pass
				elif collider.get_class() == "StaticBody3D":
					var collider_layer = collider.collision_layer
					# Check if it's a pattern box (layers 5-9 = values 32, 64, 128, 256, 512)
					if collider_layer >= 32 and collider_layer <= 512:
						pass
	
	# Handle healing (for testing) - Enter key
	if Input.is_action_just_pressed("ui_accept") and not is_dead:  # Using ui_accept (Enter) for now
		heal(25.0)  # Heal 25 HP
		print("DEBUG: Manual heal triggered - Health: " + str(current_health))
	
	# Handle manual damage (for testing) - P key  
	if Input.is_action_just_pressed("ui_cancel") and not is_dead:  # Using ui_cancel (Escape) for now
		take_damage(25.0, -1)  # Take 25 damage
		print("DEBUG: Manual damage triggered - Health: " + str(current_health))
	
	# Handle shooting with cooldown and just_pressed requirement (but not if dead)
	if get_input_just_pressed(shootAction) and not is_dead:
		var current_timestamp = Time.get_unix_time_from_system()
		
		if current_timestamp - last_shoot_time >= shoot_cooldown_time:
			last_shoot_time = current_timestamp
			var camera_transform = get_camera_transform()
			
			# Get the pattern for this specific player character (based on which peer they represent)
			var pattern_to_shoot = Game3D.get_player_pattern(player_peer_id)
			
			for cellPos in pattern_to_shoot:
				if pattern_to_shoot[cellPos] == true:
					var cell_3d: RigidBody3D = Cell3D.instantiate()
					
					# Configure bullet physics BEFORE adding to scene
					cell_3d.continuous_cd = true  # Enable continuous collision detection
					cell_3d.contact_monitor = true  # Enable contact monitoring
					cell_3d.max_contacts_reported = 10  # Allow multiple contact reports
					
					print("DEBUG: Created bullet with contact_monitor: " + str(cell_3d.contact_monitor))
					
					# Add to scene AFTER configuring physics
					Game3D.add_child(cell_3d)
					
					# Set collision layers: bullets on layer 8, collide with players (layer 3) and environment (layers 1,2)
					cell_3d.collision_layer = 256  # Layer 8 (2^8 = 256) - bullets
					cell_3d.collision_mask = 1 + 2 + 4 + 256  # Layers 1,2,3,8 (environment + players + bullets)
					
					print("DEBUG: Player collision layer: " + str(self.collision_layer))
					print("DEBUG: Bullet collision mask: " + str(cell_3d.collision_mask))
					
					# Ensure collision signals are connected (backup in case Cell3D._ready doesn't work)
					if not cell_3d.body_entered.is_connected(cell_3d._on_body_entered):
						cell_3d.body_entered.connect(cell_3d._on_body_entered)
						print("DEBUG: Manually connected body_entered signal")
					
					# Store reference to owner player for collision checking
					cell_3d.set_meta("owner_peer_id", player_peer_id)
					cell_3d.set_meta("owner_player", self)
					cell_3d.set_meta("min_separation_distance", 2.0)  # Must be this far from owner to collide
					
					# Prevent bullets from the same player from colliding with each other
					_prevent_bullet_self_collision(cell_3d, player_peer_id)
					
					# Scale the mesh and collision shape to match board cell size (0.25 units)
					var mesh_node = cell_3d.get_node("Mesh")
					var collision_node = cell_3d.get_node("CollisionShape3D")
					if mesh_node:
						mesh_node.scale = Vector3(0.25, 0.25, 0.25)
					if collision_node:
						collision_node.scale = Vector3(0.25, 0.25, 0.25)
					
					# Scale spacing to match board (no flip needed now)
					var local_position = Vector3(cellPos.x * 0.25, -cellPos.y * 0.25, 0)
					
					# Use camera transform for rotation since character body doesn't rotate
					
					# Transform the local position using camera's basis (which represents rotation)
					var rotated_position = camera_transform.basis * local_position
					
					
					# Board offset should be relative to the rotated board position
					# The board is at (0, 1.25, 0.11) relative to character, but rotated
					var board_relative_pos = Vector3(0, 1.25, 0.11)
					var rotated_board_pos = camera_transform.basis * board_relative_pos
					
					# Spawn in front of the rotated board position (negative Z is forward)
					var forward_offset = camera_transform.basis * Vector3(0, 0, -1.0)  # Move further out
					var board_offset = rotated_board_pos + forward_offset
					
					# Position at character + rotated board offset + rotated pattern position
					var final_position = self.position + board_offset + rotated_position
					cell_3d.position = final_position
					
					print("DEBUG: Spawning bullet at position: " + str(final_position) + " for player at: " + str(self.position))
					
					# Rotate the cell to match character's orientation
					cell_3d.transform.basis = camera_transform.basis
					
					# Apply forward velocity based on camera direction
					var forward_force = 20.0  # Bullet speed
					var forward_direction = -camera_transform.basis.z  # Forward is negative Z
					cell_3d.linear_velocity = forward_direction * forward_force
					
					print("DEBUG: Bullet velocity: " + str(cell_3d.linear_velocity))
					
					# Add bullet cleanup timer to prevent infinite bullets
					cell_3d.set_meta("spawn_time", Time.get_unix_time_from_system())
					cell_3d.set_meta("lifetime", 5.0)  # Bullets last 5 seconds

	
func display_properties():
	#display play char properties (only for local player)
	if !is_remote and debug_hud:
		debug_hud.display_curr_state(state_machine.curr_state_name)
		debug_hud.display_velocity(velocity.length())
		debug_hud.display_nb_jumps_in_air_allowed(nb_jumps_in_air_allowed)
		debug_hud.display_jump_buffer(jump_buff_on)
		debug_hud.display_coyote_time(coyote_jump_cooldown)
		if cam_holder:
			debug_hud.display_model_orientation(cam_holder.cam_aimed and follow_cam_pos_when_aimed)
			debug_hud.display_camera_mode(cam_holder.cam_aimed)
	
func modify_model_orientation(delta : float):
	#manage the model rotation depending on the camera mode + char parameters
	
	var dir_target_angle : float
	
	# Get camera data for both local and remote players
	var camera_rotation = get_camera_rotation()
	var cam_aimed = false
	
	# For local players, check camera aim state
	if !is_remote and cam_holder:
		cam_aimed = cam_holder.cam_aimed
	
	#follow mode (model must follow the camera rotation)
	#if the cam is in angled/aim mode
	if cam_aimed and follow_cam_pos_when_aimed and !godot_plush_skin.ragdoll:
		#get cam rotation on the y axis (+ PI to invert half circle, and be sure that the model is correctly oriented)
		dir_target_angle = camera_rotation.y + PI
		#rotate the visual model on the y axis
		visual_root.rotation.y = rotate_toward(visual_root.rotation.y, dir_target_angle, model_rot_speed * delta)
	
	#free mode (the model orientation is independant to the camera one)
	if (!cam_aimed or !follow_cam_pos_when_aimed) and move_dir != Vector2.ZERO:
		#get char move direction
		dir_target_angle = -move_dir.orthogonal().angle()
		#rotate the visual model on the y axis
		visual_root.rotation.y = rotate_toward(visual_root.rotation.y, dir_target_angle, model_rot_speed * delta)
	
	# Sync pattern and collision elements with visual root rotation
	_sync_pattern_rotation()
		
func modify_physics_properties():
	last_frame_position = position #get play char position every frame
	last_frame_velocity = velocity #get play char velocity every frame
	was_on_floor = !is_on_floor() #get if play char is on floor or not
	
func gravity_apply(delta : float):
	#if play char goes up, apply jump gravity
	#otherwise, apply fall gravity
	if velocity.y >= 0.0: velocity.y -= jump_gravity * delta
	elif velocity.y < 0.0: velocity.y -= fall_gravity * delta
	
func squash_and_strech(value : float, timing : float):
	#create a tween that simulate a compression of the model (squash and strech ones)
	#maily used to accentuate game feel/juice
	#call the squash_and_strech function of the model (it's this function that actually squash and strech the model)
	var sasTween : Tween = create_tween()
	sasTween.set_ease(Tween.EASE_OUT)
	sasTween.tween_property(godot_plush_skin, "squash_and_stretch", value, timing)
	sasTween.tween_property(godot_plush_skin, "squash_and_stretch", 1.0, timing * 1.8)

func collect_input_data() -> Dictionary:
	return {
		"move_forward": Input.is_action_pressed(moveForwardAction),
		"move_backward": Input.is_action_pressed(moveBackwardAction),
		"move_left": Input.is_action_pressed(moveLeftAction),
		"move_right": Input.is_action_pressed(moveRightAction),
		"run": Input.is_action_pressed(runAction),
		"jump": Input.is_action_just_pressed(jumpAction),
		"shoot": Input.is_action_just_pressed(shootAction),
		"ragdoll": Input.is_action_just_pressed("ragdoll"),
		"mouse_motion": Input.get_last_mouse_velocity(),
		"camera_rotation": cam_holder.global_rotation if cam_holder else Vector3.ZERO,
		"camera_transform": cam_holder.cam.global_transform if cam_holder and cam_holder.cam else Transform3D.IDENTITY,
		"position": position,
		"velocity": velocity,
		"rotation": rotation
	}

func apply_remote_input(input_data: Dictionary):
	remote_input_data = input_data
	
	# Store camera data for remote players
	if input_data.has("camera_rotation"):
		remote_camera_rotation = input_data.get("camera_rotation", Vector3.ZERO)
	if input_data.has("camera_transform"):
		remote_camera_transform = input_data.get("camera_transform", Transform3D.IDENTITY)
	
	# Apply position reconciliation for remote players
	if is_remote and input_data.has("position"):
		var target_position = input_data.get("position", position)
		var target_velocity = input_data.get("velocity", velocity)
		var target_rotation = input_data.get("rotation", rotation)
		
		# Smoothly interpolate to the authoritative position
		var distance = position.distance_to(target_position)
		if distance > 0.1:  # Only reconcile if difference is significant
			var lerp_factor = min(0.2, distance * 0.1)  # Stronger correction for larger differences
			position = position.lerp(target_position, lerp_factor)
			velocity = velocity.lerp(target_velocity, lerp_factor)
			rotation = rotation.lerp(target_rotation, lerp_factor)

func get_input_pressed(action: String) -> bool:
	if is_remote:
		return remote_input_data.get(action.replace("_action", ""), false)
	else:
		return Input.is_action_pressed(action)

func get_input_just_pressed(action: String) -> bool:
	if is_remote:
		return remote_input_data.get(action.replace("_action", ""), false)
	else:
		return Input.is_action_just_pressed(action)

func get_camera_rotation() -> Vector3:
	if is_remote:
		return remote_camera_rotation
	else:
		return cam_holder.global_rotation if cam_holder else Vector3.ZERO

func get_camera_transform() -> Transform3D:
	if is_remote:
		return remote_camera_transform
	else:
		return cam_holder.cam.global_transform if cam_holder and cam_holder.cam else Transform3D.IDENTITY

func create_pattern_model():
	# Clear existing pattern model
	clear_pattern_model()
	
	# Get the pattern for this player
	var pattern = Game3D.get_player_pattern(player_peer_id)
	
	if pattern.is_empty():
		return
	
	# Hide the default model
	if godot_plush_skin:
		godot_plush_skin.visible = false
	
	# Create pattern container node
	pattern_container = Node3D.new()
	pattern_container.name = "PatternContainer"
	add_child(pattern_container)
	
	# Create individual cells based on pattern
	_create_pattern_cells(pattern)
	
	# Make pattern model translucent for local player
	if !is_remote:
		_make_node_translucent(pattern_container, 0.3)
	
	# Set collision to match the board shape
	if collision_shape_3d:
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(2.5, 2.5, 0.2)  # Same as visual board
		collision_shape_3d.shape = box_shape
		collision_shape_3d.position = Vector3(0, 1.25, 0)  # Same position as visual board
		# Don't reset rotation - let it be controlled by _process

func _create_static_cell() -> Node3D:
	# Create a static visual cell (no physics) that looks like Cell3D
	var static_cell = MeshInstance3D.new()
	
	# Use the same visual appearance as Cell3D
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3.ONE  # Standard 1x1x1 box
	static_cell.mesh = box_mesh
	
	# Create green material to match Cell3D appearance
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.431797, 0.783099, 0.415405, 1)  # Same green as Cell3D
	material.metallic = 0.0
	material.roughness = 0.5
	static_cell.material_override = material
	
	return static_cell

func _create_pattern_monolith(pattern: Dictionary):
	# Create a simple box monolith with pattern texture
	var monolith = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(1.0, 2.0, 0.5)  # Standard monolith size for all players
	monolith.mesh = box_mesh
	
	# Create material with pattern texture
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.WHITE  # Let texture control color
	material.metallic = 0.0
	material.roughness = 0.5
	
	# Create pattern texture
	_create_pattern_texture(material, pattern)
	
	monolith.material_override = material
	monolith.position = Vector3(0, 0.0, 0)  # Put monolith center at player center
	
	
	pattern_container.add_child(monolith)
	pattern_model_cells.append(monolith)
	
	# Keep collision capsule as default (no custom collision box needed)

func _create_pattern_cells(pattern: Dictionary):
	# Create a simple box for the character body
	var character_mesh = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(2.5, 2.5, 0.2)  # Half size: 5*0.5 wide/tall, thin depth
	character_mesh.mesh = box_mesh
	character_mesh.position = Vector3(0, 1.25, 0)  # Bottom at ground level (y=0)
	
	# Simple material for the box (dark color)
	var box_material = StandardMaterial3D.new()
	box_material.albedo_color = Color(0.2, 0.2, 0.2)
	character_mesh.material_override = box_material
	
	pattern_container.add_child(character_mesh)
	pattern_model_cells.append(character_mesh)
	
	# Create Sprite3D for the pattern display
	var pattern_sprite = Sprite3D.new()
	pattern_sprite.position = Vector3(0, 1.25, 0.11)  # Match box position, slightly in front
	pattern_sprite.pixel_size = 2.5 / 32.0  # Scale to match box size (2.5 units / 32 pixels)
	pattern_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST  # Sharp pixels
	pattern_sprite.flip_h = false  # Don't flip front sprite
	
	# Generate texture for the sprite
	var texture = _create_board_sprite_texture(pattern)
	pattern_sprite.texture = texture
	
	pattern_container.add_child(pattern_sprite)
	pattern_model_cells.append(pattern_sprite)
	
	# Create back sprite (dimmer, horizontally flipped)
	var back_sprite = Sprite3D.new()
	back_sprite.position = Vector3(0, 1.25, -0.11)  # Behind the box
	back_sprite.pixel_size = 2.5 / 32.0  # Same scale as front
	back_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	back_sprite.flip_h = false  # Back sprite not flipped
	back_sprite.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Dimmer (50% brightness)
	
	# Use same texture as front
	back_sprite.texture = texture
	
	pattern_container.add_child(back_sprite)
	pattern_model_cells.append(back_sprite)
	

func _create_pattern_texture(material: StandardMaterial3D, pattern: Dictionary):
	if pattern.is_empty():
		return
	
	
	# Find pattern bounds
	var min_x = INF
	var max_x = -INF
	var min_y = INF
	var max_y = -INF
	
	for pos in pattern.keys():
		if pattern[pos] == true:
			min_x = min(min_x, pos.x)
			max_x = max(max_x, pos.x)
			min_y = min(min_y, pos.y)
			max_y = max(max_y, pos.y)
	
	if min_x == INF:
		return
	
	
	# Create texture size (make it a power of 2 for better compatibility)
	var pattern_width = int(max_x - min_x + 1)
	var pattern_height = int(max_y - min_y + 1)
	var texture_size = 32  # Fixed 32x32 texture size
	
	# Create ImageTexture using the correct Godot 4 method
	var image = Image.create(texture_size, texture_size, false, Image.FORMAT_RGB8)
	image.fill(Color(0.2, 0.2, 0.2))  # Dark background (no alpha)
	
	
	# Draw pattern cells as bright pixels
	var cells_drawn = 0
	for pos in pattern.keys():
		if pattern[pos] == true:
			var tex_x = int(pos.x - min_x)
			var tex_y = int(pos.y - min_y)
			
			# Scale to fit texture and tile
			var scale_x = float(texture_size) / float(pattern_width)
			var scale_y = float(texture_size) / float(pattern_height)
			var scale = min(scale_x, scale_y)
			
			var pixel_x = int(tex_x * scale) % texture_size
			var pixel_y = int(tex_y * scale) % texture_size
			
			# Draw a small 2x2 block for visibility
			for dx in range(2):
				for dy in range(2):
					var px = (pixel_x + dx) % texture_size
					var py = (pixel_y + dy) % texture_size
					image.set_pixel(px, py, Color(0.431797, 0.783099, 0.415405))
			cells_drawn += 1
	
	
	# Create texture and apply to material
	var texture = ImageTexture.new()
	texture.set_image(image)
	material.albedo_texture = texture
	material.uv1_scale = Vector3(2, 2, 1)  # Scale UV to show pattern clearly
	

func _create_board_pattern_texture(material: StandardMaterial3D, pattern: Dictionary):
	# Create a 10x10 texture for the board with live cells marked
	var texture_size = 32  # Use 32x32 for clear pixel art look
	var image = Image.create(texture_size, texture_size, false, Image.FORMAT_RGB8)
	
	# Fill with dark background
	image.fill(Color(0.1, 0.1, 0.1))  # Dark gray background
	
	# Draw each cell in the 10x10 grid
	var pixels_per_cell = texture_size / 10  # 3.2 pixels per cell for 32x32
	
	for cell_y in range(10):
		for cell_x in range(10):
			# Convert to grid coordinates (-5 to 4)
			var grid_pos = Vector2(cell_x - 5, cell_y - 5)
			
			# Calculate pixel position
			var pixel_start_x = int(cell_x * pixels_per_cell)
			var pixel_start_y = int(cell_y * pixels_per_cell)
			var pixel_end_x = int((cell_x + 1) * pixels_per_cell)
			var pixel_end_y = int((cell_y + 1) * pixels_per_cell)
			
			# Choose color based on if cell is alive
			var cell_color = Color(0.2, 0.2, 0.2)  # Dead cell - slightly lighter gray
			if pattern.has(grid_pos) and pattern[grid_pos] == true:
				cell_color = Color(0.0, 1.0, 0.0)  # Live cell - bright green
			
			# Fill the cell area
			for py in range(pixel_start_y, pixel_end_y):
				for px in range(pixel_start_x, pixel_end_x):
					if px < texture_size and py < texture_size:
						image.set_pixel(px, py, cell_color)
	
	# Create texture and apply to material
	var texture = ImageTexture.new()
	texture.set_image(image)
	material.albedo_texture = texture
	
	# Disable texture filtering for sharp pixel art look
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	
	# Set UV scale to prevent texture wrapping/stretching
	material.uv1_scale = Vector3(1, 1, 1)
	

func _create_board_sprite_texture(pattern: Dictionary) -> ImageTexture:
	# Create a 32x32 texture for the sprite
	var texture_size = 32
	var image = Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	
	# Fill with transparent background
	image.fill(Color(0, 0, 0, 0))
	
	# Draw each cell in the 10x10 grid
	var pixels_per_cell = texture_size / 10
	
	for cell_y in range(10):
		for cell_x in range(10):
			# Convert to grid coordinates (-5 to 4)
			var grid_pos = Vector2(cell_x - 5, cell_y - 5)
			
			# Calculate pixel position
			var pixel_start_x = int(cell_x * pixels_per_cell)
			var pixel_start_y = int(cell_y * pixels_per_cell)
			var pixel_end_x = int((cell_x + 1) * pixels_per_cell)
			var pixel_end_y = int((cell_y + 1) * pixels_per_cell)
			
			# Only draw live cells (dead cells stay transparent)
			if pattern.has(grid_pos) and pattern[grid_pos] == true:
				var cell_color = Color(0.0, 1.0, 0.0, 1.0)  # Bright green, fully opaque
				
				# Fill the cell area
				for py in range(pixel_start_y, pixel_end_y):
					for px in range(pixel_start_x, pixel_end_x):
						if px < texture_size and py < texture_size:
							image.set_pixel(px, py, cell_color)
	
	# Create and return texture
	var texture = ImageTexture.new()
	texture.set_image(image)
	
	return texture

func _create_pattern_collision_box(min_pos: Vector2, max_pos: Vector2, pattern_center_x: float, pattern_bottom_y: float, scale_factor: float, pattern: Dictionary):
	# Calculate bounding box size for the entire pattern
	var pattern_width = (max_pos.x - min_pos.x + 1) * scale_factor
	var pattern_height = (max_pos.y - min_pos.y + 1) * scale_factor
	var pattern_depth = scale_factor  # 1 block deep
	
	# Calculate collision box center position to match visual pattern positioning
	# Visual cells use: (-relative_y * scale_factor) + (0.5 * scale_factor)
	# For a pattern with min_pos.y to max_pos.y range:
	# - Bottom cell (at max_pos.y) is at y = 0.5 * scale_factor  
	# - Top cell (at min_pos.y) is at y = (max_pos.y - min_pos.y) * scale_factor + 0.5 * scale_factor
	var pattern_bottom_world_y = 0.5 * scale_factor
	var pattern_top_world_y = pattern_height - (0.5 * scale_factor)
	var collision_center_y = pattern_height / 2
	
	# Replace the character's collision shape with pattern-sized box
	if collision_shape_3d and collision_shape_3d.shape:
		var box_shape = BoxShape3D.new()
		box_shape.size = Vector3(pattern_width, pattern_height, pattern_depth)
		collision_shape_3d.shape = box_shape
		
		collision_shape_3d.position = Vector3(0, collision_center_y, 0)
		
	
	# Create collision visualization showing only empty spaces
	_create_collision_negative_space(min_pos, max_pos, pattern, pattern_center_x, pattern_bottom_y, scale_factor, Vector3(0, collision_center_y, 0))

func _create_visual_collision_box(width: float, height: float, depth: float, pos: Vector3):
	# Create a container for multiple thin boxes that form a hollow outline
	pattern_collision_box = Node3D.new()
	pattern_collision_box.position = pos
	
	# Create 12 thin boxes to form the edges of a wireframe cube
	var edge_thickness = 0.02
	var edges = [
		# Bottom edges
		Vector3(width, edge_thickness, edge_thickness), Vector3(0, -depth/2, -height/2),  # Bottom front
		Vector3(width, edge_thickness, edge_thickness), Vector3(0, depth/2, -height/2),   # Bottom back
		Vector3(edge_thickness, edge_thickness, depth), Vector3(-width/2, 0, -height/2), # Bottom left
		Vector3(edge_thickness, edge_thickness, depth), Vector3(width/2, 0, -height/2),  # Bottom right
		# Top edges
		Vector3(width, edge_thickness, edge_thickness), Vector3(0, -depth/2, height/2),   # Top front
		Vector3(width, edge_thickness, edge_thickness), Vector3(0, depth/2, height/2),    # Top back
		Vector3(edge_thickness, edge_thickness, depth), Vector3(-width/2, 0, height/2),  # Top left
		Vector3(edge_thickness, edge_thickness, depth), Vector3(width/2, 0, height/2),   # Top right
		# Vertical edges
		Vector3(edge_thickness, depth, edge_thickness), Vector3(-width/2, 0, 0),  # Left front
		Vector3(edge_thickness, depth, edge_thickness), Vector3(width/2, 0, 0),   # Right front
		Vector3(edge_thickness, depth, edge_thickness), Vector3(-width/2, 0, 0),  # Left back
		Vector3(edge_thickness, depth, edge_thickness), Vector3(width/2, 0, 0),   # Right back
	]
	
	# Create material for edges
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.0, 0.0, 0.8)
	material.flags_unshaded = true
	
	# Create edge meshes (simplified to just corners for now)
	for i in range(0, min(edges.size(), 8), 2):
		var edge_mesh = MeshInstance3D.new()
		var box_mesh = BoxMesh.new()
		box_mesh.size = edges[i]
		edge_mesh.mesh = box_mesh
		edge_mesh.material_override = material
		edge_mesh.position = edges[i + 1]
		pattern_collision_box.add_child(edge_mesh)
	
	pattern_container.add_child(pattern_collision_box)
	

func _create_collision_corners(width: float, height: float, depth: float, pos: Vector3):
	# Create small corner indicators that show collision bounds without z-fighting
	pattern_collision_box = Node3D.new()
	pattern_collision_box.position = pos
	
	var corner_size = 0.05
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.0, 0.0, 0.9)
	material.flags_unshaded = true
	
	# Create 8 corner indicators
	var corners = [
		Vector3(-width/2, -height/2, -depth/2),  # Bottom corners
		Vector3(width/2, -height/2, -depth/2),
		Vector3(-width/2, -height/2, depth/2),
		Vector3(width/2, -height/2, depth/2),
		Vector3(-width/2, height/2, -depth/2),   # Top corners
		Vector3(width/2, height/2, -depth/2),
		Vector3(-width/2, height/2, depth/2),
		Vector3(width/2, height/2, depth/2),
	]
	
	for corner_pos in corners:
		var corner = MeshInstance3D.new()
		var sphere_mesh = SphereMesh.new()
		sphere_mesh.radius = corner_size
		sphere_mesh.height = corner_size * 2
		corner.mesh = sphere_mesh
		corner.material_override = material
		corner.position = corner_pos
		pattern_collision_box.add_child(corner)
	
	pattern_container.add_child(pattern_collision_box)

func _create_collision_negative_space(min_pos: Vector2, max_pos: Vector2, pattern: Dictionary, pattern_center_x: float, pattern_bottom_y: float, scale_factor: float, collision_pos: Vector3):
	# Create collision visualization that fills empty spaces in the bounding box
	pattern_collision_box = Node3D.new()
	# Don't offset the container - position each cell individually like the pattern cells
	
	# Create semi-transparent material for empty spaces
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.0, 0.0, 0.3)  # Semi-transparent red
	material.flags_transparent = true
	material.flags_unshaded = true
	
	# Iterate through every position in the bounding box
	for x in range(int(min_pos.x), int(max_pos.x) + 1):
		for y in range(int(min_pos.y), int(max_pos.y) + 1):
			var cell_pos = Vector2(x, y)
			
			# Only create a cube if this position is NOT in the pattern
			if not pattern.has(cell_pos) or pattern[cell_pos] != true:
				var empty_cell = MeshInstance3D.new()
				var box_mesh = BoxMesh.new()
				box_mesh.size = Vector3.ONE  # Standard 1x1x1 box, same as pattern cells
				empty_cell.mesh = box_mesh
				empty_cell.material_override = material
				
				# Position relative to pattern center (same logic as pattern cells)
				var relative_x = cell_pos.x - pattern_center_x
				var relative_y = cell_pos.y - pattern_bottom_y
				var world_pos = Vector3(relative_x * scale_factor, (-relative_y * scale_factor) + (0.5 * scale_factor), 0)
				
				empty_cell.position = world_pos
				empty_cell.scale = Vector3.ONE * scale_factor  # Same scaling as pattern cells
				pattern_collision_box.add_child(empty_cell)
	
	pattern_container.add_child(pattern_collision_box)

func _sync_pattern_rotation():
	# Sync the actual collision shape (physics) with camera rotation
	if collision_shape_3d:
		var camera_transform = get_camera_transform()
		# Store original position
		var original_pos = collision_shape_3d.position
		# Apply camera rotation to the collision shape
		collision_shape_3d.transform.basis = camera_transform.basis
		# Restore position (rotation might have changed it)
		collision_shape_3d.position = original_pos


func _make_player_translucent():
	# Make the default model translucent
	if godot_plush_skin:
		_make_node_translucent(godot_plush_skin, 0.3)
	
	# Make pattern model translucent if it exists
	if pattern_container:
		_make_node_translucent(pattern_container, 0.3)

func _make_node_translucent(node: Node, alpha: float):
	
	# Handle MeshInstance3D with dual mesh approach for shadows + transparency
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		
		# Create shadow-only duplicate
		var shadow_mesh = mesh_instance.duplicate()
		shadow_mesh.name = mesh_instance.name + "_Shadow"
		
		# Shadow mesh: opaque black material, shadows only
		var shadow_mat = StandardMaterial3D.new()
		shadow_mat.albedo_color = Color.BLACK
		shadow_mat.flags_unshaded = true
		shadow_mat.flags_do_not_cast_shadows = false
		shadow_mat.flags_use_point_size = false
		shadow_mat.flags_world_space_normals = false
		shadow_mat.flags_fixed_size = false
		shadow_mat.flags_billboard_keep_scale = false
		shadow_mat.no_depth_test = false
		shadow_mat.flags_use_shadow_to_opacity = false
		shadow_mat.flags_transparent = false
		# Make it invisible but still cast shadows
		shadow_mat.flags_albedo_from_vertex_color = false
		shadow_mesh.material_override = shadow_mat
		shadow_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		
		# Original mesh: transparent material, no shadows
		var transparent_mat = StandardMaterial3D.new()
		transparent_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		transparent_mat.albedo_color = Color(0.2, 0.2, 0.2, alpha)
		transparent_mat.flags_do_not_cast_shadows = true
		mesh_instance.material_override = transparent_mat
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		# Add shadow mesh as sibling
		mesh_instance.get_parent().add_child(shadow_mesh)
	
	# Handle Sprite3D with modulation  
	elif node is Sprite3D:
		var sprite = node as Sprite3D
		sprite.modulate.a = alpha
	
	# Check children
	for child in node.get_children():
		_make_node_translucent(child, alpha)

func clear_pattern_model():
	# Remove pattern container (which includes all pattern cells and visual collision box)
	if pattern_container and is_instance_valid(pattern_container):
		pattern_container.queue_free()
		pattern_container = null
	
	pattern_model_cells.clear()
	pattern_collision_box = null
	
	# Reset collision shape to default capsule
	if collision_shape_3d:
		var capsule_shape = CapsuleShape3D.new()
		capsule_shape.radius = 0.5
		capsule_shape.height = 2.0
		collision_shape_3d.shape = capsule_shape
		collision_shape_3d.position = Vector3.ZERO
	
	# Show default model
	if godot_plush_skin:
		godot_plush_skin.visible = true

# Health management functions
func take_damage(damage: float, source_player_id: int = -1):	
	if is_dead:
		return  # Can't damage dead players
	
	current_health -= damage
	current_health = max(0.0, current_health)  # Clamp to 0
	
	print("Player " + str(player_peer_id) + " health: " + str(int(current_health)) + "/" + str(int(max_health)))
	
	# Emit health changed signal
	health_changed.emit(current_health, max_health)
	
	# Check if player died
	if current_health <= 0.0 and not is_dead:
		print("DEBUG: Player died!")
		_handle_death(source_player_id)
	
	# Sync health across network for remote players
	if multiplayer.is_server() and not is_remote:
		_sync_health.rpc(current_health, is_dead)

@rpc("any_peer", "call_local")
func _sync_health(new_health: float, dead: bool):
	current_health = new_health
	is_dead = dead
	health_changed.emit(current_health, max_health)

func heal(amount: float):
	if is_dead:
		return  # Can't heal dead players
	
	current_health += amount
	current_health = min(max_health, current_health)  # Clamp to max
	
	# Emit health changed signal
	health_changed.emit(current_health, max_health)
	
	# Sync health across network
	if multiplayer.is_server() and not is_remote:
		_sync_health.rpc(current_health, is_dead)

func _handle_death(killer_id: int = -1):
	if is_dead:
		return
	
	is_dead = true
	death_time = Time.get_unix_time_from_system()
	respawn_timer = respawn_delay
	
	# Force ragdoll on death
	if godot_plush_skin:
		godot_plush_skin.ragdoll = true
	
	# Transition to ragdoll state if not already there
	if state_machine and state_machine.curr_state_name != "Ragdoll":
		# Find the ragdoll state and trigger transition
		var ragdoll_state = state_machine.states.get("ragdollstate")
		if ragdoll_state:
			state_machine.on_state_child_transition(state_machine.curr_state, "ragdollstate")
	
	# Emit death signal
	player_died.emit(self)
	
	print("Player " + str(player_peer_id) + " died" + ((" (killed by " + str(killer_id) + ")") if killer_id != -1 else ""))

func _handle_respawn():
	if not is_dead:
		return
	
	# Reset health
	current_health = max_health
	is_dead = false
	respawn_timer = 0.0
	
	# Exit ragdoll state
	if godot_plush_skin:
		godot_plush_skin.ragdoll = false
	
	# Move to a safe respawn position (could be enhanced with spawn points)
	_respawn_at_safe_location()
	
	# Reset velocity
	velocity = Vector3.ZERO
	
	# Emit respawn signal
	player_respawned.emit(self)
	health_changed.emit(current_health, max_health)
	
	print("Player " + str(player_peer_id) + " respawned")

func _respawn_at_safe_location():
	# Simple respawn logic - move up and slightly randomize position
	position.y += 5.0  # Move up to avoid being stuck in ground
	position.x += randf_range(-2.0, 2.0)  # Small random offset
	position.z += randf_range(-2.0, 2.0)

func get_health_percentage() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0

func _prevent_bullet_self_collision(new_bullet: RigidBody3D, owner_id: int):
	# Find all existing bullets from the same player and prevent collision between them
	var game_3d = Game3D
	if not game_3d:
		return
	
	var bullets_found = 0
	for child in game_3d.get_children():
		if child is RigidBody3D and child != new_bullet:
			# Check if this is a bullet from the same player
			if child.has_meta("owner_peer_id") and child.get_meta("owner_peer_id") == owner_id:
				# Add collision exception between the new bullet and existing bullet
				new_bullet.add_collision_exception_with(child)
				child.add_collision_exception_with(new_bullet)
				bullets_found += 1
	
	if bullets_found > 0:
		print("DEBUG: Added collision exceptions between new bullet and " + str(bullets_found) + " existing bullets from player " + str(owner_id))
