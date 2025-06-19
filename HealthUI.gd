extends Control

var health_bar: ProgressBar
var health_label: Label
var respawn_label: Label
var player_character: CharacterBody3D = null

func _ready():
	# Create UI programmatically to avoid .tscn loading issues
	_create_ui_elements()
	
	# Find the local player character
	call_deferred("_find_player_character")

func _create_ui_elements():
	print("HealthUI: Creating UI elements programmatically")
	
	# Create health container
	var health_container = VBoxContainer.new()
	health_container.name = "HealthContainer"
	health_container.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	health_container.position = Vector2(20, -100)
	health_container.size = Vector2(280, 80)
	add_child(health_container)
	
	# Create health label
	health_label = Label.new()
	health_label.name = "HealthLabel"
	health_label.text = "100/100"
	health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	health_container.add_child(health_label)
	
	# Create health bar
	health_bar = ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.max_value = 100.0
	health_bar.value = 100.0
	health_bar.show_percentage = false
	health_bar.custom_minimum_size = Vector2(250, 30)
	health_container.add_child(health_bar)
	
	# Create respawn label
	respawn_label = Label.new()
	respawn_label.name = "RespawnLabel"
	respawn_label.text = "Respawning in: 3"
	respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	respawn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	respawn_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	respawn_label.position = Vector2(-100, -25)
	respawn_label.size = Vector2(200, 50)
	respawn_label.visible = false
	add_child(respawn_label)
	
	print("HealthUI: UI elements created successfully")

func _find_player_character():
	# Try finding the local player by looking for it in Game3D
	var game_3d = get_node("/root/Game3D")
	if game_3d:
		# Look for Player node first
		var player = game_3d.get_node_or_null("Player")
		if player and player.has_method("take_damage"):
			_connect_to_player(player)
			return
		
		# Look for LocalPlayer_* pattern
		for child in game_3d.get_children():
			if child.name.begins_with("LocalPlayer_") and child.has_method("take_damage"):
				_connect_to_player(child)
				return
	
	# Try again in a bit
	print("HealthUI: Player not found, retrying...")
	await get_tree().create_timer(0.5).timeout
	_find_player_character()

func _connect_to_player(player):
	player_character = player
	print("HealthUI: Connected to player " + str(player.name))
	
	# Connect to health signals
	if player.has_signal("health_changed"):
		player.health_changed.connect(_on_health_changed)
	
	# Update initial display
	_update_health_display(player.current_health, player.max_health)

func _on_health_changed(current_health: float, max_health: float):
	_update_health_display(current_health, max_health)

func _update_health_display(current_health: float, max_health: float):
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
		
		# Color based on health percentage
		var health_percent = current_health / max_health if max_health > 0 else 0
		if health_percent > 0.75:
			health_bar.modulate = Color.GREEN
		elif health_percent > 0.25:
			health_bar.modulate = Color.YELLOW
		else:
			health_bar.modulate = Color.RED
	
	if health_label:
		health_label.text = str(int(current_health)) + "/" + str(int(max_health))

func _process(_delta):
	# Update respawn timer and pattern selection status
	if player_character and player_character.is_dead:
		# Check if player is in death menu or pattern selection mode
		var in_death_menu = player_character.has_meta("in_death_menu") and player_character.get_meta("in_death_menu")
		var in_pattern_selection = player_character.has_meta("in_pattern_selection") and player_character.get_meta("in_pattern_selection")
		
		if in_pattern_selection:
			if respawn_label:
				respawn_label.text = "In Pattern Selection"
				respawn_label.visible = true
		elif in_death_menu:
			if respawn_label:
				respawn_label.text = "Choose Respawn Option"
				respawn_label.visible = true
		elif respawn_label and player_character.respawn_timer > 0:
			respawn_label.text = "Respawning in: " + str(int(player_character.respawn_timer + 1))
			respawn_label.visible = true
		elif respawn_label:
			respawn_label.visible = false
	elif respawn_label:
		respawn_label.visible = false