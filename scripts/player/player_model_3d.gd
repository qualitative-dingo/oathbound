class_name PlayerModel3D
extends Node3D

var _body_pivot: Node3D
var _head: MeshInstance3D
var _l_arm_pivot: Node3D
var _r_arm_pivot: Node3D
var _l_elbow: Node3D
var _r_elbow: Node3D
var _l_leg_pivot: Node3D
var _r_leg_pivot: Node3D
var _l_knee: Node3D
var _r_knee: Node3D
var _all_meshes: Array[MeshInstance3D] = []
var _anim_time: float = 0.0

# Shared materials (one instance per color → fewer draw calls)
var _mat_skin: StandardMaterial3D
var _mat_hair: StandardMaterial3D
var _mat_shirt: StandardMaterial3D
var _mat_belt: StandardMaterial3D
var _mat_pants: StandardMaterial3D
var _mat_boots: StandardMaterial3D


func build() -> void:
	_mat_skin  = _make_mat(Color(0.90, 0.64, 0.52))
	_mat_hair  = _make_mat(Color(0.31, 0.19, 0.18))
	_mat_shirt = _make_mat(Color(0.37, 0.24, 0.19))
	_mat_belt  = _make_mat(Color(0.50, 0.34, 0.26))
	_mat_pants = _make_mat(Color(0.32, 0.21, 0.16))
	_mat_boots = _make_mat(Color(0.24, 0.13, 0.14))

	_body_pivot = Node3D.new()
	_body_pivot.name = "BodyPivot"
	add_child(_body_pivot)

	# ── Torso ──
	_add_box(_body_pivot, Vector3(0, 0.225, 0), Vector3(0.38, 0.45, 0.20), _mat_shirt)
	_add_box(_body_pivot, Vector3(0, 0.03, 0), Vector3(0.40, 0.06, 0.22), _mat_belt)

	# ── Head ──
	_head = _add_box(_body_pivot, Vector3(0, 0.62, 0), Vector3(0.24, 0.28, 0.24), _mat_skin)
	_add_box(_body_pivot, Vector3(0, 0.78, 0), Vector3(0.26, 0.08, 0.26), _mat_hair)
	_add_box(_body_pivot, Vector3(0, 0.68, -0.01), Vector3(0.26, 0.20, 0.26), _mat_hair)
	_add_box(_body_pivot, Vector3(0, 0.50, 0.08), Vector3(0.14, 0.12, 0.08), _mat_hair)

	# ── Left arm ──
	_l_arm_pivot = _make_pivot(_body_pivot, "LArmPivot", Vector3(-0.25, 0.38, 0))
	_add_box(_l_arm_pivot, Vector3(0, -0.15, 0), Vector3(0.11, 0.30, 0.11), _mat_shirt)
	_l_elbow = _make_pivot(_l_arm_pivot, "LElbow", Vector3(0, -0.30, 0))
	_add_box(_l_elbow, Vector3(0, -0.13, 0), Vector3(0.09, 0.26, 0.09), _mat_skin)

	# ── Right arm ──
	_r_arm_pivot = _make_pivot(_body_pivot, "RArmPivot", Vector3(0.25, 0.38, 0))
	_add_box(_r_arm_pivot, Vector3(0, -0.15, 0), Vector3(0.11, 0.30, 0.11), _mat_shirt)
	_r_elbow = _make_pivot(_r_arm_pivot, "RElbow", Vector3(0, -0.30, 0))
	_add_box(_r_elbow, Vector3(0, -0.13, 0), Vector3(0.09, 0.26, 0.09), _mat_skin)

	# ── Left leg ──
	_l_leg_pivot = _make_pivot(_body_pivot, "LLegPivot", Vector3(-0.09, 0, 0))
	_add_box(_l_leg_pivot, Vector3(0, -0.19, 0), Vector3(0.13, 0.38, 0.13), _mat_pants)
	_l_knee = _make_pivot(_l_leg_pivot, "LKnee", Vector3(0, -0.38, 0))
	_add_box(_l_knee, Vector3(0, -0.17, 0), Vector3(0.12, 0.34, 0.12), _mat_pants)
	_add_box(_l_knee, Vector3(0, -0.37, 0.03), Vector3(0.12, 0.07, 0.18), _mat_boots)

	# ── Right leg ──
	_r_leg_pivot = _make_pivot(_body_pivot, "RLegPivot", Vector3(0.09, 0, 0))
	_add_box(_r_leg_pivot, Vector3(0, -0.19, 0), Vector3(0.13, 0.38, 0.13), _mat_pants)
	_r_knee = _make_pivot(_r_leg_pivot, "RKnee", Vector3(0, -0.38, 0))
	_add_box(_r_knee, Vector3(0, -0.17, 0), Vector3(0.12, 0.34, 0.12), _mat_pants)
	_add_box(_r_knee, Vector3(0, -0.37, 0.03), Vector3(0.12, 0.07, 0.18), _mat_boots)


func tick(delta: float, is_moving: bool, is_sprinting: bool, is_attacking: bool) -> void:
	_anim_time += delta
	if is_attacking:
		_animate_attack()
	elif is_moving:
		var spd := 11.0 if is_sprinting else 7.0
		var arm_a := 0.75 if is_sprinting else 0.50
		var leg_a := 0.65 if is_sprinting else 0.40
		_animate_walk(spd, arm_a, leg_a)
	else:
		_animate_idle()


func flash(col: Color) -> void:
	for mi in _all_meshes:
		var m := mi.material_override as StandardMaterial3D
		if m:
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = 2.0


func clear_flash() -> void:
	for mi in _all_meshes:
		var m := mi.material_override as StandardMaterial3D
		if m:
			m.emission_enabled = false


# ── Idle: subtle breathing ──
func _animate_idle() -> void:
	var t := _anim_time
	_body_pivot.position.y = sin(t * 1.5) * 0.006

	_l_arm_pivot.rotation.x = sin(t * 0.7) * 0.04
	_r_arm_pivot.rotation.x = sin(t * 0.7 + 0.5) * 0.04
	_l_elbow.rotation.x = -0.08
	_r_elbow.rotation.x = -0.08

	_l_leg_pivot.rotation.x = 0.0
	_r_leg_pivot.rotation.x = 0.0
	_l_knee.rotation.x = 0.0
	_r_knee.rotation.x = 0.0


# ── Walk / Run: alternating arm-leg swing ──
func _animate_walk(speed: float, arm_amp: float, leg_amp: float) -> void:
	var t := _anim_time * speed

	_l_arm_pivot.rotation.x = sin(t) * arm_amp
	_r_arm_pivot.rotation.x = sin(t + PI) * arm_amp
	_l_elbow.rotation.x = -absf(sin(t)) * 0.35
	_r_elbow.rotation.x = -absf(sin(t + PI)) * 0.35

	_l_leg_pivot.rotation.x = sin(t + PI) * leg_amp
	_r_leg_pivot.rotation.x = sin(t) * leg_amp
	_l_knee.rotation.x = -absf(sin(t + PI)) * 0.45
	_r_knee.rotation.x = -absf(sin(t)) * 0.45

	_body_pivot.position.y = absf(sin(t * 2.0)) * 0.015


# ── Attack: right arm forward swing ──
func _animate_attack() -> void:
	var phase := fmod(_anim_time * 8.0, TAU)
	_r_arm_pivot.rotation.x = -sin(phase) * 1.5
	_r_elbow.rotation.x = -absf(sin(phase * 0.5)) * 0.8

	_l_arm_pivot.rotation.x = 0.0
	_l_elbow.rotation.x = -0.1
	_l_leg_pivot.rotation.x = 0.0
	_r_leg_pivot.rotation.x = 0.0
	_l_knee.rotation.x = 0.0
	_r_knee.rotation.x = 0.0


# ── Helpers ──

func _make_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.78
	m.metallic = 0.0
	return m


func _make_pivot(parent: Node3D, pname: String, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = pname
	p.position = pos
	parent.add_child(p)
	return p


func _add_box(parent: Node3D, pos: Vector3, sz: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = sz
	mi.mesh = bx
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	_all_meshes.append(mi)
	return mi
