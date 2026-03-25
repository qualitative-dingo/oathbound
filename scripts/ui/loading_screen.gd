class_name LoadingScreen
extends CanvasLayer

const TIPS: Array[String] = [
	"Craft a torch to light your path at night",
	"Right-click hold to equip weapons and armor",
	"Shift+right-click to drop items on the ground",
	"Higher star gear rolls more powerful affixes",
	"Build a workbench to unlock better recipes",
	"Watch your stamina when swimming in deep water",
	"Explore rivers - you might find useful plants",
	"Defeated creatures drop better loot at higher star levels",
	"Build a bed to set your respawn point",
	"Stone and flint can both drop from mining rocks",
	"Hold right-click to draw your bow for ranged attacks",
	"Copper ore can be found in caves",
]

var _bg: ColorRect
var _dots_label: Label
var _tween: Tween
var _dot_timer: float = 0.0
var _dot_count: int = 0


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	_bg = ColorRect.new()
	_bg.color = Color(0.04, 0.04, 0.06, 1.0)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 24)
	_bg.add_child(vbox)

	var title := Label.new()
	title.text = "OATHBOUND"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.82, 0.72, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_dots_label = Label.new()
	_dots_label.text = "Loading."
	_dots_label.add_theme_font_size_override("font_size", 18)
	_dots_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.50))
	_dots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_dots_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	var tip := Label.new()
	tip.text = TIPS[randi() % TIPS.size()]
	tip.add_theme_font_size_override("font_size", 14)
	tip.add_theme_color_override("font_color", Color(0.45, 0.43, 0.38))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size.x = 500
	vbox.add_child(tip)

	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _process(delta: float) -> void:
	_dot_timer += delta
	if _dot_timer >= 0.4:
		_dot_timer = 0.0
		_dot_count = (_dot_count + 1) % 4
		var dots := ".".repeat(_dot_count + 1)
		_dots_label.text = "Loading" + dots


func dismiss() -> void:
	set_process(false)
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_bg, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(queue_free)
