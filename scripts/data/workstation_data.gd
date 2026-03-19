class_name WorkstationData
extends Resource
## Defines a workstation type and its upgrade path.
## Workstations are leveled by placing specific upgrade items nearby
## (within a radius). Only the highest-level station can craft its full recipe list.
##
## Key workstations in order of progression:
##   Workbench (Tier 0 — Meadows, available immediately)
##   Forge (Tier 1 — Black Forest, requires smelted copper/tin)
##   Stonecutter (Tier 2 — Swamp, requires iron)
##   Artisan Table (Tier 3 — Plains, requires Dragon Tear from Moder)
##   Galdr Table (Tier 4 — Mistlands, requires Torn Spirit from Yagluth)
##   Black Forge (Tier 5 — Mistlands, requires Queen Drop from The Queen)

@export var id: StringName = &"workbench"
@export var display_name: String = "Workbench"
@export var description: String = ""

## Progression tier this station belongs to.
@export var tier: int = 0

## Maximum level this station can reach through upgrades.
@export var max_level: int = 5

## Items required to craft/place this workstation.
## [{ "item_id": StringName, "amount": int }]
@export var build_cost: Array[Dictionary] = []

## Boss drop or item required to unlock this station's construction.
## Empty = always available (e.g. Workbench).
@export var unlock_requirement: StringName = &""

## Upgrade items and the level they grant.
## Each entry: { "item_id": StringName, "display_name": String, "level_bonus": int,
##               "build_cost": [{ "item_id": StringName, "amount": int }] }
## These are separate placeable objects that must be within radius.
@export var upgrades: Array[Dictionary] = []

## Radius within which upgrade items are detected.
@export var upgrade_detection_radius: float = 5.0
