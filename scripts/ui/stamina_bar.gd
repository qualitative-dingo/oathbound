extends ProgressBar
## Listens to GameEvents.player_stamina_changed and updates the bar.
## Fades out when stamina is full; fades in when draining.

var _tween: Tween


func _ready() -> void:
	GameEvents.player_stamina_changed.connect(_on_stamina_changed)
	modulate.a = 0.0


func _on_stamina_changed(current: float, maximum: float) -> void:
	max_value = maximum
	value = current

	var should_show := current < maximum - 0.5
	var target_alpha := 1.0 if should_show else 0.0

	if absf(modulate.a - target_alpha) < 0.01:
		return

	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", target_alpha, 0.25)
