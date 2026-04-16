extends Control

const _DEBUG_LOG := false

## Main menu: character selection → world selection → play.

enum Screen { CHARACTER_SELECT, WORLD_SELECT, PLAY_MODE }
enum Palette { WARM, COOL }

var _current_screen: int = Screen.CHARACTER_SELECT
var _characters: Array = []
var _worlds: Array = []
var _selected_character: Dictionary = {}
var _selected_world: Dictionary = {}

var _screen_root: Control
var _char_list: VBoxContainer
var _world_list: VBoxContainer
var _play_mode_panel: PanelContainer
var _new_char_name_input: LineEdit
var _new_world_name_input: LineEdit
var _new_world_seed_input: LineEdit
var _ip_input: LineEdit
var _connection_status: Label
var _bg: ColorRect

# ── Palette constants ─────────────────────────────────────────────────────────
const _WARM_BG := Color(0.08, 0.06, 0.04, 1.0)
const _WARM_OUTER_BG := Color(0.05, 0.04, 0.025, 0.97)
const _WARM_OUTER_BORDER := Color(0.50, 0.38, 0.14)
const _WARM_INNER_BG := Color(0.09, 0.07, 0.05, 0.98)
const _WARM_INNER_BORDER := Color(0.60, 0.46, 0.18, 0.6)
const _WARM_ACCENT := Color(0.85, 0.68, 0.25)
const _WARM_TEXT := Color(0.92, 0.85, 0.68)
const _WARM_TEXT_DIM := Color(0.58, 0.52, 0.40)
const _WARM_BTN_HOVER_BG := Color(0.14, 0.11, 0.06, 0.85)
const _WARM_BTN_HOVER_BORDER := Color(0.65, 0.48, 0.18, 0.8)
const _WARM_INPUT_BG := Color(0.10, 0.08, 0.05)
const _WARM_INPUT_BORDER := Color(0.40, 0.32, 0.15)

const _COOL_BG := Color(0.04, 0.06, 0.09, 1.0)
const _COOL_OUTER_BG := Color(0.03, 0.04, 0.07, 0.97)
const _COOL_OUTER_BORDER := Color(0.30, 0.38, 0.52)
const _COOL_INNER_BG := Color(0.06, 0.07, 0.10, 0.98)
const _COOL_INNER_BORDER := Color(0.40, 0.48, 0.62, 0.6)
const _COOL_ACCENT := Color(0.45, 0.65, 0.82)
const _COOL_TEXT := Color(0.88, 0.90, 0.94)
const _COOL_TEXT_DIM := Color(0.45, 0.48, 0.55)
const _COOL_BTN_HOVER_BG := Color(0.08, 0.10, 0.16, 0.85)
const _COOL_BTN_HOVER_BORDER := Color(0.35, 0.50, 0.70, 0.8)
const _COOL_INPUT_BG := Color(0.06, 0.07, 0.11)
const _COOL_INPUT_BORDER := Color(0.25, 0.30, 0.45)

const _DANGER_ACCENT := Color(0.70, 0.22, 0.18)
const _DANGER_HOVER_BG := Color(0.18, 0.08, 0.06, 0.85)
const _DANGER_HOVER_BORDER := Color(0.72, 0.28, 0.20, 0.8)


func _ready() -> void:
	AudioManager.stop_music(1.0)
	_build_background()
	_show_character_select()
	if SteamManager.is_steam_ready:
		SteamManager.join_lobby_requested.connect(_on_steam_join_requested)


func _build_background() -> void:
	_bg = ColorRect.new()
	_bg.color = _WARM_BG
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)


# ═══════════════════════════════════════════════════════════════════════════════
#  CHARACTER SELECT — "The Roster" (warm / parchment)
# ═══════════════════════════════════════════════════════════════════════════════

func _show_character_select() -> void:
	_current_screen = Screen.CHARACTER_SELECT
	_bg.color = _WARM_BG
	_clear_screen()

	_screen_root = Control.new()
	_screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen_root)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.offset_left = -340
	center.offset_right = 340
	center.offset_top = -340
	center.offset_bottom = 340
	center.add_theme_constant_override("separation", 0)
	_screen_root.add_child(center)

	# Title block
	center.add_child(_make_spacer(18))
	center.add_child(_make_title_block(
		"OATHBOUND",
		"Choose Your Champion",
		Palette.WARM
	))
	center.add_child(_make_spacer(16))

	# Double-panel list area
	var outer := _make_outer_panel(Palette.WARM)
	var inner := _make_inner_panel(Palette.WARM)

	var content_vbox := VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 8)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(620, 280)
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_char_list = VBoxContainer.new()
	_char_list.add_theme_constant_override("separation", 4)
	_char_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_char_list)
	content_vbox.add_child(list_scroll)

	# Ornamental divider
	content_vbox.add_child(_make_ornamental_separator(Palette.WARM))

	# Create new character row
	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 10)
	create_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var shield := Label.new()
	shield.text = "\u2726"
	shield.add_theme_font_size_override("font_size", 18)
	shield.add_theme_color_override("font_color", _WARM_ACCENT)
	create_row.add_child(shield)

	_new_char_name_input = _make_line_edit("Name your champion...", Palette.WARM)
	_new_char_name_input.custom_minimum_size = Vector2(280, 38)
	create_row.add_child(_new_char_name_input)

	var create_btn := _make_button("Create", Palette.WARM, true)
	create_btn.custom_minimum_size = Vector2(100, 38)
	create_btn.pressed.connect(_on_create_character)
	create_row.add_child(create_btn)

	_new_char_name_input.text_submitted.connect(func(_t: String) -> void: _on_create_character())

	content_vbox.add_child(create_row)

	inner.add_child(content_vbox)
	outer.add_child(inner)
	center.add_child(outer)

	center.add_child(_make_spacer(14))

	# Quit button
	var quit_row := HBoxContainer.new()
	quit_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var quit_btn := _make_button("Quit Game", Palette.WARM, false, true)
	quit_btn.custom_minimum_size = Vector2(140, 36)
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	quit_row.add_child(quit_btn)
	center.add_child(quit_row)

	_refresh_character_list()


# ═══════════════════════════════════════════════════════════════════════════════
#  WORLD SELECT — "The Atlas" (cool / cartographic)
# ═══════════════════════════════════════════════════════════════════════════════

func _show_world_select() -> void:
	_current_screen = Screen.WORLD_SELECT
	_bg.color = _COOL_BG
	_clear_screen()

	_screen_root = Control.new()
	_screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen_root)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.offset_left = -340
	center.offset_right = 340
	center.offset_top = -340
	center.offset_bottom = 340
	center.add_theme_constant_override("separation", 0)
	_screen_root.add_child(center)

	# Character badge at top
	var char_name: String = str(_selected_character.get("name", "Unknown"))
	var playing_as := Label.new()
	playing_as.text = "Playing as:  %s" % char_name
	playing_as.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	playing_as.add_theme_font_size_override("font_size", 13)
	playing_as.add_theme_color_override("font_color", _COOL_TEXT_DIM)
	center.add_child(playing_as)

	center.add_child(_make_spacer(10))

	# Title block
	center.add_child(_make_title_block(
		"SELECT A WORLD",
		"Chart your course",
		Palette.COOL
	))
	center.add_child(_make_spacer(16))

	# Double-panel list area
	var outer := _make_outer_panel(Palette.COOL)
	var inner := _make_inner_panel(Palette.COOL)

	var content_vbox := VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 8)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(620, 240)
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_world_list = VBoxContainer.new()
	_world_list.add_theme_constant_override("separation", 4)
	_world_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_world_list)
	content_vbox.add_child(list_scroll)

	content_vbox.add_child(_make_ornamental_separator(Palette.COOL))

	# Create new world section
	var create_col := VBoxContainer.new()
	create_col.add_theme_constant_override("separation", 6)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var compass := Label.new()
	compass.text = "\u2726"
	compass.add_theme_font_size_override("font_size", 18)
	compass.add_theme_color_override("font_color", _COOL_ACCENT)
	name_row.add_child(compass)

	_new_world_name_input = _make_line_edit("Name this world...", Palette.COOL)
	_new_world_name_input.custom_minimum_size = Vector2(260, 38)
	name_row.add_child(_new_world_name_input)

	var create_btn := _make_button("Forge World", Palette.COOL, true)
	create_btn.custom_minimum_size = Vector2(120, 38)
	create_btn.pressed.connect(_on_create_world)
	name_row.add_child(create_btn)

	_new_world_name_input.text_submitted.connect(func(_t: String) -> void: _on_create_world())

	create_col.add_child(name_row)

	# Optional seed input
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var seed_label := Label.new()
	seed_label.text = "Seed (optional):"
	seed_label.add_theme_font_size_override("font_size", 12)
	seed_label.add_theme_color_override("font_color", _COOL_TEXT_DIM)
	seed_row.add_child(seed_label)

	_new_world_seed_input = _make_line_edit("Leave blank for random", Palette.COOL)
	_new_world_seed_input.custom_minimum_size = Vector2(240, 30)
	_new_world_seed_input.add_theme_font_size_override("font_size", 13)
	seed_row.add_child(_new_world_seed_input)

	create_col.add_child(seed_row)
	content_vbox.add_child(create_col)

	inner.add_child(content_vbox)
	outer.add_child(inner)
	center.add_child(outer)

	center.add_child(_make_spacer(14))

	# Bottom buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)

	var back_btn := _make_button("\u25c0  Back", Palette.COOL)
	back_btn.custom_minimum_size = Vector2(120, 36)
	back_btn.pressed.connect(_on_back_pressed)
	btn_row.add_child(back_btn)

	var quit_btn := _make_button("Quit Game", Palette.COOL, false, true)
	quit_btn.custom_minimum_size = Vector2(120, 36)
	quit_btn.pressed.connect(func() -> void: get_tree().quit())
	btn_row.add_child(quit_btn)

	center.add_child(btn_row)

	_refresh_world_list()


# ═══════════════════════════════════════════════════════════════════════════════
#  PLAY MODE (cool palette, inherits world screen)
# ═══════════════════════════════════════════════════════════════════════════════

func _show_play_mode() -> void:
	_current_screen = Screen.PLAY_MODE
	_bg.color = _COOL_BG
	_clear_screen()

	_screen_root = Control.new()
	_screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen_root)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.offset_left = -260
	center.offset_right = 260
	center.offset_top = -280
	center.offset_bottom = 280
	center.add_theme_constant_override("separation", 0)
	_screen_root.add_child(center)

	var char_name: String = str(_selected_character.get("name", "Unknown"))
	var world_name: String = str(_selected_world.get("name", "World"))
	center.add_child(_make_title_block(
		"%s on %s" % [char_name, world_name],
		"",
		Palette.COOL
	))
	center.add_child(_make_spacer(16))

	var outer := _make_outer_panel(Palette.COOL)
	var inner := _make_inner_panel(Palette.COOL)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	if SteamManager.is_steam_ready:
		var steam_label := _make_section_label("STEAM", Palette.COOL)
		vbox.add_child(steam_label)

		var steam_host_btn := _make_button("Host Online Game", Palette.COOL, true)
		steam_host_btn.custom_minimum_size = Vector2(0, 44)
		steam_host_btn.pressed.connect(_on_host_steam)
		vbox.add_child(steam_host_btn)

		var steam_hint := Label.new()
		steam_hint.text = "Friends join via Steam: right-click your name \u2192 Join Game"
		steam_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		steam_hint.add_theme_font_size_override("font_size", 11)
		steam_hint.add_theme_color_override("font_color", _COOL_TEXT_DIM)
		steam_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(steam_hint)

		vbox.add_child(_make_ornamental_separator(Palette.COOL))

	var lan_label := _make_section_label("LOCAL NETWORK", Palette.COOL)
	vbox.add_child(lan_label)

	var host_btn := _make_button("Host LAN Game", Palette.COOL, true)
	host_btn.custom_minimum_size = Vector2(0, 44)
	host_btn.pressed.connect(_on_host_lan)
	vbox.add_child(host_btn)

	_ip_input = _make_line_edit("Host IP (e.g. 192.168.1.50)", Palette.COOL)
	_ip_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_ip_input)

	var join_btn := _make_button("Join LAN Game", Palette.COOL)
	join_btn.custom_minimum_size = Vector2(0, 44)
	join_btn.pressed.connect(_on_join_lan)
	vbox.add_child(join_btn)

	_connection_status = Label.new()
	_connection_status.text = ""
	_connection_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_connection_status.add_theme_font_size_override("font_size", 13)
	_connection_status.add_theme_color_override("font_color", _COOL_ACCENT)
	vbox.add_child(_connection_status)

	inner.add_child(vbox)
	outer.add_child(inner)
	center.add_child(outer)

	center.add_child(_make_spacer(14))

	var back_btn := _make_button("\u25c0  Back to Worlds", Palette.COOL)
	back_btn.custom_minimum_size = Vector2(180, 36)
	back_btn.pressed.connect(_on_back_pressed)
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(back_btn)
	center.add_child(back_row)


# ═══════════════════════════════════════════════════════════════════════════════
#  LIST REFRESH
# ═══════════════════════════════════════════════════════════════════════════════

func _refresh_character_list() -> void:
	if not _char_list:
		return
	for child in _char_list.get_children():
		child.queue_free()

	_characters = SaveManager.get_all_characters()

	if _characters.is_empty():
		var hint := Label.new()
		hint.text = "No champions yet \u2014 create one below"
		hint.add_theme_color_override("font_color", _WARM_TEXT_DIM)
		hint.add_theme_font_size_override("font_size", 15)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_char_list.add_child(hint)
		return

	for i in _characters.size():
		var char_data: Dictionary = _characters[i]
		var row := _make_char_row(char_data)
		_char_list.add_child(row)


func _refresh_world_list() -> void:
	if not _world_list:
		return
	for child in _world_list.get_children():
		child.queue_free()

	_worlds = SaveManager.get_all_worlds()

	if _worlds.is_empty():
		var hint := Label.new()
		hint.text = "No worlds yet \u2014 forge one below"
		hint.add_theme_color_override("font_color", _COOL_TEXT_DIM)
		hint.add_theme_font_size_override("font_size", 15)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_world_list.add_child(hint)
		return

	for i in _worlds.size():
		var world_data: Dictionary = _worlds[i]
		var row := _make_world_row(world_data)
		_world_list.add_child(row)


# ═══════════════════════════════════════════════════════════════════════════════
#  LIST ROW BUILDERS
# ═══════════════════════════════════════════════════════════════════════════════

func _make_char_row(char_data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.05, 0.4)
	style.border_color = Color(0.30, 0.25, 0.14, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	# Shield icon
	var icon := Label.new()
	icon.text = "\u2694"
	icon.add_theme_font_size_override("font_size", 22)
	icon.add_theme_color_override("font_color", _WARM_ACCENT)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	# Info column
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	name_label.text = str(char_data.get("name", "Unknown"))
	name_label.add_theme_font_size_override("font_size", 19)
	name_label.add_theme_color_override("font_color", _WARM_TEXT)
	info.add_child(name_label)

	var sub_label := Label.new()
	sub_label.text = _format_last_played(char_data)
	sub_label.add_theme_font_size_override("font_size", 12)
	sub_label.add_theme_color_override("font_color", _WARM_TEXT_DIM)
	info.add_child(sub_label)

	row.add_child(info)

	# Buttons
	var select_btn := _make_button("Select", Palette.WARM, true)
	select_btn.custom_minimum_size = Vector2(82, 34)
	var bound_data := char_data
	select_btn.pressed.connect(func() -> void: _on_character_selected(bound_data))
	row.add_child(select_btn)

	var del_btn := _make_button("Delete", Palette.WARM, false, true)
	del_btn.custom_minimum_size = Vector2(72, 34)
	var bound_name := str(char_data.get("name", "Unknown"))
	var bound_id := str(char_data.get("id", ""))
	del_btn.pressed.connect(func() -> void:
		_show_delete_confirm(bound_name, Palette.WARM, func() -> void:
			SaveManager.delete_character(bound_id)
			_refresh_character_list()
		)
	)
	row.add_child(del_btn)

	panel.add_child(row)
	return panel


func _make_world_row(world_data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.4)
	style.border_color = Color(0.20, 0.25, 0.35, 0.3)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	# Globe icon
	var icon := Label.new()
	icon.text = "\u2637"
	icon.add_theme_font_size_override("font_size", 22)
	icon.add_theme_color_override("font_color", _COOL_ACCENT)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	# Info column
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	name_label.text = str(world_data.get("name", "Unknown"))
	name_label.add_theme_font_size_override("font_size", 19)
	name_label.add_theme_color_override("font_color", _COOL_TEXT)
	info.add_child(name_label)

	var seed_str := str(world_data.get("seed", "?"))
	if seed_str.length() > 32:
		seed_str = seed_str.substr(0, 32) + "\u2026"
	var sub_label := Label.new()
	sub_label.text = "Seed: %s" % seed_str
	sub_label.add_theme_font_size_override("font_size", 12)
	sub_label.add_theme_color_override("font_color", _COOL_TEXT_DIM)
	info.add_child(sub_label)

	row.add_child(info)

	# Buttons
	var play_btn := _make_button("Play", Palette.COOL, true)
	play_btn.custom_minimum_size = Vector2(72, 34)
	var bound_data := world_data
	play_btn.pressed.connect(func() -> void: _on_world_selected(bound_data))
	row.add_child(play_btn)

	var del_btn := _make_button("Delete", Palette.COOL, false, true)
	del_btn.custom_minimum_size = Vector2(72, 34)
	var bound_name := str(world_data.get("name", "Unknown"))
	var bound_id := str(world_data.get("id", ""))
	del_btn.pressed.connect(func() -> void:
		_show_delete_confirm(bound_name, Palette.COOL, func() -> void:
			SaveManager.delete_world(bound_id)
			_refresh_world_list()
		)
	)
	row.add_child(del_btn)

	panel.add_child(row)
	return panel


# ═══════════════════════════════════════════════════════════════════════════════
#  CALLBACKS
# ═══════════════════════════════════════════════════════════════════════════════

func _on_character_selected(char_data: Dictionary) -> void:
	_selected_character = char_data
	_show_world_select()


func _on_world_selected(world_data: Dictionary) -> void:
	_selected_world = world_data
	_show_play_mode()


func _on_create_character() -> void:
	var new_name := _new_char_name_input.text.strip_edges()
	if new_name.is_empty():
		return
	SaveManager.create_character(new_name)
	_new_char_name_input.text = ""
	_refresh_character_list()


func _on_create_world() -> void:
	var new_name := _new_world_name_input.text.strip_edges()
	if new_name.is_empty():
		return
	var custom_seed := _new_world_seed_input.text.strip_edges() if _new_world_seed_input else ""
	if custom_seed.is_empty():
		SaveManager.create_world(new_name)
	else:
		var worlds := SaveManager.get_all_worlds()
		var world_data := {
			"id": str(Time.get_unix_time_from_system()).replace(".", "_"),
			"name": new_name,
			"seed": custom_seed,
			"created": Time.get_datetime_string_from_system(),
		}
		worlds.append(world_data)
		SaveManager.save_worlds(worlds)
	_new_world_name_input.text = ""
	if _new_world_seed_input:
		_new_world_seed_input.text = ""
	_refresh_world_list()


func _on_back_pressed() -> void:
	if _current_screen == Screen.PLAY_MODE:
		_show_world_select()
	else:
		_show_character_select()


func _on_play_offline() -> void:
	SaveManager.start_game(_selected_character, _selected_world)
	_launch_world(_selected_world)


func _on_host_steam() -> void:
	SaveManager.start_game(_selected_character, _selected_world)
	var seed_str: String = str(_selected_world.get("seed", "oathbound"))
	var w_name: String = str(_selected_world.get("name", "World"))
	NetworkManager.world_seed = seed_str
	NetworkManager.world_name = w_name
	NetworkManager.character_name = str(_selected_character.get("name", "Player"))
	if _connection_status:
		_connection_status.text = "Creating Steam lobby..."
		_connection_status.add_theme_color_override("font_color", _COOL_ACCENT)
	NetworkManager.steam_lobby_created.connect(_on_steam_host_ready, CONNECT_ONE_SHOT)
	NetworkManager.connection_failed.connect(_on_steam_host_failed, CONNECT_ONE_SHOT)
	NetworkManager.host_game_steam()


func _on_steam_host_ready(_lobby_id: int) -> void:
	if NetworkManager.connection_failed.is_connected(_on_steam_host_failed):
		NetworkManager.connection_failed.disconnect(_on_steam_host_failed)
	_launch_world(_selected_world)


func _on_steam_host_failed() -> void:
	if NetworkManager.steam_lobby_created.is_connected(_on_steam_host_ready):
		NetworkManager.steam_lobby_created.disconnect(_on_steam_host_ready)
	if _connection_status:
		_connection_status.text = "Failed to create Steam lobby."
		_connection_status.add_theme_color_override("font_color", _DANGER_ACCENT)


func _on_steam_join_requested(lobby_id: int) -> void:
	_ensure_character_for_join()
	_set_status("Joining Steam game...", _COOL_ACCENT)
	NetworkManager.character_name = str(_selected_character.get("name", "Player"))
	NetworkManager.connection_succeeded.connect(_on_join_connected, CONNECT_ONE_SHOT)
	NetworkManager.connection_failed.connect(_on_steam_join_failed, CONNECT_ONE_SHOT)
	NetworkManager.world_info_received.connect(_on_join_world_info, CONNECT_ONE_SHOT)
	NetworkManager.join_game_steam(lobby_id)


func _on_steam_join_failed() -> void:
	_set_status("Failed to join Steam game.", _DANGER_ACCENT)
	if NetworkManager.world_info_received.is_connected(_on_join_world_info):
		NetworkManager.world_info_received.disconnect(_on_join_world_info)


func _ensure_character_for_join() -> void:
	if not _selected_character.is_empty():
		return
	var chars := SaveManager.get_all_characters()
	if not chars.is_empty():
		_selected_character = chars[0]
	else:
		var steam_name := SteamManager.steam_name if SteamManager.is_steam_ready and SteamManager.steam_name != "" else "Player"
		_selected_character = SaveManager.create_character(steam_name)


func _on_host_lan() -> void:
	SaveManager.start_game(_selected_character, _selected_world)
	var seed_str: String = str(_selected_world.get("seed", "oathbound"))
	var w_name: String = str(_selected_world.get("name", "World"))
	NetworkManager.world_seed = seed_str
	NetworkManager.world_name = w_name
	NetworkManager.host_game()
	_launch_world(_selected_world)


func _on_join_lan() -> void:
	var ip := _ip_input.text.strip_edges()
	if ip.is_empty():
		ip = "127.0.0.1"
	_set_status("Connecting to %s..." % ip, _COOL_ACCENT)

	NetworkManager.connection_succeeded.connect(_on_join_connected, CONNECT_ONE_SHOT)
	NetworkManager.connection_failed.connect(_on_join_failed, CONNECT_ONE_SHOT)
	NetworkManager.world_info_received.connect(_on_join_world_info, CONNECT_ONE_SHOT)
	NetworkManager.join_game(ip)


func _on_join_connected() -> void:
	_set_status("Connected! Waiting for world info...", Color(0.4, 0.75, 0.45))


func _on_join_failed() -> void:
	_set_status("Connection failed.", _DANGER_ACCENT)
	if NetworkManager.world_info_received.is_connected(_on_join_world_info):
		NetworkManager.world_info_received.disconnect(_on_join_world_info)


func _on_join_world_info() -> void:
	if _DEBUG_LOG: print("[MENU-CLIENT] Received world info, loading world...")
	_set_status("Loading world...", _COOL_ACCENT)
	_ensure_character_for_join()
	SaveManager.start_game(_selected_character, {"id": "lan_client", "name": NetworkManager.world_name, "seed": NetworkManager.world_seed})
	var world_data := {"seed": NetworkManager.world_seed, "name": NetworkManager.world_name}
	_launch_world(world_data)
	if _DEBUG_LOG: print("[MENU-CLIENT] World loaded, notifying server we are ready")
	NetworkManager.call_deferred("notify_server_ready")


func _set_status(msg: String, color: Color) -> void:
	if _connection_status:
		_connection_status.text = msg
		_connection_status.add_theme_color_override("font_color", color)


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

	if NetworkManager.is_connected_to_game():
		var default_player := world_instance.get_node_or_null("Players/Player")
		if default_player:
			default_player.queue_free()
			if _DEBUG_LOG: print("[MENU] Removed default Player node for multiplayer")

	var loading := LoadingScreen.new()
	loading.name = "LoadingScreen"
	get_tree().root.add_child(loading)

	get_tree().root.add_child(world_instance)
	get_tree().current_scene = world_instance

	SaveManager.call_deferred("_deferred_load_save")
	queue_free()


# ═══════════════════════════════════════════════════════════════════════════════
#  UI HELPERS — Panels
# ═══════════════════════════════════════════════════════════════════════════════

func _make_outer_panel(palette: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = _WARM_OUTER_BG if palette == Palette.WARM else _COOL_OUTER_BG
	style.border_color = _WARM_OUTER_BORDER if palette == Palette.WARM else _COOL_OUTER_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(5)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_inner_panel(palette: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = _WARM_INNER_BG if palette == Palette.WARM else _COOL_INNER_BG
	style.border_color = _WARM_INNER_BORDER if palette == Palette.WARM else _COOL_INNER_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	return panel


# ═══════════════════════════════════════════════════════════════════════════════
#  UI HELPERS — Buttons
# ═══════════════════════════════════════════════════════════════════════════════

func _make_button(text: String, palette: int, primary := false, danger := false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 15)

	var accent: Color
	var hover_bg: Color
	var hover_border: Color
	var text_col: Color
	var text_hover: Color

	if danger:
		accent = _DANGER_ACCENT
		hover_bg = _DANGER_HOVER_BG
		hover_border = _DANGER_HOVER_BORDER
		text_col = Color(0.62, 0.42, 0.38) if palette == Palette.WARM else Color(0.60, 0.40, 0.38)
		text_hover = Color(0.92, 0.45, 0.35)
	elif palette == Palette.WARM:
		accent = _WARM_ACCENT
		hover_bg = _WARM_BTN_HOVER_BG
		hover_border = _WARM_BTN_HOVER_BORDER
		text_col = _WARM_TEXT_DIM if not primary else _WARM_TEXT
		text_hover = Color(1.0, 0.90, 0.55)
	else:
		accent = _COOL_ACCENT
		hover_bg = _COOL_BTN_HOVER_BG
		hover_border = _COOL_BTN_HOVER_BORDER
		text_col = _COOL_TEXT_DIM if not primary else _COOL_TEXT
		text_hover = Color(0.70, 0.85, 1.0)

	# Normal: transparent with subtle border for primary, fully transparent for others
	var normal := StyleBoxFlat.new()
	if primary:
		normal.bg_color = Color(hover_bg.r, hover_bg.g, hover_bg.b, 0.35)
		normal.border_color = Color(accent.r, accent.g, accent.b, 0.4)
		normal.set_border_width_all(1)
	else:
		normal.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		normal.border_color = Color(0.0, 0.0, 0.0, 0.0)
		normal.set_border_width_all(0)
	normal.set_corner_radius_all(6)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", normal)

	# Hover: highlighted
	var hover := StyleBoxFlat.new()
	hover.bg_color = hover_bg
	hover.border_color = hover_border
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(6)
	hover.content_margin_left = 12
	hover.content_margin_right = 12
	hover.content_margin_top = 8
	hover.content_margin_bottom = 8
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("focus", hover)

	# Pressed: slightly darker
	var pressed := hover.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(hover_bg.r * 0.8, hover_bg.g * 0.8, hover_bg.b * 0.8, 0.9)
	btn.add_theme_stylebox_override("pressed", pressed)

	btn.add_theme_color_override("font_color", text_col)
	btn.add_theme_color_override("font_hover_color", text_hover)
	btn.add_theme_color_override("font_focus_color", text_hover)
	btn.add_theme_color_override("font_pressed_color", text_hover)

	return btn


# ═══════════════════════════════════════════════════════════════════════════════
#  UI HELPERS — Decorative Elements
# ═══════════════════════════════════════════════════════════════════════════════

func _make_title_block(title: String, subtitle: String, palette: int) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 4)

	var accent := _WARM_ACCENT if palette == Palette.WARM else _COOL_ACCENT
	var text_dim := _WARM_TEXT_DIM if palette == Palette.WARM else _COOL_TEXT_DIM

	# Top flourish
	var flourish_top := Label.new()
	flourish_top.text = "\u2014\u2014\u2014  \u25c6  \u2014\u2014\u2014"
	flourish_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flourish_top.add_theme_font_size_override("font_size", 14)
	flourish_top.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.5))
	block.add_child(flourish_top)

	# Title
	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 38)
	title_label.add_theme_color_override("font_color", accent)
	block.add_child(title_label)

	# Subtitle
	var sub := Label.new()
	sub.text = subtitle
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", text_dim)
	block.add_child(sub)

	# Bottom flourish
	var flourish_bot := Label.new()
	flourish_bot.text = "\u2014\u2014\u2014  \u25c6  \u2014\u2014\u2014"
	flourish_bot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flourish_bot.add_theme_font_size_override("font_size", 14)
	flourish_bot.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.5))
	block.add_child(flourish_bot)

	return block


func _make_ornamental_separator(palette: int) -> Control:
	var container := HBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.add_theme_constant_override("separation", 0)
	container.custom_minimum_size = Vector2(0, 24)

	var accent := _WARM_ACCENT if palette == Palette.WARM else _COOL_ACCENT
	var dim := Color(accent.r, accent.g, accent.b, 0.35)

	var left_line := HSeparator.new()
	left_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_line.add_theme_constant_override("separation", 0)
	left_line.add_theme_color_override("separator", dim)
	container.add_child(left_line)

	var diamond := Label.new()
	diamond.text = "  \u25c6  "
	diamond.add_theme_font_size_override("font_size", 10)
	diamond.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.5))
	container.add_child(diamond)

	var right_line := HSeparator.new()
	right_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_line.add_theme_constant_override("separation", 0)
	right_line.add_theme_color_override("separator", dim)
	container.add_child(right_line)

	return container


func _make_section_label(text: String, palette: int) -> Label:
	var accent := _WARM_ACCENT if palette == Palette.WARM else _COOL_ACCENT
	var lbl := Label.new()
	lbl.text = "\u2014  %s  \u2014" % text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.6))
	return lbl


func _make_line_edit(placeholder: String, palette: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.add_theme_font_size_override("font_size", 15)

	var bg := _WARM_INPUT_BG if palette == Palette.WARM else _COOL_INPUT_BG
	var border := _WARM_INPUT_BORDER if palette == Palette.WARM else _COOL_INPUT_BORDER
	var text_col := _WARM_TEXT if palette == Palette.WARM else _COOL_TEXT

	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	edit.add_theme_stylebox_override("normal", style)

	var focus_style := style.duplicate() as StyleBoxFlat
	var accent := _WARM_ACCENT if palette == Palette.WARM else _COOL_ACCENT
	focus_style.border_color = Color(accent.r, accent.g, accent.b, 0.7)
	edit.add_theme_stylebox_override("focus", focus_style)

	edit.add_theme_color_override("font_color", text_col)
	edit.add_theme_color_override("font_placeholder_color", Color(text_col.r, text_col.g, text_col.b, 0.35))

	return edit


# ═══════════════════════════════════════════════════════════════════════════════
#  UI HELPERS — Delete Confirmation (double-panel)
# ═══════════════════════════════════════════════════════════════════════════════

func _show_delete_confirm(item_name: String, palette: int, on_confirm: Callable) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.55)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 50
	add_child(overlay)

	var outer := _make_outer_panel(palette)
	outer.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	outer.offset_left = -200
	outer.offset_right = 200
	outer.offset_top = -90
	outer.offset_bottom = 90

	# Override outer border to danger red
	var outer_style := StyleBoxFlat.new()
	outer_style.bg_color = _WARM_OUTER_BG if palette == Palette.WARM else _COOL_OUTER_BG
	outer_style.border_color = Color(_DANGER_ACCENT.r, _DANGER_ACCENT.g, _DANGER_ACCENT.b, 0.7)
	outer_style.set_border_width_all(2)
	outer_style.set_corner_radius_all(12)
	outer_style.set_content_margin_all(5)
	outer.add_theme_stylebox_override("panel", outer_style)

	var inner := _make_inner_panel(palette)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)

	var msg := Label.new()
	msg.text = "Delete \"%s\"?" % item_name
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.add_theme_font_size_override("font_size", 20)
	msg.add_theme_color_override("font_color", _WARM_TEXT if palette == Palette.WARM else _COOL_TEXT)
	vbox.add_child(msg)

	var hint := Label.new()
	hint.text = "This cannot be undone."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", _WARM_TEXT_DIM if palette == Palette.WARM else _COOL_TEXT_DIM)
	vbox.add_child(hint)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)

	var no_btn := _make_button("Cancel", palette)
	no_btn.custom_minimum_size = Vector2(100, 36)
	no_btn.pressed.connect(func() -> void: overlay.queue_free())
	btn_row.add_child(no_btn)

	var yes_btn := _make_button("Yes, Delete", palette, false, true)
	yes_btn.custom_minimum_size = Vector2(120, 36)
	yes_btn.pressed.connect(func() -> void:
		overlay.queue_free()
		on_confirm.call()
	)
	btn_row.add_child(yes_btn)

	vbox.add_child(btn_row)

	inner.add_child(vbox)
	outer.add_child(inner)
	overlay.add_child(outer)


# ═══════════════════════════════════════════════════════════════════════════════
#  UI HELPERS — Utility
# ═══════════════════════════════════════════════════════════════════════════════

func _clear_screen() -> void:
	if _screen_root and is_instance_valid(_screen_root):
		_screen_root.queue_free()
		_screen_root = null
	_char_list = null
	_world_list = null
	_play_mode_panel = null
	_new_char_name_input = null
	_new_world_name_input = null
	_new_world_seed_input = null
	_ip_input = null
	_connection_status = null


func _make_spacer(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _format_last_played(char_data: Dictionary) -> String:
	var parts: Array[String] = []

	var total_secs: float = float(char_data.get("time_played_seconds", 0.0))
	if total_secs >= 3600.0:
		var h := int(total_secs / 3600.0)
		var m := int(fmod(total_secs, 3600.0) / 60.0)
		parts.append("%dh %dm played" % [h, m])
	elif total_secs >= 60.0:
		parts.append("%dm played" % int(total_secs / 60.0))
	elif total_secs > 0.0:
		parts.append("<1m played")

	if not char_data.has("last_played"):
		if parts.is_empty():
			return "Never played"
	else:
		var last: float = float(char_data["last_played"])
		var now: float = Time.get_unix_time_from_system()
		var hours := int((now - last) / 3600.0)
		if hours < 1:
			parts.append("Last on: <1h ago")
		elif hours == 1:
			parts.append("Last on: 1h ago")
		elif hours < 24:
			parts.append("Last on: %dh ago" % hours)
		else:
			var days := hours / 24
			parts.append("Last on: %dd ago" % days)

	if parts.is_empty():
		return "Never played"
	return "  \u2022  ".join(parts)



