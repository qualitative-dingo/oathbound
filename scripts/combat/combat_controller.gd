class_name CombatController
extends Node
## Handles the player's combat actions: attacking, blocking, parrying, and dodge rolling.
## Reads from the equipped weapon/shield ItemData and the SkillSystem.
##
## Attach as a child of the Player node. Expects siblings:
##   - DamageSystem (for parry window management)
##   - SkillSystem (for skill-based damage scaling)
##   - An Area3D "HitBox" child that's toggled during attack frames

signal attack_started(weapon_skill: StringName)
signal attack_landed(target: Node3D, damage: float)
signal block_started()
signal block_ended()
signal parry_window_opened()
signal dodge_rolled()

@export_group("Dodge")
## Stamina cost of a dodge roll.
@export var dodge_stamina_cost: float = 15.0
## Duration of invulnerability frames during the dodge roll.
@export var dodge_iframe_duration: float = 0.2
## Total dodge roll animation time.
@export var dodge_roll_duration: float = 0.5
## Speed multiplier during the roll.
@export var dodge_speed: float = 8.0

@export_group("Block")
## How long the parry window lasts after pressing block (bucklers).
@export var parry_window_duration: float = 0.25

var is_attacking: bool = false
var is_blocking: bool = false
var is_dodging: bool = false

## Set by the inventory system when the player equips a weapon/shield.
var equipped_weapon: ItemData = null
var equipped_shield: ItemData = null

var _attack_cooldown: float = 0.0
var _parry_timer: float = 0.0
var _hitbox_active: bool = false

@onready var _damage_system: DamageSystem = _find_sibling(DamageSystem)
@onready var _skill_system: SkillSystem = _find_sibling(SkillSystem)
@onready var _hitbox: Area3D = get_parent().find_child("HitBox", true, false)
@onready var _player: CharacterBody3D = get_parent() as CharacterBody3D


func _ready() -> void:
	if _hitbox:
		_hitbox.body_entered.connect(_on_hitbox_body_entered)
		_hitbox.monitoring = false


func _process(delta: float) -> void:
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	# Parry window countdown
	if _parry_timer > 0.0:
		_parry_timer -= delta
		if _parry_timer <= 0.0 and _damage_system:
			_damage_system.is_parry_window_active = false


func _unhandled_input(event: InputEvent) -> void:
	if is_dodging:
		return

	if event.is_action_pressed(&"attack"):
		_try_attack()
	# Block on right mouse (could also be a separate input action)
	if event.is_action_pressed(&"block"):
		_start_block()
	if event.is_action_released(&"block"):
		_end_block()
	if event.is_action_pressed(&"dodge"):
		_try_dodge()


## --- Attack ---

func _try_attack() -> void:
	if is_attacking or _attack_cooldown > 0.0:
		return
	if not equipped_weapon:
		return

	var stamina_cost := equipped_weapon.attack_stamina_cost
	if not _player.has_method("_can_spend_stamina") or not _player._can_spend_stamina(stamina_cost):
		return

	_player._spend_stamina(stamina_cost)
	is_attacking = true

	# Determine damage with skill factor
	var skill_factor := 1.0
	if _skill_system and equipped_weapon.weapon_skill != &"":
		skill_factor = _skill_system.get_skill_factor(equipped_weapon.weapon_skill)
		_skill_system.add_xp(equipped_weapon.weapon_skill)

	var attack_damage := equipped_weapon.base_damage * skill_factor
	_attack_cooldown = 1.0 / equipped_weapon.attack_speed
	attack_started.emit(equipped_weapon.weapon_skill)

	# Activate hitbox for a brief window
	_activate_hitbox(attack_damage)

	# Deactivate after a short window
	await get_tree().create_timer(0.15).timeout
	_deactivate_hitbox()
	is_attacking = false


func _activate_hitbox(damage: float) -> void:
	_hitbox_active = true
	if _hitbox:
		_hitbox.monitoring = true
		_hitbox.set_meta(&"pending_damage", damage)


func _deactivate_hitbox() -> void:
	_hitbox_active = false
	if _hitbox:
		_hitbox.monitoring = false


func _on_hitbox_body_entered(body: Node3D) -> void:
	if body == _player:
		return
	var ds := body.find_child("DamageSystem", false, false) as DamageSystem
	if not ds:
		return

	var damage: float = _hitbox.get_meta(&"pending_damage", 10.0) if _hitbox else 10.0
	var result := ds.take_hit(
		damage,
		StringName(ItemData.DamageType.keys()[equipped_weapon.damage_type]) if equipped_weapon else &"BLUNT",
		equipped_weapon.stagger_multiplier if equipped_weapon else 1.0,
		equipped_weapon.knockback if equipped_weapon else 30.0,
		_player
	)
	if result.get("dealt", 0.0) > 0.0:
		attack_landed.emit(body, result["dealt"])


## --- Block / Parry ---

func _start_block() -> void:
	if not equipped_shield:
		return
	is_blocking = true
	block_started.emit()

	# Open the parry window at the start of the block
	var window: float = equipped_shield.parry_window
	if window > 0.0 and _damage_system:
		_damage_system.is_parry_window_active = true
		_parry_timer = window
		parry_window_opened.emit()


func _end_block() -> void:
	is_blocking = false
	if _damage_system:
		_damage_system.is_parry_window_active = false
	block_ended.emit()


## --- Dodge Roll ---

func _try_dodge() -> void:
	if is_dodging:
		return
	if not _player.has_method("_can_spend_stamina") or not _player._can_spend_stamina(dodge_stamina_cost):
		return

	_player._spend_stamina(dodge_stamina_cost)
	is_dodging = true
	dodge_rolled.emit()

	# Grant i-frames
	if _damage_system:
		_damage_system.set_invulnerable(dodge_iframe_duration)

	# After roll completes, allow actions again
	await get_tree().create_timer(dodge_roll_duration).timeout
	is_dodging = false


## --- Utility ---

func _find_sibling(type: Variant) -> Node:
	if not get_parent():
		return null
	for child in get_parent().get_children():
		if is_instance_of(child, type):
			return child
	return null
