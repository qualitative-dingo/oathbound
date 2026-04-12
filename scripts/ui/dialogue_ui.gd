class_name DialogueUI
extends Node

signal dialogue_finished(action: String)

var pc: PlayerController

var _panel: PanelContainer
var _inner_panel: PanelContainer
var _speaker_label: Label
var _text_label: RichTextLabel
var _choices_box: VBoxContainer
var _skip_hint: Label
var _choices_rule: HSeparator
var _is_open: bool = false

var _tree: Array[Dictionary] = []
var _step: int = 0
var _showing_response: bool = false
var _showing_player_line: bool = false
var _pending_next: int = -1
var _pending_action: String = ""
var _pending_opt: Dictionary = {}
var _pending_opt_type: String = ""

var _auto_advance_tween: Tween
var _typewriter_tween: Tween
var _full_text: String = ""
var _skip_hint_shown := false

const _CHAR_DELAY := 0.025
const _POST_AUDIO_BUFFER := 0.8
const _MS_PER_CHAR := 40.0
const _MIN_READ_TIME := 2.0
const _PLAYER_SPEAKER := "You"
const _NPC_COLOR := Color(1.0, 0.82, 0.35)
const _PLAYER_COLOR := Color(0.78, 0.82, 0.92)


func build_panel(root: Control) -> void:
	_panel = PanelContainer.new()
	_panel.name = "DialoguePanel"
	_panel.visible = false
	_panel.anchor_left = 0.15
	_panel.anchor_right = 0.85
	_panel.anchor_top = 0.63
	_panel.anchor_bottom = 0.95
	_panel.offset_left = 0
	_panel.offset_right = 0
	_panel.offset_top = 0
	_panel.offset_bottom = -16
	_panel.z_index = 100
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var outer_bg := StyleBoxFlat.new()
	outer_bg.bg_color = Color(0.03, 0.025, 0.015, 0.96)
	outer_bg.border_color = Color(0.35, 0.28, 0.12)
	outer_bg.set_border_width_all(3)
	outer_bg.set_corner_radius_all(14)
	outer_bg.set_content_margin_all(4)
	_panel.add_theme_stylebox_override("panel", outer_bg)

	_inner_panel = PanelContainer.new()
	_inner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner_bg := StyleBoxFlat.new()
	inner_bg.bg_color = Color(0.07, 0.06, 0.04, 0.98)
	inner_bg.border_color = Color(0.55, 0.42, 0.16, 0.7)
	inner_bg.set_border_width_all(1)
	inner_bg.set_corner_radius_all(10)
	inner_bg.content_margin_left = 24
	inner_bg.content_margin_right = 24
	inner_bg.content_margin_top = 16
	inner_bg.content_margin_bottom = 16
	_inner_panel.add_theme_stylebox_override("panel", inner_bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	_speaker_label = Label.new()
	_speaker_label.add_theme_font_size_override("font_size", 24)
	_speaker_label.add_theme_color_override("font_color", _NPC_COLOR)
	_speaker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_speaker_label)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.scroll_active = false
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("normal_font_size", 18)
	_text_label.add_theme_color_override("default_color", Color(0.90, 0.86, 0.76))
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_text_label)

	_choices_rule = HSeparator.new()
	_choices_rule.add_theme_constant_override("separation", 6)
	_choices_rule.add_theme_color_override("separator", Color(0.45, 0.35, 0.15, 0.4))
	_choices_rule.visible = false
	vbox.add_child(_choices_rule)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 5)
	_choices_box.visible = false
	vbox.add_child(_choices_box)

	_skip_hint = Label.new()
	_skip_hint.text = "click to continue"
	_skip_hint.add_theme_font_size_override("font_size", 11)
	_skip_hint.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 0.5))
	_skip_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_skip_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_skip_hint)

	_inner_panel.add_child(vbox)
	_panel.add_child(_inner_panel)
	root.add_child(_panel)


func open_dialogue(tree: Array[Dictionary]) -> void:
	_tree = tree
	_step = 0
	_showing_response = false
	_showing_player_line = false
	_pending_next = -1
	_pending_action = ""
	_pending_opt = {}
	_pending_opt_type = ""
	_skip_hint_shown = false
	_is_open = true
	_panel.visible = true
	_skip_hint.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if pc and pc._minimap_biome_label:
		pc._minimap_biome_label.visible = false
	_present_step()


func close_dialogue() -> void:
	_kill_tweens()
	_disconnect_audio_signal()
	if AudioManager._speech_player.playing:
		AudioManager._speech_player.stop()
	_panel.visible = false
	_is_open = false
	_showing_response = false
	_showing_player_line = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if pc and pc._minimap_biome_label:
		pc._minimap_biome_label.visible = true


func is_open() -> bool:
	return _is_open


func is_showing_choices() -> bool:
	return _choices_box.visible


func handle_click() -> void:
	if not _is_open or is_showing_choices():
		return
	if _is_typewriting():
		_complete_typewriter()
		return
	if _showing_player_line:
		_skip_to_response()
	elif _showing_response or _is_npc_talking():
		_skip_to_next()
	if not _skip_hint_shown:
		_skip_hint_shown = true
		_skip_hint.visible = false


func _is_typewriting() -> bool:
	return _typewriter_tween != null and _typewriter_tween.is_valid() and _typewriter_tween.is_running()


func _complete_typewriter() -> void:
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
		_typewriter_tween = null
	_text_label.text = _full_text
	if not _skip_hint_shown:
		_skip_hint_shown = true
		_skip_hint.visible = false


func _is_npc_talking() -> bool:
	if _step < 0 or _step >= _tree.size():
		return false
	return str(_tree[_step].get("type", "npc")) == "npc"


func _present_step() -> void:
	if _step < 0 or _step >= _tree.size():
		close_dialogue()
		dialogue_finished.emit("end")
		return

	_kill_tweens()
	_disconnect_audio_signal()
	_clear_choices()
	_showing_response = false
	_showing_player_line = false

	var node: Dictionary = _tree[_step]
	var type: String = str(node.get("type", "npc"))

	if type == "npc":
		var speaker := str(node.get("speaker", "???"))
		_set_speaker(speaker, false)
		var text := str(node.get("text", ""))
		_start_typewriter(text)
		_play_node_audio(node)
		_pending_next = int(node.get("next", _step + 1))
		_schedule_auto_advance(text)
	elif type == "choice" or type == "final":
		_show_choices(node)


func _find_last_npc_speaker() -> String:
	for i in range(_step - 1, -1, -1):
		var n: Dictionary = _tree[i]
		if str(n.get("type", "npc")) == "npc" and n.has("speaker"):
			return str(n["speaker"])
	return "???"


func _show_choices(node: Dictionary) -> void:
	_clear_choices()
	_set_speaker(_find_last_npc_speaker(), false)
	_text_label.text = ""
	_choices_rule.visible = true
	_choices_box.visible = true

	var options: Array = node.get("options", []) as Array
	for i in options.size():
		var opt: Dictionary = options[i] as Dictionary
		var btn := Button.new()
		btn.text = "  \u25c6  " + str(opt.get("label", "..."))
		btn.add_theme_font_size_override("font_size", 15)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 42)

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.06, 0.04, 0.0)
		style.border_color = Color(0.0, 0.0, 0.0, 0.0)
		style.set_border_width_all(0)
		style.set_corner_radius_all(6)
		style.content_margin_left = 16
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		btn.add_theme_stylebox_override("normal", style)

		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = Color(0.14, 0.11, 0.06, 0.85)
		hover_style.border_color = Color(0.65, 0.48, 0.18, 0.8)
		hover_style.set_border_width_all(1)
		hover_style.set_corner_radius_all(6)
		hover_style.content_margin_left = 16
		hover_style.content_margin_right = 12
		hover_style.content_margin_top = 8
		hover_style.content_margin_bottom = 8
		btn.add_theme_stylebox_override("hover", hover_style)
		btn.add_theme_stylebox_override("pressed", hover_style)
		btn.add_theme_stylebox_override("focus", style)
		btn.focus_mode = Control.FOCUS_NONE

		btn.add_theme_color_override("font_color", Color(0.72, 0.68, 0.58))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.90, 0.55))
		btn.add_theme_color_override("font_focus_color", Color(0.72, 0.68, 0.58))

		var bound_opt := opt
		var bound_type := str(node.get("type", "choice"))
		btn.pressed.connect(_on_choice_picked.bind(bound_opt, bound_type))
		_choices_box.add_child(btn)

	if _choices_box.get_child_count() > 0:
		_choices_box.get_child(0).release_focus()


func _on_choice_picked(opt: Dictionary, type: String) -> void:
	_kill_tweens()
	_disconnect_audio_signal()
	AudioManager._speech_player.stop()
	_clear_choices()

	var player_label := str(opt.get("label", ""))
	var player_audio: Array = opt.get("audio", []) as Array
	var response := str(opt.get("response", ""))

	_pending_opt = opt
	_pending_opt_type = type

	if response == "" and opt.has("action"):
		var action := str(opt.get("action", ""))
		close_dialogue()
		dialogue_finished.emit(action)
		return

	if response != "":
		if type == "final":
			_pending_action = str(opt.get("action", ""))
			_pending_next = -1
		else:
			_pending_next = int(opt.get("next", _step + 1))
			_pending_action = ""

	_set_speaker(_PLAYER_SPEAKER, true)
	_start_typewriter(player_label)
	_showing_player_line = true

	if player_audio.size() >= 2:
		_play_node_audio({"audio": player_audio})
		AudioManager._speech_player.finished.connect(_on_player_audio_done, CONNECT_ONE_SHOT)
	else:
		var delay := maxf(player_label.length() * _MS_PER_CHAR / 1000.0, _MIN_READ_TIME)
		_auto_advance_tween = _panel.create_tween()
		_auto_advance_tween.tween_interval(delay)
		_auto_advance_tween.tween_callback(_on_player_audio_done)


func _on_player_audio_done() -> void:
	if not _is_open or not _showing_player_line:
		return
	_showing_player_line = false
	_disconnect_audio_signal()
	AudioManager._speech_player.stop()

	_auto_advance_tween = _panel.create_tween()
	_auto_advance_tween.tween_interval(0.25)
	_auto_advance_tween.tween_callback(_show_npc_response)


func _show_npc_response() -> void:
	if not _is_open:
		return
	var opt := _pending_opt
	var type := _pending_opt_type
	var response := str(opt.get("response", ""))

	if response != "":
		var speaker := str(opt.get("response_speaker", _find_last_npc_speaker()))
		_set_speaker(speaker, false)
		_start_typewriter(response)
		var resp_audio: Array = opt.get("response_audio", []) as Array
		if resp_audio.size() >= 2:
			_play_node_audio({"audio": resp_audio})
		else:
			_play_node_audio(opt)
		_showing_response = true
		_schedule_auto_advance(response)
	else:
		if type == "final":
			var action := str(opt.get("action", ""))
			close_dialogue()
			dialogue_finished.emit(action)
		else:
			_step = int(opt.get("next", _step + 1))
			_present_step()


func _skip_to_response() -> void:
	if not _showing_player_line:
		return
	_kill_tweens()
	_disconnect_audio_signal()
	AudioManager._speech_player.stop()
	_text_label.text = _full_text
	_on_player_audio_done()


func _skip_to_next() -> void:
	_kill_tweens()
	_disconnect_audio_signal()
	AudioManager._speech_player.stop()
	_text_label.text = _full_text

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
	elif _is_npc_talking():
		_step = _pending_next if _pending_next >= 0 else _step + 1
		_pending_next = -1
		_present_step()


func _schedule_auto_advance(text: String) -> void:
	_kill_auto_advance()
	var sp := AudioManager._speech_player
	if sp.playing:
		sp.finished.connect(_on_npc_audio_done, CONNECT_ONE_SHOT)
	else:
		var delay := maxf(text.length() * _MS_PER_CHAR / 1000.0, _MIN_READ_TIME)
		_auto_advance_tween = _panel.create_tween()
		_auto_advance_tween.tween_interval(delay)
		_auto_advance_tween.tween_callback(_advance_after_audio)


func _on_npc_audio_done() -> void:
	if not _is_open:
		return
	_auto_advance_tween = _panel.create_tween()
	_auto_advance_tween.tween_interval(_POST_AUDIO_BUFFER)
	_auto_advance_tween.tween_callback(_advance_after_audio)


func _advance_after_audio() -> void:
	if not _is_open:
		return
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
	elif _is_npc_talking():
		_step = _pending_next if _pending_next >= 0 else _step + 1
		_pending_next = -1
		_present_step()


func _set_speaker(name: String, is_player: bool) -> void:
	var deco := "\u2014"
	_speaker_label.text = "%s  %s  %s" % [deco, name, deco]
	_speaker_label.add_theme_color_override("font_color", _PLAYER_COLOR if is_player else _NPC_COLOR)


func _start_typewriter(text: String) -> void:
	_full_text = text
	_text_label.text = ""
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
	_typewriter_tween = _panel.create_tween()
	var total_time := text.length() * _CHAR_DELAY
	_typewriter_tween.tween_method(_typewriter_update.bind(text), 0.0, 1.0, total_time)


func _typewriter_update(progress: float, text: String) -> void:
	var char_count := int(progress * text.length())
	_text_label.text = text.substr(0, char_count)


func _play_node_audio(node: Dictionary) -> void:
	var audio: Array = node.get("audio", []) as Array
	if audio.size() >= 2:
		var grp: String = str(audio[0])
		var idx: int = int(audio[1])
		AudioManager.play_speech(grp, idx)


func _disconnect_audio_signal() -> void:
	var sp := AudioManager._speech_player
	if sp.finished.is_connected(_on_npc_audio_done):
		sp.finished.disconnect(_on_npc_audio_done)
	if sp.finished.is_connected(_on_player_audio_done):
		sp.finished.disconnect(_on_player_audio_done)


func _kill_tweens() -> void:
	if _auto_advance_tween and _auto_advance_tween.is_valid():
		_auto_advance_tween.kill()
		_auto_advance_tween = null
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
		_typewriter_tween = null


func _kill_auto_advance() -> void:
	if _auto_advance_tween and _auto_advance_tween.is_valid():
		_auto_advance_tween.kill()
		_auto_advance_tween = null
	_disconnect_audio_signal()


func _clear_choices() -> void:
	for child in _choices_box.get_children():
		_choices_box.remove_child(child)
		child.queue_free()
	_choices_box.visible = false
	_choices_rule.visible = false
