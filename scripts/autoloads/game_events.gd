extends Node
## Global event bus. Systems communicate through signals here
## instead of holding direct references to each other.


var _debug_beacon: UDPServer

# ── Launch timing ────────────────────────────────────────────────────────────
# Wall-clock timestamp (microseconds) captured when the user presses Play in
# the main menu. Every major loading milestone prints its elapsed time relative
# to this so we can see the full "press play → interactive" breakdown in logs.
var launch_ts_us: int = 0

func launch_elapsed_ms() -> float:
	if launch_ts_us <= 0:
		return 0.0
	return (Time.get_ticks_usec() - launch_ts_us) / 1000.0

func _ready() -> void:
	_apply_debug_window_layout()


func _apply_debug_window_layout() -> void:
	if not OS.is_debug_build():
		return

	# Determine role: explicit arg or auto-detect via port binding.
	var role := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			role = "host"
		elif arg == "--client":
			role = "client"

	if role == "":
		# Try to bind a UDP beacon port. First instance wins → host (left).
		_debug_beacon = UDPServer.new()
		if _debug_beacon.listen(19050, "127.0.0.1") == OK:
			role = "host"
		else:
			role = "client"
			_debug_beacon = null

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
	# Bring this window to front after positioning
	DisplayServer.window_move_to_foreground()


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
signal player_respawned()

# --- Combat ---
signal creature_killed(creature_position: Vector3)

# --- Building ---
signal building_piece_placed(piece: Node3D)
signal building_piece_destroyed(piece: Node3D)

# --- World ---
signal day_night_changed(is_day: bool)
signal biome_entered(biome_name: StringName)
signal weather_changed(weather_id: int)
