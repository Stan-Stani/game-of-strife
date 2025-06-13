extends State

class_name IdleState

var state_name: String = "Idle"

var cR: CharacterBody3D

func enter(char_ref: CharacterBody3D):
	#pass play char reference
	cR = char_ref
	
	verifications()
	
func verifications():
	#manage the appliements that need to be set at the start of the state
	cR.godot_plush_skin.set_state("idle")
	cR.floor_snap_length = 1.0
	if cR.jump_cooldown > 0.0: cR.jump_cooldown = -1.0
	if cR.nb_jumps_in_air_allowed < cR.nb_jumps_in_air_allowed_ref: cR.nb_jumps_in_air_allowed = cR.nb_jumps_in_air_allowed_ref
	if cR.coyote_jump_cooldown < cR.coyote_jump_cooldown_ref: cR.coyote_jump_cooldown = cR.coyote_jump_cooldown_ref
	if cR.has_cut_jump: cR.has_cut_jump = false
	if cR.movement_dust.emitting: cR.movement_dust.emitting = false
	
func update(_delta: float):
	pass
	
func physics_update(delta: float):
	check_if_floor()
	
	cR.gravity_apply(delta)
	
	input_management()
	
	move(delta)
	
func check_if_floor():
	#manage the appliements and state transitions that needs to be sets/checked/performed
	#every time the play char pass through one of the following : floor-inair-onwall
	if !cR.is_on_floor() and !cR.is_on_wall():
		transitioned.emit(self, "InairState")
	if cR.is_on_floor():
		if cR.jump_buff_on:
			cR.buffered_jump = true
			cR.jump_buff_on = false
			transitioned.emit(self, "JumpState")
			
func input_management():
	#manage the state transitions depending on the actions inputs
	var jump_pressed = cR.get_input_pressed(cR.jumpAction) if cR.auto_jump else cR.get_input_just_pressed(cR.jumpAction)
	if jump_pressed:
		transitioned.emit(self, "JumpState")
		
	if cR.get_input_just_pressed(cR.runAction):
		if cR.walk_or_run == "WalkState": cR.walk_or_run = "RunState"
		elif cR.walk_or_run == "RunState": cR.walk_or_run = "WalkState"
		
	if cR.get_input_just_pressed("ragdoll"):
		if !cR.godot_plush_skin.ragdoll:
			transitioned.emit(self, "RagdollState")
	
func move(delta: float):
	#manage the character movement
	#get the move direction depending on the input
	var move_vector = get_move_vector()
	var camera_rotation = cR.get_camera_rotation()
	cR.move_dir = move_vector.rotated(-camera_rotation.y)
	
	if cR.move_dir and cR.is_on_floor():
		#transition to corresponding state
		transitioned.emit(self, cR.walk_or_run)
	else:
		#apply smooth stop 
		cR.velocity.x = lerp(cR.velocity.x, 0.0, cR.move_deccel * delta)
		cR.velocity.z = lerp(cR.velocity.z, 0.0, cR.move_deccel * delta)

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
