class_name CaveGenerator
extends RefCounted
## Generates instanced cave systems: an entrance marker on terrain,
## and a self-contained cave room far below the world (Y = -500).

const _CreatureAI := preload("res://scripts/creatures/creature_ai.gd")

const TUNNEL_WIDTH := 7.0
const TUNNEL_HEIGHT := 5.5
const WALL_THICKNESS := 0.8
const FLOOR_THICKNESS := 0.5
const SEGMENT_LENGTH := 10.0

static var _mat_cave_rock: StandardMaterial3D
static var _mat_cave_floor: StandardMaterial3D
static var _mat_copper_vein: StandardMaterial3D
static var _mat_inited := false
static var _instance_index: int = 0


static func _ensure_materials() -> void:
	if _mat_inited:
		return
	_mat_inited = true

	_mat_cave_rock = StandardMaterial3D.new()
	_mat_cave_rock.albedo_color = Color(0.18, 0.16, 0.14)
	_mat_cave_rock.roughness = 0.95
	_mat_cave_rock.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	_mat_cave_floor = StandardMaterial3D.new()
	_mat_cave_floor.albedo_color = Color(0.22, 0.19, 0.16)
	_mat_cave_floor.roughness = 0.9
	_mat_cave_floor.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	_mat_copper_vein = StandardMaterial3D.new()
	_mat_copper_vein.albedo_color = Color(0.55, 0.35, 0.18)
	_mat_copper_vein.metallic = 0.4
	_mat_copper_vein.roughness = 0.6
	_mat_copper_vein.emission_enabled = true
	_mat_copper_vein.emission = Color(0.3, 0.18, 0.05)
	_mat_copper_vein.emission_energy_multiplier = 0.3
	_mat_copper_vein.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST


# ═══════════════════════════════════════════════════════════════════════════════
#  ENTRANCE MARKER — placed on the terrain surface
# ═══════════════════════════════════════════════════════════════════════════════

static func create_entrance_marker(facing_dir: Vector3) -> StaticBody3D:
	_ensure_materials()
	var marker := StaticBody3D.new()
	marker.name = "CaveEntrance"
	marker.collision_layer = 4
	marker.collision_mask = 0
	marker.add_to_group(&"interactables")
	marker.add_to_group(&"cave_entrances")
	marker.set_meta("cave_entrance", true)

	var arch := _build_entrance_arch(facing_dir)
	arch.position = Vector3.ZERO
	marker.add_child(arch)

	var entrance_light := OmniLight3D.new()
	entrance_light.name = "EntranceLight"
	entrance_light.light_color = Color(0.9, 0.75, 0.5)
	entrance_light.light_energy = 0.8
	entrance_light.omni_range = 35.0
	entrance_light.shadow_enabled = true
	entrance_light.position = Vector3(0.0, TUNNEL_HEIGHT * 0.7, 0.0)
	marker.add_child(entrance_light)

	var label := Label3D.new()
	label.name = "EntranceLabel"
	label.text = "[E] Enter Cave"
	label.font_size = 28
	label.modulate = Color(1.0, 0.85, 0.4)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = TUNNEL_HEIGHT + 1.2
	label.visible = false
	marker.add_child(label)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TUNNEL_WIDTH, TUNNEL_HEIGHT, 2.0)
	col.shape = box
	col.position.y = TUNNEL_HEIGHT * 0.5
	marker.add_child(col)

	return marker


# ═══════════════════════════════════════════════════════════════════════════════
#  CAVE INSTANCE — a full dungeon spawned far below the world
# ═══════════════════════════════════════════════════════════════════════════════

static func create_cave_instance(rng: RandomNumberGenerator) -> Node3D:
	_ensure_materials()

	_instance_index += 1
	var cave_root := Node3D.new()
	cave_root.name = "CaveInstance_%d" % _instance_index
	cave_root.add_to_group(&"cave_instances")

	var base_pos := Vector3(_instance_index * 200.0, -500.0, 0.0)
	cave_root.position = base_pos

	var fwd := Vector3.FORWARD
	var rt := Vector3.RIGHT

	# ── Exit marker at entrance ──
	_build_exit_marker(cave_root)

	# ── Entrance chamber (wide + tall, matching boss chamber proportions) ──
	var entrance_len := 12.0
	var entrance_w := TUNNEL_WIDTH * 2.5
	var entrance_h := TUNNEL_HEIGHT * 1.8
	var entrance_floor := _make_box_static(
		Vector3(entrance_w + WALL_THICKNESS, FLOOR_THICKNESS, entrance_len),
		_mat_cave_floor
	)
	entrance_floor.position = Vector3(0.0, -FLOOR_THICKNESS * 0.5, -entrance_len * 0.5)
	cave_root.add_child(entrance_floor)

	var entrance_ceil := _make_box_static(
		Vector3(entrance_w + WALL_THICKNESS * 2.0, WALL_THICKNESS, entrance_len),
		_mat_cave_rock
	)
	entrance_ceil.position = Vector3(0.0, entrance_h, -entrance_len * 0.5)
	cave_root.add_child(entrance_ceil)

	var entrance_lw := _make_box_static(
		Vector3(WALL_THICKNESS, entrance_h + WALL_THICKNESS, entrance_len),
		_mat_cave_rock
	)
	entrance_lw.position = Vector3(-(entrance_w * 0.5 + WALL_THICKNESS * 0.5), entrance_h * 0.5, -entrance_len * 0.5)
	cave_root.add_child(entrance_lw)

	var entrance_rw := _make_box_static(
		Vector3(WALL_THICKNESS, entrance_h + WALL_THICKNESS, entrance_len),
		_mat_cave_rock
	)
	entrance_rw.position = Vector3(entrance_w * 0.5 + WALL_THICKNESS * 0.5, entrance_h * 0.5, -entrance_len * 0.5)
	cave_root.add_child(entrance_rw)

	# ── Back wall behind spawn ──
	var ew := _make_box_static(
		Vector3(entrance_w + WALL_THICKNESS * 2.0, entrance_h + WALL_THICKNESS, WALL_THICKNESS),
		_mat_cave_rock
	)
	ew.position = Vector3(0.0, entrance_h * 0.5, 1.0)
	cave_root.add_child(ew)

	cave_root.set_meta("player_spawn", Vector3(0.0, 1.5, -1.0))

	var cursor := fwd * entrance_len
	var descent := 0.5
	var enemy_idx := 0
	var cave_waypoints: Array[Vector3] = [Vector3(0.0, 0.0, 0.0)]
	var cave_widths: Array[float] = [entrance_w]

	# ════════════════════════════════════════════════════
	#  SECTION 1: Entry corridor (3 segments with turns)
	# ════════════════════════════════════════════════════
	for i in 3:
		var seg_end := cursor + fwd * SEGMENT_LENGTH
		seg_end.y -= descent
		_build_tunnel_segment(cave_root, cursor, seg_end, fwd, rt, TUNNEL_WIDTH, TUNNEL_HEIGHT)
		cursor = seg_end
		if i < 2:
			var angle := rng.randf_range(-0.3, 0.3)
			fwd = fwd.rotated(Vector3.UP, angle).normalized()
			rt = fwd.cross(Vector3.UP).normalized()

	cave_waypoints.append(cursor)
	cave_widths.append(TUNNEL_WIDTH)
	_add_wall_torch(cave_root, cursor + rt * (TUNNEL_WIDTH * 0.42), 1.8)
	_add_cave_enemy(cave_root, cursor - fwd * 3.0 + Vector3(0, 0.2, 0), "goblin", enemy_idx)
	enemy_idx += 1

	# ════════════════════════════════════════════════════
	#  SECTION 2: First chamber — small rest area
	# ════════════════════════════════════════════════════
	var ch1_w := TUNNEL_WIDTH * 1.6
	var ch1_h := TUNNEL_HEIGHT * 1.2
	var ch1_len := 8.0
	var ch1_end := cursor + fwd * ch1_len
	ch1_end.y -= descent * 0.3
	_build_tunnel_segment(cave_root, cursor, ch1_end, fwd, rt, ch1_w, ch1_h)
	_add_wall_torch(cave_root, (cursor + ch1_end) * 0.5 + rt * (ch1_w * 0.42), 1.8)
	_add_wall_torch(cave_root, (cursor + ch1_end) * 0.5 - rt * (ch1_w * 0.42), 1.8)

	for _v in rng.randi_range(2, 3):
		var vp := lerpf(0.2, 0.8, rng.randf())
		var vpos := cursor.lerp(ch1_end, vp)
		vpos.y += rng.randf_range(0.4, ch1_h * 0.5)
		vpos += rt * (ch1_w * 0.42) * (1.0 if rng.randf() < 0.5 else -1.0)
		_add_copper_vein_wall(cave_root, vpos, rng)

	cursor = ch1_end
	cave_waypoints.append(cursor)
	cave_widths.append(ch1_w)

	# ════════════════════════════════════════════════════
	#  SECTION 3: Branching corridor — left branch = loot, right = main path
	# ════════════════════════════════════════════════════

	# Branch split: wall with two openings (left + right tunnels)
	var branch_fwd_l := fwd.rotated(Vector3.UP, -0.6).normalized()
	var branch_rt_l := branch_fwd_l.cross(Vector3.UP).normalized()
	var branch_fwd_r := fwd.rotated(Vector3.UP, 0.5).normalized()
	var branch_rt_r := branch_fwd_r.cross(Vector3.UP).normalized()

	# Left branch — short dead-end with loot
	var l_cursor := cursor
	for i in 2:
		var le := l_cursor + branch_fwd_l * SEGMENT_LENGTH
		le.y -= descent * 0.4
		_build_tunnel_segment(cave_root, l_cursor, le, branch_fwd_l, branch_rt_l, TUNNEL_WIDTH * 0.9, TUNNEL_HEIGHT * 0.9)
		l_cursor = le

	# Dead-end wall
	var lw := _make_box_static(
		Vector3(TUNNEL_WIDTH + WALL_THICKNESS * 2.0, TUNNEL_HEIGHT + WALL_THICKNESS, WALL_THICKNESS),
		_mat_cave_rock
	)
	lw.position = l_cursor + Vector3(0.0, TUNNEL_HEIGHT * 0.5, 0.0)
	_orient_along(lw, branch_fwd_l)
	cave_root.add_child(lw)

	_add_wall_torch(cave_root, l_cursor - branch_fwd_l * 2.0 + branch_rt_l * (TUNNEL_WIDTH * 0.35), 1.6)
	_add_cave_chest(cave_root, l_cursor - branch_fwd_l * 1.2, branch_fwd_l, rng)
	_add_cave_enemy(cave_root, l_cursor - branch_fwd_l * 5.0 + Vector3(0, 0.2, 0), "grizzly", enemy_idx)
	enemy_idx += 1

	for _v in rng.randi_range(2, 4):
		var vpos := cursor.lerp(l_cursor, rng.randf_range(0.3, 0.9))
		vpos.y += rng.randf_range(0.3, TUNNEL_HEIGHT * 0.5)
		vpos += branch_rt_l * (TUNNEL_WIDTH * 0.38) * (1.0 if rng.randf() < 0.5 else -1.0)
		_add_copper_vein_wall(cave_root, vpos, rng)

	# Right branch — continues to main path
	var r_cursor := cursor
	for i in 3:
		var re := r_cursor + branch_fwd_r * SEGMENT_LENGTH
		re.y -= descent * 0.6
		_build_tunnel_segment(cave_root, r_cursor, re, branch_fwd_r, branch_rt_r, TUNNEL_WIDTH, TUNNEL_HEIGHT)
		r_cursor = re
		if i == 1:
			_add_wall_torch(cave_root, r_cursor + branch_rt_r * (TUNNEL_WIDTH * 0.42), 1.8)
			_add_cave_enemy(cave_root, r_cursor + Vector3(0, 0.2, 0), "goblin", enemy_idx)
			enemy_idx += 1

	fwd = branch_fwd_r
	rt = branch_rt_r
	cursor = r_cursor
	cave_waypoints.append(cursor)
	cave_widths.append(TUNNEL_WIDTH)

	# ════════════════════════════════════════════════════
	#  SECTION 4: Deep corridor with enemies
	# ════════════════════════════════════════════════════
	for i in 4:
		var angle := rng.randf_range(-0.25, 0.25)
		fwd = fwd.rotated(Vector3.UP, angle).normalized()
		rt = fwd.cross(Vector3.UP).normalized()
		var seg_end := cursor + fwd * SEGMENT_LENGTH
		seg_end.y -= descent * 0.7
		_build_tunnel_segment(cave_root, cursor, seg_end, fwd, rt, TUNNEL_WIDTH, TUNNEL_HEIGHT)
		cursor = seg_end

		if i == 1:
			_add_wall_torch(cave_root, cursor - fwd * 3.0 - rt * (TUNNEL_WIDTH * 0.42), 1.8)
			_add_cave_enemy(cave_root, cursor - fwd * 2.0 + Vector3(0, 0.2, 0), "lion", enemy_idx)
			enemy_idx += 1
		elif i == 3:
			_add_cave_enemy(cave_root, cursor - fwd * 4.0 + Vector3(0, 0.2, 0), "grizzly", enemy_idx)
			enemy_idx += 1

	cave_waypoints.append(cursor)
	cave_widths.append(TUNNEL_WIDTH)

	for _v in rng.randi_range(3, 5):
		_add_copper_rock_ground(cave_root, cursor - fwd * rng.randf_range(4.0, 20.0) + rt * rng.randf_range(-1.2, 1.2) + Vector3(0, 0.15, 0), rng)

	# ════════════════════════════════════════════════════
	#  SECTION 5: Boss chamber
	# ════════════════════════════════════════════════════
	var boss_w := TUNNEL_WIDTH * 2.8
	var boss_h := TUNNEL_HEIGHT * 2.0
	var boss_len := 18.0
	var boss_start := cursor
	var boss_end := cursor + fwd * boss_len
	boss_end.y -= descent * 0.3
	_build_tunnel_segment(cave_root, boss_start, boss_end, fwd, rt, boss_w, boss_h)

	# Back wall
	var bw := _make_box_static(
		Vector3(boss_w + WALL_THICKNESS * 2.0, boss_h + WALL_THICKNESS, WALL_THICKNESS),
		_mat_cave_rock
	)
	bw.position = boss_end + Vector3(0.0, boss_h * 0.5, 0.0)
	_orient_along(bw, fwd)
	cave_root.add_child(bw)

	# Boss chamber torches
	for t_frac in [0.2, 0.5, 0.8]:
		var tp := boss_start.lerp(boss_end, t_frac)
		_add_wall_torch(cave_root, tp + rt * (boss_w * 0.42), 2.2)
		_add_wall_torch(cave_root, tp - rt * (boss_w * 0.42), 2.2)

	# Boss enemy — tougher grizzly
	var boss_pos := boss_start.lerp(boss_end, 0.5) + Vector3(0, 0.2, 0)
	_add_cave_enemy(cave_root, boss_pos, "grizzly", enemy_idx)
	enemy_idx += 1
	# Second boss enemy flanking
	_add_cave_enemy(cave_root, boss_pos + rt * 3.0, "lion", enemy_idx)
	enemy_idx += 1
	_add_cave_enemy(cave_root, boss_pos - rt * 3.0, "lion", enemy_idx)
	enemy_idx += 1

	# Boss chamber copper veins
	for _v in rng.randi_range(4, 6):
		var vp := rng.randf_range(0.1, 0.9)
		var vpos := boss_start.lerp(boss_end, vp)
		vpos.y += rng.randf_range(0.5, boss_h * 0.6)
		vpos += rt * (boss_w * 0.42) * (1.0 if rng.randf() < 0.5 else -1.0)
		_add_copper_vein_wall(cave_root, vpos, rng)

	# Boss chest at the very back
	var boss_chest_pos := boss_end - fwd * 2.0
	boss_chest_pos.y = boss_end.y
	_add_boss_chest(cave_root, boss_chest_pos, fwd, rng)

	cave_waypoints.append(boss_start)
	cave_widths.append(boss_w)
	cave_waypoints.append(boss_end)
	cave_widths.append(boss_w)

	# ── 100 goblins spread throughout the cave ──
	var total_goblins := 100
	var n_waypoints := cave_waypoints.size()
	for gi in total_goblins:
		var t_val := float(gi) / float(total_goblins - 1)
		var seg_f := t_val * float(n_waypoints - 1)
		var seg_i := mini(int(seg_f), n_waypoints - 2)
		var seg_t := seg_f - float(seg_i)
		var base_pos_g := cave_waypoints[seg_i].lerp(cave_waypoints[seg_i + 1], seg_t)
		var w := lerpf(cave_widths[seg_i], cave_widths[seg_i + 1], seg_t)
		var offset_x := rng.randf_range(-w * 0.35, w * 0.35)
		var offset_z := rng.randf_range(-1.5, 1.5)
		var spawn_pos := base_pos_g + Vector3(offset_x, 0.2, offset_z)
		_add_cave_enemy(cave_root, spawn_pos, "goblin", enemy_idx)
		enemy_idx += 1

	# ── Ambient lighting (dim, spread across dungeon) ──
	for li in 5:
		var lp := Vector3.ZERO.lerp(boss_end, (li + 1.0) / 6.0)
		lp.y += 3.5
		var dim := OmniLight3D.new()
		dim.light_color = Color(0.25, 0.25, 0.35)
		dim.light_energy = 0.15
		dim.omni_range = 175.0
		dim.shadow_enabled = false
		dim.position = lp
		cave_root.add_child(dim)

	return cave_root


static func _build_exit_marker(cave_root: Node3D) -> void:
	var exit_marker := StaticBody3D.new()
	exit_marker.name = "CaveExit"
	exit_marker.collision_layer = 4
	exit_marker.collision_mask = 0
	exit_marker.add_to_group(&"interactables")
	exit_marker.set_meta("cave_exit", true)

	var exit_label := Label3D.new()
	exit_label.name = "ExitLabel"
	exit_label.text = "[E] Exit Cave"
	exit_label.font_size = 28
	exit_label.modulate = Color(1.0, 0.85, 0.4)
	exit_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	exit_label.position.y = 2.0
	exit_label.visible = true
	exit_marker.add_child(exit_label)

	var exit_col := CollisionShape3D.new()
	var exit_box := BoxShape3D.new()
	exit_box.size = Vector3(3.0, 4.0, 2.0)
	exit_col.shape = exit_box
	exit_col.position.y = 2.0
	exit_marker.add_child(exit_col)

	var exit_light := OmniLight3D.new()
	exit_light.light_color = Color(0.8, 0.7, 0.5)
	exit_light.light_energy = 1.5
	exit_light.omni_range = 50.0
	exit_marker.position = Vector3(0.0, 0.0, 2.0)
	exit_marker.add_child(exit_light)
	cave_root.add_child(exit_marker)


static func _add_wall_torch(parent: Node3D, pos: Vector3, height: float) -> void:
	var torch := Node3D.new()
	torch.name = "CaveTorch"

	var stick := _make_box_mesh(Vector3(0.08, 0.5, 0.08), _mat_cave_rock)
	stick.position.y = height - 0.25
	torch.add_child(stick)

	var flame := OmniLight3D.new()
	flame.light_color = Color(1.0, 0.75, 0.4)
	flame.light_energy = 3.0
	flame.omni_range = 80.0
	flame.shadow_enabled = true
	flame.position.y = height + 0.1
	torch.add_child(flame)

	var glow := MeshInstance3D.new()
	var gs := SphereMesh.new()
	gs.radius = 0.06
	gs.height = 0.12
	glow.mesh = gs
	var gm := StandardMaterial3D.new()
	gm.emission_enabled = true
	gm.emission = Color(1.0, 0.7, 0.3)
	gm.emission_energy_multiplier = 5.0
	gm.albedo_color = Color(1.0, 0.8, 0.3)
	glow.set_surface_override_material(0, gm)
	glow.position.y = height + 0.05
	torch.add_child(glow)

	torch.position = pos
	parent.add_child(torch)


static func _add_boss_chest(parent: Node3D, pos: Vector3, fwd: Vector3, rng: RandomNumberGenerator) -> void:
	var chest := StaticBody3D.new()
	chest.collision_layer = 4
	chest.collision_mask = 0
	chest.add_to_group(&"interactables")
	chest.add_to_group(&"chests")
	chest.set_meta("build_id", &"chest")

	var sz := Vector3(2.4, 1.8, 1.5)
	PlayerBuilding.build_chest_visual(chest, sz)

	var col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = sz
	col.shape = box_col
	col.position.y = sz.y * 0.5
	chest.add_child(col)

	var label := Label3D.new()
	label.text = "[E] Boss Chest"
	label.font_size = 28
	label.modulate = Color(1.0, 0.7, 0.2)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = sz.y + 0.5
	label.visible = false
	chest.add_child(label)

	var slots: Array = []
	slots.resize(32)
	for i in 32:
		slots[i] = {}
	slots[0] = {"item_id": &"copper_ore", "count": rng.randi_range(8, 15)}
	slots[1] = {"item_id": &"iron_ore", "count": rng.randi_range(3, 6)}
	slots[2] = {"item_id": &"leather", "count": rng.randi_range(4, 8)}
	slots[3] = {"item_id": &"resin", "count": rng.randi_range(6, 12)}
	slots[4] = {"item_id": &"bone", "count": rng.randi_range(5, 10)}
	if rng.randf() < 0.5:
		slots[5] = {"item_id": &"amber", "count": rng.randi_range(1, 3)}

	chest.set_meta("chest_contents", slots)
	VillageGenerator._add_chest_rarity_sheen(chest, slots, sz)

	chest.position = pos
	if fwd.length_squared() > 0.01:
		chest.look_at_from_position(pos, pos - fwd, Vector3.UP)
	parent.add_child(chest)


# ═══════════════════════════════════════════════════════════════════════════════
#  GEOMETRY BUILDERS
# ═══════════════════════════════════════════════════════════════════════════════

static func _build_entrance_arch(facing: Vector3) -> Node3D:
	var arch := Node3D.new()
	arch.name = "EntranceArch"

	var hw := TUNNEL_WIDTH * 0.5 + WALL_THICKNESS

	var lp := _make_box_mesh(Vector3(WALL_THICKNESS * 1.5, TUNNEL_HEIGHT + 0.5, WALL_THICKNESS * 2.0), _mat_cave_rock)
	lp.position = Vector3(-hw, (TUNNEL_HEIGHT + 0.5) * 0.5, 0.0)
	arch.add_child(lp)

	var rp := _make_box_mesh(Vector3(WALL_THICKNESS * 1.5, TUNNEL_HEIGHT + 0.5, WALL_THICKNESS * 2.0), _mat_cave_rock)
	rp.position = Vector3(hw, (TUNNEL_HEIGHT + 0.5) * 0.5, 0.0)
	arch.add_child(rp)

	var top := _make_box_mesh(Vector3(TUNNEL_WIDTH + WALL_THICKNESS * 4.0, WALL_THICKNESS * 1.5, WALL_THICKNESS * 2.0), _mat_cave_rock)
	top.position = Vector3(0.0, TUNNEL_HEIGHT + 0.5, 0.0)
	arch.add_child(top)

	for i in 4:
		var rock := _make_sphere_mesh(randi_range(3, 5) * 0.15, _mat_cave_rock)
		var rx := randf_range(-hw - 0.5, hw + 0.5)
		var ry := randf_range(0.0, TUNNEL_HEIGHT * 0.4)
		rock.position = Vector3(rx, ry, randf_range(-0.3, 0.3))
		arch.add_child(rock)

	if facing.length_squared() > 0.01:
		arch.look_at_from_position(Vector3.ZERO, facing, Vector3.UP)

	return arch


static func _build_tunnel_segment(
	parent: Node3D,
	seg_start: Vector3,
	seg_end: Vector3,
	fwd: Vector3,
	right_vec: Vector3,
	width: float,
	height: float,
) -> void:
	var seg_center := (seg_start + seg_end) * 0.5
	var seg_len := seg_start.distance_to(seg_end)
	var hw := width * 0.5

	var floor_node := _make_box_static(Vector3(width + WALL_THICKNESS, FLOOR_THICKNESS, seg_len + 0.2), _mat_cave_floor)
	floor_node.position = seg_center + Vector3(0.0, -FLOOR_THICKNESS * 0.5, 0.0)
	_orient_along(floor_node, fwd)
	parent.add_child(floor_node)

	var ceil_node := _make_box_static(Vector3(width + WALL_THICKNESS * 2.0, WALL_THICKNESS, seg_len + 0.2), _mat_cave_rock)
	ceil_node.position = seg_center + Vector3(0.0, height, 0.0)
	_orient_along(ceil_node, fwd)
	parent.add_child(ceil_node)

	var lw := _make_box_static(Vector3(WALL_THICKNESS, height + WALL_THICKNESS, seg_len + 0.2), _mat_cave_rock)
	lw.position = seg_center + right_vec * -(hw + WALL_THICKNESS * 0.5) + Vector3(0.0, height * 0.5, 0.0)
	_orient_along(lw, fwd)
	parent.add_child(lw)

	var rw := _make_box_static(Vector3(WALL_THICKNESS, height + WALL_THICKNESS, seg_len + 0.2), _mat_cave_rock)
	rw.position = seg_center + right_vec * (hw + WALL_THICKNESS * 0.5) + Vector3(0.0, height * 0.5, 0.0)
	_orient_along(rw, fwd)
	parent.add_child(rw)


static func _orient_along(node: Node3D, fwd: Vector3) -> void:
	if fwd.length_squared() < 0.01:
		return
	var target := node.position + fwd
	node.look_at_from_position(node.position, target, Vector3.UP)


# ═══════════════════════════════════════════════════════════════════════════════
#  CONTENT SPAWNERS
# ═══════════════════════════════════════════════════════════════════════════════

static func _add_copper_vein_wall(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var vein := StaticBody3D.new()
	vein.collision_layer = 4
	vein.collision_mask = 0
	vein.add_to_group(&"interactables")
	vein.set_meta("harvestable", true)
	vein.set_meta("hp", 40.0)
	vein.set_meta("max_hp", 40.0)
	vein.set_meta("drop_id", &"copper_ore")
	vein.set_meta("drop_min", 2)
	vein.set_meta("drop_max", 4)
	vein.set_meta("requires_pickaxe", true)

	var scale_f := rng.randf_range(0.6, 1.1)
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.45 * scale_f
	sphere.height = 0.7 * scale_f
	sphere.radial_segments = 6
	sphere.rings = 3
	mi.mesh = sphere
	mi.set_surface_override_material(0, _mat_copper_vein)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	vein.add_child(mi)

	var col := CollisionShape3D.new()
	var col_sphere := SphereShape3D.new()
	col_sphere.radius = 0.5 * scale_f
	col.shape = col_sphere
	vein.add_child(col)

	var label := Label3D.new()
	label.name = "VeinLabel"
	label.text = "Copper Vein"
	label.font_size = 24
	label.modulate = Color(0.9, 0.6, 0.2)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.7
	label.visible = false
	vein.add_child(label)

	vein.position = pos
	parent.add_child(vein)


static func _add_copper_rock_ground(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var rock := StaticBody3D.new()
	rock.collision_layer = 4
	rock.collision_mask = 0
	rock.add_to_group(&"interactables")
	rock.set_meta("harvestable", true)
	rock.set_meta("hp", 25.0)
	rock.set_meta("max_hp", 25.0)
	rock.set_meta("drop_id", &"copper_ore")
	rock.set_meta("drop_min", 1)
	rock.set_meta("drop_max", 3)
	rock.set_meta("requires_pickaxe", true)

	var sf := rng.randf_range(0.5, 0.9)
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5 * sf
	sphere.height = 0.6 * sf
	sphere.radial_segments = 5
	sphere.rings = 3
	mi.mesh = sphere
	mi.set_surface_override_material(0, _mat_copper_vein)
	mi.position.y = 0.25 * sf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	rock.add_child(mi)

	var col := CollisionShape3D.new()
	var col_sphere := SphereShape3D.new()
	col_sphere.radius = 0.5 * sf
	col.shape = col_sphere
	col.position.y = 0.25 * sf
	rock.add_child(col)

	var label := Label3D.new()
	label.name = "RockLabel"
	label.text = "Copper Deposit"
	label.font_size = 22
	label.modulate = Color(0.9, 0.6, 0.2)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 0.8
	label.visible = false
	rock.add_child(label)

	rock.position = pos
	parent.add_child(rock)


static func _add_cave_chest(parent: Node3D, pos: Vector3, fwd: Vector3, rng: RandomNumberGenerator) -> void:
	var chest := StaticBody3D.new()
	chest.collision_layer = 4
	chest.collision_mask = 0
	chest.add_to_group(&"interactables")
	chest.add_to_group(&"chests")
	chest.set_meta("build_id", &"chest")

	var sz := Vector3(1.92, 1.44, 1.2)

	PlayerBuilding.build_chest_visual(chest, sz)

	var col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = sz
	col.shape = box_col
	col.position.y = sz.y * 0.5
	chest.add_child(col)

	var label := Label3D.new()
	label.text = "[E] Chest"
	label.font_size = 24
	label.modulate = Color(1.0, 0.85, 0.4)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = sz.y + 0.4
	label.visible = false
	chest.add_child(label)

	var slots: Array = []
	slots.resize(32)
	for i in 32:
		slots[i] = {}
	slots[0] = {"item_id": &"copper_ore", "count": rng.randi_range(4, 8)}
	slots[1] = {"item_id": &"resin", "count": rng.randi_range(3, 6)}
	slots[2] = {"item_id": &"leather", "count": rng.randi_range(2, 5)}
	if rng.randf() < 0.4:
		slots[3] = {"item_id": &"bone", "count": rng.randi_range(3, 6)}

	chest.set_meta("chest_contents", slots)
	VillageGenerator._add_chest_rarity_sheen(chest, slots, sz)

	chest.position = pos
	if fwd.length_squared() > 0.01:
		chest.look_at_from_position(pos, pos - fwd, Vector3.UP)

	parent.add_child(chest)


static func _add_cave_enemy(parent: Node3D, pos: Vector3, creature_type: String, idx: int = 0) -> void:
	var stats := ZonePopulator._creature_stats(StringName(creature_type))
	if stats.is_empty():
		return

	var enemy := _CreatureAI.new()
	enemy.display_name = stats.get("name", "Creature") as String
	enemy.creature_type = creature_type
	enemy.max_health = float(stats.get("hp", 50.0))
	enemy.attack_damage = float(stats.get("dmg", 10.0))
	enemy.move_speed = float(stats.get("spd", 3.0))
	enemy.attack_cooldown = float(stats.get("cd", 2.0))
	enemy.aggro_range = 10.0
	enemy.leash_range = 50.0

	var sprite := Sprite3D.new()
	sprite.name = "BodySprite"
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.pixel_size = 1.0 / 100.0
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.position.y = float(stats.get("sprite_y", 0.8))
	var tex_dict: Dictionary = stats.get("tex", {}) as Dictionary
	if tex_dict.has("south"):
		sprite.texture = tex_dict["south"] as Texture2D
	enemy.add_child(sprite)

	enemy.sprite_textures = tex_dict
	enemy.run_frames = stats.get("run_tex", {}) as Dictionary
	enemy.attack_frames = stats.get("atk_tex", {}) as Dictionary
	var _loot := ZonePopulator._creature_loot_for(StringName(creature_type))
	enemy.loot_table = _loot.get("normal", [])
	enemy.rare_loot_table = _loot.get("rare", [])

	var col_r: float = float(stats.get("col_r", 0.4))
	var col_h: float = float(stats.get("col_h", 1.0))
	var col_y: float = float(stats.get("col_y", 0.5))
	var col_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = col_r
	capsule.height = col_h
	col_shape.shape = capsule
	col_shape.position.y = col_y
	enemy.add_child(col_shape)

	enemy.name = "CaveCreature_%d" % idx
	enemy.position = pos
	parent.add_child(enemy)


# ═══════════════════════════════════════════════════════════════════════════════
#  MESH HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

static func _make_box_mesh(size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = size
	mi.mesh = bx
	mi.set_surface_override_material(0, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


static func _make_box_static(size: Vector3, mat: StandardMaterial3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0

	var mi := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = size
	mi.mesh = bx
	mi.set_surface_override_material(0, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(mi)

	var col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = size
	col.shape = box_col
	body.add_child(col)

	return body


static func _make_sphere_mesh(radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 6
	sphere.rings = 3
	mi.mesh = sphere
	mi.set_surface_override_material(0, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi
