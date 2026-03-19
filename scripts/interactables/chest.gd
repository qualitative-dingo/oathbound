class_name InteractableChest
extends Interactable
## A storage container that opens an inventory panel when interacted with.
##
## Scene structure:
##   InteractableChest (this script)
##   ├─ CollisionShape3D
##   ├─ MeshInstance3D
##   ├─ AnimationPlayer     (open/close lid animation)
##   └─ AudioStreamPlayer3D (creak SFX)

signal chest_opened(chest: InteractableChest)
signal chest_closed(chest: InteractableChest)

@export var slot_count: int = 18
@export var is_locked: bool = false
@export var required_key_id: StringName = &""

var is_open: bool = false
## Flat array of item stacks: [{ "item_id": StringName, "count": int }, ...]
var contents: Array[Dictionary] = []

@onready var _anim: AnimationPlayer = $AnimationPlayer if has_node("AnimationPlayer") else null
@onready var _audio: AudioStreamPlayer3D = $AudioStreamPlayer3D if has_node("AudioStreamPlayer3D") else null


func _ready() -> void:
	super._ready()
	contents.resize(slot_count)
	for i in slot_count:
		contents[i] = {}


func get_interaction_verb() -> String:
	if is_locked:
		return "Unlock"
	return "Close" if is_open else "Open"


func can_interact(player: CharacterBody3D) -> bool:
	if not super.can_interact(player):
		return false
	if is_locked:
		# TODO: Check if player has the required key in inventory.
		return true
	return true


func _do_interact(player: CharacterBody3D) -> void:
	if is_locked:
		_try_unlock(player)
		return

	if is_open:
		close_chest()
	else:
		open_chest()


func open_chest() -> void:
	is_open = true
	if _anim and _anim.has_animation(&"open"):
		_anim.play(&"open")
	if _audio:
		_audio.play()
	chest_opened.emit(self)


func close_chest() -> void:
	is_open = false
	if _anim and _anim.has_animation(&"close"):
		_anim.play(&"close")
	if _audio:
		_audio.play()
	chest_closed.emit(self)


func _try_unlock(player: CharacterBody3D) -> void:
	# TODO: Check player inventory for required_key_id, consume key, set is_locked = false
	push_warning("Chest unlock not yet implemented — needs inventory system.")


## --- Container API ---

func add_item(item_id: StringName, amount: int) -> int:
	## Returns the number of items that didn't fit (overflow).
	var remaining := amount
	var stack_size: int = ItemDatabase.get_item(item_id).get("stack_size", 50)

	# Try to stack into existing slots first
	for i in slot_count:
		if remaining <= 0:
			break
		if contents[i].get("item_id") == item_id:
			var space: int = stack_size - contents[i].get("count", 0)
			var to_add := mini(remaining, space)
			contents[i]["count"] = contents[i].get("count", 0) + to_add
			remaining -= to_add

	# Fill empty slots
	for i in slot_count:
		if remaining <= 0:
			break
		if contents[i].is_empty():
			var to_add := mini(remaining, stack_size)
			contents[i] = { "item_id": item_id, "count": to_add }
			remaining -= to_add

	return remaining


func remove_item(item_id: StringName, amount: int) -> int:
	## Returns the number actually removed.
	var removed := 0
	for i in range(slot_count - 1, -1, -1):
		if contents[i].get("item_id") != item_id:
			continue
		var take := mini(amount - removed, contents[i].get("count", 0))
		contents[i]["count"] = contents[i].get("count", 0) - take
		removed += take
		if contents[i].get("count", 0) <= 0:
			contents[i] = {}
		if removed >= amount:
			break
	return removed
