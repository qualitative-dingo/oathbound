extends Node
## NetworkManager autoload — handles hosting and joining LAN games.
## Uses ENetMultiplayerPeer for low-latency LAN multiplayer.

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded()
signal connection_failed()
signal server_started()

var is_hosting := false
var world_seed: String = ""
var world_name: String = ""
var character_name: String = ""


func host_game(port: int = DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("[NET] Failed to create server on port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	is_hosting = true

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	player_connected.connect(spawn_player)
	player_disconnected.connect(despawn_player)

	print("[NET] Server started on port %d (peer_id=%d)" % [port, multiplayer.get_unique_id()])
	server_started.emit()
	spawn_player(multiplayer.get_unique_id())
	return OK


func join_game(address: String, port: int = DEFAULT_PORT) -> Error:
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

	print("[NET] Connecting to %s:%d..." % [address, port])
	return OK


func disconnect_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_hosting = false
	print("[NET] Disconnected")


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
	print("[NET] Received world info: seed=%s name=%s" % [seed_str, w_name])


func _on_peer_connected(id: int) -> void:
	print("[NET] Peer connected: %d" % id)
	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("[NET] Peer disconnected: %d" % id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	print("[NET] Connected to server (my peer_id=%d)" % multiplayer.get_unique_id())
	connection_succeeded.emit()
	_request_world_info.rpc_id(1)


func _on_connection_failed() -> void:
	print("[NET] Connection failed")
	connection_failed.emit()
	disconnect_game()


func spawn_player(peer_id: int) -> void:
	if not is_server():
		return
	var players_node := _get_players_container()
	if not players_node:
		push_error("[NET] No Players container found; cannot spawn player %d" % peer_id)
		return
	# Remove default single-player Player when spawning host
	if peer_id == multiplayer.get_unique_id():
		var default_player := players_node.get_node_or_null("Player")
		if default_player:
			default_player.queue_free()
	var player := PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)
	players_node.add_child(player)
	print("[NET] Spawned player %d" % peer_id)


func despawn_player(peer_id: int) -> void:
	if not is_server():
		return
	var players_node := _get_players_container()
	if not players_node:
		return
	var player_node := players_node.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
		print("[NET] Despawned player %d" % peer_id)


func _get_players_container() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	var current := tree.current_scene
	if not current:
		return null
	return current.get_node_or_null("Players")
