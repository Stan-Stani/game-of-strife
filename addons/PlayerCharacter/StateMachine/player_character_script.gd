extends CharacterBody3D

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
@export var follow_cam_pos_when_aimed : bool = false

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
var pattern_collision_shapes: Array[CollisionShape3D] = []

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
	
	#set char model audios effects
	godot_plush_skin.footstep.connect(func(intensity : float = 1.0):
		foot_step_audio.volume_db = linear_to_db(intensity)
		foot_step_audio.play()
		)
		
func _process(delta: float):
	modify_model_orientation(delta)
	
	display_properties()
	
func _physics_process(_delta : float):
	modify_physics_properties()
	
	if !is_remote and is_multiplayer_authority():
		# Collect and send input data
		var input_data = collect_input_data()
		Game3D.receive_player_input.rpc(multiplayer.get_unique_id(), input_data)
	
	move_and_slide()
	
	# Handle shooting with cooldown and just_pressed requirement
	if get_input_just_pressed(shootAction):
		var current_timestamp = Time.get_unix_time_from_system()
		
		if current_timestamp - last_shoot_time >= shoot_cooldown_time:
			print("bang")
			last_shoot_time = current_timestamp
			var camera_transform = get_camera_transform()
			
			# Get the pattern for this specific player character (based on which peer they represent)
			var pattern_to_shoot = Game3D.get_player_pattern(player_peer_id)
			print("Player character representing peer " + str(player_peer_id) + " (remote: " + str(is_remote) + ") shooting pattern with " + str(pattern_to_shoot.size()) + " cells")
			
			for cellPos in pattern_to_shoot:
				if pattern_to_shoot[cellPos] == true:
					var cell_3d: RigidBody3D = Cell3D.instantiate()
					var position_3d = Vector3(cellPos.x, -cellPos.y, 0)
					cell_3d.position = position_3d + self.position + (camera_transform.basis.z * -5)
					cell_3d.add_constant_central_force(camera_transform.basis.z * -50)
					Game3D.add_child(cell_3d)

	
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
		#rotate the model on the y axis
		visual_root.rotation.y = rotate_toward(visual_root.rotation.y, dir_target_angle, model_rot_speed * delta)
	
	#free mode (the model orientation is independant to the camera one)
	if (!cam_aimed or !follow_cam_pos_when_aimed) and move_dir != Vector2.ZERO:
		#get char move direction
		dir_target_angle = -move_dir.orthogonal().angle()
		#rotate the model on the y axis
		visual_root.rotation.y = rotate_toward(visual_root.rotation.y, dir_target_angle, model_rot_speed * delta)
		
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
	print("Creating pattern model for peer " + str(player_peer_id) + " with " + str(pattern.size()) + " cells")
	
	if pattern.is_empty():
		print("No pattern available, keeping default model")
		return
	
	# Hide the default model and collision
	if godot_plush_skin:
		godot_plush_skin.visible = false
	
	# Keep the original collision for movement, but make it invisible
	# The pattern collision shapes will handle hitbox detection
	
	# Calculate pattern bounds for centering
	var min_pos = Vector2(INF, INF)
	var max_pos = Vector2(-INF, -INF)
	
	for cell_pos in pattern:
		if pattern[cell_pos] == true:
			min_pos.x = min(min_pos.x, cell_pos.x)
			min_pos.y = min(min_pos.y, cell_pos.y)
			max_pos.x = max(max_pos.x, cell_pos.x)
			max_pos.y = max(max_pos.y, cell_pos.y)
	
	var pattern_center_x = (min_pos.x + max_pos.x) / 2.0
	var pattern_bottom_y = max_pos.y  # Bottom of pattern (highest Y value in 2D)
	var pattern_size = max_pos - min_pos
	
	# Scale factor to make character appropriately sized (roughly 2 units tall)
	var scale_factor = 0.5  # Adjust this to make character bigger/smaller
	
	# Create static visual cells for the pattern (no physics)
	for cell_pos in pattern:
		if pattern[cell_pos] == true:
			# Create a static visual cell instead of physics-enabled Cell3D
			var static_cell = _create_static_cell()
			
			# Position relative to pattern center horizontally, but bottom-aligned vertically
			var relative_x = cell_pos.x - pattern_center_x
			var relative_y = cell_pos.y - pattern_bottom_y  # Offset from bottom
			# Add 0.5 to lift the bottom cells so their bottom face sits on the floor
			var world_pos = Vector3(relative_x * scale_factor, (-relative_y * scale_factor) + (0.5 * scale_factor), 0)
			
			static_cell.position = world_pos
			static_cell.scale = Vector3.ONE * scale_factor
			
			# Add to visual root
			visual_root.add_child(static_cell)
			pattern_model_cells.append(static_cell)
			
			# Create individual collision shape for this cell
			var collision_shape = CollisionShape3D.new()
			var box_shape = BoxShape3D.new()
			box_shape.size = Vector3.ONE * scale_factor
			collision_shape.shape = box_shape
			collision_shape.position = world_pos
			
			# Add collision shape to the character body
			add_child(collision_shape)
			pattern_collision_shapes.append(collision_shape)
			
			print("Added pattern cell and collision at " + str(world_pos))

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

func clear_pattern_model():
	# Remove existing pattern cells
	for cell in pattern_model_cells:
		if cell and is_instance_valid(cell):
			cell.queue_free()
	pattern_model_cells.clear()
	
	# Remove pattern collision shapes
	for collision_shape in pattern_collision_shapes:
		if collision_shape and is_instance_valid(collision_shape):
			collision_shape.queue_free()
	pattern_collision_shapes.clear()
	
	# Show default model
	if godot_plush_skin:
		godot_plush_skin.visible = true
