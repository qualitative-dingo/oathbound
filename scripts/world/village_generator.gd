class_name VillageGenerator
extends RefCounted

const ZONE_SIZE := 64.0
const VILLAGE_CHANCE := 0.12
const MIN_HUTS := 6
const MAX_HUTS := 12
const CHEST_CHANCE := 0.333
const VILLAGE_RADIUS_MIN := 17.0
const VILLAGE_RADIUS_MAX := 34.0
const MIN_HEIGHT := 1.0

const WALL_W := 3.6
const WALL_H := 5.0
const WALL_T := 0.20
const FLOOR_W := 3.6
const FLOOR_D := 3.6
const FLOOR_T := 0.1

static var _mat_inited := false

static func _ensure_materials() -> void:
	if _mat_inited:
		return
	_mat_inited = true
	PlayerBuilding.ensure_building_materials()


# ── Hut variation table ───────────────────────────────────────────────────────

# gx/gz = footprint in grid cells (each cell = WALL_W = 3.6 m, matching player building pieces)
# walls = max surviving wall segments, mat = "wood"/"stone"/"mixed"
const HUT_VARIATIONS: Array[Dictionary] = [
	{"gx": 1, "gz": 1, "roof": "thatch_45", "walls": 4, "mat": "wood",  "floor": true,  "door": true},
	{"gx": 1, "gz": 1, "roof": "thatch_26", "walls": 3, "mat": "wood",  "floor": true,  "door": true},
	{"gx": 1, "gz": 1, "roof": "none",      "walls": 2, "mat": "wood",  "floor": false, "door": false},
	{"gx": 1, "gz": 1, "roof": "collapsed",  "walls": 3, "mat": "wood",  "floor": true,  "door": true},
	{"gx": 2, "gz": 1, "roof": "thatch_45", "walls": 4, "mat": "wood",  "floor": true,  "door": true},
	{"gx": 1, "gz": 2, "roof": "thatch_45", "walls": 3, "mat": "wood",  "floor": true,  "door": true},
	{"gx": 2, "gz": 2, "roof": "thatch_45", "walls": 4, "mat": "wood",  "floor": true,  "door": true},
	{"gx": 2, "gz": 2, "roof": "thatch_26", "walls": 3, "mat": "wood",  "floor": true,  "door": true},
	{"gx": 2, "gz": 2, "roof": "collapsed",  "walls": 4, "mat": "wood",  "floor": true,  "door": true},
	{"gx": 1, "gz": 1, "roof": "thatch_45", "walls": 4, "mat": "stone", "floor": true,  "door": true},
	{"gx": 1, "gz": 1, "roof": "thatch_26", "walls": 3, "mat": "stone", "floor": true,  "door": false},
	{"gx": 1, "gz": 1, "roof": "none",      "walls": 2, "mat": "stone", "floor": true,  "door": false},
	{"gx": 2, "gz": 1, "roof": "thatch_45", "walls": 3, "mat": "stone", "floor": true,  "door": true},
	{"gx": 2, "gz": 2, "roof": "thatch_45", "walls": 4, "mat": "stone", "floor": true,  "door": true},
	{"gx": 2, "gz": 2, "roof": "thatch_26", "walls": 3, "mat": "mixed", "floor": true,  "door": true},
	{"gx": 1, "gz": 1, "roof": "collapsed",  "walls": 2, "mat": "mixed", "floor": false, "door": false},
	{"gx": 2, "gz": 1, "roof": "collapsed",  "walls": 3, "mat": "mixed", "floor": true,  "door": true},
	{"gx": 3, "gz": 2, "roof": "thatch_45", "walls": 4, "mat": "wood",  "floor": true,  "door": true},
	{"gx": 2, "gz": 3, "roof": "thatch_26", "walls": 4, "mat": "stone", "floor": true,  "door": true},
	{"gx": 3, "gz": 3, "roof": "thatch_45", "walls": 4, "mat": "mixed", "floor": true,  "door": true},
	{"gx": 1, "gz": 1, "roof": "thatch_45", "walls": 2, "mat": "mixed", "floor": true,  "door": true},
	{"gx": 1, "gz": 2, "roof": "thatch_26", "walls": 4, "mat": "stone", "floor": true,  "door": true},
	{"gx": 1, "gz": 2, "roof": "collapsed",  "walls": 2, "mat": "wood",  "floor": false, "door": false},
	{"gx": 2, "gz": 1, "roof": "thatch_26", "walls": 3, "mat": "wood",  "floor": true,  "door": false},
	{"gx": 2, "gz": 1, "roof": "none",      "walls": 2, "mat": "stone", "floor": true,  "door": false},
	{"gx": 2, "gz": 2, "roof": "none",      "walls": 3, "mat": "mixed", "floor": true,  "door": true},
	{"gx": 3, "gz": 1, "roof": "thatch_45", "walls": 4, "mat": "wood",  "floor": true,  "door": true},
	{"gx": 1, "gz": 3, "roof": "thatch_26", "walls": 3, "mat": "wood",  "floor": true,  "door": true},
	{"gx": 3, "gz": 2, "roof": "collapsed",  "walls": 3, "mat": "stone", "floor": true,  "door": true},
	{"gx": 3, "gz": 3, "roof": "thatch_26", "walls": 4, "mat": "stone", "floor": true,  "door": true},
	# ── additional variations (15) ──
	{"gx": 1, "gz": 1, "roof": "thatch_26", "walls": 4, "mat": "mixed", "floor": true,  "door": true},
	{"gx": 1, "gz": 1, "roof": "collapsed",  "walls": 2, "mat": "stone", "floor": false, "door": false},
	{"gx": 2, "gz": 1, "roof": "thatch_45", "walls": 4, "mat": "mixed", "floor": true,  "door": true},
	{"gx": 2, "gz": 1, "roof": "collapsed",  "walls": 2, "mat": "wood",  "floor": false, "door": false},
	{"gx": 1, "gz": 2, "roof": "thatch_45", "walls": 4, "mat": "mixed", "floor": true,  "door": true},
	{"gx": 1, "gz": 2, "roof": "none",      "walls": 2, "mat": "wood",  "floor": true,  "door": false},
	{"gx": 2, "gz": 2, "roof": "thatch_45", "walls": 3, "mat": "mixed", "floor": true,  "door": true},
	{"gx": 2, "gz": 2, "roof": "collapsed",  "walls": 2, "mat": "stone", "floor": true,  "door": false},
	{"gx": 2, "gz": 2, "roof": "none",      "walls": 2, "mat": "wood",  "floor": false, "door": false},
	{"gx": 3, "gz": 1, "roof": "thatch_26", "walls": 3, "mat": "stone", "floor": true,  "door": true},
	{"gx": 3, "gz": 1, "roof": "collapsed",  "walls": 2, "mat": "mixed", "floor": true,  "door": false},
	{"gx": 1, "gz": 3, "roof": "thatch_45", "walls": 4, "mat": "stone", "floor": true,  "door": true},
	{"gx": 3, "gz": 2, "roof": "thatch_26", "walls": 3, "mat": "wood",  "floor": true,  "door": true},
	{"gx": 3, "gz": 3, "roof": "collapsed",  "walls": 3, "mat": "mixed", "floor": true,  "door": true},
	{"gx": 3, "gz": 3, "roof": "none",      "walls": 2, "mat": "stone", "floor": true,  "door": false},
]


# ── Main entry point ──────────────────────────────────────────────────────────

static func try_spawn_village(
	zone_root: Node3D,
	coord: Vector2i,
	rng: RandomNumberGenerator,
	origin_x: float,
	origin_z: float,
	height_func: Callable,
) -> void:
	if rng.randf() > VILLAGE_CHANCE:
		return

	var margin := 16.0
	var cx := origin_x + rng.randf_range(margin, ZONE_SIZE - margin)
	var cz := origin_z + rng.randf_range(margin, ZONE_SIZE - margin)
	var ch := float(height_func.call(cx, cz))

	if ch < MIN_HEIGHT:
		return

	if not _is_flat_enough(cx, cz, VILLAGE_RADIUS_MAX, height_func, ch):
		return

	_ensure_materials()

	var village_root := Node3D.new()
	village_root.name = "AbandonedVillage"
	village_root.position = Vector3(cx, 0, cz)
	zone_root.add_child(village_root)

	var hut_count := rng.randi_range(MIN_HUTS, MAX_HUTS)
	var angle_step := TAU / float(hut_count)
	var placed_huts: Array[Dictionary] = []  # {"x", "z", "radius"}
	var chest_count := 0
	var hut_positions: Array[Dictionary] = []

	for i in hut_count:
		var angle := angle_step * i + rng.randf_range(-0.4, 0.4)
		var radius := rng.randf_range(VILLAGE_RADIUS_MIN, VILLAGE_RADIUS_MAX)
		var hx := cx + cos(angle) * radius
		var hz := cz + sin(angle) * radius
		var hh := ZonePopulator._snap_height_to_mesh(hx, hz, height_func)
		if hh < 0.5:
			continue

		var var_idx := rng.randi_range(0, HUT_VARIATIONS.size() - 1)
		var v: Dictionary = HUT_VARIATIONS[var_idx]
		var hut_half := maxf(v["gx"] as int * WALL_W, v["gz"] as int * FLOOR_D) * 0.5 + 1.0

		if _overlaps_placed(hx, hz, hut_half, placed_huts):
			continue

		placed_huts.append({"x": hx, "z": hz, "radius": hut_half})
		var face_angle := atan2(cz - hz, cx - hx) + rng.randf_range(-0.3, 0.3)

		_place_hut(village_root, Vector3(hx, hh, hz) - village_root.position, face_angle, var_idx, rng)
		hut_positions.append({"hx": hx, "hh": hh, "hz": hz, "face": face_angle})

		if rng.randf() < CHEST_CHANCE:
			var chest_offset := Vector3(cos(face_angle) * 0.5, 0, sin(face_angle) * 0.5)
			var chest_pos := Vector3(hx, hh, hz) - village_root.position + chest_offset
			_place_village_chest(village_root, chest_pos, face_angle, rng)
			chest_count += 1

	if chest_count == 0 and hut_positions.size() > 0:
		var pick: Dictionary = hut_positions[rng.randi_range(0, hut_positions.size() - 1)]
		var fa: float = pick["face"]
		var co := Vector3(cos(fa) * 0.5, 0, sin(fa) * 0.5)
		var cp := Vector3(pick["hx"], pick["hh"], pick["hz"]) - village_root.position + co
		_place_village_chest(village_root, cp, fa, rng)

	_place_hero_asset(village_root, Vector3(0, ch, 0), rng)


## Spawn a village at an exact world position, bypassing random chance and flatness checks.
static func force_spawn_village(
	zone_root: Node3D,
	world_x: float,
	world_z: float,
	height_func: Callable,
	seed_val: int = 99999,
) -> void:
	_ensure_materials()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	var ch := float(height_func.call(world_x, world_z))
	if ch < 0.2:
		ch = 0.5

	var village_root := Node3D.new()
	village_root.name = "AbandonedVillage_Forced"
	village_root.position = Vector3(world_x, 0, world_z)
	zone_root.add_child(village_root)

	var hut_count := rng.randi_range(MIN_HUTS, MAX_HUTS)
	var angle_step := TAU / float(hut_count)
	var placed_huts: Array[Dictionary] = []
	var chest_count := 0
	var hut_positions: Array[Dictionary] = []

	for i in hut_count:
		var angle := angle_step * i + rng.randf_range(-0.4, 0.4)
		var radius := rng.randf_range(VILLAGE_RADIUS_MIN, VILLAGE_RADIUS_MAX)
		var hx := world_x + cos(angle) * radius
		var hz := world_z + sin(angle) * radius
		var hh := ZonePopulator._snap_height_to_mesh(hx, hz, height_func)
		if hh < 0.3:
			hh = ch

		var var_idx := rng.randi_range(0, HUT_VARIATIONS.size() - 1)
		var v: Dictionary = HUT_VARIATIONS[var_idx]
		var hut_half := maxf(v["gx"] as int * WALL_W, v["gz"] as int * FLOOR_D) * 0.5 + 1.0

		if _overlaps_placed(hx, hz, hut_half, placed_huts):
			continue

		placed_huts.append({"x": hx, "z": hz, "radius": hut_half})
		var face_angle := atan2(world_z - hz, world_x - hx) + rng.randf_range(-0.3, 0.3)

		_place_hut(village_root, Vector3(hx, hh, hz) - village_root.position, face_angle, var_idx, rng)
		hut_positions.append({"hx": hx, "hh": hh, "hz": hz, "face": face_angle})

		if rng.randf() < CHEST_CHANCE:
			var chest_offset := Vector3(cos(face_angle) * 0.5, 0, sin(face_angle) * 0.5)
			var chest_pos := Vector3(hx, hh, hz) - village_root.position + chest_offset
			_place_village_chest(village_root, chest_pos, face_angle, rng)
			chest_count += 1

	if chest_count == 0 and hut_positions.size() > 0:
		var pick: Dictionary = hut_positions[rng.randi_range(0, hut_positions.size() - 1)]
		var fa: float = pick["face"]
		var co := Vector3(cos(fa) * 0.5, 0, sin(fa) * 0.5)
		var cp := Vector3(pick["hx"], pick["hh"], pick["hz"]) - village_root.position + co
		_place_village_chest(village_root, cp, fa, rng)

	_place_hero_asset(village_root, Vector3(0, ch, 0), rng)


static func _overlaps_placed(hx: float, hz: float, hut_half: float, placed: Array[Dictionary]) -> bool:
	for p: Dictionary in placed:
		var dx: float = hx - (p["x"] as float)
		var dz: float = hz - (p["z"] as float)
		var min_dist: float = hut_half + (p["radius"] as float)
		if dx * dx + dz * dz < min_dist * min_dist:
			return true
	return false


static func _is_flat_enough(cx: float, cz: float, radius: float, height_func: Callable, center_h: float) -> bool:
	var max_diff := 0.0
	for angle in [0.0, TAU * 0.25, TAU * 0.5, TAU * 0.75]:
		var sx := cx + cos(angle) * radius
		var sz := cz + sin(angle) * radius
		var sh := float(height_func.call(sx, sz))
		max_diff = maxf(max_diff, absf(sh - center_h))
	return max_diff < 4.0


# ── Hut construction ──────────────────────────────────────────────────────────

static func _place_hut(parent: Node3D, pos: Vector3, yaw: float, var_idx: int, rng: RandomNumberGenerator) -> void:
	var v: Dictionary = HUT_VARIATIONS[var_idx]
	var gx: int = v["gx"]
	var gz: int = v["gz"]
	var w: float = gx * WALL_W
	var d: float = gz * FLOOR_D
	var h: float = WALL_H
	var roof_type: String = v["roof"]
	var mat_type: String = v["mat"]
	var has_floor: bool = v["floor"]
	var has_door: bool = v["door"]

	var anchor := Node3D.new()
	anchor.name = "HutAnchor_%d" % var_idx
	anchor.position = pos
	anchor.rotation.y = yaw
	anchor.add_to_group(&"structures")
	anchor.set_meta("footprint_radius", maxf(w, d) * 0.5 + 2.0)
	parent.add_child(anchor)

	var wall_id: StringName
	var floor_id: StringName
	match mat_type:
		"stone":
			wall_id = &"stone_wall"
			floor_id = &"stone_floor"
		"mixed":
			wall_id = &"stone_wall" if rng.randf() < 0.5 else &"wood_wall"
			floor_id = &"wood_floor" if rng.randf() < 0.5 else &"stone_floor"
		_:
			wall_id = &"wood_wall"
			floor_id = &"wood_floor"

	var wall_mat := _mat_for_id(wall_id)
	var floor_mat := _mat_for_id(floor_id)

	# ── Collect all component descriptors before spawning ──
	var components: Array[Dictionary] = []

	if has_floor:
		for ix in gx:
			for iz in gz:
				var ox: float = (ix - (gx - 1) * 0.5) * FLOOR_W
				var oz: float = (iz - (gz - 1) * 0.5) * FLOOR_D
				components.append({"kind": "floor", "local_pos": Vector3(ox, 0.0, oz),
					"build_id": floor_id, "mat": floor_mat})

	var hw := w * 0.5
	var hd := d * 0.5
	var n_front := ceili(w / WALL_W)
	var n_side := ceili(d / WALL_W)
	var wall_descs: Array[Dictionary] = []
	for i in n_front:
		var seg_w := minf(WALL_W, w - i * WALL_W)
		var ox: float = -hw + i * WALL_W + seg_w * 0.5
		wall_descs.append({"pos": Vector3(ox, 0.0, hd), "size": Vector3(seg_w, h, WALL_T), "side": "front"})
		wall_descs.append({"pos": Vector3(ox, 0.0, -hd), "size": Vector3(seg_w, h, WALL_T), "side": "back"})
	for i in n_side:
		var seg_w := minf(WALL_W, d - i * WALL_W)
		var oz: float = -hd + i * WALL_W + seg_w * 0.5
		wall_descs.append({"pos": Vector3(-hw, 0.0, oz), "size": Vector3(WALL_T, h, seg_w), "side": "left"})
		wall_descs.append({"pos": Vector3(hw, 0.0, oz), "size": Vector3(WALL_T, h, seg_w), "side": "right"})

	# Always remove one front wall segment (entrance facing village center)
	if not wall_descs.is_empty():
		var front_ids: Array[int] = []
		for si in wall_descs.size():
			if wall_descs[si]["side"] == "front":
				front_ids.append(si)
		if not front_ids.is_empty():
			wall_descs.remove_at(front_ids[rng.randi_range(0, front_ids.size() - 1)])

	# Always remove one side wall segment so the player can walk in from the side
	var side_ids: Array[int] = []
	for si in wall_descs.size():
		var s: String = wall_descs[si]["side"]
		if s == "left" or s == "right":
			side_ids.append(si)
	if not side_ids.is_empty():
		wall_descs.remove_at(side_ids[rng.randi_range(0, side_ids.size() - 1)])

	for wd: Dictionary in wall_descs:
		components.append({"kind": "wall", "local_pos": wd["pos"] as Vector3,
			"wall_size": wd["size"] as Vector3, "build_id": wall_id, "mat": wall_mat})

	if roof_type in ["thatch_45", "thatch_26"]:
		var rise: float = h * 0.6 if roof_type == "thatch_45" else h * 0.35
		var roof_id: StringName = &"thatch_roof_45" if roof_type == "thatch_45" else &"thatch_roof_26"
		for iz in gz:
			var section_d: float = (d + 0.4) / float(gz)
			var oz: float = (iz - (gz - 1) * 0.5) * FLOOR_D
			components.append({"kind": "roof", "local_pos": Vector3(0.0, h, oz),
				"roof_size": Vector3(w + 0.4, rise, section_d), "rise": rise,
				"build_id": roof_id})
	elif roof_type == "collapsed":
		var slab_count := rng.randi_range(2, 4)
		for i in slab_count:
			components.append({"kind": "collapsed_roof", "index": i, "w": w, "d": d, "h": h,
				"build_id": &"thatch_roof_26"})

	# ── Enforce >= 80% completeness ──
	var total := components.size()
	var max_remove := floori(total * 0.2)
	if max_remove > 0:
		var removable: Array[int] = []
		for ci in total:
			removable.append(ci)
		for ri in range(removable.size() - 1, 0, -1):
			var rj := rng.randi_range(0, ri)
			var tmp := removable[ri]
			removable[ri] = removable[rj]
			removable[rj] = tmp
		var remove_count := rng.randi_range(0, max_remove)
		var skip_set: Dictionary = {}
		for ri in remove_count:
			skip_set[removable[ri]] = true

		for ci in total:
			if skip_set.has(ci):
				continue
			_spawn_piece(anchor, components[ci], rng)
	else:
		for ci in total:
			_spawn_piece(anchor, components[ci], rng)


static func _mat_for_id(build_id: StringName) -> StandardMaterial3D:
	if build_id in [&"wood_wall", &"wood_floor", &"wood_stair", &"wood_door"]:
		return PlayerBuilding._bmat_wood
	elif build_id in [&"stone_wall", &"stone_floor", &"stone_door"]:
		return PlayerBuilding._bmat_stone
	elif String(build_id).begins_with("thatch_roof"):
		return PlayerBuilding._bmat_thatch
	elif String(build_id).begins_with("slate_roof"):
		return PlayerBuilding._bmat_slate
	return PlayerBuilding._bmat_wood


static func _spawn_piece(anchor: Node3D, comp: Dictionary, rng: RandomNumberGenerator) -> void:
	var kind: String = comp["kind"]
	match kind:
		"floor":
			_spawn_floor_piece(anchor, comp)
		"wall":
			_spawn_wall_piece(anchor, comp, rng)
		"roof":
			_spawn_roof_piece(anchor, comp)
		"collapsed_roof":
			_spawn_collapsed_piece(anchor, comp, rng)


static func _make_building_body(build_id: StringName) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 1
	body.add_to_group(&"structures")
	body.set_meta("build_id", build_id)
	return body


static func _spawn_floor_piece(anchor: Node3D, comp: Dictionary) -> void:
	var build_id: StringName = comp["build_id"]
	var mat: StandardMaterial3D = comp["mat"]
	var sz := Vector3(FLOOR_W, FLOOR_T, FLOOR_D)

	var piece := _make_building_body(build_id)
	piece.name = "Floor"
	piece.position = comp["local_pos"] as Vector3

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position.y = FLOOR_T * 0.5
	piece.add_child(mi)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = sz
	col.shape = box
	col.position.y = FLOOR_T * 0.5
	piece.add_child(col)

	anchor.add_child(piece)


static func _spawn_wall_piece(anchor: Node3D, comp: Dictionary, rng: RandomNumberGenerator) -> void:
	var build_id: StringName = comp["build_id"]
	var mat: StandardMaterial3D = comp["mat"]
	var sz: Vector3 = comp["wall_size"]

	var piece := _make_building_body(build_id)
	piece.name = "Wall"
	piece.position = comp["local_pos"] as Vector3
	var tilt := rng.randf_range(-0.03, 0.03)

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	mi.mesh = mesh
	mi.set_surface_override_material(0, mat)
	mi.position.y = sz.y * 0.5
	mi.rotation.z = tilt
	piece.add_child(mi)

	var col := CollisionShape3D.new()
	var col_box := BoxShape3D.new()
	col_box.size = Vector3(sz.x + 0.1, sz.y, sz.z + 0.1)
	col.shape = col_box
	col.position.y = sz.y * 0.5
	col.rotation.z = tilt
	piece.add_child(col)

	anchor.add_child(piece)


static func _spawn_roof_piece(anchor: Node3D, comp: Dictionary) -> void:
	var build_id: StringName = comp["build_id"]
	var sz: Vector3 = comp["roof_size"]
	var rise: float = comp["rise"]

	var piece := _make_building_body(build_id)
	piece.name = "Roof"
	piece.position = comp["local_pos"] as Vector3

	var mesh := PlayerBuilding.build_roof_mesh(sz, rise)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.set_surface_override_material(0, PlayerBuilding._bmat_thatch)
	piece.add_child(mi)

	var col := CollisionShape3D.new()
	var col_box := BoxShape3D.new()
	col_box.size = Vector3(sz.x, sz.y * 0.5, sz.z)
	col.shape = col_box
	col.position.y = sz.y * 0.25
	piece.add_child(col)

	anchor.add_child(piece)


static func _spawn_collapsed_piece(anchor: Node3D, comp: Dictionary, rng: RandomNumberGenerator) -> void:
	var build_id: StringName = comp["build_id"]
	var i: int = comp["index"]
	var w: float = comp["w"]
	var d: float = comp["d"]
	var h: float = comp["h"]

	var slab_w := w * rng.randf_range(0.4, 0.7)
	var slab_d := d * rng.randf_range(0.3, 0.6)
	var sz := Vector3(slab_w, 0.08, slab_d)

	var piece := _make_building_body(build_id)
	piece.name = "CollapsedRoof_%d" % i

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	mi.mesh = mesh
	mi.set_surface_override_material(0, PlayerBuilding._bmat_thatch)
	piece.add_child(mi)

	var col := CollisionShape3D.new()
	var col_box := BoxShape3D.new()
	col_box.size = sz
	col.shape = col_box
	piece.add_child(col)

	var ox := rng.randf_range(-w * 0.3, w * 0.3)
	var oz := rng.randf_range(-d * 0.3, d * 0.3)
	var sag := rng.randf_range(0.0, h * 0.15)
	piece.position = Vector3(ox, h - sag + i * 0.06, oz)
	piece.rotation.x = rng.randf_range(-0.2, 0.2)
	piece.rotation.z = rng.randf_range(-0.2, 0.2)

	anchor.add_child(piece)


# ── Village chest ─────────────────────────────────────────────────────────────

static func _place_village_chest(parent: Node3D, pos: Vector3, yaw: float, rng: RandomNumberGenerator) -> void:
	var chest := StaticBody3D.new()
	chest.name = "VillageChest"
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

	var contents := _fill_village_chest(rng)
	chest.set_meta("chest_contents", contents)
	_add_chest_rarity_sheen(chest, contents, sz)
	chest.position = pos
	chest.rotation.y = yaw + PI
	parent.add_child(chest)


static func _get_chest_max_stars(contents: Array) -> int:
	var best := 0
	for slot in contents:
		if slot is Dictionary:
			var sid: StringName = slot.get("item_id", &"") as StringName
			if sid == &"":
				continue
			var parsed: Dictionary = ItemDatabase.parse_star_id(sid)
			var s: int = int(parsed.get("stars", 0))
			if s > best:
				best = s
	return best


static func _add_chest_rarity_sheen(chest: Node3D, contents: Array, sz: Vector3) -> void:
	var stars := _get_chest_max_stars(contents)
	if stars <= 0:
		return
	var col: Color = ItemDatabase.get_rarity_color(stars)

	var light := OmniLight3D.new()
	light.name = "RaritySheen"
	light.light_color = col
	light.light_energy = 0.6 + stars * 0.25
	light.omni_range = 2.5 + stars * 0.5
	light.omni_attenuation = 1.5
	light.shadow_enabled = false
	light.position.y = sz.y + 0.3
	chest.add_child(light)

	var glow := MeshInstance3D.new()
	glow.name = "RarityGlow"
	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(sz.x + 0.08, sz.y + 0.08, sz.z + 0.08)
	glow.mesh = glow_mesh
	var glow_mat := StandardMaterial3D.new()
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.albedo_color = Color(col.r, col.g, col.b, 0.12 + stars * 0.03)
	glow_mat.emission_enabled = true
	glow_mat.emission = col
	glow_mat.emission_energy_multiplier = 0.3 + stars * 0.15
	glow_mat.no_depth_test = false
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.set_surface_override_material(0, glow_mat)
	glow.position.y = sz.y * 0.5
	chest.add_child(glow)


# ── Loot table ────────────────────────────────────────────────────────────────

const _MATERIAL_POOL: Array[Dictionary] = [
	{"id": &"wood",       "min": 3, "max": 8},
	{"id": &"stone",      "min": 2, "max": 5},
	{"id": &"leather",    "min": 1, "max": 4},
	{"id": &"resin",      "min": 2, "max": 4},
	{"id": &"bone",       "min": 1, "max": 3},
	{"id": &"copper_ore", "min": 2, "max": 5},
]

const _GEAR_POOL: Array[StringName] = [
	&"stone_axe", &"stone_sword", &"stone_pickaxe", &"crude_bow",
	&"leather_vest", &"leather_pants", &"leather_boots", &"wood_shield",
]

const _GEAR_AFFIX_SLOT: Dictionary = {
	&"stone_axe": "axe", &"stone_sword": "sword", &"stone_pickaxe": "pickaxe",
	&"crude_bow": "bow", &"leather_vest": "chest", &"leather_pants": "legs",
	&"leather_boots": "feet", &"wood_shield": "shield",
}

const _STAR_WEIGHTS: Array[float] = [0.30, 0.20, 0.20, 0.20, 0.10]


static func _fill_village_chest(rng: RandomNumberGenerator) -> Array:
	var slots: Array = []
	slots.resize(32)
	for i in 32:
		slots[i] = {}

	var pool := _MATERIAL_POOL.duplicate()
	for si in range(pool.size() - 1, 0, -1):
		var sj := rng.randi_range(0, si)
		var tmp: Dictionary = pool[si]
		pool[si] = pool[sj]
		pool[sj] = tmp
	var mat_count := rng.randi_range(2, 4)
	for i in mini(mat_count, pool.size()):
		var entry: Dictionary = pool[i]
		slots[i] = {"item_id": entry["id"], "count": rng.randi_range(entry["min"], entry["max"])}

	if true:
		var gear_id: StringName = _GEAR_POOL[rng.randi_range(0, _GEAR_POOL.size() - 1)]
		var stars := _roll_star_level(rng)
		if stars > 0:
			var affixes: Array[StringName] = []
			var affix_rolls: Dictionary = {}
			if stars >= 2:
				var slot_key: String = _GEAR_AFFIX_SLOT.get(gear_id, "")
				if slot_key != "":
					affixes = ItemDatabase.roll_affixes(stars, slot_key)
					affix_rolls = ItemDatabase.roll_affix_magnitudes(affixes)
			gear_id = ItemDatabase.make_star_id(gear_id, stars, affixes, affix_rolls)
		slots[mat_count] = {"item_id": gear_id, "count": 1}

	return slots


static func _roll_star_level(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	var cumulative := 0.0
	for i in _STAR_WEIGHTS.size():
		cumulative += _STAR_WEIGHTS[i]
		if roll < cumulative:
			return i + 1
	return 5


# ── Hero centerpiece ──────────────────────────────────────────────────────────

const _HERO_PATHS: Array[String] = [
	"res://models/village/stone_statue.glb",
	"res://models/village/stone_well.glb",
	"res://models/village/broken_cart.glb",
]

static var _hero_scenes: Array = []
static var _hero_loaded := false


static func _ensure_hero_assets() -> void:
	if _hero_loaded:
		return
	_hero_loaded = true
	_hero_scenes.resize(_HERO_PATHS.size())
	for i in _HERO_PATHS.size():
		var scene := load(_HERO_PATHS[i]) as PackedScene
		_hero_scenes[i] = scene


static func _place_hero_asset(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	_ensure_hero_assets()

	var idx := rng.randi_range(0, _HERO_PATHS.size() - 1)
	var scene: PackedScene = _hero_scenes[idx] as PackedScene
	if scene == null:
		_place_hero_fallback(parent, pos, rng)
		return

	var instance: Node = scene.instantiate()
	if instance == null:
		_place_hero_fallback(parent, pos, rng)
		return
	instance.name = ["StoneStatue", "StoneWell", "BrokenCart"][idx]
	if instance is Node3D:
		(instance as Node3D).position = pos
		(instance as Node3D).rotation.y = rng.randf_range(0, TAU)
		(instance as Node3D).scale = Vector3.ONE * 1.5
		(instance as Node3D).add_to_group(&"structures")
	parent.add_child(instance)


static func _place_hero_fallback(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var pillar := MeshInstance3D.new()
	pillar.name = "HeroFallback"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.35
	mesh.bottom_radius = 0.5
	mesh.height = 2.2
	pillar.mesh = mesh
	pillar.set_surface_override_material(0, PlayerBuilding._bmat_stone)
	pillar.position = pos + Vector3(0, 1.1, 0)
	pillar.rotation.z = rng.randf_range(-0.05, 0.05)
	pillar.add_to_group(&"structures")
	parent.add_child(pillar)
