class_name WorldStateSync
extends Node
## Tracks world mutations (destroyed objects, placed buildings) for LAN multiplayer sync.
##
## Terrain and zone population are deterministic per world seed. Only mutations need
## network sync. When a client joins mid-game, they request world state and apply
## mutations to their locally-generated world.

signal world_state_received()

var _destroyed_objects: Dictionary = {}  # key: "zx_zz_i" (zone_coord + local_index) -> timestamp
var _placed_buildings: Array[Dictionary] = []  # each: {build_id, px, py, pz, ry, chest_contents}
var _next_loot_id: int = 1
var _loot_registry: Dictionary = {}  # loot_id -> LootDrop (host only)


func _ready() -> void:
	add_to_group(&"world_state_sync")
	# When client receives world_info, request world state mutations
	if not NetworkManager.is_server():
		NetworkManager.world_info_received.connect(_on_world_info_received)
		# If we already have world_info (scene loaded late), request immediately
		if NetworkManager.world_seed != "":
			call_deferred("request_world_state")


func _on_world_info_received() -> void:
	request_world_state()


## Returns object key for zone coord + local index among interactables.
static func make_object_key(zone_coord: Vector2i, local_index: int) -> String:
	return "%d_%d_%d" % [zone_coord.x, zone_coord.y, local_index]


## Compute object key from a harvestable node (must be in interactables, before removal).
static func get_object_key_for_node(node: Node) -> String:
	var zone = node.get_parent()
	if not zone or not zone.name.begins_with("Zone_"):
		return ""
	var parts: PackedStringArray = zone.name.split("_")
	if parts.size() < 3:
		return ""
	var zx := int(parts[1])
	var zz := int(parts[2])
	var idx := 0
	for child in zone.get_children():
		if child.is_in_group(&"interactables"):
			if child == node:
				return make_object_key(Vector2i(zx, zz), idx)
			idx += 1
	return ""


## Call when a harvestable (tree, rock, sapling) is destroyed. Only on server.
## Call BEFORE removing the node from the group (key is computed from node).
func record_object_destroyed(node: Node) -> void:
	if not NetworkManager.is_server():
		return
	var key := get_object_key_for_node(node)
	if key.is_empty():
		return
	_record_and_broadcast_destroyed(key)


## Client sends this when they destroy a harvestable. Host validates, spawns loot, and broadcasts.
@rpc("any_peer", "reliable")
func request_destroy_object(key: String) -> void:
	if not multiplayer.is_server():
		return
	if key.is_empty() or _destroyed_objects.has(key):
		return
	var node := _get_node_by_key(key)
	if node:
		_spawn_loot_from_harvestable(node)
	_record_and_broadcast_destroyed(key)
	_remove_destroyed_object(key)


func _record_and_broadcast_destroyed(key: String) -> void:
	_destroyed_objects[key] = Time.get_unix_time_from_system()
	_broadcast_destroyed.rpc(key)


## Call when a building is placed. Only on server (host).
func record_building_placed(build_id: StringName, position: Vector3, rotation_y: float, chest_contents: Array = []) -> void:
	if not NetworkManager.is_server():
		return
	var entry := _make_building_entry(build_id, position, rotation_y, chest_contents)
	_placed_buildings.append(entry)
	_broadcast_building.rpc(entry, -1)


## Client sends this when they place a building. Host validates and broadcasts.
@rpc("any_peer", "reliable")
func request_building_placed(entry: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if entry.is_empty() or not entry.has("build_id"):
		return
	var sender := multiplayer.get_remote_sender_id()
	_placed_buildings.append(entry)
	_spawn_building(entry)  # Host needs to spawn for themselves
	_broadcast_building.rpc(entry, sender)  # Exclude sender (they already placed locally)


func _make_building_entry(build_id: StringName, position: Vector3, rotation_y: float, chest_contents: Array) -> Dictionary:
	return {
		"build_id": str(build_id),
		"px": position.x,
		"py": position.y,
		"pz": position.z,
		"ry": rotation_y,
		"chest_contents": chest_contents,
	}


@rpc("any_peer", "reliable")
func request_world_state() -> void:
	if multiplayer.is_server():
		var sender := multiplayer.get_remote_sender_id()
		_send_world_state.rpc_id(sender, _destroyed_objects, _placed_buildings)
	else:
		# Client: send request to server (peer 1 is host)
		request_world_state.rpc_id(1)


@rpc("authority", "reliable")
func _send_world_state(destroyed: Dictionary, buildings: Array) -> void:
	_destroyed_objects = destroyed
	_placed_buildings.clear()
	for entry in buildings:
		_placed_buildings.append(entry as Dictionary)
	_apply_mutations()
	world_state_received.emit()
	print("[WorldStateSync] Received world state: %d destroyed, %d buildings" % [destroyed.size(), buildings.size()])


@rpc("authority", "reliable")
func _broadcast_destroyed(key: String) -> void:
	_destroyed_objects[key] = Time.get_unix_time_from_system()
	# Only remove on clients; host either did it locally (record_object_destroyed) or in request_destroy_object
	if not multiplayer.is_server():
		_remove_destroyed_object(key)


@rpc("authority", "reliable")
func _broadcast_building(entry: Dictionary, exclude_peer: int = -1) -> void:
	# Only spawn on clients that didn't place it (exclude_peer already has it)
	if exclude_peer < 0 or multiplayer.get_unique_id() != exclude_peer:
		_spawn_building(entry)


## Apply mutations to locally-generated world. Call after receiving world state.
func _apply_mutations() -> void:
	for key in _destroyed_objects:
		_remove_destroyed_object(key)
	for entry in _placed_buildings:
		_spawn_building(entry)


func _get_node_by_key(key: String) -> Node:
	var parts := key.split("_")
	if parts.size() < 3:
		return null
	var zx := int(parts[0])
	var zz := int(parts[1])
	var target_idx := int(parts[2])
	var wg := _find_world_generator()
	if not wg:
		return null
	var zone := wg.get_node_or_null("Zone_%d_%d" % [zx, zz])
	if not zone:
		return null
	var idx := 0
	for child in zone.get_children():
		if child.is_in_group(&"interactables"):
			if idx == target_idx:
				return child
			idx += 1
	return null


func _spawn_loot_from_harvestable(node: Node) -> void:
	var drop_id: StringName = node.get_meta("drop_id", &"stone") as StringName
	var drop_min: int = int(node.get_meta("drop_min", 2))
	var drop_max: int = int(node.get_meta("drop_max", 4))
	var base_pos := (node as Node3D).global_position if node is Node3D else Vector3.ZERO
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if drop_id == &"wood":
		var total := rng.randi_range(drop_min, drop_max)
		var fall_dir := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
		var trunk_h: float = float(node.get_meta("trunk_h", 15.0))
		for i in total:
			var t := rng.randf_range(0.2, 0.9)
			var along := fall_dir * trunk_h * t
			var lateral := rng.randf_range(-1.5, 1.5)
			var perp := Vector3(-fall_dir.z, 0.0, fall_dir.x)
			var offset := along + perp * lateral + Vector3.UP * 0.5
			var stars := ItemDatabase.roll_star_level(rng)
			_spawn_and_replicate_loot(base_pos + offset, drop_id, 1, stars)
	else:
		var total := rng.randi_range(drop_min, drop_max)
		for i in total:
			var angle := rng.randf_range(0.0, TAU)
			var dist := rng.randf_range(0.8, 2.5)
			var offset := Vector3(cos(angle) * dist, 0.5, sin(angle) * dist)
			var stars := ItemDatabase.roll_star_level(rng)
			_spawn_and_replicate_loot(base_pos + offset, drop_id, 1, stars)
		if rng.randf() < 0.4:
			var flint_stars := ItemDatabase.roll_star_level(rng)
			_spawn_and_replicate_loot(base_pos + Vector3(rng.randf_range(-1.0, 1.0), 0.5, rng.randf_range(-1.0, 1.0)), &"flint", rng.randi_range(1, 2), flint_stars)


func _spawn_and_replicate_loot(world_pos: Vector3, item_id: StringName, amount: int, star_level: int) -> void:
	var composite_id := item_id
	if star_level > 0:
		composite_id = ItemDatabase.make_star_id(item_id, star_level)
	var drop := LootDrop.new()
	drop.item_id = composite_id
	drop.star_level = star_level
	drop.amount = amount
	drop.set_meta("loot_id", _next_loot_id)
	var loot_id := _next_loot_id
	_next_loot_id += 1
	_loot_registry[loot_id] = drop
	get_tree().current_scene.add_child(drop)
	drop.global_position = world_pos
	_spawn_loot_replicated.rpc(loot_id, str(composite_id), amount, star_level, world_pos.x, world_pos.y, world_pos.z)


@rpc("authority", "reliable")
func _spawn_loot_replicated(loot_id: int, item_id_str: String, amount: int, star_level: int, px: float, py: float, pz: float) -> void:
	if multiplayer.is_server():
		return  # Host already has it
	var drop := LootDrop.new()
	drop.item_id = StringName(item_id_str)
	drop.star_level = star_level
	drop.amount = amount
	drop.set_meta("loot_id", loot_id)
	get_tree().current_scene.add_child(drop)
	drop.global_position = Vector3(px, py, pz)


## Host spawns a single loot drop and replicates to clients. Call from player when host destroys harvestable.
func spawn_loot_synced(world_pos: Vector3, item_id: StringName, amount: int, star_level: int) -> void:
	if not NetworkManager.is_server():
		return
	_spawn_and_replicate_loot(world_pos, item_id, amount, star_level)


## Host processes their own pickup: grant to self and remove for everyone.
func process_host_pickup(drop: LootDrop) -> void:
	if not NetworkManager.is_server():
		return
	var loot_id: int = drop.get_meta("loot_id", -1)
	if loot_id < 0 or not _loot_registry.has(loot_id):
		return
	_loot_registry.erase(loot_id)
	_grant_pickup.rpc_id(NetworkManager.get_peer_id(), loot_id, str(drop.item_id), drop.amount, drop.star_level, drop.global_position.x, drop.global_position.y, drop.global_position.z)
	_remove_loot.rpc(loot_id)


## Client requests to pick up loot. Host grants to first requester and removes for everyone.
@rpc("any_peer", "reliable")
func request_pickup(loot_id: int, peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var drop: LootDrop = _loot_registry.get(loot_id)
	if not drop or not is_instance_valid(drop):
		return
	_loot_registry.erase(loot_id)
	var pos := drop.global_position
	_grant_pickup.rpc_id(peer_id, loot_id, str(drop.item_id), drop.amount, drop.star_level, pos.x, pos.y, pos.z)
	_remove_loot.rpc(loot_id)


@rpc("authority", "reliable")
func _grant_pickup(loot_id: int, item_id_str: String, amount: int, star_level: int, px: float, py: float, pz: float) -> void:
	GameEvents.item_picked_up.emit(StringName(item_id_str), amount)
	var base: String = str(ItemDatabase.parse_star_id(StringName(item_id_str))["base_id"])
	var pickup_sfx := "wood_pickup" if base == "wood" else "stone_rubble"
	AudioManager.play_sfx(pickup_sfx, -1.0, 0.15)
	var display := ItemDatabase.get_display_name(StringName(item_id_str))
	var num := DamageNumber.new()
	num.font_size = 28
	num.pixel_size = 0.01
	num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	num.no_depth_test = true
	num.modulate = Color.WHITE
	num.outline_modulate = Color.BLACK
	num.outline_size = 6
	num._velocity = Vector3(0, 2.0, 0)
	num.text = "+%d %s" % [amount, display]
	var scene := get_tree().current_scene
	if scene:
		scene.add_child(num)
		num.global_position = Vector3(px, py, pz) + Vector3(0, 1.2, 0)


@rpc("authority", "reliable")
func _remove_loot(loot_id: int) -> void:
	for loot_node in get_tree().get_nodes_in_group(&"loot"):
		var drop := loot_node as LootDrop
		if drop and drop.get_meta("loot_id", -1) == loot_id:
			drop.queue_free()
			return


func _remove_destroyed_object(key: String) -> void:
	var node := _get_node_by_key(key)
	if node:
		node.queue_free()


func _spawn_building(entry: Dictionary) -> void:
	var build_id_str: String = entry.get("build_id", "")
	if build_id_str.is_empty():
		return
	var player := _get_player_with_rebuild()
	if not player:
		return
	var pos := Vector3(
		float(entry.get("px", 0.0)),
		float(entry.get("py", 0.0)),
		float(entry.get("pz", 0.0)),
	)
	var rot_y: float = float(entry.get("ry", 0.0))
	player.rebuild_structure(build_id_str, pos, rot_y)
	if entry.has("chest_contents"):
		var raw: Array = entry["chest_contents"] as Array
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


## Return world state for save (destroyed objects, placed buildings).
func get_world_state_for_save() -> Dictionary:
	return {
		"destroyed": _destroyed_objects.duplicate(),
		"buildings": _placed_buildings.duplicate(),
	}


## Apply world state from save. Call when loading.
func apply_world_state_from_save(data: Dictionary) -> void:
	if data.has("destroyed"):
		_destroyed_objects = data["destroyed"].duplicate()
	if data.has("buildings"):
		_placed_buildings.clear()
		var raw_buildings: Array = data["buildings"]
		for entry in raw_buildings:
			_placed_buildings.append(entry as Dictionary)
	_apply_mutations()


## Apply destroyed objects to a zone that was just generated. Call from WorldGenerator.
func apply_destroyed_to_zone(zone_root: Node, coord: Vector2i) -> void:
	var idx := 0
	var to_remove: Array[Node] = []
	for child in zone_root.get_children():
		if child.is_in_group(&"interactables"):
			var key := make_object_key(coord, idx)
			if _destroyed_objects.has(key):
				to_remove.append(child)
			idx += 1
	for node in to_remove:
		node.queue_free()


func _find_world_generator() -> WorldGenerator:
	var wgs := get_tree().get_nodes_in_group(&"world_generator")
	for n in wgs:
		if n is WorldGenerator:
			return n as WorldGenerator
	return null


func _get_player_with_rebuild() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	var current := tree.current_scene
	if not current:
		return null
	var players := current.get_node_or_null("Players")
	if not players:
		return null
	# Prefer host/authority player
	for child in players.get_children():
		if child.has_method(&"rebuild_structure"):
			return child
	return null
