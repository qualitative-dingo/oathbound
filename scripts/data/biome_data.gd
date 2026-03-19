class_name BiomeData
extends Resource
## Defines a single biome's properties, creatures, resources, and generation rules.
## Each biome is a .tres file in res://resources/biomes/.

# --- Identity ---
@export var id: StringName = &"hearthlands"
@export var display_name: String = "Hearthlands"
@export var description: String = ""

# --- World Gen Placement ---
@export_group("World Gen")
@export var min_distance_from_center: float = 0.0
@export var max_distance_from_center: float = 5000.0
@export var min_altitude: float = -10.0
@export var max_altitude: float = 200.0
@export var generation_weight: float = 1.0

# --- Environment ---
@export_group("Environment")
@export var ambient_color: Color = Color(0.4, 0.5, 0.3)
@export var fog_color: Color = Color(0.7, 0.75, 0.8)
@export var fog_density: float = 0.003
@export var requires_frost_resistance: bool = false
@export var requires_heat_resistance: bool = false
@export var has_perpetual_darkness: bool = false
@export var has_poison_environment: bool = false
@export var music_track: StringName = &""

# --- Terrain ---
@export_group("Terrain")
@export var ground_texture: Texture2D
@export var terrain_noise_amplitude: float = 5.0
@export var terrain_noise_frequency: float = 0.01
@export var terrain_color: Color = Color(0.3, 0.5, 0.2)

# --- Vegetation & Resources ---
@export_group("Vegetation")
## Each entry: { "scene": PackedScene, "density": float, "min_altitude": float, "max_altitude": float }
@export var vegetation_table: Array[Dictionary] = []

# --- Creatures ---
@export_group("Creatures")
## { "scene": PackedScene, "weight": float, "group_size_min": int, "group_size_max": int }
@export var day_creatures: Array[Dictionary] = []
@export var night_creatures: Array[Dictionary] = []

# --- Boss ---
@export_group("Boss")
@export var boss_id: StringName = &""
@export var boss_scene: PackedScene
@export var boss_summon_item: StringName = &""
@export var boss_summon_count: int = 1

# --- Progression Tier ---
@export_group("Progression")
## Tier 1-8, matching ProgressionManager.TIER_DATA.
@export var tier: int = 1
@export var boss_drop_key: StringName = &""
