class_name PlayerInventory
extends RefCounted
## Per-player inventory instance. Holds item slots, display order, and equipment.
## In single-player, one instance exists. In multiplayer, each player gets their own.

const TOTAL_SLOTS := 64
const EQUIPMENT_SLOTS: Array[String] = ["weapon", "sword", "bow", "pickaxe", "shield", "chest", "legs", "feet"]

var _slots: Dictionary = {}
var _order: Array[StringName] = []
var _equipped: Dictionary = {}

signal changed()


func add_item(item_id: StringName, amount: int) -> void:
	if _slots.has(item_id):
		_slots[item_id] = int(_slots[item_id]) + amount
	else:
		_slots[item_id] = amount
		_order.append(item_id)
	changed.emit()
	GameEvents.inventory_changed.emit()


func remove_item(item_id: StringName, amount: int) -> bool:
	if not _slots.has(item_id):
		return false
	var current: int = int(_slots[item_id])
	if current < amount:
		return false
	current -= amount
	if current <= 0:
		_slots.erase(item_id)
		_order.erase(item_id)
	else:
		_slots[item_id] = current
	changed.emit()
	GameEvents.inventory_changed.emit()
	return true


func has_item(item_id: StringName, amount: int = 1) -> bool:
	return _slots.has(item_id) and int(_slots[item_id]) >= amount


func get_amount(item_id: StringName) -> int:
	if _slots.has(item_id):
		return int(_slots[item_id])
	return 0


func get_all_items() -> Dictionary:
	return _slots.duplicate()


func get_item_list() -> Array:
	var result: Array = []
	for item_id: StringName in _order:
		if _slots.has(item_id):
			result.append({"id": item_id, "amount": int(_slots[item_id])})
	return result


func swap_slots(from_idx: int, to_idx: int) -> void:
	if from_idx == to_idx:
		return
	if from_idx < 0 or from_idx >= _order.size():
		return
	if to_idx < 0 or to_idx >= TOTAL_SLOTS:
		return
	while _order.size() <= to_idx:
		_order.append(&"")
	var temp: StringName = _order[from_idx]
	_order[from_idx] = _order[to_idx]
	_order[to_idx] = temp
	while not _order.is_empty() and _order[-1] == &"":
		_order.remove_at(_order.size() - 1)
	changed.emit()
	GameEvents.inventory_changed.emit()


func move_group_to_end(raw_indices: Array) -> void:
	if raw_indices.is_empty():
		return
	var sorted_idx := raw_indices.duplicate()
	sorted_idx.sort()
	var items: Array[StringName] = []
	for idx in sorted_idx:
		var i := int(idx)
		if i >= 0 and i < _order.size() and _order[i] != &"":
			items.append(_order[i])
	sorted_idx.reverse()
	for idx in sorted_idx:
		var i := int(idx)
		if i >= 0 and i < _order.size():
			_order.remove_at(i)
	for item in items:
		_order.append(item)
	while not _order.is_empty() and _order[-1] == &"":
		_order.remove_at(_order.size() - 1)
	changed.emit()
	GameEvents.inventory_changed.emit()


func get_order() -> Array[StringName]:
	return _order.duplicate()


func set_order(new_order: Array[StringName]) -> void:
	_order = new_order
	changed.emit()
	GameEvents.inventory_changed.emit()


func get_amount_any_star(base_id: StringName) -> int:
	var total := 0
	for slot_id: StringName in _slots.keys():
		var parsed := ItemDatabase.parse_star_id(slot_id)
		if parsed["base_id"] == base_id:
			total += int(_slots[slot_id])
	return total


func has_item_any_star(base_id: StringName, amount: int = 1) -> bool:
	return get_amount_any_star(base_id) >= amount


func get_grouped_item_list() -> Array:
	var groups: Dictionary = {}
	var group_order: Array[StringName] = []
	var raw_idx := 0
	for item_id: StringName in _order:
		if not _slots.has(item_id):
			raw_idx += 1
			continue
		var parsed := ItemDatabase.parse_star_id(item_id)
		var base_id: StringName = parsed["base_id"]
		var stars: int = parsed["stars"]
		var amount: int = int(_slots[item_id])
		var data: Dictionary = ItemDatabase.get_item(item_id)
		var item_type: String = str(data.get("type", "material"))
		if item_type == "material" or item_type == "food" or item_type == "trophy":
			if not groups.has(base_id):
				groups[base_id] = {"base_id": base_id, "total": 0, "variants": {}, "raw_indices": [], "is_grouped": true}
				group_order.append(base_id)
			groups[base_id]["total"] += amount
			groups[base_id]["variants"][stars] = amount
			(groups[base_id]["raw_indices"] as Array).append(raw_idx)
		else:
			group_order.append(item_id)
			groups[item_id] = {"base_id": base_id, "total": amount, "variants": {stars: amount}, "exact_id": item_id, "raw_indices": [raw_idx], "is_grouped": false}
		raw_idx += 1
	var result: Array = []
	for gid in group_order:
		if groups.has(gid):
			result.append(groups[gid])
	return result


func _scan_slots_by_star(base_id: StringName, min_star: int, max_star: int) -> Dictionary:
	var by_star: Dictionary = {}
	for slot_id: StringName in _slots.keys():
		var parsed := ItemDatabase.parse_star_id(slot_id)
		if parsed["base_id"] == base_id:
			var s := int(parsed["stars"])
			if s >= min_star and s <= max_star:
				by_star[s] = {"key": slot_id, "qty": int(_slots[slot_id])}
	return by_star


func preview_consume_any_star(base_id: StringName, amount: int) -> Dictionary:
	var by_star := _scan_slots_by_star(base_id, 0, 5)
	var result: Dictionary = {}
	var remaining := amount
	for star_level in range(6):
		if remaining <= 0:
			break
		if by_star.has(star_level):
			var available: int = by_star[star_level]["qty"]
			var take := mini(available, remaining)
			remaining -= take
			if take > 0:
				result[star_level] = take
	return result


func remove_item_any_star(base_id: StringName, amount: int) -> bool:
	if not has_item_any_star(base_id, amount):
		return false
	var by_star := _scan_slots_by_star(base_id, 0, 5)
	var remaining := amount
	for star_level in range(6):
		if remaining <= 0:
			break
		if by_star.has(star_level):
			var slot_key: StringName = by_star[star_level]["key"]
			var available: int = by_star[star_level]["qty"]
			var take := mini(available, remaining)
			remaining -= take
			available -= take
			if available <= 0:
				_slots.erase(slot_key)
				_order.erase(slot_key)
			else:
				_slots[slot_key] = available
	if remaining <= 0:
		changed.emit()
		GameEvents.inventory_changed.emit()
		return true
	return false


func get_amount_capped_star(base_id: StringName, max_star: int, min_star: int = 0) -> int:
	var total := 0
	var by_star := _scan_slots_by_star(base_id, min_star, max_star)
	for s: int in by_star.keys():
		total += int(by_star[s]["qty"])
	return total


func has_item_capped_star(base_id: StringName, amount: int, max_star: int, min_star: int = 0) -> bool:
	return get_amount_capped_star(base_id, max_star, min_star) >= amount


func preview_consume_capped_star(base_id: StringName, amount: int, max_star: int, min_star: int = 0, prefer_low: bool = false) -> Dictionary:
	var by_star := _scan_slots_by_star(base_id, min_star, max_star)
	var result: Dictionary = {}
	var remaining := amount
	if prefer_low:
		for star_level in range(min_star, max_star + 1):
			if remaining <= 0:
				break
			if by_star.has(star_level):
				var available: int = by_star[star_level]["qty"]
				var take := mini(available, remaining)
				remaining -= take
				if take > 0:
					result[star_level] = take
	else:
		for star_level in range(max_star, min_star - 1, -1):
			if remaining <= 0:
				break
			if by_star.has(star_level):
				var available: int = by_star[star_level]["qty"]
				var take := mini(available, remaining)
				remaining -= take
				if take > 0:
					result[star_level] = take
	return result


func remove_item_capped_star(base_id: StringName, amount: int, max_star: int, min_star: int = 0, prefer_low: bool = false) -> bool:
	if not has_item_capped_star(base_id, amount, max_star, min_star):
		return false
	var by_star := _scan_slots_by_star(base_id, min_star, max_star)
	var remaining := amount
	var star_range: Array[int] = []
	if prefer_low:
		for sl in range(min_star, max_star + 1):
			star_range.append(sl)
	else:
		for sl in range(max_star, min_star - 1, -1):
			star_range.append(sl)
	for star_level in star_range:
		if remaining <= 0:
			break
		if by_star.has(star_level):
			var slot_key: StringName = by_star[star_level]["key"]
			var available: int = by_star[star_level]["qty"]
			var take := mini(available, remaining)
			remaining -= take
			available -= take
			if available <= 0:
				_slots.erase(slot_key)
				_order.erase(slot_key)
			else:
				_slots[slot_key] = available
	if remaining <= 0:
		changed.emit()
		GameEvents.inventory_changed.emit()
		return true
	return false


func equip_armor(item_id: StringName) -> void:
	var data: Dictionary = ItemDatabase.get_item(item_id)
	var slot: String = str(data.get("armor_slot", ""))
	if slot.is_empty():
		return
	var prev: StringName = _equipped.get(slot, &"") as StringName
	if prev == item_id:
		return
	if prev != &"":
		add_item(prev, 1)
	_equipped[slot] = item_id
	remove_item(item_id, 1)
	changed.emit()
	GameEvents.inventory_changed.emit()


func unequip_armor(slot: String) -> void:
	if not _equipped.has(slot) or _equipped[slot] == &"":
		return
	var item_id: StringName = _equipped[slot]
	_equipped[slot] = &""
	add_item(item_id, 1)
	changed.emit()
	GameEvents.inventory_changed.emit()


func is_equipped(item_id: StringName) -> bool:
	for slot: String in _equipped.keys():
		if _equipped[slot] == item_id:
			return true
	return false


func get_equipped(slot: String) -> StringName:
	return _equipped.get(slot, &"") as StringName


func get_all_equipped() -> Dictionary:
	return _equipped.duplicate()


func get_total_armor() -> float:
	var total := 0.0
	for slot: String in _equipped.keys():
		var item_id: StringName = _equipped[slot] as StringName
		if item_id == &"":
			continue
		var data: Dictionary = ItemDatabase.get_item(item_id)
		total += float(data.get("armor", 0.0))
	return total


func set_equipped_from_save(data: Dictionary) -> void:
	_equipped.clear()
	for slot: String in data.keys():
		var item_id := StringName(str(data[slot]))
		_equipped[slot] = item_id
	changed.emit()
	GameEvents.inventory_changed.emit()


func give_starting_gear() -> void:
	_equipped["weapon"] = &"starting_axe"
	_equipped["sword"] = &"starting_sword"
	_equipped["bow"] = &"starting_bow"
	_equipped["pickaxe"] = &"starting_pickaxe"
	_equipped["chest"] = &"starting_chest"
	_equipped["legs"] = &"starting_legs"
	_equipped["feet"] = &"starting_feet"
	_equipped["shield"] = &"starting_shield"
	changed.emit()
	GameEvents.inventory_changed.emit()


func clear() -> void:
	_slots.clear()
	_order.clear()
	_equipped.clear()
