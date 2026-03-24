extends Node
## NetworkManager autoload — handles hosting and joining LAN games.
## Uses ENetMultiplayerPeer for low-latency LAN multiplayer.
const _DEBUG_LOG := false

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded()
signal connection_failed()
signal server_started()
signal world_info_received()
## Phase 4d: emitted when chest contents are received (path, contents)
signal chest_contents_received(chest_path: String, contents: Array)

var is_hosting := false
var world_seed: String = ""
var world_name: String = ""
var character_name: String = ""

## Phase 5: Cached player data from clients (peer_id -> {character_id, player, inventory})
var _player_data_cache: Dictionary = {}


func host_game(port: int = DEFAULT_PORT) -> Error:
	_cleanup_old_session()

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("[NET] Failed to create server on port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	is_hosting = true

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	if _DEBUG_LOG: print("[NET] Server started on port %d (peer_id=%d)" % [port, multiplayer.get_unique_id()])
	server_started.emit()
	call_deferred("_deferred_spawn_host")
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
	_cleanup_old_session()

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		push_error("[NET] Failed to connect to %s:%d: %s" % [address, port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	is_hosting = false

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

	if _DEBUG_LOG: print("[NET] Connecting to %s:%d..." % [address, port])
	return OK


func _cleanup_old_session() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	if multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.disconnect(_on_connection_failed)
	_spawned_peers.clear()
	_player_data_cache.clear()
	is_hosting = false


func disconnect_game() -> void:
	_cleanup_old_session()
	if _DEBUG_LOG: print("[NET] Disconnected")


func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


func is_connected_to_game() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func get_peer_id() -> int:
	if multiplayer.multiplayer_peer:
		return multiplayer.get_unique_id()
	return 1


func get_connected_peers() -> PackedInt32Array:
	if multiplayer.multiplayer_peer:
		return multiplayer.get_peers()
	return PackedInt32Array()


@rpc("any_peer", "reliable")
func _request_world_info() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_send_world_info.rpc_id(sender, world_seed, world_name)


@rpc("authority", "reliable")
func _send_world_info(seed_str: String, w_name: String) -> void:
	world_seed = seed_str
	world_name = w_name
	if _DEBUG_LOG: print("[NET] Received world info: seed=%s name=%s" % [seed_str, w_name])
	world_info_received.emit()


func _on_peer_connected(id: int) -> void:
	if _DEBUG_LOG: print("[NET] Peer connected: %d" % id)
	player_connected.emit(id)
	if is_server() and id != multiplayer.get_unique_id():
		_send_world_info.rpc_id(id, world_seed, world_name)
		# Spawn client player after a delay to give them time to load the world
		_spawn_client_deferred(id)


func _on_peer_disconnected(id: int) -> void:
	if _DEBUG_LOG: print("[NET] Peer disconnected: %d" % id)
	# 5c: Save player data before removing
	if is_server():
		_save_player_data(id)
	despawn_player(id)
	_player_data_cache.erase(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	if _DEBUG_LOG: print("[NET] Connected to server (my peer_id=%d)" % multiplayer.get_unique_id())
	connection_succeeded.emit()
	# World info is now auto-sent by the host in _on_peer_connected


func _on_connection_failed() -> void:
	if _DEBUG_LOG: print("[NET] Connection failed")
	connection_failed.emit()
	disconnect_game()


var _spawned_peers: Dictionary = {}


func _spawn_client_deferred(peer_id: int) -> void:
	# Give client 3 seconds to load the world, then spawn their player
	if _DEBUG_LOG: print("[NET-HOST] Will spawn client %d in 3 seconds..." % peer_id)
	await get_tree().create_timer(3.0).timeout
	if _spawned_peers.has(peer_id):
		return
	if not multiplayer.get_peers().has(peer_id):
		if _DEBUG_LOG: print("[NET-HOST] Client %d disconnected before spawn" % peer_id)
		return
	if _DEBUG_LOG: print("[NET-HOST] Timer elapsed, spawning client %d" % peer_id)
	spawn_player(peer_id)


@rpc("any_peer", "reliable")
func client_world_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _spawned_peers.has(sender):
		return
	if _DEBUG_LOG: print("[NET-HOST] Client %d reports world ready, spawning early" % sender)
	spawn_player(sender)
	# Also tell client to create host player representation
	_rpc_create_player.rpc_id(sender, multiplayer.get_unique_id())


func notify_server_ready() -> void:
	if _DEBUG_LOG: print("[NET-CLIENT] notify_server_ready called, peer=%d" % multiplayer.get_unique_id())
	if is_server():
		return
	# Wait until the Players container exists
	var attempts := 0
	while not _get_players_container() and attempts < 120:
		await get_tree().process_frame
		attempts += 1
	if _get_players_container():
		if _DEBUG_LOG: print("[NET-CLIENT] World ready, sending client_world_ready RPC")
		client_world_ready.rpc_id(1)
	else:
		push_error("[NET-CLIENT] Players container not found after 120 frames")


func _deferred_spawn_host() -> void:
	var attempts := 0
	while not _get_players_container() and attempts < 60:
		await get_tree().process_frame
		attempts += 1
	spawn_player(multiplayer.get_unique_id())


func spawn_player(peer_id: int) -> void:
	if not is_server():
		return
	var players_node := _get_players_container()
	if not players_node:
		push_error("[NET] No Players container found; cannot spawn player %d" % peer_id)
		return
	if _DEBUG_LOG: print("[NET] spawn_player(%d): Players container at %s" % [peer_id, str(players_node.get_path())])
	if peer_id == multiplayer.get_unique_id():
		var default_player := players_node.get_node_or_null("Player")
		if default_player:
			default_player.queue_free()
	# Create player on host
	_create_player_node(peer_id, players_node)
	_spawned_peers[peer_id] = true
	# Tell the client to create their own player locally
	if peer_id != multiplayer.get_unique_id():
		_rpc_create_player.rpc_id(peer_id, peer_id)
	if _DEBUG_LOG: print("[NET] Spawned player %d" % peer_id)


func _create_player_node(peer_id: int, players_node: Node) -> void:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.position = Vector3(0, 2, 0)
	players_node.add_child(player, true)


@rpc("authority", "reliable")
func _rpc_create_player(peer_id: int) -> void:
	var players_node := _get_players_container()
	if not players_node:
		push_error("[NET-CLIENT] No Players container for player creation!")
		return
	var default_player := players_node.get_node_or_null("Player")
	if default_player:
		default_player.queue_free()
	if players_node.has_node(str(peer_id)):
		if _DEBUG_LOG: print("[NET-CLIENT] Player %d already exists, skipping" % peer_id)
		return
	if _DEBUG_LOG: print("[NET-CLIENT] Creating local player %d" % peer_id)
	_create_player_node(peer_id, players_node)


func despawn_player(peer_id: int) -> void:
	if not is_server():
		return
	var players_node := _get_players_container()
	if not players_node:
		return
	var player_node := players_node.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
		if _DEBUG_LOG: print("[NET] Despawned player %d" % peer_id)


func _get_players_container() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	var current := tree.current_scene
	if not current:
		return null
	return current.get_node_or_null("Players")


# ═══════════════════════════════════════════════════════════════════════════════
# Phase 4d: Chest sharing (host-authoritative)
# ═══════════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "reliable")
func request_open_chest(chest_path: String) -> void:
	if not is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	var chest := get_tree().root.get_node_or_null(chest_path) as Node3D
	if not chest:
		return
	var contents: Array = chest.get_meta("chest_contents", []) as Array
	_update_chest_contents.rpc_id(sender, chest_path, contents)


@rpc("any_peer", "reliable")
func request_deposit_to_chest(chest_path: String, item_id: String, amount: int) -> void:
	if not is_server():
		return
	var chest := get_tree().root.get_node_or_null(chest_path) as Node3D
	if not chest or not chest.has_meta("chest_contents"):
		return
	var contents: Array = (chest.get_meta("chest_contents", []) as Array).duplicate(true)
	while contents.size() < 32:
		contents.append({})
	var stack_size: int = ItemDatabase.get_item(StringName(item_id)).get("stack_size", 50)
	var remaining := amount
	const CHEST_SLOTS := 32
	for i in CHEST_SLOTS:
		if remaining <= 0:
			break
		var sd: Dictionary = contents[i] if i < contents.size() else {}
		if sd.get("item_id", &"") == StringName(item_id):
			var cur: int = int(sd.get("count", 0))
			var space := stack_size - cur
			var add := mini(remaining, space)
			if add > 0:
				contents[i] = {"item_id": StringName(item_id), "count": cur + add}
				remaining -= add
	for i in CHEST_SLOTS:
		if remaining <= 0:
			break
		var sd: Dictionary = contents[i] if i < contents.size() else {}
		if sd.is_empty() or sd.get("item_id", &"") == &"":
			var add := mini(remaining, stack_size)
			contents[i] = {"item_id": StringName(item_id), "count": add}
			remaining -= add
	if remaining < amount:
		chest.set_meta("chest_contents", contents)
		_update_chest_contents.rpc(chest_path, contents)


@rpc("any_peer", "reliable")
func request_withdraw_from_chest(chest_path: String, item_id: String, amount: int) -> void:
	if not is_server():
		return
	var chest := get_tree().root.get_node_or_null(chest_path) as Node3D
	if not chest or not chest.has_meta("chest_contents"):
		return
	var contents: Array = (chest.get_meta("chest_contents", []) as Array).duplicate(true)
	var removed := 0
	for i in range(contents.size() - 1, -1, -1):
		if removed >= amount:
			break
		var sd: Dictionary = contents[i] if i < contents.size() else {}
		if sd.get("item_id", &"") != StringName(item_id):
			continue
		var take := mini(amount - removed, int(sd.get("count", 0)))
		sd["count"] = int(sd.get("count", 0)) - take
		removed += take
		if sd.get("count", 0) <= 0:
			contents[i] = {}
		else:
			contents[i] = sd
	if removed > 0:
		chest.set_meta("chest_contents", contents)
		_update_chest_contents.rpc(chest_path, contents)


@rpc("authority", "reliable")
func _update_chest_contents(chest_path: String, contents: Array) -> void:
	chest_contents_received.emit(chest_path, contents)


# ═══════════════════════════════════════════════════════════════════════════════
# Phase 5: Player data sync and disconnect save
# ═══════════════════════════════════════════════════════════════════════════════

## Clients call this to report their player data to the host (for save on disconnect).
@rpc("any_peer", "reliable")
func report_player_data(character_id: String, player_data: Dictionary, inventory_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	_player_data_cache[sender] = {
		"character_id": character_id,
		"player": player_data,
		"inventory": inventory_data,
	}


func get_cached_player_data(peer_id: int) -> Dictionary:
	return _player_data_cache.get(peer_id, {})


func cache_local_player_data(peer_id: int, character_id: String, player_data: Dictionary, inventory_data: Dictionary) -> void:
	if not is_server():
		return
	_player_data_cache[peer_id] = {
		"character_id": character_id,
		"player": player_data,
		"inventory": inventory_data,
	}


func _save_player_data(peer_id: int) -> void:
	var cached: Dictionary = _player_data_cache.get(peer_id, {})
	if cached.is_empty():
		# Fallback: get position from replicated player node (inventory not available on host)
		var player_node := _get_player_by_peer(peer_id)
		if player_node:
			var p := player_node as CharacterBody3D
			if p:
				var player_data := {
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
				SaveManager.save_disconnected_player(peer_id, str(peer_id), player_data, {})
		return
	var char_id: String = str(cached.get("character_id", peer_id))
	SaveManager.save_disconnected_player(peer_id, char_id, cached["player"], cached["inventory"])


func _get_player_by_peer(peer_id: int) -> Node:
	var players_node := _get_players_container()
	if not players_node:
		return null
	return players_node.get_node_or_null(str(peer_id))


func _serialize_inventory_from(inv: PlayerInventory) -> Dictionary:
	var result: Dictionary = {}
	result["items"] = inv.get_all_items().duplicate()
	var order_strings: Array[String] = []
	for sid: StringName in inv.get_order():
		order_strings.append(String(sid))
	result["order"] = order_strings
	var eq: Dictionary = {}
	for slot: String in inv.get_all_equipped().keys():
		eq[slot] = String(inv.get_equipped(slot))
	result["equipped"] = eq
	return result
