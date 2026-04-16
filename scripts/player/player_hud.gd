class_name PlayerHUD
extends Node

## HUD sub-module for PlayerController. Stores pc: PlayerController and accesses
## all controller state through pc. Autoloads (Input, GameEvents, Inventory,
## ItemDatabase, AudioManager, WaterSystem, SaveManager, WeatherSystem) are NOT prefixed.
##
## Only chat UI and player-list UI live here. Everything else (minimap, hotbar,
## pause menu, target HUD, world map, …) is now built directly in
## scripts/player/player_controller.gd or scripts/ui/world_map.gd.

var pc: PlayerController


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

	build_player_list(root)


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
