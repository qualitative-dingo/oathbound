class_name Workstation
extends Interactable
## A crafting station (Workbench, Forge, Cauldron, etc.).
## When interacted with, opens a crafting UI filtered to recipes
## this station type can produce at its current level.
##
## Scene structure:
##   Workstation (this script)
##   ├─ CollisionShape3D
##   ├─ MeshInstance3D
##   ├─ AnimationPlayer        (idle flame, bellows, etc.)
##   ├─ AudioStreamPlayer3D
##   └─ Area3D "UpgradeZone"   (detects nearby upgrade items)

signal crafting_ui_requested(station: Workstation)
signal station_level_changed(new_level: int)

enum StationType { WORKBENCH, FORGE, CAULDRON, STONECUTTER, ARTISAN }

@export var station_type: StationType = StationType.WORKBENCH
@export var base_level: int = 1
## Max level this station can reach with upgrades.
@export var max_level: int = 5

## Maps upgrade item scene names to the level bonus they grant.
## e.g. { "ChoppingBlock": 1, "TanningRack": 1 }
@export var upgrade_map: Dictionary = {}

var current_level: int = 1
var _detected_upgrades: Array[StringName] = []

@onready var _upgrade_zone: Area3D = $UpgradeZone if has_node("UpgradeZone") else null


func _ready() -> void:
	super._ready()
	display_name = StationType.keys()[station_type].capitalize()
	current_level = base_level

	if _upgrade_zone:
		_upgrade_zone.body_entered.connect(_on_upgrade_body_entered)
		_upgrade_zone.body_exited.connect(_on_upgrade_body_exited)


func get_interaction_verb() -> String:
	return "Use"


func _do_interact(_player: CharacterBody3D) -> void:
	crafting_ui_requested.emit(self)


## Recalculate level based on which upgrade items are in the upgrade zone.
func recalculate_level() -> void:
	var bonus := 0
	for upgrade_name in _detected_upgrades:
		bonus += upgrade_map.get(upgrade_name, 0)
	var new_level := clampi(base_level + bonus, 1, max_level)
	if new_level != current_level:
		current_level = new_level
		station_level_changed.emit(current_level)


func get_station_type_name() -> StringName:
	return StringName(StationType.keys()[station_type])


func _on_upgrade_body_entered(body: Node3D) -> void:
	var body_name := StringName(body.name)
	if upgrade_map.has(body_name) and body_name not in _detected_upgrades:
		_detected_upgrades.append(body_name)
		recalculate_level()


func _on_upgrade_body_exited(body: Node3D) -> void:
	var body_name := StringName(body.name)
	_detected_upgrades.erase(body_name)
	recalculate_level()
