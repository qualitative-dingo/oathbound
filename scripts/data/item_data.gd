class_name ItemData
extends Resource
## Defines a single item in the game. Serialized as .tres files in res://resources/items/.
## The ItemDatabase autoload indexes these at startup.

enum ItemType { MATERIAL, TOOL, WEAPON, SHIELD, ARMOR, FOOD, CONSUMABLE, BUILDABLE, TROPHY, KEY, AMMO }
enum DamageType { NONE, SLASH, PIERCE, BLUNT, FIRE, FROST, LIGHTNING, POISON, SPIRIT }

# --- Identity ---
@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var icon: Texture2D
@export var item_type: ItemType = ItemType.MATERIAL
@export var stack_size: int = 50
@export var weight: float = 1.0

## If true, this item cannot be transported through portals (ores, metals, dragon eggs).
@export var teleport_restricted: bool = false

# --- Weapon Stats (if item_type == WEAPON) ---
@export_group("Weapon")
@export var base_damage: float = 0.0
@export var damage_type: DamageType = DamageType.NONE
@export var attack_stamina_cost: float = 10.0
@export var knockback: float = 30.0
## Multiplier for stagger buildup (maces = 2x, two-hand axes = 1.5x).
@export var stagger_multiplier: float = 1.0
## Which skill this weapon levels up.
@export var weapon_skill: StringName = &""
@export var attack_speed: float = 1.0

# --- Shield Stats ---
@export_group("Shield")
@export var block_power: float = 0.0
@export var parry_bonus: float = 0.0
## Parry window in seconds. Bucklers have larger windows (~0.25s).
@export var parry_window: float = 0.15
@export var block_stamina_cost: float = 10.0

# --- Armor Stats ---
@export_group("Armor")
@export var armor_value: float = 0.0
@export var movement_speed_modifier: float = 0.0

# --- Food Stats (if item_type == FOOD) ---
@export_group("Food")
## Max HP this food grants when eaten.
@export var food_health: float = 0.0
## Max stamina this food grants.
@export var food_stamina: float = 0.0
## Max eitr (mana) this food grants.
@export var food_eitr: float = 0.0
## How long the food buff lasts in seconds.
@export var food_duration: float = 1200.0
## HP regen per tick while this food is active.
@export var food_regen: float = 1.0

# --- Tool Stats ---
@export_group("Tool")
## Tool tier determines what resources can be harvested (0 = hands, 1 = flint, 2 = bronze, etc.)
@export var tool_tier: int = 0
## Tool type for interaction matching (e.g. "axe", "pickaxe", "hammer").
@export var tool_type: StringName = &""

# --- Crafting ---
@export_group("Crafting")
## Which workstation type is needed to craft this item.
@export var required_station: StringName = &""
## Minimum station level required.
@export var required_station_level: int = 1
## Recipe ingredients: [{ "item_id": StringName, "amount": int }]
@export var recipe: Array[Dictionary] = []
