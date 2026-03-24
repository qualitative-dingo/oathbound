class_name CreatureSyncManager
extends Node

const _DEBUG_LOG := false

## Batched creature state synchronization from host to clients.
##
## The host collects creature positions/states from loaded zones and broadcasts
## them to clients at a fixed interval. Position updates use unreliable RPCs
## (high frequency, loss tolerable on LAN). State changes (death, aggro) use
## reliable RPCs.

const SYNC_INTERVAL := 0.1  # seconds between position broadcasts
const STATE_SYNC_INTERVAL := 0.2  # seconds between state snapshots

var _sync_timer: float = 0.0
var _state_timer: float = 0.0
var _last_creature_states: Dictionary = {}  # "zone_key/creature_name" -> {state, health}
var _diag_tick: int = 0


func _ready() -> void:
	add_to_group(&"creature_sync_manager")
	if _DEBUG_LOG: print("[CSM] CreatureSyncManager ready | is_server=%s path=%s" % [str(multiplayer.is_server()), str(get_path())])


func _physics_process(_delta: float) -> void:
	# Creature sync is now handled by WorldStateSync (scene-file node with
	# guaranteed matching paths for RPCs). This node is kept for backward compat.
	pass


func _broadcast_creature_positions() -> void:
	var world_gen := _get_world_generator()
	if not world_gen:
		return
	var loaded_zones: Dictionary = world_gen._loaded_zones
	for coord: Vector2i in loaded_zones:
		var zone_root: Node = loaded_zones[coord]
		if not is_instance_valid(zone_root):
			continue
		var positions := PackedFloat32Array()
		var rotations := PackedFloat32Array()
		var velocities := PackedFloat32Array()
		var count := 0
		for child in zone_root.get_children():
			if child is CreatureAI:
				var creature: CreatureAI = child as CreatureAI
				positions.append(creature.global_position.x)
				positions.append(creature.global_position.y)
				positions.append(creature.global_position.z)
				rotations.append(creature.rotation.y)
				velocities.append(creature.velocity.x)
				velocities.append(creature.velocity.y)
				velocities.append(creature.velocity.z)
				count += 1
		if count > 0:
			if _diag_tick <= 3 or _diag_tick % 100 == 0:
				if _DEBUG_LOG: print("[CSM-HOST] Broadcasting zone (%d,%d): %d creatures" % [coord.x, coord.y, count])
			_receive_positions.rpc(coord.x, coord.y, positions, rotations, velocities)


func _broadcast_creature_state_changes() -> void:
	var world_gen := _get_world_generator()
	if not world_gen:
		return
	var loaded_zones: Dictionary = world_gen._loaded_zones
	for coord: Vector2i in loaded_zones:
		var zone_root: Node = loaded_zones[coord]
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
				var prev: Dictionary = _last_creature_states.get(key, {})
				if prev.is_empty() or prev.get("state", -1) != cur_state or absf(prev.get("health", -1.0) - cur_hp) > 0.5:
					indices.append(idx)
					states.append(cur_state)
					healths.append(cur_hp)
					_last_creature_states[key] = {"state": cur_state, "health": cur_hp}
				idx += 1
		if not indices.is_empty():
			_receive_state_changes.rpc(coord.x, coord.y, indices, states, healths)


var _recv_diag: int = 0

@rpc("authority", "unreliable")
func _receive_positions(zone_x: int, zone_z: int, positions: PackedFloat32Array, rotations: PackedFloat32Array, velocities: PackedFloat32Array) -> void:
	if multiplayer.is_server():
		return
	_recv_diag += 1
	var zone_root := _find_zone(zone_x, zone_z)
	if not zone_root:
		if _recv_diag <= 5 or _recv_diag % 300 == 0:
			if _DEBUG_LOG: print("[CSM-CLIENT] Zone (%d,%d) NOT FOUND on client (recv #%d)" % [zone_x, zone_z, _recv_diag])
		return
	var idx := 0
	var pos_i := 0
	for child in zone_root.get_children():
		if child is CreatureAI:
			var creature: CreatureAI = child as CreatureAI
			if pos_i + 2 < positions.size():
				var target_pos := Vector3(positions[pos_i], positions[pos_i + 1], positions[pos_i + 2])
				if not creature._sync_initialized:
					creature.global_position = target_pos
					creature._sync_initialized = true
					if _DEBUG_LOG: print("[CSM-CLIENT] Creature '%s' in zone (%d,%d) initialized at %s" % [creature.name, zone_x, zone_z, str(target_pos)])
				creature._sync_target_position = target_pos
				creature.velocity = Vector3(velocities[pos_i], velocities[pos_i + 1], velocities[pos_i + 2])
				creature.rotation.y = rotations[idx]
			pos_i += 3
			idx += 1
	if _recv_diag <= 3 or _recv_diag % 300 == 0:
		if _DEBUG_LOG: print("[CSM-CLIENT] Recv #%d zone (%d,%d): applied to %d creatures" % [_recv_diag, zone_x, zone_z, idx])


@rpc("authority", "reliable")
func _receive_state_changes(zone_x: int, zone_z: int, indices: PackedInt32Array, states: PackedInt32Array, healths: PackedFloat32Array) -> void:
	if multiplayer.is_server():
		return
	var zone_root := _find_zone(zone_x, zone_z)
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


func _find_zone(zone_x: int, zone_z: int) -> Node:
	var world_gen := _get_world_generator()
	if not world_gen:
		return null
	var coord := Vector2i(zone_x, zone_z)
	return world_gen._loaded_zones.get(coord, null) as Node


func _get_world_generator() -> Node:
	var scene := get_tree().current_scene
	if not scene:
		return null
	return scene.get_node_or_null("WorldGenerator")
