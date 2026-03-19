class_name DamageSystem
extends Node
## Central damage resolution. Handles incoming hits, stagger accumulation,
## parry checks, damage type resistances, and dodge i-frames.
##
## Attach as a child of any entity that can take damage (player, creatures,
## destructible buildings). The parent must be a CharacterBody3D or StaticBody3D.
##
## Oathbound damage rules:
##   - Physical damage types: Slash, Pierce, Blunt
##   - Elemental: Fire, Frost, Lightning, Poison, Spirit
##   - Creatures have per-type resistances: Immune, VeryResistant, Resistant, Normal, Weak, VeryWeak
##   - Stagger: cumulative damage within a window triggers a stun (2x damage taken during stagger)
##   - Parry: timed block with buckler negates all damage + stamina cost and auto-staggers attacker
##   - Dodge roll: brief invulnerability frames

signal damage_taken(amount: float, type: StringName, source: Node3D)
signal healed(amount: float)
signal staggered()
signal stagger_recovered()
signal died()
signal parry_succeeded(attacker: Node3D)

enum Resistance { IMMUNE, VERY_RESISTANT, RESISTANT, NORMAL, WEAK, VERY_WEAK }

const RESISTANCE_MULTIPLIERS: Dictionary = {
	Resistance.IMMUNE: 0.0,
	Resistance.VERY_RESISTANT: 0.25,
	Resistance.RESISTANT: 0.5,
	Resistance.NORMAL: 1.0,
	Resistance.WEAK: 1.5,
	Resistance.VERY_WEAK: 2.0,
}

@export var max_health: float = 100.0
@export var base_armor: float = 0.0
## Stagger threshold = max_health * stagger_threshold_fraction.
## Player stagger threshold scales with max HP (from food).
@export var stagger_threshold_fraction: float = 0.3
## How long the stagger stun lasts.
@export var stagger_duration: float = 1.5
## Time window for stagger damage accumulation to reset.
@export var stagger_reset_time: float = 3.0

## Per damage-type resistance map. Keys are DamageType enum names as StringName.
@export var resistances: Dictionary = {}

var current_health: float
var is_dead: bool = false
var is_staggered: bool = false
var is_invulnerable: bool = false  # Set during dodge i-frames

var _stagger_accumulator: float = 0.0
var _stagger_reset_timer: float = 0.0
var _stagger_timer: float = 0.0

## Parry state (managed externally by shield/blocking code, read here)
var is_parry_window_active: bool = false


func _ready() -> void:
	current_health = max_health


func _process(delta: float) -> void:
	# Stagger accumulator reset
	if _stagger_reset_timer > 0.0:
		_stagger_reset_timer -= delta
		if _stagger_reset_timer <= 0.0:
			_stagger_accumulator = 0.0

	# Stagger recovery
	if is_staggered:
		_stagger_timer -= delta
		if _stagger_timer <= 0.0:
			is_staggered = false
			stagger_recovered.emit()


## Main entry point for dealing damage to this entity.
func take_hit(
	base_damage: float,
	damage_type: StringName,
	stagger_multiplier: float,
	knockback_force: float,
	source: Node3D
) -> Dictionary:
	if is_dead:
		return { "dealt": 0.0, "blocked": true }

	# Dodge i-frames
	if is_invulnerable:
		return { "dealt": 0.0, "dodged": true }

	# Parry check — must happen before damage calculation
	if is_parry_window_active:
		_on_parry(source)
		return { "dealt": 0.0, "parried": true }

	# Apply resistance
	var resistance: int = resistances.get(damage_type, Resistance.NORMAL)
	var resist_mult: float = RESISTANCE_MULTIPLIERS.get(resistance, 1.0)
	var effective_damage := base_damage * resist_mult

	# Armor reduction (flat subtraction, minimum 1 damage if not immune)
	if resist_mult > 0.0:
		effective_damage = maxf(effective_damage - base_armor, 1.0)

	# Stagger during stagger = double damage
	if is_staggered:
		effective_damage *= 2.0

	current_health -= effective_damage
	damage_taken.emit(effective_damage, damage_type, source)

	# Stagger accumulation
	var stagger_damage := effective_damage * stagger_multiplier
	_stagger_accumulator += stagger_damage
	_stagger_reset_timer = stagger_reset_time

	var stagger_threshold := max_health * stagger_threshold_fraction
	if _stagger_accumulator >= stagger_threshold and not is_staggered:
		_trigger_stagger()

	# Death check
	if current_health <= 0.0:
		current_health = 0.0
		_on_death()

	return { "dealt": effective_damage, "staggered": is_staggered }


func heal(amount: float) -> void:
	if is_dead:
		return
	current_health = minf(current_health + amount, max_health)
	healed.emit(amount)


## Called by dodge roll to grant i-frames.
func set_invulnerable(duration: float) -> void:
	is_invulnerable = true
	get_tree().create_timer(duration).timeout.connect(
		func(): is_invulnerable = false
	)


func _trigger_stagger() -> void:
	is_staggered = true
	_stagger_timer = stagger_duration
	_stagger_accumulator = 0.0
	staggered.emit()


func _on_parry(attacker: Node3D) -> void:
	# Parry negates all damage and auto-staggers the attacker
	parry_succeeded.emit(attacker)
	# Try to stagger the attacker
	if attacker.has_node("DamageSystem"):
		var attacker_ds: DamageSystem = attacker.get_node("DamageSystem")
		attacker_ds._trigger_stagger()


func _on_death() -> void:
	is_dead = true
	died.emit()
