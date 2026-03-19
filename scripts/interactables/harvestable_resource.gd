class_name HarvestableResource
extends Interactable
## A destructible world resource (tree, rock, ore deposit).
## Each hit reduces HP and yields items. At 0 HP the object is destroyed
## (or hidden + respawned after a timer).
##
## Scene structure:
##   HarvestableResource (this script)
##   ├─ CollisionShape3D
##   ├─ MeshInstance3D
##   ├─ AudioStreamPlayer3D  (hit/destroy SFX)
##   └─ GPUParticles3D       (hit particles — optional)

signal resource_hit(remaining_hp: float)
signal resource_depleted()

enum ToolRequirement { NONE, AXE, PICKAXE }

@export_group("Resource Stats")
@export var max_hp: float = 50.0
@export var required_tool: ToolRequirement = ToolRequirement.NONE
## Minimum tool tier needed (0 = any, 1 = bronze, 2 = iron, etc.)
@export var min_tool_tier: int = 0

@export_group("Drops")
## Array of { "item_id": StringName, "amount_min": int, "amount_max": int }
@export var drop_table: Array[Dictionary] = []

@export_group("Respawn")
@export var respawns: bool = true
@export var respawn_time: float = 300.0  # 5 minutes

var current_hp: float

@onready var _mesh: MeshInstance3D = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var _particles: GPUParticles3D = $GPUParticles3D if has_node("GPUParticles3D") else null
@onready var _audio: AudioStreamPlayer3D = $AudioStreamPlayer3D if has_node("AudioStreamPlayer3D") else null


func _ready() -> void:
	super._ready()
	current_hp = max_hp


func get_interaction_verb() -> String:
	match required_tool:
		ToolRequirement.AXE:
			return "Chop"
		ToolRequirement.PICKAXE:
			return "Mine"
		_:
			return "Harvest"


func can_interact(player: CharacterBody3D) -> bool:
	if not super.can_interact(player):
		return false
	return current_hp > 0.0


func _do_interact(player: CharacterBody3D) -> void:
	var damage := _get_player_damage(player)
	_apply_damage(damage)

	if _particles:
		_particles.restart()
	if _audio:
		_audio.play()

	if current_hp <= 0.0:
		_on_depleted()


func _get_player_damage(player: CharacterBody3D) -> float:
	# TODO: Read equipped tool from player inventory and check tier/type.
	# For now, flat 10 damage per hit.
	return 10.0


func _apply_damage(amount: float) -> void:
	current_hp = maxf(current_hp - amount, 0.0)

	# Shake the mesh for juice
	if _mesh:
		var tween := create_tween()
		tween.tween_property(_mesh, "rotation:z", deg_to_rad(5.0), 0.05)
		tween.tween_property(_mesh, "rotation:z", deg_to_rad(-3.0), 0.05)
		tween.tween_property(_mesh, "rotation:z", 0.0, 0.08)

	resource_hit.emit(current_hp)
	_spawn_partial_drops()


func _spawn_partial_drops() -> void:
	for entry in drop_table:
		if randf() > 0.4:
			continue
		var amount := randi_range(1, max(1, entry.get("amount_min", 1)))
		var loot_table: Array = [{"id": entry.get("item_id", &"wood"), "min": amount, "max": amount, "chance": 1.0}]
		LootDrop.spawn_loot(get_tree(), global_position + Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0)), loot_table)


func _on_depleted() -> void:
	for entry in drop_table:
		var amount := randi_range(
			entry.get("amount_min", 1),
			entry.get("amount_max", 3)
		)
		var loot_table: Array = [{"id": entry.get("item_id", &"wood"), "min": amount, "max": amount, "chance": 1.0}]
		LootDrop.spawn_loot(get_tree(), global_position + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5)), loot_table)

	resource_depleted.emit()

	if respawns:
		_hide_and_respawn()
	else:
		queue_free()


func _hide_and_respawn() -> void:
	visible = false
	is_active = false
	# Disable collision while hidden
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)

	await get_tree().create_timer(respawn_time).timeout

	current_hp = max_hp
	visible = true
	is_active = true
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", false)
	interaction_available_changed.emit(true)
