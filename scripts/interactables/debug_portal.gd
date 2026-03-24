class_name DebugPortal
extends Interactable

@export var portal_tag: StringName = &"debug_teleport"
@export var destination_position: Vector3 = Vector3.ZERO

var _linked_portal: DebugPortal

func _ready() -> void:
	super._ready()
	display_name = &"Debug Portal"
	add_to_group(&"debug_portals")


func get_interaction_verb() -> String:
	return "Teleport"


func _do_interact(player: CharacterBody3D) -> void:
	var target_pos := destination_position
	_find_linked_portal()
	if _linked_portal and is_instance_valid(_linked_portal):
		target_pos = _linked_portal.global_position
	if target_pos == Vector3.ZERO:
		return
	var wg := _get_world_generator()
	if wg:
		var h: float = wg.get_height_at_scene(target_pos.x, target_pos.z)
		target_pos.y = maxf(h, 1.0) + 2.0
	else:
		target_pos.y += 2.0
	player.global_position = target_pos
	player.velocity = Vector3.ZERO


func _get_world_generator() -> Node:
	var nodes := get_tree().get_nodes_in_group(&"world_generator")
	return nodes[0] if not nodes.is_empty() else null


func _find_linked_portal() -> void:
	_linked_portal = null
	for node in get_tree().get_nodes_in_group(&"debug_portals"):
		var other := node as DebugPortal
		if other and other != self and other.portal_tag == portal_tag:
			_linked_portal = other
			return


static func create_portal_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "PortalMesh"
	var box := BoxMesh.new()
	box.size = Vector3(1.5, 3.0, 0.3)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.0, 0.8, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.1, 1.0)
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	mi.position.y = 1.5
	return mi


static func create_portal_pair(
	parent_a: Node3D, pos_a: Vector3,
	parent_b: Node3D, pos_b: Vector3,
	tag: StringName = &"debug_teleport",
) -> Array[DebugPortal]:
	var portal_a := _build_portal(tag)
	portal_a.name = "DebugPortal_A"
	portal_a.destination_position = pos_b
	parent_a.add_child(portal_a)
	portal_a.global_position = pos_a

	var portal_b := _build_portal(tag)
	portal_b.name = "DebugPortal_B"
	portal_b.destination_position = pos_a
	parent_b.add_child(portal_b)
	portal_b.global_position = pos_b

	return [portal_a, portal_b]


static func _build_portal(tag: StringName) -> DebugPortal:
	var portal := DebugPortal.new()
	portal.portal_tag = tag
	portal.collision_layer = 4
	portal.collision_mask = 0

	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0, 3.0, 1.0)
	col.shape = shape
	col.position.y = 1.5
	portal.add_child(col)

	portal.add_child(create_portal_mesh())

	var label := Label3D.new()
	label.name = "PortalLabel"
	label.text = "PORTAL"
	label.font_size = 48
	label.modulate = Color(0.5, 0.3, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 4.0
	label.no_depth_test = true
	portal.add_child(label)

	return portal
