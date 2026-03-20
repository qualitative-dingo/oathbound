extends Node
## Global event bus. Systems communicate through signals here
## instead of holding direct references to each other.


const _LOCK_PATH := "user://debug_instance.lock"

func _ready() -> void:
	_apply_debug_window_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		# Clean up lock file when this instance exits
		if FileAccess.file_exists(_LOCK_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(_LOCK_PATH))


func _apply_debug_window_layout() -> void:
	if not OS.is_debug_build():
		return

	# Determine role: explicit arg, or auto-detect via lock file
	var role := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			role = "host"
		elif arg == "--client":
			role = "client"

	if role == "":
		# First instance creates the lock → host (left). Second sees it → client (right).
		if FileAccess.file_exists(_LOCK_PATH):
			var f := FileAccess.open(_LOCK_PATH, FileAccess.READ)
			var ts := float(f.get_as_text().strip_edges()) if f else 0.0
			# Stale lock (>30s old) means previous session crashed — treat as host
			if Time.get_unix_time_from_system() - ts > 30.0:
				role = "host"
			else:
				role = "client"
		else:
			role = "host"

	if role == "host":
		var f := FileAccess.open(_LOCK_PATH, FileAccess.WRITE)
		if f:
			f.store_string(str(Time.get_unix_time_from_system()))

	var screen_size := DisplayServer.screen_get_size()
	var half_w := int(screen_size.x / 2)
	var win_h := screen_size.y - 50
	DisplayServer.window_set_size(Vector2i(half_w, win_h))
	if role == "host":
		DisplayServer.window_set_position(Vector2i(0, 25))
		DisplayServer.window_set_title("Oathbound [HOST]")
	else:
		DisplayServer.window_set_position(Vector2i(half_w, 25))
		DisplayServer.window_set_title("Oathbound [CLIENT]")


# --- Interaction ---
signal interaction_focus_changed(interactable: Node3D)
signal interaction_focus_lost()
signal interaction_performed(interactable: Node3D, player: Node3D)

# --- Inventory ---
signal item_picked_up(item_id: StringName, amount: int)
signal item_dropped(item_id: StringName, amount: int)
signal inventory_changed()

# --- Player ---
signal player_health_changed(current: float, maximum: float)
signal player_stamina_changed(current: float, maximum: float)
signal player_died()

# --- Building ---
signal building_piece_placed(piece: Node3D)
signal building_piece_destroyed(piece: Node3D)

# --- World ---
signal day_night_changed(is_day: bool)
signal biome_entered(biome_name: StringName)
signal weather_changed(weather_id: int)
