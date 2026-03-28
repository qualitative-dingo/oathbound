class_name SadHawk
extends Node3D
## A sad hawk that can't fly. Wobbles around a center point and cries.

var _orbit_center := Vector3.ZERO
var _orbit_radius := 2.0
var _orbit_speed := 0.8
var _angle := 0.0
var _wobble_phase := 0.0
var _bob_phase := 0.0
var _cry_timer := 0.0

func setup(center: Vector3, radius: float, speed: float) -> void:
	_orbit_center = center
	_orbit_radius = radius
	_orbit_speed = speed
	_angle = randf_range(0.0, TAU)
	_wobble_phase = randf_range(0.0, TAU)
	_bob_phase = randf_range(0.0, TAU)
	_cry_timer = randf_range(0.0, 4.0)

func _process(delta: float) -> void:
	_angle = fmod(_angle + _orbit_speed * delta, TAU)
	_wobble_phase += 3.5 * delta
	_bob_phase += 2.2 * delta

	var target_x := _orbit_center.x + cos(_angle) * _orbit_radius
	var target_z := _orbit_center.z + sin(_angle) * _orbit_radius
	position.x = lerpf(position.x, target_x, 2.5 * delta)
	position.z = lerpf(position.z, target_z, 2.5 * delta)
	position.y = _orbit_center.y + sin(_bob_phase) * 0.08

	rotation.y = _angle + PI
	rotation.z = sin(_wobble_phase) * 0.3
	rotation.x = cos(_wobble_phase * 0.7) * 0.2

	_cry_timer -= delta
	if _cry_timer <= 0.0:
		_cry_timer = randf_range(3.0, 7.0)
		_play_cry()

func _play_cry() -> void:
	var am := Engine.get_singleton("AudioManager") if Engine.has_singleton("AudioManager") else null
	if not am:
		for node in get_tree().get_nodes_in_group(&"audio_manager"):
			am = node
			break
	if am and am.has_method("play_sfx_at"):
		am.play_sfx_at("boar_hurt", global_position, -8.0, 0.4)
