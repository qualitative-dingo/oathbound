extends Control
## Main menu: character selection → world selection → play.

enum Screen { CHARACTER_SELECT, WORLD_SELECT }

var _current_screen: int = Screen.CHARACTER_SELECT
var _characters: Array = []
var _worlds: Array = []
var _selected_character: Dictionary = {}

var _char_list: VBoxContainer
var _world_list: VBoxContainer
var _char_panel: PanelContainer
var _world_panel: PanelContainer
var _title_label: Label
var _subtitle_label: Label
var _new_name_input: LineEdit


func _ready() -> void:
	AudioManager.stop_music(1.0)
	_build_ui()
	_show_character_select()


func _build_ui() -> void:
	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.09, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Center column
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.offset_left = -300
	center.offset_right = 300
	center.offset_top = -320
	center.offset_bottom = 320
	center.add_theme_constant_override("separation", 12)
	add_child(center)

	# Title
	_title_label = Label.new()
	_title_label.text = "OATHBOUND"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 40)
	_title_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	center.add_child(_title_label)

	# Subtitle
	_subtitle_label = Label.new()
	_subtitle_label.text = "Select your character"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 18)
	_subtitle_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	center.add_child(_subtitle_label)

	center.add_child(_make_spacer(8))

	# Character panel
	_char_panel = _make_panel()
	var char_scroll := ScrollContainer.new()
	char_scroll.custom_minimum_size = Vector2(580, 300)
	_char_list = VBoxContainer.new()
	_char_list.add_theme_constant_override("separation", 6)
	char_scroll.add_child(_char_list)
	_char_panel.add_child(char_scroll)
	center.add_child(_char_panel)

	# World panel (hidden initially)
	_world_panel = _make_panel()
	var world_scroll := ScrollContainer.new()
	world_scroll.custom_minimum_size = Vector2(580, 300)
	_world_list = VBoxContainer.new()
	_world_list.add_theme_constant_override("separation", 6)
	world_scroll.add_child(_world_list)
	_world_panel.add_child(world_scroll)
	center.add_child(_world_panel)
	_world_panel.visible = false

	center.add_child(_make_spacer(4))

	# New name input row
	var input_row := HBoxContainer.new()
	input_row.add_theme_constant_override("separation", 8)
	_new_name_input = LineEdit.new()
	_new_name_input.placeholder_text = "Enter name..."
	_new_name_input.custom_minimum_size = Vector2(300, 36)
	_new_name_input.add_theme_font_size_override("font_size", 16)
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.12, 0.13, 0.16)
	input_style.border_color = Color(0.3, 0.3, 0.35)
	input_style.set_border_width_all(1)
	input_style.set_corner_radius_all(4)
	input_style.set_content_margin_all(6)
	_new_name_input.add_theme_stylebox_override("normal", input_style)
	input_row.add_child(_new_name_input)

	var create_btn := _make_button("Create New", Color(0.25, 0.5, 0.35))
	create_btn.pressed.connect(_on_create_pressed)
	input_row.add_child(create_btn)

	center.add_child(input_row)

	center.add_child(_make_spacer(4))

	# Back button (only shown on world screen)
	var back_btn := _make_button("< Back to Characters", Color(0.35, 0.3, 0.25))
	back_btn.name = "BackButton"
	back_btn.pressed.connect(_on_back_pressed)
	center.add_child(back_btn)

	# Quit button
	var quit_btn := _make_button("Quit", Color(0.5, 0.2, 0.2))
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	center.add_child(quit_btn)


func _show_character_select() -> void:
	_current_screen = Screen.CHARACTER_SELECT
	_subtitle_label.text = "Select your character"
	_new_name_input.placeholder_text = "Character name..."
	_new_name_input.text = ""
	_char_panel.visible = true
	_world_panel.visible = false
	var back_btn := _char_panel.get_parent().get_node_or_null("BackButton")
	if back_btn:
		back_btn.visible = false
	_refresh_character_list()


func _show_world_select() -> void:
	_current_screen = Screen.WORLD_SELECT
	_subtitle_label.text = "Your worlds"
	_new_name_input.placeholder_text = "World name..."
	_new_name_input.text = ""
	_char_panel.visible = false
	_world_panel.visible = true
	var back_btn := _world_panel.get_parent().get_node_or_null("BackButton")
	if back_btn:
		back_btn.visible = true
	_refresh_world_list()


func _refresh_character_list() -> void:
	for child in _char_list.get_children():
		child.queue_free()

	_characters = SaveManager.get_all_characters()

	if _characters.is_empty():
		var hint := Label.new()
		hint.text = "No characters yet. Create one below!"
		hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_char_list.add_child(hint)
		return

	for i in _characters.size():
		var char_data: Dictionary = _characters[i]
		var subtitle := _format_last_played(char_data)
		var row := _make_list_row(
			str(char_data.get("name", "Unknown")),
			subtitle,
			func() -> void: _on_character_selected(char_data),
			func() -> void: _on_character_deleted(str(char_data.get("id", ""))),
			"Select"
		)
		_char_list.add_child(row)


func _refresh_world_list() -> void:
	for child in _world_list.get_children():
		child.queue_free()

	_worlds = SaveManager.get_all_worlds()

	if _worlds.is_empty():
		var hint := Label.new()
		hint.text = "No worlds yet. Create one below!"
		hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_world_list.add_child(hint)
		return

	for i in _worlds.size():
		var world_data: Dictionary = _worlds[i]
		var row := _make_list_row(
			str(world_data.get("name", "Unknown")),
			"Seed: %s" % str(world_data.get("seed", "?")),
			func() -> void: _on_world_selected(world_data),
			func() -> void: _on_world_deleted(str(world_data.get("id", "")))
		)
		_world_list.add_child(row)


# ═══════════════════════════════════════════════════════════════════════════════
#  CALLBACKS
# ═══════════════════════════════════════════════════════════════════════════════

func _on_character_selected(char_data: Dictionary) -> void:
	_selected_character = char_data
	_show_world_select()


func _on_character_deleted(char_id: String) -> void:
	SaveManager.delete_character(char_id)
	_refresh_character_list()


func _on_world_selected(world_data: Dictionary) -> void:
	SaveManager.start_game(_selected_character, world_data)
	_launch_world(world_data)


func _on_world_deleted(world_id: String) -> void:
	SaveManager.delete_world(world_id)
	_refresh_world_list()


func _on_create_pressed() -> void:
	var new_name := _new_name_input.text.strip_edges()
	if new_name.is_empty():
		return
	if _current_screen == Screen.CHARACTER_SELECT:
		var char_data := SaveManager.create_character(new_name)
		_new_name_input.text = ""
		_refresh_character_list()
	else:
		SaveManager.create_world(new_name)
		_new_name_input.text = ""
		_refresh_world_list()


func _on_back_pressed() -> void:
	_show_character_select()


func _launch_world(world_data: Dictionary) -> void:
	Inventory._slots.clear()
	Inventory._equipped.clear()
	Inventory.give_starting_gear()
	GameEvents.inventory_changed.emit()

	var world_scene := load("res://scenes/world/test_world.tscn") as PackedScene
	var world_instance := world_scene.instantiate()

	var wg := world_instance.get_node_or_null("WorldGenerator")
	if wg:
		wg.set("world_seed", str(world_data.get("seed", "oathbound")))

	get_tree().root.add_child(world_instance)
	get_tree().current_scene = world_instance

	if NetworkManager.pending_host:
		NetworkManager.call_deferred("_do_host_in_world")
	if not skip_save_load:
		SaveManager.call_deferred("_deferred_load_save")
	queue_free()


# ═══════════════════════════════════════════════════════════════════════════════
#  UI HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.11, 0.14, 0.95)
	style.border_color = Color(0.25, 0.25, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_list_row(title: String, subtitle: String, on_select: Callable, on_delete: Callable, select_text := "Play") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	info.add_child(name_label)

	var sub_label := Label.new()
	sub_label.text = subtitle
	sub_label.add_theme_font_size_override("font_size", 13)
	sub_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	info.add_child(sub_label)

	row.add_child(info)

	var select_btn := _make_button(select_text, Color(0.2, 0.45, 0.3))
	select_btn.custom_minimum_size = Vector2(80, 36)
	select_btn.pressed.connect(on_select)
	row.add_child(select_btn)

	var del_btn := _make_button("Delete", Color(0.5, 0.18, 0.18))
	del_btn.custom_minimum_size = Vector2(70, 36)
	del_btn.pressed.connect(func() -> void: _show_delete_confirm(title, on_delete))
	row.add_child(del_btn)

	return row


func _show_delete_confirm(item_name: String, on_confirm: Callable) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.5)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	var dialog := PanelContainer.new()
	var dstyle := StyleBoxFlat.new()
	dstyle.bg_color = Color(0.1, 0.11, 0.14, 0.98)
	dstyle.border_color = Color(0.5, 0.2, 0.2)
	dstyle.set_border_width_all(2)
	dstyle.set_corner_radius_all(8)
	dstyle.set_content_margin_all(24)
	dialog.add_theme_stylebox_override("panel", dstyle)
	dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dialog.offset_left = -180
	dialog.offset_right = 180
	dialog.offset_top = -80
	dialog.offset_bottom = 80
	overlay.add_child(dialog)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	dialog.add_child(vbox)

	var msg := Label.new()
	msg.text = "Delete \"%s\"?" % item_name
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 18)
	msg.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	vbox.add_child(msg)

	var hint := Label.new()
	hint.text = "This cannot be undone."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.55, 0.5, 0.5))
	vbox.add_child(hint)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var no_btn := _make_button("Cancel", Color(0.3, 0.3, 0.35))
	no_btn.custom_minimum_size = Vector2(100, 36)
	no_btn.pressed.connect(func() -> void: overlay.queue_free())
	btn_row.add_child(no_btn)

	var yes_btn := _make_button("Yes, Delete", Color(0.6, 0.15, 0.15))
	yes_btn.custom_minimum_size = Vector2(120, 36)
	yes_btn.pressed.connect(func() -> void:
		overlay.queue_free()
		on_confirm.call()
	)
	btn_row.add_child(yes_btn)


func _make_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 15)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn


func _format_last_played(char_data: Dictionary) -> String:
	if not char_data.has("last_played"):
		return "Never played"
	var last: float = float(char_data["last_played"])
	var now: float = Time.get_unix_time_from_system()
	var hours := int((now - last) / 3600.0)
	if hours < 1:
		return "Last played: <1h ago"
	elif hours == 1:
		return "Last played: 1h ago"
	elif hours < 24:
		return "Last played: %dh ago" % hours
	else:
		var days := hours / 24
		return "Last played: %dd ago" % days


func _make_spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer
