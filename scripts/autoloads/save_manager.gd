extends Node
## Handles saving and loading game state: player data, inventory, world info.

const SAVE_DIR := "user://saves/"
const CHARACTERS_FILE := "user://characters.json"
const AUTOSAVE_INTERVAL := 10.0

var current_character: Dictionary = {}
var current_world: Dictionary = {}

var _autosave_timer := 0.0
var _game_active := false


func _ready() -> void:
	_ensure_save_dir()


func _process(delta: float) -> void:
	if not _game_active:
		return
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
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
	_update_character_last_played()


func save_game() -> void:
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
		"structures": _serialize_structures(),
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

	var player := _get_player()
	_deserialize_player(player, save_data.get("player", {}))
	_deserialize_inventory(save_data.get("inventory", {}))
	_deserialize_structures(save_data.get("structures", []))


func stop_game() -> void:
	if _game_active:
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


func _deferred_load_save() -> void:
	# Wait for scene tree to fully settle before applying save
	await get_tree().process_frame
	await get_tree().process_frame
	var save_data := load_game()
	if not save_data.is_empty():
		apply_save_data(save_data)


func _get_player() -> Node:
	return get_tree().get_first_node_in_group(&"player")


func _serialize_player(player: Node) -> Dictionary:
	if not player:
		return {}
	var p := player as CharacterBody3D
	return {
		"position": {"x": p.global_position.x, "y": p.global_position.y, "z": p.global_position.z},
		"rotation_y": p.rotation.y,
		"health": p.get("current_health"),
		"stamina": p.get("current_stamina"),
		"equipped_weapon": str(p.get("equipped_weapon")),
		"selected_slot": p.get("_selected_slot"),
		"base_strength": p.get("base_strength"),
		"base_dexterity": p.get("base_dexterity"),
		"base_vitality": p.get("base_vitality"),
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
			migrated_eq[slot] = _migrate_item_id(StringName(str(eq_data[slot])))
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
	return ItemDatabase.make_star_id(parsed["base_id"], stars, rolled)


func _migrate_missing_affixes() -> void:
	var remap: Dictionary = {}
	for old_id: StringName in Inventory._slots.keys():
		var new_id := _migrate_item_id(old_id)
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
		var idx := Inventory._order.find(old_id)
		if idx >= 0:
			Inventory._order[idx] = new_id
		elif not Inventory._order.has(new_id):
			Inventory._order.append(new_id)


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
		var pos := Vector3(
			float(d.get("px", 0.0)),
			float(d.get("py", 0.0)),
			float(d.get("pz", 0.0)),
		)
		var rot_y: float = float(d.get("ry", 0.0))
		player.rebuild_structure(build_id, pos, rot_y)
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
