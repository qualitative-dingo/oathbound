extends Node
## Global event bus. Systems communicate through signals here
## instead of holding direct references to each other.


func _ready() -> void:
	_apply_debug_window_layout()


func _apply_debug_window_layout() -> void:
	var args := OS.get_cmdline_user_args()
	var role := ""
	for arg in args:
		if arg == "--host":
			role = "host"
		elif arg == "--client":
			role = "client"
	if role == "":
		return
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
