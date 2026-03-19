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
	var parts := zone.name.split("_")
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
func record_object_destroyed(node: Node) -> void:
	if not NetworkManager.is_server():
		return
	var key := get_object_key_for_node(node)
	if key.is_empty():
		return
	_destroyed_objects[key] = Time.get_unix_time_from_system()
	# Broadcast to other clients so they remove it too
	_broadcast_destroyed.rpc(key)


## Call when a building is placed. Only on server.
func record_building_placed(build_id: StringName, position: Vector3, rotation_y: float, chest_contents: Array = []) -> void:
	if not NetworkManager.is_server():
		return
	var entry := {
		"build_id": str(build_id),
		"px": position.x,
		"py": position.y,
		"pz": position.z,
		"ry": rotation_y,
		"chest_contents": chest_contents,
	}
	_placed_buildings.append(entry)
	# Broadcast to other clients so they spawn it too
	_broadcast_building.rpc(entry)


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
	_placed_buildings = buildings
	_apply_mutations()
	world_state_received.emit()
	print("[WorldStateSync] Received world state: %d destroyed, %d buildings" % [destroyed.size(), buildings.size()])


@rpc("authority", "reliable")
func _broadcast_destroyed(key: String) -> void:
	_destroyed_objects[key] = Time.get_unix_time_from_system()
	_remove_destroyed_object(key)


@rpc("authority", "reliable")
func _broadcast_building(entry: Dictionary) -> void:
	_placed_buildings.append(entry)
	_spawn_building(entry)


## Apply mutations to locally-generated world. Call after receiving world state.
func _apply_mutations() -> void:
	for key in _destroyed_objects:
		_remove_destroyed_object(key)
	for entry in _placed_buildings:
		_spawn_building(entry)


func _remove_destroyed_object(key: String) -> void:
	var parts := key.split("_")
	if parts.size() < 3:
		return
	var zx := int(parts[0])
	var zz := int(parts[1])
	var target_idx := int(parts[2])
	var wg := _find_world_generator()
	if not wg:
		return
	var zone := wg.get_node_or_null("Zone_%d_%d" % [zx, zz])
	if not zone:
		return  # Zone not loaded yet; will apply when zone loads
	var idx := 0
	for child in zone.get_children():
		if child.is_in_group(&"interactables"):
			if idx == target_idx:
				child.queue_free()
				return
			idx += 1


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
