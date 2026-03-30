extends Node3D
## Animates a fish sprite: plays idle frames and gently bobs at the water surface.

var idle_frames: Dictionary = {}  # {dir -> Array[Texture2D]}
var _anim_idx: int = 0
var _anim_timer: float = 0.0
var _bob_phase: float = 0.0
var _base_y: float = 0.0
var _body_sprite: Sprite3D
const FRAME_DUR := 0.15
const BOB_AMP := 0.06
const BOB_SPEED := 1.8


func _ready() -> void:
	_bob_phase = get_meta("bob_phase", randf_range(0.0, TAU))
	_base_y = position.y
	_body_sprite = get_node_or_null("BodySprite") as Sprite3D


func _process(delta: float) -> void:
	_bob_phase += delta * BOB_SPEED
	position.y = _base_y + sin(_bob_phase) * BOB_AMP

	if not _body_sprite:
		return
	var sprite := _body_sprite

	var dir := "south"
	var cam := get_viewport().get_camera_3d()
	if cam:
		var to_cam := cam.global_position - global_position
		to_cam.y = 0.0
		if to_cam.length_squared() > 0.01:
			to_cam = to_cam.normalized()
			var cam_right := cam.global_transform.basis.x
			cam_right.y = 0.0
			cam_right = cam_right.normalized()
			var cam_fwd := -cam.global_transform.basis.z
			cam_fwd.y = 0.0
			cam_fwd = cam_fwd.normalized()
			var fwd := to_cam.dot(cam_fwd)
			var rgt := to_cam.dot(cam_right)
			if absf(fwd) >= absf(rgt):
				dir = "south" if fwd < 0.0 else "north"
			else:
				dir = "west" if rgt < 0.0 else "east"

	if idle_frames.is_empty() or not idle_frames.has(dir):
		return

	_anim_timer -= delta
	if _anim_timer <= 0.0:
		_anim_timer = FRAME_DUR
		var frames: Array = idle_frames[dir] as Array
		if not frames.is_empty():
			_anim_idx = (_anim_idx + 1) % frames.size()
			var tex := frames[_anim_idx] as Texture2D
			if tex:
				sprite.texture = tex
