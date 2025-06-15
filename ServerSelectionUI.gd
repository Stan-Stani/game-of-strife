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

# Persistent server list data
var saved_servers: Dictionary = {}  # ip -> {last_seen: timestamp, verified: bool}
var current_network_id: String = ""
var save_file_path: String = "user://server_list.dat"
var scan_found_servers: Array = []  # Track servers found in current scan

func _ready():
	# Connect button signals
	connect_button.pressed.connect(_on_connect_pressed)
	refresh_button.pressed.connect(_on_refresh_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	show_log_button.pressed.connect(_on_show_log_pressed)
	
	# Load persistent server list
	_load_server_list()
	
	# Check if network has changed
	var network_id = _get_current_network_id()
	if current_network_id != network_id:
		print("Network changed from '" + current_network_id + "' to '" + network_id + "' - clearing saved servers")
		saved_servers.clear()
		current_network_id = network_id
		_save_server_list()
	
	# Load saved servers into UI
	_load_saved_servers_to_ui()

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

func add_server_to_list(server_ip: String, save_to_list: bool = true):
	# Remove "no servers" message if it exists
	for child in server_list.get_children():
		if child is Label and child.text == "No servers found on LAN":
			child.queue_free()
	
	# Check if server already exists in UI
	for button in server_buttons:
		if server_ip in button.text:
			return  # Server already in list
	
	# Add the new server button
	var button = Button.new()
	var server_number = server_buttons.size() + 1
	button.text = "Server " + str(server_number) + ": " + server_ip + ":3006"
	button.toggle_mode = true
	button.button_group = _get_or_create_button_group()
	button.pressed.connect(_on_server_button_pressed.bind(server_ip, button))
	
	server_list.add_child(button)
	server_buttons.append(button)
	
	# Save newly discovered servers and mark as found in scan
	if save_to_list:
		_add_server_to_saved_list(server_ip)
		_mark_server_found_in_scan(server_ip)
	else:
		# Even cached servers should be marked as "found" if they're still active
		_mark_server_found_in_scan(server_ip)

func start_scanning():
	# Don't clear server list - keep cached servers during scan
	clear_scan_log()  # Clear previous scan log
	scan_cancelled = false  # Reset cancellation flag
	scanning_label.visible = true
	scanning_label.text = "Scanning for servers..."
	refresh_button.disabled = true
	
	# Mark start of scan to track which servers were found
	_mark_scan_start()

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
		print("DEBUG: User clicked cancel - setting scan_cancelled flag")
		scan_cancelled = true
		scanning_label.text = "Scan cancelled by user"
		log_scan_attempt("SCAN", "CANCELLED by user")
		finish_scanning()
	
	cancelled.emit()

func is_scan_cancelled() -> bool:
	if scan_cancelled:
		print("DEBUG: is_scan_cancelled() returning true")
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

# Server persistence functions
func _get_current_network_id() -> String:
	# Create a network identifier based on local IP and common gateway IPs
	var ip_addresses = IP.get_local_addresses()
	var network_signature = ""
	
	# Look for private network IPs to create a signature
	for ip in ip_addresses:
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			var parts = ip.split(".")
			if parts.size() >= 3:
				# Use first 3 octets as network identifier
				network_signature = parts[0] + "." + parts[1] + "." + parts[2]
				break
	
	return network_signature

func _load_server_list():
	if FileAccess.file_exists(save_file_path):
		var file = FileAccess.open(save_file_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			
			var json = JSON.new()
			var parse_result = json.parse(json_string)
			if parse_result == OK:
				var data = json.data
				if data.has("servers"):
					saved_servers = data.get("servers", {})
				if data.has("network_id"):
					current_network_id = data.get("network_id", "")
				print("Loaded " + str(saved_servers.size()) + " saved servers for network: " + current_network_id)
			else:
				print("Failed to parse server list JSON")
		else:
			print("Failed to open server list file")
	else:
		print("No saved server list found")

func _save_server_list():
	var file = FileAccess.open(save_file_path, FileAccess.WRITE)
	if file:
		var data = {
			"servers": saved_servers,
			"network_id": current_network_id,
			"last_updated": Time.get_unix_time_from_system()
		}
		var json_string = JSON.stringify(data)
		file.store_string(json_string)
		file.close()
		print("Saved " + str(saved_servers.size()) + " servers to file")
	else:
		print("Failed to create server list save file")

func _load_saved_servers_to_ui():
	# Add saved servers to UI if we have any
	if not saved_servers.is_empty():
		print("Loading " + str(saved_servers.size()) + " saved servers to UI")
		for ip in saved_servers.keys():
			var server_data = saved_servers[ip]
			# Only show servers that were verified recently (within last week)
			var last_seen = server_data.get("last_seen", 0)
			var current_time = Time.get_unix_time_from_system()
			if current_time - last_seen < 604800:  # 7 days in seconds
				add_server_to_list(ip, false)  # Don't save again
		
		# Show a note about cached servers
		if server_buttons.size() > 0:
			var cached_label = Label.new()
			cached_label.text = "↑ Cached servers from previous sessions"
			cached_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cached_label.modulate = Color(0.7, 0.7, 0.7, 1.0)  # Dimmed text
			server_list.add_child(cached_label)

func _add_server_to_saved_list(ip: String, verified: bool = true):
	saved_servers[ip] = {
		"last_seen": Time.get_unix_time_from_system(),
		"verified": verified
	}
	_save_server_list()

func _remove_server_from_saved_list(ip: String):
	if saved_servers.has(ip):
		saved_servers.erase(ip)
		_save_server_list()
		print("Removed invalid server from saved list: " + ip)

func _mark_server_as_verified(ip: String):
	if saved_servers.has(ip):
		saved_servers[ip]["verified"] = true
		saved_servers[ip]["last_seen"] = Time.get_unix_time_from_system()
		_save_server_list()

func server_connection_failed(ip: String):
	# Called when a connection attempt fails - remove from saved list
	_remove_server_from_saved_list(ip)
	
	# Remove from current UI as well
	for i in range(server_buttons.size()):
		var button = server_buttons[i]
		if ip in button.text:
			button.queue_free()
			server_buttons.remove_at(i)
			break

func server_connection_succeeded(ip: String):
	# Called when connection succeeds - mark as verified
	_mark_server_as_verified(ip)

func _mark_scan_start():
	# Clear the list of servers found in this scan
	scan_found_servers.clear()

func _mark_server_found_in_scan(ip: String):
	# Track that this server was found in the current scan
	if not ip in scan_found_servers:
		scan_found_servers.append(ip)

func _complete_scan_and_cleanup():
	# Remove servers from saved list that weren't found in this scan
	var servers_to_remove = []
	
	for ip in saved_servers.keys():
		if not ip in scan_found_servers:
			# Server wasn't found in this scan - mark for removal
			servers_to_remove.append(ip)
	
	for ip in servers_to_remove:
		print("Server not found in scan, removing from saved list: " + ip)
		_remove_server_from_saved_list(ip)
		
		# Also remove from UI
		for i in range(server_buttons.size()):
			var button = server_buttons[i]
			if ip in button.text:
				button.queue_free()
				server_buttons.remove_at(i)
				break

func finish_scanning():
	scanning_label.visible = false
	refresh_button.disabled = false
	
	# Clean up servers that weren't found
	if not scan_cancelled:
		_complete_scan_and_cleanup()
	
	# Show "no servers" message if none were found
	if server_buttons.is_empty():
		var no_servers_label = Label.new()
		no_servers_label.text = "No servers found on LAN"
		no_servers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		server_list.add_child(no_servers_label)