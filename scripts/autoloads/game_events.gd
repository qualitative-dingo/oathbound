extends Node
## Global event bus. Systems communicate through signals here
## instead of holding direct references to each other.

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
