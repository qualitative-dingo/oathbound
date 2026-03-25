class_name PlayerBuilding
extends Node

const _DEBUG_LOG := false

var pc: PlayerController

# ── Constants ────────────────────────────────────────────────────────────────
const BUILD_TABS := ["Misc", "Crafting", "Building", "Heavy Build", "Furniture", "Vehicles"]

const BUILD_RECIPES: Array[Dictionary] = [
	# Misc
	{"id": &"campfire", "name": "Campfire", "tab": "Misc",
	 "cost": [{"item": &"stone", "amount": 5}, {"item": &"wood", "amount": 2}],
	 "mesh": "campfire", "color": Color(0.5, 0.3, 0.15), "size": Vector3(0.6, 0.3, 0.6)},
	{"id": &"torch_post", "name": "Standing Torch", "tab": "Misc",
	 "cost": [{"item": &"wood", "amount": 1}, {"item": &"resin", "amount": 2}],
	 "mesh": "cylinder", "color": Color(0.35, 0.25, 0.1), "size": Vector3(0.15, 1.8, 0.15),
	 "model": "res://models/building/standing_torch.glb"},
	{"id": &"wall_torch", "name": "Wall Torch", "tab": "Misc",
	 "cost": [{"item": &"torch", "amount": 1}],
	 "mesh": "wall_torch", "color": Color(0.35, 0.25, 0.1), "size": Vector3(0.1, 0.6, 0.1),
	 "model": "res://models/building/wall_torch.glb"},
	# Crafting
	{"id": &"workbench", "name": "Workbench", "tab": "Crafting",
	 "cost": [{"item": &"wood", "amount": 10}],
	 "mesh": "workbench", "color": Color(0.45, 0.3, 0.15), "size": Vector3(4.2, 2.7, 2.4)},
	# Building
	{"id": &"wood_wall", "name": "Wood Wall", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "box", "color": Color(0.4, 0.28, 0.12), "size": Vector3(3.6, 5.0, 0.20)},
	{"id": &"wood_floor", "name": "Wood Floor", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "box", "color": Color(0.45, 0.32, 0.15), "size": Vector3(3.6, 0.1, 3.6)},
	{"id": &"wood_stair", "name": "Wood Stairs", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 6}],
	 "mesh": "stair", "color": Color(0.42, 0.3, 0.14), "size": Vector3(3.6, 5.0, 3.6)},
	{"id": &"wood_door", "name": "Wood Door", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 6}],
	 "mesh": "door", "color": Color(0.4, 0.28, 0.12), "size": Vector3(3.6, 5.0, 0.20)},
	# Heavy Build
	{"id": &"stone_wall", "name": "Stone Wall", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 6}],
	 "mesh": "box", "color": Color(0.4, 0.4, 0.42), "size": Vector3(3.6, 5.0, 0.20)},
	{"id": &"stone_floor", "name": "Stone Floor", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 6}],
	 "mesh": "box", "color": Color(0.45, 0.45, 0.47), "size": Vector3(3.6, 0.1, 3.6)},
	{"id": &"stone_door", "name": "Stone Door", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 8}],
	 "mesh": "door", "color": Color(0.4, 0.4, 0.42), "size": Vector3(3.6, 5.0, 0.20)},
	# Roofing – Building tab (wood)
	{"id": &"thatch_roof_45", "name": "Thatch Roof 45°", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 6}],
	 "mesh": "roof_45", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 2.0, 2.0),
	 "model": "res://models/building/thatch_roof_45.glb"},
	{"id": &"thatch_roof_26", "name": "Thatch Roof 26°", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "roof_26", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 1.0, 2.0),
	 "model": "res://models/building/thatch_roof_26.glb"},
	{"id": &"thatch_roof_45_ocorner", "name": "Thatch Outer Corner 45°", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 6}],
	 "mesh": "roof_45_ocorner", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 2.0, 2.0)},
	{"id": &"thatch_roof_26_ocorner", "name": "Thatch Outer Corner 26°", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "roof_26_ocorner", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 1.0, 2.0)},
	{"id": &"thatch_roof_45_icorner", "name": "Thatch Inner Corner 45°", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 6}],
	 "mesh": "roof_45_icorner", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 2.0, 2.0)},
	{"id": &"thatch_roof_26_icorner", "name": "Thatch Inner Corner 26°", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "roof_26_icorner", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 1.0, 2.0)},
	{"id": &"thatch_roof_ridge", "name": "Thatch Ridge Cap", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 2}],
	 "mesh": "roof_ridge", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 0.15, 0.4)},
	# Roofing – Heavy Build tab (stone)
	{"id": &"slate_roof_45", "name": "Slate Roof 45°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 6}],
	 "mesh": "roof_45", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 2.0, 2.0)},
	{"id": &"slate_roof_26", "name": "Slate Roof 26°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 4}],
	 "mesh": "roof_26", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 1.0, 2.0)},
	{"id": &"slate_roof_45_ocorner", "name": "Slate Outer Corner 45°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 6}],
	 "mesh": "roof_45_ocorner", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 2.0, 2.0)},
	{"id": &"slate_roof_26_ocorner", "name": "Slate Outer Corner 26°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 4}],
	 "mesh": "roof_26_ocorner", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 1.0, 2.0)},
	{"id": &"slate_roof_45_icorner", "name": "Slate Inner Corner 45°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 6}],
	 "mesh": "roof_45_icorner", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 2.0, 2.0)},
	{"id": &"slate_roof_26_icorner", "name": "Slate Inner Corner 26°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 4}],
	 "mesh": "roof_26_icorner", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 1.0, 2.0)},
	{"id": &"slate_roof_ridge", "name": "Slate Ridge Cap", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 2}],
	 "mesh": "roof_ridge", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 0.15, 0.4)},
	# Furniture
	{"id": &"chest", "name": "Chest", "tab": "Furniture",
	 "cost": [{"item": &"wood", "amount": 10}],
	 "mesh": "box", "color": Color(0.5, 0.35, 0.15), "size": Vector3(1.92, 1.44, 1.2)},
	{"id": &"bed", "name": "Bed", "tab": "Furniture",
	 "cost": [{"item": &"wood", "amount": 8}, {"item": &"leather", "amount": 4}],
	 "mesh": "bed", "color": Color(0.5, 0.3, 0.2), "size": Vector3(1.2, 0.6, 2.2)},
	# Vehicles
	{"id": &"raft", "name": "Raft", "tab": "Vehicles",
	 "cost": [{"item": &"wood", "amount": 20}],
	 "mesh": "raft", "color": Color(0.45, 0.32, 0.18), "size": Vector3(3.0, 0.2, 4.0),
	 "water_only": true},
]

const Z_FIGHT_OFFSET := 0.001

const SNAP_COMPAT: Dictionary = {
	&"wall_base":      [&"wall_top", &"floor_edge"],
	&"wall_top":       [&"wall_base", &"floor_edge", &"roof_base_45", &"roof_base_26"],
	&"wall_side":      [&"wall_side"],
	&"floor_edge":     [&"wall_base", &"wall_top", &"floor_edge"],
	&"floor_corner":   [&"floor_corner"],
	&"roof_base_45":   [&"wall_top", &"roof_ridge_45"],
	&"roof_base_26":   [&"wall_top", &"roof_ridge_26"],
	&"roof_ridge_45":  [&"roof_ridge_45", &"roof_base_45"],
	&"roof_ridge_26":  [&"roof_ridge_26", &"roof_base_26"],
	&"roof_side_45":   [&"roof_side_45"],
	&"roof_side_26":   [&"roof_side_26"],
	&"ridge_cap_end":  [&"ridge_cap_end", &"roof_ridge_45", &"roof_ridge_26"],
}

const _DamageNumber := preload("res://scripts/ui/damage_number.gd")
const _LootDrop := preload("res://scripts/items/loot_drop.gd")

# Building material cache
static var _bmat_wood: StandardMaterial3D
static var _bmat_stone: StandardMaterial3D
static var _bmat_thatch: StandardMaterial3D
static var _bmat_slate: StandardMaterial3D


# ── Build menu ────────────────────────────────────────────────────────────────
func build_build_menu(root: Control) -> void:
	pc._build_menu_panel = PanelContainer.new()
	pc._build_menu_panel.name = "BuildMenu"
	pc._build_menu_panel.visible = false
	pc._build_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	pc._build_menu_panel.position = Vector2(-220, -180)
	pc._build_menu_panel.custom_minimum_size = Vector2(440, 360)
	pc._build_menu_panel.z_index = 90

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.06, 0.1, 0.95)
	bg.border_color = Color(0.6, 0.45, 0.2)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(14)
	pc._build_menu_panel.add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 4)
	pc._build_tab_buttons.clear()
	for tab_name: String in BUILD_TABS:
		var tb := Button.new()
		tb.text = tab_name
		tb.add_theme_font_size_override("font_size", 11)
		tb.custom_minimum_size = Vector2(0, 28)
		tb.pressed.connect(on_build_tab_pressed.bind(tab_name))
		tab_bar.add_child(tb)
		pc._build_tab_buttons.append(tb)
	vbox.add_child(tab_bar)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(410, 280)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pc._build_menu_grid = GridContainer.new()
	pc._build_menu_grid.columns = 1
	pc._build_menu_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(pc._build_menu_grid)
	vbox.add_child(scroll)

	pc._build_menu_panel.add_child(vbox)
	root.add_child(pc._build_menu_panel)


func on_build_tab_pressed(tab_name: String) -> void:
	pc._build_current_tab = tab_name
	refresh_build_menu()


func refresh_build_menu() -> void:
	if not pc._build_menu_grid:
		return
	for c in pc._build_menu_grid.get_children():
		pc._build_menu_grid.remove_child(c)
		c.free()

	for i in range(pc._build_tab_buttons.size()):
		var tb: Button = pc._build_tab_buttons[i]
		var active: bool = (BUILD_TABS[i] as String) == pc._build_current_tab
		tb.modulate = Color(1.0, 0.85, 0.5) if active else Color(0.6, 0.6, 0.6)

	for recipe: Dictionary in BUILD_RECIPES:
		if recipe.get("tab", "Misc") as String != pc._build_current_tab:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var rid_icon: StringName = recipe["id"] as StringName
		var icon_tex := get_build_icon(rid_icon)
		if icon_tex:
			var tex_rect := TextureRect.new()
			tex_rect.texture = icon_tex
			tex_rect.custom_minimum_size = Vector2(36, 36)
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(tex_rect)

		var info_vb := VBoxContainer.new()
		info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vb.add_theme_constant_override("separation", 1)

		var name_lbl := Label.new()
		name_lbl.text = recipe["name"] as String
		name_lbl.add_theme_font_size_override("font_size", 13)

		var cost_text := ""
		var can_afford := true
		var _free := Inventory.has_free_craft()
		for mat: Dictionary in (recipe["cost"] as Array):
			var mat_id: StringName = mat["item"] as StringName
			var mat_amt: int = int(mat["amount"])
			var have: int = Inventory.get_amount_any_star(mat_id)
			var mat_name: String = (ItemDatabase.get_item(mat_id) as Dictionary).get("name", str(mat_id)) as String
			if have < mat_amt and not _free:
				can_afford = false
			var have_color := "aaffaa" if (have >= mat_amt or _free) else "ff6666"
			if cost_text != "":
				cost_text += "  "
			cost_text += "[color=#%s]%s %d/%d[/color]" % [have_color, mat_name, have, mat_amt]

		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7) if can_afford else Color(0.5, 0.45, 0.4))
		info_vb.add_child(name_lbl)

		var cost_lbl := RichTextLabel.new()
		cost_lbl.bbcode_enabled = true
		cost_lbl.text = cost_text
		cost_lbl.fit_content = true
		cost_lbl.scroll_active = false
		cost_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		cost_lbl.custom_minimum_size.y = 16
		cost_lbl.add_theme_font_size_override("normal_font_size", 10)
		info_vb.add_child(cost_lbl)

		row.add_child(info_vb)

		var btn := Button.new()
		btn.text = "Build"
		btn.disabled = not can_afford
		btn.custom_minimum_size = Vector2(60, 30)
		var rid: StringName = recipe["id"] as StringName
		btn.pressed.connect(on_build_item_selected.bind(rid))
		row.add_child(btn)

		pc._build_menu_grid.add_child(row)


func toggle_build_menu() -> void:
	if pc._build_mode:
		cancel_build_mode()
		return
	pc._build_menu_open = not pc._build_menu_open
	if pc._build_menu_open:
		refresh_build_menu()
		pc._build_menu_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		pc._build_menu_panel.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func close_build_menu() -> void:
	pc._build_menu_open = false
	if pc._build_menu_panel:
		pc._build_menu_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func on_build_item_selected(build_id: StringName) -> void:
	pc._build_selected = build_id
	close_build_menu()
	enter_build_mode()


func enter_raft_placement() -> void:
	pc._build_selected = &"raft"
	pc._build_from_workbench = true
	enter_build_mode()


func enter_build_mode() -> void:
	pc._build_mode = true
	pc._build_rotation = pc.rotation.y
	pc._build_snapped = false
	var recipe := get_build_recipe(pc._build_selected)
	if recipe.is_empty():
		pc._build_mode = false
		return
	var mesh_type: String = recipe.get("mesh", "box") as String
	var color: Color = recipe.get("color", Color(0.5, 0.4, 0.2)) as Color
	var sz: Vector3 = recipe.get("size", Vector3(1, 1, 1)) as Vector3
	var build_id: StringName = recipe.get("id", &"") as StringName

	pc._build_ghost = Node3D.new()
	var ghost_mat := make_ghost_material(build_id, color)
	var model_path: String = recipe.get("model", "") as String
	var used_glb := false
	if not model_path.is_empty():
		used_glb = add_building_glb(pc._build_ghost, model_path, sz, ghost_mat)
	if not used_glb:
		var mi := MeshInstance3D.new()
		var mesh: Mesh
		if mesh_type in ["roof_45", "roof_26"]:
			mesh = build_roof_mesh(sz, sz.y)
		elif mesh_type in ["roof_45_ocorner", "roof_26_ocorner"]:
			mesh = build_roof_ocorner_mesh(sz, sz.y)
		elif mesh_type in ["roof_45_icorner", "roof_26_icorner"]:
			mesh = build_roof_icorner_mesh(sz, sz.y)
		elif mesh_type == "roof_ridge":
			mesh = build_roof_ridge_mesh(sz)
		elif mesh_type == "stair":
			mesh = build_stair_mesh(sz)
		elif mesh_type == "cylinder":
			var cyl := CylinderMesh.new()
			cyl.top_radius = sz.x * 0.5
			cyl.bottom_radius = sz.x * 0.5
			cyl.height = sz.y
			mesh = cyl
		else:
			var bx := BoxMesh.new()
			bx.size = sz
			mesh = bx
		mi.mesh = mesh
		mi.set_surface_override_material(0, ghost_mat)
		if mesh_type.begins_with("roof"):
			mi.position.y = 0.0
		else:
			mi.position.y = 0.0 if mesh_type == "stair" else sz.y * 0.5
		pc._build_ghost.add_child(mi)
	pc.get_tree().current_scene.add_child(pc._build_ghost)

	if pc._snap_label:
		pc._snap_label.visible = true
		pc._snap_label.text = "Snap: ON" if pc._build_snap_enabled else "Snap: OFF"
		pc._snap_label.add_theme_color_override("font_color",
			Color(0.6, 1.0, 0.6) if pc._build_snap_enabled else Color(1.0, 0.5, 0.5))
	if pc._build_crosshair:
		pc._build_crosshair.visible = true


func update_build_ghost() -> void:
	var cam := pc.get_viewport().get_camera_3d()
	if not cam:
		return
	var forward := -cam.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var place_pos := pc.global_position + forward * 3.5
	place_pos.y = pc.global_position.y

	var recipe := get_build_recipe(pc._build_selected)
	var is_water_only := recipe.get("water_only", false) as bool

	if is_water_only:
		var water_y := WaterSystem.get_surface_y(place_pos.x, place_pos.z)
		place_pos.y = water_y
		var terrain_y := place_pos.y - 10.0
		var space := pc.get_world_3d().direct_space_state
		if space:
			var ray_from := Vector3(place_pos.x, water_y + 50.0, place_pos.z)
			var ray_to := Vector3(place_pos.x, water_y - 50.0, place_pos.z)
			var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1)
			query.exclude = [pc.get_rid()]
			var result := space.intersect_ray(query)
			if not result.is_empty():
				terrain_y = result["position"].y
		if terrain_y > water_y - 0.1:
			pc._build_ghost.global_position = place_pos
			pc._build_ghost.rotation.y = pc._build_rotation
			var mi := pc._build_ghost.get_child(0) as MeshInstance3D
			if mi:
				var mat := mi.get_surface_override_material(0) as StandardMaterial3D
				if mat:
					mat.albedo_color = Color(0.9, 0.2, 0.2, 0.4)
			return
	else:
		var space := pc.get_world_3d().direct_space_state
		if space:
			var ray_from := Vector3(place_pos.x, place_pos.y + 50.0, place_pos.z)
			var ray_to := Vector3(place_pos.x, place_pos.y - 50.0, place_pos.z)
			var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1)
			query.exclude = [pc.get_rid()]
			var result := space.intersect_ray(query)
			if not result.is_empty():
				place_pos.y = result["position"].y
				var bid: StringName = recipe.get("id", &"") as StringName
				if bid in [&"wood_floor", &"stone_floor"]:
					place_pos.y -= 0.05

	var use_rot := pc._build_rotation
	pc._build_snapped = false

	if pc._build_snap_enabled and not is_water_only:
		if not recipe.is_empty():
			var bid: StringName = recipe.get("id", &"") as StringName
			var sz: Vector3 = recipe.get("size", Vector3.ONE) as Vector3
			var snap := find_best_snap(place_pos, pc._build_rotation, bid, sz)
			if not snap.is_empty():
				place_pos = snap["pos"] as Vector3
				use_rot = snap["rot_y"] as float
				pc._build_snapped = true

	pc._build_ghost.global_position = place_pos
	pc._build_ghost.rotation.y = use_rot
	update_ghost_snap_color(pc._build_snapped)


func place_build() -> void:
	var recipe := get_build_recipe(pc._build_selected)
	if recipe.is_empty():
		cancel_build_mode()
		return

	var is_water_only := recipe.get("water_only", false) as bool
	if is_water_only:
		var ghost_pos := pc._build_ghost.global_position
		var water_y := WaterSystem.get_surface_y(ghost_pos.x, ghost_pos.z)
		var space := pc.get_world_3d().direct_space_state
		var terrain_y := water_y - 20.0
		if space:
			var ray_from := Vector3(ghost_pos.x, water_y + 50.0, ghost_pos.z)
			var ray_to := Vector3(ghost_pos.x, water_y - 50.0, ghost_pos.z)
			var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1)
			query.exclude = [pc.get_rid()]
			var result := space.intersect_ray(query)
			if not result.is_empty():
				terrain_y = result["position"].y
		if terrain_y > water_y - 0.1:
			return

	if not pc._build_from_workbench and not Inventory.has_free_craft():
		var costs: Array = recipe.get("cost", []) as Array
		for mat: Dictionary in costs:
			var mat_id: StringName = mat["item"] as StringName
			var mat_amt: int = int(mat["amount"])
			if not Inventory.has_item_any_star(mat_id, mat_amt):
				return
		for mat: Dictionary in costs:
			Inventory.remove_item_any_star(mat["item"] as StringName, int(mat["amount"]))
	pc._build_from_workbench = false

	var build_id: StringName = recipe.get("id", &"") as StringName
	var sz: Vector3 = recipe.get("size", Vector3(1, 1, 1)) as Vector3
	var color: Color = recipe.get("color", Color(0.5, 0.4, 0.2)) as Color
	var mesh_type: String = recipe.get("mesh", "box") as String

	if build_id == &"raft":
		spawn_raft(pc._build_ghost.global_position, pc._build_ghost.rotation.y)
		AudioManager.play_sfx_at("wood_thud", pc._build_ghost.global_position, -2.0, 0.2)
		return

	var structure := StaticBody3D.new()
	var _deferred_campfire := mesh_type == "campfire"
	var _is_workbench := mesh_type == "workbench"
	var _is_chest := build_id == &"chest"
	var _is_wall_torch := mesh_type == "wall_torch"
	var _is_bed := mesh_type == "bed"
	var _is_door := mesh_type == "door"

	structure.add_to_group(&"structures")
	structure.set_meta("build_id", build_id)

	var model_path: String = recipe.get("model", "") as String
	var _used_glb := false
	if not model_path.is_empty():
		_used_glb = add_building_glb(structure, model_path, sz, null, color)

	if not _used_glb:
		if _is_workbench:
			build_workbench_visual(structure, sz, color)
		elif _is_chest:
			build_chest_visual(structure, sz)
		elif _is_wall_torch:
			build_wall_torch_visual(structure)
		elif _is_bed:
			build_bed_visual(structure, sz)
		elif _is_door:
			pc._build_door_visual(structure, sz, build_id)

	if _is_workbench:
		structure.add_to_group(&"workbenches")
	elif _is_chest:
		structure.add_to_group(&"chests")
	elif _is_door:
		structure.add_to_group(&"doors")
		structure.set_meta("door_open", false)

	var _is_roof := mesh_type.begins_with("roof")

	if not _used_glb:
		if _deferred_campfire:
			pass
		elif not _is_workbench and not _is_chest and not _is_wall_torch and not _is_bed and not _is_door:
			var mi := MeshInstance3D.new()
			var mesh: Mesh
			if mesh_type in ["roof_45", "roof_26"]:
				mesh = build_roof_mesh(sz, sz.y)
			elif mesh_type in ["roof_45_ocorner", "roof_26_ocorner"]:
				mesh = build_roof_ocorner_mesh(sz, sz.y)
			elif mesh_type in ["roof_45_icorner", "roof_26_icorner"]:
				mesh = build_roof_icorner_mesh(sz, sz.y)
			elif mesh_type == "roof_ridge":
				mesh = build_roof_ridge_mesh(sz)
			elif mesh_type == "stair":
				mesh = build_stair_mesh(sz)
			elif mesh_type == "cylinder":
				var cyl := CylinderMesh.new()
				cyl.top_radius = sz.x * 0.5
				cyl.bottom_radius = sz.x * 0.5
				cyl.height = sz.y
				mesh = cyl
			else:
				var bx := BoxMesh.new()
				bx.size = sz
				mesh = bx
			mi.mesh = mesh
			var bmat := get_building_material(build_id)
			if bmat:
				mi.set_surface_override_material(0, bmat)
			else:
				var mat := StandardMaterial3D.new()
				mat.albedo_color = color
				mat.roughness = 0.85
				mi.set_surface_override_material(0, mat)
			if _is_roof:
				mi.position.y = 0.0
			else:
				mi.position.y = 0.0 if mesh_type == "stair" else sz.y * 0.5
			structure.add_child(mi)

	var _is_stair := mesh_type == "stair"
	if _is_stair:
		add_stair_collision(structure, sz)
	elif _is_door:
		pass
	else:
		var col_shape := CollisionShape3D.new()
		var col: Shape3D
		if mesh_type == "cylinder" or mesh_type == "campfire":
			var cyl_col := CylinderShape3D.new()
			cyl_col.radius = sz.x * 0.5
			cyl_col.height = sz.y
			col = cyl_col
		elif _is_wall_torch:
			var box_col := BoxShape3D.new()
			box_col.size = Vector3(0.2, 0.6, 0.2)
			col = box_col
		elif _is_roof:
			var box_col := BoxShape3D.new()
			box_col.size = Vector3(sz.x, sz.y * 0.5, sz.z)
			col = box_col
			col_shape.position.y = sz.y * 0.25
		else:
			var box_col := BoxShape3D.new()
			box_col.size = sz
			col = box_col
		col_shape.shape = col
		if not _is_roof:
			col_shape.position.y = sz.y * 0.5
		structure.add_child(col_shape)

	var target_pos := pc._build_ghost.global_position
	var target_rot := pc._build_ghost.rotation.y
	pc.get_tree().current_scene.add_child(structure)
	structure.global_position = target_pos
	structure.rotation.y = target_rot

	var snap_pts := get_snap_points_for(build_id, sz)
	if not snap_pts.is_empty():
		structure.set_meta("snap_points", snap_pts)

	if _deferred_campfire:
		build_campfire_visual(structure, sz)
	else:
		setup_structure_distance_cull(structure)

	if build_id == &"torch_post":
		add_torch_light(structure, Vector3(0.0, sz.y + 0.1, 0.0))

	disable_structure_shadows(structure)
	AudioManager.play_sfx_at("wood_thud", structure.global_position, -4.0, 0.2)


func rebuild_structure(build_id_str: String, pos: Vector3, rot_y: float) -> void:
	var build_id := StringName(build_id_str)
	var recipe: Dictionary = {}
	for r: Dictionary in BUILD_RECIPES:
		if r.get("id", &"") == build_id:
			recipe = r
			break
	if recipe.is_empty():
		return

	var sz: Vector3 = recipe.get("size", Vector3(1, 1, 1)) as Vector3
	var color: Color = recipe.get("color", Color(0.5, 0.4, 0.2)) as Color
	var mesh_type: String = recipe.get("mesh", "box") as String

	var structure := StaticBody3D.new()
	var is_campfire := mesh_type == "campfire"
	var is_workbench := mesh_type == "workbench"
	var is_chest := build_id == &"chest"
	var is_wall_torch := mesh_type == "wall_torch"
	var is_bed := mesh_type == "bed"
	var is_door := mesh_type == "door"

	structure.add_to_group(&"structures")
	structure.set_meta("build_id", build_id)

	var is_roof := mesh_type.begins_with("roof")

	var rb_model_path: String = recipe.get("model", "") as String
	var rb_used_glb := false
	if not rb_model_path.is_empty():
		rb_used_glb = add_building_glb(structure, rb_model_path, sz, null, color)

	if not rb_used_glb:
		if is_workbench:
			build_workbench_visual(structure, sz, color)
		elif is_chest:
			build_chest_visual(structure, sz)
		elif is_wall_torch:
			build_wall_torch_visual(structure)
		elif is_bed:
			build_bed_visual(structure, sz)
		elif is_door:
			pc._build_door_visual(structure, sz, build_id)
		elif not is_campfire:
			var mi := MeshInstance3D.new()
			var mesh: Mesh
			if mesh_type in ["roof_45", "roof_26"]:
				mesh = build_roof_mesh(sz, sz.y)
			elif mesh_type in ["roof_45_ocorner", "roof_26_ocorner"]:
				mesh = build_roof_ocorner_mesh(sz, sz.y)
			elif mesh_type in ["roof_45_icorner", "roof_26_icorner"]:
				mesh = build_roof_icorner_mesh(sz, sz.y)
			elif mesh_type == "roof_ridge":
				mesh = build_roof_ridge_mesh(sz)
			elif mesh_type == "stair":
				mesh = build_stair_mesh(sz)
			elif mesh_type == "cylinder":
				var cyl := CylinderMesh.new()
				cyl.top_radius = sz.x * 0.5
				cyl.bottom_radius = sz.x * 0.5
				cyl.height = sz.y
				mesh = cyl
			else:
				var bx := BoxMesh.new()
				bx.size = sz
				mesh = bx
			mi.mesh = mesh
			var bmat := get_building_material(build_id)
			if bmat:
				mi.set_surface_override_material(0, bmat)
			else:
				var mat := StandardMaterial3D.new()
				mat.albedo_color = color
				mat.roughness = 0.85
				mi.set_surface_override_material(0, mat)
			if is_roof:
				mi.position.y = 0.0
			else:
				mi.position.y = 0.0 if mesh_type == "stair" else sz.y * 0.5
			structure.add_child(mi)

	if is_workbench:
		structure.add_to_group(&"workbenches")
	elif is_chest:
		structure.add_to_group(&"chests")
	elif is_door:
		structure.add_to_group(&"doors")
		structure.set_meta("door_open", false)

	var is_stair := mesh_type == "stair"
	if is_stair:
		add_stair_collision(structure, sz)
	elif is_door:
		pass
	else:
		var col_shape := CollisionShape3D.new()
		var col: Shape3D
		if mesh_type == "cylinder" or mesh_type == "campfire":
			var cyl_col := CylinderShape3D.new()
			cyl_col.radius = sz.x * 0.5
			cyl_col.height = sz.y
			col = cyl_col
		elif is_wall_torch:
			var box_col := BoxShape3D.new()
			box_col.size = Vector3(0.2, 0.6, 0.2)
			col = box_col
		elif is_roof:
			var box_col := BoxShape3D.new()
			box_col.size = Vector3(sz.x, sz.y * 0.5, sz.z)
			col = box_col
			col_shape.position.y = sz.y * 0.25
		else:
			var box_col := BoxShape3D.new()
			box_col.size = sz
			col = box_col
		col_shape.shape = col
		if not is_roof:
			col_shape.position.y = sz.y * 0.5
		structure.add_child(col_shape)

	pc.get_tree().current_scene.add_child(structure)
	structure.global_position = pos
	structure.rotation.y = rot_y

	clear_vegetation_at(pos, sz)

	var snap_pts := get_snap_points_for(build_id, sz)
	if not snap_pts.is_empty():
		structure.set_meta("snap_points", snap_pts)

	if is_campfire:
		build_campfire_visual(structure, sz)
	else:
		setup_structure_distance_cull(structure)

	if build_id == &"torch_post":
		add_torch_light(structure, Vector3(0.0, sz.y + 0.1, 0.0))

	disable_structure_shadows(structure)


func clear_vegetation_at(pos: Vector3, sz: Vector3) -> void:
	var radius := maxf(sz.x, sz.z) * 0.55
	var r2 := radius * radius

	for node: Node3D in pc.get_tree().get_nodes_in_group(&"interactables"):
		if not is_instance_valid(node):
			continue
		var dx := node.global_position.x - pos.x
		var dz := node.global_position.z - pos.z
		if dx * dx + dz * dz < r2:
			node.queue_free()

	clear_grass_multimesh_at(pos, r2)


func clear_grass_multimesh_at(pos: Vector3, r2: float) -> void:
	var scene_root := pc.get_tree().current_scene
	if not scene_root:
		return
	for zone in scene_root.get_children():
		if not zone is Node3D:
			continue
		var zone_origin := (zone as Node3D).global_position
		for child in zone.get_children():
			var mmi := child as MultiMeshInstance3D
			if not mmi or not mmi.name.begins_with("Grass_"):
				continue
			var mm := mmi.multimesh
			if not mm or mm.instance_count == 0:
				continue
			var kept: Array[Transform3D] = []
			for i in mm.instance_count:
				var t := mm.get_instance_transform(i)
				var wx := zone_origin.x + t.origin.x
				var wz := zone_origin.z + t.origin.z
				var dx := wx - pos.x
				var dz := wz - pos.z
				if dx * dx + dz * dz >= r2:
					kept.append(t)
			if kept.size() == mm.instance_count:
				continue
			if kept.is_empty():
				mmi.queue_free()
			else:
				mm.instance_count = kept.size()
				for idx in kept.size():
					mm.set_instance_transform(idx, kept[idx])


func cancel_build_mode() -> void:
	if pc._build_from_workbench and pc._build_selected != &"":
		var item_data := ItemDatabase.get_item(pc._build_selected)
		var recipe_var = item_data.get("recipe", [])
		var recipe: Array = recipe_var if recipe_var is Array else []
		for ingredient in recipe:
			if not ingredient is Dictionary:
				continue
			var req_id: StringName = StringName(str(ingredient.get("item_id", "")))
			var req_amount: int = int(ingredient.get("amount", 0))
			Inventory.add_item(req_id, req_amount)
	pc._build_from_workbench = false
	pc._build_mode = false
	pc._build_selected = &""
	pc._build_snapped = false
	if pc._build_ghost:
		pc._build_ghost.queue_free()
		pc._build_ghost = null
	if pc._snap_label:
		pc._snap_label.visible = false
	if pc._build_crosshair:
		pc._build_crosshair.visible = false


func try_salvage_structure() -> void:
	var cam: Camera3D = pc._spring_arm.get_child(0) if pc._spring_arm.get_child_count() > 0 else null
	if not cam:
		return
	var from := cam.global_position
	var forward := -cam.global_transform.basis.z
	var to := from + forward * 5.0

	var best_node: Node3D = null
	var best_dist := INF

	for node in pc.get_tree().get_nodes_in_group(&"structures"):
		var s3d := node as Node3D
		if not s3d or not is_instance_valid(s3d):
			continue
		var dist := s3d.global_position.distance_to(pc.global_position)
		if dist > 5.0:
			continue
		var to_struct := (s3d.global_position - from)
		to_struct.y = 0.0
		var fwd_flat := Vector3(forward.x, 0.0, forward.z).normalized()
		if to_struct.normalized().dot(fwd_flat) < 0.3:
			continue
		if dist < best_dist:
			best_dist = dist
			best_node = s3d

	if not best_node:
		return

	var build_id: StringName = best_node.get_meta("build_id", &"") as StringName
	if build_id == &"":
		return

	var recipe := get_build_recipe(build_id)
	var costs: Array = recipe.get("cost", []) as Array
	for mat: Dictionary in costs:
		var mat_id: StringName = mat.get("item", &"") as StringName
		var mat_amt: int = int(mat.get("amount", 0))
		var refund := maxi(ceili(mat_amt * 0.5), 1)
		Inventory.add_item(mat_id, refund)

	AudioManager.play_sfx_at("wood_thud", best_node.global_position, -2.0, 0.15)

	var msg := _DamageNumber.new()
	msg.text = "Salvaged"
	msg.font_size = 18
	msg.pixel_size = 0.008
	msg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	msg.no_depth_test = true
	msg.modulate = Color(1.0, 0.85, 0.4)
	msg.outline_modulate = Color.BLACK
	msg.outline_size = 5
	msg._velocity = Vector3(0, 1.5, 0)
	pc.get_tree().current_scene.add_child(msg)
	msg.global_position = best_node.global_position + Vector3(0, 1.5, 0)

	best_node.queue_free()


func get_build_recipe(build_id: StringName) -> Dictionary:
	for recipe: Dictionary in BUILD_RECIPES:
		if recipe["id"] as StringName == build_id:
			return recipe
	return {}


# ── Building material cache ──────────────────────────────────────────────────
static func ensure_building_materials() -> void:
	if _bmat_wood != null:
		return
	_bmat_wood = load_building_mat("res://textures/building/wood_planks.png",
		Color(0.50, 0.38, 0.22), 0.80, Vector3(4.0, 4.0, 1.0))
	_bmat_stone = load_building_mat("res://textures/building/cobblestone.png",
		Color(0.70, 0.70, 0.73), 0.92, Vector3(4.0, 4.0, 1.0))
	_bmat_thatch = load_building_mat("res://textures/building/thatch.png",
		Color(0.60, 0.50, 0.30), 0.85, Vector3(2.0, 2.0, 1.0))
	_bmat_slate = load_building_mat("res://textures/building/slate_roof.png",
		Color(0.50, 0.50, 0.55), 0.90, Vector3(2.0, 2.0, 1.0))

static func load_building_mat(path: String, tint: Color, rough: float, uv_scale: Vector3) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex := load(path) as Texture2D
	if tex:
		mat.albedo_texture = tex
		mat.albedo_color = tint
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	else:
		mat.albedo_color = tint
	mat.roughness = rough
	mat.uv1_scale = uv_scale
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func get_building_material(build_id: StringName) -> StandardMaterial3D:
	ensure_building_materials()
	if build_id in [&"wood_wall", &"wood_floor", &"wood_stair", &"wood_door"]:
		return _bmat_wood
	elif build_id in [&"stone_wall", &"stone_floor", &"stone_door"]:
		return _bmat_stone
	elif build_id.begins_with(&"thatch_roof"):
		return _bmat_thatch
	elif build_id.begins_with(&"slate_roof"):
		return _bmat_slate
	return null

func make_ghost_material(build_id: StringName, fallback_color: Color) -> StandardMaterial3D:
	var base := get_building_material(build_id)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if base and base.albedo_texture:
		mat.albedo_texture = base.albedo_texture
		mat.albedo_color = Color(base.albedo_color.r, base.albedo_color.g, base.albedo_color.b, 0.45)
		mat.uv1_scale = base.uv1_scale
		mat.texture_filter = base.texture_filter
	else:
		mat.albedo_color = Color(fallback_color.r, fallback_color.g, fallback_color.b, 0.45)
	return mat


# ── Roof wedge mesh ──────────────────────────────────────────────────────────
static func build_roof_mesh(sz: Vector3, rise: float) -> ArrayMesh:
	var hw := sz.x * 0.5
	var hd := sz.z * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var v0 := Vector3(-hw, 0.0, -hd)
	var v1 := Vector3( hw, 0.0, -hd)
	var v2 := Vector3( hw, 0.0,  hd)
	var v3 := Vector3(-hw, 0.0,  hd)
	var v4 := Vector3(-hw, rise,  hd)
	var v5 := Vector3( hw, rise,  hd)

	# Slope face (visible from above)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_uv(Vector2(1, 0)); st.add_vertex(v1)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v5)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v5)
	st.set_uv(Vector2(0, 1)); st.add_vertex(v4)

	# Bottom face
	st.set_uv(Vector2(0, 0)); st.add_vertex(v3)
	st.set_uv(Vector2(1, 0)); st.add_vertex(v2)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v1)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v3)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v1)
	st.set_uv(Vector2(0, 1)); st.add_vertex(v0)

	# Back face (vertical at +Z)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v3)
	st.set_uv(Vector2(0, 1)); st.add_vertex(v4)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v5)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v3)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v5)
	st.set_uv(Vector2(1, 0)); st.add_vertex(v2)

	# Left triangle
	st.set_uv(Vector2(0, 1)); st.add_vertex(v0)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v4)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v3)

	# Right triangle
	st.set_uv(Vector2(1, 1)); st.add_vertex(v1)
	st.set_uv(Vector2(0, 1)); st.add_vertex(v2)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v5)

	st.generate_normals()
	return st.commit()


static func build_roof_ocorner_mesh(sz: Vector3, rise: float) -> ArrayMesh:
	var hw := sz.x * 0.5
	var hd := sz.z * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var peak := Vector3(hw, rise, hd)
	var bl := Vector3(-hw, 0.0, -hd)
	var br := Vector3( hw, 0.0, -hd)
	var fl := Vector3(-hw, 0.0,  hd)
	var fr := Vector3( hw, 0.0,  hd)
	# Front slope (-Z face, from front-left and front-right up to peak)
	st.set_uv(Vector2(0, 1)); st.add_vertex(bl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	st.set_uv(Vector2(1, 0)); st.add_vertex(peak)
	# Right slope (+X face, from front-right and back-right up to peak)
	st.set_uv(Vector2(0, 1)); st.add_vertex(br)
	st.set_uv(Vector2(1, 1)); st.add_vertex(fr)
	st.set_uv(Vector2(1, 0)); st.add_vertex(peak)
	# Back wall (+Z face)
	st.set_uv(Vector2(0, 1)); st.add_vertex(fr)
	st.set_uv(Vector2(0, 0)); st.add_vertex(peak)
	st.set_uv(Vector2(1, 1)); st.add_vertex(fl)
	# Left wall (-X face)
	st.set_uv(Vector2(0, 1)); st.add_vertex(fl)
	st.set_uv(Vector2(0, 0)); st.add_vertex(peak)
	st.set_uv(Vector2(1, 1)); st.add_vertex(bl)
	# Bottom face
	st.set_uv(Vector2(0, 0)); st.add_vertex(fl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(fr)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	st.set_uv(Vector2(0, 0)); st.add_vertex(fl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	st.set_uv(Vector2(0, 1)); st.add_vertex(bl)
	st.generate_normals()
	return st.commit()


static func build_roof_icorner_mesh(sz: Vector3, rise: float) -> ArrayMesh:
	var hw := sz.x * 0.5
	var hd := sz.z * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tl := Vector3(-hw, rise,  hd)
	var tr := Vector3( hw, rise,  hd)
	var tb := Vector3( hw, rise, -hd)
	var valley := Vector3(-hw, 0.0, -hd)
	var bl := Vector3(-hw, 0.0, -hd)
	var br := Vector3( hw, 0.0, -hd)
	var fl := Vector3(-hw, 0.0,  hd)
	# Left slope: tl → fl → valley (triangle covering -X side)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
	st.set_uv(Vector2(0, 1)); st.add_vertex(fl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(valley)
	# Front slope: tl → valley → tb (the inner valley surface)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(valley)
	st.set_uv(Vector2(1, 0)); st.add_vertex(tb)
	# Right slope: tb → valley → br (triangle covering -Z side)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tb)
	st.set_uv(Vector2(0, 1)); st.add_vertex(valley)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	# Back wall (+Z face, vertical)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(tr)
	st.set_uv(Vector2(1, 1)); st.add_vertex(fl)
	# Right wall (+X face, vertical)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tr)
	st.set_uv(Vector2(1, 0)); st.add_vertex(tb)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	# Top flat between ridges
	st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(tr)
	st.set_uv(Vector2(1, 1)); st.add_vertex(tb)
	# Bottom face
	st.set_uv(Vector2(0, 0)); st.add_vertex(fl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(br)
	st.set_uv(Vector2(1, 1)); st.add_vertex(bl)
	st.generate_normals()
	return st.commit()


static func build_roof_ridge_mesh(sz: Vector3) -> ArrayMesh:
	var hw := sz.x * 0.5
	var hh := sz.y * 0.5
	var hd := sz.z * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v0 := Vector3(-hw, -hh, -hd)
	var v1 := Vector3( hw, -hh, -hd)
	var v2 := Vector3( hw,  hh, -hd)
	var v3 := Vector3(-hw,  hh, -hd)
	var v4 := Vector3(-hw, -hh,  hd)
	var v5 := Vector3( hw, -hh,  hd)
	var v6 := Vector3( hw,  hh,  hd)
	var v7 := Vector3(-hw,  hh,  hd)
	var faces := [
		[v3, v2, v1, v0],
		[v4, v5, v6, v7],
		[v0, v1, v5, v4],
		[v2, v3, v7, v6],
		[v3, v0, v4, v7],
		[v1, v2, v6, v5],
	]
	for f in faces:
		st.set_uv(Vector2(0, 0)); st.add_vertex(f[0])
		st.set_uv(Vector2(1, 0)); st.add_vertex(f[1])
		st.set_uv(Vector2(1, 1)); st.add_vertex(f[2])
		st.set_uv(Vector2(0, 0)); st.add_vertex(f[0])
		st.set_uv(Vector2(1, 1)); st.add_vertex(f[2])
		st.set_uv(Vector2(0, 1)); st.add_vertex(f[3])
	st.generate_normals()
	return st.commit()


static func build_stair_mesh(sz: Vector3, step_count: int = 6) -> ArrayMesh:
	var hw := sz.x * 0.5
	var step_h := sz.y / float(step_count)
	var step_d := sz.z / float(step_count)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(step_count):
		var y0 := step_h * float(i)
		var y1 := step_h * float(i + 1)
		var z0 := -sz.z * 0.5 + step_d * float(i)
		var z1 := -sz.z * 0.5 + step_d * float(i + 1)

		var a := Vector3(-hw, y1, z0)
		var b := Vector3( hw, y1, z0)
		var c := Vector3( hw, y1, z1)
		var d := Vector3(-hw, y1, z1)
		var e := Vector3(-hw, y0, z0)
		var f := Vector3( hw, y0, z0)

		# Top face (tread)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b)
		st.set_uv(Vector2(1, 1)); st.add_vertex(c)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a)
		st.set_uv(Vector2(1, 1)); st.add_vertex(c)
		st.set_uv(Vector2(0, 1)); st.add_vertex(d)

		# Front face (riser)
		st.set_uv(Vector2(0, 0)); st.add_vertex(e)
		st.set_uv(Vector2(1, 0)); st.add_vertex(f)
		st.set_uv(Vector2(1, 1)); st.add_vertex(b)
		st.set_uv(Vector2(0, 0)); st.add_vertex(e)
		st.set_uv(Vector2(1, 1)); st.add_vertex(b)
		st.set_uv(Vector2(0, 1)); st.add_vertex(a)

	# Left side face
	var bl := Vector3(-hw, 0.0, -sz.z * 0.5)
	var tl := Vector3(-hw, sz.y, sz.z * 0.5)
	var br := Vector3(-hw, 0.0, sz.z * 0.5)
	st.set_uv(Vector2(0, 0)); st.add_vertex(bl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(tl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(br)

	# Right side face
	var rbl := Vector3(hw, 0.0, -sz.z * 0.5)
	var rtl := Vector3(hw, sz.y, sz.z * 0.5)
	var rbr := Vector3(hw, 0.0, sz.z * 0.5)
	st.set_uv(Vector2(0, 0)); st.add_vertex(rbl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(rbr)
	st.set_uv(Vector2(1, 1)); st.add_vertex(rtl)

	# Bottom face
	var b0 := Vector3(-hw, 0.0, -sz.z * 0.5)
	var b1 := Vector3( hw, 0.0, -sz.z * 0.5)
	var b2 := Vector3( hw, 0.0,  sz.z * 0.5)
	var b3 := Vector3(-hw, 0.0,  sz.z * 0.5)
	st.set_uv(Vector2(0, 0)); st.add_vertex(b3)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b2)
	st.set_uv(Vector2(1, 1)); st.add_vertex(b1)
	st.set_uv(Vector2(0, 0)); st.add_vertex(b3)
	st.set_uv(Vector2(1, 1)); st.add_vertex(b1)
	st.set_uv(Vector2(0, 1)); st.add_vertex(b0)

	st.generate_normals()
	return st.commit()


static func add_stair_collision(structure: StaticBody3D, sz: Vector3, _step_count: int = 6) -> void:
	var phys_steps := ceili(sz.y / 0.3)
	var step_h := sz.y / float(phys_steps)
	var step_d := sz.z / float(phys_steps)
	for i in range(phys_steps):
		var col_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var height := step_h * float(i + 1)
		box.size = Vector3(sz.x, height, step_d)
		col_shape.shape = box
		var z_center := -sz.z * 0.5 + step_d * (float(i) + 0.5)
		col_shape.position = Vector3(0.0, height * 0.5, z_center)
		structure.add_child(col_shape)


# ── Snap system ──────────────────────────────────────────────────────────────
static func get_roof_angle_group(build_id: StringName) -> int:
	if "45" in str(build_id):
		return 45
	elif "26" in str(build_id):
		return 26
	return 0

func get_snap_points_for(build_id: StringName, sz: Vector3) -> Array[Dictionary]:
	var pts: Array[Dictionary] = []
	var hw := sz.x * 0.5
	var hd := sz.z * 0.5
	var h := sz.y

	if build_id in [&"wood_wall", &"stone_wall", &"wood_door", &"stone_door"]:
		var edge_overlap := 0.10
		for x in [-hw + edge_overlap, 0.0, hw - edge_overlap]:
			pts.append({"pos": Vector3(x, 0.0, 0.0), "type": &"wall_base"})
			pts.append({"pos": Vector3(x, h, 0.0), "type": &"wall_top"})
		pts.append({"pos": Vector3(-hw + edge_overlap, h * 0.5, 0.0), "type": &"wall_side"})
		pts.append({"pos": Vector3( hw - edge_overlap, h * 0.5, 0.0), "type": &"wall_side"})

	elif build_id == &"wood_stair":
		pts.append({"pos": Vector3( 0.0, 0.0, -hd), "type": &"floor_edge"})
		pts.append({"pos": Vector3( 0.0, h,    hd), "type": &"floor_edge"})
		pts.append({"pos": Vector3(-hw,  0.0, -hd), "type": &"floor_corner"})
		pts.append({"pos": Vector3( hw,  0.0, -hd), "type": &"floor_corner"})
		pts.append({"pos": Vector3(-hw,  h,    hd), "type": &"floor_corner"})
		pts.append({"pos": Vector3( hw,  h,    hd), "type": &"floor_corner"})

	elif build_id in [&"wood_floor", &"stone_floor"]:
		pts.append({"pos": Vector3( 0.0, h, -hd), "type": &"floor_edge"})
		pts.append({"pos": Vector3( 0.0, h,  hd), "type": &"floor_edge"})
		pts.append({"pos": Vector3(-hw,  h, 0.0), "type": &"floor_edge"})
		pts.append({"pos": Vector3( hw,  h, 0.0), "type": &"floor_edge"})
		pts.append({"pos": Vector3(-hw, h, -hd), "type": &"floor_corner"})
		pts.append({"pos": Vector3( hw, h, -hd), "type": &"floor_corner"})
		pts.append({"pos": Vector3(-hw, h,  hd), "type": &"floor_corner"})
		pts.append({"pos": Vector3( hw, h,  hd), "type": &"floor_corner"})

	elif build_id.begins_with("thatch_roof") or build_id.begins_with("slate_roof"):
		var ag := get_roof_angle_group(build_id)
		var base_type: StringName = &"roof_base_45" if ag == 45 else &"roof_base_26"
		var ridge_type: StringName = &"roof_ridge_45" if ag == 45 else &"roof_ridge_26"
		var side_type: StringName = &"roof_side_45" if ag == 45 else &"roof_side_26"
		var mesh_type: String = str((get_build_recipe(build_id) as Dictionary).get("mesh", ""))

		if mesh_type in ["roof_45", "roof_26"]:
			for x in [-hw, 0.0, hw]:
				pts.append({"pos": Vector3(x, 0.0, -hd), "type": base_type})
			for x in [-hw, 0.0, hw]:
				pts.append({"pos": Vector3(x, h, hd), "type": ridge_type})
			pts.append({"pos": Vector3(-hw, h * 0.5, 0.0), "type": side_type})
			pts.append({"pos": Vector3( hw, h * 0.5, 0.0), "type": side_type})

		elif mesh_type in ["roof_45_ocorner", "roof_26_ocorner"]:
			for x in [-hw, 0.0, hw]:
				pts.append({"pos": Vector3(x, 0.0, -hd), "type": base_type})
			for z in [-hd, 0.0, hd]:
				pts.append({"pos": Vector3(hw, 0.0, z), "type": base_type})
			pts.append({"pos": Vector3(hw, h, hd), "type": ridge_type})

		elif mesh_type in ["roof_45_icorner", "roof_26_icorner"]:
			for x in [-hw, 0.0, hw]:
				pts.append({"pos": Vector3(x, 0.0, -hd), "type": base_type})
			for z in [-hd, 0.0, hd]:
				pts.append({"pos": Vector3(-hw, 0.0, z), "type": base_type})
			for x in [-hw, 0.0, hw]:
				pts.append({"pos": Vector3(x, h, hd), "type": ridge_type})
			for z in [-hd, 0.0, hd]:
				pts.append({"pos": Vector3(hw, h, z), "type": ridge_type})

		elif mesh_type == "roof_ridge":
			pts.append({"pos": Vector3(-hw, 0.0, 0.0), "type": &"ridge_cap_end"})
			pts.append({"pos": Vector3( hw, 0.0, 0.0), "type": &"ridge_cap_end"})
			pts.append({"pos": Vector3( 0.0, 0.0, -hd), "type": &"ridge_cap_end"})
			pts.append({"pos": Vector3( 0.0, 0.0,  hd), "type": &"ridge_cap_end"})

	return pts


func find_best_snap(ghost_pos: Vector3, ghost_rot_y: float, build_id: StringName, sz: Vector3) -> Dictionary:
	var new_points := get_snap_points_for(build_id, sz)
	if new_points.is_empty():
		return {}

	var new_ag := get_roof_angle_group(build_id)

	var best_dist := 0.8
	var best_pos := Vector3.ZERO
	var best_rot := ghost_rot_y
	var found := false

	var structures := pc.get_tree().get_nodes_in_group(&"structures")
	for structure in structures:
		if not structure is Node3D:
			continue
		var s3d := structure as Node3D
		if s3d.global_position.distance_to(ghost_pos) > 6.0:
			continue

		var exist_id: StringName = s3d.get_meta("build_id", &"") as StringName
		var exist_recipe := get_build_recipe(exist_id)
		if exist_recipe.is_empty():
			continue

		var exist_ag := get_roof_angle_group(exist_id)
		if new_ag != 0 and exist_ag != 0 and new_ag != exist_ag:
			continue

		var exist_sz: Vector3 = exist_recipe.get("size", Vector3.ONE) as Vector3
		var exist_points := get_snap_points_for(exist_id, exist_sz)
		if exist_points.is_empty():
			continue
		var exist_basis := Basis(Vector3.UP, s3d.rotation.y)

		var rotations: Array[float] = [
			ghost_rot_y,
			s3d.rotation.y,
			s3d.rotation.y + PI * 0.5,
			s3d.rotation.y + PI,
			s3d.rotation.y + PI * 1.5,
		]

		for try_rot: float in rotations:
			var try_basis := Basis(Vector3.UP, try_rot)
			for np: Dictionary in new_points:
				var np_type: StringName = np["type"] as StringName
				var np_local: Vector3 = np["pos"] as Vector3
				var compat_list: Array = SNAP_COMPAT.get(np_type, []) as Array

				for ep: Dictionary in exist_points:
					var ep_type: StringName = ep["type"] as StringName
					if ep_type not in compat_list:
						continue
					var ep_world: Vector3 = s3d.global_position + exist_basis * (ep["pos"] as Vector3)
					var np_world: Vector3 = ghost_pos + try_basis * np_local
					var dist := ep_world.distance_to(np_world)
					if dist < best_dist:
						best_dist = dist
						best_pos = ep_world - try_basis * np_local
						best_rot = try_rot
						found = true

	if found:
		var is_roof_piece := str(build_id).begins_with("thatch_roof") or str(build_id).begins_with("slate_roof")
		if is_roof_piece:
			best_pos.y += Z_FIGHT_OFFSET
		return {"pos": best_pos, "rot_y": best_rot}
	return {}


func update_ghost_snap_color(snapped: bool) -> void:
	if not pc._build_ghost:
		return
	var mi := pc._build_ghost.get_child(0) as MeshInstance3D
	if not mi:
		return
	var mat := mi.get_surface_override_material(0) as StandardMaterial3D
	if not mat:
		return
	if snapped:
		mat.albedo_color = Color(0.3, 0.9, 0.3, 0.5)
	else:
		var recipe := get_build_recipe(pc._build_selected)
		var base_color: Color = recipe.get("color", Color(0.5, 0.4, 0.2)) as Color
		var bmat := get_building_material(pc._build_selected)
		if bmat and bmat.albedo_texture:
			mat.albedo_color = Color(bmat.albedo_color.r, bmat.albedo_color.g, bmat.albedo_color.b, 0.45)
		else:
			mat.albedo_color = Color(base_color.r, base_color.g, base_color.b, 0.45)


func build_snap_label(root: Control) -> void:
	pc._snap_label = Label.new()
	pc._snap_label.name = "SnapLabel"
	pc._snap_label.visible = false
	pc._snap_label.text = "Snap: ON"
	pc._snap_label.add_theme_font_size_override("font_size", 14)
	pc._snap_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	pc._snap_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	pc._snap_label.add_theme_constant_override("shadow_offset_x", 1)
	pc._snap_label.add_theme_constant_override("shadow_offset_y", 1)
	pc._snap_label.set_anchors_preset(Control.PRESET_CENTER)
	pc._snap_label.offset_top = 40
	pc._snap_label.offset_bottom = 60
	pc._snap_label.offset_left = -60
	pc._snap_label.offset_right = 60
	pc._snap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc._snap_label.z_index = 80
	pc._snap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pc._snap_label)


func build_build_crosshair(root: Control) -> void:
	pc._build_crosshair = Control.new()
	pc._build_crosshair.name = "BuildCrosshair"
	pc._build_crosshair.visible = false
	pc._build_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pc._build_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc._build_crosshair.z_index = 90
	pc._build_crosshair.draw.connect(func() -> void:
		var vp_size := pc._build_crosshair.get_viewport_rect().size
		var c := vp_size * 0.5
		var col := Color(1.0, 1.0, 1.0, 0.8)
		var outline := Color(0.0, 0.0, 0.0, 0.5)
		var arm := 10.0
		var gap := 3.0
		for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			pc._build_crosshair.draw_line(c + Vector2(-arm - gap, 0) + off, c + Vector2(-gap, 0) + off, outline, 2.5)
			pc._build_crosshair.draw_line(c + Vector2(gap, 0) + off, c + Vector2(arm + gap, 0) + off, outline, 2.5)
			pc._build_crosshair.draw_line(c + Vector2(0, -arm - gap) + off, c + Vector2(0, -gap) + off, outline, 2.5)
			pc._build_crosshair.draw_line(c + Vector2(0, gap) + off, c + Vector2(0, arm + gap) + off, outline, 2.5)
		pc._build_crosshair.draw_line(c + Vector2(-arm - gap, 0), c + Vector2(-gap, 0), col, 1.5)
		pc._build_crosshair.draw_line(c + Vector2(gap, 0), c + Vector2(arm + gap, 0), col, 1.5)
		pc._build_crosshair.draw_line(c + Vector2(0, -arm - gap), c + Vector2(0, -gap), col, 1.5)
		pc._build_crosshair.draw_line(c + Vector2(0, gap), c + Vector2(0, arm + gap), col, 1.5)
		pc._build_crosshair.draw_circle(c, 1.5, col)
	)
	root.add_child(pc._build_crosshair)


func get_build_icon(recipe_id: StringName) -> Texture2D:
	var path := "res://textures/items/%s.png" % str(recipe_id)
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


# ── GLB / model loading ──────────────────────────────────────────────────────
func add_building_glb(parent: Node3D, model_path: String, sz: Vector3, ghost_mat: Material = null, tint: Color = Color(-1, -1, -1)) -> bool:
	var scene: PackedScene = load(model_path) as PackedScene
	if not scene:
		return false
	var instance := scene.instantiate() as Node3D
	if not instance:
		return false

	var use_tint := tint.r >= 0.0 and not ghost_mat
	var tint_mat: StandardMaterial3D = null
	if use_tint:
		tint_mat = StandardMaterial3D.new()
		tint_mat.albedo_color = tint
		tint_mat.roughness = 0.85
		tint_mat.metallic = 0.0

	var aabb := AABB()
	var found_mesh := false
	for child in instance.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			aabb = aabb.merge(mi.get_aabb()) if found_mesh else mi.get_aabb()
			found_mesh = true
			var mat_to_apply: Material = ghost_mat if ghost_mat else (tint_mat if use_tint and glb_surface_lacks_texture(mi) else null)
			if mat_to_apply:
				for s in mi.mesh.get_surface_count():
					mi.set_surface_override_material(s, mat_to_apply)
	if not found_mesh:
		if instance is MeshInstance3D:
			aabb = (instance as MeshInstance3D).get_aabb()
			found_mesh = true
			var mi := instance as MeshInstance3D
			var mat_to_apply: Material = ghost_mat if ghost_mat else (tint_mat if use_tint and glb_surface_lacks_texture(mi) else null)
			if mat_to_apply:
				for s in mi.mesh.get_surface_count():
					mi.set_surface_override_material(s, mat_to_apply)
	if found_mesh and aabb.size.length() > 0.01:
		var scale_x := sz.x / maxf(aabb.size.x, 0.001)
		var scale_y := sz.y / maxf(aabb.size.y, 0.001)
		var scale_z := sz.z / maxf(aabb.size.z, 0.001)
		instance.scale = Vector3(scale_x, scale_y, scale_z)
		instance.position.y = sz.y * 0.5
	else:
		instance.position.y = sz.y * 0.5
	parent.add_child(instance)
	return true


func glb_surface_lacks_texture(mi: MeshInstance3D) -> bool:
	if not mi.mesh:
		return true
	for s in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(s)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if sm.albedo_texture:
				return false
			if sm.albedo_color != Color(1, 1, 1, 1) and sm.albedo_color != Color(0.8, 0.8, 0.8, 1):
				return false
		elif mat is ShaderMaterial:
			return false
	return true


func add_torch_light(structure: Node3D, offset: Vector3) -> void:
	var light := OmniLight3D.new()
	light.name = "TorchLight"
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 9.0
	light.omni_range = 52.5
	light.shadow_enabled = true
	light.position = offset
	structure.add_child(light)


func build_wall_torch_visual(structure: StaticBody3D) -> void:
	# Bracket (small box against the wall)
	var bracket := MeshInstance3D.new()
	var br_mesh := BoxMesh.new()
	br_mesh.size = Vector3(0.08, 0.15, 0.12)
	bracket.mesh = br_mesh
	var br_mat := StandardMaterial3D.new()
	br_mat.albedo_color = Color(0.3, 0.22, 0.1)
	br_mat.roughness = 0.9
	bracket.set_surface_override_material(0, br_mat)
	bracket.position = Vector3(0.0, 1.6, 0.0)
	structure.add_child(bracket)

	# Torch stick
	var stick := MeshInstance3D.new()
	var stick_mesh := CylinderMesh.new()
	stick_mesh.top_radius = 0.025
	stick_mesh.bottom_radius = 0.035
	stick_mesh.height = 0.5
	stick_mesh.radial_segments = 6
	stick.mesh = stick_mesh
	var stick_mat := StandardMaterial3D.new()
	stick_mat.albedo_color = Color(0.4, 0.28, 0.12)
	stick.set_surface_override_material(0, stick_mat)
	stick.position = Vector3(0.0, 1.85, 0.08)
	stick.rotation.x = deg_to_rad(-15.0)
	structure.add_child(stick)

	# Flame glow (small bright sphere)
	var flame := MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.06
	flame_mesh.height = 0.14
	flame_mesh.radial_segments = 6
	flame_mesh.rings = 3
	flame.mesh = flame_mesh
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.6, 0.1)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.5, 0.1)
	flame_mat.emission_energy_multiplier = 3.0
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.albedo_color.a = 0.8
	flame.set_surface_override_material(0, flame_mat)
	flame.position = Vector3(0.0, 2.12, 0.12)
	structure.add_child(flame)

	# OmniLight3D for actual illumination
	var light := OmniLight3D.new()
	light.name = "TorchLight"
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 10.5
	light.omni_range = 60.0
	light.shadow_enabled = true
	light.position = Vector3(0.0, 2.15, 0.12)
	structure.add_child(light)


static func build_chest_visual(structure: Node3D, sz: Vector3) -> void:
	ensure_building_materials()

	var mat_metal := StandardMaterial3D.new()
	mat_metal.albedo_color = Color(0.25, 0.22, 0.2)
	mat_metal.roughness = 0.5
	mat_metal.metallic = 0.4

	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := BoxMesh.new()
	body_mesh.size = sz
	body.mesh = body_mesh
	body.set_surface_override_material(0, _bmat_wood)
	body.position.y = sz.y * 0.5
	structure.add_child(body)

	var lid := MeshInstance3D.new()
	lid.name = "Lid"
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(sz.x + 0.04, sz.y * 0.15, sz.z + 0.04)
	lid.mesh = lid_mesh
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.35, 0.22, 0.10)
	lid_mat.roughness = 0.85
	lid.set_surface_override_material(0, lid_mat)
	lid.position.y = sz.y + sz.y * 0.075
	structure.add_child(lid)

	var band_mat := mat_metal
	for bx in [-0.2, 0.2]:
		var band := MeshInstance3D.new()
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(0.04, sz.y * 1.15 + 0.02, sz.z + 0.06)
		band.mesh = band_mesh
		band.set_surface_override_material(0, band_mat)
		band.position = Vector3(bx * sz.x, sz.y * 0.575, 0.0)
		structure.add_child(band)

	var latch := MeshInstance3D.new()
	var latch_mesh := BoxMesh.new()
	latch_mesh.size = Vector3(0.08, 0.06, 0.04)
	latch.mesh = latch_mesh
	latch.set_surface_override_material(0, band_mat)
	latch.position = Vector3(0.0, sz.y * 0.7, sz.z * 0.5 + 0.03)
	structure.add_child(latch)


func drop_item_on_ground(item_id: StringName, amount: int, despawn_time: float = 60.0) -> void:
	var parsed := ItemDatabase.parse_star_id(item_id)
	var stars: int = parsed["stars"]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var cam: Camera3D = pc._spring_arm.get_child(0) if pc._spring_arm.get_child_count() > 0 else null
	var forward := -cam.global_transform.basis.z if cam else Vector3.FORWARD
	var fwd_flat := Vector3(forward.x, 0.0, forward.z).normalized()
	var drop_pos := pc.global_position + fwd_flat * 2.0 + Vector3.UP * 0.5
	drop_pos += Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))

	var my_peer: int = pc.multiplayer.get_unique_id() if pc.multiplayer.has_multiplayer_peer() else 0
	var drop := _LootDrop.new()
	drop.item_id = item_id
	drop.star_level = stars
	drop.amount = amount
	drop.pickup_grace = 6.0
	drop.drop_owner_peer = my_peer
	pc.get_tree().current_scene.add_child(drop)
	drop.global_position = drop_pos

	if despawn_time > 0.0:
		pc.get_tree().create_timer(despawn_time).timeout.connect(func():
			if is_instance_valid(drop):
				drop.queue_free()
		)


# ── Campfire ──────────────────────────────────────────────────────────────────
func make_gradient_tex(w: int, h: int, top: Color, bottom: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(h - 1)
		var c := bottom.lerp(top, t)
		for x in w:
			var noise := randf_range(-0.05, 0.05)
			img.set_pixel(x, y, Color(clampf(c.r + noise, 0, 1), clampf(c.g + noise, 0, 1), clampf(c.b + noise, 0, 1), c.a))
	return ImageTexture.create_from_image(img)


func make_solid_tex(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func load_campfire_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path) or FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(abs_path if FileAccess.file_exists(abs_path) else path) == OK:
			return ImageTexture.create_from_image(img)
	return null


func build_campfire_visual(structure: StaticBody3D, sz: Vector3) -> void:
	var log_tex := load_campfire_tex("res://textures/campfire/burning_log.png")
	var ember_tex := load_campfire_tex("res://textures/campfire/ember_bed.png")
	var smoke_tex := load_campfire_tex("res://textures/campfire/smoke.png")

	# Load animated flame frames (12-frame loop)
	var flame_anim_frames: Array[Texture2D] = []
	for fi in 12:
		var path := "res://textures/campfire/flame_frame_%d.png" % fi
		var ftex := load_campfire_tex(path)
		if ftex:
			flame_anim_frames.append(ftex)
	if _DEBUG_LOG: print("[Campfire] Loaded %d flame animation frames" % flame_anim_frames.size())

	var fire_full_tex: Texture2D
	var fire_only_tex: Texture2D
	if flame_anim_frames.size() >= 2:
		fire_full_tex = flame_anim_frames[0]
		fire_only_tex = flame_anim_frames[1]
	else:
		fire_full_tex = load_campfire_tex("res://textures/campfire/campfire_full.png")
		fire_only_tex = load_campfire_tex("res://textures/campfire/flames_only.png")

	if not log_tex:
		log_tex = make_gradient_tex(24, 8, Color(0.15, 0.08, 0.02), Color(0.4, 0.2, 0.05))
	if not ember_tex:
		ember_tex = make_gradient_tex(24, 24, Color(1.0, 0.3, 0.0, 0.9), Color(0.6, 0.1, 0.0, 0.7))
	if not fire_full_tex:
		fire_full_tex = make_gradient_tex(16, 32, Color(1.0, 1.0, 0.3, 0.0), Color(1.0, 0.4, 0.0, 0.95))
	if not fire_only_tex:
		fire_only_tex = make_gradient_tex(16, 32, Color(1.0, 0.9, 0.2, 0.0), Color(1.0, 0.2, 0.0, 0.9))
	if not smoke_tex:
		smoke_tex = make_solid_tex(16, 16, Color(0.6, 0.6, 0.65, 0.15))

	# ── Static logs beneath the fire (3 crossing logs, flat and centered) ──
	for i in 3:
		var log_sp := Sprite3D.new()
		log_sp.texture = log_tex
		log_sp.pixel_size = 0.009
		log_sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		log_sp.shaded = true
		log_sp.transparent = true
		log_sp.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		var la := float(i) * TAU / 3.0
		log_sp.position = Vector3(0.0, 0.06, 0.0)
		log_sp.rotation.y = la
		log_sp.rotation.x = -PI * 0.5 + randf_range(-0.08, 0.08)
		structure.add_child(log_sp)

	# ── Ember bed (glowing coal sprite flat on the ground) ──
	var ember_sp := Sprite3D.new()
	ember_sp.texture = ember_tex
	ember_sp.pixel_size = 0.012
	ember_sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	ember_sp.axis = Vector3.AXIS_Y
	ember_sp.rotation.x = -PI * 0.5
	ember_sp.position.y = 0.03
	ember_sp.transparent = true
	ember_sp.shaded = false
	structure.add_child(ember_sp)

	# Crop region to show only the flame portion (top 60%) of each frame
	var flame_region := Rect2(0, 0, 48, 30)

	# ── Main campfire sprite (core flame — largest, always visible) ──
	var main_fire := Sprite3D.new()
	main_fire.name = "MainFire"
	main_fire.texture = fire_full_tex
	main_fire.region_enabled = true
	main_fire.region_rect = flame_region
	main_fire.pixel_size = 0.024
	main_fire.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	main_fire.position.y = 0.45
	main_fire.transparent = true
	main_fire.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	main_fire.shaded = false
	main_fire.modulate = Color(1.0, 0.95, 0.85, 0.95)
	structure.add_child(main_fire)

	# ── Multiple overlapping flame layers for depth and movement ──
	var flame_sprites: Array[Sprite3D] = []
	flame_sprites.append(main_fire)

	var flame2 := Sprite3D.new()
	flame2.name = "FlameLayer2"
	flame2.texture = fire_only_tex
	flame2.region_enabled = true
	flame2.region_rect = flame_region
	flame2.pixel_size = 0.022
	flame2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame2.position = Vector3(0.08, 0.40, 0.06)
	flame2.transparent = true
	flame2.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	flame2.shaded = false
	flame2.modulate = Color(1.0, 0.85, 0.6, 0.8)
	flame2.scale = Vector3(0.9, 1.15, 1.0)
	structure.add_child(flame2)
	flame_sprites.append(flame2)

	var flame3 := Sprite3D.new()
	flame3.name = "FlameLayer3"
	flame3.texture = fire_only_tex
	flame3.region_enabled = true
	flame3.region_rect = flame_region
	flame3.pixel_size = 0.020
	flame3.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame3.position = Vector3(-0.06, 0.50, -0.05)
	flame3.transparent = true
	flame3.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	flame3.shaded = false
	flame3.modulate = Color(1.0, 0.7, 0.4, 0.7)
	flame3.scale = Vector3(0.8, 1.0, 1.0)
	structure.add_child(flame3)
	flame_sprites.append(flame3)

	var flame4 := Sprite3D.new()
	flame4.name = "FlameLayer4"
	flame4.texture = fire_full_tex
	flame4.region_enabled = true
	flame4.region_rect = flame_region
	flame4.pixel_size = 0.017
	flame4.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame4.position = Vector3(0.0, 0.60, 0.0)
	flame4.transparent = true
	flame4.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	flame4.shaded = false
	flame4.modulate = Color(1.0, 1.0, 0.5, 0.5)
	flame4.scale = Vector3(0.6, 0.7, 1.0)
	structure.add_child(flame4)
	flame_sprites.append(flame4)

	# ── Smoke wisps (2 layers rising above the fire) ──
	var smoke_sprites: Array[Sprite3D] = []
	for si in 2:
		var smoke := Sprite3D.new()
		smoke.name = "Smoke%d" % si
		smoke.texture = smoke_tex
		smoke.pixel_size = 0.014 + float(si) * 0.004
		smoke.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		smoke.position = Vector3(randf_range(-0.06, 0.06), 1.0 + float(si) * 0.4, randf_range(-0.06, 0.06))
		smoke.transparent = true
		smoke.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		smoke.shaded = false
		smoke.modulate = Color(0.7, 0.7, 0.75, 0.2 - float(si) * 0.06)
		structure.add_child(smoke)
		smoke_sprites.append(smoke)

	# ── Main fire light ──
	var light := OmniLight3D.new()
	light.name = "FireLight"
	light.light_color = Color(1.0, 0.55, 0.15)
	light.light_energy = 9.0
	light.omni_range = 30.0
	light.omni_attenuation = 1.2
	light.shadow_enabled = true
	light.position.y = 0.8
	structure.add_child(light)

	# ── Warm fill light at base ──
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.3, 0.05)
	fill.light_energy = 3.6
	fill.omni_range = 15.0
	fill.omni_attenuation = 2.0
	fill.shadow_enabled = false
	fill.position.y = 0.15
	structure.add_child(fill)

	# ── Animate everything ──
	start_campfire_animation(structure, light, flame_sprites, smoke_sprites, ember_sp, fire_full_tex, fire_only_tex, flame_anim_frames)

	# ── Campfire looping sound ──
	start_campfire_sound(structure)

	# ── Distance culling ──
	setup_campfire_distance_cull(structure)


func setup_campfire_distance_cull(structure: StaticBody3D) -> void:
	const CAMPFIRE_RENDER_DIST := 30.0
	const CAMPFIRE_RENDER_DIST_SQ := CAMPFIRE_RENDER_DIST * CAMPFIRE_RENDER_DIST
	var cull_timer := Timer.new()
	cull_timer.name = "CampfireCullTimer"
	cull_timer.wait_time = 0.5
	cull_timer.autostart = true
	cull_timer.one_shot = false
	structure.add_child(cull_timer)
	var was_visible := [true]
	cull_timer.timeout.connect(func() -> void:
		if not is_instance_valid(structure):
			return
		var player := pc.get_tree().get_first_node_in_group(&"player") as Node3D
		if not player:
			return
		var dx := structure.global_position.x - player.global_position.x
		var dz := structure.global_position.z - player.global_position.z
		var in_range := (dx * dx + dz * dz) < CAMPFIRE_RENDER_DIST_SQ
		if in_range == was_visible[0]:
			return
		was_visible[0] = in_range
		structure.set_meta(&"campfire_culled", not in_range)
		for child in structure.get_children():
			if child is Sprite3D or child is OmniLight3D:
				child.visible = in_range
			elif child.name == "FlameAnimTimer":
				child.paused = not in_range
	)


func disable_structure_shadows(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var surf_count := maxi(mi.get_surface_override_material_count(), mi.mesh.get_surface_count() if mi.mesh else 0)
		for surf_idx in range(surf_count):
			var mat := mi.get_active_material(surf_idx)
			if mat is BaseMaterial3D:
				var m := mat.duplicate() as BaseMaterial3D
				m.set_flag(BaseMaterial3D.FLAG_DONT_RECEIVE_SHADOWS, true)
				if not m.emission_enabled:
					m.emission_enabled = true
					m.emission = m.albedo_color
					m.emission_energy_multiplier = 0.35
				mi.set_surface_override_material(surf_idx, m)
	for child in node.get_children():
		disable_structure_shadows(child)


func setup_structure_distance_cull(structure: StaticBody3D) -> void:
	const STRUCT_RENDER_DIST := 50.0
	const STRUCT_RENDER_DIST_SQ := STRUCT_RENDER_DIST * STRUCT_RENDER_DIST
	var cull_timer := Timer.new()
	cull_timer.name = "StructCullTimer"
	cull_timer.wait_time = 0.5
	cull_timer.autostart = true
	cull_timer.one_shot = false
	structure.add_child(cull_timer)
	var was_visible := [true]
	cull_timer.timeout.connect(func() -> void:
		if not is_instance_valid(structure):
			return
		var player := pc.get_tree().get_first_node_in_group(&"player") as Node3D
		if not player:
			return
		var dx := structure.global_position.x - player.global_position.x
		var dz := structure.global_position.z - player.global_position.z
		var in_range := (dx * dx + dz * dz) < STRUCT_RENDER_DIST_SQ
		if in_range == was_visible[0]:
			return
		was_visible[0] = in_range
		for child in structure.get_children():
			if child is MeshInstance3D or child is OmniLight3D or child is Sprite3D:
				child.visible = in_range
	)


func start_campfire_sound(structure: StaticBody3D) -> void:
	var sfx_paths := [
		"res://audio/sfx/campfire.wav",
		"res://audio/sfx/campfire_raging_1.wav",
		"res://audio/sfx/campfire_raging_2.wav",
	]
	var stream: AudioStream
	var paths_copy := sfx_paths.duplicate()
	paths_copy.shuffle()
	for p in paths_copy:
		if ResourceLoader.exists(p):
			stream = load(p) as AudioStream
			if stream:
				break
	if not stream:
		return

	# Use non-positional AudioStreamPlayer so volume is controlled manually
	var audio := AudioStreamPlayer.new()
	audio.name = "CampfireSound"
	audio.bus = &"SFX"
	audio.stream = stream
	audio.volume_db = -80.0
	audio.max_polyphony = 1
	structure.add_child(audio)
	audio.play()
	audio.finished.connect(audio.play)

	var max_dist := 20.0
	var full_vol_dist := 2.0
	var vol_max_db := 4.0
	var vol_min_db := -80.0

	var fade_timer := Timer.new()
	fade_timer.name = "CampfireFadeTimer"
	fade_timer.wait_time = 0.15
	fade_timer.autostart = true
	fade_timer.one_shot = false
	structure.add_child(fade_timer)
	fade_timer.timeout.connect(func() -> void:
		if not is_instance_valid(structure) or not is_instance_valid(audio):
			return
		var player := pc.get_tree().get_first_node_in_group(&"player") as Node3D
		if not player:
			audio.volume_db = vol_min_db
			return
		var dist: float = player.global_position.distance_to(structure.global_position)
		if dist >= max_dist:
			audio.volume_db = vol_min_db
		elif dist <= full_vol_dist:
			audio.volume_db = vol_max_db
		else:
			var t: float = (dist - full_vol_dist) / (max_dist - full_vol_dist)
			audio.volume_db = lerpf(vol_max_db, vol_min_db, t * t)
	)


func start_campfire_animation(
	structure: StaticBody3D,
	light: OmniLight3D,
	flames: Array[Sprite3D],
	smokes: Array[Sprite3D],
	ember: Sprite3D,
	tex_a: Texture2D,
	tex_b: Texture2D,
	anim_frames: Array[Texture2D] = [],
) -> void:
	var flame_base_x: Array[float] = []
	var flame_base_y: Array[float] = []
	for f in flames:
		flame_base_x.append(f.position.x)
		flame_base_y.append(f.position.y)

	# Copy frames into a plain Array so lambdas can capture it without type issues
	var frames_copy: Array = []
	for t in anim_frames:
		frames_copy.append(t)
	var has_anim := frames_copy.size() >= 3
	var frame_count := frames_copy.size()

	# ── Frame-by-frame fire animation via a persistent Timer node ──
	if has_anim:
		var frame_idx := [0]
		var offsets: Array[int] = []
		for fi in flames.size():
			offsets.append((fi * 2) % frame_count)

		var anim_timer := Timer.new()
		anim_timer.name = "FlameAnimTimer"
		anim_timer.wait_time = 0.12
		anim_timer.autostart = true
		anim_timer.one_shot = false
		structure.add_child(anim_timer)
		anim_timer.timeout.connect(func() -> void:
			if not is_instance_valid(structure):
				return
			frame_idx[0] = (frame_idx[0] + 1) % frame_count
			for fi in flames.size():
				if not is_instance_valid(flames[fi]):
					continue
				var idx: int = int((frame_idx[0] + offsets[fi]) % frame_count)
				flames[fi].texture = frames_copy[idx] as Texture2D
		)
		for fi in flames.size():
			if is_instance_valid(flames[fi]):
				flames[fi].texture = frames_copy[offsets[fi]] as Texture2D

	# ── Flame dance + light flicker ──
	var _tick := [0]
	var _flicker_ref: Array[Callable] = [Callable()]
	_flicker_ref[0] = func() -> void:
		if not is_instance_valid(structure):
			return
		if structure.get_meta(&"campfire_culled", false):
			var retry_tw := structure.create_tween()
			retry_tw.tween_interval(0.5)
			retry_tw.tween_callback(_flicker_ref[0])
			return
		_tick[0] += 1
		var dur := randf_range(0.08, 0.2)
		var tw := structure.create_tween()

		var energy := randf_range(6.0, 15.0)
		var col_g := randf_range(0.3, 0.65)
		tw.tween_property(light, "light_energy", energy, dur)
		tw.parallel().tween_property(light, "light_color", Color(randf_range(0.9, 1.0), col_g, 0.08), dur)

		for fi in flames.size():
			if not is_instance_valid(flames[fi]):
				continue
			var sy := randf_range(0.7, 1.3)
			var sx := randf_range(0.8, 1.2)
			var sway := flame_base_x[fi] + randf_range(-0.12, 0.12)
			var bob := flame_base_y[fi] + randf_range(-0.04, 0.08)
			tw.parallel().tween_property(flames[fi], "scale", Vector3(sx, sy, 1.0), dur)
			tw.parallel().tween_property(flames[fi], "position:x", sway, dur)
			tw.parallel().tween_property(flames[fi], "position:y", bob, dur)
			var heat := randf_range(0.6, 1.0)
			var alpha := clampf(flames[fi].modulate.a + randf_range(-0.08, 0.08), 0.5, 1.0)
			tw.parallel().tween_property(flames[fi], "modulate", Color(1.0, heat, heat * 0.5, alpha), dur)

			if not has_anim and _tick[0] % 4 == fi and tex_a and tex_b:
				flames[fi].texture = tex_b if flames[fi].texture == tex_a else tex_a

		if is_instance_valid(ember):
			var ea := randf_range(0.6, 1.0)
			tw.parallel().tween_property(ember, "modulate", Color(1.0, randf_range(0.3, 0.6), randf_range(0.0, 0.15), ea), dur)

		tw.tween_callback(_flicker_ref[0])
	_flicker_ref[0].call()

	# ── Smoke drift ──
	var _smoke_ref: Array[Callable] = [Callable()]
	_smoke_ref[0] = func() -> void:
		if not is_instance_valid(structure):
			return
		if structure.get_meta(&"campfire_culled", false):
			var retry_tw := structure.create_tween()
			retry_tw.tween_interval(0.5)
			retry_tw.tween_callback(_smoke_ref[0])
			return
		for si in smokes.size():
			if not is_instance_valid(smokes[si]):
				continue
			var stw := smokes[si].create_tween()
			var life := randf_range(2.0, 3.5)
			var start_y := 0.8 + float(si) * 0.3
			smokes[si].position = Vector3(randf_range(-0.06, 0.06), start_y, randf_range(-0.06, 0.06))
			smokes[si].modulate.a = 0.0
			smokes[si].scale = Vector3(0.7, 0.7, 1.0)
			stw.set_parallel(true)
			stw.tween_property(smokes[si], "position:y", start_y + randf_range(1.5, 2.5), life)
			stw.tween_property(smokes[si], "position:x", smokes[si].position.x + randf_range(-0.2, 0.2), life)
			stw.tween_property(smokes[si], "scale", Vector3(1.5, 1.8, 1.0), life)
			stw.set_parallel(false)
			stw.tween_property(smokes[si], "modulate:a", randf_range(0.12, 0.25), life * 0.2)
			stw.tween_property(smokes[si], "modulate:a", 0.0, life * 0.8)
		var timer := structure.get_tree().create_timer(randf_range(1.8, 3.0))
		timer.timeout.connect(_smoke_ref[0])
	_smoke_ref[0].call()

	# ── Ember sparks ──
	var spark_pool: Array[Sprite3D] = []
	var spark_count := 6
	var spark_img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	spark_img.fill(Color(1.0, 0.7, 0.1))
	var spark_tex := ImageTexture.create_from_image(spark_img)

	for si in spark_count:
		var sp := Sprite3D.new()
		sp.texture = spark_tex
		sp.pixel_size = 0.005
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.transparent = true
		sp.shaded = false
		sp.modulate = Color(1.0, randf_range(0.4, 0.8), 0.0, 0.9)
		sp.visible = false
		structure.add_child(sp)
		spark_pool.append(sp)

	var _spark_idx := [0]
	var _spark_ref: Array[Callable] = [Callable()]
	_spark_ref[0] = func() -> void:
		if not is_instance_valid(structure):
			return
		var sp: Sprite3D = spark_pool[_spark_idx[0] % spark_count]
		_spark_idx[0] += 1
		sp.position = Vector3(randf_range(-0.1, 0.1), randf_range(0.3, 0.6), randf_range(-0.1, 0.1))
		sp.modulate.a = 0.9
		sp.visible = true
		var life := randf_range(0.3, 0.7)
		var tw := sp.create_tween()
		tw.set_parallel(true)
		tw.tween_property(sp, "position:y", sp.position.y + randf_range(0.5, 1.5), life)
		tw.tween_property(sp, "position:x", sp.position.x + randf_range(-0.2, 0.2), life)
		tw.tween_property(sp, "modulate:a", 0.0, life)
		tw.set_parallel(false)
		tw.tween_callback(func() -> void: sp.visible = false)
		var timer := structure.get_tree().create_timer(randf_range(0.2, 0.6))
		timer.timeout.connect(_spark_ref[0])
	_spark_ref[0].call()


func build_workbench_visual(structure: StaticBody3D, sz: Vector3, _color: Color) -> void:
	ensure_building_materials()
	var wood_mat := _bmat_wood

	var top := MeshInstance3D.new()
	var top_box := BoxMesh.new()
	top_box.size = Vector3(sz.x, 0.12, sz.z)
	top.mesh = top_box
	top.set_surface_override_material(0, wood_mat)
	top.position.y = sz.y - 0.06
	structure.add_child(top)

	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.35, 0.22, 0.10)
	leg_mat.roughness = 0.9
	var leg_height := sz.y - 0.12
	var leg_mesh := BoxMesh.new()
	leg_mesh.size = Vector3(0.12, leg_height, 0.12)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var leg := MeshInstance3D.new()
		leg.mesh = leg_mesh
		leg.set_surface_override_material(0, leg_mat)
		leg.position = Vector3(corner.x * (sz.x * 0.43), leg_height * 0.5, corner.y * (sz.z * 0.43))
		structure.add_child(leg)

	var brace_mat := StandardMaterial3D.new()
	brace_mat.albedo_color = Color(0.38, 0.25, 0.12)
	brace_mat.roughness = 0.9
	for side_z in [-1.0, 1.0]:
		var brace := MeshInstance3D.new()
		var brace_mesh := BoxMesh.new()
		brace_mesh.size = Vector3(sz.x * 0.86, 0.08, 0.06)
		brace.mesh = brace_mesh
		brace.set_surface_override_material(0, brace_mat)
		brace.position = Vector3(0.0, leg_height * 0.35, side_z * sz.z * 0.43)
		structure.add_child(brace)


func build_bed_visual(structure: Node3D, sz: Vector3) -> void:
	ensure_building_materials()
	var frame_h := sz.y * 0.4
	var mattress_h := sz.y * 0.35
	var pillow_h := sz.y * 0.2
	var headboard_h := sz.y * 0.8

	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(sz.x, frame_h, sz.z)
	frame.mesh = frame_mesh
	frame.set_surface_override_material(0, _bmat_wood)
	frame.position.y = frame_h * 0.5
	structure.add_child(frame)

	var mattress_mat := StandardMaterial3D.new()
	mattress_mat.albedo_color = Color(0.75, 0.70, 0.60)
	mattress_mat.roughness = 0.95
	var mattress := MeshInstance3D.new()
	var mattress_mesh := BoxMesh.new()
	mattress_mesh.size = Vector3(sz.x * 0.9, mattress_h, sz.z * 0.92)
	mattress.mesh = mattress_mesh
	mattress.set_surface_override_material(0, mattress_mat)
	mattress.position.y = frame_h + mattress_h * 0.5
	structure.add_child(mattress)

	var blanket_mat := StandardMaterial3D.new()
	blanket_mat.albedo_color = Color(0.35, 0.18, 0.12)
	blanket_mat.roughness = 0.92
	var blanket := MeshInstance3D.new()
	var blanket_mesh := BoxMesh.new()
	blanket_mesh.size = Vector3(sz.x * 0.88, mattress_h * 0.3, sz.z * 0.55)
	blanket.mesh = blanket_mesh
	blanket.set_surface_override_material(0, blanket_mat)
	blanket.position = Vector3(0.0, frame_h + mattress_h + mattress_h * 0.15, -sz.z * 0.15)
	structure.add_child(blanket)

	var pillow_mat := StandardMaterial3D.new()
	pillow_mat.albedo_color = Color(0.85, 0.82, 0.75)
	pillow_mat.roughness = 0.95
	var pillow := MeshInstance3D.new()
	var pillow_mesh := BoxMesh.new()
	pillow_mesh.size = Vector3(sz.x * 0.6, pillow_h, sz.z * 0.15)
	pillow.mesh = pillow_mesh
	pillow.set_surface_override_material(0, pillow_mat)
	pillow.position = Vector3(0.0, frame_h + mattress_h + pillow_h * 0.5, sz.z * 0.38)
	structure.add_child(pillow)

	var headboard := MeshInstance3D.new()
	var headboard_mesh := BoxMesh.new()
	headboard_mesh.size = Vector3(sz.x + 0.06, headboard_h, 0.08)
	headboard.mesh = headboard_mesh
	headboard.set_surface_override_material(0, _bmat_wood)
	headboard.position = Vector3(0.0, headboard_h * 0.5, sz.z * 0.5)
	structure.add_child(headboard)

	var footboard := MeshInstance3D.new()
	var footboard_mesh := BoxMesh.new()
	footboard_mesh.size = Vector3(sz.x + 0.06, frame_h + mattress_h * 0.5, 0.06)
	footboard.mesh = footboard_mesh
	footboard.set_surface_override_material(0, _bmat_wood)
	footboard.position = Vector3(0.0, (frame_h + mattress_h * 0.5) * 0.5, -sz.z * 0.5)
	structure.add_child(footboard)


# ── Raft ──────────────────────────────────────────────────────────────────────
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
	plank_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.32, 0.22, 0.12)
	dark_mat.roughness = 0.85
	dark_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.60, 0.52, 0.35)
	rope_mat.roughness = 0.8
	rope_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

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
