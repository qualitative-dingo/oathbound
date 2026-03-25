class_name PlayerHUD
extends Node

## HUD sub-module for PlayerController. Stores pc: PlayerController and accesses
## all controller state through pc. Autoloads (Input, GameEvents, Inventory,
## ItemDatabase, AudioManager, WaterSystem, SaveManager, WeatherSystem) are NOT prefixed.

const MINIMAP_PX := 180
const MINIMAP_RING := 5
const MINIMAP_ZOOM_MIN := 3.0
const MINIMAP_ZOOM_MAX := 20.0
const MINIMAP_ZOOM_STEP := 1.5
const MAP_PX := 512
const MAP_ZOOM_MIN := 8.0
const MAP_ZOOM_MAX := 100.0
const MAP_ZOOM_STEP := 6.0
const MAP_ZOOM_SPEED := 10.0

var pc: PlayerController


func setup_floating_bars() -> void:
	const BAR_W := 1.352
	const BAR_H := 0.1014
	const STAM_H := 0.0754
	const GAP := 0.031

	pc._bar_shader = load("res://shaders/bar_hud.gdshader") as Shader

	pc._bar_anchor = Node3D.new()
	pc._bar_anchor.name = "BarAnchor"
	pc._bar_anchor.position = Vector3(0.0, 4.2, 0.0)
	pc.add_child(pc._bar_anchor)

	pc._hp_bar = make_shader_bar(BAR_W, BAR_H,
		Color(0.5, 0.05, 0.05), Color(0.95, 0.15, 0.15))
	pc._hp_bar.position = Vector3.ZERO
	pc._bar_anchor.add_child(pc._hp_bar)

	pc._stam_bar = make_shader_bar(BAR_W, STAM_H,
		Color(0.35, 0.25, 0.05), Color(0.95, 0.75, 0.15))
	pc._stam_bar.position = Vector3(0.0, -(BAR_H * 0.5 + STAM_H * 0.5 + GAP), 0.0)
	pc._bar_anchor.add_child(pc._stam_bar)


func make_shader_bar(w: float, h: float, col_a: Color, col_b: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	mi.mesh = qm
	var mat := ShaderMaterial.new()
	mat.shader = pc._bar_shader
	mat.set_shader_parameter("fill_ratio", 1.0)
	mat.set_shader_parameter("color_a", Vector3(col_a.r, col_a.g, col_a.b))
	mat.set_shader_parameter("color_b", Vector3(col_b.r, col_b.g, col_b.b))
	mat.set_shader_parameter("pulse", 0.0)
	mat.set_shader_parameter("aspect_ratio", w / h)
	mat.set_shader_parameter("glow_intensity", 0.45)
	mat.set_shader_parameter("border_softness", 0.025)
	mi.set_surface_override_material(0, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func update_floating_bars(delta: float) -> void:
	if pc._bar_anchor:
		var cam := pc.get_viewport().get_camera_3d()
		if cam:
			var anchor_world := pc._bar_anchor.global_position
			var cam_pos := cam.global_position
			var dir := (cam_pos - anchor_world)
			dir.y = 0.0
			if dir.length_squared() > 0.001:
				dir = dir.normalized()
				pc._bar_anchor.global_transform.basis = Basis.looking_at(-dir, Vector3.UP)

	pc._hp_pulse = move_toward(pc._hp_pulse, 0.0, delta * 3.0)

	if pc._hp_bar:
		var mat: ShaderMaterial = pc._hp_bar.get_surface_override_material(0) as ShaderMaterial
		if mat:
			mat.set_shader_parameter("fill_ratio", clampf(pc.current_health / pc.max_health, 0.0, 1.0))
			mat.set_shader_parameter("pulse", pc._hp_pulse)

	if pc._stam_bar:
		var mat: ShaderMaterial = pc._stam_bar.get_surface_override_material(0) as ShaderMaterial
		if mat:
			mat.set_shader_parameter("fill_ratio", clampf(pc.current_stamina / pc.max_stamina, 0.0, 1.0))


func build_hud() -> void:
	var hud := pc.get_node_or_null("HUD") as CanvasLayer
	if not hud:
		return

	pc._hud_root = Control.new()
	pc._hud_root.name = "HUDRoot"
	pc._hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pc._hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(pc._hud_root)

	build_hotbar(pc._hud_root)
	build_map_panel(pc._hud_root)
	build_interaction_prompt(pc._hud_root)
	build_world_name_label(pc._hud_root)
	build_minimap(pc._hud_root)
	build_fps_counter(pc._hud_root)
	build_target_hud(pc._hud_root)
	build_chat_ui(pc._hud_root)
	build_player_list(pc._hud_root)
	build_pause_menu()


func build_chat_ui(root: Control) -> void:
	pc._chat_panel = PanelContainer.new()
	pc._chat_panel.name = "ChatPanel"
	pc._chat_panel.anchor_left = 0.0
	pc._chat_panel.anchor_right = 0.0
	pc._chat_panel.anchor_top = 1.0
	pc._chat_panel.anchor_bottom = 1.0
	pc._chat_panel.offset_left = 12
	pc._chat_panel.offset_right = 320
	pc._chat_panel.offset_top = -140
	pc._chat_panel.offset_bottom = -8
	pc._chat_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc._chat_panel.z_index = 85

	var chat_style := StyleBoxFlat.new()
	chat_style.bg_color = Color(0.05, 0.05, 0.08, 0.75)
	chat_style.set_corner_radius_all(4)
	chat_style.set_content_margin_all(6)
	pc._chat_panel.add_theme_stylebox_override("panel", chat_style)

	var chat_vbox := VBoxContainer.new()
	chat_vbox.add_theme_constant_override("separation", 4)
	pc._chat_panel.add_child(chat_vbox)

	pc._chat_scroll = ScrollContainer.new()
	pc._chat_scroll.custom_minimum_size = Vector2(0, 100)
	pc._chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pc._chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	chat_vbox.add_child(pc._chat_scroll)

	pc._chat_log = VBoxContainer.new()
	pc._chat_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc._chat_scroll.add_child(pc._chat_log)

	pc._chat_input = LineEdit.new()
	pc._chat_input.placeholder_text = "Press Enter to chat..."
	pc._chat_input.custom_minimum_size = Vector2(0, 28)
	pc._chat_input.max_length = 128
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.12, 0.13, 0.16, 0.9)
	input_style.set_border_width_all(1)
	input_style.border_color = Color(0.3, 0.3, 0.35)
	input_style.set_corner_radius_all(3)
	input_style.set_content_margin_all(4)
	pc._chat_input.add_theme_stylebox_override("normal", input_style)
	pc._chat_input.add_theme_font_size_override("font_size", 14)
	pc._chat_input.gui_input.connect(_on_chat_input_gui_input.bind(pc))
	pc._chat_input.focus_entered.connect(_on_chat_focus_entered.bind(pc))
	pc._chat_input.focus_exited.connect(_on_chat_focus_exited.bind(pc))
	chat_vbox.add_child(pc._chat_input)

	root.add_child(pc._chat_panel)
	pc._chat_panel.modulate.a = 0.0
	pc._chat_visible = false
	ChatManager.message_received.connect(_on_chat_message_received.bind(pc))
	_refresh_chat_log(pc)


func _show_chat(pc_ref: PlayerController) -> void:
	pc_ref._chat_panel.modulate.a = 1.0
	pc_ref._chat_visible = true
	pc_ref._chat_fade_timer = 10.0


func update_chat_fade(pc_ref: PlayerController, delta: float) -> void:
	if not pc_ref._chat_panel:
		return
	if pc_ref._chat_focused:
		pc_ref._chat_panel.modulate.a = 1.0
		pc_ref._chat_visible = true
		pc_ref._chat_fade_timer = 10.0
		return
	if pc_ref._chat_fade_timer > 0.0:
		pc_ref._chat_fade_timer -= delta
		if pc_ref._chat_fade_timer <= 0.0:
			pc_ref._chat_fade_timer = 0.0
	if not pc_ref._chat_visible:
		return
	if pc_ref._chat_fade_timer <= 0.0:
		pc_ref._chat_panel.modulate.a = maxf(pc_ref._chat_panel.modulate.a - delta * 2.0, 0.0)
		if pc_ref._chat_panel.modulate.a <= 0.0:
			pc_ref._chat_visible = false


func _scroll_chat_to_bottom(pc_ref: PlayerController) -> void:
	if pc_ref._chat_scroll:
		await pc_ref.get_tree().process_frame
		pc_ref._chat_scroll.scroll_vertical = int(pc_ref._chat_scroll.get_v_scroll_bar().max_value)


func _on_chat_input_gui_input(event: InputEvent, pc_ref: PlayerController) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed:
			if ke.keycode == KEY_ESCAPE:
				pc_ref._chat_input.release_focus()
				pc_ref._chat_focused = false
				_show_chat(pc_ref)
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				get_viewport().set_input_as_handled()
			elif ke.keycode == KEY_ENTER or ke.keycode == KEY_KP_ENTER:
				var text := pc_ref._chat_input.text
				pc_ref._chat_input.text = ""
				pc_ref._chat_input.release_focus()
				pc_ref._chat_focused = false
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				if not text.is_empty():
					var cmd := text.strip_edges().to_lower()
					if cmd == "oathsword" or cmd == "rosebud":
						ItemDatabase.spawn_god_sword()
					elif cmd == "oathgun" or cmd == "oathbow":
						ItemDatabase.spawn_god_bow()
					elif cmd == "oathaxe":
						ItemDatabase.spawn_god_axe()
					elif cmd == "oathpick" or cmd == "oathpickaxe":
						ItemDatabase.spawn_god_pickaxe()
					elif cmd == "oathmace":
						ItemDatabase.spawn_god_mace()
					elif cmd == "oathshield":
						ItemDatabase.spawn_god_shield()
					elif cmd == "oathchest" or cmd == "oathplate":
						ItemDatabase.spawn_god_chest()
					elif cmd == "oathlegs" or cmd == "oathcuisses":
						ItemDatabase.spawn_god_legs()
					elif cmd == "oathboots" or cmd == "oathstriders":
						ItemDatabase.spawn_god_boots()
					elif cmd == "oathall":
						ItemDatabase.spawn_all_oath_gear()
					elif cmd == "flight":
						pc_ref.flight_mode = not pc_ref.flight_mode
					else:
						ChatManager.send_message(text)
				_show_chat(pc_ref)
				get_viewport().set_input_as_handled()


func _on_chat_focus_entered(pc_ref: PlayerController) -> void:
	pc_ref._chat_focused = true
	_show_chat(pc_ref)


func _on_chat_focus_exited(pc_ref: PlayerController) -> void:
	pc_ref._chat_focused = false


func _on_chat_message_received(sender: String, text: String, pc_ref: PlayerController) -> void:
	_refresh_chat_log(pc_ref)
	_show_chat(pc_ref)
	_scroll_chat_to_bottom(pc_ref)


func _refresh_chat_log(pc_ref: PlayerController) -> void:
	if not pc_ref._chat_log:
		return
	for child in pc_ref._chat_log.get_children():
		child.queue_free()
	var messages := ChatManager.get_messages()
	for msg in messages:
		var lbl := Label.new()
		var is_system: bool = msg["sender"] == ""
		lbl.text = msg["text"] if is_system else "%s: %s" % [msg["sender"], msg["text"]]
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45) if is_system else Color(0.9, 0.88, 0.82))
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.custom_minimum_size = Vector2(280, 0)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc_ref._chat_log.add_child(lbl)


func build_player_list(root: Control) -> void:
	if not NetworkManager.is_connected_to_game():
		return
	pc._player_list_panel = PanelContainer.new()
	pc._player_list_panel.name = "PlayerListPanel"
	pc._player_list_panel.anchor_left = 1.0
	pc._player_list_panel.anchor_right = 1.0
	pc._player_list_panel.anchor_top = 0.0
	pc._player_list_panel.anchor_bottom = 0.0
	pc._player_list_panel.offset_left = -180
	pc._player_list_panel.offset_right = -12
	pc._player_list_panel.offset_top = 12
	pc._player_list_panel.offset_bottom = 120
	pc._player_list_panel.visible = false
	pc._player_list_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc._player_list_panel.z_index = 82

	var pl_style := StyleBoxFlat.new()
	pl_style.bg_color = Color(0.05, 0.05, 0.08, 0.8)
	pl_style.set_corner_radius_all(4)
	pl_style.set_content_margin_all(8)
	pc._player_list_panel.add_theme_stylebox_override("panel", pl_style)

	var pl_vbox := VBoxContainer.new()
	pl_vbox.name = "PlayerListVBox"
	pl_vbox.add_theme_constant_override("separation", 4)
	pc._player_list_panel.add_child(pl_vbox)

	var title := Label.new()
	title.text = "Players"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7))
	pl_vbox.add_child(title)

	root.add_child(pc._player_list_panel)
	_refresh_player_list(pc)
	NetworkManager.player_connected.connect(_on_player_list_changed.bind(pc))
	NetworkManager.player_disconnected.connect(_on_player_list_changed.bind(pc))


func _on_player_list_changed(_peer_id: int, pc_ref: PlayerController) -> void:
	_refresh_player_list(pc_ref)


func _refresh_player_list(pc_ref: PlayerController) -> void:
	if not pc_ref._player_list_panel:
		return
	var vbox := pc_ref._player_list_panel.get_node_or_null("PlayerListVBox") as VBoxContainer
	if not vbox:
		return
	# Remove all children except title (index 0)
	while vbox.get_child_count() > 1:
		vbox.get_child(1).queue_free()
	var players_node := pc_ref.get_tree().current_scene.get_node_or_null("Players")
	if not players_node:
		return
	for child in players_node.get_children():
		var player := child as PlayerController
		if not player:
			continue
		var name_str := player.character_display_name if player.character_display_name != "" else "Player %s" % child.name
		var lbl := Label.new()
		lbl.text = "- %s" % name_str
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", Color(0.9, 0.88, 0.82))
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(lbl)


func build_pause_menu() -> void:
	pc._pause_overlay = CanvasLayer.new()
	pc._pause_overlay.name = "PauseOverlay"
	pc._pause_overlay.layer = 100
	pc._pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pc._pause_overlay.visible = false
	pc.add_child(pc._pause_overlay)

	var input_catcher := Control.new()
	input_catcher.name = "PauseInputCatcher"
	input_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input_catcher.process_mode = Node.PROCESS_MODE_ALWAYS
	input_catcher.focus_mode = Control.FOCUS_ALL
	input_catcher.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed(&"quit_game") and pc._pause_open:
			close_pause_menu()
			input_catcher.get_viewport().set_input_as_handled()
	)
	pc._pause_overlay.add_child(input_catcher)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_catcher.add_child(bg)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.offset_left = -220
	center.offset_right = 220
	center.offset_top = -220
	center.offset_bottom = 220
	center.add_theme_constant_override("separation", 0)
	pc._pause_overlay.add_child(center)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	panel_style.border_color = Color(0.3, 0.28, 0.22)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	vbox.add_child(title)

	var music_idx := AudioServer.get_bus_index(&"Music")
	var music_db := AudioServer.get_bus_volume_db(music_idx) if music_idx != -1 else linear_to_db(0.7)
	var music_pct := db_to_linear(music_db)
	add_volume_slider(vbox, "Music Volume", music_pct, func(val: float) -> void:
		var idx := AudioServer.get_bus_index(&"Music")
		if idx != -1:
			AudioServer.set_bus_volume_db(idx, linear_to_db(val))
	)

	var sfx_idx := AudioServer.get_bus_index(&"SFX")
	var sfx_db := AudioServer.get_bus_volume_db(sfx_idx) if sfx_idx != -1 else linear_to_db(0.7)
	var sfx_pct := db_to_linear(sfx_db)
	add_volume_slider(vbox, "SFX Volume", sfx_pct, func(val: float) -> void:
		var idx := AudioServer.get_bus_index(&"SFX")
		if idx != -1:
			AudioServer.set_bus_volume_db(idx, linear_to_db(val))
	)

	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 10)
	res_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var res_label := Label.new()
	res_label.text = "Resolution"
	res_label.add_theme_font_size_override("font_size", 14)
	res_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.45))
	res_row.add_child(res_label)
	var res_options := OptionButton.new()
	res_options.add_theme_font_size_override("font_size", 14)
	var resolutions := [
		Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
		Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
	]
	var current_size := DisplayServer.window_get_size()
	var selected_idx := -1
	for i in resolutions.size():
		var r: Vector2i = resolutions[i]
		res_options.add_item("%d x %d" % [r.x, r.y], i)
		if r == current_size:
			selected_idx = i
	if selected_idx >= 0:
		res_options.selected = selected_idx
	res_options.item_selected.connect(func(idx: int) -> void:
		var r: Vector2i = resolutions[idx]
		DisplayServer.window_set_size(r)
		var screen_size := DisplayServer.screen_get_size()
		DisplayServer.window_set_position(Vector2i(
			(screen_size.x - r.x) / 2, (screen_size.y - r.y) / 2
		))
	)
	res_row.add_child(res_options)
	vbox.add_child(res_row)

	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 10)
	fs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var fs_check := CheckBox.new()
	fs_check.text = "Fullscreen"
	fs_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs_check.add_theme_font_size_override("font_size", 14)
	fs_check.add_theme_color_override("font_color", Color(0.75, 0.65, 0.45))
	fs_check.toggled.connect(func(on: bool) -> void:
		if on:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	)
	fs_row.add_child(fs_check)
	vbox.add_child(fs_row)

	var dev_row := HBoxContainer.new()
	dev_row.add_theme_constant_override("separation", 10)
	dev_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var dev_check := CheckBox.new()
	dev_check.text = "Dev Mode (free build & craft)"
	dev_check.button_pressed = Inventory.dev_mode
	dev_check.add_theme_font_size_override("font_size", 14)
	dev_check.add_theme_color_override("font_color", Color(0.75, 0.65, 0.45))
	dev_check.toggled.connect(func(on: bool) -> void:
		Inventory.dev_mode = on
	)
	dev_row.add_child(dev_check)
	vbox.add_child(dev_row)

	var fly_row := HBoxContainer.new()
	fly_row.add_theme_constant_override("separation", 10)
	fly_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var fly_check := CheckBox.new()
	fly_check.text = "Flight Mode (noclip debug cam)"
	fly_check.button_pressed = pc.flight_mode
	fly_check.add_theme_font_size_override("font_size", 14)
	fly_check.add_theme_color_override("font_color", Color(0.45, 0.65, 0.75))
	fly_check.toggled.connect(func(on: bool) -> void:
		pc.flight_mode = on
	)
	fly_row.add_child(fly_check)
	vbox.add_child(fly_row)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	var resume_btn := make_pause_button("Resume", Color(0.2, 0.45, 0.3))
	resume_btn.pressed.connect(close_pause_menu)
	vbox.add_child(resume_btn)

	var char_btn := make_pause_button("Exit to Character Screen", Color(0.5, 0.35, 0.2))
	char_btn.pressed.connect(func() -> void:
		close_pause_menu()
		# 5d: Host saves then disconnects all; client just disconnects
		SaveManager.stop_game()
		if NetworkManager.is_connected_to_game():
			NetworkManager.disconnect_game()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		pc.get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	)
	vbox.add_child(char_btn)

	var quit_btn := make_pause_button("Exit Game", Color(0.5, 0.15, 0.15))
	quit_btn.pressed.connect(func() -> void:
		SaveManager.stop_game()
		if NetworkManager.is_connected_to_game():
			NetworkManager.disconnect_game()
		pc.get_tree().quit()
	)
	vbox.add_child(quit_btn)


func add_volume_slider(parent: VBoxContainer, label_text: String, initial: float, on_change: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.custom_minimum_size = Vector2(0, 24)

	var slider_style := StyleBoxFlat.new()
	slider_style.bg_color = Color(0.18, 0.18, 0.22)
	slider_style.set_corner_radius_all(4)
	slider_style.content_margin_top = 8
	slider_style.content_margin_bottom = 8
	slider.add_theme_stylebox_override("slider", slider_style)

	var grabber_style := StyleBoxFlat.new()
	grabber_style.bg_color = Color(0.85, 0.75, 0.55)
	grabber_style.set_corner_radius_all(4)

	slider.value_changed.connect(func(val: float) -> void: on_change.call(val))
	row.add_child(slider)
	parent.add_child(row)


func make_pause_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 16)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn


func open_pause_menu() -> void:
	pc._pause_open = true
	pc._pause_overlay.visible = true
	if not NetworkManager.is_connected_to_game():
		pc.get_tree().paused = true
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var catcher := pc._pause_overlay.get_node_or_null("PauseInputCatcher") as Control
	if catcher:
		catcher.grab_focus()


func close_pause_menu() -> void:
	pc._pause_open = false
	pc._pause_overlay.visible = false
	if not NetworkManager.is_connected_to_game():
		pc.get_tree().paused = false
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func build_fps_counter(root: Control) -> void:
	pc._fps_label = Label.new()
	pc._fps_label.name = "FPSLabel"
	pc._fps_label.add_theme_font_size_override("font_size", 14)
	pc._fps_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	pc._fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	pc._fps_label.add_theme_constant_override("shadow_offset_x", 1)
	pc._fps_label.add_theme_constant_override("shadow_offset_y", 1)
	pc._fps_label.position = Vector2(10, 10)
	pc._fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc._fps_label.z_index = 100
	root.add_child(pc._fps_label)


func build_target_hud(root: Control) -> void:
	pc._target_hud_panel = PanelContainer.new()
	pc._target_hud_panel.name = "TargetHUD"
	pc._target_hud_panel.visible = false
	pc._target_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc._target_hud_panel.z_index = 90

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.35, 0.25, 0.6)
	pc._target_hud_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	pc._target_hud_panel.add_child(vbox)

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(name_row)

	pc._target_hud_name = Label.new()
	pc._target_hud_name.add_theme_font_size_override("font_size", 22)
	pc._target_hud_name.add_theme_color_override("font_color", Color.WHITE)
	pc._target_hud_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	pc._target_hud_name.add_theme_constant_override("shadow_offset_x", 1)
	pc._target_hud_name.add_theme_constant_override("shadow_offset_y", 1)
	pc._target_hud_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(pc._target_hud_name)

	pc._target_hud_stars = Label.new()
	pc._target_hud_stars.add_theme_font_size_override("font_size", 22)
	pc._target_hud_stars.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	pc._target_hud_stars.add_theme_constant_override("shadow_offset_x", 1)
	pc._target_hud_stars.add_theme_constant_override("shadow_offset_y", 1)
	pc._target_hud_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(pc._target_hud_stars)

	var bar_bg := ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(330, 20)
	bar_bg.color = Color(0.15, 0.15, 0.15, 0.9)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bar_bg)
	pc._target_hud_hp_bar = bar_bg

	pc._target_hud_hp_fill = ColorRect.new()
	pc._target_hud_hp_fill.color = Color(0.8, 0.15, 0.15, 1.0)
	pc._target_hud_hp_fill.position = Vector2.ZERO
	pc._target_hud_hp_fill.size = Vector2(330, 20)
	pc._target_hud_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(pc._target_hud_hp_fill)

	pc._target_hud_hp_label = Label.new()
	pc._target_hud_hp_label.add_theme_font_size_override("font_size", 14)
	pc._target_hud_hp_label.add_theme_color_override("font_color", Color.WHITE)
	pc._target_hud_hp_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	pc._target_hud_hp_label.add_theme_constant_override("shadow_offset_x", 1)
	pc._target_hud_hp_label.add_theme_constant_override("shadow_offset_y", 1)
	pc._target_hud_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc._target_hud_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc._target_hud_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_bg.add_child(pc._target_hud_hp_label)

	root.add_child(pc._target_hud_panel)


func update_target_hud(delta: float) -> void:
	if not pc._target_hud_panel:
		return

	var cam: Camera3D = pc._spring_arm.get_child(0) if pc._spring_arm and pc._spring_arm.get_child_count() > 0 else null
	if cam and cam.is_inside_tree() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var ray_origin := cam.global_position
		var ray_dir := -cam.global_transform.basis.z
		var ray_end := ray_origin + ray_dir * 200.0
		var space := pc.get_world_3d().direct_space_state
		if space:
			var q := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 0xFFFFFFFF)
			q.exclude = [pc.get_rid()]
			q.collide_with_bodies = true
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var obj := hit["collider"] as Node3D
				var creature: Node3D = null
				if obj and obj.is_in_group(&"enemies"):
					creature = obj
				elif obj and obj.get_parent() and obj.get_parent().is_in_group(&"enemies"):
					creature = obj.get_parent()
				if creature and creature.has_method("take_damage"):
					set_target_creature(creature)

	if pc._target_hud_timer > 0.0:
		pc._target_hud_timer -= delta
		if pc._target_hud_timer <= 0.0:
			pc._target_creature = null
			pc._target_hud_panel.visible = false
			return

	if pc._target_creature and is_instance_valid(pc._target_creature):
		pc._target_hud_panel.visible = true
		var hp: float = pc._target_creature.get("current_health") if pc._target_creature.get("current_health") != null else 0.0
		var max_hp: float = pc._target_creature.get("max_health") if pc._target_creature.get("max_health") != null else 1.0
		var pct := clampf(hp / maxf(max_hp, 0.01), 0.0, 1.0)
		pc._target_hud_hp_fill.size.x = 330.0 * pct
		if pct > 0.5:
			pc._target_hud_hp_fill.color = Color(0.2, 0.75, 0.2, 1.0)
		elif pct > 0.25:
			pc._target_hud_hp_fill.color = Color(0.85, 0.7, 0.1, 1.0)
		else:
			pc._target_hud_hp_fill.color = Color(0.8, 0.15, 0.15, 1.0)
		pc._target_hud_hp_label.text = "%d / %d" % [ceili(hp), ceili(max_hp)]

		pc._target_hud_panel.reset_size()
		var vp_w := pc.get_viewport().get_visible_rect().size.x
		pc._target_hud_panel.position = Vector2((vp_w - pc._target_hud_panel.size.x) * 0.5, 50)
	elif pc._target_creature and not is_instance_valid(pc._target_creature):
		pc._target_creature = null
		pc._target_hud_panel.visible = false


func set_target_creature(creature: Node3D) -> void:
	if creature == pc._target_creature and pc._target_hud_timer > 0.0:
		pc._target_hud_timer = 5.0
		return
	pc._target_creature = creature
	pc._target_hud_timer = 5.0

	var dname: String = creature.get("display_name") if creature.get("display_name") != null else "Unknown"
	var stars: int = creature.get("star_level") if creature.get("star_level") != null else 0
	pc._target_hud_name.text = dname
	if stars > 0:
		var star_str := " "
		for i in stars:
			star_str += "*"
		pc._target_hud_stars.text = star_str
		pc._target_hud_stars.add_theme_color_override("font_color", ItemDatabase.get_rarity_color(stars))
		pc._target_hud_stars.visible = true
	else:
		pc._target_hud_stars.text = ""
		pc._target_hud_stars.visible = false


func build_world_name_label(root: Control) -> void:
	pc._world_name_label = Label.new()
	pc._world_name_label.name = "WorldNameLabel"
	pc._world_name_label.visible = false
	pc._world_name_label.add_theme_font_size_override("font_size", 16)
	pc._world_name_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	pc._world_name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	pc._world_name_label.add_theme_constant_override("shadow_offset_x", 1)
	pc._world_name_label.add_theme_constant_override("shadow_offset_y", 1)
	pc._world_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc._world_name_label.z_index = 80
	root.add_child(pc._world_name_label)


func minimap_do_zoom(delta_zoom: float) -> void:
	pc._minimap_zoom = clampf(pc._minimap_zoom + delta_zoom, MINIMAP_ZOOM_MIN, MINIMAP_ZOOM_MAX)
	pc._minimap_needs_refresh = true
	refresh_minimap()


func build_minimap(root: Control) -> void:
	var map_margin := 8
	var circle_d := MINIMAP_PX
	var frame_extra := 28
	var total_w := circle_d + frame_extra * 2
	var banner_h := 26
	var banner_y := 0
	var circle_x := frame_extra
	var circle_y := banner_h + 4
	var bottom_y := circle_y + circle_d

	var outer := Control.new()
	outer.name = "MinimapOuter"
	outer.anchor_left = 1.0
	outer.anchor_right = 1.0
	outer.anchor_top = 0.0
	outer.anchor_bottom = 0.0
	outer.offset_left = -(total_w + map_margin)
	outer.offset_right = -map_margin
	outer.offset_top = map_margin
	outer.offset_bottom = float(bottom_y + 36)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(outer)

	# ── Biome name banner (grey translucent box, like WoW's "Mulgore") ──
	var banner := PanelContainer.new()
	banner.name = "BiomeBanner"
	var bstyle := StyleBoxFlat.new()
	bstyle.bg_color = Color(0.15, 0.15, 0.17, 0.80)
	bstyle.set_border_width_all(2)
	bstyle.border_color = Color(0.42, 0.38, 0.28, 0.9)
	bstyle.set_corner_radius_all(4)
	bstyle.set_content_margin_all(2)
	bstyle.content_margin_left = 12
	bstyle.content_margin_right = 12
	banner.add_theme_stylebox_override("panel", bstyle)
	banner.position = Vector2(8, banner_y)
	banner.size = Vector2(total_w - 16, banner_h)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(banner)

	pc._minimap_biome_label = Label.new()
	pc._minimap_biome_label.name = "BiomeLabel"
	pc._minimap_biome_label.text = ""
	pc._minimap_biome_label.add_theme_font_size_override("font_size", 15)
	pc._minimap_biome_label.add_theme_color_override("font_color", Color(0.92, 0.84, 0.52))
	pc._minimap_biome_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	pc._minimap_biome_label.add_theme_constant_override("shadow_offset_x", 1)
	pc._minimap_biome_label.add_theme_constant_override("shadow_offset_y", 1)
	pc._minimap_biome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc._minimap_biome_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc._minimap_biome_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc._minimap_biome_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pc._minimap_biome_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(pc._minimap_biome_label)

	# ── Map circle area (the circular texture) ──
	var map_clip := Control.new()
	map_clip.name = "MapClip"
	map_clip.position = Vector2(circle_x, circle_y)
	map_clip.custom_minimum_size = Vector2(circle_d, circle_d)
	map_clip.size = Vector2(circle_d, circle_d)
	map_clip.clip_contents = true
	map_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(map_clip)

	pc._minimap_tex_rect = TextureRect.new()
	pc._minimap_tex_rect.custom_minimum_size = Vector2(circle_d, circle_d)
	pc._minimap_tex_rect.size = Vector2(circle_d, circle_d)
	pc._minimap_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pc._minimap_tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	pc._minimap_tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pc._minimap_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_clip.add_child(pc._minimap_tex_rect)

	# ── "N" compass indicator at top of circle ──
	var north_lbl := Label.new()
	north_lbl.text = "N"
	north_lbl.add_theme_font_size_override("font_size", 13)
	north_lbl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	north_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	north_lbl.add_theme_constant_override("shadow_offset_x", 1)
	north_lbl.add_theme_constant_override("shadow_offset_y", 1)
	north_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	north_lbl.position = Vector2(circle_d / 2 - 6, MINIMAP_RING + 1)
	north_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	north_lbl.z_index = 6
	map_clip.add_child(north_lbl)

	# ── Icons placed on the circle ring edge ──
	var half_d := float(circle_d) / 2.0
	var ring_r := half_d - 1.0

	# Weather icon — top-right (about 1:30 on a clock, ~60° from top)
	var weather_angle := -PI * 0.28
	var wx := circle_x + half_d + ring_r * sin(weather_angle) - 14.0
	var wy := circle_y + half_d - ring_r * cos(weather_angle) - 14.0
	var weather_frame := make_minimap_icon_frame(28)
	weather_frame.position = Vector2(wx, wy)
	outer.add_child(weather_frame)

	pc._minimap_weather_label = Label.new()
	pc._minimap_weather_label.name = "WeatherIcon"
	pc._minimap_weather_label.text = "*"
	pc._minimap_weather_label.add_theme_font_size_override("font_size", 16)
	pc._minimap_weather_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	pc._minimap_weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc._minimap_weather_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc._minimap_weather_label.position = Vector2(2, 2)
	pc._minimap_weather_label.size = Vector2(24, 24)
	pc._minimap_weather_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weather_frame.add_child(pc._minimap_weather_label)

	# Zoom + button — bottom-right (about 4 o'clock, ~120° from top)
	var zp_angle := PI * 0.35
	var zp_x := circle_x + half_d + ring_r * sin(zp_angle) - 13.0
	var zp_y := circle_y + half_d - ring_r * cos(zp_angle) - 13.0
	var zoom_in_frame := make_minimap_icon_frame(26)
	zoom_in_frame.position = Vector2(zp_x, zp_y)
	outer.add_child(zoom_in_frame)

	var zoom_in_btn := Button.new()
	zoom_in_btn.text = "+"
	zoom_in_btn.position = Vector2.ZERO
	zoom_in_btn.size = Vector2(26, 26)
	zoom_in_btn.custom_minimum_size = Vector2(26, 26)
	zoom_in_btn.add_theme_font_size_override("font_size", 16)
	zoom_in_btn.flat = true
	zoom_in_btn.add_theme_color_override("font_color", Color(0.9, 0.82, 0.45))
	zoom_in_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	zoom_in_btn.z_index = 10
	zoom_in_btn.pressed.connect(func() -> void: minimap_do_zoom(-MINIMAP_ZOOM_STEP))
	zoom_in_frame.add_child(zoom_in_btn)

	# Zoom - button — below + (about 5 o'clock, ~150° from top)
	var zm_angle := PI * 0.45
	var zm_x := circle_x + half_d + ring_r * sin(zm_angle) - 13.0
	var zm_y := circle_y + half_d - ring_r * cos(zm_angle) - 13.0
	var zoom_out_frame := make_minimap_icon_frame(26)
	zoom_out_frame.position = Vector2(zm_x, zm_y)
	outer.add_child(zoom_out_frame)

	var zoom_out_btn := Button.new()
	zoom_out_btn.text = "-"
	zoom_out_btn.position = Vector2.ZERO
	zoom_out_btn.size = Vector2(26, 26)
	zoom_out_btn.custom_minimum_size = Vector2(26, 26)
	zoom_out_btn.add_theme_font_size_override("font_size", 16)
	zoom_out_btn.flat = true
	zoom_out_btn.add_theme_color_override("font_color", Color(0.9, 0.82, 0.45))
	zoom_out_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	zoom_out_btn.z_index = 10
	zoom_out_btn.pressed.connect(func() -> void: minimap_do_zoom(MINIMAP_ZOOM_STEP))
	zoom_out_frame.add_child(zoom_out_btn)

	# ── Time label (bottom center, in a small dark banner) ──
	var time_banner := PanelContainer.new()
	time_banner.name = "TimeBanner"
	var tstyle := StyleBoxFlat.new()
	tstyle.bg_color = Color(0.10, 0.10, 0.12, 0.85)
	tstyle.set_border_width_all(1)
	tstyle.border_color = Color(0.42, 0.38, 0.28, 0.8)
	tstyle.set_corner_radius_all(3)
	tstyle.set_content_margin_all(1)
	tstyle.content_margin_left = 8
	tstyle.content_margin_right = 8
	time_banner.add_theme_stylebox_override("panel", tstyle)
	time_banner.position = Vector2(circle_x + circle_d / 2 - 28, float(bottom_y) + 2.0)
	time_banner.size = Vector2(56, 20)
	time_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(time_banner)

	pc._minimap_time_label = Label.new()
	pc._minimap_time_label.name = "TimeLabel"
	pc._minimap_time_label.text = "12:00"
	pc._minimap_time_label.add_theme_font_size_override("font_size", 12)
	pc._minimap_time_label.add_theme_color_override("font_color", Color(0.85, 0.80, 0.65))
	pc._minimap_time_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	pc._minimap_time_label.add_theme_constant_override("shadow_offset_x", 1)
	pc._minimap_time_label.add_theme_constant_override("shadow_offset_y", 1)
	pc._minimap_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc._minimap_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc._minimap_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc._minimap_time_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pc._minimap_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_banner.add_child(pc._minimap_time_label)

	# ── Pre-compute circular mask (ring = gold, inside = white, outside = transparent) ──
	pc._minimap_image = Image.create(MINIMAP_PX, MINIMAP_PX, false, Image.FORMAT_RGBA8)
	pc._minimap_image_tex = ImageTexture.new()
	pc._minimap_circle_mask = Image.create(MINIMAP_PX, MINIMAP_PX, false, Image.FORMAT_RGBA8)
	var half := float(MINIMAP_PX) * 0.5
	var ring_outer := half
	var ring_inner := half - float(MINIMAP_RING)
	for y in MINIMAP_PX:
		for x in MINIMAP_PX:
			var dx := float(x) - half
			var dy := float(y) - half
			var dist := sqrt(dx * dx + dy * dy)
			if dist > ring_outer:
				pc._minimap_circle_mask.set_pixel(x, y, Color(0, 0, 0, 0))
			elif dist > ring_inner:
				var t := (dist - ring_inner) / float(MINIMAP_RING)
				var edge_fade := 1.0 - t
				var highlight := 0.5 + 0.2 * (1.0 - t)
				var inner_glow := lerpf(0.7, 0.35, t)
				pc._minimap_circle_mask.set_pixel(x, y, Color(
					inner_glow * highlight,
					inner_glow * highlight * 0.78,
					inner_glow * highlight * 0.32,
					clampf(edge_fade + 0.5, 0.0, 1.0)))
			else:
				pc._minimap_circle_mask.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))


func make_minimap_icon_frame(sz: int) -> PanelContainer:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.10, 0.85)
	style.set_border_width_all(2)
	style.border_color = Color(0.50, 0.43, 0.28, 0.95)
	style.set_corner_radius_all(sz / 2)
	style.set_content_margin_all(0)
	frame.add_theme_stylebox_override("panel", style)
	frame.custom_minimum_size = Vector2(sz, sz)
	frame.size = Vector2(sz, sz)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.z_index = 8
	return frame


func draw_arrow_on_image(img: Image, half_px: int, scale: float = 1.0) -> void:
	var cam := pc.get_viewport().get_camera_3d()
	var facing := 0.0
	if cam:
		var fwd := -cam.global_transform.basis.z
		facing = atan2(fwd.x, -fwd.z)

	var arrow_col := Color(1.0, 0.3, 0.2)
	var outline_col := Color(0.15, 0.05, 0.02)
	var center_col := Color(1.0, 1.0, 1.0)
	var img_sz := img.get_width()

	var verts: Array[Vector2] = [
		Vector2(0.0, -5.0) * scale,
		Vector2(-3.0, 4.0) * scale,
		Vector2(0.0, 1.5) * scale,
		Vector2(3.0, 4.0) * scale,
	]
	var cos_a := cos(facing)
	var sin_a := sin(facing)
	var reach := int(7.0 * scale) + 1

	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var px_x := half_px + dx
			var px_y := half_px + dy
			if px_x < 0 or px_x >= img_sz or px_y < 0 or px_y >= img_sz:
				continue
			var pt := Vector2(
				float(dx) * cos_a + float(dy) * sin_a,
				-float(dx) * sin_a + float(dy) * cos_a)
			if point_in_arrow(pt, verts, 1.2):
				img.set_pixel(px_x, px_y, outline_col)

	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var px_x := half_px + dx
			var px_y := half_px + dy
			if px_x < 0 or px_x >= img_sz or px_y < 0 or px_y >= img_sz:
				continue
			var pt := Vector2(
				float(dx) * cos_a + float(dy) * sin_a,
				-float(dx) * sin_a + float(dy) * cos_a)
			if point_in_arrow(pt, verts, 1.0):
				img.set_pixel(px_x, px_y, arrow_col)

	if half_px >= 0 and half_px < img_sz:
		img.set_pixel(half_px, half_px, center_col)


func refresh_minimap() -> void:
	if not pc._minimap_image or not pc._minimap_tex_rect:
		return
	var wg := find_world_generator()
	if not wg:
		return

	pc._minimap_needs_refresh = false

	var player_pos := wg.get_world_position(pc)
	var half_px := MINIMAP_PX / 2
	var zone_size: float = wg.ZONE_SIZE
	var water_col := Color(0.12, 0.28, 0.52)
	var water_shallow := Color(0.18, 0.38, 0.55)
	var transparent := Color(0, 0, 0, 0)

	# World meters covered from center to edge of minimap
	var world_radius := pc._minimap_zoom * zone_size
	var meters_per_pixel := world_radius / float(half_px)

	pc._minimap_image.fill(transparent)

	var stride := 5
	var biome_cache: Dictionary = {}

	for py in range(0, MINIMAP_PX, stride):
		for px in range(0, MINIMAP_PX, stride):
			var mask_px := pc._minimap_circle_mask.get_pixel(px, py)
			if mask_px.a < 0.01:
				continue

			var is_ring := mask_px.r < 0.95 or mask_px.g < 0.95 or mask_px.b < 0.95
			if is_ring and mask_px.r < 0.9:
				var ring_col := Color(mask_px.r, mask_px.g, mask_px.b, mask_px.a)
				for sy in stride:
					for sx in stride:
						if px + sx < MINIMAP_PX and py + sy < MINIMAP_PX:
							pc._minimap_image.set_pixel(px + sx, py + sy, ring_col)
				continue

			var world_x := player_pos.x + float(px - half_px) * meters_per_pixel
			var world_z := player_pos.z + float(py - half_px) * meters_per_pixel
			var zone_coord := Vector2i(
				floori(world_x / zone_size),
				floori(world_z / zone_size))

			var h := wg.get_height_at(world_x, world_z)
			var col: Color
			if h < wg.WATER_LEVEL:
				var depth := clampf((wg.WATER_LEVEL - h) / 6.0, 0.0, 1.0)
				col = water_shallow.lerp(water_col, depth)
			else:
				if biome_cache.has(zone_coord):
					col = biome_cache[zone_coord] as Color
				else:
					var biome: StringName = wg._determine_biome(zone_coord)
					var micro := wg.get_microbiome_at_zone(zone_coord)
					col = biome_map_color(biome, micro)
					biome_cache[zone_coord] = col
				var bright := clampf(lerpf(0.7, 1.25, (h + 5.0) / 30.0), 0.0, 1.0)
				col = Color(
					clampf(col.r * bright, 0.0, 1.0),
					clampf(col.g * bright, 0.0, 1.0),
					clampf(col.b * bright, 0.0, 1.0))

			for sy in stride:
				for sx in stride:
					if px + sx < MINIMAP_PX and py + sy < MINIMAP_PX:
						pc._minimap_image.set_pixel(px + sx, py + sy, col)

	# ── Directional arrow at center ──
	draw_arrow_on_image(pc._minimap_image, MINIMAP_PX / 2, 2.6)

	pc._minimap_image_tex = ImageTexture.create_from_image(pc._minimap_image)
	pc._minimap_tex_rect.texture = pc._minimap_image_tex

	if pc._minimap_biome_label:
		var current_biome: StringName = wg.get_biome_at(player_pos)
		pc._minimap_biome_label.text = biome_display_name(current_biome)
	if pc._minimap_weather_label:
		pc._minimap_weather_label.text = WeatherSystem.get_weather_emoji()
	if pc._minimap_time_label:
		var dict := Time.get_time_dict_from_system()
		pc._minimap_time_label.text = "%02d:%02d" % [dict["hour"], dict["minute"]]


func build_hotbar(root: Control) -> void:
	var bar := HBoxContainer.new()
	bar.name = "Hotbar"
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 4)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -270
	bar.offset_right = 270
	bar.offset_top = -68
	bar.offset_bottom = -4
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)

	for i in range(8):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(60, 60)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.mouse_entered.connect(pc._on_hotbar_hover.bind(i))
		slot.mouse_exited.connect(pc._hide_tooltip)

		var stack := Control.new()
		stack.custom_minimum_size = Vector2(56, 56)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var icon_rect := TextureRect.new()
		icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(icon_rect)

		var num := Label.new()
		num.text = str(i + 1)
		num.add_theme_font_size_override("font_size", 9)
		num.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 0.6))
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		num.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		num.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(num)

		var qty_label := Label.new()
		qty_label.add_theme_font_size_override("font_size", 12)
		qty_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
		qty_label.add_theme_constant_override("outline_size", 3)
		qty_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		qty_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		qty_label.text = ""
		stack.add_child(qty_label)

		slot.add_child(stack)
		bar.add_child(slot)
		pc._hotbar_slots.append(slot)
		pc._hotbar_labels.append(num)
		pc._hotbar_icons.append(icon_rect)
		pc._hotbar_qty_labels.append(qty_label)

	pc._update_hotbar_selection()


func build_map_panel(root: Control) -> void:
	pc._map_panel = PanelContainer.new()
	pc._map_panel.name = "MapPanel"
	pc._map_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.02, 0.04, 0.94)
	pc._map_panel.add_theme_stylebox_override("panel", bg)
	pc._map_panel.visible = false
	pc._map_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "WORLD MAP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	pc._map_biome_label = Label.new()
	pc._map_biome_label.name = "BiomeLabel"
	pc._map_biome_label.text = ""
	pc._map_biome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc._map_biome_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.6))
	pc._map_biome_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(pc._map_biome_label)

	var map_container := Control.new()
	map_container.name = "MapContainer"
	map_container.custom_minimum_size = Vector2(MAP_PX, MAP_PX)

	pc._map_texture_rect = TextureRect.new()
	pc._map_texture_rect.name = "MapTexture"
	pc._map_texture_rect.custom_minimum_size = Vector2(MAP_PX, MAP_PX)
	pc._map_texture_rect.size = Vector2(MAP_PX, MAP_PX)
	pc._map_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pc._map_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	pc._map_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pc._map_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_container.add_child(pc._map_texture_rect)

	add_compass_label(map_container, "N", Vector2(MAP_PX * 0.5 - 4, 10), Color(0.95, 0.85, 0.5))
	add_compass_label(map_container, "S", Vector2(MAP_PX * 0.5 - 3, MAP_PX - 26), Color(0.6, 0.55, 0.45))
	add_compass_label(map_container, "E", Vector2(MAP_PX - 22, MAP_PX * 0.5 - 8), Color(0.6, 0.55, 0.45))
	add_compass_label(map_container, "W", Vector2(10, MAP_PX * 0.5 - 8), Color(0.6, 0.55, 0.45))

	vbox.add_child(map_container)

	var hint := Label.new()
	hint.text = "Scroll to zoom  |  [M] Close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.4, 0.38, 0.32))
	hint.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hint)

	center.add_child(vbox)
	pc._map_panel.add_child(center)
	root.add_child(pc._map_panel)

	pc._map_image = Image.create(MAP_PX, MAP_PX, false, Image.FORMAT_RGBA8)
	pc._map_image_tex = ImageTexture.new()
	build_circle_mask()

	pc._map_fog_noise = FastNoiseLite.new()
	pc._map_fog_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	pc._map_fog_noise.frequency = 0.015
	pc._map_fog_noise.fractal_octaves = 3


func add_compass_label(parent: Control, text: String, pos: Vector2, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)


func build_circle_mask() -> void:
	pc._map_circle_mask = Image.create(MAP_PX, MAP_PX, false, Image.FORMAT_RGBA8)
	var half := float(MAP_PX) * 0.5
	var radius := half - 6.0
	var edge_width := 14.0
	var ring_outer := radius + 3.0
	var ring_inner := radius - 2.0
	for y in range(MAP_PX):
		for x in range(MAP_PX):
			var dx := float(x) - half
			var dy := float(y) - half
			var dist := sqrt(dx * dx + dy * dy)
			if dist > ring_outer:
				pc._map_circle_mask.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
			elif dist > radius:
				# Ornamental ring border
				var ring_t := 1.0 - (dist - radius) / (ring_outer - radius)
				var angle := atan2(dy, dx)
				var notch := absf(sin(angle * 32.0))
				var brightness := lerpf(0.25, 0.45, notch) * ring_t
				pc._map_circle_mask.set_pixel(x, y, Color(brightness, brightness * 0.9, brightness * 0.7, 1.0))
			elif dist > ring_inner:
				# Inner ring edge
				pc._map_circle_mask.set_pixel(x, y, Color(0.3, 0.27, 0.2, 1.0))
			elif dist > ring_inner - edge_width:
				var t := (dist - (ring_inner - edge_width)) / edge_width
				pc._map_circle_mask.set_pixel(x, y, Color(1.0, 1.0, 1.0, t * 0.15 + 0.85))
			else:
				pc._map_circle_mask.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))


func refresh_map() -> void:
	if not pc._map_panel or not pc._map_image or not pc._map_texture_rect:
		return

	var transparent := Color(0, 0, 0, 0)
	pc._map_image.fill(transparent)

	var wg := find_world_generator()
	if not wg:
		pc._map_image_tex = ImageTexture.create_from_image(pc._map_image)
		pc._map_texture_rect.texture = pc._map_image_tex
		return

	var player_pos := wg.get_world_position(pc)
	var center_zone: Vector2i = wg.world_to_zone(player_pos)
	var half_px := MAP_PX / 2
	var explored: Dictionary = wg._explored_zones
	var cache: Dictionary = wg._zone_biome_cache
	var zone_size: float = wg.ZONE_SIZE

	if pc._map_biome_label:
		var current_biome: StringName = wg.get_biome_at(player_pos)
		var current_micro: StringName = wg.get_microbiome_at(player_pos)
		var display := biome_display_name(current_biome)
		if current_micro != &"none":
			display += " - " + microbiome_display_name(current_micro)
		pc._map_biome_label.text = display

	var zones_per_pixel: float = pc._map_zoom / float(half_px)
	var water_col := Color(0.12, 0.28, 0.52)
	var water_shallow := Color(0.18, 0.38, 0.55)
	var unexplored := Color(0.08, 0.08, 0.10, 1.0)

	var stride := 2
	for py in range(0, MAP_PX, stride):
		for px in range(0, MAP_PX, stride):
			var mask_pixel := pc._map_circle_mask.get_pixel(px, py)
			if mask_pixel.a < 0.01:
				continue

			if mask_pixel.r < 0.9 and mask_pixel.g < 0.9 and mask_pixel.a > 0.5 and (mask_pixel.r > 0.05 or mask_pixel.g > 0.05):
				var ring_col := Color(mask_pixel.r, mask_pixel.g, mask_pixel.b, mask_pixel.a)
				for sy in stride:
					for sx in stride:
						if px + sx < MAP_PX and py + sy < MAP_PX:
							pc._map_image.set_pixel(px + sx, py + sy, ring_col)
				continue

			var zone_fx: float = float(px - half_px) * zones_per_pixel
			var zone_fz: float = float(py - half_px) * zones_per_pixel
			var zone_coord := Vector2i(
				center_zone.x + roundi(zone_fx),
				center_zone.y + roundi(zone_fz))
			var world_x := player_pos.x + zone_fx * zone_size
			var world_z := player_pos.z + zone_fz * zone_size

			var col: Color
			if explored.has(zone_coord):
				var biome: StringName = cache.get(zone_coord, &"hearthlands") as StringName
				var micro := wg.get_microbiome_at_zone(zone_coord)
				if wg._zone_has_water(zone_coord):
					var h := wg.get_height_at(world_x, world_z)
					col = water_shallow.lerp(water_col, clampf((wg.WATER_LEVEL - h) / 6.0, 0.0, 1.0))
				else:
					col = biome_map_color(biome, micro)
					var h := wg.get_height_at(world_x, world_z)
					var bright := clampf(lerpf(0.7, 1.25, (h + 5.0) / 30.0), 0.0, 1.0)
					col = Color(
						clampf(col.r * bright, 0.0, 1.0),
						clampf(col.g * bright, 0.0, 1.0),
						clampf(col.b * bright, 0.0, 1.0))
			else:
				col = unexplored

			for sy in stride:
				for sx in stride:
					if px + sx < MAP_PX and py + sy < MAP_PX:
						pc._map_image.set_pixel(px + sx, py + sy, col)

	# ── Structure markers ──
	draw_structure_markers(half_px, zones_per_pixel, zone_size)

	# ── Player marker — directional arrow ──
	draw_player_arrow(half_px)

	pc._map_image_tex = ImageTexture.create_from_image(pc._map_image)
	pc._map_texture_rect.texture = pc._map_image_tex


func draw_player_arrow(half_px: int) -> void:
	draw_arrow_on_image(pc._map_image, half_px, 1.0)


func point_in_arrow(pt: Vector2, verts: Array[Vector2], scale: float) -> bool:
	var sv: Array[Vector2] = []
	for v in verts:
		sv.append(v * scale)
	# Triangle fan check: arrow is 2 triangles
	return point_in_tri(pt, sv[0], sv[1], sv[2]) or point_in_tri(pt, sv[0], sv[2], sv[3])


func point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var d2 := (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var d3 := (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	var has_neg := (d1 < 0.0) or (d2 < 0.0) or (d3 < 0.0)
	var has_pos := (d1 > 0.0) or (d2 > 0.0) or (d3 > 0.0)
	return not (has_neg and has_pos)


func draw_structure_markers(half_px: int, zones_per_pixel: float, zone_size: float) -> void:
	var marker_col := Color(0.9, 0.75, 0.3)
	var cave_col := Color(0.5, 0.35, 0.2)

	for node in pc.get_tree().get_nodes_in_group(&"structures"):
		var n3d := node as Node3D
		if not n3d:
			continue
		draw_map_dot(n3d.global_position, marker_col, 2, half_px, zones_per_pixel, zone_size)

	for node in pc.get_tree().get_nodes_in_group(&"cave_entrances"):
		var n3d := node as Node3D
		if not n3d:
			continue
		draw_map_dot(n3d.global_position, cave_col, 2, half_px, zones_per_pixel, zone_size)


func draw_map_dot(world_pos: Vector3, color: Color, radius: int, half_px: int, zones_per_pixel: float, zone_size: float) -> void:
	if zones_per_pixel < 0.001:
		return
	var dx_world := world_pos.x - pc.global_position.x
	var dz_world := world_pos.z - pc.global_position.z
	var px_x := half_px + roundi(dx_world / (zones_per_pixel * zone_size))
	var px_y := half_px + roundi(dz_world / (zones_per_pixel * zone_size))
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var fx := px_x + dx
				var fy := px_y + dy
				if fx >= 0 and fx < MAP_PX and fy >= 0 and fy < MAP_PX:
					pc._map_image.set_pixel(fx, fy, color)


func biome_map_color(biome: StringName, micro: StringName = &"none") -> Color:
	if biome == &"hearthlands" and micro != &"none":
		match micro:
			&"meadow":        return Color(0.42, 0.62, 0.28)
			&"forest":        return Color(0.2, 0.4, 0.15)
			&"birch_forest":  return Color(0.35, 0.55, 0.22)
			&"hills":         return Color(0.45, 0.52, 0.32)
			&"riverside":     return Color(0.32, 0.52, 0.35)
	if biome == &"ocean":
		return Color(0.1, 0.2, 0.4)
	return Color(0.35, 0.55, 0.25)


func biome_display_name(biome: StringName) -> String:
	if biome == &"ocean":
		return "Ocean"
	return "Hearthlands"


func microbiome_display_name(micro: StringName) -> String:
	match micro:
		&"meadow":        return "Meadow"
		&"forest":        return "Forest"
		&"birch_forest":  return "Birch Forest"
		&"hills":         return "Hills"
		&"riverside":     return "Riverside"
		_:                return ""


func find_world_generator() -> WorldGenerator:
	if is_instance_valid(pc._cached_wg):
		return pc._cached_wg
	var wgs := pc.get_tree().get_nodes_in_group(&"world_generator")
	for n in wgs:
		if n is WorldGenerator:
			pc._cached_wg = n as WorldGenerator
			return pc._cached_wg
	var root := pc.get_tree().current_scene
	for child in root.get_children():
		if child is WorldGenerator:
			pc._cached_wg = child as WorldGenerator
			return pc._cached_wg
	for child in root.get_children():
		for grandchild in child.get_children():
			if grandchild is WorldGenerator:
				pc._cached_wg = grandchild as WorldGenerator
				return pc._cached_wg
	return null


func build_interaction_prompt(root: Control) -> void:
	pc._interact_prompt = Label.new()
	pc._interact_prompt.name = "InteractionPrompt"
	pc._interact_prompt.visible = false
	pc._interact_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc._interact_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pc._interact_prompt.add_theme_font_size_override("font_size", 20)
	pc._interact_prompt.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	pc._interact_prompt.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	pc._interact_prompt.add_theme_constant_override("shadow_offset_x", 2)
	pc._interact_prompt.add_theme_constant_override("shadow_offset_y", 2)
	pc._interact_prompt.set_anchors_preset(Control.PRESET_CENTER)
	pc._interact_prompt.offset_top = 60
	pc._interact_prompt.offset_bottom = 100
	pc._interact_prompt.offset_left = -200
	pc._interact_prompt.offset_right = 200
	pc._interact_prompt.z_index = 50
	root.add_child(pc._interact_prompt)
