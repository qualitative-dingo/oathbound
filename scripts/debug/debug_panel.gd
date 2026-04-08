class_name DebugPanel
extends CanvasLayer

const _ZonePool := preload("res://scripts/world/zone_pool.gd")

var _panel_root: Control
var _fps_label: Label
var _stats_label: Label
var _version_label: Label
var _player_ref: Node  # PlayerController
var _last_fps_band: int = -1  # 0=red, 1=yellow, 2=green

# Tracks which toggles are ON (true = enabled / spawning normally)
var _toggles: Dictionary = {
	"trees": true,
	"rocks": true,
	"blueberries": true,
	"flowers": true,
	"creatures": true,
	"villages": true,
	"stones": true,
	"fish": true,
	"horses": true,
	"terrain_col": true,
	"minimap": true,
	"world_map": true,
	"fancy_terrain": true,
	"terrain_visible": true,
	"ssao": false,
	"glow": false,
	"nearest_filter": false,
}

## True while "Disable ALL post & filters" is active (WorldEnvironment + DayNightCycle bypass).
var _post_fx_strip_active: bool = false

## Stores original shader code so we can revert after hot-swapping filter modes.
var _original_shader_codes: Dictionary = {}  # Shader -> String


func _init() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	name = "DebugPanel"


func setup(player: Node) -> void:
	_player_ref = player
	_build_ui()
	visible = false


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.7)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	bg.add_child(margin)

	# Make the panel scrollable
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(outer)

	var title := Label.new()
	title.text = "DEBUG PANEL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	outer.add_child(title)

	var hint := Label.new()
	hint.text = "Toggle systems off, then explore. When FPS stays at 60, you found the culprit."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer.add_child(hint)

	# Live perf readout
	_fps_label = Label.new()
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fps_label.add_theme_font_size_override("font_size", 18)
	_fps_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	outer.add_child(_fps_label)

	_stats_label = Label.new()
	_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats_label.add_theme_font_size_override("font_size", 13)
	_stats_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	outer.add_child(_stats_label)

	_version_label = Label.new()
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version_label.add_theme_font_size_override("font_size", 14)
	_version_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_version_label.text = "Build: %s" % _compute_build_hash()
	outer.add_child(_version_label)

	var sep := HSeparator.new()
	outer.add_child(sep)

	var post_title := Label.new()
	post_title.text = "Post / screen FX (grain & banding)"
	post_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	post_title.add_theme_font_size_override("font_size", 15)
	post_title.add_theme_color_override("font_color", Color(0.75, 0.65, 0.9))
	outer.add_child(post_title)

	var post_hint := Label.new()
	post_hint.text = "Turns off SSAO, glow, fog, color grading, and DNC tonemap — leaves spawns & terrain as-is."
	post_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	post_hint.add_theme_font_size_override("font_size", 11)
	post_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	post_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	outer.add_child(post_hint)

	var post_row := HBoxContainer.new()
	post_row.add_theme_constant_override("separation", 12)
	post_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var post_off := _make_button("Disable ALL post & filters", Color(0.35, 0.2, 0.45))
	post_off.pressed.connect(func() -> void:
		_set_post_fx_strip(true)
	)
	var post_on := _make_button("Restore post & filters", Color(0.2, 0.38, 0.28))
	post_on.pressed.connect(func() -> void:
		_set_post_fx_strip(false)
	)
	post_row.add_child(post_off)
	post_row.add_child(post_on)
	outer.add_child(post_row)

	var post_sep := HSeparator.new()
	outer.add_child(post_sep)

	# --- Two-column layout: toggles on left, actions on right ---
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	columns.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(columns)

	# Left column: spawning toggles
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)

	var spawn_title := Label.new()
	spawn_title.text = "Spawning Toggles"
	spawn_title.add_theme_font_size_override("font_size", 16)
	spawn_title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	left.add_child(spawn_title)

	var spawn_hint := Label.new()
	spawn_hint.text = "OFF = skip spawning new ones + hide existing"
	spawn_hint.add_theme_font_size_override("font_size", 11)
	spawn_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	left.add_child(spawn_hint)

	_add_toggle(left, "Trees", "trees")
	_add_toggle(left, "Rocks (harvestable)", "rocks")
	_add_toggle(left, "Blueberry Bushes", "blueberries")
	_add_toggle(left, "Flowers", "flowers")
	_add_toggle(left, "Creatures", "creatures")
	_add_toggle(left, "Villages / Structures", "villages")
	_add_toggle(left, "Ground Stones", "stones")
	_add_toggle(left, "Fish", "fish")
	_add_toggle(left, "Horses", "horses")
	_add_toggle(left, "Terrain Collision", "terrain_col")
	_add_toggle(left, "Minimap Refresh", "minimap")
	_add_toggle(left, "World Map", "world_map")
	_add_toggle(left, "Fancy Terrain Shader", "fancy_terrain")
	_add_toggle(left, "Terrain Visible", "terrain_visible")
	_add_toggle(left, "SSAO", "ssao")
	_add_toggle(left, "Glow", "glow")
	_add_toggle(left, "Pixel-Art Filter (nearest)", "nearest_filter")

	var deselect_btn := _make_button("Disable ALL", Color(0.7, 0.15, 0.15))
	deselect_btn.pressed.connect(_deselect_all)
	left.add_child(deselect_btn)

	var reselect_btn := _make_button("Enable ALL", Color(0.15, 0.6, 0.15))
	reselect_btn.pressed.connect(_reselect_all)
	left.add_child(reselect_btn)

	# Right column: actions & player toggles
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)

	var action_title := Label.new()
	action_title.text = "Player & Actions"
	action_title.add_theme_font_size_override("font_size", 16)
	action_title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	right.add_child(action_title)

	# Flight mode toggle
	var flight_cb := CheckBox.new()
	flight_cb.text = "Flight Mode"
	flight_cb.button_pressed = _player_ref.get("flight_mode") if _player_ref else false
	flight_cb.add_theme_font_size_override("font_size", 15)
	flight_cb.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	flight_cb.toggled.connect(func(on: bool) -> void:
		if _player_ref:
			_player_ref.flight_mode = on
	)
	right.add_child(flight_cb)

	# Flush Pool button
	var flush_btn := _make_button("Flush Object Pool", Color(0.5, 0.3, 0.15))
	flush_btn.pressed.connect(func() -> void:
		_ZonePool.flush_all()
		print("[DEBUG] Pool flushed")
	)
	right.add_child(flush_btn)

	# Nuke & Regenerate: free ALL zones and let the world generator rebuild fresh
	var nuke_btn := _make_button("Nuke All Zones (regenerate)", Color(0.55, 0.15, 0.15))
	nuke_btn.pressed.connect(_nuke_zones)
	right.add_child(nuke_btn)

	var disable_all_btn := _make_button("Disable ALL Spawning", Color(0.4, 0.15, 0.15))
	disable_all_btn.pressed.connect(func() -> void:
		for key in _toggles:
			_toggles[key] = false
		_apply_all_toggles()
		_refresh_checkboxes()
	)
	right.add_child(disable_all_btn)

	var enable_all_btn := _make_button("Enable ALL Spawning", Color(0.15, 0.4, 0.2))
	enable_all_btn.pressed.connect(func() -> void:
		for key in _toggles:
			_toggles[key] = true
		_apply_all_toggles()
		_refresh_checkboxes()
	)
	right.add_child(enable_all_btn)

	# Close button
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	outer.add_child(spacer)

	var close_btn := _make_button("Close (Esc)", Color(0.25, 0.25, 0.3))
	close_btn.custom_minimum_size = Vector2(200, 0)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(toggle_panel)
	outer.add_child(close_btn)

	_panel_root = bg


func _compute_build_hash() -> String:
	var files := [
		"res://scripts/player/player_controller.gd",
		"res://scripts/world/world_generator.gd",
		"res://scripts/world/zone_populator.gd",
		"res://scripts/player/player_combat.gd",
		"res://scripts/autoloads/item_database.gd",
	]
	var hash_val := 0
	for path in files:
		if FileAccess.file_exists(path):
			var f := FileAccess.open(path, FileAccess.READ)
			if f:
				hash_val = (hash_val * 31 + f.get_length()) & 0xFFFFFF
				f.close()
	return "%06X" % hash_val


func _process(_delta: float) -> void:
	if not visible:
		return
	var fps := Engine.get_frames_per_second()
	var band := 2 if fps >= 55 else (1 if fps >= 35 else 0)
	if band != _last_fps_band:
		_last_fps_band = band
		var fps_color := Color(0.3, 1.0, 0.3) if band == 2 else (Color(1.0, 0.8, 0.2) if band == 1 else Color(1.0, 0.3, 0.3))
		_fps_label.add_theme_color_override("font_color", fps_color)
	_fps_label.text = "FPS: %d" % fps

	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var proc := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	_stats_label.text = "nodes=%d  objects=%d  draws=%d  proc=%.1fms  phys=%.1fms  %s" % [
		nodes, objects, draws, proc, phys, _ZonePool.get_pool_stats()]


func toggle_panel() -> void:
	visible = not visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ─── Toggle Helpers ─────────────────────────────────────────────────────────────

var _checkbox_refs: Dictionary = {}

func _add_toggle(parent: VBoxContainer, label: String, key: String) -> void:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = _toggles[key]
	cb.add_theme_font_size_override("font_size", 15)
	cb.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	cb.toggled.connect(func(on: bool) -> void:
		_toggles[key] = on
		_apply_toggle(key, on)
	)
	parent.add_child(cb)
	_checkbox_refs[key] = cb


func _refresh_checkboxes() -> void:
	for key in _checkbox_refs:
		var cb: CheckBox = _checkbox_refs[key]
		cb.set_pressed_no_signal(_toggles[key])


func _apply_all_toggles() -> void:
	for key in _toggles:
		_apply_toggle(key, _toggles[key])


func _apply_toggle(key: String, on: bool) -> void:
	print("[DEBUG TOGGLE] %s = %s" % [key, "ON" if on else "OFF"])
	var pop_cls := load("res://scripts/world/zone_populator.gd")
	if pop_cls:
		match key:
			"trees":
				pop_cls.set("debug_skip_trees", not on)
			"rocks":
				pop_cls.set("debug_skip_rocks", not on)
			"blueberries":
				pop_cls.set("debug_skip_saplings", not on)
			"flowers":
				pop_cls.set("debug_skip_flowers", not on)
			"creatures":
				pop_cls.set("debug_skip_creatures", not on)
			"villages":
				pop_cls.set("debug_skip_villages", not on)
			"stones":
				pop_cls.set("debug_skip_stones", not on)
			"fish":
				pop_cls.set("debug_skip_fish", not on)
			"horses":
				pop_cls.set("debug_skip_horses", not on)

	if key == "minimap" and _player_ref:
		_player_ref.set("_minimap_paused", not on)
		var outer: Control = _player_ref.get("_minimap_outer")
		if outer:
			outer.visible = on

	if key == "world_map" and _player_ref:
		_player_ref.set("_map_disabled", not on)
		if not on and _player_ref.get("_map_open"):
			_player_ref.call("_close_map")

	if key == "fancy_terrain":
		var wg_nodes := get_tree().get_nodes_in_group(&"world_generator")
		if not wg_nodes.is_empty():
			var wg: Node = wg_nodes[0]
			if wg.has_method("set_fast_terrain_shader"):
				wg.set_fast_terrain_shader(not on)

	if key == "terrain_visible":
		var wg_nodes := get_tree().get_nodes_in_group(&"world_generator")
		if not wg_nodes.is_empty():
			var wg: Node = wg_nodes[0]
			if wg.has_method("set_terrain_visible"):
				wg.set_terrain_visible(on)

	if key == "ssao":
		for node in get_tree().get_nodes_in_group(&"world_environment"):
			if node is WorldEnvironment:
				var env: Environment = (node as WorldEnvironment).environment
				if env:
					env.ssao_enabled = on

	if key == "glow":
		var dnc := get_tree().current_scene.get_node_or_null("DayNightCycle") if get_tree().current_scene else null
		if dnc:
			dnc.set("glow_override_enabled", on)

	if key == "nearest_filter":
		var scene := get_tree().current_scene
		if on:
			if scene and scene.has_method("_force_nearest_recursive"):
				scene.set("force_nearest_filter", on)
				scene._force_nearest_recursive(scene)
			_swap_all_shader_filters(true)
		else:
			if scene:
				scene.set("force_nearest_filter", false)
			_force_linear_recursive(scene if scene else get_tree().root)
			_swap_all_shader_filters(false)

	# Also show/hide existing instances in the current scene
	_toggle_existing(key, on)

	if _post_fx_strip_active:
		_enforce_post_fx_strip_env()


func _enforce_post_fx_strip_env() -> void:
	var tree := get_tree()
	for node in tree.get_nodes_in_group(&"world_environment"):
		if node is WorldEnvironment:
			var env: Environment = (node as WorldEnvironment).environment
			if env:
				env.ssao_enabled = false
				env.glow_enabled = false
				env.adjustment_enabled = false
	var dnc: Node = tree.current_scene.get_node_or_null("DayNightCycle") if tree.current_scene else null
	if dnc:
		dnc.set("glow_override_enabled", false)


func _toggle_existing(key: String, on: bool) -> void:
	var tree := get_tree()
	if not tree:
		return

	match key:
		"trees":
			for node in tree.get_nodes_in_group(&"interactables"):
				if node.has_meta("tree_name"):
					_set_node_active(node, on)
		"rocks":
			for node in tree.get_nodes_in_group(&"interactables"):
				if node.has_meta("drop_id") and node.get_meta("drop_id") == &"stone":
					if node is StaticBody3D and not node.has_meta("tree_name"):
						_set_node_active(node, on)
		"blueberries":
			for node in tree.get_nodes_in_group(&"interactables"):
				var n: String = node.name
				if n.begins_with("BlueberryBush"):
					_set_node_active(node, on)
		"creatures":
			for node in tree.get_nodes_in_group(&"enemies"):
				_set_node_active(node, on)
			for node in tree.get_nodes_in_group(&"creature"):
				_set_node_active(node, on)
		"villages":
			for node in tree.get_nodes_in_group(&"structures"):
				_set_node_active(node, on)
			_toggle_by_name("AbandonedVillage", on)
		"stones":
			_toggle_loot_drops(on)
		"fish":
			_toggle_by_name_prefix("Fish", on)
		"horses":
			for node in tree.get_nodes_in_group(&"horses"):
				_set_node_active(node, on)
		"terrain_col":
			_toggle_by_name("TerrainCol", on)


func _set_node_active(node: Node, on: bool) -> void:
	if not is_instance_valid(node):
		return
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = not on
		return
	if node is Node3D:
		(node as Node3D).visible = on
	if node is StaticBody3D:
		(node as StaticBody3D).collision_layer = (4 if on else 0)
	if node is CharacterBody3D:
		node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED


func _toggle_by_name_prefix(prefix: String, on: bool) -> void:
	var root := get_tree().current_scene
	if not root:
		return
	for zone in root.get_children():
		if not zone is Node3D:
			continue
		for child in zone.get_children():
			if child.name.begins_with(prefix):
				_set_node_active(child, on)


func _toggle_by_name(target_name: String, on: bool) -> void:
	var root := get_tree().current_scene
	if not root:
		return
	_recursive_toggle_by_name(root, target_name, on)


func _recursive_toggle_by_name(node: Node, target_name: String, on: bool) -> void:
	if node.name == target_name:
		_set_node_active(node, on)
	for child in node.get_children():
		_recursive_toggle_by_name(child, target_name, on)


func _toggle_loot_drops(on: bool) -> void:
	var root := get_tree().current_scene
	if not root:
		return
	for zone in root.get_children():
		if not zone is Node3D:
			continue
		for child in zone.get_children():
			if child.name.begins_with("LootDrop") or child.get_script() and child.get_script().resource_path.ends_with("loot_drop.gd"):
				_set_node_active(child, on)


func _nuke_zones() -> void:
	_ZonePool.flush_all()
	var wg := _find_world_generator()
	if not wg:
		print("[DEBUG] Could not find WorldGenerator node")
		return
	var count := 0
	var loaded: Dictionary = wg.get("_loaded_zones")
	if loaded:
		for coord in loaded:
			var zone_node: Node = loaded[coord]
			if is_instance_valid(zone_node):
				zone_node.queue_free()
				count += 1
		loaded.clear()
	# Clear threaded generation state so stale results don't finalize
	var in_flight: Dictionary = wg.get("_gen_in_flight")
	if in_flight:
		in_flight.clear()
	var backlog: Array = wg.get("_finalize_backlog")
	if backlog:
		backlog.clear()
	var pop_backlog: Array = wg.get("_populate_backlog")
	if pop_backlog:
		pop_backlog.clear()
	print("[DEBUG] Nuked %d zones — world generator will rebuild on next frame" % count)


func _find_world_generator() -> Node:
	var root := get_tree().current_scene
	if not root:
		return null
	if root is WorldGenerator:
		return root
	for child in root.get_children():
		if child is WorldGenerator:
			return child
	return null


# ─── UI Helpers ─────────────────────────────────────────────────────────────────

func _set_post_fx_strip(active: bool) -> void:
	_post_fx_strip_active = active
	print("[DEBUG] post-FX strip = %s" % active)
	var tree := get_tree()
	var dnc: Node = tree.current_scene.get_node_or_null("DayNightCycle") if tree.current_scene else null
	if active:
		if dnc:
			dnc.set("debug_post_fx_bypass", true)
			dnc.set("glow_override_enabled", false)
		for node in tree.get_nodes_in_group(&"world_environment"):
			if node is WorldEnvironment:
				var env: Environment = (node as WorldEnvironment).environment
				if env:
					env.ssao_enabled = false
					env.glow_enabled = false
					env.adjustment_enabled = false
		_toggles["ssao"] = false
		_toggles["glow"] = false
	else:
		_toggles["ssao"] = true
		_toggles["glow"] = true
		if dnc:
			dnc.set("debug_post_fx_bypass", false)
			dnc.set("glow_override_enabled", true)
		for node in tree.get_nodes_in_group(&"world_environment"):
			if node is WorldEnvironment:
				var env: Environment = (node as WorldEnvironment).environment
				if env:
					env.ssao_enabled = true
					env.glow_enabled = true
					env.adjustment_enabled = true
	_refresh_checkboxes()


func _deselect_all() -> void:
	print("[DEBUG] === DISABLE ALL TOGGLES ===")
	for key in _toggles:
		_toggles[key] = false
		_apply_toggle(key, false)
	_refresh_checkboxes()


func _reselect_all() -> void:
	print("[DEBUG] === ENABLE ALL TOGGLES ===")
	for key in _toggles:
		_toggles[key] = true
		_apply_toggle(key, true)
	_refresh_checkboxes()


func _force_linear_recursive(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is StandardMaterial3D:
					(mat as StandardMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if node is GeometryInstance3D:
		var mat := (node as GeometryInstance3D).material_override
		if mat is StandardMaterial3D:
			(mat as StandardMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for child in node.get_children():
		_force_linear_recursive(child)


func _swap_all_shader_filters(use_nearest: bool) -> void:
	var visited: Dictionary = {}
	_collect_shaders_recursive(get_tree().root, visited)
	for shader: Shader in visited:
		if not _original_shader_codes.has(shader):
			_original_shader_codes[shader] = shader.code
		if use_nearest:
			shader.code = _original_shader_codes[shader]
		else:
			var code: String = _original_shader_codes[shader]
			code = code.replace("filter_nearest_mipmap", "filter_linear_mipmap")
			code = code.replace("filter_nearest", "filter_linear")
			shader.code = code


func _collect_shaders_recursive(node: Node, visited: Dictionary) -> void:
	if not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
					visited[(mat as ShaderMaterial).shader] = true
	if node is GeometryInstance3D:
		var mat := (node as GeometryInstance3D).material_override
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
			visited[(mat as ShaderMaterial).shader] = true
	for child in node.get_children():
		_collect_shaders_recursive(child, visited)


func _make_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 14)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn
