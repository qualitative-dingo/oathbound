class_name PlayerWorkbenchUI
extends Node

## Workbench UI sub-module for PlayerController. Stores pc: PlayerController and accesses
## all controller state through pc. Autoloads (Input, GameEvents, Inventory,
## ItemDatabase, AudioManager) are NOT prefixed.

var pc: PlayerController


func build_workbench_panel(root: Control) -> void:
	pc._workbench_panel = PanelContainer.new()
	pc._workbench_panel.name = "WorkbenchPanel"
	pc._workbench_panel.visible = false
	pc._workbench_panel.set_anchors_preset(Control.PRESET_CENTER)
	pc._workbench_panel.position = Vector2(-252, -240)
	pc._workbench_panel.custom_minimum_size = Vector2(504, 480)
	pc._workbench_panel.z_index = 90

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.06, 0.1, 0.95)
	bg.border_color = Color(0.6, 0.45, 0.2)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(17)
	pc._workbench_panel.add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var title := Label.new()
	title.text = "Workbench"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	pc._workbench_discard_btn = Button.new()
	pc._workbench_discard_btn.text = "🗑 Off"
	pc._workbench_discard_btn.add_theme_font_size_override("font_size", 12)
	pc._workbench_discard_btn.custom_minimum_size = Vector2(70, 28)
	pc._workbench_discard_btn.tooltip_text = "Auto-trash: crafted items at or below this rarity are instantly destroyed"
	pc._workbench_discard_btn.pressed.connect(cycle_auto_discard)
	var discard_style := StyleBoxFlat.new()
	discard_style.bg_color = Color(0.15, 0.12, 0.1, 0.9)
	discard_style.border_color = Color(0.4, 0.35, 0.25)
	discard_style.set_border_width_all(1)
	discard_style.set_corner_radius_all(4)
	discard_style.set_content_margin_all(4)
	pc._workbench_discard_btn.add_theme_stylebox_override("normal", discard_style)
	title_row.add_child(pc._workbench_discard_btn)

	vbox.add_child(title_row)

	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pc._workbench_tab_buttons.clear()
	for cat in ["Tools", "Equipment", "Supplies", "Building"]:
		var btn := Button.new()
		btn.text = cat
		btn.custom_minimum_size = Vector2(102, 34)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(on_workbench_tab.bind(cat))
		tab_row.add_child(btn)
		pc._workbench_tab_buttons.append(btn)
	vbox.add_child(tab_row)

	# Equipment sub-filter row (Weapons / Armor / Tools) — only visible for Equipment tab
	pc._workbench_equip_filter_row = HBoxContainer.new()
	pc._workbench_equip_filter_row.add_theme_constant_override("separation", 4)
	pc._workbench_equip_filter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pc._workbench_equip_filter_row.visible = false
	pc._workbench_equip_filter_buttons.clear()
	for sub in ["All", "Weapons", "Armor"]:
		var sbtn := Button.new()
		sbtn.text = sub
		sbtn.custom_minimum_size = Vector2(80, 26)
		sbtn.add_theme_font_size_override("font_size", 11)
		sbtn.pressed.connect(_on_equip_filter.bind(sub))
		pc._workbench_equip_filter_row.add_child(sbtn)
		pc._workbench_equip_filter_buttons.append(sbtn)
	vbox.add_child(pc._workbench_equip_filter_row)

	# Quality tier slider — only visible for Equipment tab
	var tier_vbox := VBoxContainer.new()
	tier_vbox.add_theme_constant_override("separation", 0)

	# Slider row: label + slider
	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 10)
	slider_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var q_label := Label.new()
	q_label.text = "Quality"
	q_label.add_theme_font_size_override("font_size", 12)
	q_label.add_theme_color_override("font_color", Color(0.7, 0.65, 0.5))
	slider_row.add_child(q_label)

	pc._workbench_tier_slider = HSlider.new()
	pc._workbench_tier_slider.min_value = 0
	pc._workbench_tier_slider.max_value = 2
	pc._workbench_tier_slider.step = 1
	pc._workbench_tier_slider.value = 0
	pc._workbench_tier_slider.tick_count = 0
	pc._workbench_tier_slider.ticks_on_borders = false
	pc._workbench_tier_slider.custom_minimum_size = Vector2(180, 20)
	pc._workbench_tier_slider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Style the slider track
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = Color(0.15, 0.14, 0.2, 0.9)
	slider_bg.set_corner_radius_all(3)
	slider_bg.content_margin_top = 8
	slider_bg.content_margin_bottom = 8
	pc._workbench_tier_slider.add_theme_stylebox_override("slider", slider_bg)

	var slider_fg := StyleBoxFlat.new()
	slider_fg.bg_color = Color(0.7, 0.6, 0.3, 0.6)
	slider_fg.set_corner_radius_all(3)
	slider_fg.content_margin_top = 8
	slider_fg.content_margin_bottom = 8
	pc._workbench_tier_slider.add_theme_stylebox_override("grabber_area", slider_fg)
	pc._workbench_tier_slider.add_theme_stylebox_override("grabber_area_highlight", slider_fg)

	pc._workbench_tier_slider.value_changed.connect(_on_tier_slider_changed)
	slider_row.add_child(pc._workbench_tier_slider)
	tier_vbox.add_child(slider_row)

	# Tick labels row: Low / Medium / High
	pc._workbench_tier_row = HBoxContainer.new()
	pc._workbench_tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pc._workbench_tier_row.add_theme_constant_override("separation", 0)

	var spacer_left := Control.new()
	spacer_left.custom_minimum_size = Vector2(62, 0)
	pc._workbench_tier_row.add_child(spacer_left)

	pc._workbench_tier_labels.clear()
	var tier_names := ["Low", "Medium", "High"]
	for i in tier_names.size():
		var lbl := Label.new()
		lbl.text = tier_names[i]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size = Vector2(60, 0)
		pc._workbench_tier_row.add_child(lbl)
		pc._workbench_tier_labels.append(lbl)
	tier_vbox.add_child(pc._workbench_tier_row)

	# Info button
	var info_btn := Button.new()
	info_btn.text = "ⓘ  Material Quality"
	info_btn.add_theme_font_size_override("font_size", 12)
	info_btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	info_style.set_border_width_all(0)
	info_style.set_content_margin_all(2)
	info_btn.add_theme_stylebox_override("normal", info_style)
	var info_hover := info_style.duplicate() as StyleBoxFlat
	info_hover.bg_color = Color(0.2, 0.2, 0.3, 0.3)
	info_btn.add_theme_stylebox_override("hover", info_hover)
	info_btn.pressed.connect(toggle_tier_info)
	tier_vbox.add_child(info_btn)

	pc._workbench_tier_info_panel = PanelContainer.new()
	pc._workbench_tier_info_panel.visible = false
	var info_bg := StyleBoxFlat.new()
	info_bg.bg_color = Color(0.08, 0.08, 0.14, 0.95)
	info_bg.border_color = Color(0.5, 0.4, 0.25)
	info_bg.set_border_width_all(1)
	info_bg.set_corner_radius_all(4)
	info_bg.set_content_margin_all(12)
	pc._workbench_tier_info_panel.add_theme_stylebox_override("panel", info_bg)
	var info_rtl := RichTextLabel.new()
	info_rtl.bbcode_enabled = true
	info_rtl.fit_content = true
	info_rtl.scroll_active = false
	info_rtl.add_theme_font_size_override("normal_font_size", 12)
	info_rtl.add_theme_font_size_override("bold_font_size", 12)
	info_rtl.text = "[b]Controls which materials are used when crafting weapons and armor.[/b]\n\n" \
		+ "[color=#ffffff]Low[/color] — Uses 0–1★ materials only. Consumes [color=#aaaaaa]lowest[/color] quality first.\n" \
		+ "  Ideal for basic crafts without spending starred materials.\n\n" \
		+ "[color=#55aaff]Medium[/color] — Uses 1–3★ materials only (ignores 0★). Consumes [color=#aaaaaa]highest[/color] quality first.\n" \
		+ "  Good balance — uses your mid-tier materials for a reasonable star chance.\n\n" \
		+ "[color=#ff4444]High[/color] — Uses 3–5★ materials only (ignores 0–2★). Consumes [color=#aaaaaa]highest[/color] quality first.\n" \
		+ "  Best chance at high-star gear, but requires rare materials.\n\n" \
		+ "[color=#ccaa66]Higher quality materials increase the chance of crafting starred gear with powerful affixes.\n" \
		+ "Select an item to see exact material consumption and star chances before crafting.[/color]"
	pc._workbench_tier_info_panel.add_child(info_rtl)
	tier_vbox.add_child(pc._workbench_tier_info_panel)

	vbox.add_child(tier_vbox)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(468, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc._workbench_grid = VBoxContainer.new()
	pc._workbench_grid.add_theme_constant_override("separation", 4)
	pc._workbench_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pc._workbench_grid)
	vbox.add_child(scroll)

	pc._workbench_craft_btn = Button.new()
	pc._workbench_craft_btn.text = "Craft"
	pc._workbench_craft_btn.custom_minimum_size = Vector2(468, 40)
	pc._workbench_craft_btn.add_theme_font_size_override("font_size", 16)
	pc._workbench_craft_btn.disabled = true
	var craft_btn_style := StyleBoxFlat.new()
	craft_btn_style.bg_color = Color(0.2, 0.2, 0.25, 0.9)
	craft_btn_style.border_color = Color(0.4, 0.35, 0.25)
	craft_btn_style.set_border_width_all(1)
	craft_btn_style.set_corner_radius_all(4)
	craft_btn_style.set_content_margin_all(6)
	pc._workbench_craft_btn.add_theme_stylebox_override("normal", craft_btn_style)
	var craft_btn_disabled := craft_btn_style.duplicate() as StyleBoxFlat
	craft_btn_disabled.bg_color = Color(0.12, 0.12, 0.15, 0.9)
	craft_btn_disabled.border_color = Color(0.25, 0.25, 0.25)
	pc._workbench_craft_btn.add_theme_stylebox_override("disabled", craft_btn_disabled)
	pc._workbench_craft_btn.add_theme_color_override("font_disabled_color", Color(0.4, 0.4, 0.4))
	pc._workbench_craft_btn.pressed.connect(_on_craft_btn_pressed)
	vbox.add_child(pc._workbench_craft_btn)

	pc._workbench_panel.add_child(vbox)
	root.add_child(pc._workbench_panel)

	pc._workbench_preview_panel = PanelContainer.new()
	pc._workbench_preview_panel.name = "CraftPreviewPanel"
	pc._workbench_preview_panel.visible = false
	pc._workbench_preview_panel.set_anchors_preset(Control.PRESET_CENTER)
	pc._workbench_preview_panel.custom_minimum_size = Vector2(360, 0)
	pc._workbench_preview_panel.position = Vector2(270, -120)
	pc._workbench_preview_panel.z_index = 95
	var ppbg := StyleBoxFlat.new()
	ppbg.bg_color = Color(0.08, 0.07, 0.12, 0.97)
	ppbg.border_color = Color(0.5, 0.7, 0.5)
	ppbg.set_border_width_all(2)
	ppbg.set_corner_radius_all(8)
	ppbg.set_content_margin_all(14)
	pc._workbench_preview_panel.add_theme_stylebox_override("panel", ppbg)
	root.add_child(pc._workbench_preview_panel)


func toggle_tier_info() -> void:
	if pc._workbench_tier_info_panel:
		pc._workbench_tier_info_panel.visible = not pc._workbench_tier_info_panel.visible


func cycle_auto_discard() -> void:
	pc._workbench_auto_discard_star += 1
	if pc._workbench_auto_discard_star > 4:
		pc._workbench_auto_discard_star = -1
	update_discard_btn_label()


func update_discard_btn_label() -> void:
	if not pc._workbench_discard_btn:
		return
	if pc._workbench_auto_discard_star < 0:
		pc._workbench_discard_btn.text = "🗑 Off"
		pc._workbench_discard_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	else:
		var rname: String = ItemDatabase.RARITY_NAMES[pc._workbench_auto_discard_star]
		pc._workbench_discard_btn.text = "🗑 ≤%s" % rname
		pc._workbench_discard_btn.add_theme_color_override("font_color", ItemDatabase.RARITY_COLORS[pc._workbench_auto_discard_star])


func _on_tier_slider_changed(value: float) -> void:
	var tiers := ["low", "medium", "high"]
	var idx := int(value)
	if idx >= 0 and idx < tiers.size():
		pc._workbench_quality_tier = tiers[idx]
	refresh_workbench_ui()


func on_workbench_tier(tier: String) -> void:
	pc._workbench_quality_tier = tier
	if pc._workbench_tier_slider:
		var idx: int = {"low": 0, "medium": 1, "high": 2}.get(tier, 0)
		pc._workbench_tier_slider.set_value_no_signal(float(idx))
	refresh_workbench_ui()


func get_workbench_star_config() -> Dictionary:
	match pc._workbench_quality_tier:
		"medium": return {"min": 1, "max": 3, "prefer_low": false}
		"high": return {"min": 3, "max": 5, "prefer_low": false}
		_: return {"min": 0, "max": 1, "prefer_low": true}


func on_workbench_tab(category: String) -> void:
	pc._workbench_category = category
	pc._workbench_selected_id = &""
	pc._workbench_equip_filter = "All"
	refresh_workbench_ui()


func _on_equip_filter(sub: String) -> void:
	pc._workbench_equip_filter = sub
	pc._workbench_selected_id = &""
	refresh_workbench_ui()


func open_workbench() -> void:
	if not pc._workbench_panel:
		return
	if pc._workbench_open:
		return
	pc._workbench_open = true
	pc._workbench_selected_id = &""
	pc._workbench_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	call_deferred("refresh_workbench_ui")


func close_workbench() -> void:
	pc._workbench_open = false
	if pc._workbench_panel:
		pc._workbench_panel.visible = false
	if pc._workbench_preview_panel:
		pc._workbench_preview_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func get_workbench_category(data: Dictionary) -> String:
	var item_type: String = str(data.get("type", "material"))
	if item_type == "tool":
		return "Tools"
	elif item_type in ["weapon", "armor"]:
		return "Equipment"
	elif item_type == "placeable":
		return "Building"
	else:
		return "Supplies"


func refresh_workbench_ui() -> void:
	if pc._workbench_preview_panel:
		pc._workbench_preview_panel.visible = false
	if not pc._workbench_grid or not is_instance_valid(pc._workbench_grid):
		return
	while pc._workbench_grid.get_child_count() > 0:
		var c := pc._workbench_grid.get_child(0)
		pc._workbench_grid.remove_child(c)
		c.free()

	# Style active tab
	for btn in pc._workbench_tab_buttons:
		var is_active := btn.text == pc._workbench_category
		var s := StyleBoxFlat.new()
		if is_active:
			s.bg_color = Color(0.9, 0.75, 0.4, 0.3)
			s.border_color = Color(0.9, 0.75, 0.4)
		else:
			s.bg_color = Color(0.15, 0.14, 0.2, 0.8)
			s.border_color = Color(0.3, 0.28, 0.22)
		s.set_border_width_all(1)
		s.set_corner_radius_all(4)
		s.set_content_margin_all(4)
		btn.add_theme_stylebox_override("normal", s)
		var h := s.duplicate() as StyleBoxFlat
		h.bg_color = s.bg_color.lightened(0.15)
		btn.add_theme_stylebox_override("hover", h)
		btn.add_theme_color_override("font_color", Color.WHITE if is_active else Color(0.7, 0.65, 0.55))

	# Show/hide equipment sub-filter and quality tier — only for Equipment tab
	var show_equip := pc._workbench_category == "Equipment"
	if pc._workbench_equip_filter_row:
		pc._workbench_equip_filter_row.visible = show_equip
	if show_equip:
		for sbtn in pc._workbench_equip_filter_buttons:
			var is_active := sbtn.text == pc._workbench_equip_filter
			var ss := StyleBoxFlat.new()
			if is_active:
				ss.bg_color = Color(0.7, 0.6, 0.35, 0.3)
				ss.border_color = Color(0.7, 0.6, 0.35)
			else:
				ss.bg_color = Color(0.12, 0.12, 0.18, 0.8)
				ss.border_color = Color(0.25, 0.24, 0.2)
			ss.set_border_width_all(1)
			ss.set_corner_radius_all(3)
			ss.set_content_margin_all(3)
			sbtn.add_theme_stylebox_override("normal", ss)
			var sh := ss.duplicate() as StyleBoxFlat
			sh.bg_color = ss.bg_color.lightened(0.12)
			sbtn.add_theme_stylebox_override("hover", sh)
			sbtn.add_theme_color_override("font_color", Color.WHITE if is_active else Color(0.55, 0.52, 0.45))

	var show_tiers := show_equip
	if pc._workbench_tier_row:
		pc._workbench_tier_row.get_parent().visible = show_tiers
	if pc._workbench_tier_info_panel and not show_tiers:
		pc._workbench_tier_info_panel.visible = false
	if pc._workbench_discard_btn:
		pc._workbench_discard_btn.visible = show_tiers

	# Sync slider position and style tick labels
	var tier_colors := {"low": Color.WHITE, "medium": Color(0.35, 0.7, 1.0), "high": Color(1.0, 0.25, 0.25)}
	var tier_keys := ["low", "medium", "high"]
	if pc._workbench_tier_slider:
		var idx := tier_keys.find(pc._workbench_quality_tier)
		if idx >= 0:
			pc._workbench_tier_slider.set_value_no_signal(float(idx))
	for i in pc._workbench_tier_labels.size():
		var lbl: Label = pc._workbench_tier_labels[i]
		var key: String = tier_keys[i]
		var is_active := key == pc._workbench_quality_tier
		var accent: Color = tier_colors.get(key, Color.WHITE)
		lbl.add_theme_color_override("font_color", accent if is_active else Color(0.4, 0.38, 0.35))

	var star_cfg := get_workbench_star_config()
	var max_star: int = star_cfg["max"]
	var min_star: int = star_cfg["min"]
	var prefer_low: bool = star_cfg["prefer_low"]

	# Building tab: show BUILD_RECIPES (same items as hammer build menu)
	if pc._workbench_category == "Building":
		populate_workbench_building_tab()
		_update_craft_btn_state()
		_show_selected_detail()
		return

	var recipes: Array = ItemDatabase.get_workbench_recipes()
	if recipes.is_empty():
		_update_craft_btn_state()
		return

	var found_any := false
	for i in recipes.size():
		var entry = recipes[i]
		if not entry is Dictionary:
			continue
		var item_id: StringName = StringName(str(entry.get("id", "")))
		var data = entry.get("data", {})
		if not data is Dictionary:
			continue
		if item_id == &"" or data.is_empty():
			continue

		if get_workbench_category(data) != pc._workbench_category:
			continue

		var item_type: String = str(data.get("type", "material"))

		if pc._workbench_category == "Equipment" and pc._workbench_equip_filter != "All":
			match pc._workbench_equip_filter:
				"Weapons":
					if item_type != "weapon":
						continue
				"Armor":
					if item_type != "armor":
						continue

		found_any = true
		var is_starrable := item_type in ["weapon", "armor"]
		var eff_max: int = max_star if is_starrable else 0
		var eff_min: int = min_star if is_starrable else 0
		var can_make: bool = ItemDatabase.can_craft(item_id, eff_max, eff_min)

		var is_selected := item_id == pc._workbench_selected_id

		var row_btn := Button.new()
		row_btn.custom_minimum_size = Vector2(0, 48)
		row_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row_style := StyleBoxFlat.new()
		if is_selected:
			row_style.bg_color = Color(0.9, 0.75, 0.4, 0.2)
			row_style.border_color = Color(0.9, 0.75, 0.4)
		else:
			row_style.bg_color = Color(0.1, 0.1, 0.14, 0.5)
			row_style.border_color = Color(0.2, 0.2, 0.22)
		row_style.set_border_width_all(1)
		row_style.set_corner_radius_all(4)
		row_style.set_content_margin_all(6)
		row_btn.add_theme_stylebox_override("normal", row_style)
		var row_hover := row_style.duplicate() as StyleBoxFlat
		row_hover.bg_color = row_style.bg_color.lightened(0.12)
		row_btn.add_theme_stylebox_override("hover", row_hover)
		row_btn.pressed.connect(_on_select_item.bind(item_id))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(38, 38)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon_tex: Texture2D = ItemDatabase.get_icon(item_id)
		if icon_tex:
			icon_rect.texture = icon_tex
		else:
			var ph := PlaceholderTexture2D.new()
			ph.size = Vector2(34, 34)
			icon_rect.texture = ph
			icon_rect.modulate = get_item_fallback_color(item_id)
		row.add_child(icon_rect)

		var craft_amount: int = int(data.get("craft_amount", 1))
		var name_text: String = str(data.get("name", str(item_id)))
		if craft_amount > 1:
			name_text += " x%d" % craft_amount
		var name_lbl := Label.new()
		name_lbl.text = name_text
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.add_theme_color_override("font_color", Color.WHITE if can_make else Color(0.45, 0.45, 0.45))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_lbl)

		row_btn.add_child(row)
		pc._workbench_grid.add_child(row_btn)

	if not found_any:
		var empty_lbl := Label.new()
		empty_lbl.text = "No recipes in this category."
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pc._workbench_grid.add_child(empty_lbl)

	_update_craft_btn_state()
	_show_selected_detail()


func get_build_icon(recipe_id: StringName) -> Texture2D:
	var path := "res://textures/items/%s.png" % str(recipe_id)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func populate_workbench_building_tab() -> void:
	var _free := Inventory.has_free_craft()
	for recipe: Dictionary in pc.BUILD_RECIPES:
		var recipe_id: StringName = recipe["id"] as StringName
		var can_afford := true
		if not _free:
			for mat: Dictionary in (recipe["cost"] as Array):
				var mat_id: StringName = mat["item"] as StringName
				var mat_amt: int = int(mat["amount"])
				if Inventory.get_amount_any_star(mat_id) < mat_amt:
					can_afford = false
					break

		var is_selected := recipe_id == pc._workbench_selected_id
		var row_btn := Button.new()
		row_btn.custom_minimum_size = Vector2(0, 48)
		row_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var row_style := StyleBoxFlat.new()
		if is_selected:
			row_style.bg_color = Color(0.9, 0.75, 0.4, 0.2)
			row_style.border_color = Color(0.9, 0.75, 0.4)
		else:
			row_style.bg_color = Color(0.1, 0.1, 0.14, 0.5)
			row_style.border_color = Color(0.2, 0.2, 0.22)
		row_style.set_border_width_all(1)
		row_style.set_corner_radius_all(4)
		row_style.set_content_margin_all(6)
		row_btn.add_theme_stylebox_override("normal", row_style)
		var row_hover := row_style.duplicate() as StyleBoxFlat
		row_hover.bg_color = row_style.bg_color.lightened(0.12)
		row_btn.add_theme_stylebox_override("hover", row_hover)
		row_btn.pressed.connect(_on_select_building.bind(recipe_id))

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var icon_tex := get_build_icon(recipe_id)
		if icon_tex:
			var tex_rect := TextureRect.new()
			tex_rect.texture = icon_tex
			tex_rect.custom_minimum_size = Vector2(38, 38)
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(tex_rect)
		else:
			var color_rect := ColorRect.new()
			color_rect.custom_minimum_size = Vector2(38, 38)
			color_rect.color = recipe.get("color", Color(0.4, 0.3, 0.15)) as Color
			color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(color_rect)

		var name_lbl := Label.new()
		name_lbl.text = recipe["name"] as String
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.add_theme_color_override("font_color", Color.WHITE if can_afford else Color(0.45, 0.45, 0.45))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_lbl)

		row_btn.add_child(row)
		pc._workbench_grid.add_child(row_btn)


func _on_select_building(build_id: StringName) -> void:
	if pc._workbench_selected_id == build_id:
		pc._workbench_selected_id = &""
	else:
		pc._workbench_selected_id = build_id
	call_deferred("refresh_workbench_ui")


func on_workbench_build(build_id: StringName) -> void:
	pc._build_selected = build_id
	close_workbench()
	pc._build_from_workbench = true
	pc._enter_build_mode()


func _on_select_item(item_id: StringName) -> void:
	if pc._workbench_selected_id == item_id:
		pc._workbench_selected_id = &""
	else:
		pc._workbench_selected_id = item_id
	call_deferred("refresh_workbench_ui")


func _on_craft_btn_pressed() -> void:
	if pc._workbench_selected_id == &"":
		return
	if pc._workbench_category == "Building":
		on_workbench_build(pc._workbench_selected_id)
		return
	execute_craft(pc._workbench_selected_id)


func _update_craft_btn_state() -> void:
	if not pc._workbench_craft_btn:
		return
	var is_building := pc._workbench_category == "Building"
	var default_label := "Build" if is_building else "Craft"
	if pc._workbench_selected_id == &"":
		pc._workbench_craft_btn.disabled = true
		pc._workbench_craft_btn.text = default_label
		return

	if is_building:
		var recipe: Dictionary = {}
		for r: Dictionary in pc.BUILD_RECIPES:
			if r.get("id", &"") == pc._workbench_selected_id:
				recipe = r
				break
		if recipe.is_empty():
			pc._workbench_craft_btn.disabled = true
			pc._workbench_craft_btn.text = default_label
			return
		var can_afford := true
		if not Inventory.has_free_craft():
			for mat: Dictionary in (recipe["cost"] as Array):
				if Inventory.get_amount_any_star(mat["item"] as StringName) < int(mat["amount"]):
					can_afford = false
					break
		pc._workbench_craft_btn.text = "Build %s" % str(recipe.get("name", ""))
		pc._workbench_craft_btn.disabled = not can_afford
		return

	var data := ItemDatabase.get_item(pc._workbench_selected_id)
	if data.is_empty():
		pc._workbench_craft_btn.disabled = true
		pc._workbench_craft_btn.text = default_label
		return
	var item_type: String = str(data.get("type", "material"))
	var is_starrable := item_type in ["weapon", "armor"]
	var cfg := get_workbench_star_config()
	var eff_max: int = int(cfg["max"]) if is_starrable else 0
	var eff_min: int = int(cfg["min"]) if is_starrable else 0
	var can_make := ItemDatabase.can_craft(pc._workbench_selected_id, eff_max, eff_min)
	var item_name: String = str(data.get("name", str(pc._workbench_selected_id)))
	pc._workbench_craft_btn.text = "Craft %s" % item_name
	pc._workbench_craft_btn.disabled = not can_make


func _show_selected_detail() -> void:
	if not pc._workbench_preview_panel:
		return
	if pc._workbench_selected_id == &"":
		pc._workbench_preview_panel.visible = false
		return

	if pc._workbench_category == "Building":
		_show_building_detail()
		return

	for ch in pc._workbench_preview_panel.get_children():
		ch.queue_free()

	var item_id := pc._workbench_selected_id
	var item_data := ItemDatabase.get_item(item_id)
	if item_data.is_empty():
		pc._workbench_preview_panel.visible = false
		return

	var item_name: String = str(item_data.get("name", str(item_id)))
	var item_type: String = str(item_data.get("type", "material"))
	var is_starrable := item_type in ["weapon", "armor"]
	var recipe_var = item_data.get("recipe", [])
	var recipe_arr: Array = recipe_var if recipe_var is Array else []

	var cfg := get_workbench_star_config()
	var eff_max: int = int(cfg["max"]) if is_starrable else 0
	var eff_min: int = int(cfg["min"]) if is_starrable else 0
	var eff_low: bool = bool(cfg["prefer_low"]) if is_starrable else false

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = item_name
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vb.add_child(sep)

	var detail_rtl := RichTextLabel.new()
	detail_rtl.bbcode_enabled = true
	detail_rtl.fit_content = true
	detail_rtl.scroll_active = false
	detail_rtl.add_theme_font_size_override("normal_font_size", 13)
	detail_rtl.add_theme_font_size_override("bold_font_size", 13)
	detail_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var text := "[b]Materials Required:[/b]\n"
	for ingredient in recipe_arr:
		if not ingredient is Dictionary:
			continue
		var mat_id: StringName = StringName(str(ingredient.get("item_id", "")))
		var mat_amt: int = int(ingredient.get("amount", 0))
		var mat_data: Dictionary = ItemDatabase.get_item(mat_id)
		var mat_name: String = str(mat_data.get("name", str(mat_id)))
		var have: int = Inventory.get_amount_capped_star(mat_id, eff_max, eff_min)
		var have_color := "aaffaa" if (have >= mat_amt or Inventory.has_free_craft()) else "ff6666"
		text += "  • [color=#%s]%s  %d/%d[/color]\n" % [have_color, mat_name, have, mat_amt]

	if is_starrable:
		var using_parts: PackedStringArray = []
		for ingredient in recipe_arr:
			if not ingredient is Dictionary:
				continue
			var mat_id: StringName = StringName(str(ingredient.get("item_id", "")))
			var mat_amt: int = int(ingredient.get("amount", 0))
			var mat_name: String = str(ItemDatabase.get_item(mat_id).get("name", str(mat_id)))
			var consumed: Dictionary = Inventory.preview_consume_capped_star(mat_id, mat_amt, eff_max, eff_min, eff_low)
			for sl: int in consumed.keys():
				var qty: int = int(consumed[sl])
				if qty > 0:
					var stars_str := "★".repeat(sl) if sl > 0 else "0★"
					var col: Color = ItemDatabase.RARITY_COLORS[sl]
					var hex := "%02x%02x%02x" % [int(col.r * 255), int(col.g * 255), int(col.b * 255)]
					using_parts.append("[color=#%s]%dx %s[/color] %s" % [hex, qty, stars_str, mat_name])
		if using_parts.size() > 0:
			text += "\n[b]Materials consumed:[/b]\n" + "\n".join(using_parts)

		var avg_q: float = ItemDatabase.compute_recipe_star_avg(recipe_arr, eff_max, eff_min, eff_low)
		text += "\n\n[b]Average quality:[/b]  [color=#ffcc44]%.2f[/color]" % avg_q

		var probs: Array[float] = ItemDatabase.get_crafting_probabilities(avg_q)
		var chance_parts: PackedStringArray = []
		for ti in probs.size():
			var pct := probs[ti] * 100.0
			if pct < 0.5:
				continue
			var col: Color = ItemDatabase.RARITY_COLORS[ti]
			var hex := "%02x%02x%02x" % [int(col.r * 255), int(col.g * 255), int(col.b * 255)]
			chance_parts.append("[color=#%s]%d★  %d%%[/color]" % [hex, ti, roundi(pct)])
		if chance_parts.size() > 0:
			text += "\n\n[b]Star chances:[/b]\n" + "\n".join(chance_parts)

	detail_rtl.text = text
	vb.add_child(detail_rtl)

	pc._workbench_preview_panel.add_child(vb)
	pc._workbench_preview_panel.visible = true


func execute_craft(item_id: StringName) -> void:
	var item_data := ItemDatabase.get_item(item_id)
	var item_type: String = str(item_data.get("type", ""))
	var is_starrable := item_type in ["weapon", "armor"]
	var craft_cfg := get_workbench_star_config()
	var eff_max: int = int(craft_cfg["max"]) if is_starrable else 0
	var eff_min: int = int(craft_cfg["min"]) if is_starrable else 0
	var eff_low: bool = bool(craft_cfg["prefer_low"]) if is_starrable else false
	if item_type == "placeable":
		if not ItemDatabase.can_craft(item_id, eff_max, eff_min):
			return
		if not Inventory.has_free_craft():
			var recipe_var = item_data.get("recipe", [])
			var recipe: Array = recipe_var if recipe_var is Array else []
			for ingredient in recipe:
				if not ingredient is Dictionary:
					continue
				var req_id: StringName = StringName(str(ingredient.get("item_id", "")))
				var req_amount: int = int(ingredient.get("amount", 0))
				Inventory.remove_item_capped_star(req_id, req_amount, eff_max, eff_min, eff_low)
		close_workbench()
		pc._enter_raft_placement()
		return
	var crafted_id: StringName = ItemDatabase.craft_item_at(item_id, "workbench", eff_max, eff_min, eff_low)
	if crafted_id != &"":
		var crafted_parsed := ItemDatabase.parse_star_id(crafted_id)
		var crafted_stars: int = crafted_parsed["stars"]
		if pc._workbench_auto_discard_star >= 0 and crafted_stars <= pc._workbench_auto_discard_star:
			var craft_amount: int = int(ItemDatabase.get_item(crafted_id).get("craft_amount", 1))
			Inventory.remove_item(crafted_id, craft_amount)
			spawn_discard_text(crafted_id)
		else:
			spawn_craft_text(crafted_id)
		refresh_workbench_ui()
		pc._refresh_inventory_ui()


func _show_building_detail() -> void:
	for ch in pc._workbench_preview_panel.get_children():
		ch.queue_free()

	var recipe: Dictionary = {}
	for r: Dictionary in pc.BUILD_RECIPES:
		if r.get("id", &"") == pc._workbench_selected_id:
			recipe = r
			break
	if recipe.is_empty():
		pc._workbench_preview_panel.visible = false
		return

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = recipe["name"] as String
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	vb.add_child(sep)

	var detail_rtl := RichTextLabel.new()
	detail_rtl.bbcode_enabled = true
	detail_rtl.fit_content = true
	detail_rtl.scroll_active = false
	detail_rtl.add_theme_font_size_override("normal_font_size", 13)
	detail_rtl.add_theme_font_size_override("bold_font_size", 13)
	detail_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var text := "[b]Materials Required:[/b]\n"
	for mat: Dictionary in (recipe["cost"] as Array):
		var mat_id: StringName = mat["item"] as StringName
		var mat_amt: int = int(mat["amount"])
		var have: int = Inventory.get_amount_any_star(mat_id)
		var mat_name: String = (ItemDatabase.get_item(mat_id) as Dictionary).get("name", str(mat_id)) as String
		var have_color := "aaffaa" if (have >= mat_amt or Inventory.has_free_craft()) else "ff6666"
		text += "  • [color=#%s]%s  %d/%d[/color]\n" % [have_color, mat_name, have, mat_amt]

	detail_rtl.text = text
	vb.add_child(detail_rtl)

	pc._workbench_preview_panel.add_child(vb)
	pc._workbench_preview_panel.visible = true


func spawn_discard_text(crafted_id: StringName) -> void:
	var parsed := ItemDatabase.parse_star_id(crafted_id)
	var stars: int = parsed["stars"]
	var display := ItemDatabase.get_display_name(crafted_id)
	var num := DamageNumber.new()
	num.font_size = 24
	num.pixel_size = 0.01
	num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	num.no_depth_test = true
	num.modulate = Color(0.7, 0.3, 0.3)
	num.outline_modulate = Color.BLACK
	num.outline_size = 6
	num._velocity = Vector3(0, 1.5, 0)
	if stars > 0:
		num.text = "Trashed: %s " % display
		var star_lbl := Label3D.new()
		star_lbl.text = "★".repeat(stars)
		star_lbl.font_size = 24
		star_lbl.pixel_size = 0.01
		star_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star_lbl.no_depth_test = true
		star_lbl.modulate = ItemDatabase.get_rarity_color(stars)
		star_lbl.outline_modulate = Color.BLACK
		star_lbl.outline_size = 6
		star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		num.add_child(star_lbl)
	else:
		num.text = "Trashed: %s" % display
	pc.get_tree().current_scene.add_child(num)
	var cam := pc.get_viewport().get_camera_3d()
	var right_offset := cam.global_transform.basis.x * 5.1 if cam else Vector3(5.1, 0, 0)
	num.global_position = pc.global_position + Vector3(0, 2.5, 0) + right_offset


func spawn_craft_text(crafted_id: StringName) -> void:
	var parsed := ItemDatabase.parse_star_id(crafted_id)
	var stars: int = parsed["stars"]
	var display := ItemDatabase.get_display_name(crafted_id)
	var data := ItemDatabase.get_item(crafted_id)
	var amount: int = int(data.get("craft_amount", 1))

	var prefix := "+%d " % amount if amount > 1 else ""
	var full_text: String
	var star_text := ""
	if stars > 0:
		full_text = "%s%s " % [prefix, display]
		star_text = "★".repeat(stars)
	else:
		full_text = "%s%s" % [prefix, display]

	var lbl := RichTextLabel.new()
	lbl.bbcode_enabled = true
	lbl.fit_content = true
	lbl.scroll_active = false
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.z_index = 100

	var star_color := ItemDatabase.get_rarity_color(stars)
	var star_hex := star_color.to_html(false)
	if star_text != "":
		lbl.text = "[center]%s[color=#%s]%s[/color][/center]" % [full_text, star_hex, star_text]
	else:
		lbl.text = "[center]%s[/center]" % full_text
	lbl.add_theme_font_size_override("normal_font_size", 22)
	lbl.add_theme_color_override("default_color", Color.WHITE)
	lbl.custom_minimum_size = Vector2(400, 0)

	var anchor_pos := Vector2(pc.get_viewport().get_visible_rect().size.x * 0.5 - 200, pc.get_viewport().get_visible_rect().size.y * 0.35)
	lbl.position = anchor_pos
	pc._hud_root.add_child(lbl)

	var tween := lbl.create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", anchor_pos.y - 80.0, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.chain().tween_callback(lbl.queue_free)


func get_item_fallback_color(item_id: StringName) -> Color:
	var parsed := ItemDatabase.parse_star_id(item_id)
	var base_id: StringName = parsed["base_id"]
	match base_id:
		&"wood":       return Color(0.55, 0.35, 0.15)
		&"stone":      return Color(0.55, 0.55, 0.55)
		&"flint":      return Color(0.3, 0.3, 0.35)
		&"leather":    return Color(0.5, 0.35, 0.2)
		&"bone":       return Color(0.85, 0.82, 0.75)
		&"meat":       return Color(0.7, 0.2, 0.15)
		&"trophy_boar": return Color(0.6, 0.4, 0.2)
		&"trophy_skeleton": return Color(0.9, 0.9, 0.85)
		&"flint_axe":  return Color(0.4, 0.4, 0.45)
		&"bronze_sword": return Color(0.7, 0.55, 0.2)
		&"bronze_mace": return Color(0.65, 0.5, 0.15)
		&"iron_sword": return Color(0.5, 0.5, 0.55)
		&"gold":       return Color(0.95, 0.8, 0.2)
		&"thick_hide": return Color(0.4, 0.25, 0.12)
		&"fang":       return Color(0.9, 0.88, 0.82)
		&"ancient_bone": return Color(0.75, 0.7, 0.55)
		&"ember_stone": return Color(0.9, 0.4, 0.1)
		&"frost_shard": return Color(0.6, 0.85, 0.95)
		_:             return Color(0.6, 0.6, 0.3)
