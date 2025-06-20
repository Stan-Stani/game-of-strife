extends State

class_name WalkState

var state_name : String = "Walk"

var cR : CharacterBody3D

func enter(char_ref : CharacterBody3D):
	cR = char_ref
	
	verifications()
	
func verifications():
	cR.godot_plush_skin.set_state("walk")
	cR.move_speed = cR.walk_speed
	cR.move_accel = cR.walk_accel
	cR.move_deccel = cR.walk_deccel
	
	cR.floor_snap_length = 1.0
	if cR.jump_cooldown > 0.0: cR.jump_cooldown = -1.0
	if cR.nb_jumps_in_air_allowed < cR.nb_jumps_in_air_allowed_ref: cR.nb_jumps_in_air_allowed = cR.nb_jumps_in_air_allowed_ref
	if cR.coyote_jump_cooldown < cR.coyote_jump_cooldown_ref: cR.coyote_jump_cooldown = cR.coyote_jump_cooldown_ref
	if cR.has_cut_jump: cR.has_cut_jump = false
	if cR.movement_dust.emitting: cR.movement_dust.emitting = false
	
func update(_delta : float):
	pass
	
func physics_update(delta : float):
	check_if_floor()
	
	cR.gravity_apply(delta)
	
	input_management()
	
	move(delta)
	
func check_if_floor():
	if !cR.is_on_floor() and !cR.is_on_wall():
		if cR.velocity.y < 0.0:
			transitioned.emit(self, "InairState")
			
	if cR.is_on_floor():
		if cR.jump_buff_on:
			#apply jump buffering
			cR.buffered_jump = true
			cR.jump_buff_on = false
			transitioned.emit(self, "JumpState")
			
func input_management():
	var jump_pressed = cR.get_input_pressed(cR.jumpAction) if cR.auto_jump else cR.get_input_just_pressed(cR.jumpAction)
	if jump_pressed:
		transitioned.emit(self, "JumpState")
		
	if cR.get_input_just_pressed(cR.runAction):
		cR.walk_or_run = "RunState"
		transitioned.emit(self, "RunState")
		
	if cR.get_input_just_pressed("ragdoll"):
		if !cR.godot_plush_skin.ragdoll:
			transitioned.emit(self, "RagdollState")
		
func move(delta : float):
	var move_vector = get_move_vector()
	var camera_rotation = cR.get_camera_rotation()
	cR.move_dir = move_vector.rotated(-camera_rotation.y)
	
	if cR.move_dir and cR.is_on_floor():
		#apply smooth move
		cR.velocity.x = lerp(cR.velocity.x, cR.move_dir.x * cR.move_speed, cR.move_accel * delta)
		cR.velocity.z = lerp(cR.velocity.z, cR.move_dir.y * cR.move_speed, cR.move_accel * delta)
	else:
		transitioned.emit(self, "IdleState")

func get_move_vector() -> Vector2:
	var move_vector = Vector2.ZERO
	if cR.get_input_pressed(cR.moveLeftAction):
		move_vector.x -= 1.0
	if cR.get_input_pressed(cR.moveRightAction):
		move_vector.x += 1.0
	if cR.get_input_pressed(cR.moveForwardAction):
		move_vector.y -= 1.0
	if cR.get_input_pressed(cR.moveBackwardAction):
		move_vector.y += 1.0
	return move_vector.normalized()
