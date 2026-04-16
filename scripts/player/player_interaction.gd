class_name PlayerInteraction
extends Node

## Sub-module for interaction system: chests, mounting, caves, raft.
## Add as child of PlayerController. Stores `var pc: PlayerController` and accesses state via `pc.`.

var pc: PlayerController

const CHEST_COLS := 4
const CHEST_ROWS := 8
const CHEST_SLOTS := CHEST_COLS * CHEST_ROWS
const _DamageNumber := preload("res://scripts/ui/damage_number.gd")
const RAFT_SPEED := 5.2
const RAFT_TURN_SPEED := 1.8
const MOUNT_SPEED_MULT := 2.0
const _HORSE_WALK_FRAME_DURATION := 0.14
const _HORSE_RUN_FRAME_DURATION := 0.09
const _SIT_IDLE_FRAME_DURATION := 0.12

const UNLOCK_HOLD_TIME := 1.5

var _unlock_progress: float = 0.0
var _unlock_target: Node3D = null
var _unlock_bar: ProgressBar = null
var _unlock_bar_container: PanelContainer = null


# ===================================================================
# CHEST
# ===================================================================

func build_chest_panel(root: Control) -> void:
	pc._chest_panel = PanelContainer.new()
	pc._chest_panel.name = "ChestPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.06, 0.94)
	style.border_color = Color(0.5, 0.38, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	pc._chest_panel.add_theme_stylebox_override("panel", style)
	pc._chest_panel.anchor_left = 1.0
	pc._chest_panel.anchor_right = 1.0
	pc._chest_panel.anchor_top = 0.0
	pc._chest_panel.anchor_bottom = 0.0
	pc._chest_panel.offset_left = -320
	pc._chest_panel.offset_right = -30
	pc._chest_panel.offset_top = 30
	pc._chest_panel.offset_bottom = 560
	pc._chest_panel.visible = false
	pc._chest_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	pc._chest_panel.z_index = 60

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "Chest"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	vbox.add_child(title)

	pc._chest_grid = GridContainer.new()
	pc._chest_grid.columns = CHEST_COLS
	pc._chest_grid.add_theme_constant_override("h_separation", 4)
	pc._chest_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(pc._chest_grid)

	pc._chest_panel.add_child(vbox)
	root.add_child(pc._chest_panel)


func open_chest(chest_node: Node3D) -> void:
	if pc._chest_open:
		close_chest()
	pc._chest_node = chest_node
	pc._chest_open = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not chest_node.has_meta("chest_contents"):
		var slots: Array[Dictionary] = []
		slots.resize(CHEST_SLOTS)
		for i in CHEST_SLOTS:
			slots[i] = {}
		chest_node.set_meta("chest_contents", slots)
	refresh_chest_ui()
	if pc._chest_panel:
		pc._chest_panel.visible = true
	if pc._inventory_panel:
		pc._inventory_panel.visible = true
		pc._refresh_inventory_ui()
	if pc._minimap_biome_label:
		pc._minimap_biome_label.visible = false
	AudioManager.play_sfx_at("wood_thud", chest_node.global_position, -6.0, 0.2)


func close_chest() -> void:
	pc._chest_open = false
	pc._chest_node = null
	pc._hide_tooltip()
	if pc._chest_panel:
		pc._chest_panel.visible = false
	if pc._inventory_panel and not pc._inventory_open:
		pc._inventory_panel.visible = false
	if pc._minimap_biome_label:
		pc._minimap_biome_label.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ===================================================================
# CHEST UNLOCK
# ===================================================================

func _has_oathsword_equipped() -> bool:
	var equipped := Inventory.get_all_equipped()
	for slot_name in equipped:
		var item_id: StringName = equipped[slot_name] as StringName
		if item_id == &"" or item_id == &"fists":
			continue
		var parsed := ItemDatabase.parse_star_id(item_id)
		if parsed.get("base", &"") == &"god_sword":
			return true
	return false


func _try_unlock_chest(chest_node: Node3D) -> void:
	if _has_oathsword_equipped():
		chest_node.set_meta("is_locked", false)
		AudioManager.play_sfx("ui_click", -6.0)
		if NetworkManager.is_server() or not NetworkManager.is_connected_to_game():
			open_chest(chest_node)
		return

	if not Inventory.has_item_any_star(&"chest_key"):
		AudioManager.play_sfx("ui_click", -8.0)
		return

	if _unlock_target == chest_node and _unlock_progress > 0.0:
		return
	_unlock_target = chest_node
	_unlock_progress = 0.0
	_show_unlock_bar()


func _show_unlock_bar() -> void:
	_hide_unlock_bar()
	if not pc._hud_root:
		return
	_unlock_bar_container = PanelContainer.new()
	_unlock_bar_container.name = "UnlockBarContainer"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.04, 0.85)
	style.border_color = Color(0.5, 0.38, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	_unlock_bar_container.add_theme_stylebox_override("panel", style)
	_unlock_bar_container.set_anchors_preset(Control.PRESET_CENTER)
	_unlock_bar_container.offset_left = -120
	_unlock_bar_container.offset_right = 120
	_unlock_bar_container.offset_top = 60
	_unlock_bar_container.offset_bottom = 100
	_unlock_bar_container.z_index = 80

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var label := Label.new()
	label.text = "Unlocking..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	vbox.add_child(label)

	_unlock_bar = ProgressBar.new()
	_unlock_bar.custom_minimum_size = Vector2(220, 12)
	_unlock_bar.max_value = 1.0
	_unlock_bar.value = 0.0
	_unlock_bar.show_percentage = false
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
	bg_style.set_corner_radius_all(3)
	_unlock_bar.add_theme_stylebox_override("background", bg_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.85, 0.65, 0.15, 0.9)
	fill_style.set_corner_radius_all(3)
	_unlock_bar.add_theme_stylebox_override("fill", fill_style)
	vbox.add_child(_unlock_bar)

	_unlock_bar_container.add_child(vbox)
	pc._hud_root.add_child(_unlock_bar_container)


func _hide_unlock_bar() -> void:
	if _unlock_bar_container and is_instance_valid(_unlock_bar_container):
		_unlock_bar_container.queue_free()
	_unlock_bar_container = null
	_unlock_bar = null


func cancel_unlock() -> void:
	_unlock_target = null
	_unlock_progress = 0.0
	_hide_unlock_bar()


func tick_unlock(delta: float) -> void:
	if _unlock_target == null:
		return
	if not is_instance_valid(_unlock_target):
		cancel_unlock()
		return
	if pc.global_position.distance_to(_unlock_target.global_position) > 3.5:
		cancel_unlock()
		return
	_unlock_progress += delta
	if _unlock_bar and is_instance_valid(_unlock_bar):
		_unlock_bar.value = clampf(_unlock_progress / UNLOCK_HOLD_TIME, 0.0, 1.0)

	if _unlock_progress >= UNLOCK_HOLD_TIME:
		var chest := _unlock_target
		Inventory.remove_item_any_star(&"chest_key", 1)
		chest.set_meta("is_locked", false)
		cancel_unlock()
		AudioManager.play_sfx("ui_click", -4.0)
		if NetworkManager.is_server() or not NetworkManager.is_connected_to_game():
			open_chest(chest)


func refresh_chest_ui() -> void:
	if not pc._chest_grid or not pc._chest_node:
		return
	pc._hide_tooltip()
	for child in pc._chest_grid.get_children():
		pc._chest_grid.remove_child(child)
		child.free()

	var contents: Array = pc._chest_node.get_meta("chest_contents", []) as Array

	for i in CHEST_SLOTS:
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(56, 56)
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(0.15, 0.13, 0.1, 0.8)
		slot_style.border_color = Color(0.35, 0.3, 0.2, 0.6)
		slot_style.set_border_width_all(1)
		slot_style.set_corner_radius_all(3)
		slot.add_theme_stylebox_override("panel", slot_style)

		var slot_data: Dictionary = contents[i] if i < contents.size() else {}
		var item_id: StringName = slot_data.get("item_id", &"") as StringName
		var count: int = int(slot_data.get("count", 0))

		if item_id != &"" and count > 0:
			var parsed: Dictionary = ItemDatabase.parse_star_id(item_id)
			var slot_stars: int = int(parsed.get("stars", 0))
			if slot_stars > 0:
				slot_style.border_color = ItemDatabase.get_rarity_color(slot_stars)
				slot_style.set_border_width_all(2)

			var stack := Control.new()
			stack.custom_minimum_size = Vector2(52, 52)
			stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var data: Dictionary = ItemDatabase.get_item(item_id)
			var icon_path: String = str(data.get("icon", ""))
			var icon_tex: Texture2D = null
			if icon_path != "" and ResourceLoader.exists(icon_path):
				icon_tex = load(icon_path) as Texture2D
			if icon_tex:
				var tex_rect := TextureRect.new()
				tex_rect.texture = icon_tex
				tex_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tex_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				stack.add_child(tex_rect)
			else:
				var color_rect := ColorRect.new()
				color_rect.color = pc._get_item_fallback_color(item_id)
				color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				stack.add_child(color_rect)

			if count > 1:
				var qty := Label.new()
				qty.text = str(count)
				qty.add_theme_font_size_override("font_size", 11)
				qty.add_theme_color_override("font_color", Color(0.9, 0.9, 0.8))
				qty.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
				qty.add_theme_constant_override("shadow_offset_x", 1)
				qty.add_theme_constant_override("shadow_offset_y", 1)
				qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				qty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
				qty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
				stack.add_child(qty)

			slot.add_child(stack)

		var slot_idx := i
		slot.gui_input.connect(func(ev: InputEvent):
			on_chest_slot_click(ev, slot_idx)
		)
		if item_id != &"" and count > 0:
			slot.mouse_entered.connect(pc._show_tooltip_for_item.bind(item_id))
			slot.mouse_exited.connect(pc._hide_tooltip)
		pc._chest_grid.add_child(slot)


func on_chest_slot_click(event: InputEvent, slot_idx: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if not pc._chest_node or not pc._chest_node.has_meta("chest_contents"):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
		return

	# Right-click (no shift) = take all; Shift+Left = take half; Shift+Right = take all
	if mb.button_index == MOUSE_BUTTON_LEFT and not mb.shift_pressed:
		return

	var contents: Array = pc._chest_node.get_meta("chest_contents") as Array
	var slot_data: Dictionary = contents[slot_idx] if slot_idx < contents.size() else {}
	var chest_id: StringName = slot_data.get("item_id", &"") as StringName
	var chest_count: int = int(slot_data.get("count", 0))

	if chest_id == &"" or chest_count <= 0:
		return

	var to_take: int
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.shift_pressed:
		to_take = maxi(chest_count / 2, 1)
	else:
		to_take = chest_count

	Inventory.add_item(chest_id, to_take)
	if NetworkManager.is_server() or not NetworkManager.is_connected_to_game():
		chest_count -= to_take
		if chest_count <= 0:
			contents[slot_idx] = {}
		else:
			contents[slot_idx] = {"item_id": chest_id, "count": chest_count}
		pc._chest_node.set_meta("chest_contents", contents)
		refresh_chest_ui.call_deferred()
		pc._refresh_inventory_ui.call_deferred()
	else:
		NetworkManager.request_withdraw_from_chest.rpc_id(1, str(pc._chest_node.get_path()), str(chest_id), to_take)
		pc._refresh_inventory_ui()
		# Chest UI refreshes on chest_contents_received


func deposit_inv_slot_to_chest(slot_idx: int, half_only: bool) -> void:
	var items: Array = Inventory.get_item_list()
	if slot_idx >= items.size():
		return
	var item_id: StringName = items[slot_idx]["id"] as StringName
	var count: int = int(items[slot_idx].get("amount", 1))
	var to_deposit := count if not half_only else maxi(count / 2, 1)
	if to_deposit <= 0:
		return

	if not Inventory.remove_item(item_id, to_deposit):
		return

	if NetworkManager.is_server() or not NetworkManager.is_connected_to_game():
		var contents: Array = pc._chest_node.get_meta("chest_contents") as Array
		var stack_size: int = ItemDatabase.get_item(item_id).get("stack_size", 50)
		var deposited := 0
		for i in CHEST_SLOTS:
			if deposited >= to_deposit:
				break
			var sd: Dictionary = contents[i] if i < contents.size() else {}
			if sd.get("item_id", &"") == item_id:
				var cur: int = int(sd.get("count", 0))
				var space := stack_size - cur
				var add := mini(to_deposit - deposited, space)
				if add > 0:
					contents[i] = {"item_id": item_id, "count": cur + add}
					deposited += add
		for i in CHEST_SLOTS:
			if deposited >= to_deposit:
				break
			var sd: Dictionary = contents[i] if i < contents.size() else {}
			if sd.is_empty() or sd.get("item_id", &"") == &"":
				var add := mini(to_deposit - deposited, stack_size)
				contents[i] = {"item_id": item_id, "count": add}
				deposited += add
		if deposited > 0:
			pc._chest_node.set_meta("chest_contents", contents)
		refresh_chest_ui.call_deferred()
		pc._refresh_inventory_ui.call_deferred()
	else:
		NetworkManager.request_deposit_to_chest.rpc_id(1, str(pc._chest_node.get_path()), str(item_id), to_deposit)
		pc._refresh_inventory_ui()
		# Chest UI refreshes on chest_contents_received


func deposit_item_to_chest(item_id: StringName, half_only: bool) -> void:
	var count: int = Inventory.get_amount(item_id)
	if count <= 0:
		return
	var to_deposit := count if not half_only else maxi(count / 2, 1)
	if not Inventory.remove_item(item_id, to_deposit):
		return

	if NetworkManager.is_server() or not NetworkManager.is_connected_to_game():
		var contents: Array = pc._chest_node.get_meta("chest_contents") as Array
		var stack_size: int = ItemDatabase.get_item(item_id).get("stack_size", 50)
		var deposited := 0
		for i in CHEST_SLOTS:
			if deposited >= to_deposit:
				break
			var sd: Dictionary = contents[i] if i < contents.size() else {}
			if sd.get("item_id", &"") == item_id:
				var cur: int = int(sd.get("count", 0))
				var space := stack_size - cur
				var add := mini(to_deposit - deposited, space)
				if add > 0:
					contents[i] = {"item_id": item_id, "count": cur + add}
					deposited += add
		for i in CHEST_SLOTS:
			if deposited >= to_deposit:
				break
			var sd: Dictionary = contents[i] if i < contents.size() else {}
			if sd.is_empty() or sd.get("item_id", &"") == &"":
				var add := mini(to_deposit - deposited, stack_size)
				contents[i] = {"item_id": item_id, "count": add}
				deposited += add
		if deposited > 0:
			pc._chest_node.set_meta("chest_contents", contents)
		refresh_chest_ui.call_deferred()
		pc._refresh_inventory_ui.call_deferred()
	else:
		NetworkManager.request_deposit_to_chest.rpc_id(1, str(pc._chest_node.get_path()), str(item_id), to_deposit)
		pc._refresh_inventory_ui()


# ===================================================================
# INTERACT PROMPT & TRY INTERACT
# ===================================================================

var _interact_cache_timer := 0.0
var _interact_cached_workbenches: Array[Node] = []
var _interact_cached_doors: Array[Node] = []
var _interact_cached_chests: Array[Node] = []
var _interact_cached_horses: Array[Node] = []
var _interact_cached_rafts: Array[Node] = []
var _interact_cached_cave_entrances: Array[Node] = []
var _interact_cached_berry_bushes: Array[Node] = []
var _interact_cached_npcs: Array[Node] = []
var _interact_cached_signposts: Array[Node] = []
const _INTERACT_CACHE_INTERVAL := 1.0

func _refresh_interact_caches() -> void:
	_interact_cached_workbenches = pc.get_tree().get_nodes_in_group(&"workbenches")
	_interact_cached_doors = pc.get_tree().get_nodes_in_group(&"doors")
	_interact_cached_chests = pc.get_tree().get_nodes_in_group(&"chests")
	_interact_cached_horses = pc.get_tree().get_nodes_in_group(&"horses")
	_interact_cached_rafts = pc.get_tree().get_nodes_in_group(&"rafts")
	_interact_cached_cave_entrances = pc.get_tree().get_nodes_in_group(&"cave_entrances")
	_interact_cached_berry_bushes = pc.get_tree().get_nodes_in_group(&"berry_bushes")
	_interact_cached_npcs = pc.get_tree().get_nodes_in_group(&"npcs")
	_interact_cached_signposts = pc.get_tree().get_nodes_in_group(&"signposts")

func update_interact_prompt() -> void:
	if not pc._interact_prompt:
		return
	if pc._inventory_open or pc._workbench_open or pc._build_menu_open or pc._build_mode or pc._terraform_mode or pc._chest_open or pc._map_open or pc._shop_open:
		pc._interact_prompt.visible = false
		if pc._world_name_label:
			pc._world_name_label.visible = false
		return

	_interact_cache_timer -= 0.15
	if _interact_cache_timer <= 0.0:
		_interact_cache_timer = _INTERACT_CACHE_INTERVAL
		_refresh_interact_caches()

	var pp := pc.global_position
	var closest_dist := 3.5
	var closest_name := ""
	for wb in _interact_cached_workbenches:
		if not is_instance_valid(wb):
			continue
		var wb3d := wb as Node3D
		if not wb3d or not wb3d.is_inside_tree():
			continue
		var d := pp.distance_to(wb3d.global_position)
		if d < closest_dist:
			closest_dist = d
			closest_name = "Workbench"

	for door in _interact_cached_doors:
		if not is_instance_valid(door):
			continue
		var d3d := door as Node3D
		if not d3d or not d3d.is_inside_tree():
			continue
		var d := pp.distance_to(d3d.global_position)
		if d < closest_dist:
			closest_dist = d
			var is_open: bool = d3d.get_meta("door_open", false)
			closest_name = "Close Door" if is_open else "Open Door"

	for ch in _interact_cached_chests:
		if not is_instance_valid(ch):
			continue
		var ch3d := ch as Node3D
		if not ch3d or not ch3d.is_inside_tree():
			continue
		var d := pp.distance_to(ch3d.global_position)
		if d < closest_dist:
			closest_dist = d
			if ch3d.get_meta("is_locked", false):
				closest_name = "Unlock Chest"
			else:
				closest_name = "Chest"

	if pc._on_raft:
		closest_name = "Dismount Raft"
	elif pc._mounted:
		closest_name = "Dismount"
	else:
		for horse in _interact_cached_horses:
			if not is_instance_valid(horse):
				continue
			var h3d := horse as Node3D
			if not h3d or not h3d.is_inside_tree():
				continue
			var d := pp.distance_to(h3d.global_position)
			if d < closest_dist:
				closest_dist = d
				closest_name = "Mount"
		for raft in _interact_cached_rafts:
			if not is_instance_valid(raft):
				continue
			var r3d := raft as Node3D
			if not r3d or not r3d.is_inside_tree():
				continue
			var d := pp.distance_to(r3d.global_position)
			if d < 4.0 and d < closest_dist:
				closest_dist = d
				closest_name = "Board Raft"

	for bb in _interact_cached_berry_bushes:
		if not is_instance_valid(bb):
			continue
		var bb3d := bb as Node3D
		if not bb3d or not bb3d.is_inside_tree():
			continue
		if not bb3d.get_meta("berry_harvest", false):
			continue
		var bush_center := bb3d.global_position + Vector3.UP * 0.5
		var d := pp.distance_to(bush_center)
		if d < 3.0 and d < closest_dist:
			closest_dist = d
			var drop_id: StringName = bb3d.get_meta("drop_id", &"blueberry")
			var berry_name := ItemDatabase.get_display_name(drop_id) if drop_id != &"" else "Berries"
			closest_name = "Harvest %s" % berry_name

	for npc in _interact_cached_npcs:
		if not is_instance_valid(npc):
			continue
		var n3d := npc as Node3D
		if not n3d or not n3d.is_inside_tree():
			continue
		var d := pp.distance_to(n3d.global_position)
		if d < 3.5 and d < closest_dist:
			closest_dist = d
			var npc_name: String = str(n3d.get("display_name")) if "display_name" in n3d else "NPC"
			var verb: String = n3d.get_interaction_verb() if n3d.has_method("get_interaction_verb") else "Talk to"
			closest_name = "%s %s" % [verb, npc_name]

	for sp in _interact_cached_signposts:
		if not is_instance_valid(sp):
			continue
		var s3d := sp as Node3D
		if not s3d or not s3d.is_inside_tree():
			continue
		var d := pp.distance_to(s3d.global_position)
		if d < 3.0 and d < closest_dist:
			closest_dist = d
			closest_name = "Read Sign"

	var nearest_world_name := ""
	var cam: Camera3D = pc._spring_arm.get_child(0) if pc._spring_arm.get_child_count() > 0 else null
	if cam and cam.is_inside_tree() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var ray_origin := cam.global_position
		var ray_dir := -cam.global_transform.basis.z
		var ray_end := ray_origin + ray_dir * 20.0
		var space := pc.get_world_3d().direct_space_state
		if space:
			var q := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 4 | 32)
			q.exclude = [pc.get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var obj := hit["collider"] as Node3D
				if obj:
					if obj.has_meta("tree_name"):
						nearest_world_name = obj.get_meta("tree_name") as String
					elif obj.has_meta("rock_name"):
						nearest_world_name = obj.get_meta("rock_name") as String
					elif obj.has_meta("vein_name"):
						nearest_world_name = obj.get_meta("vein_name") as String
					elif obj.has_meta("cave_entrance"):
						nearest_world_name = "Cave"
					elif obj.has_meta("cave_exit"):
						nearest_world_name = "Exit"

	if not pc._in_cave:
		for ce in _interact_cached_cave_entrances:
			if not is_instance_valid(ce):
				continue
			var ce3d := ce as Node3D
			if not ce3d or not ce3d.is_inside_tree():
				continue
			var d := pp.distance_to(ce3d.global_position)
			if d < 4.0 and d < closest_dist:
				closest_dist = d
				closest_name = "Enter Cave"
	else:
		for node in _interact_cached_cave_entrances:
			if not is_instance_valid(node):
				continue
			var n3d := node as Node3D
			if not n3d or not n3d.is_inside_tree() or not n3d.has_meta("cave_exit"):
				continue
			var d := pp.distance_to(n3d.global_position)
			if d < 4.0 and d < closest_dist:
				closest_dist = d
				closest_name = "Exit Cave"

	if closest_name != "":
		pc._interact_prompt.text = "[E] %s" % closest_name
		pc._interact_prompt.visible = true
	else:
		pc._interact_prompt.visible = false

	if pc._world_name_label:
		if nearest_world_name != "" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			pc._world_name_label.text = nearest_world_name
			pc._world_name_label.visible = true
			var vp_center := pc.get_viewport().get_visible_rect().size * 0.5
			pc._world_name_label.position = vp_center + Vector2(18, 16)
		else:
			pc._world_name_label.visible = false


func try_interact() -> void:
	# Dismount raft
	if pc._on_raft:
		dismount_raft()
		return
	# Dismount if mounted
	if pc._mounted:
		dismount()
		return

	# Cave exit — check first if inside a cave
	if pc._in_cave:
		for node in pc.get_tree().get_nodes_in_group(&"interactables"):
			var n3d := node as Node3D
			if not n3d or not n3d.has_meta("cave_exit"):
				continue
			if pc.global_position.distance_to(n3d.global_position) < 4.0:
				exit_cave()
				return

	# Cave entrances
	if not pc._in_cave:
		for node in pc.get_tree().get_nodes_in_group(&"cave_entrances"):
			var n3d := node as Node3D
			if not n3d:
				continue
			if pc.global_position.distance_to(n3d.global_position) < 4.0:
				enter_cave(n3d)
				return

	var best_loot: Node3D
	var best_dist := 4.49
	for node in pc.get_tree().get_nodes_in_group(&"loot"):
		var loot := node as Node3D
		if not loot:
			continue
		if "pickup_grace" in loot and loot.pickup_grace > 0.0:
			continue
		var d: float = pc.global_position.distance_to(loot.global_position)
		if d < best_dist:
			best_dist = d
			best_loot = loot
	if best_loot and best_loot.has_method("pickup"):
		best_loot.pickup(pc)
		return

	# Check signposts (high priority — before horses/bushes/etc)
	for sp in pc.get_tree().get_nodes_in_group(&"signposts"):
		var s3d := sp as Node3D
		if not s3d:
			continue
		if pc.global_position.distance_to(s3d.global_position) < 3.0:
			_interact_signpost(s3d)
			return

	# Check rafts
	for raft in pc.get_tree().get_nodes_in_group(&"rafts"):
		var r3d := raft as Node3D
		if r3d and pc.global_position.distance_to(r3d.global_position) < 4.0:
			mount_raft(r3d)
			return

	# Check horses
	for horse in pc.get_tree().get_nodes_in_group(&"horses"):
		var h3d := horse as Node3D
		if h3d and pc.global_position.distance_to(h3d.global_position) < 3.5:
			mount(h3d)
			return

	# Check doors
	for door in pc.get_tree().get_nodes_in_group(&"doors"):
		var d3d := door as StaticBody3D
		if not d3d:
			continue
		if pc.global_position.distance_to(d3d.global_position) < 3.5:
			pc._toggle_door(d3d)
			return

	# Check beds (sleep)
	for bed in pc.get_tree().get_nodes_in_group(&"beds"):
		var b3d := bed as Node3D
		if b3d and pc.global_position.distance_to(b3d.global_position) < 3.5:
			pc._try_sleep()
			return

	# Check chests
	for ch in pc.get_tree().get_nodes_in_group(&"chests"):
		var ch3d := ch as Node3D
		if not ch3d:
			continue
		if pc.global_position.distance_to(ch3d.global_position) < 3.0:
			if ch3d.get_meta("is_locked", false):
				_try_unlock_chest(ch3d)
				return
			if NetworkManager.is_server() or not NetworkManager.is_connected_to_game():
				open_chest(ch3d)
			else:
				NetworkManager.request_open_chest.rpc_id(1, str(ch3d.get_path()))
			return

	# Check debug portals
	for portal in pc.get_tree().get_nodes_in_group(&"debug_portals"):
		var p3d := portal as Node3D
		if not p3d:
			continue
		if pc.global_position.distance_to(p3d.global_position) < 4.0:
			if p3d.has_method("interact"):
				p3d.interact(pc)
			return

	# Check berry bushes for E-to-harvest
	var best_bush: Node3D = null
	var best_bush_dist := 3.0
	for bb in pc.get_tree().get_nodes_in_group(&"berry_bushes"):
		var bb3d := bb as Node3D
		if not bb3d:
			continue
		if not bb3d.get_meta("berry_harvest", false):
			continue
		var d := pc.global_position.distance_to(bb3d.global_position + Vector3.UP * 0.5)
		if d < best_bush_dist:
			best_bush_dist = d
			best_bush = bb3d
	if best_bush:
		_harvest_berry_bush(best_bush)
		return

	# Check workbenches
	for wb in pc.get_tree().get_nodes_in_group(&"workbenches"):
		var wb3d := wb as Node3D
		if not wb3d:
			continue
		if pc.global_position.distance_to(wb3d.global_position) < 3.0:
			pc._workbench_ui.open_workbench()
			return

	# Check NPCs (merchants)
	for npc in pc.get_tree().get_nodes_in_group(&"npcs"):
		var n3d := npc as Node3D
		if not n3d:
			continue
		if pc.global_position.distance_to(n3d.global_position) < 3.5:
			if n3d.has_method("interact"):
				n3d.interact(pc)
			return


func _interact_signpost(signpost: Node3D) -> void:
	pc._show_speech(pc._LINES_SIGNPOST, &"signpost")
	if signpost.get_meta("reveals_merchant", false):
		var merchant_pos: Vector3 = signpost.get_meta("merchant_pos", Vector3.ZERO) as Vector3
		var wgs := pc.get_tree().get_nodes_in_group(&"world_generator")
		var wg_ref := wgs[0] if not wgs.is_empty() else null
		var player_abs: Vector3 = wg_ref.get_world_position(pc) if wg_ref and wg_ref.has_method(&"get_world_position") else pc.global_position
		var signpost_abs: Vector3 = wg_ref.get_world_position(signpost) if wg_ref and wg_ref.has_method(&"get_world_position") else signpost.global_position
		var merchant_real: Vector3 = wg_ref.get_merchant_world_pos() if wg_ref and wg_ref.has_method(&"get_merchant_world_pos") else Vector3.ZERO
		print("[SIGNPOST] reveals_merchant meta=%s real_merchant=%s player_abs=%s signpost_abs=%s" % [
			merchant_pos, merchant_real, player_abs, signpost_abs])
		if merchant_pos != Vector3.ZERO:
			pc._reveal_map_marker("merchant", merchant_pos, "Halvard")


# ===================================================================
# BERRY BUSH HARVESTING
# ===================================================================

func _harvest_berry_bush(bush: Node3D) -> void:
	var drop_id: StringName = bush.get_meta("drop_id", &"blueberry")
	var drop_min: int = int(bush.get_meta("drop_min", 1))
	var drop_max: int = int(bush.get_meta("drop_max", 1))

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var amount := rng.randi_range(drop_min, drop_max)

	AudioManager.play_sfx("fist_hit_tree", -14.0, 0.2)
	AudioManager.play_sfx("wood_pickup", -6.0, 0.15)
	GameEvents.item_picked_up.emit(drop_id, amount)

	var display := ItemDatabase.get_display_name(drop_id)
	var num := _DamageNumber.new()
	num.text = "+%d %s" % [amount, display]
	num.font_size = 28
	num.pixel_size = 0.01
	num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	num.no_depth_test = true
	num.modulate = Color.WHITE
	num.outline_modulate = Color.BLACK
	num.outline_size = 6
	num._velocity = Vector3(0, 2.0, 0)
	pc.get_tree().current_scene.add_child(num)
	num.global_position = bush.global_position + Vector3(0, 1.5, 0)

	bush.set_meta("berry_harvest", false)
	bush.remove_from_group(&"berry_bushes")

	# Hide the batched berry MultiMesh (BerryMM) - leaves and trunk stay visible
	var berry_mm := bush.get_node_or_null("BerryMM") as MultiMeshInstance3D
	if berry_mm:
		berry_mm.visible = false

	# Slight shake animation on the foliage
	var leaf_mm := bush.get_node_or_null("LeafMM") as Node3D
	if leaf_mm:
		var tw := bush.create_tween()
		var base_pos := leaf_mm.position
		tw.tween_property(leaf_mm, "position", base_pos + Vector3(0.04, 0.02, -0.03), 0.06)
		tw.tween_property(leaf_mm, "position", base_pos + Vector3(-0.03, -0.01, 0.04), 0.06)
		tw.tween_property(leaf_mm, "position", base_pos + Vector3(0.02, 0.01, -0.02), 0.05)
		tw.tween_property(leaf_mm, "position", base_pos, 0.07)

	# Respawn berries after 8-24 hours (28800-86400 seconds)
	var stree := bush.get_tree()
	if stree:
		var respawn_secs := randf_range(28800.0, 86400.0)
		stree.create_timer(respawn_secs).timeout.connect(func():
			if not is_instance_valid(bush):
				return
			bush.set_meta("berry_harvest", true)
			bush.add_to_group(&"berry_bushes")
			# Show the batched berry MultiMesh again
			var respawn_berry_mm := bush.get_node_or_null("BerryMM") as MultiMeshInstance3D
			if respawn_berry_mm:
				respawn_berry_mm.visible = true
		)


# ===================================================================
# CAVE TELEPORTATION
# ===================================================================

func enter_cave(entrance: Node3D) -> void:
	if pc._in_cave:
		return
	print("[CAVE] Entering cave from entrance at %s" % entrance.global_position)
	pc._cave_return_pos = pc.global_position
	pc._cave_entrance_node = entrance
	pc._in_cave = true
	pc._swim_fatigue = 0.0
	pc._drown_tick_timer = 0.0
	pc._is_swimming = false

	if pc._minimap_outer:
		pc._minimap_outer.visible = false
	if pc._footstep_player and pc._footstep_player.playing:
		pc._footstep_player.stop()
	if pc._gallop_player and pc._gallop_player.playing:
		pc._gallop_player.stop()

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(entrance.global_position)
	pc._cave_instance = CaveGenerator.create_cave_instance(rng)
	pc.get_tree().root.add_child(pc._cave_instance)

	var spawn_local: Vector3 = pc._cave_instance.get_meta("player_spawn", Vector3.ZERO)
	var target := pc._cave_instance.global_position + spawn_local
	print("[CAVE] Cave instance at %s, spawn_local=%s, target=%s" % [pc._cave_instance.global_position, spawn_local, target])

	# Wait for physics server to register the cave collision shapes
	await pc.get_tree().physics_frame
	await pc.get_tree().physics_frame

	if not is_instance_valid(pc) or not pc._in_cave:
		return
	pc.global_position = target
	pc.velocity = Vector3.ZERO


func exit_cave() -> void:
	if not pc._in_cave:
		return
	pc._in_cave = false
	pc.global_position = pc._cave_return_pos + Vector3(0.0, 1.0, 0.0)
	pc.velocity = Vector3.ZERO

	if pc._minimap_outer:
		pc._minimap_outer.visible = true

	if is_instance_valid(pc._cave_instance):
		pc._cave_instance.queue_free()
	pc._cave_instance = null
	pc._cave_entrance_node = null


# ===================================================================
# MOUNT (HORSE)
# ===================================================================

func mount(horse: Node3D) -> void:
	pc._mounted = true
	pc._mount_node = horse
	pc._mount_star_level = int(horse.get_meta("star_level", 0))
	pc._mount_max_stamina = float(horse.get_meta("max_stamina", 100.0))
	pc._mount_stamina = float(horse.get_meta("current_stamina", pc._mount_max_stamina))
	pc._mount_stamina_regen_timer = 0.0
	pc._horse_walk_frames = horse.get_meta("walk_frames", {}) as Dictionary
	pc._horse_run_frames = horse.get_meta("run_frames", {}) as Dictionary
	pc._horse_anim_idx = 0
	pc._horse_anim_timer = 0.0
	pc.floor_max_angle = deg_to_rad(55.0)
	pc.floor_snap_length = 1.5
	horse.remove_from_group(&"horses")
	if horse is StaticBody3D:
		(horse as StaticBody3D).collision_layer = 0
		(horse as StaticBody3D).collision_mask = 0
	for child in horse.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true

	var gpos := horse.global_position
	var grot := horse.rotation
	var old_parent := horse.get_parent()
	if old_parent:
		old_parent.remove_child(horse)
	var world_root := pc.get_tree().current_scene
	if world_root:
		world_root.add_child(horse)
	horse.global_position = gpos
	horse.rotation = grot

	pc._mount_anim_player = pc._find_anim_player(horse)

	if pc._footstep_player and pc._footstep_player.playing:
		pc._footstep_player.stop()

	var np_root := horse.get_node_or_null("HorseNameplateRoot")
	if np_root:
		np_root.visible = false

	pc._sit_idle_anim_idx = 0
	pc._sit_idle_anim_timer = 0.0

	if pc._player_sprite and pc._gltf_anim_player:
		pc._player_sprite.visible = true
		var rider_node := pc._player_sprite.duplicate()
		rider_node.name = "Rider3D"
		rider_node.scale = pc._player_sprite.scale
		var mount_model := get_mount_3d_model(horse)
		var ride_y := 1.2
		if mount_model:
			ride_y = estimate_mount_height(mount_model)
		rider_node.position = Vector3(0, ride_y, 0)
		horse.add_child(rider_node)
		pc._player_sprite.visible = false
		var rider_anim := pc._find_anim_player(rider_node)
		if rider_anim:
			for anim_name in rider_anim.get_animation_list():
				var anim := rider_anim.get_animation(anim_name)
				if anim:
					anim.loop_mode = Animation.LOOP_LINEAR
			var played := false
			for anim_name in rider_anim.get_animation_list():
				if "sit" in anim_name.to_lower():
					rider_anim.play(anim_name)
					played = true
					break
			if not played:
				for anim_name in rider_anim.get_animation_list():
					if "idle" in anim_name.to_lower():
						rider_anim.play(anim_name)
						break
	elif pc._player_sprite:
		pc._player_sprite.visible = false
		var rider := Sprite3D.new()
		rider.name = "RiderSprite"
		if pc._sit_idle_frames.has("south") and not (pc._sit_idle_frames["south"] as Array).is_empty():
			rider.texture = (pc._sit_idle_frames["south"] as Array)[0] as Texture2D
		elif pc._player_textures.has("south"):
			rider.texture = pc._player_textures["south"] as Texture2D
		rider.pixel_size = 0.025
		rider.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		rider.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		rider.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		rider.transparent = true
		rider.shaded = true
		rider.double_sided = true
		rider.position.y = 1.55
		rider.render_priority = 1
		horse.add_child(rider)


func get_mount_3d_model(horse: Node3D) -> Node3D:
	for child in horse.get_children():
		if child is Node3D and not child is CollisionShape3D and child.name != "BodySprite" and child.name != "RiderSprite" and child.name != "Rider3D":
			return child
	return null


func estimate_mount_height(model: Node3D) -> float:
	var max_y := 1.0
	for child in model.get_children():
		if child is MeshInstance3D:
			var aabb := (child as MeshInstance3D).get_aabb()
			var top := aabb.position.y + aabb.size.y
			if top > max_y:
				max_y = top
	return max_y * model.scale.y * 0.85


func force_dismount() -> void:
	pc._mounted = false
	pc.floor_max_angle = deg_to_rad(55.0)
	pc.floor_snap_length = 1.0

	if pc._player_sprite:
		pc._player_sprite.visible = true
	if pc._gallop_player and pc._gallop_player.playing:
		pc._gallop_player.stop()

	if is_instance_valid(pc._mount_node):
		pc._mount_node.set_meta("max_stamina", pc._mount_max_stamina)
		pc._mount_node.set_meta("current_stamina", pc._mount_stamina)
		pc._mount_node.add_to_group(&"horses")
		if pc._mount_node is StaticBody3D:
			(pc._mount_node as StaticBody3D).collision_layer = 4
			(pc._mount_node as StaticBody3D).collision_mask = 1
		for child in pc._mount_node.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = false
		for tag in ["RiderSprite", "Rider3D"]:
			var rider := pc._mount_node.get_node_or_null(tag)
			if rider:
				rider.queue_free()
		var wg := pc.get_tree().root.get_node_or_null("TestWorld/WorldGenerator")
		if wg and wg.has_method("get_height_at_scene"):
			var hp := pc._mount_node.global_position
			pc._mount_node.global_position.y = wg.get_height_at_scene(hp.x, hp.z)

	pc._mount_node = null
	pc._mount_anim_player = null
	pc._horse_walk_frames = {}
	pc._horse_run_frames = {}
	pc._horse_anim_idx = 0
	pc._horse_anim_timer = 0.0


func dismount() -> void:
	if not pc._mounted:
		return
	pc._mounted = false
	pc.floor_max_angle = deg_to_rad(55.0)
	pc.floor_snap_length = 1.0

	if pc._player_sprite:
		pc._player_sprite.visible = true
	if pc._gallop_player and pc._gallop_player.playing:
		pc._gallop_player.stop()

	if is_instance_valid(pc._mount_node):
		var np_root := pc._mount_node.get_node_or_null("HorseNameplateRoot")
		if np_root:
			np_root.visible = true
		pc._mount_node.set_meta("max_stamina", pc._mount_max_stamina)
		pc._mount_node.set_meta("current_stamina", pc._mount_stamina)
		pc._mount_node.add_to_group(&"horses")
		if pc._mount_node is StaticBody3D:
			(pc._mount_node as StaticBody3D).collision_layer = 4
			(pc._mount_node as StaticBody3D).collision_mask = 1
		for child in pc._mount_node.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).disabled = false
		for tag in ["RiderSprite", "Rider3D"]:
			var rider := pc._mount_node.get_node_or_null(tag)
			if rider:
				rider.queue_free()
		var offset := -pc.global_transform.basis.z * 2.0
		offset.y = 0.0
		var horse_pos := pc.global_position + offset
		var wg := pc.get_tree().root.get_node_or_null("TestWorld/WorldGenerator")
		if wg and wg.has_method("get_height_at_scene"):
			horse_pos.y = wg.get_height_at_scene(horse_pos.x, horse_pos.z)
		pc._mount_node.global_position = horse_pos

	pc._mount_node = null
	pc._mount_anim_player = null
	pc._horse_walk_frames = {}
	pc._horse_run_frames = {}
	pc._horse_anim_idx = 0
	pc._horse_anim_timer = 0.0


# ===================================================================
# RAFT
# ===================================================================

func spawn_raft(pos: Vector3, rot_y: float) -> void:
	var raft := StaticBody3D.new()
	raft.name = "Raft"
	raft.collision_layer = 4
	raft.collision_mask = 0
	raft.add_to_group(&"rafts")
	raft.set_meta("interact_name", "Raft")

	var raft_visual := build_raft_model()
	raft.add_child(raft_visual)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.0, 0.3, 4.0)
	col.shape = box
	col.position.y = 0.15
	raft.add_child(col)

	pc.get_tree().current_scene.add_child(raft)
	raft.global_position = pos
	raft.rotation.y = rot_y


func build_raft_model() -> Node3D:
	var root := Node3D.new()
	root.name = "RaftModel"

	var plank_mat := StandardMaterial3D.new()
	plank_mat.albedo_color = Color(0.45, 0.32, 0.18)
	plank_mat.roughness = 0.9
	plank_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.32, 0.22, 0.12)
	dark_mat.roughness = 0.85
	dark_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.60, 0.52, 0.35)
	rope_mat.roughness = 0.8
	rope_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# Base planks (5 logs lashed together)
	for i in 5:
		var x_off := (float(i) - 2.0) * 0.58
		pc._add_box_part(root, "log_%d" % i, Vector3(0.28, 0.18, 3.6), Vector3(x_off, 0.09, 0.0), plank_mat)

	# Cross beams
	pc._add_box_part(root, "beam_f", Vector3(2.8, 0.10, 0.14), Vector3(0.0, 0.22, 1.2), dark_mat)
	pc._add_box_part(root, "beam_b", Vector3(2.8, 0.10, 0.14), Vector3(0.0, 0.22, -1.2), dark_mat)

	# Rope lashings
	for bz in [1.2, -1.2]:
		for lx in [-1.0, 0.0, 1.0]:
			pc._add_box_part(root, "rope_%.0f_%.0f" % [bz, lx], Vector3(0.06, 0.06, 0.20), Vector3(lx, 0.26, bz), rope_mat)

	# Raised edge rails
	pc._add_box_part(root, "rail_l", Vector3(0.08, 0.20, 3.2), Vector3(-1.35, 0.32, 0.0), dark_mat)
	pc._add_box_part(root, "rail_r", Vector3(0.08, 0.20, 3.2), Vector3(1.35, 0.32, 0.0), dark_mat)

	# Paddle (resting on the side)
	var paddle_root := Node3D.new()
	paddle_root.name = "Paddle"
	pc._add_box_part(paddle_root, "shaft", Vector3(0.05, 0.05, 1.8), Vector3.ZERO, dark_mat)
	pc._add_box_part(paddle_root, "blade", Vector3(0.14, 0.02, 0.40), Vector3(0.0, 0.0, -1.0), plank_mat)
	pc._add_box_part(paddle_root, "grip", Vector3(0.07, 0.07, 0.12), Vector3(0.0, 0.0, 0.85), dark_mat)
	paddle_root.position = Vector3(0.0, 0.8, 0.0)
	root.add_child(paddle_root)

	return root


func mount_raft(raft: Node3D) -> void:
	pc._on_raft = true
	pc._raft_node = raft
	pc._raft_paddle_timer = 0.0
	pc._is_swimming = false

	raft.remove_from_group(&"rafts")
	if raft is StaticBody3D:
		(raft as StaticBody3D).collision_layer = 0
		(raft as StaticBody3D).collision_mask = 0
	for child in raft.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true

	pc.collision_layer = 0
	pc.collision_mask = 0


func dismount_raft() -> void:
	if not pc._on_raft or not is_instance_valid(pc._raft_node):
		pc._on_raft = false
		pc._raft_node = null
		pc.rotation = Vector3.ZERO
		pc.collision_layer = 1
		pc.collision_mask = 1
		return

	pc._on_raft = false
	pc._raft_node.add_to_group(&"rafts")
	if pc._raft_node is StaticBody3D:
		(pc._raft_node as StaticBody3D).collision_layer = 4
		(pc._raft_node as StaticBody3D).collision_mask = 0
	for child in pc._raft_node.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = false

	var dismount_dir := -pc.global_transform.basis.z
	dismount_dir.y = 0.0
	dismount_dir = dismount_dir.normalized()
	var water_y := WaterSystem.get_surface_y(pc.global_position.x, pc.global_position.z)
	pc.global_position = pc._raft_node.global_position + dismount_dir * 3.0
	pc.global_position.y = water_y + 0.3
	pc.velocity = Vector3.ZERO
	pc.rotation = Vector3.ZERO

	pc._raft_node = null
	pc.collision_layer = 1
	pc.collision_mask = 1


func tick_raft(delta: float) -> void:
	if not pc._on_raft or not is_instance_valid(pc._raft_node):
		dismount_raft()
		return

	var water_y := WaterSystem.get_surface_y(pc._raft_node.global_position.x, pc._raft_node.global_position.z)
	pc._raft_node.global_position.y = water_y

	if pc._chat_focused:
		tick_paddle_animation(delta, false)
		return

	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_backward")
	var raft_forward := Vector3(-sin(pc._raft_node.rotation.y), 0.0, -cos(pc._raft_node.rotation.y))
	var moving := input_dir.length() > 0.1

	if absf(input_dir.x) > 0.1:
		pc._raft_node.rotation.y -= input_dir.x * RAFT_TURN_SPEED * delta

	if absf(input_dir.y) > 0.1:
		var spd := RAFT_SPEED * input_dir.y
		pc._raft_node.global_position += raft_forward * spd * delta

	pc.global_position = pc._raft_node.global_position + Vector3(0.0, 0.4, 0.0)
	pc.rotation.y = pc._raft_node.rotation.y
	pc.velocity = Vector3.ZERO

	# Wave tilt
	var wave_tilt_x := WaterSystem.get_surface_y(pc._raft_node.global_position.x + 1.0, pc._raft_node.global_position.z) - WaterSystem.get_surface_y(pc._raft_node.global_position.x - 1.0, pc._raft_node.global_position.z)
	var wave_tilt_z := WaterSystem.get_surface_y(pc._raft_node.global_position.x, pc._raft_node.global_position.z + 1.0) - WaterSystem.get_surface_y(pc._raft_node.global_position.x, pc._raft_node.global_position.z - 1.0)
	pc._raft_node.rotation.x = lerpf(pc._raft_node.rotation.x, wave_tilt_z * 0.15, 4.0 * delta)
	pc._raft_node.rotation.z = lerpf(pc._raft_node.rotation.z, -wave_tilt_x * 0.15, 4.0 * delta)

	tick_paddle_animation(delta, moving)


func tick_paddle_animation(delta: float, rowing: bool) -> void:
	var paddle := pc._raft_node.get_node_or_null("RaftModel/Paddle") as Node3D
	if not paddle:
		return
	if rowing:
		pc._raft_paddle_timer += delta * 3.0
		var cycle := fmod(pc._raft_paddle_timer, TAU)
		var dip := sin(cycle)
		var side_f := 1.0 if pc._raft_paddle_side else -1.0
		# Switch sides every full stroke
		if cycle < delta * 3.0 and pc._raft_paddle_timer > TAU * 0.5:
			pc._raft_paddle_side = not pc._raft_paddle_side
		paddle.position = Vector3(side_f * 0.8, 0.7, 0.2)
		paddle.rotation = Vector3(
			deg_to_rad(lerpf(-15.0, 45.0, (dip + 1.0) * 0.5)),
			deg_to_rad(side_f * 20.0),
			deg_to_rad(side_f * -30.0),
		)
	else:
		paddle.position = paddle.position.lerp(Vector3(0.0, 0.8, 0.0), 4.0 * delta)
		paddle.rotation = paddle.rotation.lerp(Vector3.ZERO, 4.0 * delta)


func tick_horse_animation(delta: float) -> void:
	if not pc._mount_node:
		return

	var flat_speed := Vector2(pc.velocity.x, pc.velocity.z).length()
	var is_moving := flat_speed > 0.5

	if pc._mount_anim_player:
		var want_anim := "idle"
		if is_moving:
			want_anim = "run" if pc._is_sprinting else "walk"
		if want_anim != pc._mount_current_anim:
			pc._mount_current_anim = want_anim
			for candidate in ["animation." + want_anim, want_anim]:
				if pc._mount_anim_player.has_animation(candidate):
					pc._mount_anim_player.play(candidate)
					break

		var mount_model := get_mount_3d_model(pc._mount_node)
		if mount_model:
			var flat_vel := Vector2(pc.velocity.x, pc.velocity.z)
			if flat_vel.length() > 0.3:
				var target_angle := atan2(-pc.velocity.x, -pc.velocity.z)
				mount_model.rotation.y = lerp_angle(mount_model.rotation.y, target_angle, 0.15)
		return

	var dir := pc._get_camera_relative_dir()
	var body_sprite := pc._mount_node.get_node_or_null("BodySprite") as Sprite3D
	var rider := pc._mount_node.get_node_or_null("RiderSprite") as Sprite3D

	if is_moving:
		var use_run := pc._is_sprinting and pc._horse_run_frames.has(dir)
		var frame_dict: Dictionary = pc._horse_run_frames if use_run else pc._horse_walk_frames
		var frame_dur := _HORSE_RUN_FRAME_DURATION if use_run else _HORSE_WALK_FRAME_DURATION
		if frame_dict.has(dir):
			var frames: Array = Array(frame_dict[dir])
			if not frames.is_empty():
				pc._horse_anim_timer -= delta
				if pc._horse_anim_timer <= 0.0:
					pc._horse_anim_idx = (pc._horse_anim_idx + 1) % frames.size()
					pc._horse_anim_timer = frame_dur
				if pc._horse_anim_idx >= frames.size():
					pc._horse_anim_idx = 0
				var tex := frames[pc._horse_anim_idx] as Texture2D
				if tex and body_sprite:
					body_sprite.texture = tex
					var smat := body_sprite.material_override as ShaderMaterial
					if smat:
						smat.set_shader_parameter("sprite_texture", tex)
	else:
		pc._horse_anim_idx = 0
		pc._horse_anim_timer = 0.0
		var horse_textures: Dictionary = pc._mount_node.get_meta("sprite_textures", {}) as Dictionary
		if body_sprite and horse_textures.has(dir):
			var htex: Texture2D = horse_textures[dir] as Texture2D
			body_sprite.texture = htex
			var smat := body_sprite.material_override as ShaderMaterial
			if smat:
				smat.set_shader_parameter("sprite_texture", htex)

	if rider:
		if pc._sit_idle_frames.has(dir) and not (pc._sit_idle_frames[dir] as Array).is_empty():
			var sit_frames: Array = Array(pc._sit_idle_frames[dir])
			pc._sit_idle_anim_timer -= delta
			if pc._sit_idle_anim_timer <= 0.0:
				pc._sit_idle_anim_idx = (pc._sit_idle_anim_idx + 1) % sit_frames.size()
				pc._sit_idle_anim_timer = _SIT_IDLE_FRAME_DURATION
			if pc._sit_idle_anim_idx >= sit_frames.size():
				pc._sit_idle_anim_idx = 0
			rider.texture = sit_frames[pc._sit_idle_anim_idx] as Texture2D
		elif pc._player_textures.has(dir):
			rider.texture = pc._player_textures[dir] as Texture2D
