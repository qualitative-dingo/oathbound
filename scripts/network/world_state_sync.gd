class_name WorldStateSync
extends Node
## Tracks world mutations (destroyed objects, placed buildings) for LAN multiplayer sync.
##
## Terrain and zone population are deterministic per world seed. Only mutations need
## network sync. When a client joins mid-game, they request world state and apply
## mutations to their locally-generated world.

const _DEBUG_LOG := false

signal world_state_received()

var _destroyed_objects: Dictionary = {}  # key: "zx_zz_i" (zone_coord + local_index) -> timestamp
var _placed_buildings: Array[Dictionary] = []  # each: {build_id, px, py, pz, ry, chest_contents}
var _pending_buildings: Array[Dictionary] = []
var _saved_horses: Array = []  # each: {x, y, z, star_level} — global positions, loaded from save
var _next_loot_id: int = 1
var _loot_registry: Dictionary = {}  # loot_id -> LootDrop (host only)


func _ready() -> void:
	add_to_group(&"world_state_sync")
	set_process(false)
	_connect_zone_unload_signal()
	if not NetworkManager.is_server():
		NetworkManager.world_info_received.connect(_on_world_info_received)
		if NetworkManager.world_seed != "":
			call_deferred("request_world_state")


func _connect_zone_unload_signal() -> void:
	call_deferred("_deferred_connect_zone_unload")


func _deferred_connect_zone_unload() -> void:
	var wg := _find_world_generator()
	if wg and not wg.zone_unloaded.is_connected(_on_zone_unloaded):
		wg.zone_unloaded.connect(_on_zone_unloaded)


func _on_zone_unloaded(coord: Vector2i) -> void:
	var prefix := "%d_%d_" % [coord.x, coord.y]
	var to_erase: Array[String] = []
	for key: String in _csync_last_states:
		if key.begins_with(prefix):
			to_erase.append(key)
	for key in to_erase:
		_csync_last_states.erase(key)
	_prune_loot_registry()


func _prune_loot_registry() -> void:
	var to_erase: Array[int] = []
	for loot_id: int in _loot_registry:
		var drop = _loot_registry[loot_id]
		if not is_instance_valid(drop):
			to_erase.append(loot_id)
	for lid in to_erase:
		_loot_registry.erase(lid)


func _on_world_info_received() -> void:
	request_world_state()


func _process(_delta: float) -> void:
	if _pending_buildings.is_empty():
		set_process(false)
		return
	var player := _get_player_with_rebuild()
	if not player:
		return
	var to_process := _pending_buildings.duplicate()
	_pending_buildings.clear()
	set_process(false)
	for entry in to_process:
		_spawn_building(entry)


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
	var sender := multiplayer.get_remote_sender_id()
	if key.is_empty() or _destroyed_objects.has(key):
		if _DEBUG_LOG: print("[WSS] request_destroy_object REJECTED key='%s' from peer %d (empty=%s dup=%s)" % [
			key, sender, str(key.is_empty()), str(_destroyed_objects.has(key))])
		return
	var node := _get_node_by_key(key)
	if node:
		if _DEBUG_LOG: print("[WSS] request_destroy_object key='%s' from peer %d → spawning loot for '%s'" % [
			key, sender, node.name])
		_spawn_loot_from_harvestable(node)
	else:
		if _DEBUG_LOG: print("[WSS] request_destroy_object key='%s' from peer %d → node NOT FOUND" % [key, sender])
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
	if _DEBUG_LOG: print("[WSS] record_building_placed: broadcasting '%s' to clients (total=%d)" % [str(build_id), _placed_buildings.size()])
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
		_send_world_state.rpc_id(sender, _destroyed_objects, _placed_buildings, _collect_horse_positions())
	else:
		request_world_state.rpc_id(1)


@rpc("authority", "reliable")
func _send_world_state(destroyed: Dictionary, buildings: Array, horses: Array = []) -> void:
	_destroyed_objects = destroyed
	_placed_buildings.clear()
	for entry in buildings:
		_placed_buildings.append(entry as Dictionary)
	if not horses.is_empty():
		_saved_horses = horses.duplicate()
	_apply_mutations()
	world_state_received.emit()
	if _DEBUG_LOG: print("[WorldStateSync] Received world state: %d destroyed, %d buildings, %d horses" % [destroyed.size(), buildings.size(), horses.size()])


@rpc("authority", "reliable")
func _broadcast_destroyed(key: String) -> void:
	_destroyed_objects[key] = Time.get_unix_time_from_system()
	# Only remove on clients; host either did it locally (record_object_destroyed) or in request_destroy_object
	if not multiplayer.is_server():
		_remove_destroyed_object(key)


@rpc("authority", "reliable")
func _broadcast_building(entry: Dictionary, exclude_peer: int = -1) -> void:
	if exclude_peer < 0 or multiplayer.get_unique_id() != exclude_peer:
		if _DEBUG_LOG: print("[WSS] _broadcast_building received: %s (my_id=%d exclude=%d)" % [entry.get("build_id", "?"), multiplayer.get_unique_id(), exclude_peer])
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


func _spawn_and_replicate_loot(world_pos: Vector3, item_id: StringName, amount: int, star_level: int, dropper_peer: int = -1, spawn_delay: float = 0.0) -> void:
	var composite_id := item_id
	if star_level > 0:
		composite_id = ItemDatabase.make_star_id(item_id, star_level)
	var drop := LootDrop.new()
	drop.item_id = composite_id
	drop.star_level = star_level
	drop.amount = amount
	drop.spawn_delay = spawn_delay
	drop.set_meta("loot_id", _next_loot_id)
	if dropper_peer >= 0:
		drop.drop_owner_peer = dropper_peer
		drop.pickup_grace = 5.0
	var loot_id := _next_loot_id
	_next_loot_id += 1
	_loot_registry[loot_id] = drop
	get_tree().current_scene.add_child(drop)
	drop.global_position = world_pos
	_spawn_loot_replicated.rpc(loot_id, str(composite_id), amount, star_level, world_pos.x, world_pos.y, world_pos.z, dropper_peer, spawn_delay)


@rpc("authority", "reliable")
func _spawn_loot_replicated(loot_id: int, item_id_str: String, amount: int, star_level: int, px: float, py: float, pz: float, dropper_peer: int = -1, spawn_delay: float = 0.0) -> void:
	if multiplayer.is_server():
		return
	var drop := LootDrop.new()
	drop.item_id = StringName(item_id_str)
	drop.star_level = star_level
	drop.amount = amount
	drop.spawn_delay = spawn_delay
	drop.set_meta("loot_id", loot_id)
	if dropper_peer >= 0:
		drop.drop_owner_peer = dropper_peer
		drop.pickup_grace = 5.0
	get_tree().current_scene.add_child(drop)
	drop.global_position = Vector3(px, py, pz)


## Host spawns a single loot drop and replicates to clients. Call from player when host destroys harvestable.
func spawn_loot_synced(world_pos: Vector3, item_id: StringName, amount: int, star_level: int, spawn_delay: float = 0.0) -> void:
	if not NetworkManager.is_server():
		return
	_spawn_and_replicate_loot(world_pos, item_id, amount, star_level, -1, spawn_delay)


## Host drops an item from inventory — visible to all, with pickup grace for the dropper.
func spawn_player_drop_synced(world_pos: Vector3, item_id: StringName, amount: int, star_level: int, dropper_peer: int) -> void:
	if not NetworkManager.is_server():
		return
	_spawn_and_replicate_loot(world_pos, item_id, amount, star_level, dropper_peer)


## Client requests the host to spawn a dropped item so all peers can see it.
@rpc("any_peer", "reliable")
func request_drop_item(item_id_str: String, amount: int, star_level: int, px: float, py: float, pz: float) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_spawn_and_replicate_loot(Vector3(px, py, pz), StringName(item_id_str), amount, star_level, sender)


## Host processes their own pickup: grant to self directly and remove for everyone.
func process_host_pickup(drop: LootDrop) -> void:
	if not NetworkManager.is_server():
		return
	var loot_id: int = drop.get_meta("loot_id", -1)
	if loot_id < 0 or not _loot_registry.has(loot_id):
		return
	_loot_registry.erase(loot_id)
	_grant_pickup(loot_id, str(drop.item_id), drop.amount, drop.star_level, drop.global_position.x, drop.global_position.y, drop.global_position.z)
	_remove_loot(loot_id)
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
	_remove_loot(loot_id)
	_remove_loot.rpc(loot_id)


@rpc("authority", "reliable")
func _grant_pickup(loot_id: int, item_id_str: String, amount: int, star_level: int, px: float, py: float, pz: float) -> void:
	var composite_id := StringName(item_id_str)
	GameEvents.item_picked_up.emit(composite_id, amount)
	var parsed := ItemDatabase.parse_star_id(composite_id)
	var base: String = str(parsed["base_id"])
	var stars: int = int(parsed["stars"])
	var pickup_sfx := "wood_pickup" if base == "wood" else "stone_rubble"
	AudioManager.play_sfx(pickup_sfx, -1.0, 0.15)
	var display := ItemDatabase.get_display_name(composite_id)
	var num := DamageNumber.new()
	num.font_size = 28
	num.pixel_size = 0.01
	num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	num.no_depth_test = true
	num.modulate = Color.WHITE
	num.outline_modulate = Color.BLACK
	num.outline_size = 6
	num._velocity = Vector3(0, 2.0, 0)
	if stars > 0:
		num.text = "+%d %s " % [amount, display]
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var star_str := ""
		for i in stars:
			star_str += "★"
		var star_lbl := Label3D.new()
		star_lbl.text = star_str
		star_lbl.font_size = 28
		star_lbl.pixel_size = 0.01
		star_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star_lbl.no_depth_test = true
		star_lbl.modulate = ItemDatabase.get_rarity_color(stars)
		star_lbl.outline_modulate = Color.BLACK
		star_lbl.outline_size = 6
		star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		num.add_child(star_lbl)
	else:
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
		if _DEBUG_LOG: print("[WSS] _spawn_building: no player found, deferring '%s' (%d pending)" % [build_id_str, _pending_buildings.size() + 1])
		_pending_buildings.append(entry)
		set_process(true)
		return
	var world_pos := Vector3(
		float(entry.get("px", 0.0)),
		float(entry.get("py", 0.0)),
		float(entry.get("pz", 0.0)),
	)
	var wgs := get_tree().get_nodes_in_group(&"world_generator")
	var scene_pos := world_pos
	if not wgs.is_empty() and wgs[0].has_method(&"world_to_scene_pos"):
		scene_pos = wgs[0].world_to_scene_pos(world_pos)
	var rot_y: float = float(entry.get("ry", 0.0))
	player.rebuild_structure(build_id_str, scene_pos, rot_y)
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


## Return world state for save (destroyed objects, placed buildings, horse positions).
func get_world_state_for_save() -> Dictionary:
	return {
		"destroyed": _destroyed_objects.duplicate(),
		"buildings": _placed_buildings.duplicate(),
		"horses": _collect_horse_positions(),
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
	if data.has("horses"):
		_saved_horses = (data["horses"] as Array).duplicate()
	_apply_mutations()


## Collect global positions of all horses (free-roaming + currently mounted).
func _collect_horse_positions() -> Array:
	var result: Array = []
	var wgs := get_tree().get_nodes_in_group(&"world_generator")
	var wg: Node = wgs[0] if not wgs.is_empty() else null
	for horse in get_tree().get_nodes_in_group(&"horses"):
		if horse is Node3D:
			var gp: Vector3 = wg.get_world_position(horse) if wg else (horse as Node3D).global_position
			result.append({
				"x": gp.x, "y": gp.y, "z": gp.z,
				"star_level": int(horse.get_meta("star_level", 0)),
			})
	var player := get_tree().get_first_node_in_group(&"player")
	if player and player.get("_mounted") and is_instance_valid(player.get("_mount_node")):
		var mount: Node3D = player.get("_mount_node") as Node3D
		var gp: Vector3 = wg.get_world_position(player) if wg else player.global_position
		result.append({
			"x": gp.x, "y": gp.y, "z": gp.z,
			"star_level": int(mount.get_meta("star_level", 0)),
		})
	return result


## Called by ZonePopulator to check if saved horse data exists.
func get_saved_horses() -> Array:
	return _saved_horses


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
	for child in players.get_children():
		if child.has_method(&"rebuild_structure"):
			return child
	return null


# ═══════════════════════════════════════════════════════════════════════════════
#  Creature Sync (host → clients)
# ═══════════════════════════════════════════════════════════════════════════════

const _CREATURE_POS_INTERVAL := 0.1
const _CREATURE_STATE_INTERVAL := 0.2

var _csync_pos_timer: float = 0.0
var _csync_state_timer: float = 0.0
var _csync_last_states: Dictionary = {}
var _csync_diag: int = 0
var _csync_recv_diag: int = 0


var _csync_started := false

func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return
	if not _csync_started:
		_csync_started = true
		var wg := _find_world_generator()
		if _DEBUG_LOG: print("[WSS] Creature sync started | wg=%s zones=%d path=%s" % [
			str(wg != null),
			wg._loaded_zones.size() if wg else 0,
			str(get_path())])
	_csync_pos_timer += delta
	_csync_state_timer += delta
	if _csync_pos_timer >= _CREATURE_POS_INTERVAL:
		_csync_pos_timer = 0.0
		_csync_diag += 1
		_csync_broadcast_positions()
	if _csync_state_timer >= _CREATURE_STATE_INTERVAL:
		_csync_state_timer = 0.0
		_csync_broadcast_state_changes()


func _csync_broadcast_positions() -> void:
	var wg := _find_world_generator()
	if not wg:
		return
	var loaded: Dictionary = wg._loaded_zones
	for coord: Vector2i in loaded:
		var zone_root: Node = loaded[coord]
		if not is_instance_valid(zone_root):
			continue
		var positions := PackedFloat32Array()
		var rotations := PackedFloat32Array()
		var velocities := PackedFloat32Array()
		var count := 0
		var _wgs := get_tree().get_nodes_in_group(&"world_generator")
		var _wg: Node = _wgs[0] if not _wgs.is_empty() else null
		for child in zone_root.get_children():
			if child is CreatureAI:
				var creature: CreatureAI = child as CreatureAI
				var cwp: Vector3 = _wg.get_world_position(creature) if _wg else creature.global_position
				positions.append(cwp.x)
				positions.append(cwp.y)
				positions.append(cwp.z)
				rotations.append(creature.rotation.y)
				velocities.append(creature.velocity.x)
				velocities.append(creature.velocity.y)
				velocities.append(creature.velocity.z)
				count += 1
		if count > 0:
			if _csync_diag <= 3 or _csync_diag % 100 == 0:
				if _DEBUG_LOG: print("[CSYNC-HOST] zone (%d,%d): %d creatures" % [coord.x, coord.y, count])
			_csync_recv_pos.rpc(coord.x, coord.y, positions, rotations, velocities)


func _csync_broadcast_state_changes() -> void:
	var wg := _find_world_generator()
	if not wg:
		return
	var loaded: Dictionary = wg._loaded_zones
	for coord: Vector2i in loaded:
		var zone_root: Node = loaded[coord]
		if not is_instance_valid(zone_root):
			continue
		var indices := PackedInt32Array()
		var states := PackedInt32Array()
		var healths := PackedFloat32Array()
		var idx := 0
		for child in zone_root.get_children():
			if child is CreatureAI:
				var creature: CreatureAI = child as CreatureAI
				var key := "%d_%d_%d" % [coord.x, coord.y, idx]
				var cur_state := creature._state as int
				var cur_hp: float = creature.current_health
				var prev: Dictionary = _csync_last_states.get(key, {})
				if prev.is_empty() or prev.get("state", -1) != cur_state or absf(prev.get("health", -1.0) - cur_hp) > 0.5:
					indices.append(idx)
					states.append(cur_state)
					healths.append(cur_hp)
					_csync_last_states[key] = {"state": cur_state, "health": cur_hp}
				idx += 1
		if not indices.is_empty():
			_csync_recv_states.rpc(coord.x, coord.y, indices, states, healths)


@rpc("authority", "unreliable")
func _csync_recv_pos(zone_x: int, zone_z: int, positions: PackedFloat32Array, rotations: PackedFloat32Array, velocities: PackedFloat32Array) -> void:
	if multiplayer.is_server():
		return
	_csync_recv_diag += 1
	var wg := _find_world_generator()
	if not wg:
		if _csync_recv_diag <= 5:
			if _DEBUG_LOG: print("[CSYNC-CLIENT] WorldGenerator not found!")
		return
	var coord := Vector2i(zone_x, zone_z)
	var zone_root: Node = wg._loaded_zones.get(coord, null)
	if not zone_root:
		if _csync_recv_diag <= 5 or _csync_recv_diag % 300 == 0:
			if _DEBUG_LOG: print("[CSYNC-CLIENT] Zone (%d,%d) NOT FOUND (recv #%d)" % [zone_x, zone_z, _csync_recv_diag])
		return
	var idx := 0
	var pos_i := 0
	for child in zone_root.get_children():
		if child is CreatureAI:
			var creature: CreatureAI = child as CreatureAI
			if pos_i + 2 < positions.size():
				var world_pos := Vector3(positions[pos_i], positions[pos_i + 1], positions[pos_i + 2])
				var target_pos := wg.world_to_scene_pos(world_pos)
				if not creature._sync_initialized:
					creature.global_position = target_pos
					creature._sync_initialized = true
					if _DEBUG_LOG: print("[CSYNC-CLIENT] Creature '%s' zone (%d,%d) init at %s" % [creature.name, zone_x, zone_z, str(world_pos)])
				creature._sync_target_position = target_pos
				creature.velocity = Vector3(velocities[pos_i], velocities[pos_i + 1], velocities[pos_i + 2])
				creature.rotation.y = rotations[idx]
			pos_i += 3
			idx += 1
	if _csync_recv_diag <= 3 or _csync_recv_diag % 300 == 0:
		if _DEBUG_LOG: print("[CSYNC-CLIENT] Recv #%d zone (%d,%d): %d creatures" % [_csync_recv_diag, zone_x, zone_z, idx])


# ── Client → Host damage request (routed through this scene-defined node
#    so we avoid RPC node-path mismatches on dynamically generated creatures)

@rpc("any_peer", "reliable")
func request_creature_damage(zone_x: int, zone_z: int, creature_idx: int, amount: float, source_peer: int) -> void:
	if not multiplayer.is_server():
		return
	# Server-side sanity clamp: reject impossibly large damage values.
	# TODO: move full damage calc to host for cheat-proof authority.
	var clamped := clampf(amount, 0.0, 9999.0)
	if clamped != amount:
		if _DEBUG_LOG: print("[WSS] WARN: peer %d sent suspicious damage %.1f, clamped to %.1f" % [source_peer, amount, clamped])
	var wg := _find_world_generator()
	if not wg:
		if _DEBUG_LOG: print("[WSS] request_creature_damage: WorldGenerator not found")
		return
	var coord := Vector2i(zone_x, zone_z)
	var zone_root: Node = wg._loaded_zones.get(coord, null)
	if not zone_root:
		if _DEBUG_LOG: print("[WSS] request_creature_damage: zone (%d,%d) not loaded" % [zone_x, zone_z])
		return
	var idx := 0
	for child in zone_root.get_children():
		if child is CreatureAI:
			if idx == creature_idx:
				var creature: CreatureAI = child as CreatureAI
				if _DEBUG_LOG: print("[WSS] request_creature_damage: %.1f from peer %d → '%s'" % [clamped, source_peer, creature.name])
				var source: Node3D = creature._get_player_by_peer(source_peer)
				creature.take_damage(clamped, source)
				return
			idx += 1
	if _DEBUG_LOG: print("[WSS] request_creature_damage: creature idx %d not found in zone (%d,%d)" % [creature_idx, zone_x, zone_z])


@rpc("authority", "reliable")
func _csync_recv_states(zone_x: int, zone_z: int, indices: PackedInt32Array, states: PackedInt32Array, healths: PackedFloat32Array) -> void:
	if multiplayer.is_server():
		return
	var wg := _find_world_generator()
	if not wg:
		return
	var coord := Vector2i(zone_x, zone_z)
	var zone_root: Node = wg._loaded_zones.get(coord, null)
	if not zone_root:
		return
	var creatures: Array[CreatureAI] = []
	for child in zone_root.get_children():
		if child is CreatureAI:
			creatures.append(child)
	for i in indices.size():
		var ci: int = indices[i]
		if ci < creatures.size():
			var creature := creatures[ci]
			var new_state: int = states[i]
			var new_hp: float = healths[i]
			creature.current_health = new_hp
			if creature._state != new_state:
				creature._state = new_state as CreatureAI.State
				if new_state == CreatureAI.State.DEAD:
					creature._death_visual_started = false
