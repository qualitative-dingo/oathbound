class_name BuildingPiece
extends StaticBody3D

func _get_world_pos() -> Vector3:
	var wgs := get_tree().get_nodes_in_group(&"world_generator")
	if not wgs.is_empty() and wgs[0].has_method(&"get_world_position"):
		return wgs[0].get_world_position(self)
	return global_position
## A placed building piece with structural integrity.
##
## The stability system works like pressure flowing from ground upward.
## Support is NOT based on realistic physics — there's no weight limit per beam.
## Instead, each piece loses a fraction of its support value based on material
## and connection direction (vertical vs horizontal).
##
## Stability colors (shown on hover with hammer):
##   Blue   (1.0 - 0.8)  = Fully grounded, extremely stable
##   Green  (0.8 - 0.6)  = Well supported
##   Yellow (0.6 - 0.4)  = Moderate — consider reinforcing
##   Orange (0.4 - 0.2)  = Weak — may collapse if extended further
##   Red    (0.2 - 0.0)  = Critical — one more piece and it breaks
##
## Material support properties:
##   Wood:       max_support=100, vertical_loss=1/8,  horizontal_loss=1/5
##   Hardwood:   max_support=140, vertical_loss=1/10, horizontal_loss=1/6
##   Stone:      max_support=1000, vertical_loss=1/8, horizontal_loss=1/5
##   Iron:       max_support=1500, vertical_loss=1/13, horizontal_loss=1/10
##   Marble:     max_support=1500, vertical_loss=1/10, horizontal_loss=1/7

signal stability_changed(new_support: float, color: Color)
signal piece_collapsed()

enum PieceType { FOUNDATION, FLOOR, WALL, HALF_WALL, ROOF_26, ROOF_45, STAIRS, BEAM, POLE, DOOR_FRAME, DOOR, FENCE }
enum MaterialType { WOOD, HARDWOOD, STONE, IRON, MARBLE }
enum ConnectionDir { VERTICAL, HORIZONTAL }

@export var piece_type: PieceType = PieceType.FOUNDATION
@export var material_type: MaterialType = MaterialType.WOOD
@export var piece_name: StringName = &"Wood Wall"
@export var max_hp: float = 200.0
## Does rain degrade this piece when not under a roof?
@export var degrades_in_rain: bool = true

var current_hp: float
var current_support: float = 0.0
var connected_parent: BuildingPiece = null
var connected_children: Array[BuildingPiece] = []

## Material-specific support constants.
const MATERIAL_PROPS: Dictionary = {
	MaterialType.WOOD:     { "max": 100.0,  "v_loss": 0.125,  "h_loss": 0.20 },
	MaterialType.HARDWOOD: { "max": 140.0,  "v_loss": 0.10,   "h_loss": 0.167 },
	MaterialType.STONE:    { "max": 1000.0, "v_loss": 0.125,  "h_loss": 0.20 },
	MaterialType.IRON:     { "max": 1500.0, "v_loss": 0.077,  "h_loss": 0.10 },
	MaterialType.MARBLE:   { "max": 1500.0, "v_loss": 0.10,   "h_loss": 0.143 },
}


func _ready() -> void:
	current_hp = max_hp
	collision_layer = 8  # Layer 4 = Buildings
	collision_mask = 1 | 8  # Terrain + other buildings
	add_to_group(&"building_pieces")


## Calculate this piece's support and propagate to children.
func calculate_support() -> void:
	var props: Dictionary = MATERIAL_PROPS[material_type]

	if _is_grounded():
		current_support = props["max"]
	elif connected_parent:
		var parent_support := connected_parent.current_support
		var connection := _get_connection_direction(connected_parent)
		var loss_fraction: float = props["v_loss"] if connection == ConnectionDir.VERTICAL else props["h_loss"]
		current_support = maxf(parent_support - props["max"] * loss_fraction, 0.0)
	else:
		current_support = 0.0

	var color := _support_to_color()
	stability_changed.emit(current_support, color)

	if current_support <= 0.0:
		collapse()
		return

	for child in connected_children:
		child.calculate_support()


func get_support_fraction() -> float:
	var props: Dictionary = MATERIAL_PROPS[material_type]
	return current_support / props["max"]


func collapse() -> void:
	piece_collapsed.emit()
	GameEvents.building_piece_destroyed.emit(self)
	# Disconnect from parent
	if connected_parent:
		connected_parent.connected_children.erase(self)
	# Children lose their support source
	for child in connected_children:
		child.connected_parent = null
		child.calculate_support()
	queue_free()


func connect_to_parent(parent: BuildingPiece) -> void:
	connected_parent = parent
	if self not in parent.connected_children:
		parent.connected_children.append(self)
	calculate_support()


func get_snap_points() -> Array[Marker3D]:
	var points: Array[Marker3D] = []
	for child in get_children():
		if child is Marker3D and child.name.begins_with("snap_"):
			points.append(child)
	return points


func get_snap_type(marker: Marker3D) -> StringName:
	var parts := marker.name.split("_")
	if parts.size() < 3:
		return &""
	return StringName("_".join(parts.slice(1, parts.size() - 1)))


## --- Stability Color ---

func _support_to_color() -> Color:
	var frac := get_support_fraction()
	if frac >= 0.8:
		return Color(0.2, 0.4, 1.0)   # Blue
	elif frac >= 0.6:
		return Color(0.2, 0.8, 0.3)   # Green
	elif frac >= 0.4:
		return Color(0.9, 0.85, 0.2)  # Yellow
	elif frac >= 0.2:
		return Color(0.9, 0.5, 0.15)  # Orange
	else:
		return Color(0.9, 0.15, 0.1)  # Red


## --- Ground Detection ---

func _is_grounded() -> bool:
	# Foundations touching terrain are fully supported
	if piece_type != PieceType.FOUNDATION:
		return false
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.1,
		global_position + Vector3.DOWN * 0.5,
		1  # Terrain layer only
	)
	var result := space_state.intersect_ray(query)
	return not result.is_empty()


func _get_connection_direction(parent: BuildingPiece) -> ConnectionDir:
	# If the parent is below us (Y difference > threshold), it's vertical support.
	var y_diff := global_position.y - parent.global_position.y
	if absf(y_diff) > 0.3:
		return ConnectionDir.VERTICAL
	return ConnectionDir.HORIZONTAL


## --- Rain Degradation ---
## Called by a weather system periodically when it's raining and this piece
## has no roof above it. Wood degrades; stone does not.

func apply_rain_damage(amount: float) -> void:
	if not degrades_in_rain:
		return
	if material_type == MaterialType.STONE or material_type == MaterialType.IRON:
		return
	current_hp = maxf(current_hp - amount, 0.0)
	if current_hp <= 0.0:
		collapse()


## --- Save / Load ---

func serialize() -> Dictionary:
	return {
		"piece_type": piece_type,
		"material_type": material_type,
		"piece_name": piece_name,
		"position": var_to_str(_get_world_pos()),
		"rotation": var_to_str(global_rotation),
		"current_hp": current_hp,
	}
