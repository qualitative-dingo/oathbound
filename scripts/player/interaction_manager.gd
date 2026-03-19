class_name InteractionManager
extends Node3D
## Mounted as a child of the Camera3D (or SpringArm3D pivot).
## Casts a ray from the camera centre every physics frame to detect
## Interactable objects. Maintains a "focused" interactable and
## delegates the interact() call when the player presses the key.
##
## Scene tree expectation:
##   Player (CharacterBody3D)
##   ├─ CameraPivot (Node3D)
##   │   ├─ SpringArm3D
##   │   │   └─ Camera3D
##   │   │       └─ **InteractionManager** (this node)
##   │   │           └─ RayCast3D
##   └─ InteractionPrompt (Control — UI layer)

@export var interact_distance: float = 4.0
@export var ray_collision_mask: int = 4  # Layer 3 = Interactables

var focused_interactable: Interactable = null

@onready var _ray: RayCast3D = $RayCast3D
@onready var _player: CharacterBody3D = _find_player_ancestor()
var _prompt_label: Label


func _ready() -> void:
	_setup_raycast()
	# Defer prompt search so the Player's _ready() has time to build the HUD
	call_deferred("_deferred_find_prompt")


func _deferred_find_prompt() -> void:
	_prompt_label = _find_prompt_label()


func _physics_process(_delta: float) -> void:
	_update_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact") and focused_interactable:
		focused_interactable.interact(_player)
		get_viewport().set_input_as_handled()
		_update_focus()


## --- Private ---

func _setup_raycast() -> void:
	if not _ray:
		_ray = RayCast3D.new()
		add_child(_ray)
	_ray.target_position = Vector3(0.0, 0.0, -interact_distance)
	_ray.collision_mask = ray_collision_mask
	_ray.enabled = true
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true


func _update_focus() -> void:
	var new_focus: Interactable = null

	if _ray.is_colliding():
		var collider := _ray.get_collider()
		if collider is Interactable and collider.can_interact(_player):
			new_focus = collider as Interactable

	if new_focus == focused_interactable:
		return

	focused_interactable = new_focus

	if focused_interactable:
		_show_prompt(focused_interactable.get_prompt_text())
		GameEvents.interaction_focus_changed.emit(focused_interactable)
	else:
		_hide_prompt()
		GameEvents.interaction_focus_lost.emit()


func _show_prompt(text: String) -> void:
	if _prompt_label:
		_prompt_label.text = text
		_prompt_label.visible = true


func _hide_prompt() -> void:
	if _prompt_label:
		_prompt_label.visible = false


func _find_player_ancestor() -> CharacterBody3D:
	var node := get_parent()
	while node:
		if node is CharacterBody3D:
			return node
		node = node.get_parent()
	push_error("InteractionManager: No CharacterBody3D ancestor found.")
	return null


func _find_prompt_label() -> Label:
	# Walk up to the player root, then look for an InteractionPrompt child
	if not _player:
		return null
	var prompt := _player.find_child("InteractionPrompt", true, false)
	if prompt is Label:
		return prompt as Label
	# Fallback: try a RichTextLabel or any Control named InteractionPrompt
	if prompt is RichTextLabel:
		push_warning("InteractionManager: Found RichTextLabel instead of Label for prompt.")
	return null
