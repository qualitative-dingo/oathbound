extends Label
## HUD label that displays the interaction prompt.
## Centered at the bottom-third of the screen.
## The InteractionManager sets .text and .visible directly,
## but this script handles the fade-in/out polish.

var _tween: Tween


func _ready() -> void:
	visible = false
	modulate.a = 0.0

	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	anchors_preset = PRESET_CENTER_BOTTOM
	offset_top = -80.0
	offset_bottom = -40.0
	offset_left = -200.0
	offset_right = 200.0

	add_theme_font_size_override("font_size", 20)
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	add_theme_constant_override("shadow_offset_x", 2)
	add_theme_constant_override("shadow_offset_y", 2)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_VISIBILITY_CHANGED:
			_animate_visibility()


func _animate_visibility() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	if visible:
		_tween.tween_property(self, "modulate:a", 1.0, 0.15)
	else:
		_tween.tween_property(self, "modulate:a", 0.0, 0.1)
		_tween.tween_callback(func(): visible = false)
		# Keep visible during fade-out so tween can run
		visible = true
