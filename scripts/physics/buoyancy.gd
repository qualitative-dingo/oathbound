class_name Buoyancy
extends Node3D
## Attach as a child of a RigidBody3D to make it float on the water surface.
##
## For small objects (loot, crates) keep sample_offsets empty — a single
## center sample is used.  For large objects (boats), set sample_offsets
## to the 4 corners so the body tilts with waves.
##
## Usage:
##   var buoy := Buoyancy.new()
##   buoy.buoyancy_strength = 6.0
##   my_rigid_body.add_child(buoy)

@export var buoyancy_strength: float = 8.0
@export var damping: float = 3.0
@export var sample_offsets: Array[Vector3] = []

var _body: RigidBody3D


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	if not _body:
		push_warning("Buoyancy: parent must be a RigidBody3D")
		set_physics_process(false)
		return
	_body.linear_damp = damping
	_body.angular_damp = 1.5


func _physics_process(_delta: float) -> void:
	if not _body:
		return

	if sample_offsets.is_empty():
		_apply_single_point()
	else:
		_apply_multi_point()


func _apply_single_point() -> void:
	var pos := _body.global_position
	var submersion := WaterSystem.get_submersion(pos)
	if submersion <= 0.0:
		return
	var force_y := submersion * buoyancy_strength * _body.mass
	_body.apply_central_force(Vector3(0.0, force_y, 0.0))


func _apply_multi_point() -> void:
	var center := _body.global_position
	var basis := _body.global_transform.basis

	for off in sample_offsets:
		var world_pt := center + basis * off
		var submersion := WaterSystem.get_submersion(world_pt)
		if submersion <= 0.0:
			continue
		var force_y := (submersion * buoyancy_strength * _body.mass) / float(sample_offsets.size())
		_body.apply_force(Vector3(0.0, force_y, 0.0), basis * off)
