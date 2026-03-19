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
	pc._workbench_discard_btn.tooltip_text = "Auto-discard: crafted items at or below this rarity are dropped on the ground"
	pc._workbench_discard_btn.pressed.connect(cycle_auto_discard)
	var discard_style := StyleBoxFlat.new()
	discard_style.bg_color = Color(0.15, 0.12, 0.1, 0.9)
	discard_style.border_color = Color(0.4, 0.35, 0.25)
	discard_style.set_border_width_all(1)
	discard_style.set_corner_radius_all(4)
	discard_style.set_content_margin_all(4)
	pc._workbench_discard_btn.add_theme_stylebox_override("normal", discard_style)
	title_row.add_child(pc._workbench_discard_btn)

	pc._workbench_preview_btn = Button.new()
	pc._workbench_preview_btn.text = "👁 Preview"
	pc._workbench_preview_btn.add_theme_font_size_override("font_size", 12)
	pc._workbench_preview_btn.custom_minimum_size = Vector2(86, 28)
	pc._workbench_preview_btn.tooltip_text = "Toggle craft preview: see material breakdown and star chances before crafting"
	pc._workbench_preview_btn.pressed.connect(toggle_workbench_preview)
	var preview_style := discard_style.duplicate() as StyleBoxFlat
	preview_style.border_color = Color(0.3, 0.5, 0.4)
	pc._workbench_preview_btn.add_theme_stylebox_override("normal", preview_style)
	pc._workbench_preview_btn.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
	title_row.add_child(pc._workbench_preview_btn)

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

	# Quality tier selector (Low / Medium / High) — only visible for Equipment tab
	var tier_vbox := VBoxContainer.new()
	tier_vbox.add_theme_constant_override("separation", 2)

	pc._workbench_tier_row = HBoxContainer.new()
	pc._workbench_tier_row.add_theme_constant_override("separation", 4)
	pc._workbench_tier_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pc._workbench_tier_buttons.clear()
	for tier_name in ["Low", "Medium", "High"]:
		var tbtn := Button.new()
		tbtn.text = tier_name
		tbtn.custom_minimum_size = Vector2(96, 29)
		tbtn.add_theme_font_size_override("font_size", 13)
		tbtn.pressed.connect(on_workbench_tier.bind(tier_name.to_lower()))
		pc._workbench_tier_row.add_child(tbtn)
		pc._workbench_tier_buttons.append(tbtn)
	tier_vbox.add_child(pc._workbench_tier_row)

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
		+ "Use Preview mode (👁) to see exact material consumption and star chances before crafting.[/color]"
	pc._workbench_tier_info_panel.add_child(info_rtl)
	tier_vbox.add_child(pc._workbench_tier_info_panel)

	vbox.add_child(tier_vbox)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(468, 336)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pc._workbench_grid = VBoxContainer.new()
	pc._workbench_grid.add_theme_constant_override("separation", 8)
	scroll.add_child(pc._workbench_grid)
	vbox.add_child(scroll)

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


func toggle_workbench_preview() -> void:
	pc._workbench_preview_on = not pc._workbench_preview_on
	if pc._workbench_preview_btn:
		if pc._workbench_preview_on:
			pc._workbench_preview_btn.text = "👁 Preview"
			pc._workbench_preview_btn.add_theme_color_override("font_color", Color(0.5, 0.9, 0.6))
		else:
			pc._workbench_preview_btn.text = "👁 Off"
			pc._workbench_preview_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	refresh_workbench_ui()


func on_workbench_tier(tier: String) -> void:
	pc._workbench_quality_tier = tier
	refresh_workbench_ui()


func get_workbench_star_config() -> Dictionary:
	match pc._workbench_quality_tier:
		"medium": return {"min": 1, "max": 3, "prefer_low": false}
		"high": return {"min": 3, "max": 5, "prefer_low": false}
		_: return {"min": 0, "max": 1, "prefer_low": true}


func on_workbench_tab(category: String) -> void:
	pc._workbench_category = category
	refresh_workbench_ui()


func open_workbench() -> void:
	if not pc._workbench_panel:
		return
	if pc._workbench_open:
		return
	pc._workbench_open = true
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

	# Show/hide quality tier row — only for Equipment tab
	var show_tiers := pc._workbench_category == "Equipment"
	if pc._workbench_tier_row:
		pc._workbench_tier_row.get_parent().visible = show_tiers
	if pc._workbench_tier_info_panel and not show_tiers:
		pc._workbench_tier_info_panel.visible = false
	if pc._workbench_discard_btn:
		pc._workbench_discard_btn.visible = show_tiers
	if pc._workbench_preview_btn:
		pc._workbench_preview_btn.visible = show_tiers

	# Style active tier button
	var tier_colors := {"low": Color.WHITE, "medium": Color(0.35, 0.7, 1.0), "high": Color(1.0, 0.25, 0.25)}
	for tbtn in pc._workbench_tier_buttons:
		var tier_key := tbtn.text.to_lower()
		var is_active_tier := tier_key == pc._workbench_quality_tier
		var ts := StyleBoxFlat.new()
		if is_active_tier:
			var accent: Color = tier_colors.get(tier_key, Color.WHITE)
			ts.bg_color = accent * Color(1, 1, 1, 0.25)
			ts.border_color = accent
		else:
			ts.bg_color = Color(0.12, 0.12, 0.18, 0.8)
			ts.border_color = Color(0.25, 0.24, 0.2)
		ts.set_border_width_all(1)
		ts.set_corner_radius_all(4)
		ts.set_content_margin_all(3)
		tbtn.add_theme_stylebox_override("normal", ts)
		var th := ts.duplicate() as StyleBoxFlat
		th.bg_color = ts.bg_color.lightened(0.15)
		tbtn.add_theme_stylebox_override("hover", th)
		var font_col: Color = tier_colors.get(tier_key, Color.WHITE) if is_active_tier else Color(0.6, 0.55, 0.5)
		tbtn.add_theme_color_override("font_color", font_col)

	var star_cfg := get_workbench_star_config()
	var max_star: int = star_cfg["max"]
	var min_star: int = star_cfg["min"]
	var prefer_low: bool = star_cfg["prefer_low"]

	# Building tab: show BUILD_RECIPES (same items as hammer build menu)
	if pc._workbench_category == "Building":
		populate_workbench_building_tab()
		return

	var recipes: Array = ItemDatabase.get_workbench_recipes()
	if recipes.is_empty():
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

		found_any = true
		var item_type: String = str(data.get("type", "material"))
		var is_starrable := item_type in ["weapon", "armor"]
		var eff_max: int = max_star if is_starrable else 0
		var eff_min: int = min_star if is_starrable else 0
		var eff_low: bool = prefer_low if is_starrable else false
		var can_make: bool = ItemDatabase.can_craft(item_id, eff_max, eff_min)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(43, 43)
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_tex: Texture2D = ItemDatabase.get_icon(item_id)
		if icon_tex:
			icon_rect.texture = icon_tex
		else:
			var ph := PlaceholderTexture2D.new()
			ph.size = Vector2(38, 38)
			icon_rect.texture = ph
			icon_rect.modulate = get_item_fallback_color(item_id)
		row.add_child(icon_rect)

		var info_vb := VBoxContainer.new()
		info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vb.add_theme_constant_override("separation", 2)

		var craft_amount: int = int(data.get("craft_amount", 1))
		var name_text: String = str(data.get("name", str(item_id)))
		if craft_amount > 1:
			name_text += " x%d" % craft_amount
		var name_lbl := Label.new()
		name_lbl.text = name_text
		name_lbl.add_theme_font_size_override("font_size", 15)
		name_lbl.add_theme_color_override("font_color", Color.WHITE if can_make else Color(0.5, 0.45, 0.4))
		info_vb.add_child(name_lbl)

		var recipe_arr = data.get("recipe", [])
		if not recipe_arr is Array:
			recipe_arr = []

		var cost_lbl := RichTextLabel.new()
		cost_lbl.bbcode_enabled = true
		cost_lbl.fit_content = true
		cost_lbl.scroll_active = false
		cost_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		cost_lbl.add_theme_font_size_override("normal_font_size", 12)
		cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cost_text := ""
		for j in recipe_arr.size():
			var ingredient = recipe_arr[j]
			if not ingredient is Dictionary:
				continue
			var req_id: StringName = StringName(str(ingredient.get("item_id", "")))
			var req_amt: int = int(ingredient.get("amount", 0))
			var req_data: Dictionary = ItemDatabase.get_item(req_id)
			var req_name: String = str(req_data.get("name", str(req_id)))
			var have: int = Inventory.get_amount_capped_star(req_id, eff_max, eff_min)
			var have_color := "aaffaa" if have >= req_amt else "ff6666"
			if cost_text != "":
				cost_text += "  "
			cost_text += "[color=#%s]%s %d/%d[/color]" % [have_color, req_name, have, req_amt]
		cost_lbl.text = cost_text
		info_vb.add_child(cost_lbl)

		row.add_child(info_vb)

		var btn := Button.new()
		if pc._workbench_preview_on and is_starrable:
			btn.text = "Preview"
		else:
			btn.text = "Craft"
		btn.disabled = not can_make
		btn.custom_minimum_size = Vector2(72, 36)
		btn.pressed.connect(on_workbench_craft.bind(item_id))
		row.add_child(btn)

		pc._workbench_grid.add_child(row)

	if not found_any:
		var empty_lbl := Label.new()
		empty_lbl.text = "No recipes in this category."
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pc._workbench_grid.add_child(empty_lbl)


func get_build_icon(recipe_id: StringName) -> Texture2D:
	var path := "res://textures/items/%s.png" % str(recipe_id)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func populate_workbench_building_tab() -> void:
	for recipe: Dictionary in pc.BUILD_RECIPES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var recipe_id: StringName = recipe["id"] as StringName
		var icon_tex := get_build_icon(recipe_id)
		if icon_tex:
			var tex_rect := TextureRect.new()
			tex_rect.texture = icon_tex
			tex_rect.custom_minimum_size = Vector2(43, 43)
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(tex_rect)
		else:
			var color_rect := ColorRect.new()
			color_rect.custom_minimum_size = Vector2(43, 43)
			color_rect.color = recipe.get("color", Color(0.4, 0.3, 0.15)) as Color
			row.add_child(color_rect)

		var info_vb := VBoxContainer.new()
		info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vb.add_theme_constant_override("separation", 2)

		var name_lbl := Label.new()
		name_lbl.add_theme_font_size_override("font_size", 15)

		var cost_text := ""
		var can_afford := true
		for mat: Dictionary in (recipe["cost"] as Array):
			var mat_id: StringName = mat["item"] as StringName
			var mat_amt: int = int(mat["amount"])
			var have: int = Inventory.get_amount_any_star(mat_id)
			var mat_name: String = (ItemDatabase.get_item(mat_id) as Dictionary).get("name", str(mat_id)) as String
			if have < mat_amt:
				can_afford = false
			var have_color := "aaffaa" if have >= mat_amt else "ff6666"
			if cost_text != "":
				cost_text += "  "
			cost_text += "[color=#%s]%s %d/%d[/color]" % [have_color, mat_name, have, mat_amt]

		var tab_name: String = recipe.get("tab", "Misc") as String
		var display_name: String = recipe["name"] as String
		name_lbl.text = display_name
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7) if can_afford else Color(0.5, 0.45, 0.4))
		info_vb.add_child(name_lbl)

		var cost_lbl := RichTextLabel.new()
		cost_lbl.bbcode_enabled = true
		cost_lbl.text = cost_text
		cost_lbl.fit_content = true
		cost_lbl.scroll_active = false
		cost_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		cost_lbl.custom_minimum_size.y = 19
		cost_lbl.add_theme_font_size_override("normal_font_size", 12)
		cost_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_vb.add_child(cost_lbl)
		row.add_child(info_vb)

		var btn := Button.new()
		btn.text = "Build"
		btn.disabled = not can_afford
		btn.custom_minimum_size = Vector2(72, 36)
		btn.pressed.connect(on_workbench_build.bind(recipe_id))
		row.add_child(btn)

		pc._workbench_grid.add_child(row)


func on_workbench_build(build_id: StringName) -> void:
	pc._build_selected = build_id
	close_workbench()
	pc._build_from_workbench = true
	pc._enter_build_mode()


func on_workbench_craft(item_id: StringName) -> void:
	var item_data := ItemDatabase.get_item(item_id)
	var item_type: String = str(item_data.get("type", ""))
	var is_starrable := item_type in ["weapon", "armor"]
	if pc._workbench_preview_on and is_starrable:
		show_craft_preview(item_id)
		return
	execute_craft(item_id)


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
			pc._drop_item_on_ground(crafted_id, craft_amount, 60.0)
			spawn_discard_text(crafted_id)
		else:
			spawn_craft_text(crafted_id)
		refresh_workbench_ui()
		pc._refresh_inventory_ui()


func show_craft_preview(item_id: StringName) -> void:
	if not pc._workbench_preview_panel:
		return
	for ch in pc._workbench_preview_panel.get_children():
		ch.queue_free()

	var item_data := ItemDatabase.get_item(item_id)
	var item_name: String = str(item_data.get("name", str(item_id)))
	var recipe_var = item_data.get("recipe", [])
	var recipe_arr: Array = recipe_var if recipe_var is Array else []

	var cfg := get_workbench_star_config()
	var eff_max: int = cfg["max"]
	var eff_min: int = cfg["min"]
	var eff_low: bool = cfg["prefer_low"]

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)

	var title := Label.new()
	title.text = "Craft Preview — %s" % item_name
	title.add_theme_font_size_override("font_size", 16)
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
	detail_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var text := ""

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
		text += "[b]Materials consumed:[/b]\n" + "\n".join(using_parts)

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

	var sep2 := HSeparator.new()
	sep2.add_theme_constant_override("separation", 6)
	vb.add_child(sep2)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER

	var craft_btn := Button.new()
	craft_btn.text = "Confirm Craft"
	craft_btn.custom_minimum_size = Vector2(120, 36)
	craft_btn.add_theme_font_size_override("font_size", 14)
	craft_btn.pressed.connect(func():
		pc._workbench_preview_panel.visible = false
		execute_craft(item_id)
	)
	btn_row.add_child(craft_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(80, 36)
	cancel_btn.add_theme_font_size_override("font_size", 14)
	cancel_btn.pressed.connect(func():
		pc._workbench_preview_panel.visible = false
	)
	btn_row.add_child(cancel_btn)

	vb.add_child(btn_row)

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
		num.text = "Discarded: %s " % display
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
		num.text = "Discarded: %s" % display
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

	var num := DamageNumber.new()
	num.font_size = 28
	num.pixel_size = 0.01
	num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	num.no_depth_test = true
	num.modulate = Color.WHITE
	num.outline_modulate = Color.BLACK
	num.outline_size = 6
	num._velocity = Vector3(0, 2.0, 0)

	var prefix := "+%d " % amount if amount > 1 else ""
	if stars > 0:
		num.text = "%s%s " % [prefix, display]
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var star_lbl := Label3D.new()
		star_lbl.text = "★".repeat(stars)
		star_lbl.font_size = 28
		star_lbl.pixel_size = 0.01
		star_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star_lbl.no_depth_test = true
		star_lbl.modulate = ItemDatabase.get_rarity_color(stars)
		star_lbl.outline_modulate = Color.BLACK
		star_lbl.outline_size = 6
		star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		num.add_child(star_lbl)
	else:
		num.text = "%s%s" % [prefix, display]

	pc.get_tree().current_scene.add_child(num)
	var cam := pc.get_viewport().get_camera_3d()
	var right_offset := cam.global_transform.basis.x * 5.1 if cam else Vector3(5.1, 0, 0)
	num.global_position = pc.global_position + Vector3(0, 2.5, 0) + right_offset


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
