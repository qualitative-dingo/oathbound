class_name ProgressionManager
extends Node
## Tracks which bosses have been defeated and what tier of content is unlocked.
## Kill boss -> get key item -> unlock next tier's stations/recipes -> access next biome's resources.
##
## Register as autoload: GameProgression

signal tier_unlocked(tier: int, boss_id: StringName)
signal boss_power_activated(boss_id: StringName)
signal boss_power_deactivated()

## Biome tiers. Currently only Hearthlands (tier 1); more biomes will be added later.
const TIER_DATA: Array[Dictionary] = [
	{
		"tier": 1,
		"biome": &"hearthlands",
		"boss": &"the_stag_king",
		"boss_drop": &"antler_pick",
		"unlocks_station": &"",
		"unlocks_description": "Antler Pick — mine copper and tin",
		"boss_power": "Movement speed +30% for 5 min",
	},
]

## Tracks defeated bosses by their StringName id.
var defeated_bosses: Dictionary = {}
## Currently active boss power (only one at a time, on cooldown).
var active_boss_power: StringName = &""
var boss_power_cooldown: float = 0.0
## Boss power duration and cooldown (5 min active, 20 min cooldown).
const BOSS_POWER_DURATION: float = 300.0
const BOSS_POWER_COOLDOWN: float = 1200.0

var _power_timer: float = 0.0
var _power_active: bool = false


func _process(delta: float) -> void:
	if boss_power_cooldown > 0.0:
		boss_power_cooldown -= delta
	if _power_active:
		_power_timer -= delta
		if _power_timer <= 0.0:
			_deactivate_power()


func get_current_tier() -> int:
	if defeated_bosses.is_empty():
		return 1
	var highest := 0
	for boss_id in defeated_bosses:
		for data in TIER_DATA:
			if data["boss"] == boss_id:
				highest = maxi(highest, data["tier"] as int)
	return highest + 1


func is_boss_defeated(boss_id: StringName) -> bool:
	return defeated_bosses.has(boss_id)


func defeat_boss(boss_id: StringName) -> void:
	if defeated_bosses.has(boss_id):
		return
	defeated_bosses[boss_id] = true
	var new_tier := get_current_tier()
	tier_unlocked.emit(new_tier, boss_id)


func is_station_unlocked(station_type: StringName) -> bool:
	## A station is unlocked if the tier that grants it has been reached.
	for data in TIER_DATA:
		if data["unlocks_station"] == station_type:
			return get_current_tier() > data["tier"] as int
	# Stations not gated by bosses (workbench, forge) are always available.
	return true


func activate_boss_power(boss_id: StringName) -> void:
	if boss_power_cooldown > 0.0:
		return
	if not is_boss_defeated(boss_id):
		return
	active_boss_power = boss_id
	_power_active = true
	_power_timer = BOSS_POWER_DURATION
	boss_power_activated.emit(boss_id)


func _deactivate_power() -> void:
	_power_active = false
	boss_power_cooldown = BOSS_POWER_COOLDOWN
	boss_power_deactivated.emit()
	active_boss_power = &""


## --- Save / Load ---

func serialize() -> Dictionary:
	return {
		"defeated_bosses": defeated_bosses.keys(),
		"active_power": active_boss_power,
		"power_timer": _power_timer,
		"power_cooldown": boss_power_cooldown,
	}


func deserialize(data: Dictionary) -> void:
	defeated_bosses.clear()
	for boss_id in data.get("defeated_bosses", []):
		defeated_bosses[StringName(boss_id)] = true
	active_boss_power = StringName(data.get("active_power", ""))
	_power_timer = data.get("power_timer", 0.0)
	boss_power_cooldown = data.get("power_cooldown", 0.0)
	_power_active = _power_timer > 0.0
