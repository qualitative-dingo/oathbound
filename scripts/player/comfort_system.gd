class_name ComfortSystem
extends Node
## Calculates the player's comfort level from nearby furniture and applies
## the Rested buff. Sitting near a fire for 20 seconds grants
## Rested, whose duration depends on comfort level.
##
## Comfort rules:
##   - Only the highest-tier item per furniture category counts.
##   - Categories: fire, bed, seating, table, decoration, banner, rug, etc.
##   - Base comfort = 1 (just a fire).
##   - Each unique category adds +1 comfort.
##   - Rested duration = 8 minutes + 1 minute per comfort level.
##   - Rested buff multiplies HP and stamina regen.

signal comfort_changed(level: int)
signal rested_started(duration: float)
signal rested_expired()

const BASE_RESTED_DURATION := 480.0  # 8 minutes in seconds
const RESTED_PER_COMFORT := 60.0     # +1 minute per comfort level
const RESTED_REGEN_MULTIPLIER := 1.5
const TIME_TO_REST := 20.0           # Must sit near fire for 20s

## Area3D on the player that detects furniture nodes in range.
@export var detection_radius: float = 10.0

var comfort_level: int = 0
var is_rested: bool = false
var rested_remaining: float = 0.0
var _resting_timer: float = 0.0
var _near_fire: bool = false
var _sitting: bool = false


func _process(delta: float) -> void:
	# Tick down rested buff
	if is_rested:
		rested_remaining -= delta
		if rested_remaining <= 0.0:
			is_rested = false
			rested_expired.emit()

	# Accumulate resting time if conditions met
	if _near_fire and _sitting:
		_resting_timer += delta
		if _resting_timer >= TIME_TO_REST and not is_rested:
			_activate_rested()
	else:
		_resting_timer = 0.0


func set_near_fire(value: bool) -> void:
	_near_fire = value

func set_sitting(value: bool) -> void:
	_sitting = value


func recalculate_comfort(furniture_in_range: Array[Node3D]) -> void:
	## Each furniture node should have metadata: "comfort_category" (StringName)
	## and optionally "comfort_tier" (int). Only the highest tier per category counts.
	var categories: Dictionary = {}  # category -> highest tier

	for node in furniture_in_range:
		var category: StringName = node.get_meta(&"comfort_category", &"")
		if category == &"":
			continue
		var tier: int = node.get_meta(&"comfort_tier", 1)
		if not categories.has(category) or tier > categories[category]:
			categories[category] = tier

	# Comfort = number of unique categories present (minimum 1 if near fire)
	comfort_level = maxi(categories.size(), 1 if _near_fire else 0)
	comfort_changed.emit(comfort_level)


func get_rested_duration() -> float:
	return BASE_RESTED_DURATION + comfort_level * RESTED_PER_COMFORT


func get_regen_multiplier() -> float:
	return RESTED_REGEN_MULTIPLIER if is_rested else 1.0


func _activate_rested() -> void:
	is_rested = true
	rested_remaining = get_rested_duration()
	rested_started.emit(rested_remaining)


## --- Save / Load ---

func serialize() -> Dictionary:
	return {
		"is_rested": is_rested,
		"rested_remaining": rested_remaining,
	}

func deserialize(data: Dictionary) -> void:
	is_rested = data.get("is_rested", false)
	rested_remaining = data.get("rested_remaining", 0.0)
