extends ProgressBar
## Displays the player's health as a red bar. Connects to GameEvents.

func _ready() -> void:
	GameEvents.player_health_changed.connect(_on_health_changed)
	modulate = Color(0.9, 0.2, 0.2)


func _on_health_changed(current: float, maximum: float) -> void:
	max_value = maximum
	value = current
