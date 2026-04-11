class_name DialogueUI
extends Node

signal dialogue_finished(action: String)

var pc: PlayerController
var _panel: PanelContainer
var _speaker_label: Label
var _text_label: RichTextLabel
var _choices_box: VBoxContainer
var _continue_btn: Button
var _is_open: bool = false

var _tree: Array[Dictionary] = []
var _step: int = 0
var _showing_response: bool = false
var _pending_next: int = -1
var _pending_action: String = ""


func build_panel(root: Control) -> void:
	_panel = PanelContainer.new()
	_panel.name = "DialoguePanel"
	_panel.visible = false
	_panel.anchor_left = 0.12
	_panel.anchor_right = 0.88
	_panel.anchor_top = 0.62
	_panel.anchor_bottom = 0.95
	_panel.offset_left = 0
	_panel.offset_right = 0
	_panel.offset_top = 0
	_panel.offset_bottom = -16
	_panel.z_index = 100
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.05, 0.03, 0.94)
	bg.border_color = Color(0.65, 0.48, 0.18)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(10)
	bg.set_content_margin_all(20)
	_panel.add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 20)
	_speaker_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	vbox.add_child(_speaker_label)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.5, 0.38, 0.15, 0.5))
	vbox.add_child(sep)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.scroll_active = false
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("normal_font_size", 16)
	_text_label.add_theme_color_override("default_color", Color(0.88, 0.84, 0.74))
	vbox.add_child(_text_label)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 6)
	_choices_box.visible = false
	vbox.add_child(_choices_box)

	_continue_btn = Button.new()
	_continue_btn.text = "Continue  \u25b6"
	_continue_btn.add_theme_font_size_override("font_size", 14)
	_continue_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_continue_btn.custom_minimum_size = Vector2(130, 36)
	_continue_btn.visible = false

	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.16, 0.13, 0.08, 0.85)
	btn_style.border_color = Color(0.6, 0.45, 0.18)
	btn_style.set_border_width_all(1)
	btn_style.set_corner_radius_all(5)
	btn_style.set_content_margin_all(6)
	_continue_btn.add_theme_stylebox_override("normal", btn_style)

	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.22, 0.18, 0.1, 0.9)
	btn_hover.border_color = Color(0.8, 0.6, 0.25)
	btn_hover.set_border_width_all(1)
	btn_hover.set_corner_radius_all(5)
	btn_hover.set_content_margin_all(6)
	_continue_btn.add_theme_stylebox_override("hover", btn_hover)
	_continue_btn.add_theme_stylebox_override("pressed", btn_hover)
	_continue_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.55))
	_continue_btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7))
	_continue_btn.pressed.connect(_on_continue)
	vbox.add_child(_continue_btn)

	_panel.add_child(vbox)
	root.add_child(_panel)


func open_dialogue(tree: Array[Dictionary]) -> void:
	_tree = tree
	_step = 0
	_showing_response = false
	_pending_next = -1
	_pending_action = ""
	_is_open = true
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if pc and pc._minimap_biome_label:
		pc._minimap_biome_label.visible = false
	_present_step()


func close_dialogue() -> void:
	_panel.visible = false
	_is_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if pc and pc._minimap_biome_label:
		pc._minimap_biome_label.visible = true


func is_open() -> bool:
	return _is_open


func _present_step() -> void:
	if _step < 0 or _step >= _tree.size():
		close_dialogue()
		dialogue_finished.emit("end")
		return

	_clear_choices()
	_continue_btn.visible = false

	var node: Dictionary = _tree[_step]
	var type: String = str(node.get("type", "npc"))

	if type == "npc":
		_speaker_label.text = str(node.get("speaker", "???"))
		_text_label.text = str(node.get("text", ""))
		_pending_next = int(node.get("next", _step + 1))
		_continue_btn.visible = true
		_continue_btn.grab_focus()
	elif type == "choice" or type == "final":
		_show_choices(node)


func _show_choices(node: Dictionary) -> void:
	_clear_choices()
	_choices_box.visible = true

	var options: Array = node.get("options", []) as Array
	for i in options.size():
		var opt: Dictionary = options[i] as Dictionary
		var btn := Button.new()
		btn.text = "  \u25b8  " + str(opt.get("label", "..."))
		btn.add_theme_font_size_override("font_size", 15)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 40)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.08, 0.05, 0.8)
		style.border_color = Color(0.45, 0.35, 0.15, 0.6)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(8)
		btn.add_theme_stylebox_override("normal", style)

		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = Color(0.18, 0.14, 0.07, 0.9)
		hover_style.border_color = Color(0.75, 0.55, 0.2)
		hover_style.set_border_width_all(1)
		hover_style.set_corner_radius_all(6)
		hover_style.set_content_margin_all(8)
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", hover_style)

		btn.add_theme_color_override("font_color", Color(0.85, 0.8, 0.65))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.6))

		var bound_opt := opt
		var bound_type := str(node.get("type", "choice"))
		btn.pressed.connect(_on_choice_picked.bind(bound_opt, bound_type))
		_choices_box.add_child(btn)

	if _choices_box.get_child_count() > 0:
		(_choices_box.get_child(0) as Button).grab_focus()


func _on_choice_picked(opt: Dictionary, type: String) -> void:
	var response: String = str(opt.get("response", ""))
	var speaker: String = str(opt.get("response_speaker", "Halvard"))

	if response != "":
		_clear_choices()
		_choices_box.visible = false
		_speaker_label.text = speaker
		_text_label.text = response
		_showing_response = true

		if type == "final":
			_pending_action = str(opt.get("action", ""))
			_pending_next = -1
		else:
			_pending_next = int(opt.get("next", _step + 1))
			_pending_action = ""

		_continue_btn.visible = true
		_continue_btn.grab_focus()
	else:
		if type == "final":
			var action := str(opt.get("action", ""))
			close_dialogue()
			dialogue_finished.emit(action)
		else:
			_step = int(opt.get("next", _step + 1))
			_showing_response = false
			_present_step()


func _on_continue() -> void:
	if _showing_response:
		_showing_response = false
		if _pending_action != "":
			var action := _pending_action
			_pending_action = ""
			close_dialogue()
			dialogue_finished.emit(action)
			return
		if _pending_next >= 0:
			_step = _pending_next
			_pending_next = -1
			_present_step()
		else:
			close_dialogue()
			dialogue_finished.emit("end")
	else:
		_step = _pending_next if _pending_next >= 0 else _step + 1
		_pending_next = -1
		_present_step()


func _clear_choices() -> void:
	for child in _choices_box.get_children():
		_choices_box.remove_child(child)
		child.queue_free()
	_choices_box.visible = false
