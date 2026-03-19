class_name DamageNumber
extends Label3D
## Floating damage number that rises and fades out, then self-destructs.

var _velocity := Vector3.ZERO
var _lifetime := 0.0
const MAX_LIFE := 0.8
const RISE_SPEED := 2.5
const DRIFT_RANGE := 0.8


## source_type: "player" = damage dealt BY player (white/yellow crit),
##              "enemy"  = damage dealt BY enemy  (red / big red crit)
static func spawn(tree: SceneTree, world_pos: Vector3, amount: float, is_crit := false, source_type := "player") -> void:
	var label := DamageNumber.new()
	label.text = str(roundi(amount))
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_modulate = Color.BLACK
	label.outline_size = 8

	if source_type == "player":
		label.font_size = 52 if is_crit else 36
		label.modulate = Color(1.0, 0.9, 0.1) if is_crit else Color.WHITE
	else:
		label.font_size = 52 if is_crit else 36
		label.modulate = Color(1.0, 0.1, 0.1) if is_crit else Color(0.9, 0.2, 0.2)

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	label._velocity = Vector3(
		rng.randf_range(-DRIFT_RANGE, DRIFT_RANGE),
		RISE_SPEED,
		rng.randf_range(-DRIFT_RANGE, DRIFT_RANGE)
	)

	tree.current_scene.add_child(label)
	label.global_position = world_pos + Vector3(0.0, 1.8, 0.0)


func _process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= MAX_LIFE:
		queue_free()
		return

	global_position += _velocity * delta
	_velocity.y -= 3.0 * delta

	var progress := _lifetime / MAX_LIFE
	modulate.a = 1.0 - progress * progress
	scale = Vector3.ONE * (1.0 + progress * 0.3)
