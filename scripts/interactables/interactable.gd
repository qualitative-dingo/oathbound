class_name Interactable
extends StaticBody3D
## Base class for all objects the player can interact with.
##
## Subclasses override get_interaction_verb(), can_interact(), and _do_interact()
## to define custom behaviour. The InteractionManager on the player detects these
## via RayCast3D and calls interact() when the player presses the interact key.
##
## Expected scene structure for any Interactable:
##   StaticBody3D (this script)
##   ├─ CollisionShape3D          (physics + raycast hit)
##   ├─ MeshInstance3D            (visual)
##   └─ (optional children)

signal interacted(player: CharacterBody3D)
signal interaction_available_changed(is_available: bool)

## The display name shown in the HUD prompt (e.g. "Oak Tree", "Iron Chest").
@export var display_name: StringName = &"Object"

## If false, the InteractionManager skips this object entirely.
@export var is_active: bool = true

## Collision layer 3 = Interactables. Set in the editor or here.
func _ready() -> void:
	collision_layer = 4  # Layer 3 (bit 2)
	collision_mask = 0
	add_to_group(&"interactables")


## Text shown on the HUD prompt, e.g. "Chop", "Open", "Use".
## Override in subclasses.
func get_interaction_verb() -> String:
	return "Interact"


## Full prompt string: "[E] Chop Oak Tree"
func get_prompt_text() -> String:
	return "[E] %s %s" % [get_interaction_verb(), display_name]


## Whether this object can currently be interacted with.
## Override for conditional logic (e.g. locked chest, depleted resource).
func can_interact(_player: CharacterBody3D) -> bool:
	return is_active


## Called by InteractionManager. Validates then delegates to _do_interact().
func interact(player: CharacterBody3D) -> void:
	if not can_interact(player):
		return
	_do_interact(player)
	interacted.emit(player)
	GameEvents.interaction_performed.emit(self, player)


## Override this in subclasses for the actual interaction logic.
func _do_interact(_player: CharacterBody3D) -> void:
	pass


## Convenience: temporarily disable then re-enable after a cooldown.
func disable_for(seconds: float) -> void:
	is_active = false
	interaction_available_changed.emit(false)
	await get_tree().create_timer(seconds).timeout
	is_active = true
	interaction_available_changed.emit(true)
