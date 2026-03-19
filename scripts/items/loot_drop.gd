class_name LootDrop
extends StaticBody3D
## A pickup item on the ground. Press E (interact) when close to collect.

@export var item_id: StringName = &"wood"
@export var amount: int = 1
@export var star_level: int = 0

const DESPAWN_TIME := 180.0
const DESPAWN_FADE := 5.0

var _bob_time := 0.0
var _age := 0.0
var pickup_grace := 0.0
var _sprite: Sprite3D
var _nameplate_label: Label3D
var _stars_label: Label3D
var _nameplate_bg: Sprite3D


func _ready() -> void:
	collision_layer = 4
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
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_sprite.transparent = true
	_sprite.shaded = true
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
	if not _grounded:
		_snap_to_ground()

	if pickup_grace > 0.0:
		pickup_grace -= delta
	_age += delta
	if _age >= DESPAWN_TIME:
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
			_nameplate_bg.modulate.a = fade * 0.85

	_bob_time += delta * 2.0
	_sprite.position.y = 0.4 + sin(_bob_time) * 0.08
	_sprite.rotation.y += delta * 1.5

	# Nameplate: show if ANY player is within range (use nearest player's distance)
	var nearest_dist := INF
	for p in get_tree().get_nodes_in_group(&"player"):
		var node := p as Node3D
		if not is_instance_valid(node):
			continue
		var d := global_position.distance_to(node.global_position)
		if d < nearest_dist:
			nearest_dist = d
	var label_dist := 9.0 if item_id == &"stone" else 45.0
	var show_label := nearest_dist < label_dist
	if _nameplate_label:
		_nameplate_label.visible = show_label
		if _stars_label:
			_stars_label.visible = show_label
		if _nameplate_bg:
			_nameplate_bg.visible = show_label


func _snap_to_ground() -> void:
	_push_away_from_stumps()

	var wgs := get_tree().get_nodes_in_group(&"world_generator")
	if wgs.is_empty():
		_grounded = true
		return
	var wg: Node = wgs[0]
	if wg.has_method(&"get_height_at"):
		var ground_y: float = wg.get_height_at(global_position.x, global_position.z)
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
	var label_px := 0.00088
	var label_y := 0.95

	_nameplate_label = Label3D.new()
	_nameplate_label.name = "LootNameplate"
	_nameplate_label.text = name_part
	_nameplate_label.font_size = label_fs
	_nameplate_label.pixel_size = label_px
	_nameplate_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate_label.fixed_size = true
	_nameplate_label.no_depth_test = false
	_nameplate_label.modulate = Color.WHITE
	_nameplate_label.outline_modulate = Color(0, 0, 0, 0.9)
	_nameplate_label.outline_size = 6
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
		_stars_label.fixed_size = true
		_stars_label.no_depth_test = false
		_stars_label.modulate = ItemDatabase.get_rarity_color(star_level)
		_stars_label.outline_modulate = Color(0, 0, 0, 0.9)
		_stars_label.outline_size = 6
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


func _attach_loot_nameplate_bg(bg_w: float, bg_h: float, label_y: float) -> void:
	CreatureAI._ensure_panel_tex()

	_nameplate_bg = Sprite3D.new()
	_nameplate_bg.name = "LootNameplateBG"
	_nameplate_bg.texture = CreatureAI._shared_panel_tex
	_nameplate_bg.modulate = Color(0.05, 0.05, 0.08, 0.85)
	_nameplate_bg.pixel_size = bg_w / 4.0
	_nameplate_bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate_bg.fixed_size = true
	_nameplate_bg.no_depth_test = false
	_nameplate_bg.transparent = true
	_nameplate_bg.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_nameplate_bg.render_priority = 0
	_nameplate_bg.position.y = label_y
	_nameplate_bg.visible = false
	_nameplate_bg.scale.y = bg_h / bg_w
	add_child(_nameplate_bg)


func _update_visuals() -> void:
	var icon_tex: Texture2D = ItemDatabase.get_icon(item_id)
	if icon_tex:
		_sprite.texture = icon_tex
	else:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.25, 0.25, 0.25)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _get_item_color()
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.set_surface_override_material(0, mat)
		mi.position.y = 0.3
		add_child(mi)

	# Tint the sprite with rarity color for starred items
	if star_level > 0:
		_sprite.modulate = ItemDatabase.get_rarity_color(star_level).lightened(0.3)


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


static func spawn_loot(tree: SceneTree, world_pos: Vector3, loot_table: Array, creature_stars: int = 0, rare_table: Array = []) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var qty_multiplier := 1.0 + creature_stars * 0.5
	var extra_rolls := creature_stars

	# Check player affixes for loot bonuses — if ANY player has lucky, apply bonus
	var affix_lucky := 0.0
	for p in tree.get_nodes_in_group(&"player"):
		if p.has_method("_has_affix") and p._has_affix(&"lucky"):
			affix_lucky = 0.05
			break

	for entry in loot_table:
		var id: StringName = entry.get("id", &"wood") as StringName
		var min_amt: int = int(entry.get("min", 1))
		var max_amt: int = int(entry.get("max", 1))
		var chance: float = float(entry.get("chance", 1.0))
		var boosted_chance := minf(chance + creature_stars * 0.05, 1.0)
		if rng.randf() > boosted_chance:
			continue
		var qty: int = rng.randi_range(min_amt, max_amt)
		qty = int(ceil(qty * qty_multiplier))
		if qty <= 0:
			continue

		var stars := ItemDatabase.roll_star_level(rng)
		for _i in extra_rolls:
			var reroll := ItemDatabase.roll_star_level(rng)
			if reroll > stars:
				stars = reroll

		_spawn_single_drop(tree, world_pos, id, qty, stars, rng)

	# Rare / super drop table — each entry rolled independently
	var rare_chance_boost := creature_stars * 0.02 + affix_lucky
	for entry in rare_table:
		var id: StringName = entry.get("id", &"wood") as StringName
		var min_amt: int = int(entry.get("min", 1))
		var max_amt: int = int(entry.get("max", 1))
		var chance: float = float(entry.get("chance", 0.05))
		if rng.randf() > chance + rare_chance_boost:
			continue
		var qty: int = rng.randi_range(min_amt, max_amt)
		qty = int(ceil(qty * qty_multiplier))
		if qty <= 0:
			continue

		var stars := 0
		if not entry.get("no_stars", false):
			stars = ItemDatabase.roll_star_level(rng)
			for _i in extra_rolls:
				var reroll := ItemDatabase.roll_star_level(rng)
				if reroll > stars:
					stars = reroll

		_spawn_single_drop(tree, world_pos, id, qty, stars, rng)


static func _spawn_single_drop(tree: SceneTree, world_pos: Vector3, id: StringName, qty: int, stars: int, rng: RandomNumberGenerator) -> void:
	var composite_id := id
	if stars > 0:
		var base_data: Dictionary = ItemDatabase.get_item(id)
		var item_type: String = str(base_data.get("type", "material"))
		var affixes: Array[StringName] = []
		if stars >= 3 and item_type in ["weapon", "armor"]:
			affixes = ItemDatabase.roll_affixes(stars, ItemDatabase.get_affix_slot(id))
		composite_id = ItemDatabase.make_star_id(id, stars, affixes)

	var offset := Vector3(
		rng.randf_range(-8.0, 8.0), 0.0, rng.randf_range(-8.0, 8.0)
	)
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
