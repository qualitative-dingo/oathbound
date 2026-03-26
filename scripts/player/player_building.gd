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
	 "mesh": "campfire", "color": Color(0.5, 0.3, 0.15), "size": Vector3(0.72, 0.36, 0.72)},
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
	 "mesh": "roof_45", "color": Color(0.55, 0.45, 0.25), "size": Vector3(3.6, 3.6, 3.6)},
	{"id": &"thatch_roof_26", "name": "Thatch Roof 26°", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "roof_26", "color": Color(0.55, 0.45, 0.25), "size": Vector3(3.6, 1.76, 3.6)},
	{"id": &"thatch_roof_45_ocorner", "name": "Thatch Outer Corner 45°", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 6}],
	 "mesh": "roof_45_ocorner", "color": Color(0.55, 0.45, 0.25), "size": Vector3(3.6, 3.6, 3.6)},
	{"id": &"thatch_roof_26_ocorner", "name": "Thatch Outer Corner 26°", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "roof_26_ocorner", "color": Color(0.55, 0.45, 0.25), "size": Vector3(3.6, 1.76, 3.6)},
	{"id": &"thatch_roof_45_icorner", "name": "Thatch Inner Corner 45°", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 6}],
	 "mesh": "roof_45_icorner", "color": Color(0.55, 0.45, 0.25), "size": Vector3(3.6, 3.6, 3.6)},
	{"id": &"thatch_roof_26_icorner", "name": "Thatch Inner Corner 26°", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "roof_26_icorner", "color": Color(0.55, 0.45, 0.25), "size": Vector3(3.6, 1.76, 3.6)},
	{"id": &"thatch_roof_ridge", "name": "Thatch Ridge Cap", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 2}],
	 "mesh": "roof_ridge", "color": Color(0.55, 0.45, 0.25), "size": Vector3(3.6, 0.25, 0.5)},
	# Gable walls – Building tab (wood)
	{"id": &"wood_gable_45", "name": "Wood Gable 45°", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "gable_45", "color": Color(0.4, 0.28, 0.12), "size": Vector3(3.6, 3.6, 0.20)},
	{"id": &"wood_gable_26", "name": "Wood Gable 26°", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 3}],
	 "mesh": "gable_26", "color": Color(0.4, 0.28, 0.12), "size": Vector3(3.6, 1.76, 0.20)},
	# Roofing – Heavy Build tab (stone)
	{"id": &"slate_roof_45", "name": "Slate Roof 45°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 6}],
	 "mesh": "roof_45", "color": Color(0.35, 0.35, 0.4), "size": Vector3(3.6, 3.6, 3.6)},
	{"id": &"slate_roof_26", "name": "Slate Roof 26°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 4}],
	 "mesh": "roof_26", "color": Color(0.35, 0.35, 0.4), "size": Vector3(3.6, 1.76, 3.6)},
	{"id": &"slate_roof_45_ocorner", "name": "Slate Outer Corner 45°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 6}],
	 "mesh": "roof_45_ocorner", "color": Color(0.35, 0.35, 0.4), "size": Vector3(3.6, 3.6, 3.6)},
	{"id": &"slate_roof_26_ocorner", "name": "Slate Outer Corner 26°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 4}],
	 "mesh": "roof_26_ocorner", "color": Color(0.35, 0.35, 0.4), "size": Vector3(3.6, 1.76, 3.6)},
	{"id": &"slate_roof_45_icorner", "name": "Slate Inner Corner 45°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 6}],
	 "mesh": "roof_45_icorner", "color": Color(0.35, 0.35, 0.4), "size": Vector3(3.6, 3.6, 3.6)},
	{"id": &"slate_roof_26_icorner", "name": "Slate Inner Corner 26°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 4}],
	 "mesh": "roof_26_icorner", "color": Color(0.35, 0.35, 0.4), "size": Vector3(3.6, 1.76, 3.6)},
	{"id": &"slate_roof_ridge", "name": "Slate Ridge Cap", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 2}],
	 "mesh": "roof_ridge", "color": Color(0.35, 0.35, 0.4), "size": Vector3(3.6, 0.25, 0.5)},
	# Gable walls – Heavy Build tab (stone)
	{"id": &"stone_gable_45", "name": "Stone Gable 45°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 4}],
	 "mesh": "gable_45", "color": Color(0.4, 0.4, 0.42), "size": Vector3(3.6, 3.6, 0.20)},
	{"id": &"stone_gable_26", "name": "Stone Gable 26°", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 3}],
	 "mesh": "gable_26", "color": Color(0.4, 0.4, 0.42), "size": Vector3(3.6, 1.76, 0.20)},
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
	&"wall_base":      [&"wall_top", &"floor_edge", &"gable_base_45", &"gable_base_26"],
	&"wall_top":       [&"wall_base", &"floor_edge", &"roof_base_45", &"roof_base_26", &"gable_base_45", &"gable_base_26"],
	&"wall_side":      [&"wall_side"],
	&"floor_edge":     [&"wall_base", &"wall_top", &"floor_edge"],
	&"floor_corner":   [&"floor_corner"],
	&"roof_base_45":   [&"wall_top", &"roof_ridge_45", &"gable_slope_45"],
	&"roof_base_26":   [&"wall_top", &"roof_ridge_26", &"gable_slope_26"],
	&"roof_ridge_45":  [&"roof_ridge_45", &"roof_base_45"],
	&"roof_ridge_26":  [&"roof_ridge_26", &"roof_base_26"],
	&"roof_side_45":   [&"roof_side_45", &"gable_slope_45"],
	&"roof_side_26":   [&"roof_side_26", &"gable_slope_26"],
	&"ridge_cap_end":  [&"ridge_cap_end", &"roof_ridge_45", &"roof_ridge_26"],
	&"gable_base_45":  [&"wall_top", &"wall_base"],
	&"gable_base_26":  [&"wall_top", &"wall_base"],
	&"gable_slope_45": [&"roof_side_45", &"roof_base_45"],
	&"gable_slope_26": [&"roof_side_26", &"roof_base_26"],
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
		elif mesh_type in ["gable_45", "gable_26"]:
			mesh = build_gable_mesh(sz)
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
			elif mesh_type in ["gable_45", "gable_26"]:
				mesh = build_gable_mesh(sz)
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
			var cvx := ConvexPolygonShape3D.new()
			if mesh_type in ["roof_45", "roof_26"]:
				var hw2 := sz.x * 0.5
				var hd2 := sz.z * 0.5
				cvx.points = PackedVector3Array([
					Vector3(-hw2, 0, -hd2), Vector3(hw2, 0, -hd2),
					Vector3(-hw2, 0, hd2), Vector3(hw2, 0, hd2),
					Vector3(-hw2, sz.y, hd2), Vector3(hw2, sz.y, hd2)])
			elif mesh_type in ["roof_45_ocorner", "roof_26_ocorner"]:
				var hw2 := sz.x * 0.5
				var hd2 := sz.z * 0.5
				cvx.points = PackedVector3Array([
					Vector3(-hw2, 0, -hd2), Vector3(hw2, 0, -hd2),
					Vector3(-hw2, 0, hd2), Vector3(hw2, 0, hd2),
					Vector3(hw2, sz.y, hd2)])
			elif mesh_type in ["roof_45_icorner", "roof_26_icorner"]:
				var hw2 := sz.x * 0.5
				var hd2 := sz.z * 0.5
				cvx.points = PackedVector3Array([
					Vector3(-hw2, 0, -hd2), Vector3(hw2, 0, -hd2),
					Vector3(-hw2, 0, hd2), Vector3(hw2, 0, hd2),
					Vector3(-hw2, sz.y, hd2), Vector3(hw2, sz.y, hd2),
					Vector3(hw2, sz.y, -hd2)])
			elif mesh_type in ["gable_45", "gable_26"]:
				var hw2 := sz.x * 0.5
				var hd2 := sz.z * 0.5
				cvx.points = PackedVector3Array([
					Vector3(-hw2, 0, -hd2), Vector3(hw2, 0, -hd2),
					Vector3(-hw2, 0, hd2), Vector3(hw2, 0, hd2),
					Vector3(0, sz.y, -hd2), Vector3(0, sz.y, hd2)])
			else:
				var box_col := BoxShape3D.new()
				box_col.size = Vector3(sz.x, sz.y * 0.5, sz.z)
				col = box_col
				col_shape.position.y = sz.y * 0.25
			if cvx.points.size() > 0:
				col = cvx
			col_shape.position.y = 0.0
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
			elif mesh_type in ["gable_45", "gable_26"]:
				mesh = build_gable_mesh(sz)
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
			var cvx := ConvexPolygonShape3D.new()
			if mesh_type in ["roof_45", "roof_26"]:
				var hw2 := sz.x * 0.5
				var hd2 := sz.z * 0.5
				cvx.points = PackedVector3Array([
					Vector3(-hw2, 0, -hd2), Vector3(hw2, 0, -hd2),
					Vector3(-hw2, 0, hd2), Vector3(hw2, 0, hd2),
					Vector3(-hw2, sz.y, hd2), Vector3(hw2, sz.y, hd2)])
			elif mesh_type in ["roof_45_ocorner", "roof_26_ocorner"]:
				var hw2 := sz.x * 0.5
				var hd2 := sz.z * 0.5
				cvx.points = PackedVector3Array([
					Vector3(-hw2, 0, -hd2), Vector3(hw2, 0, -hd2),
					Vector3(-hw2, 0, hd2), Vector3(hw2, 0, hd2),
					Vector3(hw2, sz.y, hd2)])
			elif mesh_type in ["roof_45_icorner", "roof_26_icorner"]:
				var hw2 := sz.x * 0.5
				var hd2 := sz.z * 0.5
				cvx.points = PackedVector3Array([
					Vector3(-hw2, 0, -hd2), Vector3(hw2, 0, -hd2),
					Vector3(-hw2, 0, hd2), Vector3(hw2, 0, hd2),
					Vector3(-hw2, sz.y, hd2), Vector3(hw2, sz.y, hd2),
					Vector3(hw2, sz.y, -hd2)])
			elif mesh_type in ["gable_45", "gable_26"]:
				var hw2 := sz.x * 0.5
				var hd2 := sz.z * 0.5
				cvx.points = PackedVector3Array([
					Vector3(-hw2, 0, -hd2), Vector3(hw2, 0, -hd2),
					Vector3(-hw2, 0, hd2), Vector3(hw2, 0, hd2),
					Vector3(0, sz.y, -hd2), Vector3(0, sz.y, hd2)])
			else:
				var box_col := BoxShape3D.new()
				box_col.size = Vector3(sz.x, sz.y * 0.5, sz.z)
				col = box_col
				col_shape.position.y = sz.y * 0.25
			if cvx.points.size() > 0:
				col = cvx
			col_shape.position.y = 0.0
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
	if build_id in [&"wood_wall", &"wood_floor", &"wood_stair", &"wood_door", &"wood_gable_45", &"wood_gable_26"]:
		return _bmat_wood
	elif build_id in [&"stone_wall", &"stone_floor", &"stone_door", &"stone_gable_45", &"stone_gable_26"]:
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


# ── Roof mesh helpers ────────────────────────────────────────────────────────

const ROOF_THICKNESS := 0.12
const ROOF_OVERHANG := 0.25

static func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		uv_a := Vector2(0, 0), uv_b := Vector2(1, 0), uv_c := Vector2(1, 1), uv_d := Vector2(0, 1)) -> void:
	st.set_uv(uv_a); st.add_vertex(a)
	st.set_uv(uv_b); st.add_vertex(b)
	st.set_uv(uv_c); st.add_vertex(c)
	st.set_uv(uv_a); st.add_vertex(a)
	st.set_uv(uv_c); st.add_vertex(c)
	st.set_uv(uv_d); st.add_vertex(d)

static func _add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		uv_a := Vector2(0, 0), uv_b := Vector2(1, 0), uv_c := Vector2(0.5, 1)) -> void:
	st.set_uv(uv_a); st.add_vertex(a)
	st.set_uv(uv_b); st.add_vertex(b)
	st.set_uv(uv_c); st.add_vertex(c)

static func build_roof_mesh(sz: Vector3, rise: float) -> ArrayMesh:
	var hw := sz.x * 0.5
	var hd := sz.z * 0.5
	var oh := ROOF_OVERHANG
	var th := ROOF_THICKNESS
	var slope_len := sqrt(sz.z * sz.z + rise * rise)
	var eave_drop := oh * (rise / sz.z)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var ot0 := Vector3(-hw - oh, -eave_drop, -hd - oh)
	var ot1 := Vector3( hw + oh, -eave_drop, -hd - oh)
	var ot2 := Vector3( hw + oh, rise,  hd)
	var ot3 := Vector3(-hw - oh, rise,  hd)
	var ib0 := Vector3(-hw, 0.0, -hd)
	var ib1 := Vector3( hw, 0.0, -hd)
	var ib2 := Vector3( hw, rise - th,  hd)
	var ib3 := Vector3(-hw, rise - th,  hd)

	var u_w := (hw * 2.0 + oh * 2.0) / sz.x
	var u_sl := slope_len / sz.z
	_add_quad(st, ot0, ot1, ot2, ot3,
		Vector2(0, 0), Vector2(u_w, 0), Vector2(u_w, u_sl), Vector2(0, u_sl))
	_add_quad(st, ib3, ib2, ib1, ib0)
	_add_quad(st, ot1, ot0, ib0, ib1,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.1), Vector2(0, 0.1))
	_add_quad(st, ot3, ot2, ib2, ib3,
		Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.1), Vector2(0, 0.1))
	_add_tri(st, ot0, ot3, ib3, Vector2(0, 1), Vector2(0, 0), Vector2(0.1, 0))
	_add_tri(st, ot0, ib3, ib0, Vector2(0, 1), Vector2(0.1, 0), Vector2(0.1, 1))
	_add_tri(st, ot2, ot1, ib1, Vector2(0, 0), Vector2(0, 1), Vector2(0.1, 1))
	_add_tri(st, ot2, ib1, ib2, Vector2(0, 0), Vector2(0.1, 1), Vector2(0.1, 0))

	var tb := 0.08
	var eb0 := Vector3(-hw - oh, -eave_drop - tb, -hd - oh)
	var eb1 := Vector3( hw + oh, -eave_drop - tb, -hd - oh)
	_add_quad(st, ot0, ot1, eb1, eb0,
		Vector2(0, 0), Vector2(u_w, 0), Vector2(u_w, 0.05), Vector2(0, 0.05))
	_add_quad(st, eb1, eb0, ib0, ib1,
		Vector2(0, 0), Vector2(u_w, 0), Vector2(u_w, 0.05), Vector2(0, 0.05))

	st.generate_normals()
	return st.commit()


static func build_roof_ocorner_mesh(sz: Vector3, rise: float) -> ArrayMesh:
	var hw := sz.x * 0.5
	var hd := sz.z * 0.5
	var th := ROOF_THICKNESS
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var peak := Vector3(hw, rise, hd)
	var bl := Vector3(-hw, 0.0, -hd)
	var br := Vector3( hw, 0.0, -hd)
	var fl := Vector3(-hw, 0.0,  hd)
	var fr := Vector3( hw, 0.0,  hd)

	_add_tri(st, bl, br, peak, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	_add_tri(st, br, fr, peak, Vector2(0, 1), Vector2(1, 1), Vector2(1, 0))
	_add_tri(st, fr, fl, peak, Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1))
	_add_tri(st, fl, bl, peak, Vector2(0, 0), Vector2(1, 0), Vector2(0.5, 1))

	var peak_i := Vector3(hw, rise - th, hd)
	var bl_i := Vector3(-hw + th, th, -hd + th)
	var br_i := Vector3( hw - th, th, -hd + th)
	var fr_i := Vector3( hw - th, th,  hd - th)
	_add_tri(st, peak_i, br_i, bl_i, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))
	_add_tri(st, peak_i, fr_i, br_i, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))

	_add_quad(st, fl, fr, br, bl)
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
	_add_tri(st, tl, fl, valley, Vector2(0, 0), Vector2(0, 1), Vector2(1, 1))
	_add_tri(st, tl, valley, tb, Vector2(0, 0), Vector2(1, 1), Vector2(1, 0))
	_add_tri(st, tb, valley, br, Vector2(0, 0), Vector2(0, 1), Vector2(1, 1))
	_add_tri(st, tl, tr, fl, Vector2(0, 0), Vector2(1, 0), Vector2(0, 1))
	_add_tri(st, tr, tb, br, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1))
	_add_tri(st, tl, tr, tb)
	_add_tri(st, fl, br, bl)
	st.generate_normals()
	return st.commit()


static func build_roof_ridge_mesh(sz: Vector3) -> ArrayMesh:
	var hw := sz.x * 0.5
	var hh := sz.y * 0.5
	var hd := sz.z * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := [
		Vector3(-hw, -hh, -hd), Vector3( hw, -hh, -hd),
		Vector3( hw,  hh, -hd), Vector3(-hw,  hh, -hd),
		Vector3(-hw, -hh,  hd), Vector3( hw, -hh,  hd),
		Vector3( hw,  hh,  hd), Vector3(-hw,  hh,  hd),
	]
	var faces := [
		[v[3], v[2], v[1], v[0]],
		[v[4], v[5], v[6], v[7]],
		[v[0], v[1], v[5], v[4]],
		[v[2], v[3], v[7], v[6]],
		[v[3], v[0], v[4], v[7]],
		[v[1], v[2], v[6], v[5]],
	]
	var u_len := hw * 2.0 / maxf(sz.z, 0.01)
	for f in faces:
		_add_quad(st, f[0], f[1], f[2], f[3],
			Vector2(0, 0), Vector2(u_len, 0), Vector2(u_len, 1), Vector2(0, 1))
	st.generate_normals()
	return st.commit()


static func build_gable_mesh(sz: Vector3) -> ArrayMesh:
	var hw := sz.x * 0.5
	var hd := sz.z * 0.5
	var rise := sz.y
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_tri(st,
		Vector3(-hw, 0.0, -hd), Vector3(hw, 0.0, -hd), Vector3(0.0, rise, -hd),
		Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0))
	_add_tri(st,
		Vector3(hw, 0.0, hd), Vector3(-hw, 0.0, hd), Vector3(0.0, rise, hd),
		Vector2(0, 1), Vector2(1, 1), Vector2(0.5, 0))
	_add_quad(st,
		Vector3(-hw, 0.0, -hd), Vector3(0.0, rise, -hd),
		Vector3(0.0, rise,  hd), Vector3(-hw, 0.0,  hd),
		Vector2(0, 1), Vector2(0.5, 0), Vector2(0.5, 0), Vector2(0, 1))
	_add_quad(st,
		Vector3(0.0, rise, -hd), Vector3(hw, 0.0, -hd),
		Vector3(hw, 0.0,  hd), Vector3(0.0, rise,  hd),
		Vector2(0.5, 0), Vector2(1, 1), Vector2(1, 1), Vector2(0.5, 0))
	_add_quad(st,
		Vector3(-hw, 0.0, hd), Vector3(hw, 0.0, hd),
		Vector3(hw, 0.0, -hd), Vector3(-hw, 0.0, -hd))
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
		var is_roof_piece := str(build_id).begins_with("thatch_roof") or str(build_id).begins_with("slate_roof") or str(build_id).ends_with("gable_45") or str(build_id).ends_with("gable_26")
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


func _make_soft_circle_tex(sz: int) -> ImageTexture:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var center := float(sz) * 0.5
	for y in sz:
		for x in sz:
			var dx := float(x) - center + 0.5
			var dy := float(y) - center + 0.5
			var dist := sqrt(dx * dx + dy * dy) / center
			var alpha := clampf(1.0 - dist * dist, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)


static var _campfire_stone_tex: ImageTexture
static var _campfire_bark_tex: ImageTexture


static func _get_stone_texture() -> ImageTexture:
	if _campfire_stone_tex:
		return _campfire_stone_tex
	var sz := 32
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var base := randf_range(0.22, 0.38)
			var speckle := randf_range(-0.06, 0.06)
			var crack := 0.0
			if randf() < 0.08:
				crack = -randf_range(0.05, 0.12)
			var vein := sin(float(x) * 0.8 + float(y) * 0.4 + randf_range(-1.0, 1.0)) * 0.03
			var v := clampf(base + speckle + crack + vein, 0.08, 0.5)
			img.set_pixel(x, y, Color(v * 1.0, v * 0.95, v * 0.85, 1.0))
	_campfire_stone_tex = ImageTexture.create_from_image(img)
	return _campfire_stone_tex


static func _get_bark_texture() -> ImageTexture:
	if _campfire_bark_tex:
		return _campfire_bark_tex
	var w := 16
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var char_t := clampf(float(h - y) / float(h), 0.0, 1.0)
		for x in w:
			var bark_base := randf_range(0.18, 0.32)
			var grain := sin(float(y) * 1.5 + float(x) * 0.3 + randf_range(-0.5, 0.5)) * 0.05
			var ridge := 0.0
			if (x + int(randf_range(-1, 1))) % 4 == 0:
				ridge = -randf_range(0.03, 0.08)
			var charring := char_t * char_t * randf_range(0.1, 0.25)
			var v := clampf(bark_base + grain + ridge - charring, 0.04, 0.4)
			var r := v * 1.4
			var g := v * 0.85
			var b := v * 0.45
			r += char_t * char_t * randf_range(0.0, 0.15)
			img.set_pixel(x, y, Color(clampf(r, 0.02, 0.5), clampf(g, 0.02, 0.35), clampf(b, 0.01, 0.2), 1.0))
	_campfire_bark_tex = ImageTexture.create_from_image(img)
	return _campfire_bark_tex


func _build_campfire_stone_ring(structure: StaticBody3D) -> void:
	var stone_tex := _get_stone_texture()
	var stone_count := 10
	var ring_radius := 0.55
	for i in stone_count:
		var stone := MeshInstance3D.new()
		stone.name = "RingStone%d" % i
		var sphere := SphereMesh.new()
		var base_r := randf_range(0.13, 0.21)
		sphere.radius = base_r
		sphere.height = base_r * randf_range(1.2, 1.8)
		sphere.radial_segments = 5
		sphere.rings = 3
		stone.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = stone_tex
		mat.albedo_color = Color(randf_range(0.35, 0.55), randf_range(0.33, 0.5), randf_range(0.3, 0.45))
		mat.roughness = 0.95
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		stone.set_surface_override_material(0, mat)
		var angle := float(i) * TAU / float(stone_count) + randf_range(-0.12, 0.12)
		var radial_offset := randf_range(-0.04, 0.04)
		stone.position = Vector3(
			cos(angle) * (ring_radius + radial_offset),
			sphere.height * 0.35,
			sin(angle) * (ring_radius + radial_offset)
		)
		stone.rotation = Vector3(randf_range(-0.25, 0.25), randf_range(0, TAU), randf_range(-0.25, 0.25))
		stone.scale = Vector3(randf_range(0.9, 1.3), randf_range(0.7, 1.1), randf_range(0.9, 1.3))
		stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		structure.add_child(stone)


func build_campfire_visual(structure: StaticBody3D, sz: Vector3) -> void:
	var soft_tex := _make_soft_circle_tex(32)

	_build_campfire_stone_ring(structure)

	# -- 3D logs arranged in a teepee/pile (6 logs) --
	var bark_tex := _get_bark_texture()
	var log_angles := [0.0, TAU / 6.0, TAU * 2.0 / 6.0, TAU * 3.0 / 6.0, TAU * 4.0 / 6.0, TAU * 5.0 / 6.0]
	var log_tilts := [0.45, 0.55, 0.4, 0.5, 0.48, 0.42]
	var log_lengths := [0.55, 0.48, 0.52, 0.45, 0.5, 0.44]
	for i in 6:
		var log_mi := MeshInstance3D.new()
		log_mi.name = "Log%d" % i
		var cyl := CylinderMesh.new()
		cyl.top_radius = randf_range(0.03, 0.05)
		cyl.bottom_radius = randf_range(0.05, 0.07)
		cyl.height = log_lengths[i] * 1.2
		cyl.radial_segments = 5
		cyl.rings = 2
		log_mi.mesh = cyl
		var log_mat := StandardMaterial3D.new()
		log_mat.albedo_texture = bark_tex
		log_mat.albedo_color = Color(randf_range(0.7, 1.0), randf_range(0.65, 0.9), randf_range(0.6, 0.85))
		log_mat.roughness = 1.0
		log_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		log_mat.emission_enabled = true
		log_mat.emission = Color(0.5, 0.1, 0.0)
		log_mat.emission_energy_multiplier = 0.6
		log_mi.set_surface_override_material(0, log_mat)
		var angle: float = log_angles[i] + randf_range(-0.2, 0.2)
		var tilt: float = log_tilts[i] + randf_range(-0.1, 0.1)
		var outward := randf_range(0.18, 0.25)
		log_mi.position = Vector3(cos(angle) * outward, 0.05, sin(angle) * outward)
		log_mi.rotation = Vector3(-tilt, angle, randf_range(-0.15, 0.15))
		log_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		structure.add_child(log_mi)

	# -- Animated ember bed (shader-driven pulsing coals) --
	var ember_mi := MeshInstance3D.new()
	ember_mi.name = "EmberBed"
	var ember_quad := QuadMesh.new()
	ember_quad.size = Vector2(0.55, 0.55)
	ember_quad.orientation = PlaneMesh.FACE_Y
	ember_mi.mesh = ember_quad
	ember_mi.position.y = 0.04
	ember_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ember_shader := load("res://shaders/ember_glow.gdshader") as Shader
	if ember_shader:
		var emat := ShaderMaterial.new()
		emat.shader = ember_shader
		emat.set_shader_parameter("color_hot", Color(1.0, 0.55, 0.05))
		emat.set_shader_parameter("color_cool", Color(0.4, 0.08, 0.0))
		emat.set_shader_parameter("pulse_speed", 1.2)
		emat.set_shader_parameter("noise_scale", 6.0)
		emat.set_shader_parameter("brightness", 3.0)
		ember_mi.material_override = emat
	else:
		var fallback_mat := StandardMaterial3D.new()
		fallback_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fallback_mat.albedo_color = Color(1.0, 0.4, 0.05)
		fallback_mat.emission_enabled = true
		fallback_mat.emission = Color(1.0, 0.4, 0.05)
		fallback_mat.emission_energy_multiplier = 3.0
		ember_mi.material_override = fallback_mat
	structure.add_child(ember_mi)

	# -- Inner flame mesh (hot core: white/yellow/orange) --
	var fire_shader := load("res://shaders/fire_flame.gdshader") as Shader
	var inner_flame := MeshInstance3D.new()
	inner_flame.name = "InnerFlame"
	var inner_cyl := CylinderMesh.new()
	inner_cyl.top_radius = 0.5
	inner_cyl.bottom_radius = 0.5
	inner_cyl.height = 2.0
	inner_cyl.radial_segments = 12
	inner_cyl.rings = 8
	inner_flame.mesh = inner_cyl
	inner_flame.position.y = 0.08
	inner_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if fire_shader:
		var imat := ShaderMaterial.new()
		imat.shader = fire_shader
		imat.set_shader_parameter("top_radius", 0.0)
		imat.set_shader_parameter("bottom_radius", 0.2)
		imat.set_shader_parameter("center_radius", 0.32)
		imat.set_shader_parameter("center_position", 0.2)
		imat.set_shader_parameter("cylinder_height", 1.1)
		imat.set_shader_parameter("bottom_curve", 0.6)
		imat.set_shader_parameter("vibrate_amplitude", 0.006)
		imat.set_shader_parameter("vibrate_frequency", 100.0)
		imat.set_shader_parameter("speed", 3.0)
		imat.set_shader_parameter("noise_scale", 2.8)
		imat.set_shader_parameter("brightness", 1.3)
		imat.set_shader_parameter("cutoff_base", 0.18)
		imat.set_shader_parameter("band_steps", 5.0)
		imat.set_shader_parameter("color_core", Color(1.0, 1.0, 0.9))
		imat.set_shader_parameter("color_mid", Color(1.0, 0.7, 0.15))
		imat.set_shader_parameter("color_outer", Color(1.0, 0.35, 0.04))
		imat.set_shader_parameter("color_edge", Color(0.7, 0.12, 0.0))
		inner_flame.material_override = imat
	structure.add_child(inner_flame)

	# -- Outer flame mesh (cooler shell: yellow/orange/red, slower) --
	var outer_flame := MeshInstance3D.new()
	outer_flame.name = "OuterFlame"
	var outer_cyl := CylinderMesh.new()
	outer_cyl.top_radius = 0.5
	outer_cyl.bottom_radius = 0.5
	outer_cyl.height = 2.0
	outer_cyl.radial_segments = 10
	outer_cyl.rings = 6
	outer_flame.mesh = outer_cyl
	outer_flame.position.y = 0.04
	outer_flame.scale = Vector3(1.1, 1.05, 1.1)
	outer_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if fire_shader:
		var omat := ShaderMaterial.new()
		omat.shader = fire_shader
		omat.set_shader_parameter("top_radius", 0.0)
		omat.set_shader_parameter("bottom_radius", 0.25)
		omat.set_shader_parameter("center_radius", 0.42)
		omat.set_shader_parameter("center_position", 0.25)
		omat.set_shader_parameter("cylinder_height", 0.9)
		omat.set_shader_parameter("bottom_curve", 0.6)
		omat.set_shader_parameter("vibrate_amplitude", 0.01)
		omat.set_shader_parameter("vibrate_frequency", 80.0)
		omat.set_shader_parameter("speed", 2.0)
		omat.set_shader_parameter("noise_scale", 2.5)
		omat.set_shader_parameter("brightness", 0.75)
		omat.set_shader_parameter("cutoff_base", 0.22)
		omat.set_shader_parameter("band_steps", 4.0)
		omat.set_shader_parameter("color_core", Color(1.0, 0.8, 0.25))
		omat.set_shader_parameter("color_mid", Color(1.0, 0.4, 0.06))
		omat.set_shader_parameter("color_outer", Color(0.75, 0.15, 0.0))
		omat.set_shader_parameter("color_edge", Color(0.3, 0.04, 0.0))
		outer_flame.material_override = omat
	structure.add_child(outer_flame)

	# -- Flame tip wisps (subtle accents at flame tips) --
	var wisp_particles := GPUParticles3D.new()
	wisp_particles.name = "FlameWisps"
	wisp_particles.amount = 6
	wisp_particles.lifetime = 0.5
	wisp_particles.explosiveness = 0.1
	wisp_particles.randomness = 0.5
	wisp_particles.one_shot = false
	wisp_particles.local_coords = true
	wisp_particles.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 5, 4))
	wisp_particles.position.y = 0.7

	var wisp_mesh := QuadMesh.new()
	wisp_mesh.size = Vector2(0.12, 0.25)
	wisp_particles.draw_pass_1 = wisp_mesh

	var wisp_pmat := ParticleProcessMaterial.new()
	wisp_pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	wisp_pmat.emission_sphere_radius = 0.1
	wisp_pmat.direction = Vector3(0, 1, 0)
	wisp_pmat.spread = 22.0
	wisp_pmat.initial_velocity_min = 0.6
	wisp_pmat.initial_velocity_max = 1.2
	wisp_pmat.gravity = Vector3(0, 0.3, 0)
	wisp_pmat.damping_min = 0.5
	wisp_pmat.damping_max = 1.2
	wisp_pmat.scale_min = 0.4
	wisp_pmat.scale_max = 1.0

	var wisp_scale_crv := CurveTexture.new()
	var wsc := Curve.new()
	wsc.add_point(Vector2(0.0, 0.3))
	wsc.add_point(Vector2(0.2, 1.0))
	wsc.add_point(Vector2(0.6, 0.5))
	wsc.add_point(Vector2(1.0, 0.0))
	wisp_scale_crv.curve = wsc
	wisp_pmat.scale_curve = wisp_scale_crv

	var wisp_grad := Gradient.new()
	wisp_grad.offsets = PackedFloat32Array([0.0, 0.2, 0.6, 1.0])
	wisp_grad.colors = PackedColorArray([
		Color(1.0, 0.9, 0.5, 0.6),
		Color(1.0, 0.6, 0.15, 0.45),
		Color(0.85, 0.25, 0.03, 0.2),
		Color(0.4, 0.08, 0.0, 0.0),
	])
	var wisp_ramp := GradientTexture1D.new()
	wisp_ramp.gradient = wisp_grad
	wisp_pmat.color_ramp = wisp_ramp
	wisp_particles.process_material = wisp_pmat

	var wisp_mat := StandardMaterial3D.new()
	wisp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wisp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wisp_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	wisp_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.7)
	wisp_mat.albedo_texture = soft_tex
	wisp_mat.emission_enabled = true
	wisp_mat.emission = Color(1.0, 0.5, 0.1)
	wisp_mat.emission_energy_multiplier = 2.0
	wisp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	wisp_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wisp_particles.material_override = wisp_mat
	structure.add_child(wisp_particles)

	# -- Spark particles (natural arcing embers) --
	var spark_particles := GPUParticles3D.new()
	spark_particles.name = "SparkParticles"
	spark_particles.amount = 18
	spark_particles.lifetime = 1.8
	spark_particles.explosiveness = 0.15
	spark_particles.randomness = 0.7
	spark_particles.one_shot = false
	spark_particles.local_coords = true
	spark_particles.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 5, 6))
	spark_particles.position.y = 0.3

	var spark_mesh := QuadMesh.new()
	spark_mesh.size = Vector2(0.03, 0.03)
	spark_particles.draw_pass_1 = spark_mesh

	var spark_pmat := ParticleProcessMaterial.new()
	spark_pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spark_pmat.emission_sphere_radius = 0.12
	spark_pmat.direction = Vector3(0, 1, 0)
	spark_pmat.spread = 40.0
	spark_pmat.initial_velocity_min = 1.2
	spark_pmat.initial_velocity_max = 3.0
	spark_pmat.gravity = Vector3(0.2, -2.5, 0.0)
	spark_pmat.damping_min = 0.5
	spark_pmat.damping_max = 2.0
	spark_pmat.scale_min = 0.3
	spark_pmat.scale_max = 1.2
	spark_pmat.angular_velocity_min = -30.0
	spark_pmat.angular_velocity_max = 30.0

	var spark_grad := Gradient.new()
	spark_grad.offsets = PackedFloat32Array([0.0, 0.15, 0.4, 0.7, 1.0])
	spark_grad.colors = PackedColorArray([
		Color(1.0, 1.0, 0.7, 1.0),
		Color(1.0, 0.8, 0.3, 0.9),
		Color(1.0, 0.45, 0.08, 0.6),
		Color(0.6, 0.12, 0.0, 0.3),
		Color(0.25, 0.03, 0.0, 0.0),
	])
	var spark_ramp := GradientTexture1D.new()
	spark_ramp.gradient = spark_grad
	spark_pmat.color_ramp = spark_ramp
	spark_particles.process_material = spark_pmat

	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark_mat.albedo_color = Color(1.0, 0.8, 0.35, 1.0)
	spark_mat.albedo_texture = soft_tex
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.55, 0.1)
	spark_mat.emission_energy_multiplier = 3.5
	spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	spark_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	spark_particles.material_override = spark_mat
	structure.add_child(spark_particles)

	# -- Thick smoke column --
	var smoke_particles := GPUParticles3D.new()
	smoke_particles.name = "SmokeParticles"
	smoke_particles.amount = 16
	smoke_particles.lifetime = 4.0
	smoke_particles.explosiveness = 0.04
	smoke_particles.randomness = 0.5
	smoke_particles.one_shot = false
	smoke_particles.local_coords = true
	smoke_particles.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 10, 8))
	smoke_particles.position.y = 0.8

	var smoke_mesh := QuadMesh.new()
	smoke_mesh.size = Vector2(0.9, 0.9)
	smoke_particles.draw_pass_1 = smoke_mesh

	var smoke_pmat := ParticleProcessMaterial.new()
	smoke_pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke_pmat.emission_sphere_radius = 0.1
	smoke_pmat.direction = Vector3(0, 1, 0)
	smoke_pmat.spread = 15.0
	smoke_pmat.initial_velocity_min = 0.4
	smoke_pmat.initial_velocity_max = 0.8
	smoke_pmat.gravity = Vector3(0.08, 0.2, 0.0)
	smoke_pmat.damping_min = 0.2
	smoke_pmat.damping_max = 0.6
	smoke_pmat.scale_min = 0.5
	smoke_pmat.scale_max = 1.4
	smoke_pmat.angular_velocity_min = -20.0
	smoke_pmat.angular_velocity_max = 20.0
	smoke_pmat.tangential_accel_min = -0.15
	smoke_pmat.tangential_accel_max = 0.15

	var smoke_scale_crv := CurveTexture.new()
	var ssc := Curve.new()
	ssc.add_point(Vector2(0.0, 0.2))
	ssc.add_point(Vector2(0.2, 0.6))
	ssc.add_point(Vector2(0.5, 1.0))
	ssc.add_point(Vector2(0.8, 1.4))
	ssc.add_point(Vector2(1.0, 1.8))
	smoke_scale_crv.curve = ssc
	smoke_pmat.scale_curve = smoke_scale_crv

	var smoke_grad := Gradient.new()
	smoke_grad.offsets = PackedFloat32Array([0.0, 0.1, 0.3, 0.6, 0.85, 1.0])
	smoke_grad.colors = PackedColorArray([
		Color(0.45, 0.42, 0.38, 0.0),
		Color(0.42, 0.40, 0.36, 0.18),
		Color(0.50, 0.48, 0.44, 0.14),
		Color(0.55, 0.53, 0.50, 0.10),
		Color(0.58, 0.56, 0.52, 0.05),
		Color(0.6, 0.58, 0.54, 0.0),
	])
	var smoke_ramp := GradientTexture1D.new()
	smoke_ramp.gradient = smoke_grad
	smoke_pmat.color_ramp = smoke_ramp
	smoke_particles.process_material = smoke_pmat

	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	smoke_mat.albedo_color = Color(0.5, 0.47, 0.43, 1.0)
	smoke_mat.albedo_texture = soft_tex
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smoke_particles.material_override = smoke_mat
	structure.add_child(smoke_particles)

	# -- Heat distortion (proportional to contained fire) --
	var dist_shader := load("res://shaders/heat_distortion.gdshader") as Shader
	if dist_shader:
		var distortion_mi := MeshInstance3D.new()
		distortion_mi.name = "HeatDistortion"
		var cone := CylinderMesh.new()
		cone.top_radius = 0.03
		cone.bottom_radius = 0.3
		cone.height = 1.2
		cone.radial_segments = 8
		cone.rings = 1
		distortion_mi.mesh = cone
		distortion_mi.position.y = 1.3
		distortion_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var dist_mat := ShaderMaterial.new()
		dist_mat.shader = dist_shader
		dist_mat.set_shader_parameter("distortion_strength", 0.012)
		dist_mat.set_shader_parameter("scroll_speed", 1.5)
		dist_mat.set_shader_parameter("noise_scale", 3.5)
		distortion_mi.material_override = dist_mat
		structure.add_child(distortion_mi)

	# -- Main fire light (warm glow, not blinding) --
	var light := OmniLight3D.new()
	light.name = "FireLight"
	light.light_color = Color(1.0, 0.55, 0.15)
	light.light_energy = 5.0
	light.omni_range = 18.0
	light.omni_attenuation = 1.4
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 1.5
	light.position.y = 0.6
	structure.add_child(light)

	# -- Warm fill light at base --
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.3, 0.05)
	fill.light_energy = 2.0
	fill.omni_range = 8.0
	fill.omni_attenuation = 1.8
	fill.shadow_enabled = false
	fill.light_volumetric_fog_energy = 1.0
	fill.position.y = 0.12
	structure.add_child(fill)

	start_campfire_animation(structure, light, ember_mi)

	start_campfire_sound(structure)
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
			if child is GPUParticles3D:
				child.emitting = in_range
				child.visible = in_range
			elif child is Sprite3D or child is OmniLight3D or child is MeshInstance3D:
				child.visible = in_range
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
	ember_node: Node3D,
) -> void:
	var _flicker_ref: Array[Callable] = [Callable()]
	var _breath_counter := [0]
	_flicker_ref[0] = func() -> void:
		if not is_instance_valid(structure):
			return
		if structure.get_meta(&"campfire_culled", false):
			var retry_tw := structure.create_tween()
			retry_tw.tween_interval(0.5)
			retry_tw.tween_callback(_flicker_ref[0])
			return

		_breath_counter[0] += 1
		var is_breath: bool = (_breath_counter[0] % 8 == 0)
		var dur := randf_range(0.3, 0.5) if is_breath else randf_range(0.04, 0.1)
		var tw := structure.create_tween()

		var energy: float
		if is_breath:
			energy = randf_range(4.0, 7.0)
		else:
			energy = randf_range(7.0, 14.0)
		var col_g := randf_range(0.25, 0.65)
		tw.tween_property(light, "light_energy", energy, dur)
		tw.parallel().tween_property(light, "light_color", Color(randf_range(0.92, 1.0), col_g, randf_range(0.05, 0.12)), dur)

		if is_instance_valid(ember_node):
			var emat := ember_node.material_override as ShaderMaterial
			if emat:
				var pulse_b := randf_range(2.0, 4.5)
				tw.parallel().tween_method(func(v: float) -> void:
					if is_instance_valid(ember_node) and ember_node.material_override:
						ember_node.material_override.set_shader_parameter("brightness", v)
				, emat.get_shader_parameter("brightness"), pulse_b, dur)

		tw.tween_callback(_flicker_ref[0])
	_flicker_ref[0].call()


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
