extends Node

const _DEBUG_LOG := false

## Handles saving and loading game state: player data, inventory, world info.

const SAVE_DIR := "user://saves/"
const CHARACTERS_FILE := "user://characters.json"
const SETTINGS_FILE := "user://settings.json"
const AUTOSAVE_INTERVAL := 10.0

var current_character: Dictionary = {}
var current_world: Dictionary = {}

var render_distance: int = 2
var saturation_boost: float = 1.0  # 0.5–2.0 multiplier applied on top of day/night curve

var _autosave_timer := 0.0
var _game_active := false
var _settings_loaded := false
var _session_start_time := 0.0


func _ready() -> void:
	_ensure_save_dir()
	load_and_apply_settings()


func save_settings() -> void:
	var music_idx := AudioServer.get_bus_index(&"Music")
	var sfx_idx := AudioServer.get_bus_index(&"SFX")
	var data := {
		"music_volume": db_to_linear(AudioServer.get_bus_volume_db(music_idx)) if music_idx != -1 else 0.05,
		"sfx_volume": db_to_linear(AudioServer.get_bus_volume_db(sfx_idx)) if sfx_idx != -1 else 0.07,
		"window_mode": get_window().mode,
		"window_width": DisplayServer.window_get_size().x,
		"window_height": DisplayServer.window_get_size().y,
		"render_distance": render_distance,
		"saturation_boost": saturation_boost,
	}
	var file := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))


func load_and_apply_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_FILE):
		return
	var file := FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	if not file:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data = json.data
	if data is not Dictionary:
		return

	_settings_loaded = true

	var music_vol: float = float(data.get("music_volume", 0.05))
	var sfx_vol: float = float(data.get("sfx_volume", 0.07))
	var music_idx := AudioServer.get_bus_index(&"Music")
	if music_idx != -1:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(music_vol))
	var sfx_idx := AudioServer.get_bus_index(&"SFX")
	if sfx_idx != -1:
		AudioServer.set_bus_volume_db(sfx_idx, linear_to_db(sfx_vol))

	var win_mode: int = int(data.get("window_mode", Window.MODE_MAXIMIZED))
	var win_w: int = int(data.get("window_width", 1920))
	var win_h: int = int(data.get("window_height", 1080))

	if win_mode in [Window.MODE_EXCLUSIVE_FULLSCREEN, Window.MODE_FULLSCREEN]:
		get_window().mode = win_mode
	else:
		get_window().mode = Window.MODE_WINDOWED
		get_window().borderless = false
		get_window().size = Vector2i(win_w, win_h)
		var screen_size := DisplayServer.screen_get_size()
		get_window().position = (screen_size - Vector2i(win_w, win_h)) / 2

	render_distance = clampi(int(data.get("render_distance", 2)), 1, 5)
	saturation_boost = clampf(float(data.get("saturation_boost", 1.0)), 0.5, 1.5)


func _process(delta: float) -> void:
	if not _game_active:
		return
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		_accumulate_play_time()
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			_save_client_inventory()
		else:
			save_game()


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


# ═══════════════════════════════════════════════════════════════════════════════
#  CHARACTER MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════════

func get_all_characters() -> Array:
	if not FileAccess.file_exists(CHARACTERS_FILE):
		return []
	var file := FileAccess.open(CHARACTERS_FILE, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return []
	var data = json.data
	if data is Array:
		return data
	return []


func save_characters(characters: Array) -> void:
	var file := FileAccess.open(CHARACTERS_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify(characters, "\t"))


func create_character(char_name: String) -> Dictionary:
	var characters := get_all_characters()
	var char_data := {
		"id": str(Time.get_unix_time_from_system()).replace(".", "_"),
		"name": char_name,
		"created": Time.get_datetime_string_from_system(),
	}
	characters.append(char_data)
	save_characters(characters)
	return char_data


func delete_character(char_id: String) -> void:
	var characters := get_all_characters()
	characters = characters.filter(func(c: Dictionary) -> bool: return str(c.get("id", "")) != char_id)
	save_characters(characters)
	var dir_path := SAVE_DIR + char_id + "/"
	if DirAccess.dir_exists_absolute(dir_path):
		var dir := DirAccess.open(dir_path)
		if dir:
			dir.list_dir_begin()
			var fname := dir.get_next()
			while fname != "":
				if not dir.current_is_dir():
					dir.remove(fname)
				fname = dir.get_next()
			dir.list_dir_end()
		DirAccess.remove_absolute(dir_path)


# ═══════════════════════════════════════════════════════════════════════════════
#  WORLD MANAGEMENT  (worlds are global — any character can enter any world)
# ═══════════════════════════════════════════════════════════════════════════════

const WORLDS_FILE := "user://worlds.json"

func get_all_worlds() -> Array:
	if not FileAccess.file_exists(WORLDS_FILE):
		return []
	var file := FileAccess.open(WORLDS_FILE, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return []
	var data = json.data
	if data is Array:
		return data
	return []


func save_worlds(worlds: Array) -> void:
	var file := FileAccess.open(WORLDS_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify(worlds, "\t"))


func create_world(world_name: String) -> Dictionary:
	var worlds := get_all_worlds()
	var seed_str := world_name + "_" + str(randi())
	var world_data := {
		"id": str(Time.get_unix_time_from_system()).replace(".", "_"),
		"name": world_name,
		"seed": seed_str,
		"created": Time.get_datetime_string_from_system(),
	}
	worlds.append(world_data)
	save_worlds(worlds)
	return world_data


func delete_world(world_id: String) -> void:
	var worlds := get_all_worlds()
	worlds = worlds.filter(func(w: Dictionary) -> bool: return str(w.get("id", "")) != world_id)
	save_worlds(worlds)


# ═══════════════════════════════════════════════════════════════════════════════
#  SAVE / LOAD GAME STATE
# ═══════════════════════════════════════════════════════════════════════════════

func start_game(character: Dictionary, world: Dictionary) -> void:
	current_character = character
	current_world = world
	_game_active = true
	_autosave_timer = 0.0
	_session_start_time = Time.get_unix_time_from_system()
	_update_character_last_played()


func _save_client_inventory() -> void:
	if current_character.is_empty() or current_world.is_empty():
		return
	var char_id: String = str(current_character.get("id", ""))
	var world_id: String = str(current_world.get("id", ""))
	var player := _get_player()
	var save_data := {
		"character": current_character,
		"world": current_world,
		"player": _serialize_player(player),
		"inventory": _serialize_inventory(),
		"timestamp": Time.get_datetime_string_from_system(),
	}
	var file := FileAccess.open(SAVE_DIR + char_id + "_" + world_id + ".json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data, "\t"))


func save_game() -> void:
	if current_character.is_empty() or current_world.is_empty():
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return

	var char_id: String = str(current_character.get("id", ""))
	var world_id: String = str(current_world.get("id", ""))

	var player := _get_player()
	var save_data := {
		"character": current_character,
		"world": current_world,
		"world_state": _serialize_world_state(),
		"player": _serialize_player(player),
		"inventory": _serialize_inventory(),
		"players": _serialize_all_players(char_id),
		"timestamp": Time.get_datetime_string_from_system(),
	}

	var file := FileAccess.open(SAVE_DIR + char_id + "_" + world_id + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data, "\t"))


func load_game() -> Dictionary:
	if current_character.is_empty() or current_world.is_empty():
		return {}

	var char_id: String = str(current_character.get("id", ""))
	var world_id: String = str(current_world.get("id", ""))
	var save_path := SAVE_DIR + char_id + "_" + world_id + ".json"

	if not FileAccess.file_exists(save_path):
		return {}

	var file := FileAccess.open(save_path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}
	var data = json.data
	if data is Dictionary:
		return data
	return {}


func apply_save_data(save_data: Dictionary) -> void:
	if save_data.is_empty():
		return

	# 5a: Apply world state (destroyed objects, placed buildings)
	if save_data.has("world_state"):
		_deserialize_world_state(save_data["world_state"])

	var player := _get_player()
	_deserialize_player(player, save_data.get("player", {}))
	_deserialize_inventory(save_data.get("inventory", {}))
	# Legacy: structures from scene (superseded by world_state when present)
	if not save_data.has("world_state") and save_data.has("structures"):
		_deserialize_structures(save_data.get("structures", []))


func stop_game() -> void:
	if _game_active:
		_accumulate_play_time()
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			_save_client_inventory()
		else:
			save_game()
		_update_character_last_played()
	_game_active = false
	current_character = {}
	current_world = {}


func _update_character_last_played() -> void:
	if current_character.is_empty():
		return
	var char_id: String = str(current_character.get("id", ""))
	var characters := get_all_characters()
	for i in characters.size():
		if str(characters[i].get("id", "")) == char_id:
			characters[i]["last_played"] = Time.get_unix_time_from_system()
			break
	save_characters(characters)


func _accumulate_play_time() -> void:
	if current_character.is_empty() or _session_start_time <= 0.0:
		return
	var now := Time.get_unix_time_from_system()
	var elapsed := now - _session_start_time
	_session_start_time = now
	if elapsed <= 0.0:
		return
	var char_id: String = str(current_character.get("id", ""))
	var characters := get_all_characters()
	for i in characters.size():
		if str(characters[i].get("id", "")) == char_id:
			var prev: float = float(characters[i].get("time_played_seconds", 0.0))
			characters[i]["time_played_seconds"] = prev + elapsed
			break
	save_characters(characters)


func _deferred_load_save() -> void:
	print("[LAUNCH→LOAD_SAVE] called since_launch=%.1fms" % GameEvents.launch_elapsed_ms())
	await get_tree().process_frame
	await get_tree().process_frame
	var _t_load_start := Time.get_ticks_usec()
	var save_data := load_game()
	var _t_load_end := Time.get_ticks_usec()

	# No save for this character+world combo — carry over inventory/stats from
	# the character's most recent save on any world so gear persists across worlds.
	var used_fallback := false
	if save_data.is_empty():
		var fallback := _load_latest_character_save()
		if not fallback.is_empty():
			save_data = {
				"inventory": fallback.get("inventory", {}),
				"player": _strip_position_from_player(fallback.get("player", {})),
			}
			used_fallback = true
	var _t_fallback := Time.get_ticks_usec()

	if not save_data.is_empty():
		apply_save_data(save_data)
	else:
		Inventory.give_starting_gear()
		GameEvents.inventory_changed.emit()
	var _t_apply := Time.get_ticks_usec()

	# Always start a session with full health (like Valheim)
	var player := _get_player()
	if player:
		var max_hp: float = float(player.get("max_health"))
		if max_hp > 0.0:
			player.set("current_health", max_hp)
			player.set("current_stamina", float(player.get("max_stamina")))
	print("[LAUNCH→LOAD_SAVE] done since_launch=%.1fms load_json=%.1fms fallback=%.1fms(used=%s) apply=%.1fms has_save=%s" % [
		GameEvents.launch_elapsed_ms(),
		(_t_load_end - _t_load_start) / 1000.0,
		(_t_fallback - _t_load_end) / 1000.0, str(used_fallback),
		(_t_apply - _t_fallback) / 1000.0,
		str(not save_data.is_empty())])


func _load_latest_character_save() -> Dictionary:
	var char_id: String = str(current_character.get("id", ""))
	if char_id.is_empty():
		return {}
	var dir := DirAccess.open(SAVE_DIR)
	if not dir:
		return {}
	var latest_data: Dictionary = {}
	var latest_time: String = ""
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.begins_with(char_id + "_") and fname.ends_with(".json"):
			var fpath := SAVE_DIR + fname
			var file := FileAccess.open(fpath, FileAccess.READ)
			if file:
				var json := JSON.new()
				if json.parse(file.get_as_text()) == OK:
					var data = json.data
					if data is Dictionary:
						var ts: String = str(data.get("timestamp", ""))
						if ts > latest_time:
							latest_time = ts
							latest_data = data
		fname = dir.get_next()
	dir.list_dir_end()
	return latest_data


func _strip_position_from_player(player_data: Dictionary) -> Dictionary:
	var result := player_data.duplicate()
	result.erase("position")
	result.erase("rotation_y")
	return result


func _get_player() -> Node:
	return get_tree().get_first_node_in_group(&"player")


func _serialize_player(player: Node) -> Dictionary:
	if not player:
		return {}
	var p := player as CharacterBody3D
	var wp := p.global_position
	var wgs := get_tree().get_nodes_in_group(&"world_generator")
	if not wgs.is_empty() and wgs[0].has_method(&"get_world_position"):
		wp = wgs[0].get_world_position(p)
	var map_markers_save: Array = []
	var raw_markers: Array = p.get("_map_markers") if "_map_markers" in p else []
	for m in raw_markers:
		map_markers_save.append({
			"id": str(m.get("id", "")),
			"pos": {"x": (m["pos"] as Vector3).x, "y": (m["pos"] as Vector3).y, "z": (m["pos"] as Vector3).z},
			"label": str(m.get("label", "")),
		})
	var learned_recipes_save: Array = []
	var raw_recipes: Array = p.get("_learned_build_recipes") if "_learned_build_recipes" in p else []
	for r in raw_recipes:
		learned_recipes_save.append(str(r))
	return {
		"position": {"x": wp.x, "y": wp.y, "z": wp.z},
		"rotation_y": p.rotation.y,
		"health": p.get("current_health"),
		"stamina": p.get("current_stamina"),
		"equipped_weapon": str(p.get("equipped_weapon")),
		"selected_slot": p.get("_selected_slot"),
		"base_strength": p.get("base_strength"),
		"base_dexterity": p.get("base_dexterity"),
		"base_vitality": p.get("base_vitality"),
		"map_markers": map_markers_save,
		"learned_build_recipes": learned_recipes_save,
		"npc_progress": p.get("_npc_progress") if "_npc_progress" in p else 0,
	}


func _deserialize_player(player: Node, data: Dictionary) -> void:
	if not player or data.is_empty():
		return
	var p := player as CharacterBody3D
	var pos: Dictionary = data.get("position", {})
	if not pos.is_empty():
		var saved_pos := Vector3(
			float(pos.get("x", 0.0)),
			float(pos.get("y", 5.0)),
			float(pos.get("z", 0.0))
		)
		# Ensure restored position is above terrain
		var wgs := get_tree().get_nodes_in_group(&"world_generator")
		if not wgs.is_empty() and wgs[0].has_method(&"get_height_at"):
			var ground_y: float = wgs[0].get_height_at(saved_pos.x, saved_pos.z)
			saved_pos.y = maxf(saved_pos.y, ground_y + 1.5)
		if not wgs.is_empty() and wgs[0].has_method(&"world_to_scene_pos"):
			p.global_position = wgs[0].world_to_scene_pos(saved_pos)
		else:
			p.global_position = saved_pos
		p.velocity = Vector3.ZERO
	if data.has("rotation_y"):
		p.rotation.y = float(data["rotation_y"])
	if data.has("health") and data["health"] != null:
		p.set("current_health", float(data["health"]))
	if data.has("stamina") and data["stamina"] != null:
		p.set("current_stamina", float(data["stamina"]))
	if data.has("equipped_weapon"):
		p.set("equipped_weapon", StringName(str(data["equipped_weapon"])))
	if data.has("selected_slot"):
		p.set("_selected_slot", int(data["selected_slot"]))
	if data.has("base_strength"):
		p.set("base_strength", int(data["base_strength"]))
	if data.has("base_dexterity"):
		p.set("base_dexterity", int(data["base_dexterity"]))
	if data.has("base_vitality"):
		p.set("base_vitality", int(data["base_vitality"]))
	if data.has("map_markers"):
		var markers: Array[Dictionary] = []
		for m in (data["map_markers"] as Array):
			var mdict := m as Dictionary
			var mpos: Dictionary = mdict.get("pos", {}) as Dictionary
			markers.append({
				"id": str(mdict.get("id", "")),
				"pos": Vector3(float(mpos.get("x", 0)), float(mpos.get("y", 0)), float(mpos.get("z", 0))),
				"label": str(mdict.get("label", "")),
				"color": Color(1.0, 0.85, 0.3),
			})
		p.set("_map_markers", markers)
	if data.has("learned_build_recipes"):
		var recipes: Array[StringName] = []
		for r in (data["learned_build_recipes"] as Array):
			recipes.append(StringName(str(r)))
		p.set("_learned_build_recipes", recipes)
	if data.has("npc_progress"):
		p.set("_npc_progress", int(data["npc_progress"]))


func _serialize_inventory() -> Dictionary:
	var result: Dictionary = {}
	result["items"] = Inventory.get_all_items().duplicate()
	var order_strings: Array[String] = []
	for sid: StringName in Inventory.get_order():
		order_strings.append(String(sid))
	result["order"] = order_strings
	var eq: Dictionary = {}
	for slot: String in Inventory.get_all_equipped().keys():
		eq[slot] = String(Inventory.get_equipped(slot))
	result["equipped"] = eq
	return result


func _deserialize_inventory(data: Dictionary) -> void:
	if data.is_empty():
		return
	Inventory._slots.clear()
	Inventory._order.clear()
	# Support both old format (flat dict) and new format (items + order)
	var items_dict: Dictionary = data.get("items", data) as Dictionary
	for key: String in items_dict.keys():
		if key == "items" or key == "order":
			continue
		Inventory._slots[StringName(key)] = int(items_dict[key])
	var saved_order: Array = data.get("order", []) as Array
	if not saved_order.is_empty():
		for sid in saved_order:
			var sn := StringName(str(sid))
			if Inventory._slots.has(sn):
				Inventory._order.append(sn)
	# Add any items missing from the saved order
	for sid: StringName in Inventory._slots.keys():
		if not Inventory._order.has(sid):
			Inventory._order.append(sid)

	_migrate_missing_affixes()

	var eq_data: Dictionary = data.get("equipped", {}) as Dictionary
	if not eq_data.is_empty():
		var migrated_eq: Dictionary = {}
		for slot: String in eq_data.keys():
			var mid := _migrate_item_id(StringName(str(eq_data[slot])))
			migrated_eq[slot] = _migrate_replaced_affixes(mid)
		Inventory.set_equipped_from_save(migrated_eq)
	GameEvents.inventory_changed.emit()


func _migrate_item_id(old_id: StringName) -> StringName:
	var parsed := ItemDatabase.parse_star_id(old_id)
	var stars: int = parsed["stars"]
	var affixes: Array = parsed.get("affixes", [])
	if stars < 3 or not affixes.is_empty():
		return old_id
	var base_data: Dictionary = ItemDatabase.get_item(parsed["base_id"])
	var item_type: String = str(base_data.get("type", "material"))
	if item_type not in ["weapon", "armor"]:
		return old_id
	var rolled: Array[StringName] = ItemDatabase.roll_affixes(stars, ItemDatabase.get_affix_slot(parsed["base_id"]))
	if rolled.is_empty():
		return old_id
	var rolls: Dictionary = ItemDatabase.roll_affix_magnitudes(rolled)
	return ItemDatabase.make_star_id(parsed["base_id"], stars, rolled, rolls)


func _migrate_missing_affixes() -> void:
	var remap: Dictionary = {}
	for old_id: StringName in Inventory._slots.keys():
		var new_id := _migrate_item_id(old_id)
		new_id = _migrate_replaced_affixes(new_id)
		if new_id != old_id:
			remap[old_id] = new_id

	for old_id: StringName in remap.keys():
		var new_id: StringName = remap[old_id]
		var amount: int = int(Inventory._slots[old_id])
		Inventory._slots.erase(old_id)
		if Inventory._slots.has(new_id):
			Inventory._slots[new_id] = int(Inventory._slots[new_id]) + amount
		else:
			Inventory._slots[new_id] = amount
		var idx: int = Inventory._order.find(old_id)
		if idx >= 0:
			Inventory._order[idx] = new_id
		elif not Inventory._order.has(new_id):
			Inventory._order.append(new_id)


const _AFFIX_REPLACEMENTS := {&"piercing": &"bouncing_shot"}

func _migrate_replaced_affixes(item_id: StringName) -> StringName:
	var parsed := ItemDatabase.parse_star_id(item_id)
	var affixes: Array = parsed.get("affixes", [])
	if affixes.is_empty():
		return item_id
	var changed := false
	var new_affixes: Array[StringName] = []
	var new_rolls: Dictionary = parsed.get("affix_rolls", {}).duplicate()
	for a: StringName in affixes:
		if _AFFIX_REPLACEMENTS.has(a):
			var replacement: StringName = _AFFIX_REPLACEMENTS[a]
			new_affixes.append(replacement)
			var old_roll: float = new_rolls.get(a, randf())
			new_rolls.erase(a)
			new_rolls[replacement] = old_roll
			changed = true
		else:
			new_affixes.append(a)
	if not changed:
		return item_id
	var int_rolls: Dictionary = {}
	for key: StringName in new_rolls:
		int_rolls[key] = int(clampf(float(new_rolls[key]) * 100.0, 0.0, 100.0))
	return ItemDatabase.make_star_id(parsed["base_id"], parsed["stars"], new_affixes, int_rolls)


func _serialize_structures() -> Array:
	var result: Array = []
	for node: Node in get_tree().get_nodes_in_group(&"structures"):
		var s := node as Node3D
		if not s:
			continue
		var build_id: String = str(s.get_meta("build_id", ""))
		if build_id.is_empty():
			continue
		var entry := {
			"build_id": build_id,
			"px": s.global_position.x,
			"py": s.global_position.y,
			"pz": s.global_position.z,
			"ry": s.rotation.y,
		}
		if s.has_meta("chest_contents"):
			var raw: Array = s.get_meta("chest_contents") as Array
			var serialized: Array = []
			for slot in raw:
				if slot is Dictionary and slot.get("item_id", &"") != &"":
					serialized.append({"item_id": str(slot["item_id"]), "count": int(slot.get("count", 0))})
				else:
					serialized.append({})
			entry["chest_contents"] = serialized
		result.append(entry)
	return result


func _deserialize_structures(data: Array) -> void:
	if data.is_empty():
		return
	var player := _get_player()
	if not player or not player.has_method(&"rebuild_structure"):
		return
	for entry in data:
		if entry is not Dictionary:
			continue
		var d: Dictionary = entry
		var build_id: String = d.get("build_id", "")
		if build_id.is_empty():
			continue
		var world_pos := Vector3(
			float(d.get("px", 0.0)),
			float(d.get("py", 0.0)),
			float(d.get("pz", 0.0)),
		)
		var wgs2 := get_tree().get_nodes_in_group(&"world_generator")
		var scene_pos := world_pos
		if not wgs2.is_empty() and wgs2[0].has_method(&"world_to_scene_pos"):
			scene_pos = wgs2[0].world_to_scene_pos(world_pos)
		var rot_y: float = float(d.get("ry", 0.0))
		player.rebuild_structure(build_id, scene_pos, rot_y)
		if d.has("chest_contents"):
			var raw: Array = d["chest_contents"] as Array
			var restored: Array = []
			for slot in raw:
				if slot is Dictionary and str(slot.get("item_id", "")) != "":
					restored.append({"item_id": StringName(str(slot["item_id"])), "count": int(slot.get("count", 0))})
				else:
					restored.append({})
			var chests := get_tree().get_nodes_in_group(&"chests")
			if not chests.is_empty():
				var last_chest := chests.back() as Node3D
				if last_chest:
					last_chest.set_meta("chest_contents", restored)


func _serialize_world_state() -> Dictionary:
	var wss := _get_world_state_sync()
	if not wss:
		return {"destroyed": {}, "buildings": []}
	return wss.get_world_state_for_save()


func _deserialize_world_state(data: Dictionary) -> void:
	var wss := _get_world_state_sync()
	if wss and not data.is_empty():
		wss.apply_world_state_from_save(data)


func _get_world_state_sync() -> Node:
	var wss := get_tree().get_nodes_in_group(&"world_state_sync")
	if not wss.is_empty() and wss[0].has_method(&"get_world_state_for_save"):
		return wss[0]
	return null


func _serialize_all_players(host_char_id: String) -> Dictionary:
	var result: Dictionary = {}
	# Host's own data
	var player := _get_player()
	if player:
		result[host_char_id] = {
			"player": _serialize_player(player),
			"inventory": _serialize_inventory(),
		}
	# Cached data from other players
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		for peer_id in NetworkManager.get_connected_peers():
			if peer_id == multiplayer.get_unique_id():
				continue
			var cached := NetworkManager.get_cached_player_data(peer_id)
			if not cached.is_empty():
				var char_id: String = str(cached.get("character_id", peer_id))
				result[char_id] = {
					"player": cached.get("player", {}),
					"inventory": cached.get("inventory", {}),
				}
	return result


func save_disconnected_player(peer_id: int, char_id: String, player_data: Dictionary, inventory_data: Dictionary) -> void:
	if current_world.is_empty():
		return
	var world_id: String = str(current_world.get("id", ""))
	var save_path := SAVE_DIR + char_id + "_" + world_id + "_disconnected.json"
	var data := {
		"character_id": char_id,
		"peer_id": peer_id,
		"player": player_data,
		"inventory": inventory_data,
		"timestamp": Time.get_datetime_string_from_system(),
	}
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		if _DEBUG_LOG: print("[SAVE] Saved disconnected player %s (peer %d)" % [char_id, peer_id])
