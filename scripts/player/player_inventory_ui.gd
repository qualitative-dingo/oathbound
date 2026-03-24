class_name PlayerInventoryUI
extends Node

const _DamageNumber := preload("res://scripts/ui/damage_number.gd")
const _LootDrop := preload("res://scripts/items/loot_drop.gd")

var pc: PlayerController


func get_hotbar_items() -> Array[StringName]:
	var grouped: Array = Inventory.get_grouped_item_list()
	var result: Array[StringName] = []
	for i in range(8):
		if i < grouped.size():
			var entry: Dictionary = grouped[i]
			result.append(entry.get("exact_id", entry["base_id"]) as StringName)
		else:
			result.append(&"")
	return result


func toggle_inventory() -> void:
	pc._auto_run = false
	pc._inventory_open = not pc._inventory_open
	if pc._inventory_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if pc._inventory_panel:
			pc._inventory_panel.visible = true
		if pc._crafting_panel:
			pc._crafting_panel.visible = true
		if pc._stats_arrow:
			pc._stats_arrow.visible = true
		if pc._stats_open and pc._stats_panel:
			pc._stats_panel.visible = true
		refresh_inventory_ui()
		position_stats_panel.call_deferred()
		if pc._stats_open:
			refresh_stats_panel()
	else:
		close_inventory()


func close_inventory() -> void:
	pc._inventory_open = false
	cancel_drag()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if pc._inventory_panel:
		pc._inventory_panel.visible = false
	if pc._crafting_panel:
		pc._crafting_panel.visible = false
	if pc._stats_arrow:
		pc._stats_arrow.visible = false
	if pc._stats_panel:
		pc._stats_panel.visible = false


func toggle_map() -> void:
	pc._map_open = not pc._map_open
	if pc._map_open:
		pc._map_zoom = pc._map_zoom_target
		pc._map_dirty = true
		if pc._map_panel:
			pc._map_panel.visible = true
		pc._refresh_map()
		pc._map_dirty = false
	else:
		close_map()


func close_map() -> void:
	pc._map_open = false
	if pc._map_panel:
		pc._map_panel.visible = false


func build_inventory_panel(root: Control) -> void:
	# --- Inventory window (top-left) ---
	pc._inventory_panel = PanelContainer.new()
	pc._inventory_panel.name = "InventoryPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	style.border_color = Color(0.4, 0.35, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	pc._inventory_panel.add_theme_stylebox_override("panel", style)

	pc._inventory_panel.anchor_left = 0.0
	pc._inventory_panel.anchor_right = 0.0
	pc._inventory_panel.anchor_top = 0.0
	pc._inventory_panel.anchor_bottom = 0.0
	pc._inventory_panel.offset_left = 30
	pc._inventory_panel.offset_top = 30
	pc._inventory_panel.visible = false
	pc._inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var inv_vbox := VBoxContainer.new()
	inv_vbox.add_theme_constant_override("separation", 8)

	var inv_title := Label.new()
	inv_title.text = "INVENTORY"
	inv_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	inv_title.add_theme_font_size_override("font_size", 20)
	inv_vbox.add_child(inv_title)

	var inv_sep := HSeparator.new()
	inv_vbox.add_child(inv_sep)

	var inv_scroll := ScrollContainer.new()
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inv_scroll.custom_minimum_size.y = 4 * 60 + 3 * 4

	pc._inventory_grid = GridContainer.new()
	pc._inventory_grid.columns = 8
	pc._inventory_grid.add_theme_constant_override("h_separation", 4)
	pc._inventory_grid.add_theme_constant_override("v_separation", 4)
	inv_scroll.add_child(pc._inventory_grid)
	inv_vbox.add_child(inv_scroll)

	build_equip_bar(inv_vbox)

	pc._inventory_panel.add_child(inv_vbox)
	root.add_child(pc._inventory_panel)

	build_stats_panel(root)
	refresh_equip_bar()

	# --- Crafting window (right side, vertically centered) ---
	pc._crafting_panel = PanelContainer.new()
	pc._crafting_panel.name = "CraftingPanel"
	var craft_style := StyleBoxFlat.new()
	craft_style.bg_color = Color(0.1, 0.09, 0.14, 0.92)
	craft_style.border_color = Color(0.35, 0.3, 0.2)
	craft_style.set_border_width_all(2)
	craft_style.set_corner_radius_all(6)
	craft_style.set_content_margin_all(14)
	pc._crafting_panel.add_theme_stylebox_override("panel", craft_style)

	pc._crafting_panel.anchor_left = 1.0
	pc._crafting_panel.anchor_right = 1.0
	pc._crafting_panel.anchor_top = 0.1
	pc._crafting_panel.anchor_bottom = 0.7
	pc._crafting_panel.offset_left = -510
	pc._crafting_panel.offset_right = -200
	pc._crafting_panel.visible = false
	pc._crafting_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var craft_vbox := VBoxContainer.new()
	craft_vbox.add_theme_constant_override("separation", 6)

	var title_row := HBoxContainer.new()
	var craft_title := Label.new()
	craft_title.text = "CRAFTING"
	craft_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	craft_title.add_theme_font_size_override("font_size", 20)
	craft_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(craft_title)

	var info_btn := Button.new()
	info_btn.text = "i"
	info_btn.custom_minimum_size = Vector2(26, 26)
	info_btn.add_theme_font_size_override("font_size", 14)
	info_btn.tooltip_text = "Material Quality Info"
	title_row.add_child(info_btn)
	craft_vbox.add_child(title_row)

	var info_panel := PanelContainer.new()
	info_panel.visible = false
	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	info_style.border_color = Color(0.4, 0.35, 0.25, 0.6)
	info_style.set_border_width_all(1)
	info_style.set_corner_radius_all(4)
	info_style.set_content_margin_all(10)
	info_panel.add_theme_stylebox_override("panel", info_style)

	var info_rtl := RichTextLabel.new()
	info_rtl.bbcode_enabled = true
	info_rtl.fit_content = true
	info_rtl.scroll_active = false
	info_rtl.add_theme_font_size_override("normal_font_size", 11)
	info_rtl.text = "[color=#e6c84a]★ Material Quality System[/color]\n\n" \
		+ "[color=#aaaaaa]Items can drop with [/color][color=#ffffff]star ratings (0-5★)[/color][color=#aaaaaa] from monsters and resources. " \
		+ "Higher stars = better quality.[/color]\n\n" \
		+ "[color=#e6c84a]Non-Equipment Crafting[/color]\n" \
		+ "[color=#aaaaaa]Building pieces, tools, arrows, and other non-equipment recipes " \
		+ "only consume [/color][color=#ffffff]unstarred (0★)[/color][color=#aaaaaa] materials. " \
		+ "Your starred materials are kept safe for equipment crafting.[/color]\n\n" \
		+ "[color=#e6c84a]Equipment Crafting[/color]\n" \
		+ "[color=#aaaaaa]Weapons and armor use starred materials based on the quality tier " \
		+ "selected at the workbench. The star quality of ingredients affects the outcome.[/color]"
	info_panel.add_child(info_rtl)
	craft_vbox.add_child(info_panel)
	info_btn.pressed.connect(func(): info_panel.visible = not info_panel.visible)

	var craft_sep := HSeparator.new()
	craft_vbox.add_child(craft_sep)

	var craft_scroll := ScrollContainer.new()
	craft_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	craft_scroll.mouse_filter = Control.MOUSE_FILTER_PASS

	pc._crafting_grid = VBoxContainer.new()
	pc._crafting_grid.add_theme_constant_override("separation", 8)
	craft_scroll.add_child(pc._crafting_grid)
	craft_vbox.add_child(craft_scroll)

	pc._crafting_panel.add_child(craft_vbox)
	root.add_child(pc._crafting_panel)


func build_equip_bar(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.color = Color(0.5, 0.42, 0.28, 0.8)
	sep_style.content_margin_top = 4
	sep_style.content_margin_bottom = 4
	sep.add_theme_stylebox_override("separator", sep_style)
	parent.add_child(sep)

	const GHOST_ICONS := {
		"weapon": "res://textures/items/stone_axe.png",
		"sword": "res://textures/items/stone_sword.png",
		"bow": "res://textures/items/crude_bow.png",
		"pickaxe": "res://textures/items/stone_pickaxe.png",
		"shield": "res://textures/items/wood_shield.png",
		"chest": "res://textures/items/leather_vest.png",
		"legs": "res://textures/items/leather_pants.png",
		"feet": "res://textures/items/leather_boots.png",
	}
	const SLOT_LABELS := {
		"weapon": "Woodaxe",
		"sword": "Melee",
		"bow": "Ranged",
		"pickaxe": "Pick",
		"shield": "Shield",
		"chest": "Chest",
		"legs": "Legs",
		"feet": "Boots",
	}
	const TOOL_SLOTS: Array[String] = ["weapon", "pickaxe"]
	const EQUIP_SLOTS: Array[String] = ["sword", "bow", "shield", "chest", "legs", "feet"]

	var wrapper := PanelContainer.new()
	var wrapper_style := StyleBoxFlat.new()
	wrapper_style.bg_color = Color(0.06, 0.055, 0.04, 0.5)
	wrapper_style.set_corner_radius_all(4)
	wrapper_style.set_content_margin_all(6)
	wrapper.add_theme_stylebox_override("panel", wrapper_style)

	var equip_vbox := VBoxContainer.new()
	equip_vbox.add_theme_constant_override("separation", 4)

	var tools_lbl := Label.new()
	tools_lbl.text = "TOOLS"
	tools_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.4))
	tools_lbl.add_theme_font_size_override("font_size", 11)
	equip_vbox.add_child(tools_lbl)

	var tools_row := HBoxContainer.new()
	tools_row.add_theme_constant_override("separation", 4)
	equip_vbox.add_child(tools_row)

	var equip_lbl := Label.new()
	equip_lbl.text = "EQUIPMENT"
	equip_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.4))
	equip_lbl.add_theme_font_size_override("font_size", 11)
	equip_vbox.add_child(equip_lbl)

	var equip_row := HBoxContainer.new()
	equip_row.add_theme_constant_override("separation", 4)
	equip_vbox.add_child(equip_row)

	var all_slots: Array[String] = []
	all_slots.append_array(TOOL_SLOTS)
	all_slots.append_array(EQUIP_SLOTS)
	for slot_name in all_slots:
		var target_row: HBoxContainer = tools_row if slot_name in TOOL_SLOTS else equip_row

		var slot_col := VBoxContainer.new()
		slot_col.add_theme_constant_override("separation", 2)

		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(60, 60)
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(0.12, 0.11, 0.08, 0.9)
		slot_style.border_color = Color(0.45, 0.38, 0.22)
		slot_style.set_border_width_all(1)
		slot_style.set_corner_radius_all(4)
		slot_style.set_content_margin_all(2)
		slot.add_theme_stylebox_override("panel", slot_style)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP

		var stack := Control.new()
		stack.custom_minimum_size = Vector2(56, 56)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var ghost := TextureRect.new()
		ghost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ghost.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.modulate = Color(1, 1, 1, 0.25)
		var ghost_path: String = GHOST_ICONS.get(slot_name, "")
		if ghost_path != "" and ResourceLoader.exists(ghost_path):
			ghost.texture = load(ghost_path) as Texture2D
		stack.add_child(ghost)
		pc._equip_bar_ghost[slot_name] = ghost

		var icon := TextureRect.new()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false
		stack.add_child(icon)
		pc._equip_bar_icons[slot_name] = icon

		slot.add_child(stack)
		slot.gui_input.connect(on_equip_bar_slot_input.bind(slot_name))
		slot.mouse_entered.connect(on_equip_bar_hover.bind(slot_name))
		slot.mouse_exited.connect(hide_tooltip)
		pc._equip_bar_slots[slot_name] = slot
		slot_col.add_child(slot)

		var lbl := Label.new()
		lbl.text = SLOT_LABELS.get(slot_name, slot_name)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.55, 0.5, 0.38))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size.x = 60
		slot_col.add_child(lbl)

		target_row.add_child(slot_col)

	wrapper.add_child(equip_vbox)
	parent.add_child(wrapper)
	pc._equip_bar = wrapper


func refresh_equip_bar() -> void:
	if not pc._equip_bar:
		return
	const SLOT_ORDER: Array[String] = ["weapon", "sword", "bow", "pickaxe", "shield", "chest", "legs", "feet"]
	for slot_name in SLOT_ORDER:
		var eq_id: StringName = Inventory.get_equipped(slot_name)
		var icon: TextureRect = pc._equip_bar_icons.get(slot_name) as TextureRect
		var ghost: TextureRect = pc._equip_bar_ghost.get(slot_name) as TextureRect
		var slot_panel: PanelContainer = pc._equip_bar_slots.get(slot_name) as PanelContainer
		if not icon or not ghost or not slot_panel:
			continue

		if eq_id != &"":
			var tex: Texture2D = ItemDatabase.get_icon(eq_id)
			if tex:
				icon.texture = tex
				icon.visible = true
			else:
				icon.visible = false
			ghost.visible = false

			var parsed := ItemDatabase.parse_star_id(eq_id)
			var stars: int = parsed["stars"]
			var eq_data: Dictionary = ItemDatabase.get_item(eq_id)
			var style: StyleBoxFlat = slot_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			if stars > 0:
				style.border_color = ItemDatabase.get_rarity_color(stars)
				style.set_border_width_all(2)
			elif eq_data.has("quality_color"):
				style.border_color = (eq_data["quality_color"] as Color).darkened(0.3)
				style.set_border_width_all(1)
			else:
				style.border_color = Color(0.45, 0.38, 0.22)
				style.set_border_width_all(1)
			slot_panel.add_theme_stylebox_override("panel", style)
		else:
			icon.visible = false
			ghost.visible = true
			var style: StyleBoxFlat = slot_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			style.border_color = Color(0.45, 0.38, 0.22)
			style.set_border_width_all(1)
			slot_panel.add_theme_stylebox_override("panel", style)


func on_equip_bar_slot_input(event: InputEvent, slot_name: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var eq_id: StringName = Inventory.get_equipped(slot_name)
			if eq_id != &"":
				unequip_item_deferred.call_deferred(slot_name)


func try_drop_on_equip_bar() -> bool:
	if pc._dragging_item == &"" or not pc._hud_root:
		return false
	var mouse_pos := pc._hud_root.get_global_mouse_position()
	for slot_name: String in pc._equip_bar_slots.keys():
		var panel: PanelContainer = pc._equip_bar_slots[slot_name] as PanelContainer
		if panel and panel.get_global_rect().has_point(mouse_pos):
			var data: Dictionary = ItemDatabase.get_item(pc._dragging_item)
			var item_type: String = str(data.get("type", ""))
			var item_slot: String = str(data.get("armor_slot", ""))
			if (item_type == "weapon" or item_type == "armor") and item_slot == slot_name:
				Inventory.equip_armor(pc._dragging_item)
				refresh_inventory_ui()
				refresh_equip_bar()
			cancel_drag()
			return true
	return false


func on_equip_bar_hover(slot_name: String) -> void:
	var eq_id: StringName = Inventory.get_equipped(slot_name)
	if eq_id != &"":
		show_tooltip_for_item(eq_id)
	else:
		const SLOT_LABELS := {"weapon": "Woodaxe", "sword": "Melee", "bow": "Ranged", "pickaxe": "Pickaxe", "shield": "Shield", "chest": "Chest Armor", "legs": "Leg Armor", "feet": "Boots"}
		var hint: String = SLOT_LABELS.get(slot_name, slot_name)
		if pc._tooltip_label and pc._tooltip_panel:
			pc._tooltip_label.text = "[color=#888888]Empty %s slot[/color]" % hint
			pc._tooltip_panel.visible = true


func build_stats_panel(root: Control) -> void:
	pc._stats_arrow = Button.new()
	pc._stats_arrow.name = "StatsArrow"
	pc._stats_arrow.text = "▶"
	pc._stats_arrow.custom_minimum_size = Vector2(20, 60)
	pc._stats_arrow.add_theme_font_size_override("font_size", 14)
	pc._stats_arrow.add_theme_color_override("font_color", Color(0.8, 0.75, 0.55))
	var arrow_style := StyleBoxFlat.new()
	arrow_style.bg_color = Color(0.12, 0.12, 0.16, 0.9)
	arrow_style.border_color = Color(0.4, 0.35, 0.25)
	arrow_style.set_border_width_all(1)
	arrow_style.border_width_left = 0
	arrow_style.set_corner_radius_all(0)
	arrow_style.corner_radius_top_right = 4
	arrow_style.corner_radius_bottom_right = 4
	arrow_style.set_content_margin_all(2)
	pc._stats_arrow.add_theme_stylebox_override("normal", arrow_style)
	var arrow_hover := arrow_style.duplicate() as StyleBoxFlat
	arrow_hover.bg_color = Color(0.18, 0.18, 0.22, 0.95)
	pc._stats_arrow.add_theme_stylebox_override("hover", arrow_hover)
	pc._stats_arrow.add_theme_stylebox_override("pressed", arrow_hover)
	pc._stats_arrow.visible = false
	pc._stats_arrow.mouse_filter = Control.MOUSE_FILTER_STOP
	pc._stats_arrow.pressed.connect(toggle_stats_panel)
	root.add_child(pc._stats_arrow)

	pc._stats_panel = PanelContainer.new()
	pc._stats_panel.name = "StatsPanel"
	var sp_style := StyleBoxFlat.new()
	sp_style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	sp_style.border_color = Color(0.4, 0.35, 0.25)
	sp_style.set_border_width_all(2)
	sp_style.border_width_left = 0
	sp_style.set_corner_radius_all(0)
	sp_style.corner_radius_top_right = 6
	sp_style.corner_radius_bottom_right = 6
	sp_style.set_content_margin_all(12)
	pc._stats_panel.add_theme_stylebox_override("panel", sp_style)
	pc._stats_panel.visible = false
	pc._stats_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(pc._stats_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "CHARACTER"
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var stat_keys: Array[String] = [
		"strength", "dexterity", "vitality",
		"_sep1",
		"crit_chance", "crit_damage",
		"_sep2",
		"weapon", "attack_speed", "dps",
		"_sep3",
		"armor",
	]
	var stat_display: Dictionary = {
		"strength": "Strength",
		"dexterity": "Dexterity",
		"vitality": "Vitality",
		"crit_chance": "Crit Chance",
		"crit_damage": "Crit Damage",
		"weapon": "Weapon",
		"attack_speed": "Attack Speed",
		"dps": "DPS",
		"armor": "Armor",
	}

	for key in stat_keys:
		if key.begins_with("_sep"):
			var s2 := HSeparator.new()
			s2.modulate = Color(1, 1, 1, 0.3)
			vbox.add_child(s2)
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var name_lbl := Label.new()
		name_lbl.text = stat_display.get(key, key)
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var val_lbl := Label.new()
		val_lbl.text = "—"
		val_lbl.add_theme_font_size_override("font_size", 12)
		val_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
		pc._stats_labels[key] = val_lbl

		vbox.add_child(row)

	pc._stats_panel.add_child(vbox)


func toggle_stats_panel() -> void:
	pc._stats_open = not pc._stats_open
	pc._stats_panel.visible = pc._stats_open
	pc._stats_arrow.text = "◀" if pc._stats_open else "▶"
	if pc._stats_open:
		refresh_stats_panel()
		position_stats_panel()


func position_stats_panel() -> void:
	if not pc._inventory_panel or not pc._stats_arrow:
		return
	var inv_rect := pc._inventory_panel.get_rect()
	var right_edge := inv_rect.position.x + inv_rect.size.x
	var top := inv_rect.position.y + 40.0

	pc._stats_arrow.position = Vector2(right_edge, top)
	if pc._stats_open and pc._stats_panel:
		pc._stats_panel.position = Vector2(right_edge + pc._stats_arrow.size.x, top)


func refresh_stats_panel() -> void:
	if not pc._stats_open:
		return

	var str_val := pc.base_strength
	var dex_val := pc.base_dexterity
	var vit_val := pc.base_vitality

	var crit_chance := 5.0 + dex_val * 0.5
	var crit_dmg := 150.0 + str_val * 2.0

	var wpn_data := ItemDatabase.get_item(pc.equipped_weapon)
	var wpn_name: String = wpn_data.get("name", "Fists") as String
	var wpn_damage: float = float(wpn_data.get("damage", 5.0))
	var wpn_speed: float = float(wpn_data.get("attack_speed", 1.0))
	var hits_per_sec := 1.0 / maxf(wpn_speed, 0.1)
	var base_dps := wpn_damage * hits_per_sec
	var effective_dps := base_dps * (1.0 + (crit_chance / 100.0) * ((crit_dmg - 100.0) / 100.0))

	var armor_val := Inventory.get_total_armor()

	if pc._stats_labels.has("strength"):
		(pc._stats_labels["strength"] as Label).text = str(str_val)
	if pc._stats_labels.has("dexterity"):
		(pc._stats_labels["dexterity"] as Label).text = str(dex_val)
	if pc._stats_labels.has("vitality"):
		(pc._stats_labels["vitality"] as Label).text = str(vit_val)
	if pc._stats_labels.has("crit_chance"):
		(pc._stats_labels["crit_chance"] as Label).text = "%.1f%%" % crit_chance
	if pc._stats_labels.has("crit_damage"):
		(pc._stats_labels["crit_damage"] as Label).text = "%.0f%%" % crit_dmg
	if pc._stats_labels.has("weapon"):
		(pc._stats_labels["weapon"] as Label).text = wpn_name
	if pc._stats_labels.has("attack_speed"):
		(pc._stats_labels["attack_speed"] as Label).text = "%.2fs" % wpn_speed
	if pc._stats_labels.has("dps"):
		(pc._stats_labels["dps"] as Label).text = "%.1f" % effective_dps
		(pc._stats_labels["dps"] as Label).add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	if pc._stats_labels.has("armor"):
		(pc._stats_labels["armor"] as Label).text = "%.0f" % armor_val


func build_tooltip(root: Control) -> void:
	pc._tooltip_panel = PanelContainer.new()
	pc._tooltip_panel.name = "Tooltip"
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	s.border_color = Color(0.5, 0.45, 0.3)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(10)
	pc._tooltip_panel.add_theme_stylebox_override("panel", s)
	pc._tooltip_panel.visible = false
	pc._tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc._tooltip_panel.z_index = 100

	pc._tooltip_label = RichTextLabel.new()
	pc._tooltip_label.bbcode_enabled = true
	pc._tooltip_label.fit_content = true
	pc._tooltip_label.scroll_active = false
	pc._tooltip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	pc._tooltip_label.custom_minimum_size = Vector2(180, 0)
	pc._tooltip_label.add_theme_font_size_override("normal_font_size", 12)
	pc._tooltip_label.add_theme_color_override("default_color", Color.WHITE)
	pc._tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc._tooltip_panel.add_child(pc._tooltip_label)
	root.add_child(pc._tooltip_panel)


func build_drag_icon(root: Control) -> void:
	pc._drag_icon = TextureRect.new()
	pc._drag_icon.custom_minimum_size = Vector2(32, 32)
	pc._drag_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	pc._drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pc._drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc._drag_icon.visible = false
	pc._drag_icon.z_index = 200
	pc._drag_icon.modulate = Color(1, 1, 1, 0.8)
	root.add_child(pc._drag_icon)


func show_tooltip_for_item(item_id: StringName) -> void:
	if item_id == &"" or not pc._tooltip_panel:
		hide_tooltip()
		return
	var data: Dictionary = ItemDatabase.get_item(item_id)
	if data.is_empty():
		hide_tooltip()
		return

	var display_name := ItemDatabase.get_display_name(item_id)
	var parsed_tip := ItemDatabase.parse_star_id(item_id)
	var tip_stars: int = parsed_tip["stars"]

	var text := ""
	if tip_stars > 0:
		var rc: Color = ItemDatabase.get_rarity_color(tip_stars)
		var hex := "#%02x%02x%02x" % [int(rc.r * 255), int(rc.g * 255), int(rc.b * 255)]
		var rarity_name: String = ItemDatabase.RARITY_NAMES[clampi(tip_stars, 0, 5)]
		text += "[color=%s][b]%s[/b] %s[/color]\n" % [hex, display_name, "★".repeat(tip_stars)]
		text += "[color=%s]%s[/color]\n" % [hex, rarity_name]
	elif data.has("quality_color"):
		var qc: Color = data["quality_color"] as Color
		var qhex := "#%02x%02x%02x" % [int(qc.r * 255), int(qc.g * 255), int(qc.b * 255)]
		var qname: String = data.get("quality_name", "Poor") as String
		text += "[color=%s][b]%s[/b][/color]\n" % [qhex, display_name]
		text += "[color=%s]%s[/color]\n" % [qhex, qname]
	else:
		text += "[b]%s[/b]\n" % display_name

	var item_type: String = data.get("type", "material") as String
	if item_type == "weapon" and data.has("weapon_class"):
		text += "Type: %s\n" % str(data["weapon_class"]).capitalize()
	elif item_type == "armor" and data.has("armor_slot"):
		text += "Type: %s Armor\n" % str(data["armor_slot"]).capitalize()
	else:
		text += "Type: %s\n" % item_type.capitalize()

	if data.has("damage"):
		text += "Damage: %.0f\n" % float(data["damage"])
	if data.has("attack_speed"):
		text += "Speed: %.2fs\n" % float(data["attack_speed"])
	if data.has("range"):
		text += "Range: %.1f\n" % float(data["range"])
	if data.has("stamina_cost"):
		text += "Stamina: %.0f\n" % float(data["stamina_cost"])
	if data.has("knockback"):
		text += "Knockback: %.0f\n" % float(data["knockback"])
	if data.has("hands"):
		text += "Hands: %s\n" % str(data["hands"])
	if data.has("armor"):
		var armor_f := float(data["armor"])
		text += "Armor: %.1f\n" % armor_f
	if data.has("description"):
		text += "\n%s" % str(data["description"])

	# Affixes section
	var tip_affixes: Array = parsed_tip.get("affixes", [])
	var tip_rolls: Dictionary = parsed_tip.get("affix_rolls", {})
	if not tip_affixes.is_empty():
		text += "\n\n[color=#666666]───────────────[/color]"
		for affix_id in tip_affixes:
			var affix_data: Dictionary = ItemDatabase.get_affix_data(affix_id)
			if affix_data.is_empty():
				continue
			var affix_name: String = affix_data.get("name", str(affix_id)) as String
			var roll: float = float(tip_rolls.get(affix_id, 0.5))
			var affix_desc: String = ItemDatabase.format_affix_description(affix_id, roll)
			text += "\n[color=#ffd700]%s[/color]" % affix_name
			if affix_desc != "":
				text += "\n[color=#aaaaaa]%s[/color]" % affix_desc

	pc._tooltip_label.text = text.strip_edges()
	pc._tooltip_panel.reset_size()
	pc._tooltip_panel.visible = true
	pc._tooltip_panel.position = pc._hud_root.get_local_mouse_position() + Vector2(16, 8)


func show_grouped_tooltip(base_id: StringName, variants: Dictionary, display_id: StringName) -> void:
	if not pc._tooltip_panel:
		return
	var data: Dictionary = ItemDatabase.get_item(base_id)
	if data.is_empty():
		data = ItemDatabase.get_item(display_id)
	if data.is_empty():
		hide_tooltip()
		return

	var display_name: String = str(data.get("name", str(base_id)))
	var item_type: String = str(data.get("type", "material"))

	var total := 0
	var max_stars := 0
	for sv in variants.keys():
		if int(sv) > max_stars:
			max_stars = int(sv)
		total += int(variants[sv])

	var text := "[b]%s[/b]  ×%d\n" % [display_name, total]
	text += "Type: %s\n" % item_type.capitalize()

	if data.has("damage"):
		text += "Damage: %.0f\n" % float(data["damage"])
	if data.has("armor"):
		text += "Armor: %.0f\n" % float(data["armor"])
	if data.has("armor_slot"):
		text += "Slot: %s\n" % str(data["armor_slot"]).capitalize()
	if Inventory.is_equipped(display_id):
		text += "◆ Equipped\n"
		text += "[color=#999999]Right-click to unequip[/color]\n"
	elif data.has("armor_slot"):
		text += "[color=#999999]Right-click to equip[/color]\n"

	if variants.size() > 1 or max_stars > 0:
		text += "\nQuality breakdown:\n"
		var star_keys: Array = variants.keys()
		star_keys.sort()
		for sv in star_keys:
			var s: int = int(sv)
			var amt: int = int(variants[sv])
			var rarity_name := ItemDatabase.get_rarity_name(s)
			var c: Color = ItemDatabase.get_rarity_color(s)
			var hex := "#%02x%02x%02x" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]
			if s == 0:
				text += "  [color=%s]Common: %d[/color]\n" % [hex, amt]
			else:
				text += "  [color=%s]%s %s: %d[/color]\n" % [hex, "★".repeat(s), rarity_name, amt]

	if data.has("description"):
		text += "\n%s" % str(data["description"])

	pc._tooltip_label.text = text.strip_edges()
	pc._tooltip_panel.reset_size()
	pc._tooltip_panel.visible = true
	pc._tooltip_panel.position = pc._hud_root.get_local_mouse_position() + Vector2(16, 8)


func hide_tooltip() -> void:
	if pc._tooltip_panel:
		pc._tooltip_panel.visible = false


func on_hotbar_hover(slot_idx: int) -> void:
	var grouped: Array = Inventory.get_grouped_item_list()
	if slot_idx >= 0 and slot_idx < grouped.size():
		var entry: Dictionary = grouped[slot_idx]
		var base_id: StringName = entry["base_id"]
		var variants: Dictionary = entry["variants"]
		var display_id: StringName = entry.get("exact_id", base_id) as StringName
		if entry.get("is_grouped", false):
			show_grouped_tooltip(base_id, variants, display_id)
		else:
			show_tooltip_for_item(display_id)
		return
	hide_tooltip()


func refresh_inventory_ui() -> void:
	if not pc._inventory_grid:
		return
	for child in pc._inventory_grid.get_children():
		pc._inventory_grid.remove_child(child)
		child.free()

	pc._cached_grouped = Inventory.get_grouped_item_list()
	var grouped: Array = pc._cached_grouped

	const TOTAL_SLOTS := 64

	for i in range(TOTAL_SLOTS):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(60, 60)
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(0.12, 0.12, 0.16, 0.8)
		slot_style.border_color = Color(0.25, 0.25, 0.3)
		slot_style.set_border_width_all(1)
		slot_style.set_corner_radius_all(3)
		slot_style.set_content_margin_all(2)

		if i < grouped.size():
			var entry: Dictionary = grouped[i]
			var base_id: StringName = entry["base_id"]
			var total: int = entry["total"]
			var variants: Dictionary = entry["variants"]
			var display_id: StringName = entry.get("exact_id", base_id) as StringName
			var item_equipped := Inventory.is_equipped(display_id)
			var is_grouped: bool = entry.get("is_grouped", false)

			# Rarity border for equipment (ungrouped items with stars)
			if not is_grouped:
				var parsed_slot := ItemDatabase.parse_star_id(display_id)
				var slot_stars: int = parsed_slot["stars"]
				if slot_stars > 0:
					var rarity_col: Color = ItemDatabase.get_rarity_color(slot_stars)
					slot_style.border_color = rarity_col
					slot_style.set_border_width_all(2)

			var stack := Control.new()
			stack.custom_minimum_size = Vector2(56, 56)
			stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var icon_rect := TextureRect.new()
			icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var icon_tex: Texture2D = ItemDatabase.get_icon(base_id)
			if not icon_tex:
				icon_tex = ItemDatabase.get_icon(display_id)
			if icon_tex:
				icon_rect.texture = icon_tex
			else:
				var placeholder := PlaceholderTexture2D.new()
				placeholder.size = Vector2(32, 32)
				icon_rect.texture = placeholder
				icon_rect.modulate = get_item_fallback_color(base_id)
			stack.add_child(icon_rect)

			if item_equipped:
				var equip_badge := Label.new()
				equip_badge.text = "E"
				equip_badge.add_theme_font_size_override("font_size", 10)
				equip_badge.add_theme_color_override("font_color", Color.WHITE)
				equip_badge.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
				equip_badge.add_theme_constant_override("shadow_offset_x", 1)
				equip_badge.add_theme_constant_override("shadow_offset_y", 1)
				equip_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
				equip_badge.vertical_alignment = VERTICAL_ALIGNMENT_TOP
				equip_badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				equip_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
				stack.add_child(equip_badge)

			if total > 1:
				var amt_lbl := Label.new()
				amt_lbl.text = str(total)
				amt_lbl.add_theme_font_size_override("font_size", 11)
				amt_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.8))
				amt_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
				amt_lbl.add_theme_constant_override("shadow_offset_x", 1)
				amt_lbl.add_theme_constant_override("shadow_offset_y", 1)
				amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				amt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
				amt_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				amt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				stack.add_child(amt_lbl)

			slot.add_child(stack)
			if is_grouped:
				slot.mouse_entered.connect(show_grouped_tooltip.bind(base_id, variants, display_id))
			else:
				slot.mouse_entered.connect(show_tooltip_for_item.bind(display_id))
			slot.mouse_exited.connect(hide_tooltip)

		slot.add_theme_stylebox_override("panel", slot_style)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(on_inv_slot_gui_input.bind(i))
		pc._inventory_grid.add_child(slot)

	recheck_inventory_tooltip()
	refresh_crafting_ui()


func refresh_crafting_ui() -> void:
	if not pc._crafting_grid:
		return
	for child in pc._crafting_grid.get_children():
		pc._crafting_grid.remove_child(child)
		child.free()

	var recipes: Array = ItemDatabase.get_hand_recipes()
	for recipe_entry in recipes:
		var item_id: StringName = recipe_entry["id"] as StringName
		var data: Dictionary = recipe_entry["data"] as Dictionary
		var hand_type: String = str(data.get("type", "material"))
		var hand_is_equip := hand_type in ["weapon", "armor"]
		var hand_max: int = 5 if hand_is_equip else 0
		var can_make: bool = ItemDatabase.can_craft(item_id, hand_max, 0)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(36, 36)
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var icon_tex: Texture2D = ItemDatabase.get_icon(item_id)
		if icon_tex:
			icon_rect.texture = icon_tex
		else:
			var ph := PlaceholderTexture2D.new()
			ph.size = Vector2(32, 32)
			icon_rect.texture = ph
			icon_rect.modulate = get_item_fallback_color(item_id)
		row.add_child(icon_rect)

		var info_vb := VBoxContainer.new()
		info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vb.add_theme_constant_override("separation", 0)

		var name_lbl := Label.new()
		name_lbl.text = data.get("name", str(item_id)) as String
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color.WHITE if can_make else Color(0.5, 0.45, 0.4))
		info_vb.add_child(name_lbl)

		var recipe_arr: Array = data.get("recipe", []) as Array
		var cost_text := ""
		for ingredient: Dictionary in recipe_arr:
			var req_id: StringName = StringName(ingredient.get("item_id", ""))
			var req_amt: int = int(ingredient.get("amount", 0))
			var req_data: Dictionary = ItemDatabase.get_item(req_id)
			var req_name: String = req_data.get("name", str(req_id)) as String
			var have: int = Inventory.get_amount_capped_star(req_id, hand_max, 0) if not hand_is_equip else Inventory.get_amount_any_star(req_id)
			var have_color := "aaffaa" if (have >= req_amt or Inventory.has_free_craft()) else "ff6666"
			if cost_text != "":
				cost_text += "  "
			cost_text += "[color=#%s]%s %d/%d[/color]" % [have_color, req_name, have, req_amt]

		var cost_lbl := RichTextLabel.new()
		cost_lbl.bbcode_enabled = true
		cost_lbl.text = cost_text
		cost_lbl.fit_content = true
		cost_lbl.scroll_active = false
		cost_lbl.custom_minimum_size.y = 16
		cost_lbl.add_theme_font_size_override("normal_font_size", 10)
		info_vb.add_child(cost_lbl)

		row.add_child(info_vb)

		var btn := Button.new()
		btn.text = "Craft"
		btn.disabled = not can_make
		btn.custom_minimum_size = Vector2(60, 30)
		btn.pressed.connect(on_craft_pressed.bind(item_id))
		row.add_child(btn)

		pc._crafting_grid.add_child(row)


func on_craft_pressed(item_id: StringName) -> void:
	var crafted_id: StringName = ItemDatabase.craft_item(item_id)
	if crafted_id != &"":
		spawn_craft_text(crafted_id)
		refresh_inventory_ui()


func spawn_craft_text(crafted_id: StringName) -> void:
	var parsed := ItemDatabase.parse_star_id(crafted_id)
	var stars: int = parsed["stars"]
	var display := ItemDatabase.get_display_name(crafted_id)
	var data: Dictionary = ItemDatabase.get_item(crafted_id)
	var amount: int = int(data.get("craft_amount", 1))

	var num := _DamageNumber.new()
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


func on_inv_slot_gui_input(event: InputEvent, slot_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if slot_idx >= pc._cached_grouped.size():
			return
		var entry: Dictionary = pc._cached_grouped[slot_idx]
		var raw_indices: Array = entry.get("raw_indices", []) as Array
		var is_grouped: bool = entry.get("is_grouped", false)
		var entry_id: StringName = entry.get("exact_id", entry["base_id"]) as StringName
		if pc._chest_open and pc._chest_node and pc._chest_node.has_meta("chest_contents") and mb.shift_pressed:
			if (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT) and mb.pressed:
				var half_only := mb.button_index == MOUSE_BUTTON_LEFT
				if is_grouped:
					var base: StringName = entry["base_id"]
					var variants: Dictionary = entry["variants"]
					for star_level in variants.keys():
						var vid: StringName = ItemDatabase.make_star_id(base, int(star_level))
						pc._deposit_item_to_chest(vid, half_only)
				elif not raw_indices.is_empty():
					pc._deposit_inv_slot_to_chest(int(raw_indices[0]), half_only)
				return
		if mb.shift_pressed and mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not pc._chest_open:
			discard_inventory_slot.call_deferred(entry)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if pc._dragging_item == &"":
				if not raw_indices.is_empty():
					var raw_idx: int = int(raw_indices[0])
					start_drag(entry_id, raw_idx)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var data: Dictionary = ItemDatabase.get_item(entry_id)
			var item_type: String = str(data.get("type", ""))
			if data.has("armor_slot") and (item_type == "armor" or item_type == "weapon"):
				start_equip_progress(entry_id, slot_idx)


func equip_item_deferred(entry_id: StringName) -> void:
	Inventory.equip_armor(entry_id)
	refresh_inventory_ui()
	refresh_equip_bar()


func unequip_item_deferred(slot_name: String) -> void:
	Inventory.unequip_armor(slot_name)
	refresh_inventory_ui()
	refresh_equip_bar()


func discard_inventory_slot(entry: Dictionary) -> void:
	var is_grouped: bool = entry.get("is_grouped", false)
	var base_id: StringName = entry["base_id"]
	if is_grouped:
		var variants: Dictionary = entry.get("variants", {})
		for star_level in variants.keys():
			var vid: StringName = ItemDatabase.make_star_id(base_id, int(star_level))
			var qty: int = int(variants[star_level])
			if qty > 0 and Inventory.remove_item(vid, qty):
				pc._drop_item_on_ground(vid, qty, 60.0)
	else:
		var exact_id: StringName = entry.get("exact_id", base_id) as StringName
		var qty: int = Inventory.get_amount(exact_id)
		if qty > 0 and Inventory.remove_item(exact_id, qty):
			pc._drop_item_on_ground(exact_id, qty, 60.0)
	refresh_inventory_ui()


func start_equip_progress(item_id: StringName, slot_idx: int) -> void:
	pc._start_equip_progress(item_id, slot_idx)


func cancel_equip_progress() -> void:
	pc._cancel_equip_progress()


func tick_equip_progress(delta: float) -> void:
	pc._tick_equip_progress(delta)


func recheck_inventory_tooltip() -> void:
	if not pc._inventory_panel or not pc._inventory_panel.visible:
		return
	if not pc._inventory_grid or not pc._hud_root:
		return
	var mouse_pos := pc._hud_root.get_local_mouse_position()
	for i in range(pc._inventory_grid.get_child_count()):
		var slot: Control = pc._inventory_grid.get_child(i) as Control
		if slot and i < pc._cached_grouped.size():
			var slot_rect: Rect2 = slot.get_global_rect()
			if slot_rect.has_point(mouse_pos):
				var entry: Dictionary = pc._cached_grouped[i]
				var display_id: StringName = entry.get("exact_id", entry["base_id"]) as StringName
				if entry.get("is_grouped", false):
					var variants: Dictionary = entry["variants"]
					show_grouped_tooltip(entry["base_id"], variants, display_id)
				else:
					show_tooltip_for_item(display_id)
				return
	hide_tooltip()


func on_inventory_hover(item_id: StringName) -> void:
	show_tooltip_for_item(item_id)


func start_drag(item_id: StringName, from_slot: int) -> void:
	pc._dragging_item = item_id
	pc._drag_from_slot = from_slot
	var icon_tex: Texture2D = ItemDatabase.get_icon(item_id)
	if icon_tex and pc._drag_icon:
		pc._drag_icon.texture = icon_tex
		pc._drag_icon.visible = true
		pc._drag_icon.position = pc._hud_root.get_local_mouse_position() - Vector2(16, 16)


func cancel_drag() -> void:
	pc._dragging_item = &""
	pc._drag_from_slot = -1
	if pc._drag_icon:
		pc._drag_icon.visible = false


func drop_dragged_item() -> void:
	var item_id := pc._dragging_item
	if item_id == &"":
		cancel_drag()
		return
	var vis_slot := -1
	for i in range(pc._cached_grouped.size()):
		var e: Dictionary = pc._cached_grouped[i]
		var eid: StringName = e.get("exact_id", e["base_id"]) as StringName
		if eid == item_id:
			vis_slot = i
			break
	if vis_slot >= 0 and vis_slot < pc._cached_grouped.size():
		discard_inventory_slot(pc._cached_grouped[vis_slot])
	else:
		var qty: int = Inventory.get_amount(item_id)
		if qty > 0 and Inventory.remove_item(item_id, qty):
			pc._drop_item_on_ground(item_id, qty, 60.0)
		refresh_inventory_ui()
	cancel_drag()


func get_inv_slot_under_mouse() -> int:
	if not pc._inventory_grid or not pc._hud_root:
		return -1
	var mouse_pos := pc._hud_root.get_global_mouse_position()
	for i in range(pc._inventory_grid.get_child_count()):
		var slot: Control = pc._inventory_grid.get_child(i) as Control
		if slot and slot.get_global_rect().has_point(mouse_pos):
			return i
	return -1


func finish_drag(to_visual_slot: int) -> void:
	if pc._drag_from_slot < 0:
		cancel_drag()
		return
	if to_visual_slot < pc._cached_grouped.size():
		var to_entry: Dictionary = pc._cached_grouped[to_visual_slot]
		var to_raw: Array = to_entry.get("raw_indices", []) as Array
		var raw_to := to_visual_slot
		if not to_raw.is_empty():
			raw_to = int(to_raw[0])
		if pc._drag_from_slot != raw_to:
			Inventory.swap_slots(pc._drag_from_slot, raw_to)
			refresh_inventory_ui()
			update_hotbar_selection()
	else:
		var from_visual := -1
		for i in range(pc._cached_grouped.size()):
			var entry: Dictionary = pc._cached_grouped[i]
			var raw_indices: Array = entry.get("raw_indices", []) as Array
			for ri in raw_indices:
				if int(ri) == pc._drag_from_slot:
					from_visual = i
					break
			if from_visual >= 0:
				break
		if from_visual >= 0 and from_visual < pc._cached_grouped.size() - 1:
			var entry: Dictionary = pc._cached_grouped[from_visual]
			var raw_indices: Array = entry.get("raw_indices", []) as Array
			Inventory.move_group_to_end(raw_indices)
			refresh_inventory_ui()
			update_hotbar_selection()
	cancel_drag()


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


func update_hotbar_selection() -> void:
	var hotbar := get_hotbar_items()
	var grouped: Array = Inventory.get_grouped_item_list()
	for i in range(pc._hotbar_slots.size()):
		var slot: PanelContainer = pc._hotbar_slots[i]
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(4)
		s.set_content_margin_all(4)

		var item_id: StringName = hotbar[i]

		if i == pc._selected_slot:
			s.bg_color = Color(0.2, 0.18, 0.1, 0.95)
			s.border_color = Color(0.85, 0.7, 0.3)
			s.set_border_width_all(2)
		else:
			s.bg_color = Color(0.1, 0.1, 0.14, 0.85)
			s.border_color = Color(0.3, 0.3, 0.35)
			s.set_border_width_all(1)
		slot.add_theme_stylebox_override("panel", s)

		if i < pc._hotbar_icons.size():
			if item_id == &"":
				pc._hotbar_icons[i].texture = null
				pc._hotbar_icons[i].modulate = Color.WHITE
			else:
				var base_id: StringName = ItemDatabase.parse_star_id(item_id)["base_id"]
				var icon_tex: Texture2D = ItemDatabase.get_icon(base_id)
				if not icon_tex:
					icon_tex = ItemDatabase.get_icon(item_id)
				if icon_tex:
					pc._hotbar_icons[i].texture = icon_tex
					pc._hotbar_icons[i].modulate = Color.WHITE
				else:
					var ph := PlaceholderTexture2D.new()
					ph.size = Vector2(32, 32)
					pc._hotbar_icons[i].texture = ph
					pc._hotbar_icons[i].modulate = get_item_fallback_color(item_id)

		if i < pc._hotbar_qty_labels.size():
			if item_id == &"" or i >= grouped.size():
				pc._hotbar_qty_labels[i].text = ""
			else:
				var amt: int = int(grouped[i]["total"])
				pc._hotbar_qty_labels[i].add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
				pc._hotbar_qty_labels[i].text = str(amt) if amt > 1 else ""
