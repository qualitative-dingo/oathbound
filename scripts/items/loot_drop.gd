class_name LootDrop
extends StaticBody3D
## A pickup item on the ground. Press E (interact) when close to collect.

@export var item_id: StringName = &"wood"
@export var amount: int = 1
@export var star_level: int = 0

const DESPAWN_TIME := 60.0
const DESPAWN_FADE := 5.0
const MAX_LOOT_NODES := 150
const STACK_RADIUS_SQ := 2.25
const STACK_SPACING := 0.40

static var _s_cached_players: Array = []
static var _s_cached_world_gen: Node = null
static var _s_cache_frame: int = -1

var _bob_time := 0.0
var _age := 0.0
var _nameplate_timer := 0.0
var pickup_grace := 0.0
var spawn_delay := 0.0
var drop_owner_peer: int = 0
var _sprite: Sprite3D
var _nameplate_label: Label3D
var _stars_label: Label3D
var _nameplate_bg: Sprite3D
var _accent_bar: Sprite3D


func _refresh_static_caches() -> void:
	var frame := Engine.get_process_frames()
	if frame != _s_cache_frame:
		_s_cache_frame = frame
		_s_cached_players = get_tree().get_nodes_in_group(&"player")
		if not is_instance_valid(_s_cached_world_gen):
			var wgs := get_tree().get_nodes_in_group(&"world_generator")
			_s_cached_world_gen = wgs[0] if not wgs.is_empty() else null

func _ready() -> void:
	collision_layer = 32
	collision_mask = 0
	add_to_group(&"loot")

	# Build the composite item_id from base + star level
	if star_level > 0:
		var parsed := ItemDatabase.parse_star_id(item_id)
		if parsed["stars"] == 0:
			item_id = ItemDatabase.make_star_id(item_id, star_level)

	_sprite = Sprite3D.new()
	_sprite.pixel_size = 0.02
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = 0.5
	_sprite.transparent = true
	_sprite.shaded = false
	_sprite.double_sided = true
	_sprite.position.y = 0.4
	add_child(_sprite)

	_build_nameplate()

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	col.shape = shape
	col.position.y = 0.3
	add_child(col)

	_update_visuals()


var _grounded := false

func _process(delta: float) -> void:
	if spawn_delay > 0.0:
		spawn_delay -= delta
		visible = false
		return
	elif not visible:
		visible = true

	if not _grounded:
		_snap_to_ground()

	if pickup_grace > 0.0:
		pickup_grace -= delta
	_age += delta
	if _age >= DESPAWN_TIME:
		_cleanup_registry()
		queue_free()
		return
	if _age >= DESPAWN_TIME - DESPAWN_FADE:
		var fade := 1.0 - (_age - (DESPAWN_TIME - DESPAWN_FADE)) / DESPAWN_FADE
		_sprite.modulate.a = fade
		if _nameplate_label:
			_nameplate_label.modulate.a = fade
		if _stars_label:
			_stars_label.modulate.a = fade
		if _nameplate_bg:
			_nameplate_bg.modulate.a = fade
		if _accent_bar:
			_accent_bar.modulate.a = fade

	_bob_time += delta * 2.0
	_sprite.position.y = 0.4 + sin(_bob_time) * 0.08
	_sprite.rotation.y += delta * 1.5

	_nameplate_timer -= delta
	if _nameplate_timer <= 0.0:
		_nameplate_timer = 0.5
		_refresh_static_caches()
		var nearest_dist_sq := INF
		for p in _s_cached_players:
			var node := p as Node3D
			if not is_instance_valid(node):
				continue
			var d_sq := global_position.distance_squared_to(node.global_position)
			if d_sq < nearest_dist_sq:
				nearest_dist_sq = d_sq
		var label_dist := 9.0 if item_id == &"stone" else 45.0
		var show_label := nearest_dist_sq < label_dist * label_dist
		if _nameplate_label:
			_nameplate_label.visible = show_label
			if _stars_label:
				_stars_label.visible = show_label
			if _nameplate_bg:
				_nameplate_bg.visible = show_label
			if _accent_bar:
				_accent_bar.visible = show_label

			if show_label:
				_update_stack_offset()


func _update_stack_offset() -> void:
	var my_pos := global_position
	var my_id := get_instance_id()
	var slot := 0
	var parent := get_parent()
	if not parent:
		return
	for child in parent.get_children():
		if child == self or not is_instance_valid(child):
			continue
		var od := child as LootDrop
		if not od or not od._nameplate_label or not od._nameplate_label.visible:
			continue
		var dx: float = od.global_position.x - my_pos.x
		var dz: float = od.global_position.z - my_pos.z
		if dx * dx + dz * dz < STACK_RADIUS_SQ:
			if od.get_instance_id() < my_id:
				slot += 1
	var target_y := 0.95 + slot * STACK_SPACING
	_nameplate_label.position.y = target_y
	if _stars_label:
		_stars_label.position.y = target_y


func _cleanup_registry() -> void:
	var loot_id: int = get_meta("loot_id", -1)
	if loot_id >= 0:
		var wss := _get_world_state_sync()
		if wss and wss._loot_registry.has(loot_id):
			wss._loot_registry.erase(loot_id)


static func _enforce_loot_cap() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return
	var all_loot := tree.get_nodes_in_group(&"loot")
	var excess := all_loot.size() - MAX_LOOT_NODES
	if excess <= 0:
		return
	var sorted: Array[LootDrop] = []
	for n in all_loot:
		if n is LootDrop:
			sorted.append(n as LootDrop)
	sorted.sort_custom(func(a: LootDrop, b: LootDrop) -> bool: return a._age > b._age)
	for i in mini(excess, sorted.size()):
		sorted[i]._cleanup_registry()
		sorted[i].queue_free()


func _snap_to_ground() -> void:
	_push_away_from_stumps()

	if global_position.y < -100.0:
		_grounded = true
		return

	_refresh_static_caches()
	if not is_instance_valid(_s_cached_world_gen):
		_grounded = true
		return
	var wg: Node = _s_cached_world_gen
	if wg.has_method(&"get_height_at_scene"):
		var ground_y: float = wg.get_height_at_scene(global_position.x, global_position.z)
		global_position.y = ground_y + 0.15
	_grounded = true


func _push_away_from_stumps() -> void:
	for node in get_tree().get_nodes_in_group(&"stumps"):
		var stump := node as Node3D
		if not stump:
			continue
		var to_loot := Vector3(global_position.x - stump.global_position.x, 0.0, global_position.z - stump.global_position.z)
		var stump_r: float = stump.get_meta("stump_radius", 0.5)
		var clear_dist := stump_r + 0.4
		if to_loot.length() < clear_dist:
			if to_loot.length_squared() < 0.001:
				to_loot = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
			else:
				to_loot = to_loot.normalized()
			global_position.x = stump.global_position.x + to_loot.x * clear_dist
			global_position.z = stump.global_position.z + to_loot.z * clear_dist


func pickup(_player: Node3D) -> void:
	# Multiplayer: host processes directly; client sends RPC to host
	if NetworkManager.is_connected_to_game():
		var loot_id: int = get_meta("loot_id", -1)
		if loot_id >= 0:
			var wss := _get_world_state_sync()
			if wss:
				if NetworkManager.is_server():
					wss.process_host_pickup(self)
				else:
					wss.request_pickup.rpc_id(1, loot_id, NetworkManager.get_peer_id())
			return
	# Singleplayer or legacy loot without id: local pickup
	_do_local_pickup()


func _do_local_pickup() -> void:
	GameEvents.item_picked_up.emit(item_id, amount)
	var parsed := ItemDatabase.parse_star_id(item_id)
	var base: String = str(parsed["base_id"])
	var stars: int = parsed["stars"]
	var pickup_sfx := "wood_pickup" if base == "wood" else "stone_rubble"
	AudioManager.play_sfx(pickup_sfx, -1.0, 0.15)
	var display := _get_display_name()
	var num := DamageNumber.new()
	num.font_size = 28
	num.pixel_size = 0.01
	num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	num.no_depth_test = true
	num.modulate = Color.WHITE
	num.outline_modulate = Color.BLACK
	num.outline_size = 6
	num._velocity = Vector3(0, 2.0, 0)

	if stars > 0:
		num.text = "+%d %s " % [amount, display]
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var star_str := ""
		for i in stars:
			star_str += "★"
		var star_lbl := Label3D.new()
		star_lbl.text = star_str
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
		num.text = "+%d %s" % [amount, display]

	get_tree().current_scene.add_child(num)
	num.global_position = global_position + Vector3(0, 1.2, 0)
	queue_free()


func _get_world_state_sync() -> WorldStateSync:
	for n in get_tree().get_nodes_in_group(&"world_state_sync"):
		if n is WorldStateSync:
			return n as WorldStateSync
	return null


func _get_display_name() -> String:
	return ItemDatabase.get_display_name(item_id)


func _build_nameplate() -> void:
	var display_name := _get_display_name()
	var name_part := "%s x%d" % [display_name, amount]
	var star_text := ""
	if star_level > 0:
		star_text = " "
		for i in star_level:
			star_text += "★"
	var full_text := name_part + star_text

	var label_fs := 28
	var label_px := 0.009
	var label_y := 0.95

	_nameplate_label = Label3D.new()
	_nameplate_label.name = "LootNameplate"
	_nameplate_label.text = name_part
	_nameplate_label.font_size = label_fs
	_nameplate_label.pixel_size = label_px
	_nameplate_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate_label.no_depth_test = false
	var data: Dictionary = ItemDatabase.get_item(item_id)
	var qc = data.get("quality_color", null)
	if star_level == 0 and qc is Color:
		_nameplate_label.modulate = qc as Color
	else:
		_nameplate_label.modulate = Color.WHITE
	_nameplate_label.outline_modulate = Color(0, 0, 0, 0.95)
	_nameplate_label.outline_size = 10
	_nameplate_label.render_priority = 1
	_nameplate_label.visible = false

	if star_level > 0:
		_nameplate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stars_label = Label3D.new()
		_stars_label.name = "LootStars"
		_stars_label.text = star_text
		_stars_label.font_size = label_fs
		_stars_label.pixel_size = label_px
		_stars_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_stars_label.no_depth_test = false
		_stars_label.modulate = ItemDatabase.get_rarity_color(star_level)
		_stars_label.outline_modulate = Color(0, 0, 0, 0.95)
		_stars_label.outline_size = 10
		_stars_label.render_priority = 1
		_stars_label.visible = false
		_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var font: Font = _nameplate_label.font if _nameplate_label.font else ThemeDB.fallback_font
	var actual_name_w := font.get_string_size(name_part, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs).x * label_px
	var actual_stars_w := 0.0
	if _stars_label:
		actual_stars_w = font.get_string_size(star_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs).x * label_px
	var total_w := actual_name_w + actual_stars_w

	var em := float(label_fs) * label_px
	var star_outline := label_px * 14.0 if _stars_label else 0.0
	var padding := em * 1.5 + star_outline
	var text_h := em * 0.77
	var pad_y := text_h * 0.35
	var bg_w := total_w + padding
	var bg_h := text_h + pad_y * 2.0

	if _stars_label:
		var junction_x := (actual_name_w - actual_stars_w) * 0.5 + em * 0.22
		_nameplate_label.position = Vector3(junction_x, label_y, 0)
		_stars_label.position = Vector3(junction_x, label_y, 0)
		add_child(_stars_label)
	else:
		_nameplate_label.position.y = label_y
	add_child(_nameplate_label)

	_attach_loot_nameplate_bg(bg_w, bg_h, label_y)


func _attach_loot_nameplate_bg(_bg_w: float, _bg_h: float, _label_y: float) -> void:
	pass


func _update_visuals() -> void:
	var icon_tex: Texture2D = ItemDatabase.get_icon(item_id)
	if icon_tex:
		_sprite.texture = icon_tex
	else:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.25, 0.25, 0.25)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _get_item_color()
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.set_surface_override_material(0, mat)
		mi.position.y = 0.3
		add_child(mi)

	# Tint the sprite with rarity/quality color
	if star_level > 0:
		_sprite.modulate = ItemDatabase.get_rarity_color(star_level).lightened(0.3)
	else:
		var data: Dictionary = ItemDatabase.get_item(item_id)
		var qc = data.get("quality_color", null)
		if qc is Color:
			_sprite.modulate = (qc as Color).lightened(0.15)


func _get_item_color() -> Color:
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
		&"gold":       return Color(0.95, 0.8, 0.2)
		&"thick_hide": return Color(0.4, 0.25, 0.12)
		&"fang":       return Color(0.9, 0.88, 0.82)
		&"ancient_bone": return Color(0.75, 0.7, 0.55)
		&"ember_stone": return Color(0.9, 0.4, 0.1)
		&"frost_shard": return Color(0.6, 0.85, 0.95)
		_:             return Color(0.6, 0.6, 0.3)


static var _PIECE_COUNTS: Array[Vector2i] = [
	Vector2i(2, 4),   # 0 stars
	Vector2i(3, 5),   # 1 star
	Vector2i(4, 6),   # 2 stars
	Vector2i(6, 9),   # 3 stars
	Vector2i(9, 12),  # 4 stars
	Vector2i(12, 15), # 5 stars
]

static var _QUALITY_MULTIPLIERS: Array[float] = [1.0, 1.2, 1.5, 1.8, 2.5, 3.3]


static func _roll_boosted_star(rng: RandomNumberGenerator, quality_mult: float) -> int:
	var weights := ItemDatabase.STAR_WEIGHTS.duplicate()
	for i in range(1, weights.size()):
		weights[i] *= quality_mult
	var total := 0.0
	for w in weights:
		total += w
	var roll := rng.randf() * total
	var cumulative := 0.0
	for i in weights.size():
		cumulative += weights[i]
		if roll < cumulative:
			return i
	return 0


static var _drop_index: int = 0

static func spawn_loot(tree: SceneTree, world_pos: Vector3, loot_table: Array, creature_stars: int = 0, rare_table: Array = []) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var star_idx := clampi(creature_stars, 0, _PIECE_COUNTS.size() - 1)
	var piece_range := _PIECE_COUNTS[star_idx]
	var piece_count := rng.randi_range(piece_range.x, piece_range.y)
	var quality_mult := _QUALITY_MULTIPLIERS[star_idx]

	# Build weighted pool from loot table
	var pool: Array[Dictionary] = []
	var total_weight := 0.0
	for entry in loot_table:
		var w: float = float(entry.get("chance", 1.0))
		pool.append(entry)
		total_weight += w

	if pool.is_empty():
		return

	_drop_index = 0
	var base_angle := rng.randf_range(0.0, TAU)
	_enforce_loot_cap()

	var stacked: Dictionary = {}
	for _piece in piece_count:
		var roll := rng.randf() * total_weight
		var cumulative := 0.0
		var chosen: Dictionary = pool[0]
		for entry in pool:
			cumulative += float(entry.get("chance", 1.0))
			if roll < cumulative:
				chosen = entry
				break

		var id: StringName = chosen.get("id", &"bone") as StringName
		var qty := rng.randi_range(1, 2)
		var stars := _roll_boosted_star(rng, quality_mult)
		var item_type: String = str(ItemDatabase.get_item(id).get("type", "material"))
		if item_type in ["weapon", "armor"]:
			_spawn_single_drop(tree, world_pos, id, qty, stars, rng, base_angle)
		else:
			var key := "%s:%d" % [str(id), stars]
			if stacked.has(key):
				stacked[key]["qty"] += qty
			else:
				stacked[key] = {"id": id, "stars": stars, "qty": qty}

	var rare_chance_boost := creature_stars * 0.02
	for entry in rare_table:
		var id: StringName = entry.get("id", &"bone") as StringName
		var min_amt: int = int(entry.get("min", 1))
		var max_amt: int = int(entry.get("max", 1))
		var chance: float = float(entry.get("chance", 0.05))
		if rng.randf() > chance + rare_chance_boost:
			continue
		var qty: int = rng.randi_range(min_amt, max_amt)
		if qty <= 0:
			continue
		var stars := 0
		if not entry.get("no_stars", false):
			stars = _roll_boosted_star(rng, quality_mult)
		var item_type: String = str(ItemDatabase.get_item(id).get("type", "material"))
		if item_type in ["weapon", "armor"]:
			_spawn_single_drop(tree, world_pos, id, qty, stars, rng, base_angle)
		else:
			var key := "%s:%d" % [str(id), stars]
			if stacked.has(key):
				stacked[key]["qty"] += qty
			else:
				stacked[key] = {"id": id, "stars": stars, "qty": qty}

	for key: String in stacked:
		var s: Dictionary = stacked[key]
		_spawn_single_drop(tree, world_pos, s["id"] as StringName, s["qty"] as int, s["stars"] as int, rng, base_angle)


static func _spawn_scattered_drops(tree: SceneTree, world_pos: Vector3, id: StringName, total_qty: int, stars: int, rng: RandomNumberGenerator, base_angle: float = 0.0) -> void:
	const MAX_PER_DROP := 2
	if total_qty <= MAX_PER_DROP:
		_spawn_single_drop(tree, world_pos, id, total_qty, stars, rng, base_angle)
		return
	var remaining := total_qty
	while remaining > 0:
		var chunk := mini(rng.randi_range(1, MAX_PER_DROP), remaining)
		remaining -= chunk
		_spawn_single_drop(tree, world_pos, id, chunk, stars, rng, base_angle)


static func _spawn_single_drop(tree: SceneTree, world_pos: Vector3, id: StringName, qty: int, stars: int, rng: RandomNumberGenerator, base_angle: float = 0.0) -> void:
	var composite_id := id
	if stars > 0:
		var base_data: Dictionary = ItemDatabase.get_item(id)
		var item_type: String = str(base_data.get("type", "material"))
		var affixes: Array[StringName] = []
		if stars >= 2 and item_type in ["weapon", "armor"]:
			affixes = ItemDatabase.roll_affixes(stars, ItemDatabase.get_affix_slot(id))
		var affix_rolls: Dictionary = ItemDatabase.roll_affix_magnitudes(affixes)
		composite_id = ItemDatabase.make_star_id(id, stars, affixes, affix_rolls)

	const GOLDEN_ANGLE := 2.39996323  # PI * (3 - sqrt(5))
	const MIN_RADIUS := 0.8
	const MAX_RADIUS := 4.0
	const RADIUS_STEP := 0.35
	var idx := _drop_index
	_drop_index += 1
	var angle := base_angle + idx * GOLDEN_ANGLE + rng.randf_range(-0.15, 0.15)
	var radius := minf(MIN_RADIUS + idx * RADIUS_STEP, MAX_RADIUS) + rng.randf_range(-0.1, 0.1)
	var offset := Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	var final_pos := world_pos + offset + Vector3.UP * 0.5
	# Multiplayer: host spawns and replicates
	if NetworkManager.is_connected_to_game() and NetworkManager.is_server():
		var wss := _get_wss_from_tree(tree)
		if wss:
			wss.spawn_loot_synced(final_pos, composite_id, qty, stars)
			return
	var drop := LootDrop.new()
	drop.item_id = composite_id
	drop.star_level = stars
	drop.amount = qty
	tree.current_scene.add_child(drop)
	drop.global_position = final_pos


static func _get_wss_from_tree(tree: SceneTree) -> WorldStateSync:
	for n in tree.get_nodes_in_group(&"world_state_sync"):
		if n is WorldStateSync:
			return n as WorldStateSync
	return null
