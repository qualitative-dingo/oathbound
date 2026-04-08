class_name PlayerShopUI
extends Node

var pc: PlayerController
var _shop_panel: PanelContainer
var _shop_grid: VBoxContainer
var _gold_label: Label
var _merchant_node: Node3D


func build_shop_panel(root: Control) -> void:
	_shop_panel = PanelContainer.new()
	_shop_panel.name = "ShopPanel"
	_shop_panel.visible = false
	_shop_panel.set_anchors_preset(Control.PRESET_CENTER)
	_shop_panel.position = Vector2(-220, -200)
	_shop_panel.custom_minimum_size = Vector2(440, 420)
	_shop_panel.z_index = 95

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.06, 0.04, 0.96)
	bg.border_color = Color(0.75, 0.55, 0.2)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(8)
	bg.set_content_margin_all(16)
	_shop_panel.add_theme_stylebox_override("panel", bg)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "Halvard's Trading Post"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(title)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 15)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(_gold_label)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.5, 0.38, 0.18, 0.5))
	outer_vbox.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(400, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_shop_grid = VBoxContainer.new()
	_shop_grid.add_theme_constant_override("separation", 6)
	scroll.add_child(_shop_grid)
	outer_vbox.add_child(scroll)

	var close_hint := Label.new()
	close_hint.text = "Press [ESC] or [E] to close"
	close_hint.add_theme_font_size_override("font_size", 12)
	close_hint.add_theme_color_override("font_color", Color(0.6, 0.55, 0.45))
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer_vbox.add_child(close_hint)

	_shop_panel.add_child(outer_vbox)
	root.add_child(_shop_panel)


func open_shop(merchant: Node3D) -> void:
	_merchant_node = merchant
	_refresh_shop()
	_shop_panel.visible = true
	pc._shop_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if pc._minimap_biome_label:
		pc._minimap_biome_label.visible = false
	AudioManager.play_sfx("wood_thud", -6.0, 0.15)


func close_shop() -> void:
	_shop_panel.visible = false
	pc._shop_open = false
	_merchant_node = null
	if pc._minimap_biome_label:
		pc._minimap_biome_label.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return _shop_panel != null and _shop_panel.visible


func _refresh_shop() -> void:
	if not _shop_grid:
		return
	for child in _shop_grid.get_children():
		_shop_grid.remove_child(child)
		child.queue_free()

	var gold_count := Inventory.get_amount(&"gold")
	_gold_label.text = "Gold: %d" % gold_count

	var items: Array[Dictionary] = []
	if _merchant_node and _merchant_node.has_method("get") == false:
		items = _get_merchant_items()
	else:
		items = _get_merchant_items()

	for entry in items:
		var item_id: StringName = entry.get("item_id", &"") as StringName
		var price: int = int(entry.get("price", 0))
		var amount: int = int(entry.get("amount", 1))
		var data: Dictionary = ItemDatabase.get_item(item_id)
		if data.is_empty():
			continue

		var row := PanelContainer.new()
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color(0.12, 0.1, 0.08, 0.7)
		row_style.border_color = Color(0.4, 0.32, 0.18, 0.4)
		row_style.set_border_width_all(1)
		row_style.set_corner_radius_all(4)
		row_style.set_content_margin_all(8)
		row.add_theme_stylebox_override("panel", row_style)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)

		var icon_path: String = str(data.get("icon", ""))
		if icon_path != "" and ResourceLoader.exists(icon_path):
			var tex := load(icon_path) as Texture2D
			if tex:
				var tex_rect := TextureRect.new()
				tex_rect.texture = tex
				tex_rect.custom_minimum_size = Vector2(40, 40)
				tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				hbox.add_child(tex_rect)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)

		var name_lbl := Label.new()
		var display_name: String = str(data.get("name", item_id))
		if amount > 1:
			display_name += " x%d" % amount
		name_lbl.text = display_name
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
		info.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = str(data.get("description", ""))
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.48))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size.x = 200
		info.add_child(desc_lbl)

		hbox.add_child(info)

		var buy_btn := Button.new()
		var can_afford := gold_count >= price
		buy_btn.text = "%d Gold" % price
		buy_btn.add_theme_font_size_override("font_size", 13)
		buy_btn.custom_minimum_size = Vector2(90, 36)
		buy_btn.disabled = not can_afford

		var btn_style := StyleBoxFlat.new()
		btn_style.bg_color = Color(0.2, 0.16, 0.08, 0.9) if can_afford else Color(0.15, 0.13, 0.1, 0.6)
		btn_style.border_color = Color(0.7, 0.55, 0.2) if can_afford else Color(0.3, 0.25, 0.18)
		btn_style.set_border_width_all(1)
		btn_style.set_corner_radius_all(4)
		btn_style.set_content_margin_all(4)
		buy_btn.add_theme_stylebox_override("normal", btn_style)
		buy_btn.add_theme_stylebox_override("hover", btn_style)
		buy_btn.add_theme_stylebox_override("pressed", btn_style)
		buy_btn.add_theme_stylebox_override("disabled", btn_style)
		buy_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5) if can_afford else Color(0.5, 0.4, 0.3))

		var bound_id := item_id
		var bound_price := price
		var bound_amount := amount
		buy_btn.pressed.connect(_buy_item.bind(bound_id, bound_price, bound_amount))
		hbox.add_child(buy_btn)

		row.add_child(hbox)
		_shop_grid.add_child(row)


func _get_merchant_items() -> Array[Dictionary]:
	if _merchant_node and "SHOP_ITEMS" in _merchant_node:
		var raw: Array = _merchant_node.SHOP_ITEMS
		var result: Array[Dictionary] = []
		for entry in raw:
			result.append(entry as Dictionary)
		return result
	return []


func _buy_item(item_id: StringName, price: int, amount: int) -> void:
	var gold := Inventory.get_amount(&"gold")
	if gold < price:
		return
	Inventory.remove_item(&"gold", price)
	Inventory.add_item(item_id, amount)
	AudioManager.play_sfx("wood_pickup", -4.0, 0.1)
	GameEvents.inventory_changed.emit()

	var data := ItemDatabase.get_item(item_id)
	var teaches: StringName = data.get("teaches_build", &"") as StringName
	if teaches != &"" and pc:
		pc._try_learn_recipe(item_id)

	_refresh_shop()
