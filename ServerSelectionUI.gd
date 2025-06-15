extends Control

signal server_selected(ip_address: String)
signal cancelled

@onready var server_list = $Panel/VBoxContainer/ScrollContainer/ServerList
@onready var connect_button = $Panel/VBoxContainer/ButtonContainer/ConnectButton
@onready var refresh_button = $Panel/VBoxContainer/ButtonContainer/RefreshButton
@onready var cancel_button = $Panel/VBoxContainer/ButtonContainer/CancelButton
@onready var show_log_button = $Panel/VBoxContainer/ButtonContainer/ShowLogButton
@onready var scanning_label = $Panel/VBoxContainer/ScanningLabel

var selected_server: String = ""
var server_buttons: Array = []
var scan_log_dialog: AcceptDialog = null
var scan_log_text: RichTextLabel = null
var scan_cancelled: bool = false

func _ready():
	# Connect button signals
	connect_button.pressed.connect(_on_connect_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	show_log_button.pressed.connect(_on_show_log_pressed)

func show_servers(servers: Array):
	_clear_server_list()
	scanning_label.visible = false
	
	if servers.is_empty():
		var no_servers_label = Label.new()
		no_servers_label.text = "No servers found on LAN"
		no_servers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		server_list.add_child(no_servers_label)
	else:
		for i in range(servers.size()):
			var server_ip = servers[i]
			add_server_to_list(server_ip)

func add_server_to_list(server_ip: String):
	# Remove "no servers" message if it exists
	for child in server_list.get_children():
		if child is Label and child.text == "No servers found on LAN":
			child.queue_free()
	
	# Add the new server button
	var button = Button.new()
	var server_number = server_buttons.size() + 1
	button.text = "Server " + str(server_number) + ": " + server_ip + ":3006"
	button.toggle_mode = true
	button.button_group = _get_or_create_button_group()
	button.pressed.connect(_on_server_button_pressed.bind(server_ip, button))
	
	server_list.add_child(button)
	server_buttons.append(button)

func start_scanning():
	_clear_server_list()
	clear_scan_log()  # Clear previous scan log
	scan_cancelled = false  # Reset cancellation flag
	scanning_label.visible = true
	scanning_label.text = "Scanning for servers..."
	refresh_button.disabled = true

func update_scanning_status(ip_address: String, status: String):
	if scanning_label.visible:
		match status:
			"TESTING":
				scanning_label.text = "Trying: " + ip_address
			"SUCCESS":
				scanning_label.text = "Found server at: " + ip_address
			"FAILED":
				scanning_label.text = "No server at: " + ip_address
			"SKIPPED":
				scanning_label.text = "Skipping: " + ip_address
			_:
				scanning_label.text = "Scanning for servers..."

func finish_scanning():
	scanning_label.visible = false
	refresh_button.disabled = false
	
	# Show "no servers" message if none were found
	if server_buttons.is_empty():
		var no_servers_label = Label.new()
		no_servers_label.text = "No servers found on LAN"
		no_servers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		server_list.add_child(no_servers_label)

func show_scanning():
	_clear_server_list()
	scanning_label.visible = true
	refresh_button.disabled = true

func hide_scanning():
	scanning_label.visible = false
	refresh_button.disabled = false

func _clear_server_list():
	for child in server_list.get_children():
		child.queue_free()
	server_buttons.clear()
	selected_server = ""
	connect_button.disabled = true

func _get_or_create_button_group() -> ButtonGroup:
	# Create a button group so only one server can be selected at a time
	var group = ButtonGroup.new()
	return group

func _on_server_button_pressed(ip_address: String, button: Button):
	if button.button_pressed:
		selected_server = ip_address
		connect_button.disabled = false
	else:
		selected_server = ""
		connect_button.disabled = true

func _on_connect_pressed():
	if selected_server != "":
		server_selected.emit(selected_server)

func _on_refresh_pressed():
	emit_signal("refresh_requested")

func _on_cancel_pressed():
	# If scanning is in progress, cancel it
	if scanning_label.visible:
		scan_cancelled = true
		scanning_label.text = "Scan cancelled by user"
		log_scan_attempt("SCAN", "CANCELLED by user")
		finish_scanning()
	
	cancelled.emit()

func is_scan_cancelled() -> bool:
	return scan_cancelled

func cancel_scan():
	scan_cancelled = true

# Add a signal for refresh requests
signal refresh_requested

var scan_log_entries: Array = []

func log_scan_attempt(ip_address: String, result: String):
	var timestamp = Time.get_datetime_string_from_system()
	var entry = "[" + timestamp + "] " + ip_address + " - " + result
	scan_log_entries.append(entry)
	
	# Update the modal in real-time if it's open
	_update_scan_log_display()

func clear_scan_log():
	scan_log_entries.clear()
	_update_scan_log_display()

func update_last_log_entry(ip_address: String, new_result: String):
	# Find and update the most recent entry for this IP
	for i in range(scan_log_entries.size() - 1, -1, -1):  # Search backwards
		var entry = scan_log_entries[i]
		if ip_address in entry:
			var timestamp = Time.get_datetime_string_from_system()
			scan_log_entries[i] = "[" + timestamp + "] " + ip_address + " - " + new_result
			_update_scan_log_display()
			break

func _on_show_log_pressed():
	_create_scan_log_dialog()

func _create_scan_log_dialog():
	if scan_log_dialog != null:
		scan_log_dialog.queue_free()
	
	# Create modal dialog
	scan_log_dialog = AcceptDialog.new()
	scan_log_dialog.title = "Scan Log"
	scan_log_dialog.size = Vector2i(600, 400)
	scan_log_dialog.unresizable = false
	
	# Create scrollable text area
	var scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	scan_log_text = RichTextLabel.new()
	scan_log_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scan_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scan_log_text.bbcode_enabled = true
	scan_log_text.scroll_following = true
	
	# Populate with scan log
	_update_scan_log_display()
	
	scroll_container.add_child(scan_log_text)
	scan_log_dialog.add_child(scroll_container)
	
	# Add to scene and show
	get_tree().current_scene.add_child(scan_log_dialog)
	scan_log_dialog.popup_centered()

func _update_scan_log_display():
	if scan_log_text == null:
		return
	
	var log_content = ""
	if scan_log_entries.is_empty():
		log_content = "[i]No scan performed yet[/i]"
	else:
		for entry in scan_log_entries:
			# Color code the results
			if "SUCCESS" in entry:
				log_content += "[color=green]" + entry + "[/color]\n"
			elif "FAILED" in entry or "TIMEOUT" in entry:
				log_content += "[color=red]" + entry + "[/color]\n"
			elif "TESTING" in entry:
				log_content += "[color=yellow]" + entry + "[/color]\n"
			else:
				log_content += entry + "\n"
	
	scan_log_text.text = log_content