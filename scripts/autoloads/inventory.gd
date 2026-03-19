extends Node
## Inventory autoload - acts as a ROUTER to the local player's PlayerInventory.
## In single-player, _local points to the only inventory. In multiplayer,
## _local points to whichever player this client controls.
## All existing Inventory.xyz() calls continue to work via delegation.

const TOTAL_SLOTS := 64
const EQUIPMENT_SLOTS: Array[String] = ["weapon", "sword", "bow", "pickaxe", "shield", "chest", "legs", "feet"]

var _local: PlayerInventory
var _all_inventories: Dictionary = {}  # peer_id -> PlayerInventory

## Backward compat for save_manager/main_menu; forwards to _local.
var _slots: Dictionary:
	get: return _local._slots if _local else {}
var _order: Array:
	get: return _local._order if _local else []
var _equipped: Dictionary:
	get: return _local._equipped if _local else {}


func _ready() -> void:
	_local = PlayerInventory.new()
	GameEvents.item_picked_up.connect(_on_item_picked_up)


func get_local() -> PlayerInventory:
	return _local


func set_local(inv: PlayerInventory) -> void:
	_local = inv


func register_inventory(peer_id: int, inv: PlayerInventory) -> void:
	_all_inventories[peer_id] = inv


func unregister_inventory(peer_id: int) -> void:
	_all_inventories.erase(peer_id)


func get_inventory_for(peer_id: int) -> PlayerInventory:
	return _all_inventories.get(peer_id, null)


func _on_item_picked_up(item_id: StringName, amount: int) -> void:
	_local.add_item(item_id, amount)


func add_item(item_id: StringName, amount: int) -> void:
	_local.add_item(item_id, amount)

func remove_item(item_id: StringName, amount: int) -> bool:
	return _local.remove_item(item_id, amount)

func has_item(item_id: StringName, amount: int = 1) -> bool:
	return _local.has_item(item_id, amount)

func get_amount(item_id: StringName) -> int:
	return _local.get_amount(item_id)

func get_all_items() -> Dictionary:
	return _local.get_all_items()

func get_item_list() -> Array:
	return _local.get_item_list()

func swap_slots(from_idx: int, to_idx: int) -> void:
	_local.swap_slots(from_idx, to_idx)

func move_group_to_end(raw_indices: Array) -> void:
	_local.move_group_to_end(raw_indices)

func get_order() -> Array[StringName]:
	return _local.get_order()

func set_order(new_order: Array[StringName]) -> void:
	_local.set_order(new_order)

func get_amount_any_star(base_id: StringName) -> int:
	return _local.get_amount_any_star(base_id)

func has_item_any_star(base_id: StringName, amount: int = 1) -> bool:
	return _local.has_item_any_star(base_id, amount)

func get_grouped_item_list() -> Array:
	return _local.get_grouped_item_list()

func preview_consume_any_star(base_id: StringName, amount: int) -> Dictionary:
	return _local.preview_consume_any_star(base_id, amount)

func remove_item_any_star(base_id: StringName, amount: int) -> bool:
	return _local.remove_item_any_star(base_id, amount)

func get_amount_capped_star(base_id: StringName, max_star: int, min_star: int = 0) -> int:
	return _local.get_amount_capped_star(base_id, max_star, min_star)

func has_item_capped_star(base_id: StringName, amount: int, max_star: int, min_star: int = 0) -> bool:
	return _local.has_item_capped_star(base_id, amount, max_star, min_star)

func preview_consume_capped_star(base_id: StringName, amount: int, max_star: int, min_star: int = 0, prefer_low: bool = false) -> Dictionary:
	return _local.preview_consume_capped_star(base_id, amount, max_star, min_star, prefer_low)

func remove_item_capped_star(base_id: StringName, amount: int, max_star: int, min_star: int = 0, prefer_low: bool = false) -> bool:
	return _local.remove_item_capped_star(base_id, amount, max_star, min_star, prefer_low)

func equip_armor(item_id: StringName) -> void:
	_local.equip_armor(item_id)

func unequip_armor(slot: String) -> void:
	_local.unequip_armor(slot)

func is_equipped(item_id: StringName) -> bool:
	return _local.is_equipped(item_id)

func get_equipped(slot: String) -> StringName:
	return _local.get_equipped(slot)

func get_all_equipped() -> Dictionary:
	return _local.get_all_equipped()

func get_total_armor() -> float:
	return _local.get_total_armor()

func set_equipped_from_save(data: Dictionary) -> void:
	_local.set_equipped_from_save(data)

func give_starting_gear() -> void:
	_local.give_starting_gear()
