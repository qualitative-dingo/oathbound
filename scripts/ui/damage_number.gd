class_name DamageNumber
extends Label3D
## WoW-style floating combat text.
## Color defines source (white=auto, yellow=ability, red=enemy, green=heal).
## Scale/animation defines impact (crits pop from 2.5x → 1.0x then slow float).

var _velocity := Vector3.ZERO
var _lifetime := 0.0
var _is_crit := false

const MAX_LIFE := 1.6
const RISE_SPEED := 1.8
const RISE_SPEED_CRIT := 1.2
const DRIFT_RANGE := 0.6
const CRIT_SNAP_TIME := 0.1
const CRIT_SPAWN_SCALE := 2.5
const REFERENCE_DIST := 10.0

static var _combat_font: Font = null

static var _dmg_stack_idx := 0
static var _dmg_last_msec := 0

static var _heal_stack_idx := 0
static var _heal_last_msec := 0


static func _get_combat_font() -> Font:
	if _combat_font == null:
		var path := "res://fonts/Almendra-Regular.ttf"
		if ResourceLoader.exists(path):
			_combat_font = load(path) as Font
	return _combat_font


## hit_type: "auto" = white auto-attack, "ability" = yellow special/elemental,
##           "enemy" = red damage taken from creature
static func spawn(tree: SceneTree, world_pos: Vector3, amount: float, is_crit := false, hit_type := "auto") -> void:
	var label := DamageNumber.new()
	label.text = str(roundi(amount))
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_modulate = Color.BLACK
	label._is_crit = is_crit

	var fnt := _get_combat_font()
	if fnt:
		label.font = fnt

	match hit_type:
		"ability":
			label.modulate = Color(1.0, 1.0, 0.0)
		"enemy":
			label.modulate = Color(1.0, 0.15, 0.15) if is_crit else Color(0.9, 0.2, 0.2)
		_:
			label.modulate = Color.WHITE

	if is_crit:
		label.font_size = 59
		label.outline_size = 13
	else:
		label.font_size = 36
		label.outline_size = 9

	var now := Time.get_ticks_msec()
	if now - _dmg_last_msec > 300:
		_dmg_stack_idx = 0
	_dmg_last_msec = now
	var idx := _dmg_stack_idx
	_dmg_stack_idx += 1

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var cam := tree.root.get_camera_3d()
	var cam_right := Vector3.RIGHT
	if cam:
		cam_right = cam.global_transform.basis.x.normalized()

	var lateral_offset := Vector3.ZERO
	var lateral_vel := Vector3.ZERO
	if idx > 0:
		var side := 1.0 if idx % 2 == 1 else -1.0
		var strength := 0.8 + (idx - 1) * 0.5
		lateral_offset = cam_right * side * strength
		lateral_vel = cam_right * side * (1.5 + idx * 0.5)

	var vertical_stagger := idx * 0.6

	if is_crit:
		label._velocity = lateral_vel + Vector3(
			rng.randf_range(-0.1, 0.1), RISE_SPEED_CRIT,
			rng.randf_range(-0.1, 0.1))
		label.scale = Vector3.ONE * CRIT_SPAWN_SCALE
	else:
		label._velocity = lateral_vel + Vector3(
			rng.randf_range(-0.2, 0.2), RISE_SPEED + rng.randf_range(-0.3, 0.3),
			rng.randf_range(-0.2, 0.2))

	tree.current_scene.add_child(label)
	label.global_position = world_pos + lateral_offset + Vector3(0.0, 1.8 + vertical_stagger, 0.0)


static func spawn_heal(tree: SceneTree, world_pos: Vector3, amount: float, cam_basis: Basis) -> void:
	if amount < 0.5:
		return

	var now := Time.get_ticks_msec()
	if now - _heal_last_msec > 300:
		_heal_stack_idx = 0
	_heal_last_msec = now
	var idx := _heal_stack_idx
	_heal_stack_idx += 1

	var label := DamageNumber.new()
	label.text = "+%d" % roundi(amount)
	label.font_size = 38
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.0, 1.0, 0.0)
	label.outline_modulate = Color.BLACK
	label.outline_size = 8

	var fnt := _get_combat_font()
	if fnt:
		label.font = fnt

	var cam_left := -cam_basis.x.normalized()
	var cam_up := cam_basis.y.normalized()
	var vertical_stagger := idx * 0.45
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var lateral_drift := rng.randf_range(-0.3, 0.3)
	label._velocity = Vector3(0, RISE_SPEED * 0.8, 0) + cam_left * lateral_drift

	tree.current_scene.add_child(label)
	label.global_position = world_pos + Vector3(0.0, 2.2, 0.0) + cam_left * 1.2 + cam_up * vertical_stagger


func _process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= MAX_LIFE:
		queue_free()
		return

	global_position += _velocity * delta
	_velocity.y -= 0.8 * delta

	var progress := _lifetime / MAX_LIFE

	var anim_scale := 1.0
	if _is_crit:
		if _lifetime < CRIT_SNAP_TIME:
			var snap_t := _lifetime / CRIT_SNAP_TIME
			anim_scale = lerpf(CRIT_SPAWN_SCALE, 1.0, snap_t)
		else:
			anim_scale = 1.0 + (progress * 0.1)
	else:
		anim_scale = 1.0 + progress * 0.15

	var cam := get_viewport().get_camera_3d()
	var dist_scale := 1.0
	if cam:
		var dist := global_position.distance_to(cam.global_position)
		dist_scale = maxf(dist / REFERENCE_DIST, 0.5)
	scale = Vector3.ONE * anim_scale * dist_scale

	if progress > 0.6:
		modulate.a = lerpf(1.0, 0.0, (progress - 0.6) / 0.4)
