class_name FoodSystem
extends Node
## Manages the player's food buff slots (max 3 simultaneous).
##
## Without food the player has base 25 HP and 50 stamina — you MUST eat
## to have meaningful stat pools. Each food provides max HP, max stamina,
## and/or max eitr (mana) for a duration. The buff strength decays linearly
## over the food's duration.
##
## The fork icon color convention:
##   Red   = primarily HP
##   Yellow = primarily Stamina
##   Blue  = primarily Eitr
##   White = balanced
##
## Eating the same food type while its buff is still active refreshes
## both the remaining strength and duration to full.

signal food_slot_changed(slot_index: int, food_data: Dictionary)
signal food_expired(slot_index: int)
signal stats_changed(total_hp: float, total_stamina: float, total_eitr: float)

const MAX_FOOD_SLOTS := 3
const BASE_HEALTH := 25.0
const BASE_STAMINA := 50.0
const BASE_EITR := 0.0

## Each slot: { "item_id": StringName, "health": float, "stamina": float,
##              "eitr": float, "regen": float, "duration": float, "remaining": float }
## Empty slot = {}
var food_slots: Array[Dictionary] = [{}, {}, {}]


func _process(delta: float) -> void:
	var changed := false
	for i in MAX_FOOD_SLOTS:
		if food_slots[i].is_empty():
			continue
		food_slots[i]["remaining"] = food_slots[i].get("remaining", 0.0) - delta
		if food_slots[i]["remaining"] <= 0.0:
			food_slots[i] = {}
			food_expired.emit(i)
			changed = true
	if changed:
		_emit_stats()


## Attempts to eat a food item. Returns true if consumed.
func eat(item: ItemData) -> bool:
	if item.item_type != ItemData.ItemType.FOOD:
		return false

	# Check if we already have this food active — refresh it
	for i in MAX_FOOD_SLOTS:
		if food_slots[i].get("item_id") == item.id:
			_apply_food_to_slot(i, item)
			return true

	# Find an empty slot
	for i in MAX_FOOD_SLOTS:
		if food_slots[i].is_empty():
			_apply_food_to_slot(i, item)
			return true

	# All slots full — check if any food is nearly expired (< 20% remaining)
	# and replace the most-expired one (auto-replaces when you eat)
	var worst_slot := -1
	var worst_ratio := 1.0
	for i in MAX_FOOD_SLOTS:
		var ratio: float = food_slots[i].get("remaining", 0.0) / food_slots[i].get("duration", 1.0)
		if ratio < worst_ratio:
			worst_ratio = ratio
			worst_slot = i
	if worst_slot >= 0 and worst_ratio < 0.2:
		_apply_food_to_slot(worst_slot, item)
		return true

	return false


func get_total_max_health() -> float:
	var total := BASE_HEALTH
	for slot in food_slots:
		if slot.is_empty():
			continue
		var ratio: float = slot.get("remaining", 0.0) / slot.get("duration", 1.0)
		total += slot.get("health", 0.0) * ratio
	return total


func get_total_max_stamina() -> float:
	var total := BASE_STAMINA
	for slot in food_slots:
		if slot.is_empty():
			continue
		var ratio: float = slot.get("remaining", 0.0) / slot.get("duration", 1.0)
		total += slot.get("stamina", 0.0) * ratio
	return total


func get_total_max_eitr() -> float:
	var total := BASE_EITR
	for slot in food_slots:
		if slot.is_empty():
			continue
		var ratio: float = slot.get("remaining", 0.0) / slot.get("duration", 1.0)
		total += slot.get("eitr", 0.0) * ratio
	return total


func get_total_regen() -> float:
	var total := 0.0
	for slot in food_slots:
		if slot.is_empty():
			continue
		total += slot.get("regen", 0.0)
	return total


func get_slot_info(index: int) -> Dictionary:
	return food_slots[index]


func _apply_food_to_slot(index: int, item: ItemData) -> void:
	food_slots[index] = {
		"item_id": item.id,
		"health": item.food_health,
		"stamina": item.food_stamina,
		"eitr": item.food_eitr,
		"regen": item.food_regen,
		"duration": item.food_duration,
		"remaining": item.food_duration,
	}
	food_slot_changed.emit(index, food_slots[index])
	_emit_stats()


func _emit_stats() -> void:
	stats_changed.emit(get_total_max_health(), get_total_max_stamina(), get_total_max_eitr())


## --- Save / Load ---

func serialize() -> Array:
	return food_slots.duplicate(true)

func deserialize(data: Array) -> void:
	for i in mini(data.size(), MAX_FOOD_SLOTS):
		food_slots[i] = data[i]
	_emit_stats()
