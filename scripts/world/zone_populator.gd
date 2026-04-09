class_name ZonePopulator
extends RefCounted

const _DEBUG_LOG := false

## Deterministically scatters proper 3D objects into zones.
##
## Trees = procedural trunk (root flare + buttress ridges) + billboard leaf canopy.
## Rocks = low-poly SphereMesh with triplanar stone texture.
## Bushes = small squished SphereMesh with triplanar leaf texture.
## All materials use triplanar mapping.
## Creatures keep billboards (they have directional sprite swapping).

const _CreatureAI := preload("res://scripts/creatures/creature_ai.gd")
const _LootDrop := preload("res://scripts/items/loot_drop.gd")
const _VillageGenerator := preload("res://scripts/world/village_generator.gd")
const _FishIdle := preload("res://scripts/creatures/fish_idle.gd")
const _ZonePool := preload("res://scripts/world/zone_pool.gd")
const _MerchantNPC := preload("res://scripts/npcs/merchant_npc.gd")

const ZONE_SIZE := 64.0
const _MIN_LAND_Y := 0.5
const _WATER_LEVEL := 0.0
const _TREE_LINE_START := 22.0
const _TREE_LINE_END := 37.0

# ─── Floating origin offset (set by WorldGenerator on each origin shift) ──────
static var origin_shift := Vector3.ZERO

# ─── Structures group cache (refreshed once per frame to avoid repeated scene tree scans) ──
static var _cached_structures: Array = []
static var _structures_cache_frame: int = -1

static func _get_structures_cached() -> Array:
	var current_frame := Engine.get_frames_drawn()
	if current_frame != _structures_cache_frame:
		var tree := Engine.get_main_loop() as SceneTree
		var raw := tree.get_nodes_in_group(&"structures") if tree else []
		_cached_structures = []
		for node in raw:
			if is_instance_valid(node):
				_cached_structures.append(node)
		_structures_cache_frame = current_frame
	return _cached_structures

# ─── Berry bushes group cache ──
static var _cached_bushes: Array = []
static var _bushes_cache_frame: int = -1

static func _get_berry_bushes_cached() -> Array:
	var current_frame := Engine.get_frames_drawn()
	if current_frame != _bushes_cache_frame:
		var tree := Engine.get_main_loop() as SceneTree
		var raw := tree.get_nodes_in_group(&"berry_bushes") if tree else []
		_cached_bushes = []
		for node in raw:
			if is_instance_valid(node):
				_cached_bushes.append(node)
		_bushes_cache_frame = current_frame
	return _cached_bushes


static func _get_world_generator() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return null
	var nodes := tree.get_nodes_in_group(&"world_generator")
	if nodes.is_empty():
		return null
	return nodes[0]

# ─── Goblin camp positions (world XZ) for minimum distance enforcement ────────
static var _goblin_camp_positions: Array[Vector2] = []
const _GOBLIN_CAMP_MIN_DIST := 120.0

# ─── Zone height grid (pre-computed to avoid per-blade noise calls) ───────────
const _HG_RES := 48
const _HG_PAD := 2        # extra cells on each side for slope/cliff checks near zone edges
const _HG_FULL := _HG_RES + _HG_PAD * 2
static var _hg_data := PackedFloat32Array()
static var _hg_coord := Vector2i(-999999, -999999)
static var _hg_origin_x := 0.0
static var _hg_origin_z := 0.0
static var _hg_step := ZONE_SIZE / float(_HG_RES)

static func _ensure_height_grid(coord: Vector2i, height_func: Callable) -> void:
	if coord == _hg_coord:
		return
	_hg_coord = coord
	_hg_origin_x = coord.x * ZONE_SIZE - _HG_PAD * _hg_step
	_hg_origin_z = coord.y * ZONE_SIZE - _HG_PAD * _hg_step
	var w := _HG_FULL + 1
	var total := w * w
	if _hg_data.size() != total:
		_hg_data.resize(total)
	for gz in w:
		for gx in w:
			var wx := _hg_origin_x + gx * _hg_step
			var wz := _hg_origin_z + gz * _hg_step
			_hg_data[gz * w + gx] = float(height_func.call(wx, wz))

static func _hg_sample(wx: float, wz: float) -> float:
	var gx := (wx - _hg_origin_x) / _hg_step
	var gz := (wz - _hg_origin_z) / _hg_step
	var w := _HG_FULL + 1
	var ix := clampi(int(gx), 0, _HG_FULL - 1)
	var iz := clampi(int(gz), 0, _HG_FULL - 1)
	var fx := clampf(gx - float(ix), 0.0, 1.0)
	var fz := clampf(gz - float(iz), 0.0, 1.0)
	var h00 := _hg_data[iz * w + ix]
	var h10 := _hg_data[iz * w + ix + 1]
	var h01 := _hg_data[(iz + 1) * w + ix]
	var h11 := _hg_data[(iz + 1) * w + ix + 1]
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)

static func _hg_snap_and_normal(wx: float, wz: float) -> Vector2:
	const STEP := ZONE_SIZE / 48.0
	var gx := floorf(wx / STEP) * STEP
	var gz := floorf(wz / STEP) * STEP
	var fx := (wx - gx) / STEP
	var fz := (wz - gz) / STEP
	var h00 := _hg_sample(gx, gz)
	var h10 := _hg_sample(gx + STEP, gz)
	var h01 := _hg_sample(gx, gz + STEP)
	var h11 := _hg_sample(gx + STEP, gz + STEP)
	var snapped: float
	if fx + fz <= 1.0:
		snapped = h00 + (h10 - h00) * fx + (h01 - h00) * fz
	else:
		snapped = h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)
	var tx := Vector3(2.0 * STEP, h10 - h00 + h11 - h01, 0.0)
	var tz := Vector3(0.0, h01 - h00 + h11 - h10, 2.0 * STEP)
	var ny := tz.cross(tx).normalized().y
	return Vector2(snapped, ny)

static func _hg_snap_height(wx: float, wz: float) -> float:
	const STEP := ZONE_SIZE / 48.0
	var gx := floorf(wx / STEP) * STEP
	var gz := floorf(wz / STEP) * STEP
	var fx := (wx - gx) / STEP
	var fz := (wz - gz) / STEP
	var h00 := _hg_sample(gx, gz)
	var h10 := _hg_sample(gx + STEP, gz)
	var h01 := _hg_sample(gx, gz + STEP)
	var h11 := _hg_sample(gx + STEP, gz + STEP)
	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)

static func _hg_is_steep_edge(wx: float, wz: float, ground_y: float) -> bool:
	const R := 10.0
	var h_l := _hg_snap_height(wx - R, wz)
	var h_r := _hg_snap_height(wx + R, wz)
	var h_u := _hg_snap_height(wx, wz - R)
	var h_d := _hg_snap_height(wx, wz + R)
	var slope_x := absf(h_r - h_l) / (R * 2.0)
	var slope_z := absf(h_d - h_u) / (R * 2.0)
	if slope_x > 0.28 or slope_z > 0.28:
		return true
	if absf(ground_y - h_l) > 5.0 or absf(ground_y - h_r) > 5.0 \
			or absf(ground_y - h_u) > 5.0 or absf(ground_y - h_d) > 5.0:
		return true
	return false

# ─── Flower rejection grid (pre-computed to skip expensive noise per sample)
const _RG_RES := 16
const _RG_CELL := ZONE_SIZE / float(_RG_RES)
const _RG_DENSITY_LOW := 1
const _RG_DIRT := 2
const _RG_PATH := 4
const _RG_WATER := 8
const _RG_STRUCTURE := 16
const _RG_BUSH := 32
static var _rg_data := PackedByteArray()
static var _rg_coord := Vector2i(-999999, -999999)

static func _ensure_rejection_grid(coord: Vector2i, origin_x: float, origin_z: float) -> void:
	if coord == _rg_coord:
		return
	_rg_coord = coord
	_rg_data.resize(_RG_RES * _RG_RES)
	var wg := _get_world_generator()
	for gz in _RG_RES:
		for gx in _RG_RES:
			var wx := origin_x + (gx + 0.5) * _RG_CELL
			var wz := origin_z + (gz + 0.5) * _RG_CELL
			var idx := gz * _RG_RES + gx
			var flags := 0
			if _vegetation_density_noise(wx, wz) < 0.18:
				flags |= _RG_DENSITY_LOW
			if is_dirt_patch(wx, wz):
				flags |= _RG_DIRT
			if is_on_path(wx, wz):
				flags |= _RG_PATH
			if wg and wg.has_method("_ws_sample_accum"):
				var accum: float = wg._ws_sample_accum(wx, wz)
				if accum > 1.5:
					flags |= _RG_WATER
			_rg_data[idx] = flags

	var os := origin_shift
	var structs := _get_structures_cached()
	for s in structs:
		if not is_instance_valid(s):
			continue
		var sp: Vector3 = (s as Node3D).global_position
		var swx := sp.x + os.x
		var swz := sp.z + os.z
		var r := 4.0
		if (s as Node3D).has_meta("footprint_radius"):
			r = float((s as Node3D).get_meta("footprint_radius"))
		else:
			for child in (s as Node3D).get_children():
				if not is_instance_valid(child):
					continue
				if child is CollisionShape3D and child.shape is BoxShape3D:
					var sz: Vector3 = (child.shape as BoxShape3D).size
					r = maxf(r, maxf(sz.x, sz.z) * 0.5 + 1.5)
					break
		var lx := swx - origin_x
		var lz := swz - origin_z
		if lx < -r or lx > ZONE_SIZE + r or lz < -r or lz > ZONE_SIZE + r:
			continue
		var cmin_x := maxi(0, int((lx - r) / _RG_CELL))
		var cmax_x := mini(_RG_RES - 1, int((lx + r) / _RG_CELL))
		var cmin_z := maxi(0, int((lz - r) / _RG_CELL))
		var cmax_z := mini(_RG_RES - 1, int((lz + r) / _RG_CELL))
		for rgz in range(cmin_z, cmax_z + 1):
			for rgx in range(cmin_x, cmax_x + 1):
				var cx := origin_x + (rgx + 0.5) * _RG_CELL
				var cz := origin_z + (rgz + 0.5) * _RG_CELL
				if (cx - swx) * (cx - swx) + (cz - swz) * (cz - swz) < r * r:
					_rg_data[rgz * _RG_RES + rgx] |= _RG_STRUCTURE

	var bushes := _get_berry_bushes_cached()
	for b in bushes:
		if not is_instance_valid(b):
			continue
		var bp: Vector3 = (b as Node3D).global_position
		var bwx := bp.x + os.x
		var bwz := bp.z + os.z
		var blx := bwx - origin_x
		var blz := bwz - origin_z
		if blx < -2.0 or blx > ZONE_SIZE + 2.0 or blz < -2.0 or blz > ZONE_SIZE + 2.0:
			continue
		var cgx := clampi(int(blx / _RG_CELL), 0, _RG_RES - 1)
		var cgz := clampi(int(blz / _RG_CELL), 0, _RG_RES - 1)
		_rg_data[cgz * _RG_RES + cgx] |= _RG_BUSH

# ─── Debug toggles (set by DebugPanel to skip spawning categories) ────────────
static var debug_skip_trees := false
static var debug_skip_rocks := false
static var debug_skip_saplings := false
static var debug_skip_flowers := false
static var debug_skip_creatures := false
static var debug_skip_villages := false
static var debug_skip_stones := false
static var debug_skip_fish := false
static var debug_skip_horses := false
static var debug_skip_grass := false

# ─── Shared materials ──────────────────────────────────────────────────────────

static var _mat_bark: StandardMaterial3D
static var _mat_leaves: Material
static var _mat_pine_leaves: Material
static var _mat_palm_leaves: Material
static var _mat_stone: Material
static var _rock_shader: Shader
static var _mat_pebble: StandardMaterial3D
static var _rock_meshes: Array[ArrayMesh] = []
static var _rock_convex_shapes: Array[ConvexPolygonShape3D] = []
static var _mat_bush_leaves: Material
static var _mat_birch_bark: StandardMaterial3D
static var _mat_birch_leaves: Material
static var _wind_shader: Shader
static var _leaf_shader: Shader
static var _leaf_tex_oak: ImageTexture
static var _leaf_tex_birch: ImageTexture
static var _leaf_tex_pine: ImageTexture
static var _leaf_tex_willow: ImageTexture
static var _leaf_tex_palm: ImageTexture
static var _leaf_tex_generic: ImageTexture

# Creature 3D-enhancement shaders + cached materials
static var _creature_shader: Shader
static var _shadow_mat: StandardMaterial3D

# Creature billboard textures
static var _tex_boar: Dictionary = {}  # {south/east/north/west -> Texture2D}
static var _tex_skeleton: Dictionary = {}
static var _tex_grizzly: Dictionary = {}
static var _tex_blackbear: Dictionary = {}
static var _tex_lion: Dictionary = {}
static var _tex_grizzly_run: Dictionary = {}
static var _tex_grizzly_attack: Dictionary = {}
static var _tex_blackbear_run: Dictionary = {}
static var _tex_blackbear_attack: Dictionary = {}
static var _tex_lion_run: Dictionary = {}
static var _tex_lion_attack: Dictionary = {}
static var _tex_moose: Dictionary = {}
static var _tex_mamabear: Dictionary = {}
static var _tex_tiger: Dictionary = {}
static var _tex_boar_walk: Dictionary = {}
static var _tex_boar_run: Dictionary = {}
static var _tex_moose_walk: Dictionary = {}
static var _tex_moose_run: Dictionary = {}
static var _tex_grizzly_walk: Dictionary = {}
static var _tex_blackbear_walk: Dictionary = {}
static var _tex_lion_walk: Dictionary = {}
static var _tex_mamabear_walk: Dictionary = {}
static var _tex_mamabear_run: Dictionary = {}
static var _tex_tiger_walk: Dictionary = {}
static var _tex_tiger_run: Dictionary = {}
static var _tex_tiger_attack: Dictionary = {}
static var _tex_hawk: Dictionary = {}
static var _tex_hawk_fly: Dictionary = {}
static var _tex_hawk_attack: Dictionary = {}
static var _tex_seagull: Dictionary = {}
static var _tex_seagull_fly: Dictionary = {}
static var _tex_seagull_idle: Dictionary = {}
static var _tex_fish: Dictionary = {}
static var _tex_fish_idle: Dictionary = {}
static var _tex_horse: Dictionary = {}
static var _tex_horse_walk: Dictionary = {}  # {dir -> Array[Texture2D]} walk animation frames
static var _tex_horse_run: Dictionary = {}   # {dir -> Array[Texture2D]} run animation frames
static var _tex_bush: Texture2D  # fallback if no 3D tex

static var _billboard_shader: Shader  # Used for reeds and other billboard vegetation
static var _billboard_quad_mesh: ArrayMesh  # Cross-plane mesh for billboard vegetation
static var _leaf_unit_quad: QuadMesh
static var _flower_textures: Array[ImageTexture] = []

static var _water_plants_ready := false
static var _lily_pad_mesh: ArrayMesh
static var _lily_pad_mat: StandardMaterial3D
static var _lily_flower_mesh: ArrayMesh
static var _lily_flower_mat: StandardMaterial3D
static var _lily_stem_mat: StandardMaterial3D
static var _cattail_mat: StandardMaterial3D
static var _cattail_head_mat: StandardMaterial3D
static var _loosestrife_mat: StandardMaterial3D
static var _loosestrife_flower_mat: StandardMaterial3D
static var _reed_mat: ShaderMaterial
static var _grass_mat: ShaderMaterial
static var _grass_texture: ImageTexture

static var _berry_bushes_ready := false
static var _blueberry_leaf_mat: Material
static var _lingonberry_leaf_mat: Material
static var _blueberry_mat: StandardMaterial3D
static var _lingonberry_mat: StandardMaterial3D

static var _textures_loaded := false


## Force full texture/shader reload on next zone population.
## Call at game start to ensure fresh state after code changes.
static func reset_texture_cache() -> void:
	_textures_loaded = false
	_cached_leaf_mats.clear()
	_cached_flower_mats.clear()
	_flower_types_table.clear()
	_merchant_spawned = false
	_signposts_spawned.clear()
	print("[ZonePopulator] Texture cache reset - will reload on next use")


static func _ensure_textures() -> void:
	if _textures_loaded:
		return
	_textures_loaded = true

	var bark_tex := _try_load("res://textures/materials/bark.png")
	var leaves_tex := _try_load("res://textures/materials/leaves.png")
	var stone_tex := _try_load("res://textures/materials/stone.png")

	for dir in ["south", "east", "north", "west"]:
		var boar_path := "res://textures/creatures/boar_%s.png" % dir
		if ResourceLoader.exists(boar_path):
			_tex_boar[dir] = load(boar_path) as Texture2D
		var skel_path := "res://textures/creatures/skeleton_%s.png" % dir
		if ResourceLoader.exists(skel_path):
			_tex_skeleton[dir] = load(skel_path) as Texture2D
		var grizzly_path := "res://textures/creatures/grizzly_%s.png" % dir
		if ResourceLoader.exists(grizzly_path):
			_tex_grizzly[dir] = load(grizzly_path) as Texture2D
		var bb_path := "res://textures/creatures/blackbear_%s.png" % dir
		if ResourceLoader.exists(bb_path):
			_tex_blackbear[dir] = load(bb_path) as Texture2D
		var lion_path := "res://textures/creatures/lion_%s.png" % dir
		if ResourceLoader.exists(lion_path):
			_tex_lion[dir] = load(lion_path) as Texture2D
		var hawk_path := "res://textures/creatures/hawk_%s.png" % dir
		if ResourceLoader.exists(hawk_path):
			_tex_hawk[dir] = load(hawk_path) as Texture2D
		var seagull_path := "res://textures/creatures/seagull_%s.png" % dir
		if ResourceLoader.exists(seagull_path):
			_tex_seagull[dir] = load(seagull_path) as Texture2D
		var fish_path := "res://textures/creatures/fish_%s.png" % dir
		if ResourceLoader.exists(fish_path):
			_tex_fish[dir] = load(fish_path) as Texture2D
		var moose_path := "res://textures/creatures/moose_%s.png" % dir
		if ResourceLoader.exists(moose_path):
			_tex_moose[dir] = load(moose_path) as Texture2D
		var mamabear_path := "res://textures/creatures/mamabear_%s.png" % dir
		if ResourceLoader.exists(mamabear_path):
			_tex_mamabear[dir] = load(mamabear_path) as Texture2D
		var tiger_path := "res://textures/creatures/tiger_%s.png" % dir
		if ResourceLoader.exists(tiger_path):
			_tex_tiger[dir] = load(tiger_path) as Texture2D

		for creature_info: Array in [
			["grizzly_run", _tex_grizzly_run, 8],
			["grizzly_attack", _tex_grizzly_attack, 7],
			["blackbear_run", _tex_blackbear_run, 8],
			["blackbear_attack", _tex_blackbear_attack, 7],
			["lion_run", _tex_lion_run, 8],
			["lion_attack", _tex_lion_attack, 9],
			["hawk_fly", _tex_hawk_fly, 16],
			["hawk_attack", _tex_hawk_attack, 16],
			["seagull_fly", _tex_seagull_fly, 16],
			["seagull_idle", _tex_seagull_idle, 8],
			["fish_idle", _tex_fish_idle, 8],
			["boar_walk", _tex_boar_walk, 8],
			["boar_run", _tex_boar_run, 8],
			["moose_walk", _tex_moose_walk, 8],
			["moose_run", _tex_moose_run, 8],
			["grizzly_walk", _tex_grizzly_walk, 8],
			["blackbear_walk", _tex_blackbear_walk, 8],
			["lion_walk", _tex_lion_walk, 8],
			["mamabear_walk", _tex_mamabear_walk, 8],
			["mamabear_run", _tex_mamabear_run, 8],
			["tiger_walk", _tex_tiger_walk, 8],
			["tiger_run", _tex_tiger_run, 8],
			["tiger_attack", _tex_tiger_attack, 9],
		]:
			var folder: String = creature_info[0]
			var target: Dictionary = creature_info[1]
			var frame_count: int = creature_info[2]
			var anim_frames: Array[Texture2D] = []
			for fi in frame_count:
				var fpath := "res://textures/creatures/%s/%s_%d.png" % [folder, dir, fi]
				if ResourceLoader.exists(fpath):
					var ftex := load(fpath) as Texture2D
					if ftex:
						anim_frames.append(ftex)
			if not anim_frames.is_empty():
				target[dir] = anim_frames

		var horse_path := "res://textures/creatures/horse_%s.png" % dir
		if ResourceLoader.exists(horse_path):
			_tex_horse[dir] = load(horse_path) as Texture2D
		var walk_frames: Array[Texture2D] = []
		for fi in 4:
			var wpath := "res://textures/creatures/horse_walk/%s_%d.png" % [dir, fi]
			if ResourceLoader.exists(wpath):
				var wtex := load(wpath) as Texture2D
				if wtex:
					walk_frames.append(wtex)
		if not walk_frames.is_empty():
			_tex_horse_walk[dir] = walk_frames
		var run_frames: Array[Texture2D] = []
		for ri in 8:
			var rpath := "res://textures/creatures/horse_run/%s_%d.png" % [dir, ri]
			if ResourceLoader.exists(rpath):
				var rtex := load(rpath) as Texture2D
				if rtex:
					run_frames.append(rtex)
		if not run_frames.is_empty():
			_tex_horse_run[dir] = run_frames

	# ── Bark material — wraps around CylinderMesh trunk ──
	_mat_bark = _make_triplanar_mat(bark_tex, Color(0.35, 0.22, 0.12))
	_mat_bark.uv1_scale = Vector3(4.0, 2.0, 4.0)

	# ── Birch bark — procedural white/beige with dark lenticel marks ──
	var birch_tex := _generate_birch_bark_texture()
	_mat_birch_bark = StandardMaterial3D.new()
	_mat_birch_bark.albedo_texture = birch_tex
	_mat_birch_bark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mat_birch_bark.uv1_triplanar = true
	_mat_birch_bark.uv1_world_triplanar = true
	_mat_birch_bark.uv1_triplanar_sharpness = 1.0
	_mat_birch_bark.uv1_scale = Vector3(3.0, 2.0, 3.0)
	_mat_birch_bark.roughness = 0.7

	# ── Wind foliage shader ──
	if ResourceLoader.exists("res://shaders/wind_foliage.gdshader"):
		_wind_shader = load("res://shaders/wind_foliage.gdshader") as Shader

	# ── Billboard shader + quad mesh (used for reeds and other vegetation) ──
	if ResourceLoader.exists("res://shaders/grass_billboard.gdshader"):
		_billboard_shader = load("res://shaders/grass_billboard.gdshader") as Shader
	_billboard_quad_mesh = _create_billboard_cross(1.0, 1.0)
	_leaf_unit_quad = QuadMesh.new()
	_leaf_unit_quad.size = Vector2(1.0, 1.0)

	_flower_textures.clear()
	for fi in 10:
		_flower_textures.append(_gen_flower_texture(fi))

	# ── Creature 3D-enhancement shaders ──
	if ResourceLoader.exists("res://shaders/creature_sprite.gdshader"):
		_creature_shader = load("res://shaders/creature_sprite.gdshader") as Shader

	# Procedural radial-gradient shadow texture (no shader needed)
	var shadow_size := 64
	var shadow_img := Image.create(shadow_size, shadow_size, false, Image.FORMAT_RGBA8)
	var center := Vector2(shadow_size * 0.5, shadow_size * 0.5)
	var max_r := shadow_size * 0.5
	for sy in shadow_size:
		for sx in shadow_size:
			var dist := Vector2(sx, sy).distance_to(center) / max_r
			var a := (1.0 - smoothstep(0.25, 1.0, dist)) * 0.45
			shadow_img.set_pixel(sx, sy, Color(0.02, 0.02, 0.05, a))
	var shadow_tex := ImageTexture.create_from_image(shadow_img)
	_shadow_mat = StandardMaterial3D.new()
	_shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shadow_mat.albedo_texture = shadow_tex
	_shadow_mat.albedo_color = Color.WHITE
	_shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shadow_mat.no_depth_test = false
	_shadow_mat.render_priority = -1

	# ── Leaf materials — shader-based with wind ──
	_mat_leaves = _make_wind_leaf_mat(leaves_tex, Color(0.25, 0.55, 0.15))
	_mat_pine_leaves = _make_wind_leaf_mat(leaves_tex, Color(0.15, 0.35, 0.12))
	_mat_palm_leaves = _make_wind_leaf_mat(leaves_tex, Color(0.22, 0.55, 0.20))

	# ── Birch leaves — lighter, yellow-green ──
	_mat_birch_leaves = _make_wind_leaf_mat(leaves_tex, Color(0.32, 0.58, 0.15), 0.5, Vector3(4.0, 4.0, 4.0))

	# ── Rock shader + stone material ──
	if ResourceLoader.exists("res://shaders/rock.gdshader"):
		_rock_shader = load("res://shaders/rock.gdshader") as Shader
	if _rock_shader:
		var smat := ShaderMaterial.new()
		smat.shader = _rock_shader
		if stone_tex:
			smat.set_shader_parameter("stone_texture", stone_tex)
		smat.set_shader_parameter("normal_texture", _generate_stone_normal_map())
		smat.set_shader_parameter("stone_color", Color(0.5, 0.48, 0.45))
		smat.set_shader_parameter("stone_color_dark", Color(0.32, 0.30, 0.28))
		smat.set_shader_parameter("moss_color", Color(0.18, 0.38, 0.08))
		smat.set_shader_parameter("moss_threshold", 0.55)
		smat.set_shader_parameter("moss_blend_sharpness", 2.0)
		smat.set_shader_parameter("moss_noise_scale", 2.5)
		smat.set_shader_parameter("normal_strength", 0.8)
		smat.set_shader_parameter("ao_strength", 0.8)
		smat.set_shader_parameter("triplanar_scale", 1.0)
		_mat_stone = smat
	else:
		var fallback := _make_triplanar_mat(stone_tex, Color(0.5, 0.48, 0.45))
		fallback.uv1_scale = Vector3(1.0, 1.0, 1.0)
		fallback.normal_texture = _generate_stone_normal_map()
		fallback.normal_scale = 0.3
		_mat_stone = fallback

	# ── Pebble material — flat, muted, no normal map ──
	_mat_pebble = StandardMaterial3D.new()
	_mat_pebble.albedo_color = Color(0.42, 0.40, 0.37)
	_mat_pebble.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_mat_pebble.roughness = 0.95

	# ── 30 unique procedural rock meshes ──
	_rock_meshes.clear()
	_rock_convex_shapes.clear()
	for ri in 30:
		var rmesh := _generate_rock_mesh(ri)
		_rock_meshes.append(rmesh)
		_rock_convex_shapes.append(rmesh.create_convex_shape())

	# ── Bush leaves — shader-based with gentler wind ──
	_mat_bush_leaves = _make_wind_leaf_mat(leaves_tex, Color(0.28, 0.52, 0.18), 0.15, Vector3(4.0, 4.0, 4.0))

	# ── 2D leaf billboard textures (one per tree shape family) ──
	if ResourceLoader.exists("res://shaders/leaf_billboard.gdshader"):
		_leaf_shader = load("res://shaders/leaf_billboard.gdshader") as Shader
	_leaf_tex_oak = _gen_leaf_tex_oak()
	_leaf_tex_birch = _gen_leaf_tex_birch()
	_leaf_tex_pine = _gen_leaf_tex_pine()
	_leaf_tex_willow = _gen_leaf_tex_willow()
	_leaf_tex_palm = _gen_leaf_tex_palm()
	_leaf_tex_generic = _gen_leaf_tex_generic()

	_ensure_water_plants()
	_ensure_berry_bushes()


static func _ensure_berry_bushes() -> void:
	if _berry_bushes_ready:
		return
	_berry_bushes_ready = true

	var leaves_tex: Texture2D = null
	if ResourceLoader.exists("res://textures/leaves.png"):
		leaves_tex = load("res://textures/leaves.png") as Texture2D

	_blueberry_leaf_mat = _make_wind_leaf_mat(
		leaves_tex, Color(0.15, 0.38, 0.12), 0.20, Vector3(3.0, 3.0, 3.0))
	_lingonberry_leaf_mat = _make_wind_leaf_mat(
		leaves_tex, Color(0.10, 0.30, 0.08), 0.20, Vector3(3.0, 3.0, 3.0))

	_blueberry_mat = StandardMaterial3D.new()
	_blueberry_mat.albedo_color = Color(0.12, 0.08, 0.45)
	_blueberry_mat.emission_enabled = true
	_blueberry_mat.emission = Color(0.06, 0.04, 0.22)
	_blueberry_mat.emission_energy_multiplier = 0.4
	_blueberry_mat.roughness = 0.65
	_blueberry_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	_lingonberry_mat = StandardMaterial3D.new()
	_lingonberry_mat.albedo_color = Color(0.72, 0.08, 0.10)
	_lingonberry_mat.emission_enabled = true
	_lingonberry_mat.emission = Color(0.36, 0.04, 0.05)
	_lingonberry_mat.emission_energy_multiplier = 0.4
	_lingonberry_mat.roughness = 0.65
	_lingonberry_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


static func _create_blueberry_bush(rng: RandomNumberGenerator) -> StaticBody3D:
	if not _leaf_shader or not _leaf_tex_generic:
		return null

	var sf := rng.randf_range(0.53, 0.92)
	var trunk_h := 1.8 * sf
	var trunk_r := 0.03 * sf

	var root := StaticBody3D.new()
	root.name = "BlueberryBush"
	root.collision_layer = 32  # Layer 6: walk-through interactable (not in player collision_mask)
	root.collision_mask = 0
	root.add_to_group(&"interactables")
	root.add_to_group(&"berry_bushes")

	# Small bushes: collision for raycast only (player can walk through)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.7 * sf
	shape.height = trunk_h * 0.8
	col.shape = shape
	col.position.y = trunk_h * 0.4
	root.add_child(col)
	root.set_meta("skip_collision_lod", true)  # Tell LOD system to not toggle this

	root.set_meta("harvestable", true)
	root.set_meta("hp", 10.0 * sf)
	root.set_meta("max_hp", 10.0 * sf)
	root.set_meta("drop_id", &"blueberry")
	root.set_meta("drop_min", 1)
	root.set_meta("drop_max", 1)
	root.set_meta("harvest_type", &"bush")
	root.set_meta("tree_name", "Blueberry Bush")
	root.set_meta("trunk_h", trunk_h)
	root.set_meta("berry_harvest", true)

	var trunk_mi := MeshInstance3D.new()
	trunk_mi.name = "Trunk"
	trunk_mi.mesh = _build_trunk_mesh(trunk_r * 1.2, trunk_r * 0.4, trunk_h, 0, rng)
	trunk_mi.set_surface_override_material(0, _mat_bark)
	trunk_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trunk_mi)

	var leaf_tex: ImageTexture = _leaf_tex_generic
	var leaf_color := Color.from_hsv(
		rng.randf_range(0.25, 0.35),
		rng.randf_range(0.5, 0.7),
		rng.randf_range(0.4, 0.6))
	var leaf_mat := _make_tree_leaf_mat(leaf_tex, leaf_color, rng)

	var crown_y := trunk_h * 0.35
	var crown_r := 1.32 * sf
	var crown_h := trunk_h * 0.92

	var leaf_xforms: Array[Transform3D] = []

	for li in rng.randi_range(7, 10):
		var leaf_size := rng.randf_range(2.64, 3.96) * sf
		var pos := Vector3(
			rng.randf_range(-crown_r * 0.5, crown_r * 0.5),
			maxf(0.1, crown_y + rng.randf_range(-crown_h * 0.1, crown_h * 0.6)),
			rng.randf_range(-crown_r * 0.5, crown_r * 0.5))
		var rot := Vector3(
			rng.randf_range(-0.6, 0.6),
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.4, 0.4))
		var basis := Basis.from_euler(rot).scaled(Vector3(leaf_size, leaf_size, leaf_size))
		leaf_xforms.append(Transform3D(basis, pos))

	for li in rng.randi_range(6, 9):
		var leaf_size := rng.randf_range(1.85, 3.17) * sf
		var angle := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(crown_r * 0.3, crown_r)
		var pos := Vector3(
			cos(angle) * r,
			maxf(0.1, crown_y + rng.randf_range(-crown_h * 0.3, crown_h * 0.4)),
			sin(angle) * r)
		var rot := Vector3(
			rng.randf_range(-0.8, 0.8),
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.5, 0.5))
		var basis := Basis.from_euler(rot).scaled(Vector3(leaf_size, leaf_size, leaf_size))
		leaf_xforms.append(Transform3D(basis, pos))

	if not leaf_xforms.is_empty():
		var mm := MultiMesh.new()
		mm.mesh = _leaf_unit_quad
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false
		mm.instance_count = leaf_xforms.size()
		for i in leaf_xforms.size():
			mm.set_instance_transform(i, leaf_xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "LeafMM"
		mmi.multimesh = mm
		mmi.material_override = leaf_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)

	# PERF FIX: Batch all berries into single MMI instead of individual meshes
	# This reduces draw calls from 24-42 per bush to just 1
	_ensure_berry_bushes()
	var berry_count := rng.randi_range(24, 42)
	var berry_xforms: Array[Transform3D] = []
	var avg_radius := 0.09  # Average berry radius for uniform sphere mesh
	
	for _bi in berry_count:
		var b_angle := rng.randf_range(0.0, TAU)
		var b_out := rng.randf_range(0.1, crown_r * 0.8)
		var b_y := maxf(0.15, crown_y + rng.randf_range(-crown_h * 0.2, crown_h * 0.5))
		var b_scale := rng.randf_range(0.75, 1.3)  # Slight size variation
		var pos := Vector3(cos(b_angle) * b_out, b_y, sin(b_angle) * b_out)
		berry_xforms.append(Transform3D(Basis().scaled(Vector3(b_scale, b_scale, b_scale)), pos))
	
	if not berry_xforms.is_empty():
		var berry_sphere := SphereMesh.new()
		berry_sphere.radius = avg_radius
		berry_sphere.height = avg_radius * 2.0
		berry_sphere.radial_segments = 4
		berry_sphere.rings = 2
		
		var berry_mm := MultiMesh.new()
		berry_mm.mesh = berry_sphere
		berry_mm.transform_format = MultiMesh.TRANSFORM_3D
		berry_mm.use_colors = false
		berry_mm.instance_count = berry_xforms.size()
		for i in berry_xforms.size():
			berry_mm.set_instance_transform(i, berry_xforms[i])
		
		var berry_mmi := MultiMeshInstance3D.new()
		berry_mmi.name = "BerryMM"
		berry_mmi.multimesh = berry_mm
		berry_mmi.material_override = _blueberry_mat
		berry_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(berry_mmi)

	return root


static func _create_lingonberry_bush(rng: RandomNumberGenerator) -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = "LingonberryBush"
	root.collision_layer = 32  # Walk-through interactable
	root.collision_mask = 0

	var sf := rng.randf_range(0.4, 0.55)

	var bush_mi := MeshInstance3D.new()
	bush_mi.name = "MeshInstance3D"
	var sphere := SphereMesh.new()
	sphere.radius = 0.5 * sf
	sphere.height = 0.35 * sf
	sphere.radial_segments = 6
	sphere.rings = 3
	bush_mi.mesh = sphere
	bush_mi.set_surface_override_material(0, _lingonberry_leaf_mat)
	bush_mi.position.y = 0.18 * sf
	bush_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bush_mi.scale = Vector3(
		rng.randf_range(0.9, 1.3), rng.randf_range(0.55, 0.75), rng.randf_range(0.9, 1.3))
	bush_mi.rotation.y = rng.randf_range(0.0, TAU)
	root.add_child(bush_mi)

	# PERF FIX: Batch berries into single MMI
	var berry_count := rng.randi_range(5, 8)
	var berry_xforms: Array[Transform3D] = []
	var avg_radius := 0.065
	
	for _bi in berry_count:
		var angle := rng.randf_range(0.0, TAU)
		var elev := rng.randf_range(0.0, 0.8)
		var out := rng.randf_range(0.12, 0.35) * sf
		var bx := cos(angle) * out
		var bz := sin(angle) * out
		var by := bush_mi.position.y + elev * 0.25 * sf
		var b_scale := rng.randf_range(0.8, 1.2)
		berry_xforms.append(Transform3D(Basis().scaled(Vector3(b_scale, b_scale, b_scale)), Vector3(bx, by, bz)))
	
	if not berry_xforms.is_empty():
		var berry_sphere := SphereMesh.new()
		berry_sphere.radius = avg_radius
		berry_sphere.height = avg_radius * 2.0
		berry_sphere.radial_segments = 4
		berry_sphere.rings = 2
		
		var berry_mm := MultiMesh.new()
		berry_mm.mesh = berry_sphere
		berry_mm.transform_format = MultiMesh.TRANSFORM_3D
		berry_mm.use_colors = false
		berry_mm.instance_count = berry_xforms.size()
		for i in berry_xforms.size():
			berry_mm.set_instance_transform(i, berry_xforms[i])
		
		var berry_mmi := MultiMeshInstance3D.new()
		berry_mmi.name = "BerryMM"
		berry_mmi.multimesh = berry_mm
		berry_mmi.material_override = _lingonberry_mat
		berry_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(berry_mmi)

	# Small bushes: collision always enabled (no LOD toggle needed)
	var col := CollisionShape3D.new()
	var col_shape := SphereShape3D.new()
	col_shape.radius = 0.35 * sf
	col.shape = col_shape
	col.position.y = 0.18 * sf
	root.add_child(col)
	root.set_meta("skip_collision_lod", true)  # Tell LOD system to not toggle this

	root.add_to_group(&"interactables")
	root.add_to_group(&"berry_bushes")
	root.set_meta("harvestable", true)
	root.set_meta("hp", rng.randf_range(8.0, 12.0))
	root.set_meta("drop_id", &"lingonberry")
	root.set_meta("drop_min", 2)
	root.set_meta("drop_max", 5)
	root.set_meta("harvest_type", &"bush")
	root.set_meta("tree_name", "Lingonberry Bush")
	root.set_meta("trunk_h", 0.35 * sf)  # For respawn calculations
	root.set_meta("berry_harvest", true)
	return root


static func _generate_birch_bark_texture() -> ImageTexture:
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8472

	# Base: warm white/cream with subtle vertical variation
	for y in range(size):
		for x in range(size):
			var v := rng.randf_range(0.82, 0.92)
			var warm := rng.randf_range(-0.02, 0.02)
			img.set_pixel(x, y, Color(v + warm, v - 0.01, v - 0.04))

	# Horizontal dark lenticel bands (characteristic birch marks)
	for _i in range(12):
		var by := rng.randi_range(0, size - 1)
		var bx_start := rng.randi_range(0, size / 2)
		var blen := rng.randi_range(4, 16)
		var thickness := rng.randi_range(1, 2)
		for dx in range(blen):
			var px := (bx_start + dx) % size
			for dy in range(thickness):
				var py := (by + dy) % size
				var dark := rng.randf_range(0.12, 0.28)
				img.set_pixel(px, py, Color(dark, dark * 0.9, dark * 0.7))

	# Scattered small dark spots/patches
	for _i in range(20):
		var sx := rng.randi_range(0, size - 1)
		var sy := rng.randi_range(0, size - 1)
		var dark := rng.randf_range(0.15, 0.35)
		img.set_pixel(sx, sy, Color(dark, dark * 0.85, dark * 0.7))
		if rng.randf() < 0.5 and sx + 1 < size:
			img.set_pixel(sx + 1, sy, Color(dark + 0.05, dark * 0.9, dark * 0.75))

	return ImageTexture.create_from_image(img)


static func _generate_stone_normal_map() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5591
	for y in range(size):
		for x in range(size):
			var fx := float(x) / float(size) * TAU
			var fy := float(y) / float(size) * TAU
			var n1 := sin(fx * 3.7 + fy * 2.3) * cos(fy * 4.1 - fx * 1.9)
			var n2 := sin(fx * 7.3 - fy * 5.1) * 0.5
			var n3 := cos(fx * 11.0 + fy * 9.7) * 0.3
			var bump := (n1 + n2 + n3) * 0.3 + rng.randf_range(-0.08, 0.08)
			var nx_val := clampf(0.5 + bump * 0.6, 0.0, 1.0)
			var ny_val := clampf(0.5 + bump * 0.5 + rng.randf_range(-0.04, 0.04), 0.0, 1.0)
			img.set_pixel(x, y, Color(nx_val, ny_val, 1.0))
	return ImageTexture.create_from_image(img)


# ── Per-type leaf texture generators ──────────────────────────────────────────

static func _paint_ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, brightness: float, rng: RandomNumberGenerator) -> void:
	var sz := img.get_width()
	for dy in range(-ry, ry + 1):
		for dx in range(-rx, rx + 1):
			var px := cx + dx
			var py := cy + dy
			if px < 0 or px >= sz or py < 0 or py >= sz:
				continue
			var nx := float(dx) / maxf(float(rx), 0.5)
			var ny := float(dy) / maxf(float(ry), 0.5)
			if nx * nx + ny * ny > 1.0:
				continue
			var edge := 1.0 - (nx * nx + ny * ny)
			var v := brightness * (0.75 + edge * 0.25) + rng.randf_range(-0.06, 0.06)
			v = clampf(v, 0.15, 1.0)
			img.set_pixel(px, py, Color(v, v, v, 1.0))


static func _punch_holes(img: Image, count: int, rng: RandomNumberGenerator) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for _i in count:
		var hx := rng.randi_range(3, w - 4)
		var hy := rng.randi_range(3, h - 4)
		var hr := rng.randi_range(1, 2)
		for dy in range(-hr, hr + 1):
			for dx in range(-hr, hr + 1):
				if dx * dx + dy * dy > hr * hr:
					continue
				var px := hx + dx
				var py := hy + dy
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, Color(0, 0, 0, 0))


static func _gen_leaf_tex_oak() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 70201
	for _i in 55:
		var cx := rng.randi_range(7, sz - 8)
		var cy := rng.randi_range(7, sz - 8)
		var lobes := rng.randi_range(3, 5)
		var base_r := rng.randi_range(3, 6)
		var bri := rng.randf_range(0.65, 1.0)
		_paint_ellipse(img, cx, cy, base_r, base_r + 1, bri, rng)
		for _l in lobes:
			var angle := rng.randf_range(0, TAU)
			var dist := rng.randf_range(2.0, 4.0)
			var lx := cx + roundi(cos(angle) * dist)
			var ly := cy + roundi(sin(angle) * dist)
			_paint_ellipse(img, lx, ly, rng.randi_range(2, 5), rng.randi_range(2, 5), bri * rng.randf_range(0.85, 1.0), rng)
	_punch_holes(img, 5, rng)
	return ImageTexture.create_from_image(img)


static func _gen_leaf_tex_birch() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 81432
	for _i in 80:
		var cx := rng.randi_range(4, sz - 5)
		var cy := rng.randi_range(4, sz - 5)
		var bri := rng.randf_range(0.6, 1.0)
		var rx := rng.randi_range(2, 5)
		var ry := rng.randi_range(2, 6)
		_paint_ellipse(img, cx, cy, rx, ry, bri, rng)
	_punch_holes(img, 8, rng)
	return ImageTexture.create_from_image(img)


static func _gen_leaf_tex_pine() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 93156
	for _i in 90:
		var cx := rng.randi_range(3, sz - 4)
		var cy := rng.randi_range(3, sz - 4)
		var bri := rng.randf_range(0.55, 0.95)
		var length := rng.randi_range(4, 10)
		var angle := rng.randf_range(-0.3, 0.3)
		for s in length:
			var px := cx + roundi(sin(angle) * float(s))
			var py := cy + s
			if px >= 0 and px < sz and py >= 0 and py < sz:
				img.set_pixel(px, py, Color(bri, bri, bri, 1.0))
				if px + 1 < sz:
					img.set_pixel(px + 1, py, Color(bri * 0.85, bri * 0.85, bri * 0.85, 1.0))
	_punch_holes(img, 4, rng)
	return ImageTexture.create_from_image(img)


static func _gen_leaf_tex_willow() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42871
	for _i in 70:
		var cx := rng.randi_range(4, sz - 5)
		var cy := rng.randi_range(3, sz - 8)
		var bri := rng.randf_range(0.6, 1.0)
		var length := rng.randi_range(6, 14)
		var sway := rng.randf_range(-0.15, 0.15)
		for s in length:
			var px := cx + roundi(sin(float(s) * 0.3 + sway) * 1.5)
			var py := cy + s
			if px >= 0 and px < sz and py >= 0 and py < sz:
				img.set_pixel(px, py, Color(bri, bri, bri, 1.0))
			if px - 1 >= 0 and py < sz and py >= 0:
				img.set_pixel(px - 1, py, Color(bri * 0.7, bri * 0.7, bri * 0.7, 0.7))
			if px + 1 < sz and py < sz and py >= 0:
				img.set_pixel(px + 1, py, Color(bri * 0.7, bri * 0.7, bri * 0.7, 0.7))
	_punch_holes(img, 3, rng)
	return ImageTexture.create_from_image(img)


static func _gen_leaf_tex_palm() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 58923
	for _i in 18:
		var cx := rng.randi_range(20, sz - 20)
		var cy := rng.randi_range(8, 20)
		var angle := rng.randf_range(0, TAU)
		var frond_len := rng.randi_range(14, 24)
		var bri := rng.randf_range(0.6, 1.0)
		for s in frond_len:
			var t := float(s) / float(frond_len)
			var droop := t * t * 6.0
			var px := cx + roundi(cos(angle) * float(s))
			var py := cy + roundi(sin(angle) * float(s) + droop)
			if px < 0 or px >= sz or py < 0 or py >= sz:
				continue
			var w := roundi((1.0 - t) * 3.0) + 1
			for dw in range(-w, w + 1):
				var fx := px + roundi(float(dw) * sin(angle + PI * 0.5))
				var fy := py + roundi(float(dw) * cos(angle + PI * 0.5))
				if fx >= 0 and fx < sz and fy >= 0 and fy < sz:
					img.set_pixel(fx, fy, Color(bri, bri, bri, 1.0))
	_punch_holes(img, 2, rng)
	return ImageTexture.create_from_image(img)


static func _gen_leaf_tex_generic() -> ImageTexture:
	var sz := 64
	var img := Image.create(sz, sz, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 33517
	for _i in 65:
		var cx := rng.randi_range(6, sz - 7)
		var cy := rng.randi_range(6, sz - 7)
		var rx := rng.randi_range(3, 7)
		var ry := rng.randi_range(3, 7)
		var bri := rng.randf_range(0.65, 1.0)
		_paint_ellipse(img, cx, cy, rx, ry, bri, rng)
	_punch_holes(img, 5, rng)
	return ImageTexture.create_from_image(img)


static var _cached_leaf_mats: Dictionary = {}

static func _make_tree_leaf_mat(tex: ImageTexture, base_color: Color, rng: RandomNumberGenerator) -> ShaderMaterial:
	if not _leaf_shader:
		return ShaderMaterial.new()

	var cache_key := str(tex.get_rid().get_id()) + "_" + str(base_color.to_html())
	if _cached_leaf_mats.has(cache_key):
		return _cached_leaf_mats[cache_key]

	var mat := ShaderMaterial.new()
	mat.shader = _leaf_shader
	mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("albedo_color", base_color)
	mat.set_shader_parameter("roughness", 0.85)
	mat.set_shader_parameter("alpha_cutoff", 0.3)
	mat.set_shader_parameter("wind_strength", 0.82)
	mat.set_shader_parameter("wind_speed", 1.85)
	mat.set_shader_parameter("wind_turbulence", 1.2)
	_cached_leaf_mats[cache_key] = mat
	return mat


static func _try_load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


static func _make_wind_leaf_mat(
	tex: Texture2D, color: Color,
	strength: float = 0.35,
	uv_scale: Vector3 = Vector3(3.0, 3.0, 3.0)
) -> Material:
	if _wind_shader:
		var mat := ShaderMaterial.new()
		mat.shader = _wind_shader
		if tex:
			mat.set_shader_parameter("albedo_texture", tex)
		mat.set_shader_parameter("albedo_color", color)
		mat.set_shader_parameter("roughness", 0.85)
		mat.set_shader_parameter("uv1_scale", uv_scale)
		mat.set_shader_parameter("wind_strength", strength)
		mat.set_shader_parameter("wind_speed", 1.2)
		mat.set_shader_parameter("wind_turbulence", 0.6)
		return mat
	# Fallback to standard material if shader missing
	var fb := StandardMaterial3D.new()
	if tex:
		fb.albedo_texture = tex
	else:
		fb.albedo_color = color
	fb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	fb.uv1_triplanar = true
	fb.uv1_world_triplanar = true
	fb.uv1_triplanar_sharpness = 1.0
	fb.roughness = 0.85
	fb.uv1_scale = uv_scale
	return fb


static func _make_triplanar_mat(tex: Texture2D, fallback_color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	if tex:
		mat.albedo_texture = tex
	else:
		mat.albedo_color = fallback_color
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_triplanar_sharpness = 1.0
	mat.roughness = 0.85
	return mat


# ─── Zone Population ───────────────────────────────────────────────────────────

## Populate a zone across multiple phases to spread work across frames.
## phase=0: villages + scatter trees
## phase=1: cluster trees + rocks + pebbles + stones
## phase=2: creatures + caves + horses + fish
## phase=3: ground grass (MultiMesh + billboard shader, distance-culled)
## phase=4-5: wildflowers (5 types per phase)
## phase=6: blueberry bushes + water plants
## Returns true when ALL phases are done.
static func populate_zone_phase(
	zone_root: Node3D,
	coord: Vector2i,
	biome: StringName,
	world_seed_hash: int,
	height_func: Callable,
	microbiome: StringName,
	phase: int,
) -> bool:
	_ensure_textures()
	_ensure_height_grid(coord, height_func)

	var base_seed: int = world_seed_hash + coord.x * 73856093 + coord.y * 19349663
	var rng := RandomNumberGenerator.new()
	rng.seed = base_seed + phase * 999331

	var origin_x: float = coord.x * ZONE_SIZE
	var origin_z: float = coord.y * ZONE_SIZE

	var counts := _get_microbiome_counts(biome, microbiome)
	var tree_n := counts[0]
	var rock_n := counts[1]
	var bush_n := counts[2]
	var enemy_n := counts[3]

	if phase == 0:
		# ── Phase 0: villages + scatter trees + NPC camps ──
		if not debug_skip_villages:
			if biome == &"hearthlands":
				_VillageGenerator.try_spawn_village(zone_root, coord, rng, origin_x, origin_z, height_func)
			if coord == Vector2i(0, 0):
				_VillageGenerator.force_spawn_village(zone_root, 20.0, 20.0, height_func)
				_spawn_village_signpost(zone_root, 20.0, 20.0, origin_x, origin_z, height_func)

		_try_spawn_merchant_camp(zone_root, coord, origin_x, origin_z, height_func)
		_try_spawn_signposts(zone_root, coord, origin_x, origin_z, height_func)

		var structs := _get_structures_cached()
		var scatter_n := int(tree_n * 0.4)

		var _placed_trees: Array[Vector2] = []
		var _min_tree_dist := 3.5

		if not debug_skip_trees:
			for i in scatter_n:
				var lx := rng.randf_range(4.0, ZONE_SIZE - 4.0)
				var lz := rng.randf_range(4.0, ZONE_SIZE - 4.0)
				var wx := origin_x + lx
				var wz := origin_z + lz
				var sn := _hg_snap_and_normal(wx, wz)
				var ground_y := sn.x
				if ground_y < _MIN_LAND_Y:
					continue
				if ground_y > _TREE_LINE_END:
					continue
				if ground_y > _TREE_LINE_START:
					var tree_line_chance := 1.0 - (ground_y - _TREE_LINE_START) / (_TREE_LINE_END - _TREE_LINE_START)
					if rng.randf() > tree_line_chance:
						continue
				if sn.y < 0.82:
					continue
				if _hg_is_steep_edge(wx, wz, ground_y):
					continue
				if is_dirt_patch(wx, wz):
					continue
				if _is_near_structure(wx, wz, 4.0, structs):
					continue
				var too_close := false
				for pt in _placed_trees:
					if Vector2(lx, lz).distance_to(pt) < _min_tree_dist:
						too_close = true
						break
				if too_close:
					continue
				var obj := _create_tree(biome, rng, microbiome)
				zone_root.add_child(obj)
				obj.position = Vector3(lx, ground_y - 1.5, lz)
				_placed_trees.append(Vector2(lx, lz))

		return false

	if phase == 1:
		# ── Phase 1: cluster trees + rocks + stones ──
		var structs := _get_structures_cached()
		var cluster_budget := tree_n - int(tree_n * 0.4)

		var _cluster_placed: Array[Vector2] = []
		var _min_cluster_dist := 3.0

		if not debug_skip_trees:
			var cluster_count := rng.randi_range(1, 3)
			var trees_per_cluster: int = maxi(1, cluster_budget / cluster_count)
			for _ci in cluster_count:
				var cx := rng.randf_range(8.0, ZONE_SIZE - 8.0)
				var cz := rng.randf_range(8.0, ZONE_SIZE - 8.0)
				var cwx := origin_x + cx
				var cwz := origin_z + cz
				var forest_n := _fbm2(cwx * 0.012 + 300.0, cwz * 0.012 + 400.0)
				if forest_n < 0.28:
					continue
				var cluster_radius := rng.randf_range(8.0, 16.0)
				for _ti in trees_per_cluster:
					var angle := rng.randf_range(0.0, TAU)
					var dist := rng.randf_range(0.0, cluster_radius) * sqrt(rng.randf())
					var lx := clampf(cx + cos(angle) * dist, 4.0, ZONE_SIZE - 4.0)
					var lz := clampf(cz + sin(angle) * dist, 4.0, ZONE_SIZE - 4.0)
					var wx := origin_x + lx
					var wz := origin_z + lz
					var sn := _hg_snap_and_normal(wx, wz)
					var ground_y := sn.x
					if ground_y < _MIN_LAND_Y:
						continue
					if ground_y > _TREE_LINE_END:
						continue
					if ground_y > _TREE_LINE_START:
						var tree_line_chance := 1.0 - (ground_y - _TREE_LINE_START) / (_TREE_LINE_END - _TREE_LINE_START)
						if rng.randf() > tree_line_chance:
							continue
					if sn.y < 0.82:
						continue
					if _hg_is_steep_edge(wx, wz, ground_y):
						continue
					if is_dirt_patch(wx, wz):
						continue
					if _is_near_structure(wx, wz, 4.0, structs):
						continue
					var too_close := false
					for pt in _cluster_placed:
						if Vector2(lx, lz).distance_to(pt) < _min_cluster_dist:
							too_close = true
							break
					if too_close:
						continue
					var obj := _create_tree(biome, rng, microbiome)
					zone_root.add_child(obj)
					obj.position = Vector3(lx, ground_y - 1.5, lz)
					_cluster_placed.append(Vector2(lx, lz))

		if not debug_skip_rocks:
			for i in rock_n:
				var lx := rng.randf_range(2.0, ZONE_SIZE - 2.0)
				var lz := rng.randf_range(2.0, ZONE_SIZE - 2.0)
				var wx := origin_x + lx
				var wz := origin_z + lz
				var ground_y := _hg_snap_height(wx, wz)
				if ground_y < _MIN_LAND_Y:
					continue
				if _is_near_structure(wx, wz, 4.0, structs):
					continue
				if _hg_is_steep_edge(wx, wz, ground_y):
					continue
				var obj := _create_rock(rng)
				zone_root.add_child(obj)
				obj.position = Vector3(lx, ground_y, lz)

			var pebble_n := rng.randi_range(rock_n * 2, rock_n * 4)
			for i in pebble_n:
				var lx := rng.randf_range(1.0, ZONE_SIZE - 1.0)
				var lz := rng.randf_range(1.0, ZONE_SIZE - 1.0)
				var wx := origin_x + lx
				var wz := origin_z + lz
				var ground_y := _hg_snap_height(wx, wz)
				if ground_y < _MIN_LAND_Y:
					continue
				if _hg_is_steep_edge(wx, wz, ground_y):
					continue
				var peb := _create_pebble(rng)
				zone_root.add_child(peb)
				peb.position = Vector3(lx, ground_y + 0.05, lz)

		if not debug_skip_stones:
			var stone_n: int = rng.randi_range(1, 3)
			for i in stone_n:
				var lx := rng.randf_range(2.0, ZONE_SIZE - 2.0)
				var lz := rng.randf_range(2.0, ZONE_SIZE - 2.0)
				var wx := origin_x + lx
				var wz := origin_z + lz
				var ground_y := _hg_snap_height(wx, wz)
				if ground_y < _MIN_LAND_Y:
					continue
				if _is_near_structure(wx, wz, 4.0, structs):
					continue
				if _hg_is_steep_edge(wx, wz, ground_y):
					continue
				var stone := _create_ground_stone(rng)
				zone_root.add_child(stone)
				stone.position = Vector3(lx, ground_y + 0.1, lz)

		if not debug_skip_rocks:
			_scatter_creek_rocks(zone_root, coord, rng, height_func)

		return false

	if phase == 2:
		# ── Phase 2: creatures + caves + horses + fish ──
		if not debug_skip_creatures:
			var actual_enemy_n := maxi(1, int(enemy_n * 0.3))
			var creature_idx := 0
			for i in actual_enemy_n:
				var lx := rng.randf_range(8.0, ZONE_SIZE - 8.0)
				var lz := rng.randf_range(8.0, ZONE_SIZE - 8.0)
				var wx := origin_x + lx
				var wz := origin_z + lz
				var ground_y := _hg_snap_height(wx, wz)
				if ground_y < _MIN_LAND_Y:
					continue
				if ground_y > 5.0:
					var skip_chance := smoothstep(5.0, 12.0, ground_y)
					if rng.randf() < skip_chance:
						continue
				var enemy := _create_enemy(biome, rng)
				if not enemy:
					continue
				enemy.name = "Creature_%d" % creature_idx
				creature_idx += 1
				zone_root.add_child(enemy)
				var spawn_y := ground_y + 0.1
				if enemy.get("is_flying"):
					spawn_y = ground_y + enemy.get("fly_height")
				enemy.position = Vector3(lx, spawn_y, lz)

		if biome == &"hearthlands":
			_try_spawn_cave(zone_root, coord, rng, origin_x, origin_z, height_func)

		_try_spawn_goblin_camp(zone_root, coord, rng, origin_x, origin_z, height_func)

		if not debug_skip_horses:
			var _has_saved_horses := not _get_saved_horses().is_empty()
			if biome == &"hearthlands":
				if rng.randf() < 0.15:
					var lx := rng.randf_range(10.0, ZONE_SIZE - 10.0)
					var lz := rng.randf_range(10.0, ZONE_SIZE - 10.0)
					var wx := origin_x + lx
					var wz := origin_z + lz
					var ground_y := _hg_snap_height(wx, wz)
					if ground_y > _MIN_LAND_Y:
						if _has_saved_horses:
							rng.randf()
						else:
							var horse := _create_horse(rng)
							zone_root.add_child(horse)
							horse.position = Vector3(lx, ground_y, lz)
							horse.set_meta("spawn_zone", coord)

			_restore_saved_horses_in_zone(zone_root, coord, height_func)

		if not debug_skip_fish:
			if biome == &"hearthlands":
				var fish_count := rng.randi_range(0, 3)
				for _fi in fish_count:
					var lx := rng.randf_range(4.0, ZONE_SIZE - 4.0)
					var lz := rng.randf_range(4.0, ZONE_SIZE - 4.0)
					var wx := origin_x + lx
					var wz := origin_z + lz
					var mesh_h := _hg_snap_height(wx, wz)
					if mesh_h < -0.5:
						var fish := _create_fish(rng)
						zone_root.add_child(fish)
						fish.position = Vector3(lx, -0.1, lz)

		return false

	# ── Phase 3: ground grass (MultiMesh, shader-culled for performance) ──
	if phase == 3:
		if not debug_skip_grass:
			_scatter_grass(zone_root, coord, biome, rng, height_func)
		return false

	# ── Phases 4–5: wildflowers (5 types per frame) ──
	if phase >= 4 and phase <= 5:
		if not debug_skip_flowers:
			var fi_start := (phase - 4) * 5
			_scatter_flowers(zone_root, coord, biome, rng, height_func, fi_start, fi_start + 5)
		return false

	# ── Phase 6: blueberry bushes + water plants + creek vegetation ──
	if not debug_skip_saplings:
		_scatter_blueberry_bushes(zone_root, coord, biome, rng, height_func, origin_x, origin_z)

	_scatter_water_plants(zone_root, coord, biome, rng, height_func)
	_scatter_creek_vegetation(zone_root, coord, rng, height_func)

	return true


# ═══════════════════════════════════════════════════════════════════════════════
#  MERCHANT & SIGNPOST SPAWNING
# ═══════════════════════════════════════════════════════════════════════════════

static var _merchant_spawned := false
static var _signposts_spawned: Dictionary = {}

static func _try_spawn_merchant_camp(
	zone_root: Node3D,
	coord: Vector2i,
	origin_x: float,
	origin_z: float,
	height_func: Callable,
) -> void:
	if _merchant_spawned:
		return
	var wg := _get_world_generator()
	if not wg or not wg.has_method("get_merchant_world_pos"):
		return
	var merchant_pos: Vector3 = wg.get_merchant_world_pos()
	if merchant_pos == Vector3.ZERO:
		return
	var zone_end_x := origin_x + ZONE_SIZE
	var zone_end_z := origin_z + ZONE_SIZE
	if merchant_pos.x < origin_x or merchant_pos.x >= zone_end_x:
		return
	if merchant_pos.z < origin_z or merchant_pos.z >= zone_end_z:
		return
	_merchant_spawned = true
	var camp := _MerchantNPC.create_camp(merchant_pos, height_func)
	var lx := merchant_pos.x - origin_x
	var lz := merchant_pos.z - origin_z
	var ground_y: float = height_func.call(merchant_pos.x, merchant_pos.z)
	camp.position = Vector3(lx, ground_y, lz)
	zone_root.add_child(camp)
	if _DEBUG_LOG:
		print("[ZONE] Spawned merchant camp at world (%.0f, %.0f)" % [merchant_pos.x, merchant_pos.z])


static func _try_spawn_signposts(
	zone_root: Node3D,
	coord: Vector2i,
	origin_x: float,
	origin_z: float,
	height_func: Callable,
) -> void:
	var wg := _get_world_generator()
	if not wg or not wg.has_method("get_signpost_positions"):
		return
	var positions: Array = wg.get_signpost_positions()
	var merchant_pos: Vector3 = wg.get_merchant_world_pos()
	var zone_end_x := origin_x + ZONE_SIZE
	var zone_end_z := origin_z + ZONE_SIZE

	var sign_texts := [
		"Trader Halvard -- camps nearby",
		"Halvard's Trading Post -- follow the smoke",
		"Supplies ahead. Almost there.",
	]

	for i in positions.size():
		var sp: Vector3 = positions[i]
		if _signposts_spawned.has(i):
			continue
		if sp.x < origin_x or sp.x >= zone_end_x:
			continue
		if sp.z < origin_z or sp.z >= zone_end_z:
			continue
		_signposts_spawned[i] = true
		var text: String = sign_texts[i] if i < sign_texts.size() else "This way..."
		var signpost := _create_signpost(sp, text, merchant_pos, height_func)
		var lx := sp.x - origin_x
		var lz := sp.z - origin_z
		var ground_y: float = height_func.call(sp.x, sp.z)
		signpost.position = Vector3(lx, ground_y, lz)
		zone_root.add_child(signpost)
		if _DEBUG_LOG:
			print("[ZONE] Spawned signpost #%d at world (%.0f, %.0f)" % [i, sp.x, sp.z])


static func _create_signpost(world_pos: Vector3, text: String, merchant_pos: Vector3, height_func: Callable) -> StaticBody3D:
	var post := StaticBody3D.new()
	post.name = "Signpost"
	post.collision_layer = 4
	post.collision_mask = 0
	post.add_to_group(&"interactables")
	post.add_to_group(&"signposts")
	post.set_meta("sign_text", text)
	post.set_meta("reveals_merchant", true)
	post.set_meta("merchant_pos", merchant_pos)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 1.6, 0.3)
	col.shape = shape
	col.position = Vector3(0, 0.8, 0)
	post.add_child(col)

	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.4, 0.28, 0.14)
	post_mat.roughness = 0.9

	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.height = 1.8
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.08
	pole.mesh = pole_mesh
	pole.material_override = post_mat
	pole.position = Vector3(0, 0.9, 0)
	post.add_child(pole)

	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(0.8, 0.35, 0.04)
	board.mesh = board_mesh
	board.material_override = post_mat
	board.position = Vector3(0, 1.5, 0.06)
	post.add_child(board)

	var label := Label3D.new()
	label.text = text
	label.font_size = 24
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = false
	label.modulate = Color(0.9, 0.8, 0.5)
	label.outline_modulate = Color(0, 0, 0, 0.8)
	label.outline_size = 4
	label.position = Vector3(0, 1.5, 0.1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	post.add_child(label)

	var dir_to_merchant := Vector2(merchant_pos.x - world_pos.x, merchant_pos.z - world_pos.z).normalized()
	post.rotation.y = atan2(-dir_to_merchant.x, -dir_to_merchant.y)

	return post


static func _spawn_village_signpost(
	zone_root: Node3D,
	village_wx: float,
	village_wz: float,
	origin_x: float,
	origin_z: float,
	height_func: Callable,
) -> void:
	var wg := _get_world_generator()
	if not wg:
		return
	var merchant_pos: Vector3 = wg.get_merchant_world_pos()
	if merchant_pos == Vector3.ZERO:
		return
	var dir_to_merchant := Vector2(merchant_pos.x - village_wx, merchant_pos.z - village_wz).normalized()
	var sign_wx := village_wx + dir_to_merchant.x * 12.0
	var sign_wz := village_wz + dir_to_merchant.y * 12.0
	var sign_y: float = height_func.call(sign_wx, sign_wz)
	var signpost := _create_signpost(
		Vector3(sign_wx, sign_y, sign_wz),
		"Trader Halvard -- follow this path",
		merchant_pos,
		height_func,
	)
	signpost.position = Vector3(sign_wx - origin_x, sign_y, sign_wz - origin_z)
	zone_root.add_child(signpost)


## Legacy single-call populate for spawn area (runs synchronously)
static func populate_zone(
	zone_root: Node3D,
	coord: Vector2i,
	biome: StringName,
	world_seed_hash: int,
	height_func: Callable,
	microbiome: StringName = &"none",
) -> void:
	for p in 7:  # 0-6: villages/trees, clusters/rocks, creatures, (unused), flowers(x2), bushes
		populate_zone_phase(zone_root, coord, biome, world_seed_hash, height_func, microbiome, p)


# Two intersecting planes (cross) so billboard vegetation is never edge-on to camera
static func _create_billboard_cross(w: float, h: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var half_w := w * 0.5
	for plane_i in 2:
		var angle := plane_i * PI * 0.5
		var dx := cos(angle) * half_w
		var dz := sin(angle) * half_w
		var bi := verts.size()
		verts.append(Vector3(-dx, 0.0, -dz))
		verts.append(Vector3(dx, 0.0, dz))
		verts.append(Vector3(dx, h, dz))
		verts.append(Vector3(-dx, h, -dz))
		uvs.append(Vector2(0, 1)); uvs.append(Vector2(1, 1))
		uvs.append(Vector2(1, 0)); uvs.append(Vector2(0, 0))
		for _n in 4:
			normals.append(Vector3(0, 1, 0))
		indices.append(bi); indices.append(bi + 1); indices.append(bi + 2)
		indices.append(bi); indices.append(bi + 2); indices.append(bi + 3)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# ── Procedural wildflower texture generators ─────────────────────────────────
# Each flower: thin green stem(s) + colored head. Grayscale image tinted by
# the albedo_color in the shader material, so "color" is encoded as brightness
# with actual hue coming from the material tint.

static func _paint_stem(img: Image, cx: int, base_y: int, stem_h: int, bri: float, rng: RandomNumberGenerator) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var curve := rng.randf_range(-0.03, 0.03)
	for dy in stem_h:
		var y := base_y - dy
		if y < 0 or y >= h:
			continue
		var t := float(dy) / float(stem_h)
		var v := clampf(lerpf(bri * 0.7, bri, t) + rng.randf_range(-0.03, 0.03), 0.15, 0.9)
		var ox := int(curve * dy * dy * 0.01)
		var px := cx + ox
		if px >= 0 and px < w:
			img.set_pixel(px, y, Color(v, v, v, 1.0))


static func _paint_flower_head(img: Image, cx: int, cy: int, shape: int,
		size: int, bri: float, rng: RandomNumberGenerator) -> void:
	var w := img.get_width()
	var h := img.get_height()
	match shape:
		0:  # Round dot cluster (buttercup, dandelion, clover)
			var r := maxi(size, 2)
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx * dx + dy * dy > r * r:
						continue
					var px := cx + dx
					var py := cy + dy
					if px < 0 or px >= w or py < 0 or py >= h:
						continue
					var edge := 1.0 - float(dx * dx + dy * dy) / float(r * r)
					var v := clampf(bri * (0.75 + edge * 0.25) + rng.randf_range(-0.04, 0.04), 0.2, 1.0)
					img.set_pixel(px, py, Color(v, v, v, 1.0))
		1:  # Star / daisy petals
			var petals := rng.randi_range(4, 6)
			var petal_len := maxi(size, 2)
			for p in petals:
				var angle := float(p) / float(petals) * TAU + rng.randf_range(-0.2, 0.2)
				for d in petal_len:
					var t := float(d) / float(petal_len)
					var px := cx + int(cos(angle) * d)
					var py := cy + int(sin(angle) * d)
					if px < 0 or px >= w or py < 0 or py >= h:
						continue
					var v := clampf(bri * (1.0 - t * 0.3), 0.2, 1.0)
					img.set_pixel(px, py, Color(v, v, v, 1.0))
					if d < petal_len - 1:
						for off in [-1, 1]:
							var ppx := px + int(sin(angle) * off)
							var ppy := py + int(cos(angle) * off)
							if ppx >= 0 and ppx < w and ppy >= 0 and ppy < h:
								img.set_pixel(ppx, ppy, Color(v * 0.9, v * 0.9, v * 0.9, 1.0))
			# Center dot
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var px := cx + dx
					var py := cy + dy
					if px >= 0 and px < w and py >= 0 and py < h:
						img.set_pixel(px, py, Color(bri * 1.1, bri * 1.1, bri * 1.1, 1.0))
		2:  # Vertical spike (lavender, loosestrife-like)
			var spike_h := maxi(size * 2, 4)
			var spike_w := maxi(size / 2, 1)
			for dy in spike_h:
				var y := cy - dy
				if y < 0 or y >= h:
					continue
				var t := float(dy) / float(spike_h)
				var bw := maxi(1, int(float(spike_w) * (1.0 - t * 0.6)))
				var v := clampf(bri * (0.8 + t * 0.2) + rng.randf_range(-0.05, 0.05), 0.2, 1.0)
				for dx in range(-bw, bw + 1):
					if rng.randf() < 0.3:
						continue
					var px := cx + dx
					if px >= 0 and px < w:
						img.set_pixel(px, y, Color(v, v, v, 1.0))
		3:  # Bell / drooping (bluebell)
			var bell_h := maxi(size, 2)
			var bell_w := maxi(size, 2)
			for dy in bell_h:
				var y := cy + dy
				if y < 0 or y >= h:
					continue
				var t := float(dy) / float(bell_h)
				var bw := int(float(bell_w) * sin(t * PI * 0.8 + 0.3))
				var v := clampf(bri * (1.0 - t * 0.2), 0.2, 1.0)
				for dx in range(-bw, bw + 1):
					var px := cx + dx
					if px >= 0 and px < w:
						img.set_pixel(px, y, Color(v, v, v, 1.0))


# Flower configs: [shape, head_size, stem_count, stem_h_min, stem_h_max, head_bri, stem_bri]
static var _flower_configs: Array = [
	# 0: Cornflower (blue) — star petals
	[1, 4, 3, 14, 22, 0.85, 0.5],
	# 1: Red Poppy — round dot
	[0, 4, 2, 16, 24, 0.9, 0.45],
	# 2: Buttercup (yellow) — small round
	[0, 2, 4, 10, 18, 0.95, 0.5],
	# 3: Lavender (purple) — vertical spike
	[2, 3, 3, 12, 20, 0.8, 0.45],
	# 4: White Daisy — star petals
	[1, 5, 2, 16, 24, 0.95, 0.5],
	# 5: Wild Violet — small round
	[0, 3, 3, 10, 16, 0.85, 0.5],
	# 6: Clover (pink) — round dot
	[0, 3, 3, 12, 18, 0.9, 0.5],
	# 7: Dandelion (yellow) — round dot
	[0, 4, 2, 14, 22, 0.95, 0.5],
	# 8: Chamomile (white-green) — small star
	[1, 3, 4, 10, 16, 0.8, 0.55],
	# 9: Bluebell — drooping bell
	[3, 3, 2, 16, 24, 0.85, 0.5],
]


static func _gen_flower_texture(idx: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 60000 + idx * 311
	var cfg: Array = _flower_configs[idx]
	var shape: int = cfg[0]
	var head_size: int = cfg[1]
	var stem_count: int = cfg[2]
	var stem_h_min: int = cfg[3]
	var stem_h_max: int = cfg[4]
	var head_bri: float = cfg[5]
	var stem_bri: float = cfg[6]

	var sz_w := 32
	var sz_h := 40
	var img := Image.create(sz_w, sz_h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	for _s in stem_count:
		var cx := rng.randi_range(8, sz_w - 9)
		var stem_h := rng.randi_range(stem_h_min, stem_h_max)
		_paint_stem(img, cx, sz_h - 1, stem_h, stem_bri, rng)
		var flower_y := sz_h - 1 - stem_h
		_paint_flower_head(img, cx, flower_y, shape, head_size + rng.randi_range(-1, 1), head_bri, rng)

	return ImageTexture.create_from_image(img)


static var _flower_types_table: Array = []


static func _get_flower_types() -> Array:
	if _flower_types_table.is_empty():
		# [texture, color, count, scale_min, scale_max, quad_w, quad_h]
		_flower_types_table = [
			# 0: Cornflower — blue
			[_flower_textures[0], Color(0.30, 0.40, 0.88), 10, 0.6, 1.1, 0.9, 1.1],
			# 1: Red Poppy — red-orange
			[_flower_textures[1], Color(0.90, 0.22, 0.15), 8, 0.6, 1.0, 0.8, 1.0],
			# 2: Buttercup — bright yellow
			[_flower_textures[2], Color(0.95, 0.85, 0.15), 14, 0.5, 0.9, 0.7, 0.8],
			# 3: Lavender — purple
			[_flower_textures[3], Color(0.60, 0.40, 0.80), 11, 0.6, 1.0, 0.8, 1.2],
			# 4: White Daisy — white
			[_flower_textures[4], Color(0.95, 0.95, 0.90), 9, 0.6, 1.1, 0.9, 1.0],
			# 5: Wild Violet — deep purple-blue
			[_flower_textures[5], Color(0.50, 0.30, 0.75), 11, 0.5, 0.9, 0.7, 0.9],
			# 6: Clover — pink/rose
			[_flower_textures[6], Color(0.85, 0.45, 0.55), 12, 0.5, 0.9, 0.7, 0.9],
			# 7: Dandelion — bright yellow
			[_flower_textures[7], Color(0.95, 0.80, 0.10), 10, 0.6, 1.0, 0.8, 1.0],
			# 8: Chamomile — soft white-green
			[_flower_textures[8], Color(0.80, 0.85, 0.70), 13, 0.5, 0.9, 0.7, 0.8],
			# 9: Bluebell — soft blue
			[_flower_textures[9], Color(0.45, 0.55, 0.85), 10, 0.6, 1.0, 0.8, 1.1],
		]
	return _flower_types_table


static var _cached_flower_mats: Dictionary = {}


static func _make_flower_mat(tex: ImageTexture, color: Color) -> ShaderMaterial:
	var cache_key := str(tex.get_rid().get_id()) + "_f_" + color.to_html()
	if _cached_flower_mats.has(cache_key):
		return _cached_flower_mats[cache_key]
	var mat := ShaderMaterial.new()
	mat.shader = _billboard_shader
	mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("albedo_color", color)
	mat.set_shader_parameter("alpha_cutoff", 0.35)
	mat.set_shader_parameter("wind_strength", 0.35)
	mat.set_shader_parameter("wind_speed", 1.2)
	mat.set_shader_parameter("wind_turbulence", 0.5)
	_cached_flower_mats[cache_key] = mat
	return mat


static func _scatter_flowers(
	zone_root: Node3D,
	coord: Vector2i,
	biome: StringName,
	rng: RandomNumberGenerator,
	height_func: Callable,
	type_start: int = 0,
	type_end: int = -1,
) -> void:
	if not _billboard_shader or not _billboard_quad_mesh:
		return
	if biome != &"hearthlands":
		return

	_ensure_height_grid(coord, height_func)

	var flower_types := _get_flower_types()
	if type_end < 0:
		type_end = flower_types.size()

	var origin_x: float = coord.x * ZONE_SIZE
	var origin_z: float = coord.y * ZONE_SIZE

	_ensure_rejection_grid(coord, origin_x, origin_z)

	for fi in range(type_start, type_end):
		var cfg: Array = flower_types[fi]
		var tex: ImageTexture = cfg[0]
		var color: Color = cfg[1]
		var count: int = cfg[2]
		var scale_min: float = cfg[3]
		var scale_max: float = cfg[4]
		var quad_w: float = cfg[5]
		var quad_h: float = cfg[6]

		if not tex:
			continue

		var mat := _make_flower_mat(tex, Color(color, 1.0))

		var water_only := fi == 3 or fi == 5
		var transforms: Array[Transform3D] = []

		const FLOWER_CELL := 3.0
		var fc_x0 := int(floor(origin_x / FLOWER_CELL))
		var fc_z0 := int(floor(origin_z / FLOWER_CELL))
		var fc_x1 := int(ceil((origin_x + ZONE_SIZE) / FLOWER_CELL))
		var fc_z1 := int(ceil((origin_z + ZONE_SIZE) / FLOWER_CELL))
		var fc_total := (fc_x1 - fc_x0) * (fc_z1 - fc_z0)
		var accept_thresh := float(count) / float(fc_total) * 2.5
		var salt_base := 100 + fi * 10

		for gcz in range(fc_z0, fc_z1):
			for gcx in range(fc_x0, fc_x1):
				var h0 := _grass_cell_hash(gcx, gcz, salt_base)
				if h0 > accept_thresh:
					continue
				var h1 := _grass_cell_hash(gcx, gcz, salt_base + 1)
				var h2 := _grass_cell_hash(gcx, gcz, salt_base + 2)
				var h3 := _grass_cell_hash(gcx, gcz, salt_base + 3)
				var h4 := _grass_cell_hash(gcx, gcz, salt_base + 4)

				var wx := (float(gcx) + 0.05 + h1 * 0.9) * FLOWER_CELL
				var wz := (float(gcz) + 0.05 + h2 * 0.9) * FLOWER_CELL
				var lx := wx - origin_x
				var lz := wz - origin_z

				if lx < 0.0 or lx >= ZONE_SIZE or lz < 0.0 or lz >= ZONE_SIZE:
					continue

				var rgx := clampi(int(lx / _RG_CELL), 0, _RG_RES - 1)
				var rgz := clampi(int(lz / _RG_CELL), 0, _RG_RES - 1)
				if _rg_data[rgz * _RG_RES + rgx] & (_RG_DENSITY_LOW | _RG_PATH | _RG_STRUCTURE) != 0:
					continue

				var density := _vegetation_density_noise(wx, wz)
				if density < 0.22:
					continue

				var sn := _hg_snap_and_normal(wx, wz)
				var ground_y := sn.x
				if ground_y < _MIN_LAND_Y or ground_y > 22.0:
					continue
				if sn.y < 0.95:
					continue
				var _fhc := sn.x
				if absf(_fhc - _hg_sample(wx + 2.0, wz)) > 1.5 \
						or absf(_fhc - _hg_sample(wx - 2.0, wz)) > 1.5 \
						or absf(_fhc - _hg_sample(wx, wz + 2.0)) > 1.5 \
						or absf(_fhc - _hg_sample(wx, wz - 2.0)) > 1.5:
					continue
				if water_only:
					if ground_y > _WATER_LEVEL + 3.0:
						continue
					var near_water := false
					for probe_r in [2.0, 4.0, 6.0]:
						for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
								Vector2(0.707, 0.707), Vector2(-0.707, 0.707),
								Vector2(0.707, -0.707), Vector2(-0.707, -0.707)]:
							if _hg_sample(wx + d.x * probe_r, wz + d.y * probe_r) < _WATER_LEVEL + 0.1:
								near_water = true
								break
						if near_water:
							break
					if not near_water:
						continue

				var scale_val := scale_min + h3 * (scale_max - scale_min)
				var rot := h4 * TAU
				var sx := quad_w * scale_val
				var sy := quad_h * scale_val
				var sz := quad_w * scale_val
				var basis := Basis(Vector3.UP, rot).scaled(Vector3(sx, sy, sz))
				transforms.append(Transform3D(basis, Vector3(lx, ground_y, lz)))

		if transforms.is_empty():
			continue

		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.mesh = _billboard_quad_mesh
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false
		mm.instance_count = transforms.size()
		mmi.multimesh = mm
		for tidx in transforms.size():
			mm.set_instance_transform(tidx, transforms[tidx])

		mmi.name = "Flower_%d" % fi
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 120.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		zone_root.add_child(mmi)


static func _grass_cell_hash(cx: int, cz: int, salt: int) -> float:
	var n: int = (cx + 7919) * 374761393 + (cz + 7207) * 668265263 + (salt + 3571) * 1274126177
	n = (n >> 13) ^ n
	n = n % 1000000007
	if n < 0:
		n += 1000000007
	return float(n) / 1000000007.0


static func _scatter_grass(
	zone_root: Node3D,
	coord: Vector2i,
	biome: StringName,
	rng: RandomNumberGenerator,
	height_func: Callable,
) -> void:
	if not _grass_mat or not _billboard_quad_mesh:
		return
	if biome != &"hearthlands":
		return

	_ensure_height_grid(coord, height_func)

	var origin_x: float = coord.x * ZONE_SIZE
	var origin_z: float = coord.y * ZONE_SIZE

	_ensure_rejection_grid(coord, origin_x, origin_z)

	var transforms: Array[Transform3D] = []
	const _RG_GRASS_REJECT := _RG_WATER | _RG_STRUCTURE

	const GRASS_CELL := 0.325
	var cell_x0 := int(floor(origin_x / GRASS_CELL))
	var cell_z0 := int(floor(origin_z / GRASS_CELL))
	var cell_x1 := int(ceil((origin_x + ZONE_SIZE) / GRASS_CELL))
	var cell_z1 := int(ceil((origin_z + ZONE_SIZE) / GRASS_CELL))

	for gcz in range(cell_z0, cell_z1):
		for gcx in range(cell_x0, cell_x1):
			var h1 := _grass_cell_hash(gcx, gcz, 0)
			var h2 := _grass_cell_hash(gcx, gcz, 1)
			var h3 := _grass_cell_hash(gcx, gcz, 2)
			var h4 := _grass_cell_hash(gcx, gcz, 3)

			var wx := (float(gcx) + 0.05 + h1 * 0.9) * GRASS_CELL
			var wz := (float(gcz) + 0.05 + h2 * 0.9) * GRASS_CELL
			var lx := wx - origin_x
			var lz := wz - origin_z

			if lx < 0.0 or lx >= ZONE_SIZE or lz < 0.0 or lz >= ZONE_SIZE:
				continue

			var rgx := clampi(int(lx / _RG_CELL), 0, _RG_RES - 1)
			var rgz := clampi(int(lz / _RG_CELL), 0, _RG_RES - 1)
			if _rg_data[rgz * _RG_RES + rgx] & _RG_GRASS_REJECT != 0:
				continue

			var h5 := _grass_cell_hash(gcx, gcz, 4)
			var d1 := sin(wx * 0.08 + wz * 0.06 + 31.7) * 0.5 + 0.5
			var d2 := sin(wx * 0.05 - wz * 0.09 + 74.3) * 0.5 + 0.5
			var d3 := sin(wx * 0.13 + wz * 0.03 - 15.9) * 0.5 + 0.5
			var density := (d1 + d2 + d3) / 3.0
			var keep := lerpf(0.50, 1.0, density)
			if h5 > keep:
				continue

			var sn := _hg_snap_and_normal(wx, wz)
			var ground_y := sn.x
			if ground_y < _MIN_LAND_Y or ground_y > 120.0:
				continue
			if sn.y < 0.85:
				continue
			if _hg_is_steep_edge(wx, wz, ground_y):
				continue

			var scale_val := 0.4 + h3 * 0.45
			var rot := h4 * TAU
			var sx := 2.4 * scale_val
			var sy := 2.8 * scale_val
			var sz := 2.4 * scale_val
			var basis := Basis(Vector3.UP, rot).scaled(Vector3(sx, sy, sz))
			transforms.append(Transform3D(basis, Vector3(lx, ground_y - 0.04, lz)))

	if transforms.is_empty():
		return

	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.mesh = _billboard_quad_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.instance_count = transforms.size()
	mmi.multimesh = mm
	for tidx in transforms.size():
		mm.set_instance_transform(tidx, transforms[tidx])

	mmi.name = "GrassClump"
	mmi.material_override = _grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 288.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	zone_root.add_child(mmi)


static func _is_near_structure(wx: float, wz: float, min_dist_sq: float = 4.0, cached_structures: Array = []) -> bool:
	var structs: Array = cached_structures
	if structs.is_empty():
		structs = _get_structures_cached()
	for i in structs.size():
		var s = structs[i]
		if not is_instance_valid(s):
			continue
		var sp: Vector3 = (s as Node3D).global_position
		var dx := (sp.x + origin_shift.x) - wx
		var dz := (sp.z + origin_shift.z) - wz
		var dist_sq := dx * dx + dz * dz
		var r_sq := min_dist_sq
		if (s as Node3D).has_meta("footprint_radius"):
			var r: float = float((s as Node3D).get_meta("footprint_radius"))
			r_sq = maxf(r_sq, r * r)
		else:
			for child in (s as Node3D).get_children():
				if not is_instance_valid(child):
					continue
				if child is CollisionShape3D and child.shape is BoxShape3D:
					var sz: Vector3 = (child.shape as BoxShape3D).size
					var half := maxf(sz.x, sz.z) * 0.5 + 1.5
					r_sq = maxf(r_sq, half * half)
					break
		if dist_sq < r_sq:
			return true
	return false


static func _is_near_bush(wx: float, wz: float, min_dist: float, cached_bushes: Array = []) -> bool:
	var bushes: Array = cached_bushes
	if bushes.is_empty():
		bushes = _get_berry_bushes_cached()
	var r_sq := min_dist * min_dist
	for i in bushes.size():
		var b = bushes[i]
		if not is_instance_valid(b):
			continue
		var bp: Vector3 = (b as Node3D).global_position
		var dx := (bp.x + origin_shift.x) - wx
		var dz := (bp.z + origin_shift.z) - wz
		if dx * dx + dz * dz < r_sq:
			return true
	return false


## Vegetation density noise - used for flowers and rejection grid
static func _vegetation_density_noise(wx: float, wz: float) -> float:
	return _fbm2(wx * 0.055 + 1200.0, wz * 0.055 + 900.0)


static func _scatter_blueberry_bushes(
	zone_root: Node3D,
	coord: Vector2i,
	biome: StringName,
	rng: RandomNumberGenerator,
	height_func: Callable,
	origin_x: float,
	origin_z: float,
) -> void:
	_ensure_berry_bushes()

	var cluster_count: int = rng.randi_range(6, 14)

	for _i in cluster_count:
		var lx := rng.randf_range(2.0, ZONE_SIZE - 2.0)
		var lz := rng.randf_range(2.0, ZONE_SIZE - 2.0)
		var wx := origin_x + lx
		var wz := origin_z + lz
		var sn := _hg_snap_and_normal(wx, wz)
		var ground_y := sn.x
		if ground_y < _MIN_LAND_Y or ground_y > 20.0:
			continue
		if sn.y < 0.85:
			continue
		if _hg_is_steep_edge(wx, wz, ground_y):
			continue
		if is_dirt_patch(wx, wz):
			continue
		if is_on_path(wx, wz):
			continue
		if _is_near_structure(wx, wz):
			continue

		var bushes_in_cluster := rng.randi_range(1, 4)
		for _ci in bushes_in_cluster:
			var cx := lx
			var cz := lz
			if _ci > 0:
				var off_angle := rng.randf_range(0.0, TAU)
				var off_dist := rng.randf_range(0.8, 2.0)
				cx = clampf(lx + cos(off_angle) * off_dist, 2.0, ZONE_SIZE - 2.0)
				cz = clampf(lz + sin(off_angle) * off_dist, 2.0, ZONE_SIZE - 2.0)
				var csn := _hg_snap_and_normal(origin_x + cx, origin_z + cz)
				if csn.x < _MIN_LAND_Y or csn.y < 0.85:
					continue
				ground_y = csn.x

			var bush := _create_blueberry_bush(rng)
			if not bush:
				continue
			bush.position = Vector3(cx, ground_y + 0.08, cz)
			bush.rotation.y = rng.randf_range(0.0, TAU)
			zone_root.add_child(bush)


static func _get_microbiome_counts(biome: StringName, micro: StringName) -> PackedInt32Array:
	if biome == &"hearthlands" and micro != &"none":
		# [trees, rocks, bushes, enemies]
		match micro:
			&"meadow":
				return PackedInt32Array([12, 2, 4, 1])
			&"forest":
				return PackedInt32Array([28, 1, 2, 2])
			&"birch_forest":
				return PackedInt32Array([28, 1, 2, 1])
			&"hills":
				return PackedInt32Array([10, 3, 1, 2])
			&"riverside":
				return PackedInt32Array([16, 4, 5, 1])
		return PackedInt32Array([14, 2, 3, 1])
	return _get_biome_counts(biome)


static func _get_biome_counts(biome: StringName) -> PackedInt32Array:
	if biome == &"hearthlands":
		return PackedInt32Array([12, 2, 3, 1])
	return PackedInt32Array([0, 0, 0, 0])


static func _hash12(px: float, pz: float) -> float:
	var h := px * 127.1 + pz * 311.7
	return fmod(abs(sin(h) * 43758.5453), 1.0)

static func _vnoise(px: float, pz: float) -> float:
	var ix := floorf(px)
	var iz := floorf(pz)
	var fx := px - ix
	var fz := pz - iz
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	return lerpf(
		lerpf(_hash12(ix, iz), _hash12(ix + 1.0, iz), fx),
		lerpf(_hash12(ix, iz + 1.0), _hash12(ix + 1.0, iz + 1.0), fx),
		fz)

static func _fbm2(px: float, pz: float) -> float:
	var v := _vnoise(px, pz) * 0.6
	v += _vnoise(px * 2.1 + 100.0, pz * 2.1 + 100.0) * 0.4
	return v

static func is_dirt_patch(wx: float, wz: float, amount: float = 0.1) -> bool:
	var warp_x := _fbm2(wx * 0.012 + 137.0, wz * 0.012 + 241.0) * 28.0
	var warp_z := _fbm2(wx * 0.012 + 359.0, wz * 0.012 + 83.0) * 28.0
	var n := _fbm2((wx + warp_x) * 0.018 + 500.0, (wz + warp_z) * 0.018 + 700.0)
	var thresh := 0.5 + (0.5 - amount) * 0.6
	return n > thresh


static func get_path_factor(wx: float, wz: float) -> float:
	var warp1_x := _fbm2(wx * 0.005 + 300.0, wz * 0.005 + 150.0) * 42.0
	var warp1_z := _fbm2(wx * 0.005 + 800.0, wz * 0.005 + 550.0) * 42.0
	var warp2_x := _vnoise(wx * 0.018 + 170.0, wz * 0.018 + 430.0) * 16.0
	var warp2_z := _vnoise(wx * 0.018 + 610.0, wz * 0.018 + 290.0) * 16.0
	var warped_x := wx + warp1_x + warp2_x
	var warped_z := wz + warp1_z + warp2_z

	var n1 := _vnoise(warped_x * 0.018, warped_z * 0.009)
	var ridge1 := 1.0 - absf(n1 * 2.0 - 1.0)
	ridge1 = ridge1 * ridge1 * ridge1 * ridge1

	var n2 := _vnoise(warped_x * 0.009 + 50.0, warped_z * 0.018 + 70.0)
	var ridge2 := 1.0 - absf(n2 * 2.0 - 1.0)
	ridge2 = ridge2 * ridge2 * ridge2 * ridge2

	var combined := maxf(ridge1, ridge2 * 0.8)
	return clampf(combined * 1.4 - 0.3, 0.0, 1.0)


static func is_on_path(wx: float, wz: float) -> bool:
	return get_path_factor(wx, wz) > 0.3

static func _snap_height_to_mesh(wx: float, wz: float, height_func: Callable) -> float:
	const STEP := ZONE_SIZE / 48.0
	var gx := floorf(wx / STEP) * STEP
	var gz := floorf(wz / STEP) * STEP
	var fx := (wx - gx) / STEP
	var fz := (wz - gz) / STEP

	var h00 := float(height_func.call(gx, gz))
	var h10 := float(height_func.call(gx + STEP, gz))
	var h01 := float(height_func.call(gx, gz + STEP))
	var h11 := float(height_func.call(gx + STEP, gz + STEP))

	if fx + fz <= 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)


static func _terrain_normal_y(wx: float, wz: float, height_func: Callable) -> float:
	const STEP := ZONE_SIZE / 32.0
	var h_left := float(height_func.call(wx - STEP, wz))
	var h_right := float(height_func.call(wx + STEP, wz))
	var h_up := float(height_func.call(wx, wz - STEP))
	var h_down := float(height_func.call(wx, wz + STEP))
	var tx := Vector3(2.0 * STEP, h_right - h_left, 0.0)
	var tz := Vector3(0.0, h_down - h_up, 2.0 * STEP)
	return tz.cross(tx).normalized().y


## Combined snap + normal in one pass — samples height grid only 4 times
## instead of 8 (4 for snap + 4 for normal separately).
## Returns Vector2(snapped_height, normal_y).
static func _snap_and_normal(wx: float, wz: float, height_func: Callable) -> Vector2:
	const STEP := ZONE_SIZE / 32.0
	var gx := floorf(wx / STEP) * STEP
	var gz := floorf(wz / STEP) * STEP
	var fx := (wx - gx) / STEP
	var fz := (wz - gz) / STEP

	var h00 := float(height_func.call(gx, gz))
	var h10 := float(height_func.call(gx + STEP, gz))
	var h01 := float(height_func.call(gx, gz + STEP))
	var h11 := float(height_func.call(gx + STEP, gz + STEP))

	var snapped: float
	if fx + fz <= 1.0:
		snapped = h00 + (h10 - h00) * fx + (h01 - h00) * fz
	else:
		snapped = h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)

	var tx := Vector3(2.0 * STEP, h10 - h00 + h11 - h01, 0.0)
	var tz := Vector3(0.0, h01 - h00 + h11 - h10, 2.0 * STEP)
	var ny := tz.cross(tx).normalized().y

	return Vector2(snapped, ny)


## Returns true when the point sits on or near a steep mountain edge.
## Uses a wide-radius height probe to catch cliff transitions that
## local normals miss (e.g., a flat ledge right at the edge of a drop).
static func _is_steep_edge(wx: float, wz: float, ground_y: float, height_func: Callable) -> bool:
	const R := 10.0
	var h_l := _snap_height_to_mesh(wx - R, wz, height_func)
	var h_r := _snap_height_to_mesh(wx + R, wz, height_func)
	var h_u := _snap_height_to_mesh(wx, wz - R, height_func)
	var h_d := _snap_height_to_mesh(wx, wz + R, height_func)
	var slope_x := absf(h_r - h_l) / (R * 2.0)
	var slope_z := absf(h_d - h_u) / (R * 2.0)
	if slope_x > 0.28 or slope_z > 0.28:
		return true
	if absf(ground_y - h_l) > 5.0 or absf(ground_y - h_r) > 5.0 \
			or absf(ground_y - h_u) > 5.0 or absf(ground_y - h_d) > 5.0:
		return true
	return false


# ═══════════════════════════════════════════════════════════════════════════════
#  TREE — Procedural trunk with root flare + 2D billboard leaf planes
# ═══════════════════════════════════════════════════════════════════════════════

## Builds a trunk ArrayMesh with a flared base, buttress root ridges, and
## organic asymmetry via SurfaceTool.  Radius profile: wide flare at the
## bottom with smooth cubic ease into a tapered body.  Per-ring center
## offsets produce a natural lean/wobble.  Each ring is slightly oval with
## randomised orientation.  Bottom cap closes the mesh so it never looks
## hollow.  Buttress roots vary in strength for a non-uniform silhouette.
static func _build_trunk_mesh(
	bot_r: float, top_r: float, height: float,
	num_roots: int, rng: RandomNumberGenerator,
	branch_fracs: PackedFloat32Array = PackedFloat32Array(),
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var radial_segs := 16
	var h_rings := 18
	var flare_mult := 1.40
	var flare_zone := 0.15
	var root_zone := 0.25

	var sorted_branches := Array(branch_fracs)
	sorted_branches.sort()
	var step_down_per_branch := 0.08

	# --- Buttress roots with varied strength ---
	var root_angles := PackedFloat32Array()
	var root_strengths := PackedFloat32Array()
	if num_roots > 0:
		var base_a := rng.randf_range(0.0, TAU)
		for i in num_roots:
			root_angles.append(
				base_a + TAU * float(i) / float(num_roots)
				+ rng.randf_range(-0.35, 0.35))
			root_strengths.append(rng.randf_range(0.5, 1.0))

	# --- Organic lean: accumulated XZ drift per ring ---
	var drift_x := 0.0
	var drift_z := 0.0
	var drift_step_x := rng.randf_range(-0.035, 0.035) * bot_r
	var drift_step_z := rng.randf_range(-0.035, 0.035) * bot_r

	# --- Per-ring ovalization ---
	var oval_angle := rng.randf_range(0.0, TAU)
	var oval_amount := rng.randf_range(0.03, 0.10)

	var all_rings: Array[PackedVector3Array] = []
	for ri in range(h_rings + 1):
		var t := float(ri) / float(h_rings)
		var y := t * height

		var r: float
		if t < flare_zone:
			var ft := t / flare_zone
			var ease := ft * ft * (3.0 - 2.0 * ft)
			r = lerpf(bot_r * flare_mult, bot_r, ease)
		else:
			var tt := (t - flare_zone) / (1.0 - flare_zone)
			r = lerpf(bot_r, top_r, tt)

		var cumulative_reduction := 0.0
		for bf in sorted_branches:
			if t > bf:
				cumulative_reduction += step_down_per_branch
		r *= (1.0 - cumulative_reduction)

		drift_x += drift_step_x * (1.0 - t * 0.3)
		drift_z += drift_step_z * (1.0 - t * 0.3)
		if ri % 4 == 0:
			drift_step_x += rng.randf_range(-0.012, 0.012) * bot_r
			drift_step_z += rng.randf_range(-0.012, 0.012) * bot_r

		var ring := PackedVector3Array()
		ring.resize(radial_segs)
		for si in radial_segs:
			var angle := TAU * float(si) / float(radial_segs)
			var vr := r

			var oval_stretch := 1.0 + oval_amount * cos(2.0 * (angle - oval_angle))
			vr *= oval_stretch

			if t < root_zone and num_roots > 0:
				var root_fade := 1.0 - t / root_zone
				root_fade = root_fade * root_fade * root_fade
				for ra_idx in root_angles.size():
					var ra: float = root_angles[ra_idx]
					var str_mult: float = root_strengths[ra_idx]
					var da := absf(fmod(angle - ra + PI + TAU, TAU) - PI)
					var root_w := 0.45
					if da < root_w:
						var strength := cos(da / root_w * PI * 0.5)
						strength *= strength
						vr += bot_r * 0.75 * strength * root_fade * str_mult

			vr += rng.randf_range(-0.035, 0.035) * r

			var px := cos(angle) * vr + drift_x * t
			var pz := sin(angle) * vr + drift_z * t
			ring[si] = Vector3(px, y, pz)

		all_rings.append(ring)

	# --- Side faces ---
	for ri in h_rings:
		for si in radial_segs:
			var ns := (si + 1) % radial_segs
			var v00: Vector3 = all_rings[ri][si]
			var v10: Vector3 = all_rings[ri][ns]
			var v01: Vector3 = all_rings[ri + 1][si]
			var v11: Vector3 = all_rings[ri + 1][ns]

			st.add_vertex(v00)
			st.add_vertex(v10)
			st.add_vertex(v01)

			st.add_vertex(v10)
			st.add_vertex(v11)
			st.add_vertex(v01)

	# --- Bottom cap (triangle fan, facing down) ---
	var bot_ring: PackedVector3Array = all_rings[0]
	var bot_center := Vector3.ZERO
	for vi in bot_ring.size():
		bot_center += bot_ring[vi]
	bot_center /= float(bot_ring.size())
	for si in radial_segs:
		var ns := (si + 1) % radial_segs
		st.add_vertex(bot_center)
		st.add_vertex(bot_ring[ns])
		st.add_vertex(bot_ring[si])

	st.generate_normals()
	return st.commit()


static func _sample_branch_curve(
	t: float, length: float, upward_arc: float, bend: Dictionary,
) -> Vector3:
	var freq: float = bend.freq
	var amp_x: float = bend.amp_x
	var amp_z: float = bend.amp_z
	var ph_x: float = bend.phase_x
	var ph_z: float = bend.phase_z
	var cx: float = sin(t * freq * PI + ph_x) * amp_x * t
	var cz: float = sin(t * freq * PI * 0.7 + ph_z) * amp_z * t
	return Vector3(cx, upward_arc * t * t + t * length, cz)


static func _make_bend_params(length: float, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"freq": rng.randf_range(1.5, 3.0),
		"amp_x": length * rng.randf_range(0.075, 0.1875),
		"amp_z": length * rng.randf_range(0.05, 0.125),
		"phase_x": rng.randf_range(0.0, TAU),
		"phase_z": rng.randf_range(0.0, TAU),
	}


static func _build_branch_mesh(
	base_r: float, length: float, upward_arc: float,
	rng: RandomNumberGenerator, bend: Dictionary = {},
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var radial_segs := 8
	var h_rings := 10
	var tip_r := base_r * 0.20

	var bend_freq: float = bend.get("freq", rng.randf_range(1.5, 3.0))
	var bend_amp_x: float = bend.get("amp_x", length * rng.randf_range(0.06, 0.15))
	var bend_amp_z: float = bend.get("amp_z", length * rng.randf_range(0.04, 0.10))
	var bend_phase_x: float = bend.get("phase_x", rng.randf_range(0.0, TAU))
	var bend_phase_z: float = bend.get("phase_z", rng.randf_range(0.0, TAU))

	var all_rings: Array[PackedVector3Array] = []
	for ri in range(h_rings + 1):
		var t := float(ri) / float(h_rings)
		var r := lerpf(base_r, tip_r, t)
		r += rng.randf_range(-0.02, 0.02) * base_r

		var y_offset := upward_arc * t * t
		var along := t * length

		var curve_x := sin(t * bend_freq * PI + bend_phase_x) * bend_amp_x * t
		var curve_z := sin(t * bend_freq * PI * 0.7 + bend_phase_z) * bend_amp_z * t

		var ring := PackedVector3Array()
		ring.resize(radial_segs)
		for si in radial_segs:
			var angle := TAU * float(si) / float(radial_segs)
			var px := cos(angle) * r + curve_x
			var pz := sin(angle) * r + curve_z
			ring[si] = Vector3(px, y_offset + along, pz)
		all_rings.append(ring)

	for ri in h_rings:
		for si in radial_segs:
			var ns := (si + 1) % radial_segs
			var v00: Vector3 = all_rings[ri][si]
			var v10: Vector3 = all_rings[ri][ns]
			var v01: Vector3 = all_rings[ri + 1][si]
			var v11: Vector3 = all_rings[ri + 1][ns]
			st.add_vertex(v00)
			st.add_vertex(v10)
			st.add_vertex(v01)
			st.add_vertex(v10)
			st.add_vertex(v11)
			st.add_vertex(v01)

	var bot_ring: PackedVector3Array = all_rings[0]
	var bot_center := Vector3.ZERO
	for vi in bot_ring.size():
		bot_center += bot_ring[vi]
	bot_center /= float(bot_ring.size())
	for si in radial_segs:
		var ns := (si + 1) % radial_segs
		st.add_vertex(bot_center)
		st.add_vertex(bot_ring[ns])
		st.add_vertex(bot_ring[si])

	st.generate_normals()
	return st.commit()


static func _create_tree(biome: StringName, rng: RandomNumberGenerator, microbiome: StringName = &"none") -> StaticBody3D:
	var pooled := _ZonePool.get_tree_node()
	if pooled:
		pooled.set_meta("hp", 80.0)
		pooled.set_meta("max_hp", 80.0)
		pooled.collision_mask = 0
		return pooled

	var root := StaticBody3D.new()
	root.collision_layer = 4
	root.collision_mask = 0
	root.add_to_group(&"interactables")

	var tname := _pick_tree_name(biome, rng, microbiome)
	var is_birch := tname == "Birch"
	var is_pine := tname == "Pine"
	var is_willow := tname == "Willow"
	var is_palm := false
	var is_oak := tname == "Oak"

	var height_tiers := [0.7, 0.8, 0.9, 1.0]
	var sf: float = height_tiers[rng.randi_range(0, 3)]
	var wsf := rng.randf_range(0.9, 1.1)

	# ── Trunk ──
	var trunk_h: float
	var trunk_bot_r: float
	var trunk_top_r: float
	var bark_mat: Material
	var num_roots: int

	if is_birch:
		trunk_h = 81.0 * sf
		trunk_bot_r = 0.63 * sf * wsf
		trunk_top_r = 0.28 * sf * wsf
		bark_mat = _mat_birch_bark
		num_roots = 3
	elif is_pine:
		trunk_h = 91.2 * sf
		trunk_bot_r = 0.77 * sf * wsf
		trunk_top_r = 0.245 * sf * wsf
		bark_mat = _mat_bark
		num_roots = 3
	elif is_willow:
		trunk_h = 60.9 * sf
		trunk_bot_r = 0.91 * sf * wsf
		trunk_top_r = 0.49 * sf * wsf
		bark_mat = _mat_bark
		num_roots = 4
	elif is_palm:
		trunk_h = 71.1 * sf
		trunk_bot_r = 0.595 * sf * wsf
		trunk_top_r = 0.35 * sf * wsf
		bark_mat = _mat_bark
		num_roots = 2
	else:
		trunk_h = 76.2 * sf
		trunk_bot_r = 0.84 * sf * wsf
		trunk_top_r = 0.35 * sf * wsf
		bark_mat = _mat_bark
		num_roots = 4

	# ── Branches: define per-species parameters ──
	var branch_count: int
	var branch_zone_lo: float
	var branch_zone_hi: float
	var branch_len_frac_lo: float
	var branch_len_frac_hi: float
	var branch_tilt_lo: float
	var branch_tilt_hi: float
	var branch_r_frac: float

	if is_birch:
		branch_count = int(rng.randi_range(12, 20) * sf)
		branch_zone_lo = 0.25
		branch_zone_hi = 0.70
		branch_len_frac_lo = 0.14
		branch_len_frac_hi = 0.28
		branch_tilt_lo = 30.0
		branch_tilt_hi = 55.0
		branch_r_frac = 0.55
	elif is_oak:
		branch_count = int(rng.randi_range(16, 24) * sf)
		branch_zone_lo = 0.20
		branch_zone_hi = 0.65
		branch_len_frac_lo = 0.175
		branch_len_frac_hi = 0.35
		branch_tilt_lo = 20.0
		branch_tilt_hi = 45.0
		branch_r_frac = 0.65
	else:
		branch_count = int(rng.randi_range(12, 20) * sf)
		branch_zone_lo = 0.25
		branch_zone_hi = 0.68
		branch_len_frac_lo = 0.154
		branch_len_frac_hi = 0.315
		branch_tilt_lo = 25.0
		branch_tilt_hi = 50.0
		branch_r_frac = 0.60

	var branch_heights: PackedFloat32Array = PackedFloat32Array()
	var leaf_anchor_positions: Array[Vector3] = []
	# Golden angle (~137.5 deg) ensures branches spread evenly around trunk
	const GOLDEN_ANGLE := 2.39996323
	var branch_base_angle := rng.randf_range(0.0, TAU)
	for bi in branch_count:
		var t_in_zone := float(bi) / float(maxi(branch_count - 1, 1))
		var h_frac := lerpf(branch_zone_lo, branch_zone_hi, t_in_zone)
		h_frac += rng.randf_range(-0.04, 0.04)
		h_frac = clampf(h_frac, branch_zone_lo, branch_zone_hi)
		branch_heights.append(h_frac)

	var trunk_mesh := _build_trunk_mesh(trunk_bot_r, trunk_top_r, trunk_h, num_roots, rng, branch_heights)

	# Merge trunk + all branches into a single mesh for performance
	var merge_st := SurfaceTool.new()
	merge_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	merge_st.append_from(trunk_mesh, 0, Transform3D.IDENTITY)

	# ── Build branches and merge geometry into trunk mesh ──
	for bi in branch_count:
		var h_frac: float = branch_heights[bi]
		var branch_y := h_frac * trunk_h
		var height_t := float(bi) / float(maxi(branch_count - 1, 1))

		var branch_angle := branch_base_angle + GOLDEN_ANGLE * float(bi) + rng.randf_range(-0.2, 0.2)
		var len_frac := lerpf(branch_len_frac_hi, branch_len_frac_lo, height_t)
		var branch_len := trunk_h * len_frac * rng.randf_range(0.85, 1.15)

		var trunk_r_at_h := lerpf(trunk_bot_r, trunk_top_r, h_frac)
		var b_base_r := trunk_r_at_h * branch_r_frac * lerpf(1.0, 0.6, height_t)
		var tilt_deg := lerpf(branch_tilt_lo, branch_tilt_hi, height_t) + rng.randf_range(-5.0, 5.0)
		var upward_arc := branch_len * rng.randf_range(0.25, 0.50)

		var branch_bend := _make_bend_params(branch_len, rng)
		var branch_mesh := _build_branch_mesh(b_base_r, branch_len, upward_arc, rng, branch_bend)

		var tilt_rad := deg_to_rad(tilt_deg)
		var branch_dir := Vector3(
			cos(branch_angle) * cos(tilt_rad),
			sin(tilt_rad),
			sin(branch_angle) * cos(tilt_rad)).normalized()
		var up_guess := Vector3.UP
		if absf(branch_dir.dot(up_guess)) > 0.95:
			up_guess = Vector3.FORWARD
		var b_right := branch_dir.cross(up_guess).normalized()
		var b_forward := b_right.cross(branch_dir).normalized()
		var branch_basis := Basis(b_right, branch_dir, b_forward)

		var branch_pos := Vector3(
			cos(branch_angle) * trunk_r_at_h * 0.5,
			branch_y,
			sin(branch_angle) * trunk_r_at_h * 0.5)
		var branch_xform := Transform3D(branch_basis, branch_pos)
		merge_st.append_from(branch_mesh, 0, branch_xform)

		for sample_t in [0.35, 0.65, 1.0]:
			var pt := _sample_branch_curve(sample_t, branch_len, upward_arc, branch_bend)
			var pt_in_root := branch_basis * pt + branch_pos
			leaf_anchor_positions.append(pt_in_root)

		var sub_count := rng.randi_range(2, 3)
		for si in sub_count:
			var sub_t := rng.randf_range(0.4, 0.75)
			var sub_len := branch_len * rng.randf_range(0.35, 0.50)
			var sub_r := b_base_r * 0.3
			var sub_arc := sub_len * rng.randf_range(0.20, 0.45)
			var sub_angle := branch_angle + rng.randf_range(-0.8, 0.8)
			var sub_tilt_deg := tilt_deg + rng.randf_range(10.0, 25.0)
			var sub_tilt_rad := deg_to_rad(sub_tilt_deg)

			var sub_bend := _make_bend_params(sub_len, rng)
			var sub_mesh := _build_branch_mesh(sub_r, sub_len, sub_arc, rng, sub_bend)

			var sub_dir := Vector3(
				cos(sub_angle) * cos(sub_tilt_rad),
				sin(sub_tilt_rad),
				sin(sub_angle) * cos(sub_tilt_rad)).normalized()
			var sub_up := Vector3.UP
			if absf(sub_dir.dot(sub_up)) > 0.95:
				sub_up = Vector3.FORWARD
			var sub_right := sub_dir.cross(sub_up).normalized()
			var sub_fwd := sub_right.cross(sub_dir).normalized()

			var attach_pt := _sample_branch_curve(sub_t, branch_len, upward_arc, branch_bend)
			var sub_basis := Basis(sub_right, sub_dir, sub_fwd)
			var sub_xform := branch_xform * Transform3D(sub_basis, attach_pt)
			merge_st.append_from(sub_mesh, 0, sub_xform)

			var sub_attach_in_root := branch_basis * attach_pt + branch_pos
			var sub_tip_offset := Vector3(
				cos(sub_angle) * sub_len * 0.7 * cos(sub_tilt_rad),
				sub_len * sin(sub_tilt_rad) + sub_arc,
				sin(sub_angle) * sub_len * 0.7 * cos(sub_tilt_rad))
			leaf_anchor_positions.append(sub_attach_in_root + sub_tip_offset)

			# Tertiary twigs branching off each sub-branch
			var twig_count := rng.randi_range(1, 2)
			for ti in twig_count:
				var tw_t := rng.randf_range(0.45, 0.85)
				var tw_len := sub_len * rng.randf_range(0.30, 0.45)
				var tw_r := sub_r * 0.35
				var tw_arc := tw_len * rng.randf_range(0.15, 0.40)
				var tw_angle := sub_angle + rng.randf_range(-1.0, 1.0)
				var tw_tilt_deg := sub_tilt_deg + rng.randf_range(5.0, 20.0)
				var tw_tilt_rad := deg_to_rad(tw_tilt_deg)

				var tw_mesh := _build_branch_mesh(tw_r, tw_len, tw_arc, rng)

				var tw_dir := Vector3(
					cos(tw_angle) * cos(tw_tilt_rad),
					sin(tw_tilt_rad),
					sin(tw_angle) * cos(tw_tilt_rad)).normalized()
				var tw_up := Vector3.UP
				if absf(tw_dir.dot(tw_up)) > 0.95:
					tw_up = Vector3.FORWARD
				var tw_right := tw_dir.cross(tw_up).normalized()
				var tw_fwd := tw_right.cross(tw_dir).normalized()

				var tw_attach := _sample_branch_curve(tw_t, sub_len, sub_arc, sub_bend)
				var tw_basis := Basis(tw_right, tw_dir, tw_fwd)
				var tw_xform := sub_xform * Transform3D(tw_basis, tw_attach)
				merge_st.append_from(tw_mesh, 0, tw_xform)

				var tw_world_attach := sub_basis * tw_attach
				var tw_tip := Vector3(
					cos(tw_angle) * tw_len * 0.6 * cos(tw_tilt_rad),
					tw_len * sin(tw_tilt_rad) + tw_arc,
					sin(tw_angle) * tw_len * 0.6 * cos(tw_tilt_rad))
				leaf_anchor_positions.append(sub_attach_in_root + tw_world_attach + tw_tip)

	merge_st.generate_normals()
	var trunk_mi := MeshInstance3D.new()
	trunk_mi.name = "MeshInstance3D"
	trunk_mi.mesh = merge_st.commit()
	trunk_mi.set_surface_override_material(0, bark_mat)
	trunk_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trunk_mi.visibility_range_end = 360.0
	trunk_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	root.add_child(trunk_mi)

	# ── Trunk spine leaf anchors: upper 40% of trunk always covered ──
	var trunk_leaf_start := trunk_h * 0.60
	var trunk_spine_steps := 8
	for ti in trunk_spine_steps:
		var frac := float(ti) / float(trunk_spine_steps - 1)
		var spine_y := lerpf(trunk_leaf_start, trunk_h, frac)
		var spine_angle := rng.randf_range(0.0, TAU)
		var spine_r := rng.randf_range(0.0, trunk_top_r * 1.5)
		leaf_anchor_positions.append(Vector3(
			cos(spine_angle) * spine_r, spine_y, sin(spine_angle) * spine_r))

	# ── Choose leaf texture and base color by tree family ──
	var leaf_tex: ImageTexture
	var base_leaf_color: Color

	if is_birch:
		leaf_tex = _leaf_tex_birch
		base_leaf_color = Color.from_hsv(0.22, 0.55, 0.62)
	elif is_pine:
		leaf_tex = _leaf_tex_pine
		base_leaf_color = Color.from_hsv(0.33, 0.65, 0.38)
	elif is_willow:
		leaf_tex = _leaf_tex_willow
		base_leaf_color = Color.from_hsv(0.28, 0.50, 0.55)
	elif is_palm:
		leaf_tex = _leaf_tex_palm
		base_leaf_color = Color.from_hsv(0.30, 0.55, 0.55)
	elif is_oak:
		leaf_tex = _leaf_tex_oak
		base_leaf_color = Color.from_hsv(0.27, 0.60, 0.50)
	else:
		leaf_tex = _leaf_tex_generic
		base_leaf_color = Color.from_hsv(0.28, 0.58, 0.48)

	var leaf_mat := _make_tree_leaf_mat(leaf_tex, base_leaf_color, rng)

	# ── Canopy geometry ──
	var canopy_spread: float
	var canopy_height: float
	var canopy_base_y: float
	var plane_count: int
	var plane_size_base: float

	if is_birch:
		canopy_spread = 6.05 * sf * wsf
		canopy_base_y = trunk_h * 0.28
		plane_count = int(rng.randi_range(130, 180) * sf)
		plane_size_base = 7.0 * sf * wsf
	elif is_pine:
		canopy_spread = 4.4 * sf * wsf
		canopy_base_y = trunk_h * 0.2
		plane_count = int(rng.randi_range(72, 105) * sf)
		plane_size_base = 5.8 * sf * wsf
	elif is_willow:
		canopy_spread = 7.7 * sf * wsf
		canopy_base_y = trunk_h * 0.35
		plane_count = int(rng.randi_range(72, 100) * sf)
		plane_size_base = 8.5 * sf * wsf
	elif is_palm:
		canopy_spread = 5.5 * sf * wsf
		canopy_base_y = trunk_h * 0.7
		plane_count = int(rng.randi_range(40, 56) * sf)
		plane_size_base = 8.0 * sf * wsf
	elif is_oak:
		canopy_spread = 6.6 * sf * wsf
		canopy_base_y = trunk_h * 0.20
		plane_count = int(rng.randi_range(190, 290) * sf)
		plane_size_base = 7.5 * sf * wsf
	else:
		canopy_spread = 6.6 * sf * wsf
		canopy_base_y = trunk_h * 0.25
		plane_count = int(rng.randi_range(65, 100) * sf)
		plane_size_base = 7.5 * sf * wsf

	# Canopy must always extend above trunk top with overshoot
	var canopy_overshoot := 3.25 * sf
	canopy_height = (trunk_h + canopy_overshoot) - canopy_base_y

	var canopy_center_y := canopy_base_y + canopy_height * 0.5
	var canopy_parent := Node3D.new()
	canopy_parent.name = "Canopy"
	canopy_parent.position.y = canopy_center_y
	root.add_child(canopy_parent)

	var leaf_xforms: Array[Transform3D] = []

	var n_anchors := leaf_anchor_positions.size()
	var min_per_anchor := 3
	var anchor_count := maxi(int(plane_count * 0.80), n_anchors * min_per_anchor) if n_anchors > 0 else 0
	if n_anchors > 0:
		var per_anchor := maxi(min_per_anchor, anchor_count / n_anchors)
		var placed := 0
		for ai in n_anchors:
			var anchor: Vector3 = leaf_anchor_positions[ai]
			var anchor_in_canopy := anchor - Vector3(0.0, canopy_center_y, 0.0)
			var cluster_r := canopy_spread * 0.22
			var n_for := per_anchor if ai < n_anchors - 1 else maxi(min_per_anchor, anchor_count - placed)
			for _pi in n_for:
				var this_size := plane_size_base * rng.randf_range(0.6, 1.15)
				var off := Vector3(
					rng.randf_range(-cluster_r, cluster_r),
					rng.randf_range(-cluster_r * 0.5, cluster_r * 0.5),
					rng.randf_range(-cluster_r, cluster_r))
				var pos := anchor_in_canopy + off
				var rot := Vector3(
					rng.randf_range(-0.7, 0.7),
					rng.randf_range(0.0, TAU),
					rng.randf_range(-0.5, 0.5))
				var basis := Basis.from_euler(rot).scaled(Vector3(this_size, this_size, this_size))
				leaf_xforms.append(Transform3D(basis, pos))
			placed += n_for

	var remaining := maxi(0, plane_count - anchor_count)
	var fill_count := int(remaining * 0.65)
	for pi in fill_count:
		var this_size := plane_size_base * rng.randf_range(0.55, 1.1)
		var fill_angle := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(canopy_spread * 0.15, canopy_spread * 0.7)
		var vert := rng.randf_range(-canopy_height * 0.15, canopy_height * 0.45)
		if is_pine:
			r *= (1.0 - (vert + canopy_height * 0.48) / canopy_height)
		var pos := Vector3(cos(fill_angle) * r, vert, sin(fill_angle) * r)
		var rot := Vector3(
			rng.randf_range(-0.8, 0.8),
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.5, 0.5))
		var basis := Basis.from_euler(rot).scaled(Vector3(this_size, this_size, this_size))
		leaf_xforms.append(Transform3D(basis, pos))

	var trunk_top_in_canopy := trunk_h - canopy_center_y
	var crown_count := maxi(0, remaining - fill_count)
	for ci in crown_count:
		var this_size := plane_size_base * rng.randf_range(0.7, 1.05)
		var collar_angle := rng.randf_range(0.0, TAU)
		var collar_r := rng.randf_range(0.0, canopy_spread * 0.45)
		var pos := Vector3(
			cos(collar_angle) * collar_r,
			trunk_top_in_canopy + rng.randf_range(-2.0, 2.5) * sf,
			sin(collar_angle) * collar_r)
		var rot := Vector3(
			rng.randf_range(-0.8, 0.8),
			rng.randf_range(0.0, TAU),
			rng.randf_range(-0.5, 0.5))
		var basis := Basis.from_euler(rot).scaled(Vector3(this_size, this_size, this_size))
		leaf_xforms.append(Transform3D(basis, pos))

	if not leaf_xforms.is_empty():
		var mm := MultiMesh.new()
		mm.mesh = _leaf_unit_quad
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = false
		mm.instance_count = leaf_xforms.size()
		for i in leaf_xforms.size():
			mm.set_instance_transform(i, leaf_xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "LeafMM"
		mmi.multimesh = mm
		mmi.material_override = leaf_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 300.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		canopy_parent.add_child(mmi)

	# ── Collision — wider at base to cover root flare ──
	# Start disabled to avoid physics spike on creation; LOD update enables for nearby zones
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = trunk_bot_r * 1.5
	shape.height = trunk_h * 0.8
	col.shape = shape
	col.position.y = trunk_h * 0.4
	col.disabled = true
	root.add_child(col)

	# ── Harvestable metadata ──
	root.set_meta("harvestable", true)
	root.set_meta("hp", 80.0)
	root.set_meta("max_hp", 80.0)
	root.set_meta("drop_id", &"wood")
	root.set_meta("drop_min", 4)
	root.set_meta("drop_max", 8)
	root.set_meta("tree_name", tname)
	root.set_meta("trunk_h", trunk_h)

	return root


static func _pick_tree_name(_biome: StringName, rng: RandomNumberGenerator, microbiome: StringName = &"none") -> String:
	match microbiome:
		&"birch_forest":
			return "Birch" if rng.randf() < 0.85 else "Oak"
		&"forest":
			return "Birch" if rng.randf() < 0.3 else "Oak"
		&"meadow":
			return "Birch" if rng.randf() < 0.4 else "Oak"
		&"riverside":
			return "Birch" if rng.randf() < 0.5 else "Oak"
		&"hills":
			return "Oak" if rng.randf() < 0.7 else "Birch"
		_:
			return "Birch" if rng.randf() < 0.35 else "Oak"


static func _get_canopy_material(_biome: StringName) -> Material:
	return _mat_leaves


static func _get_leaf_tex_for_biome(_biome: StringName) -> ImageTexture:
	return _leaf_tex_generic


# ═══════════════════════════════════════════════════════════════════════════════
#  3D ROCK — low-poly SphereMesh with triplanar stone texture
# ═══════════════════════════════════════════════════════════════════════════════

static func _generate_rock_mesh(seed_idx: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7777 + seed_idx * 131

	# Base proportions vary per rock: tall pillar, flat slab, round boulder, etc.
	var stretch := Vector3(
		rng.randf_range(0.6, 1.6),
		rng.randf_range(0.3, 1.4),
		rng.randf_range(0.6, 1.6))

	var segments := 12
	var rings := 7
	var base_radius := 0.5

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# Generate UV sphere vertices with noise displacement
	for ring in range(rings + 1):
		var v_frac := float(ring) / rings
		var phi := v_frac * PI
		for seg in range(segments + 1):
			var u_frac := float(seg) / segments
			var theta := u_frac * TAU

			var nx := sin(phi) * cos(theta)
			var ny := cos(phi)
			var nz := sin(phi) * sin(theta)
			var normal := Vector3(nx, ny, nz)

			# Multi-frequency noise for craggy, angular displacement
			var disp := 1.0
			var n1 := sin(nx * 5.3 + float(seed_idx) * 1.7) * cos(nz * 4.1 + ny * 3.2)
			var n2 := sin(ny * 7.9 + nx * 2.3 + float(seed_idx) * 0.9) * 0.5
			var n3 := cos(nx * 12.0 + nz * 8.0 + float(seed_idx) * 3.1) * 0.25
			disp += (n1 * 0.35 + n2 * 0.25 + n3 * 0.15) * rng.randf_range(0.5, 1.5)

			# Faceting: quantize a random subset of displacements for angular edges
			if rng.randf() < 0.35:
				disp = snapped(disp, 0.12)

			# Flatten bottom so rocks sit on ground
			if ny < -0.3:
				disp *= lerpf(0.4, 1.0, (ny + 1.0) * 0.7)

			var pos := normal * base_radius * disp
			pos *= stretch

			verts.append(pos)
			normals.append(normal * stretch.normalized())
			uvs.append(Vector2(u_frac, v_frac))

	# Generate triangle indices
	for ring in rings:
		for seg in segments:
			var curr := ring * (segments + 1) + seg
			var next := curr + segments + 1
			indices.append(curr)
			indices.append(next)
			indices.append(curr + 1)
			indices.append(curr + 1)
			indices.append(next)
			indices.append(next + 1)

	# Recompute normals from geometry — ensure they point outward
	var computed_normals := PackedVector3Array()
	computed_normals.resize(verts.size())
	for i in range(0, indices.size(), 3):
		var i0 := indices[i]
		var i1 := indices[i + 1]
		var i2 := indices[i + 2]
		var face_normal := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
		var center := (verts[i0] + verts[i1] + verts[i2]) / 3.0
		if face_normal.dot(center) < 0.0:
			face_normal = -face_normal
		computed_normals[i0] += face_normal
		computed_normals[i1] += face_normal
		computed_normals[i2] += face_normal
	for i in computed_normals.size():
		if computed_normals[i].length_squared() < 0.001:
			computed_normals[i] = verts[i].normalized()
		else:
			computed_normals[i] = computed_normals[i].normalized()

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = computed_normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _create_rock(rng: RandomNumberGenerator) -> StaticBody3D:
	var pooled := _ZonePool.get_rock_node()
	if pooled:
		var sf := rng.randf_range(1.2, 8.0)
		pooled.set_meta("hp", 15.0 + sf * 5.0)
		pooled.collision_mask = 0
		return pooled

	var root := StaticBody3D.new()
	root.collision_layer = 4
	root.collision_mask = 0

	var size_roll := rng.randf()
	var sf: float
	if size_roll < 0.45:
		sf = rng.randf_range(1.2, 2.5)
	elif size_roll < 0.75:
		sf = rng.randf_range(2.5, 4.0)
	elif size_roll < 0.93:
		sf = rng.randf_range(4.0, 6.0)
	else:
		sf = rng.randf_range(6.0, 8.0)

	var mesh_idx := rng.randi_range(0, _rock_meshes.size() - 1)

	var tinted_mat := _mat_stone.duplicate()
	var tint := Color(
		rng.randf_range(0.88, 1.12),
		rng.randf_range(0.88, 1.12),
		rng.randf_range(0.88, 1.12))
	if tinted_mat is ShaderMaterial:
		var base_col: Color = (tinted_mat as ShaderMaterial).get_shader_parameter("stone_color")
		(tinted_mat as ShaderMaterial).set_shader_parameter("stone_color", Color(
			base_col.r * tint.r, base_col.g * tint.g, base_col.b * tint.b))
	elif tinted_mat is StandardMaterial3D:
		(tinted_mat as StandardMaterial3D).albedo_color = tint

	var rock_mi := MeshInstance3D.new()
	rock_mi.name = "MeshInstance3D"
	rock_mi.mesh = _rock_meshes[mesh_idx]
	rock_mi.set_surface_override_material(0, tinted_mat)
	rock_mi.scale = Vector3(sf, sf, sf)
	rock_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(rock_mi)

	root.rotation.y = rng.randf_range(0.0, TAU)
	root.rotation.x = rng.randf_range(-0.15, 0.15)
	root.rotation.z = rng.randf_range(-0.15, 0.15)

	var col := CollisionShape3D.new()
	col.shape = _rock_convex_shapes[mesh_idx]
	col.scale = Vector3(sf, sf, sf)
	col.disabled = true  # Keep always disabled - raycast still works for harvesting
	root.add_child(col)

	root.add_to_group(&"interactables")
	root.set_meta("skip_collision_lod", true)  # Tell LOD system to not toggle collision
	root.set_meta("harvestable", true)
	root.set_meta("hp", 15.0 + sf * 5.0)
	root.set_meta("drop_id", &"stone")
	root.set_meta("drop_min", maxi(3, int(sf * 1.5)))
	root.set_meta("drop_max", maxi(6, int(sf * 2.4)))
	root.set_meta("requires_tool", &"stone_pickaxe")

	return root


static func _create_pebble(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Pebble"

	var sf := rng.randf_range(0.15, 0.45)
	var mesh_idx := rng.randi_range(0, _rock_meshes.size() - 1)

	var peb_mi := MeshInstance3D.new()
	peb_mi.mesh = _rock_meshes[mesh_idx]
	peb_mi.set_surface_override_material(0, _mat_pebble)
	peb_mi.scale = Vector3(sf, sf * rng.randf_range(0.5, 0.8), sf)
	peb_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(peb_mi)

	root.rotation.y = rng.randf_range(0.0, TAU)
	root.rotation.x = rng.randf_range(-0.2, 0.2)
	root.rotation.z = rng.randf_range(-0.2, 0.2)

	return root


# ═══════════════════════════════════════════════════════════════════════════════
#  3D BUSH — small squished SphereMesh with triplanar leaf texture
# ═══════════════════════════════════════════════════════════════════════════════

static func _create_bush(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var sf := rng.randf_range(0.4, 0.9)

	var bush_mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5 * sf
	sphere.height = 0.6 * sf
	sphere.radial_segments = 6
	sphere.rings = 3
	bush_mi.mesh = sphere
	bush_mi.set_surface_override_material(0, _mat_bush_leaves)
	bush_mi.position.y = 0.25 * sf
	bush_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	bush_mi.scale = Vector3(
		rng.randf_range(0.9, 1.3),
		rng.randf_range(0.6, 0.8),
		rng.randf_range(0.9, 1.3)
	)
	bush_mi.rotation.y = rng.randf_range(0.0, TAU)
	root.add_child(bush_mi)

	return root


static func _create_ground_stone(_rng: RandomNumberGenerator) -> Node3D:
	var drop := _LootDrop.new()
	drop.item_id = &"stone"
	drop.star_level = 0
	drop.amount = _rng.randi_range(1, 3)
	return drop


# ═══════════════════════════════════════════════════════════════════════════════
#  CREATURES — 3D-enhanced billboards with normal-map lighting + ground shadows
# ═══════════════════════════════════════════════════════════════════════════════

static var _cached_creature_mats: Dictionary = {}

static func _make_creature_sprite_mat(tex: Texture2D) -> ShaderMaterial:
	if not _creature_shader or not tex:
		return null
	var tex_id := tex.get_rid().get_id()
	if _cached_creature_mats.has(tex_id):
		return _cached_creature_mats[tex_id]
	var mat := ShaderMaterial.new()
	mat.shader = _creature_shader
	mat.set_shader_parameter("sprite_texture", tex)
	_cached_creature_mats[tex_id] = mat
	return mat


static func _add_ground_shadow(parent: Node3D, radius_x: float, radius_z: float, y_offset: float = 0.05) -> void:
	if not _shadow_mat:
		return
	var shadow := MeshInstance3D.new()
	shadow.name = "GroundShadow"
	var quad := QuadMesh.new()
	quad.size = Vector2(radius_x * 2.0, radius_z * 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	shadow.mesh = quad
	shadow.material_override = _shadow_mat
	shadow.position.y = y_offset
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shadow)


static var _creature_model_paths: Dictionary = {
	&"grizzly": "res://models/creatures/Grizzly Bear/Meshy_AI_model_Animation_Walking_withSkin.glb",
	&"boar": "res://models/creatures/Boar/Meshy_AI_model_Animation_Walking_withSkin.glb",
	&"lion": "res://models/creatures/Lion/Meshy_AI_model_Animation_Walking_withSkin.glb",
	&"cyclops": "res://models/creatures/Cyclops/Cyclops.glb",
	&"minotaur": "res://models/creatures/Minotaur/Minotaur.glb",
	&"orc_brute": "res://models/creatures/Orc Brute/Orc+Brute.glb",
	&"goblin": "res://models/creatures/Small Goblin/Goblin+Small.glb",
	&"hawk": "res://models/creatures/Hawk/hawk.gltf",
}

static var _creature_model_scales: Dictionary = {
	&"grizzly": 462.0,
	&"boar": 800.0,
	&"lion": 280.0,
	&"cyclops": 5.0,
	&"minotaur": 4.5,
	&"orc_brute": 3.5,
	&"goblin": 2.0,
	&"hawk": 2.5,
}

# Tripo models face opposite to Godot's -Z forward. PI offset corrects them.
static var _creature_yaw_offsets: Dictionary = {
	&"cyclops": -PI / 2.0,
	&"minotaur": -PI / 2.0,
	&"orc_brute": -PI / 2.0,
	&"goblin": -PI / 2.0,
}


static func _create_enemy(biome: StringName, rng: RandomNumberGenerator = null, forced_kind: StringName = &"") -> CharacterBody3D:
	var creature: CharacterBody3D = _CreatureAI.new()

	var kind := forced_kind if forced_kind != &"" else _pick_creature_kind(biome, rng)
	var stats := _creature_stats(kind)

	# Roll creature star level (1-5 stars, weighted by rarity)
	var star_rng := rng if rng else RandomNumberGenerator.new()
	var creature_stars := _roll_creature_stars(star_rng)

	# Scale HP and damage with stars: +40% per star
	var star_mult := 1.0 + creature_stars * 0.4
	creature.set("max_health", stats.hp * star_mult)
	creature.set("attack_damage", stats.dmg * star_mult)
	creature.set("move_speed", stats.spd)
	creature.set("display_name", stats.name)
	creature.set("creature_type", stats.sound)
	creature.set("creature_kind", kind)
	creature.set("attack_cooldown", stats.cd)
	var _loot := _creature_loot_for(kind)
	creature.set("loot_table", _loot.get("normal", []))
	creature.set("rare_loot_table", _loot.get("rare", []))
	creature.set("star_level", creature_stars)
	if stats.has("flying") and stats.flying:
		creature.set("is_flying", true)
	if stats.has("passive") and stats.passive:
		creature.set("is_passive", true)

	# Try loading a 3D model for this creature kind
	var model_path: String = _creature_model_paths.get(kind, "") as String
	var model_loaded := false

	if model_path != "" and ResourceLoader.exists(model_path):
		var scene: PackedScene = load(model_path) as PackedScene
		if scene:
			var model_node := scene.instantiate()
			model_node.name = "CreatureModel"
			var s: float = _creature_model_scales.get(kind, 1.0) as float
			model_node.scale = Vector3(s, s, s)
			creature.add_child(model_node)
			creature.set("use_3d_model", true)
			creature.set("_model_node", model_node)
			var yaw_off: float = _creature_yaw_offsets.get(kind, 0.0) as float
			if yaw_off != 0.0:
				creature.set("_model_yaw_offset", yaw_off)
			model_loaded = true

			# DEBUG: dump model structure
			var mesh_count := 0
			for child in model_node.find_children("*", "MeshInstance3D", true):
				var mi: MeshInstance3D = child as MeshInstance3D
				var surf_count := mi.mesh.get_surface_count() if mi.mesh else 0
				var mat_info := ""
				for si in surf_count:
					var mat := mi.get_active_material(si)
					mat_info += " surf%d=%s" % [si, mat.get_class() if mat else "NULL"]
				if _DEBUG_LOG: print("[ZONE DEBUG] %s mesh '%s': visible=%s surfs=%d%s" % [kind, mi.name, mi.visible, surf_count, mat_info])
				mesh_count += 1
			if mesh_count == 0:
				if _DEBUG_LOG: print("[ZONE DEBUG] %s: NO MeshInstance3D found! Children: %s" % [kind, str(_list_children_recursive(model_node))])
			else:
				if _DEBUG_LOG: print("[ZONE DEBUG] %s: %d meshes found, scale=%.1f" % [kind, mesh_count, s])

			var anim_player := _find_anim_player(model_node)
			if anim_player:
				creature.set("_model_anim_player", anim_player)

			var tex_path: String = _creature_texture_paths.get(kind, "") as String
			var fallback_tex: Texture2D = null
			if tex_path != "" and ResourceLoader.exists(tex_path):
				fallback_tex = load(tex_path) as Texture2D
			_fix_model_materials(model_node, fallback_tex)
			_apply_nearest_filter_recursive(model_node)

	if not model_loaded:
		if _DEBUG_LOG: print("[ZONE] Skipping creature '%s' — no 3D model loaded" % kind)
		creature.queue_free()
		return null

	if false:
		var tex_dict: Dictionary = stats.tex
		creature.set("sprite_textures", tex_dict)
		if stats.has("walk_tex") and not stats.walk_tex.is_empty():
			creature.set("walk_frames", stats.walk_tex)
		if stats.has("run_tex") and not stats.run_tex.is_empty():
			creature.set("run_frames", stats.run_tex)
		if stats.has("atk_tex") and not stats.atk_tex.is_empty():
			creature.set("attack_frames", stats.atk_tex)
		if stats.has("idle_tex") and not stats.idle_tex.is_empty():
			creature.set("idle_frames", stats.idle_tex)
		var sprite := Sprite3D.new()
		sprite.name = "BodySprite"
		var initial_tex: Texture2D = tex_dict.get("south", null) as Texture2D
		sprite.texture = initial_tex
		sprite.pixel_size = 0.04
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.transparent = true
		sprite.shaded = true
		sprite.double_sided = true
		sprite.no_depth_test = false
		sprite.position.y = stats.sprite_y

		var smat := _make_creature_sprite_mat(initial_tex)
		if smat:
			sprite.material_override = smat
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		else:
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS

		creature.add_child(sprite)

	var col_r: float = stats.col_r
	var col_h: float = stats.col_h
	var col_y: float = stats.col_y

	_add_ground_shadow(creature, col_r * 1.6, col_r * 1.1)

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = col_r
	shape.height = col_h
	col.shape = shape
	col.position.y = col_y
	creature.add_child(col)

	return creature


static func _compute_node_aabb(node: Node3D) -> AABB:
	var combined := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi and mi.mesh:
			var xform := _get_relative_transform(node, mi)
			var mesh_aabb := mi.mesh.get_aabb()
			var corners: Array[Vector3] = []
			for ix in 2:
				for iy in 2:
					for iz in 2:
						corners.append(xform * Vector3(
							mesh_aabb.position.x + mesh_aabb.size.x * ix,
							mesh_aabb.position.y + mesh_aabb.size.y * iy,
							mesh_aabb.position.z + mesh_aabb.size.z * iz))
			for ci in corners.size():
				if first:
					combined = AABB(corners[ci], Vector3.ZERO)
					first = false
				else:
					combined = combined.expand(corners[ci])
	return combined


static func _get_relative_transform(root: Node3D, child: Node3D) -> Transform3D:
	var xform := child.transform
	var current := child.get_parent()
	while current != null and current != root:
		if current is Node3D:
			xform = (current as Node3D).transform * xform
		current = current.get_parent()
	return xform


static func _list_children_recursive(node: Node, depth: int = 0) -> Array:
	var result := []
	for child in node.get_children():
		result.append("%s%s (%s)" % ["  ".repeat(depth), child.name, child.get_class()])
		result.append_array(_list_children_recursive(child, depth + 1))
	return result


static func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found:
			return found
	return null


static func _apply_nearest_filter_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for surf_idx in mi.mesh.get_surface_count() if mi.mesh else 0:
			var mat := mi.get_active_material(surf_idx)
			if mat is StandardMaterial3D:
				(mat as StandardMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for child in node.get_children():
		_apply_nearest_filter_recursive(child)


## Creature basecolor texture paths (Tripo exports these alongside the GLB).
static var _creature_texture_paths: Dictionary = {
	&"cyclops": "res://models/creatures/Cyclops/Cyclops_armoredcreature3dmodel_basecolor.jpg",
	&"minotaur": "res://models/creatures/Minotaur/Minotaur_Minotaur_basecolor.jpg",
	&"orc_brute": "res://models/creatures/Orc Brute/Orc+Brute_OrcBrute_basecolor.jpg",
	&"goblin": "res://models/creatures/Small Goblin/Goblin+Small_GoblinSmall_basecolor.jpg",
}


## Force-override all materials on a model with a simple StandardMaterial3D.
## This bypasses any broken Tripo/Meshy shader materials that render invisible.
## For models with a known basecolor texture, applies it as albedo.
## For models without (like existing Meshy AI creatures), tries to preserve
## the original material if it's already a working StandardMaterial3D.
static func _fix_model_materials(node: Node, fallback_tex: Texture2D = null) -> void:
	_fix_model_materials_inner(node, fallback_tex, fallback_tex != null)

static func _fix_model_materials_inner(node: Node, fallback_tex: Texture2D, force_override: bool) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.visible = true
		if mi.mesh and force_override:
			var new_mat := StandardMaterial3D.new()
			new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			if fallback_tex:
				new_mat.albedo_texture = fallback_tex
			else:
				new_mat.albedo_color = Color(0.6, 0.5, 0.4)
			mi.material_override = new_mat
		elif mi.mesh:
			# For existing working models, just fix emission/transparency issues
			for surf_idx in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(surf_idx)
				if mat is StandardMaterial3D:
					var smat := mat as StandardMaterial3D
					if smat.emission_enabled:
						if smat.emission_texture and not smat.albedo_texture:
							smat.albedo_texture = smat.emission_texture
						if smat.emission != Color.BLACK and smat.albedo_color == Color.BLACK:
							smat.albedo_color = smat.emission
						smat.emission_enabled = false
					if smat.albedo_color.a < 0.1:
						smat.albedo_color.a = 1.0
					if smat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
						smat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	for child in node.get_children():
		_fix_model_materials_inner(child, fallback_tex, force_override)


static func _set_visibility_range(node: Node, max_dist: float) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.visibility_range_end = max_dist
		gi.visibility_range_end_margin = 5.0
		gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	for child in node.get_children():
		_set_visibility_range(child, max_dist)


static var _creature_tints: Dictionary = {
	&"black_bear": Color(0.15, 0.12, 0.10),
	&"boar": Color(0.40, 0.26, 0.15),
	&"grizzly": Color(0.50, 0.33, 0.18),
}

static func _apply_creature_tint(kind: StringName, model_node: Node3D) -> void:
	var tint: Color = _creature_tints.get(kind, Color.WHITE) as Color
	if tint == Color.WHITE:
		return
	_tint_meshes_recursive(model_node, tint)

static func _tint_meshes_recursive(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mi.material_override = mat
	for child in node.get_children():
		_tint_meshes_recursive(child, tint)



static func _create_horse(rng: RandomNumberGenerator = null, override_stars: int = -1) -> StaticBody3D:
	_ensure_textures()
	var horse := StaticBody3D.new()
	horse.add_to_group(&"horses")
	horse.collision_layer = 4
	horse.collision_mask = 1

	var star_level := override_stars if override_stars >= 0 else (_roll_creature_stars(rng) if rng else 0)
	horse.set_meta("star_level", star_level)
	var base_stamina := 100.0 + star_level * 20.0
	horse.set_meta("max_stamina", base_stamina)

	var model_loaded := false
	var model_path := "res://models/creatures/Horse/Meshy_AI_model_Animation_Walking_withSkin.glb"
	if ResourceLoader.exists(model_path):
		var scene: PackedScene = load(model_path) as PackedScene
		if scene:
			var model_node := scene.instantiate()
			model_node.name = "CreatureModel"
			var s := 350.0
			model_node.scale = Vector3(s, s, s)
			model_node.position.y = 0.0
			horse.add_child(model_node)
			horse.set_meta("use_3d_model", true)
			horse.set_meta("model_node", model_node)
			model_loaded = true
			var anim_player := _find_anim_player(model_node)
			if anim_player:
				for anim_name in anim_player.get_animation_list():
					var anim := anim_player.get_animation(anim_name)
					if anim:
						for i in range(anim.get_track_count() - 1, -1, -1):
							if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
								anim.remove_track(i)
				horse.set_meta("model_anim_player", anim_player)
			_fix_model_materials(model_node)
			_apply_nearest_filter_recursive(model_node)
			_set_visibility_range(model_node, 60.0)

	if not model_loaded:
		var sprite := Sprite3D.new()
		sprite.name = "BodySprite"
		var tex: Texture2D = _tex_horse.get("south", null) as Texture2D
		if not tex:
			var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.5, 0.35, 0.15))
			tex = ImageTexture.create_from_image(img)
		sprite.texture = tex
		sprite.pixel_size = 0.04
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.transparent = true
		sprite.shaded = true
		sprite.double_sided = true
		sprite.no_depth_test = false
		sprite.position.y = 0.8
		var smat := _make_creature_sprite_mat(tex)
		if smat:
			sprite.material_override = smat
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		else:
			sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		horse.add_child(sprite)

	_add_ground_shadow(horse, 0.7, 0.5)

	horse.set_meta("sprite_textures", _tex_horse)
	horse.set_meta("walk_frames", _tex_horse_walk)
	horse.set_meta("run_frames", _tex_horse_run)

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.5
	shape.height = 1.4
	col.shape = shape
	col.position.y = 0.7
	horse.add_child(col)

	var label_fs := 48
	var label_px := 0.009
	var has_stars := star_level > 0
	var star_str := (" " + "★".repeat(star_level)) if has_stars else ""

	var name_lbl := Label3D.new()
	name_lbl.name = "HorseNameplate"
	name_lbl.text = "Horse"
	name_lbl.font_size = label_fs
	name_lbl.pixel_size = label_px
	name_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_lbl.no_depth_test = false
	name_lbl.modulate = Color.WHITE
	name_lbl.outline_modulate = Color(0, 0, 0, 0.95)
	name_lbl.outline_size = 12
	name_lbl.render_priority = 1
	if has_stars:
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var stars_lbl: Label3D = null
	if has_stars:
		stars_lbl = Label3D.new()
		stars_lbl.name = "HorseStarsLabel"
		stars_lbl.text = star_str
		stars_lbl.font_size = label_fs
		stars_lbl.pixel_size = label_px
		stars_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		stars_lbl.no_depth_test = false
		stars_lbl.modulate = ItemDatabase.get_rarity_color(star_level)
		stars_lbl.outline_modulate = Color(0, 0, 0, 0.95)
		stars_lbl.outline_size = 12
		stars_lbl.render_priority = 1
		stars_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var ui_root := Node3D.new()
	ui_root.name = "HorseNameplateRoot"
	ui_root.position.y = 5.0

	if has_stars:
		var font: Font = name_lbl.font if name_lbl.font else ThemeDB.fallback_font
		var name_w := font.get_string_size("Horse", HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs).x * label_px
		var star_w := font.get_string_size(star_str, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs).x * label_px
		var em := float(label_fs) * label_px
		var junction_x := (name_w - star_w) * 0.5 + em * 0.22
		name_lbl.position = Vector3(junction_x, 0.0, 0)
		stars_lbl.position = Vector3(junction_x, 0.0, 0)
		ui_root.add_child(stars_lbl)
	else:
		name_lbl.position.y = 0.0
	ui_root.add_child(name_lbl)

	horse.add_child(ui_root)

	return horse


## Roll a star level (0-5) for a creature. 0 = no stars (most common).
## Weights: ~60% no stars, ~22% 1*, ~10% 2*, ~5% 3*, ~2% 4*, ~1% 5*
static func _roll_creature_stars(rng: RandomNumberGenerator) -> int:
	const WEIGHTS: Array[float] = [0.60, 0.22, 0.10, 0.05, 0.02, 0.01]
	var roll := rng.randf() if rng else randf()
	var cumulative := 0.0
	for i in WEIGHTS.size():
		cumulative += WEIGHTS[i]
		if roll < cumulative:
			return i
	return 0


## Pick a creature kind string for the given biome, using rng for variety.
static func _pick_creature_kind(biome: StringName, rng: RandomNumberGenerator) -> StringName:
	var roll := rng.randf() if rng else randf()
	if roll < 0.125:
		return &"lion"
	elif roll < 0.250:
		return &"cyclops"
	elif roll < 0.375:
		return &"minotaur"
	elif roll < 0.500:
		return &"orc_brute"
	elif roll < 0.625:
		return &"goblin"
	elif roll < 0.750:
		return &"grizzly"
	elif roll < 0.875:
		return &"hawk"
	else:
		return &"boar"


## All creature stats in one place, keyed by creature kind.
static func _creature_stats(kind: StringName) -> Dictionary:
	# {name, hp, dmg, spd, cd, sound, tex, sprite_y, col_r, col_h, col_y}
	match kind:
		&"boar":
			return {name="Boar", hp=50.0, dmg=10.0, spd=2.3, cd=2.5, sound="boar",
				tex=_tex_boar, walk_tex=_tex_boar_walk, run_tex=_tex_boar_run,
				sprite_y=0.6, col_r=0.35, col_h=1.2, col_y=0.6}
		&"black_bear":
			return {name="Black Bear", hp=90.0, dmg=18.0, spd=2.8, cd=2.2, sound="bear",
				tex=_tex_blackbear, walk_tex=_tex_blackbear_walk, run_tex=_tex_blackbear_run, atk_tex=_tex_blackbear_attack,
				sprite_y=0.7, col_r=0.4, col_h=1.4, col_y=0.7}
		&"wolf":
			return {name="Wolf", hp=70.0, dmg=15.0, spd=3.5, cd=2.0, sound="wolf",
				tex=_tex_boar, walk_tex=_tex_boar_walk, run_tex=_tex_boar_run, atk_tex={},
				sprite_y=0.6, col_r=0.35, col_h=1.2, col_y=0.6}
		&"grizzly":
			return {name="Grizzly Bear", hp=180.0, dmg=30.0, spd=2.6, cd=2.0, sound="bear",
				tex=_tex_grizzly, walk_tex=_tex_grizzly_walk, run_tex=_tex_grizzly_run, atk_tex=_tex_grizzly_attack,
				sprite_y=0.8, col_r=0.5, col_h=1.6, col_y=0.8}
		&"moose":
			return {name="Moose", hp=220.0, dmg=35.0, spd=3.0, cd=2.0, sound="bear",
				tex=_tex_moose, walk_tex=_tex_moose_walk, run_tex=_tex_moose_run,
				sprite_y=0.9, col_r=0.5, col_h=1.8, col_y=0.9, passive=true}
		&"mama_bear":
			return {name="Mama Bear", hp=250.0, dmg=40.0, spd=2.8, cd=1.8, sound="bear",
				tex=_tex_mamabear, walk_tex=_tex_mamabear_walk, run_tex=_tex_mamabear_run,
				sprite_y=0.8, col_r=0.5, col_h=1.6, col_y=0.8}
		&"tiger":
			return {name="Striped Tiger", hp=200.0, dmg=38.0, spd=3.6, cd=1.5, sound="lion",
				tex=_tex_tiger, walk_tex=_tex_tiger_walk, run_tex=_tex_tiger_run, atk_tex=_tex_tiger_attack,
				sprite_y=0.7, col_r=0.45, col_h=1.4, col_y=0.7}
		&"crab":
			return {name="Crab", hp=90.0, dmg=20.0, spd=2.6, cd=2.2, sound="boar",
				tex=_tex_boar, sprite_y=0.6, col_r=0.35, col_h=1.2, col_y=0.6}
		&"mountain_goat":
			return {name="Mountain Goat", hp=110.0, dmg=25.0, spd=2.8, cd=1.8, sound="boar",
				tex=_tex_skeleton, sprite_y=0.6, col_r=0.35, col_h=1.2, col_y=0.6}
		&"hyena":
			return {name="Hyena", hp=130.0, dmg=30.0, spd=3.2, cd=1.5, sound="hyena",
				tex=_tex_boar, sprite_y=0.6, col_r=0.35, col_h=1.2, col_y=0.6}
		&"lion":
			return {name="Lion", hp=200.0, dmg=35.0, spd=3.4, cd=1.5, sound="lion",
				tex=_tex_lion, walk_tex=_tex_lion_walk, run_tex=_tex_lion_run, atk_tex=_tex_lion_attack,
				sprite_y=0.8, col_r=0.5, col_h=1.6, col_y=0.8}
		&"hawk":
			return {name="Hawk", hp=40.0, dmg=8.0, spd=5.5, cd=2.5, sound="hawk",
				tex=_tex_hawk, run_tex=_tex_hawk_fly, atk_tex=_tex_hawk_attack,
				sprite_y=0.5, col_r=0.3, col_h=0.8, col_y=0.4,
				flying=true, passive=true}
		&"seagull":
			return {name="Seagull", hp=25.0, dmg=0.0, spd=4.5, cd=99.0, sound="hawk",
				tex=_tex_seagull, run_tex=_tex_seagull_fly, atk_tex={},
				idle_tex=_tex_seagull_idle,
				sprite_y=0.4, col_r=0.25, col_h=0.6, col_y=0.3,
				flying=true, passive=true}
		&"ghoul":
			return {name="Ghoul", hp=150.0, dmg=35.0, spd=2.6, cd=1.3, sound="lion",
				tex=_tex_skeleton, sprite_y=0.6, col_r=0.35, col_h=1.2, col_y=0.6}
		&"fire_imp":
			return {name="Fire Imp", hp=170.0, dmg=40.0, spd=2.9, cd=1.2, sound="lion",
				tex=_tex_skeleton, sprite_y=0.6, col_r=0.35, col_h=1.2, col_y=0.6}
		&"frost_wraith":
			return {name="Frost Wraith", hp=190.0, dmg=45.0, spd=3.1, cd=1.0, sound="lion",
				tex=_tex_skeleton, sprite_y=0.6, col_r=0.35, col_h=1.2, col_y=0.6}
		&"cyclops":
			return {name="Cyclops", hp=300.0, dmg=45.0, spd=1.8, cd=2.5, sound="bear",
				tex=_tex_boar, sprite_y=1.0, col_r=0.6, col_h=2.0, col_y=1.0}
		&"minotaur":
			return {name="Minotaur", hp=250.0, dmg=40.0, spd=2.4, cd=1.8, sound="bear",
				tex=_tex_boar, sprite_y=0.9, col_r=0.55, col_h=1.8, col_y=0.9}
		&"orc_brute":
			return {name="Orc Brute", hp=160.0, dmg=28.0, spd=2.5, cd=2.0, sound="lion",
				tex=_tex_boar, sprite_y=0.7, col_r=0.4, col_h=1.5, col_y=0.75}
		&"goblin":
			return {name="Goblin", hp=60.0, dmg=12.0, spd=3.5, cd=1.5, sound="boar",
				tex=_tex_boar, sprite_y=0.4, col_r=0.25, col_h=0.8, col_y=0.4}
		_:
			return {name="Creature", hp=50.0, dmg=10.0, spd=2.0, cd=2.0, sound="boar",
				tex=_tex_boar, sprite_y=0.6, col_r=0.35, col_h=1.2, col_y=0.6}


static func _creature_loot_for(kind: StringName) -> Dictionary:
	match kind:
		# ── Animals ──────────────────────────────────────────────────────
		&"boar":
			return {"normal": [
				{"id": &"leather", "min": 1, "max": 2, "chance": 0.8},
				{"id": &"meat", "min": 1, "max": 2, "chance": 0.9},
			], "rare": [
				{"id": &"trophy_boar", "min": 1, "max": 1, "chance": 0.08},
			]}
		&"black_bear":
			return {"normal": [
				{"id": &"leather", "min": 2, "max": 4, "chance": 0.9},
				{"id": &"meat", "min": 2, "max": 4, "chance": 0.85},
				{"id": &"bone", "min": 1, "max": 2, "chance": 0.3},
			], "rare": [
				{"id": &"thick_hide", "min": 1, "max": 1, "chance": 0.08},
			]}
		&"grizzly":
			return {"normal": [
				{"id": &"leather", "min": 3, "max": 6, "chance": 0.9},
				{"id": &"meat", "min": 3, "max": 5, "chance": 0.9},
				{"id": &"bone", "min": 2, "max": 4, "chance": 0.5},
			], "rare": [
				{"id": &"thick_hide", "min": 1, "max": 2, "chance": 0.12},
				{"id": &"fang", "min": 1, "max": 1, "chance": 0.06},
			]}
		&"wolf":
			return {"normal": [
				{"id": &"leather", "min": 1, "max": 3, "chance": 0.7},
				{"id": &"meat", "min": 1, "max": 2, "chance": 0.6},
				{"id": &"bone", "min": 1, "max": 2, "chance": 0.4},
			], "rare": [
				{"id": &"fang", "min": 1, "max": 1, "chance": 0.10},
			]}
		&"lion":
			return {"normal": [
				{"id": &"leather", "min": 3, "max": 5, "chance": 0.9},
				{"id": &"meat", "min": 2, "max": 5, "chance": 0.85},
				{"id": &"bone", "min": 2, "max": 3, "chance": 0.5},
			], "rare": [
				{"id": &"fang", "min": 1, "max": 2, "chance": 0.10},
				{"id": &"thick_hide", "min": 1, "max": 1, "chance": 0.06},
			]}
		&"moose":
			return {"normal": [
				{"id": &"leather", "min": 3, "max": 6, "chance": 0.9},
				{"id": &"meat", "min": 4, "max": 7, "chance": 0.95},
				{"id": &"bone", "min": 2, "max": 4, "chance": 0.6},
			], "rare": [
				{"id": &"thick_hide", "min": 1, "max": 2, "chance": 0.10},
			]}
		&"mama_bear":
			return {"normal": [
				{"id": &"leather", "min": 4, "max": 7, "chance": 0.95},
				{"id": &"meat", "min": 3, "max": 6, "chance": 0.9},
				{"id": &"bone", "min": 2, "max": 5, "chance": 0.7},
			], "rare": [
				{"id": &"thick_hide", "min": 1, "max": 3, "chance": 0.15},
				{"id": &"fang", "min": 1, "max": 2, "chance": 0.08},
			]}
		&"tiger":
			return {"normal": [
				{"id": &"leather", "min": 3, "max": 5, "chance": 0.9},
				{"id": &"meat", "min": 2, "max": 5, "chance": 0.85},
				{"id": &"bone", "min": 2, "max": 4, "chance": 0.6},
			], "rare": [
				{"id": &"fang", "min": 1, "max": 2, "chance": 0.10},
				{"id": &"thick_hide", "min": 1, "max": 1, "chance": 0.08},
			]}
		# ── Birds / Coastal ──────────────────────────────────────────────
		&"hawk":
			return {"normal": [
				{"id": &"feather", "min": 1, "max": 3, "chance": 0.9},
				{"id": &"meat", "min": 1, "max": 1, "chance": 0.6},
			], "rare": [
				{"id": &"fang", "min": 1, "max": 1, "chance": 0.04},
			]}
		&"seagull":
			return {"normal": [
				{"id": &"feather", "min": 1, "max": 2, "chance": 0.8},
				{"id": &"raw_fish", "min": 1, "max": 1, "chance": 0.3},
			], "rare": []}
		&"crab":
			return {"normal": [
				{"id": &"meat", "min": 1, "max": 3, "chance": 0.8},
				{"id": &"flint", "min": 1, "max": 2, "chance": 0.3},
			], "rare": []}
		&"mountain_goat":
			return {"normal": [
				{"id": &"leather", "min": 1, "max": 2, "chance": 0.6},
				{"id": &"bone", "min": 1, "max": 2, "chance": 0.5},
			], "rare": [
				{"id": &"thick_hide", "min": 1, "max": 1, "chance": 0.06},
			]}
		&"hyena":
			return {"normal": [
				{"id": &"bone", "min": 2, "max": 4, "chance": 0.7},
				{"id": &"leather", "min": 1, "max": 3, "chance": 0.5},
			], "rare": [
				{"id": &"fang", "min": 1, "max": 1, "chance": 0.08},
			]}
		# ── Humanoids / Monsters (drop gold) ─────────────────────────────
		&"goblin":
			return {"normal": [
				{"id": &"bone", "min": 1, "max": 2, "chance": 0.7},
				{"id": &"flint", "min": 1, "max": 2, "chance": 0.5},
			], "rare": [
				{"id": &"gold", "min": 1, "max": 3, "chance": 0.40, "no_stars": true},
				{"id": &"chest_key", "min": 1, "max": 1, "chance": 0.08, "no_stars": true},
			]}
		&"orc_brute":
			return {"normal": [
				{"id": &"leather", "min": 2, "max": 4, "chance": 0.8},
				{"id": &"bone", "min": 1, "max": 3, "chance": 0.6},
			], "rare": [
				{"id": &"gold", "min": 2, "max": 6, "chance": 0.50, "no_stars": true},
				{"id": &"ancient_bone", "min": 1, "max": 1, "chance": 0.06},
				{"id": &"chest_key", "min": 1, "max": 1, "chance": 0.10, "no_stars": true},
			]}
		&"ghoul":
			return {"normal": [
				{"id": &"bone", "min": 2, "max": 5, "chance": 0.9},
			], "rare": [
				{"id": &"gold", "min": 1, "max": 4, "chance": 0.35, "no_stars": true},
				{"id": &"trophy_skeleton", "min": 1, "max": 1, "chance": 0.08},
				{"id": &"ancient_bone", "min": 1, "max": 1, "chance": 0.05},
				{"id": &"chest_key", "min": 1, "max": 1, "chance": 0.07, "no_stars": true},
			]}
		&"fire_imp":
			return {"normal": [
				{"id": &"flint", "min": 2, "max": 4, "chance": 0.7},
				{"id": &"bone", "min": 1, "max": 3, "chance": 0.6},
			], "rare": [
				{"id": &"gold", "min": 2, "max": 5, "chance": 0.40, "no_stars": true},
				{"id": &"ember_stone", "min": 1, "max": 1, "chance": 0.08},
				{"id": &"chest_key", "min": 1, "max": 1, "chance": 0.07, "no_stars": true},
			]}
		&"frost_wraith":
			return {"normal": [
				{"id": &"bone", "min": 2, "max": 4, "chance": 0.7},
				{"id": &"leather", "min": 1, "max": 3, "chance": 0.5},
			], "rare": [
				{"id": &"gold", "min": 1, "max": 5, "chance": 0.35, "no_stars": true},
				{"id": &"frost_shard", "min": 1, "max": 1, "chance": 0.08},
				{"id": &"chest_key", "min": 1, "max": 1, "chance": 0.07, "no_stars": true},
			]}
		&"cyclops":
			return {"normal": [
				{"id": &"bone", "min": 3, "max": 6, "chance": 0.9},
				{"id": &"leather", "min": 2, "max": 4, "chance": 0.5},
			], "rare": [
				{"id": &"gold", "min": 5, "max": 12, "chance": 0.55, "no_stars": true},
				{"id": &"ancient_bone", "min": 1, "max": 2, "chance": 0.10},
				{"id": &"chest_key", "min": 1, "max": 1, "chance": 0.12, "no_stars": true},
			]}
		&"minotaur":
			return {"normal": [
				{"id": &"leather", "min": 3, "max": 5, "chance": 0.9},
				{"id": &"bone", "min": 2, "max": 5, "chance": 0.7},
				{"id": &"meat", "min": 2, "max": 4, "chance": 0.6},
			], "rare": [
				{"id": &"gold", "min": 4, "max": 10, "chance": 0.50, "no_stars": true},
				{"id": &"ancient_bone", "min": 1, "max": 1, "chance": 0.08},
				{"id": &"thick_hide", "min": 1, "max": 2, "chance": 0.06},
				{"id": &"chest_key", "min": 1, "max": 1, "chance": 0.10, "no_stars": true},
			]}
		_:
			return {"normal": [{"id": &"bone", "min": 1, "max": 1, "chance": 0.5}], "rare": []}


# ═══════════════════════════════════════════════════════════════════════════════
#  FISH (simple water sprites for seagull interaction)
# ═══════════════════════════════════════════════════════════════════════════════

static func _create_fish(rng: RandomNumberGenerator) -> Node3D:
	_ensure_textures()
	var root := Node3D.new()
	root.name = "Fish"
	root.set_script(_FishIdle)
	root.add_to_group(&"fish")

	var model_loaded := false
	var model_path := "res://models/creatures/fish.gltf"
	if ResourceLoader.exists(model_path):
		var scene: PackedScene = load(model_path) as PackedScene
		if scene:
			var model_node := scene.instantiate()
			model_node.name = "CreatureModel"
			var s := 0.8
			model_node.scale = Vector3(s, s, s)
			model_node.position.y = 0.1
			root.add_child(model_node)
			root.set_meta("use_3d_model", true)
			model_loaded = true
			var anim_player := _find_anim_player(model_node)
			if anim_player and anim_player.has_animation("animation.idle"):
				anim_player.play("animation.idle")
			_apply_nearest_filter_recursive(model_node)

	if not model_loaded:
		var sprite := Sprite3D.new()
		sprite.name = "BodySprite"
		var tex: Texture2D = _tex_fish.get("south", null) as Texture2D
		if tex:
			sprite.texture = tex
		else:
			var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.3, 0.5, 0.7))
			sprite.texture = ImageTexture.create_from_image(img)
		sprite.pixel_size = 0.02
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		sprite.transparent = true
		sprite.shaded = true
		sprite.double_sided = true
		sprite.position.y = 0.15
		root.add_child(sprite)

	root.set_meta("sprite_textures", _tex_fish)
	root.set_meta("bob_phase", rng.randf_range(0.0, TAU))
	root.set("idle_frames", _tex_fish_idle)
	return root


# ═══════════════════════════════════════════════════════════════════════════════
#  CAVE SPAWNING
# ═══════════════════════════════════════════════════════════════════════════════

static func _try_spawn_cave(
	zone_root: Node3D,
	coord: Vector2i,
	rng: RandomNumberGenerator,
	origin_x: float,
	origin_z: float,
	height_func: Callable,
) -> void:
	if rng.randf() > 0.066:  # ~1 in 15 zones (2x previous rate)
		return

	# Sample the zone center to find elevated terrain (a hill)
	var cx := origin_x + ZONE_SIZE * 0.5
	var cz := origin_z + ZONE_SIZE * 0.5
	var center_h := float(height_func.call(cx, cz))
	if center_h < 3.0:
		return  # not hilly enough

	# Find the highest point in a small grid to locate the hill peak
	var peak_x := cx
	var peak_z := cz
	var peak_h := center_h
	var step := ZONE_SIZE * 0.25
	var offsets: PackedFloat64Array = [-1.0, 0.0, 1.0]
	for sx: float in offsets:
		for sz: float in offsets:
			var px := cx + sx * step
			var pz := cz + sz * step
			var ph := float(height_func.call(px, pz))
			if ph > peak_h:
				peak_h = ph
				peak_x = px
				peak_z = pz

	if peak_h < 6.0:
		return  # hill not tall enough for a cave

	# Find the steepest downhill direction from the peak for the cave entrance
	var best_dir := Vector3.ZERO
	var best_drop := 0.0
	var sample_dist := 6.0
	for angle_i: int in 8:
		var angle := float(angle_i) * TAU / 8.0
		var dx := cos(angle) * sample_dist
		var dz := sin(angle) * sample_dist
		var sh := float(height_func.call(peak_x + dx, peak_z + dz))
		var drop := peak_h - sh
		if drop > best_drop:
			best_drop = drop
			best_dir = Vector3(dx, 0.0, dz).normalized()

	if best_drop < 2.0 or best_dir.length_squared() < 0.01:
		return  # not enough slope for a visible entrance

	# Place the entrance partway down the slope from the peak
	var entrance_wx := peak_x + best_dir.x * 5.0
	var entrance_wz := peak_z + best_dir.z * 5.0
	var entrance_h := _hg_snap_height(entrance_wx, entrance_wz)
	if entrance_h < _WATER_LEVEL + 1.5:
		return

	var entrance_pos := Vector3(
		entrance_wx - origin_x,
		entrance_h,
		entrance_wz - origin_z,
	)

	var entrance := CaveGenerator.create_entrance_marker(best_dir)
	zone_root.add_child(entrance)
	entrance.position = entrance_pos


# ═══════════════════════════════════════════════════════════════════════════════
#  GOBLIN CAMP SPAWNING (mountain-top POIs)
# ═══════════════════════════════════════════════════════════════════════════════

const _GOBLIN_CAMP_LOOT_MATERIALS: Array[Dictionary] = [
	{"id": &"gold", "min": 3, "max": 10},
	{"id": &"bone", "min": 2, "max": 5},
	{"id": &"flint", "min": 2, "max": 6},
	{"id": &"leather", "min": 2, "max": 5},
	{"id": &"iron_ore", "min": 1, "max": 4},
	{"id": &"copper_ore", "min": 2, "max": 6},
	{"id": &"resin", "min": 2, "max": 4},
	{"id": &"ember_stone", "min": 1, "max": 2},
]

const _GOBLIN_CAMP_LOOT_GEAR: Array[StringName] = [
	&"stone_sword", &"stone_axe", &"stone_pickaxe", &"crude_bow",
	&"bronze_sword", &"bronze_mace", &"iron_sword",
	&"leather_vest", &"leather_pants", &"leather_boots",
	&"chain_chest", &"chain_legs", &"chain_boots",
	&"wood_shield", &"reinforced_shield",
]

const _GOBLIN_CAMP_GEAR_AFFIX_SLOT: Dictionary = {
	&"stone_sword": "sword", &"stone_axe": "axe", &"stone_pickaxe": "pickaxe",
	&"crude_bow": "bow", &"bronze_sword": "sword", &"bronze_mace": "mace",
	&"iron_sword": "sword", &"leather_vest": "chest", &"leather_pants": "legs",
	&"leather_boots": "feet", &"chain_chest": "chest", &"chain_legs": "legs",
	&"chain_boots": "feet", &"wood_shield": "shield", &"reinforced_shield": "shield",
}

const _GOBLIN_CAMP_STAR_WEIGHTS: Array[float] = [0.20, 0.25, 0.25, 0.20, 0.10]


static func _try_spawn_goblin_camp(
	zone_root: Node3D,
	coord: Vector2i,
	rng: RandomNumberGenerator,
	origin_x: float,
	origin_z: float,
	height_func: Callable,
) -> void:
	var cx := origin_x + ZONE_SIZE * 0.5
	var cz := origin_z + ZONE_SIZE * 0.5
	var center_h := float(height_func.call(cx, cz))
	if center_h < 20.0:
		return

	var peak_x := cx
	var peak_z := cz
	var peak_h := center_h
	var step := ZONE_SIZE * 0.25
	var offsets: PackedFloat64Array = [-1.0, 0.0, 1.0]
	for sx: float in offsets:
		for sz: float in offsets:
			var px := cx + sx * step
			var pz := cz + sz * step
			var ph := float(height_func.call(px, pz))
			if ph > peak_h:
				peak_h = ph
				peak_x = px
				peak_z = pz

	if peak_h < 25.0:
		return

	var is_local_max := true
	for angle_i: int in 8:
		var angle := float(angle_i) * TAU / 8.0
		var sx := peak_x + cos(angle) * 8.0
		var sz := peak_z + sin(angle) * 8.0
		if float(height_func.call(sx, sz)) > peak_h + 0.5:
			is_local_max = false
			break
	if not is_local_max:
		return

	# Flatness check: sample 12 points at the hut footprint radius (~15m).
	# Reject if any point drops more than 3m below the peak (mountain edge).
	var flat_ok := true
	for fi: int in 12:
		var fa := float(fi) * TAU / 12.0
		for fr: float in [8.0, 15.0]:
			var fh := float(height_func.call(peak_x + cos(fa) * fr, peak_z + sin(fa) * fr))
			if peak_h - fh > 3.0:
				flat_ok = false
				break
		if not flat_ok:
			break
	if not flat_ok:
		return

	var camp_pos_2d := Vector2(peak_x, peak_z)
	for existing: Vector2 in _goblin_camp_positions:
		if camp_pos_2d.distance_to(existing) < _GOBLIN_CAMP_MIN_DIST:
			return
	_goblin_camp_positions.append(camp_pos_2d)

	var camp_root := Node3D.new()
	camp_root.name = "GoblinCamp"
	camp_root.add_to_group(&"structures")
	var local_x := peak_x - origin_x
	var local_z := peak_z - origin_z
	camp_root.position = Vector3(local_x, peak_h, local_z)
	zone_root.add_child(camp_root)

	_build_goblin_hut(camp_root, rng)
	_build_goblin_campfire(camp_root, rng)
	_build_goblin_camp_chest(camp_root, rng)

	var goblin_count := 10
	for gi in goblin_count:
		var angle := rng.randf_range(0, TAU)
		var radius := rng.randf_range(10.0, 25.0)
		var gx := peak_x + cos(angle) * radius
		var gz := peak_z + sin(angle) * radius
		var gy := float(height_func.call(gx, gz))
		if gy < 3.0:
			continue
		var goblin := _create_enemy(&"hearthlands", rng, &"goblin")
		if goblin:
			zone_root.add_child(goblin)
			goblin.position = Vector3(gx - origin_x, gy + 0.1, gz - origin_z)


static func _build_goblin_hut(camp_root: Node3D, rng: RandomNumberGenerator) -> void:
	PlayerBuilding.ensure_building_materials()
	var wood_mat: StandardMaterial3D = PlayerBuilding._bmat_wood
	var thatch_mat: StandardMaterial3D = PlayerBuilding._bmat_thatch

	var hut := Node3D.new()
	hut.name = "GoblinHut"
	hut.add_to_group(&"structures")

	var floor_size := Vector3(20.0, 0.75, 20.0)
	var floor_mi := MeshInstance3D.new()
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = floor_size
	floor_mi.mesh = floor_mesh
	floor_mi.set_surface_override_material(0, wood_mat)
	floor_mi.position.y = floor_size.y * 0.5
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hut.add_child(floor_mi)

	var wall_h := 11.0
	var wall_thick := 0.75
	var hw := floor_size.x * 0.5
	var hd := floor_size.z * 0.5

	var door_w := 4.0
	var door_h := 5.5
	var half_front := (floor_size.x - door_w) * 0.5

	var wall_data := [
		{"size": Vector3(floor_size.x, wall_h, wall_thick), "pos": Vector3(0, wall_h * 0.5 + floor_size.y, -hd)},
		{"size": Vector3(wall_thick, wall_h, floor_size.z), "pos": Vector3(-hw, wall_h * 0.5 + floor_size.y, 0)},
		{"size": Vector3(wall_thick, wall_h, floor_size.z), "pos": Vector3(hw, wall_h * 0.5 + floor_size.y, 0)},
		{"size": Vector3(half_front, wall_h, wall_thick), "pos": Vector3(-(half_front + door_w) * 0.5, wall_h * 0.5 + floor_size.y, hd)},
		{"size": Vector3(half_front, wall_h, wall_thick), "pos": Vector3((half_front + door_w) * 0.5, wall_h * 0.5 + floor_size.y, hd)},
		{"size": Vector3(door_w, wall_h - door_h, wall_thick), "pos": Vector3(0, door_h + (wall_h - door_h) * 0.5 + floor_size.y, hd)},
	]
	for wd: Dictionary in wall_data:
		var wall_mi := MeshInstance3D.new()
		var wall_mesh := BoxMesh.new()
		wall_mesh.size = wd["size"] as Vector3
		wall_mi.mesh = wall_mesh
		wall_mi.set_surface_override_material(0, wood_mat)
		wall_mi.position = wd["pos"] as Vector3
		wall_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hut.add_child(wall_mi)

	var roof_mi := MeshInstance3D.new()
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(floor_size.x + 3.0, 0.6, floor_size.z + 3.0)
	roof_mi.mesh = roof_mesh
	roof_mi.set_surface_override_material(0, thatch_mat)
	roof_mi.position.y = floor_size.y + wall_h + 0.3
	roof_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	hut.add_child(roof_mi)

	var col := CollisionShape3D.new()
	var col_shape := BoxShape3D.new()
	col_shape.size = Vector3(floor_size.x, wall_h + floor_size.y, floor_size.z)
	col.shape = col_shape
	col.position.y = (wall_h + floor_size.y) * 0.5
	hut.add_child(col)

	hut.position = Vector3(0, 0, 0)
	hut.rotation.y = rng.randf_range(0, TAU)
	camp_root.add_child(hut)


static func _build_goblin_campfire(camp_root: Node3D, rng: RandomNumberGenerator) -> void:
	var fire := Node3D.new()
	fire.name = "GoblinCampfire"
	fire.add_to_group(&"structures")
	fire.add_to_group(&"campfires")
	fire.scale = Vector3(5.0, 5.0, 5.0)

	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.45, 0.42, 0.38)
	stone_mat.roughness = 0.92
	for i in 10:
		var stone := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = rng.randf_range(0.08, 0.14)
		sphere.height = sphere.radius * rng.randf_range(1.2, 1.8)
		sphere.radial_segments = 6
		sphere.rings = 3
		stone.mesh = sphere
		stone.material_override = stone_mat
		var sa := float(i) * TAU / 10.0 + rng.randf_range(-0.15, 0.15)
		stone.position = Vector3(cos(sa) * 0.4, sphere.height * 0.3, sin(sa) * 0.4)
		stone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fire.add_child(stone)

	var log_mat := StandardMaterial3D.new()
	log_mat.albedo_color = Color(0.35, 0.22, 0.10)
	log_mat.roughness = 1.0
	log_mat.emission_enabled = true
	log_mat.emission = Color(0.5, 0.1, 0.0)
	log_mat.emission_energy_multiplier = 0.6
	for i in 6:
		var log_mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = rng.randf_range(0.04, 0.06)
		cyl.bottom_radius = rng.randf_range(0.06, 0.09)
		cyl.height = rng.randf_range(0.45, 0.65)
		cyl.radial_segments = 5
		cyl.rings = 2
		log_mi.mesh = cyl
		log_mi.material_override = log_mat
		var la := float(i) * TAU / 6.0 + rng.randf_range(-0.2, 0.2)
		var tilt := rng.randf_range(0.4, 0.55)
		var outward := rng.randf_range(0.18, 0.25)
		var inward_dir := Vector3(-cos(la), 0.0, -sin(la))
		var lean_y := (Vector3.UP * cos(tilt) + inward_dir * sin(tilt)).normalized()
		var ref := Vector3.FORWARD if absf(lean_y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var lean_x := lean_y.cross(ref).normalized()
		var lean_z := lean_x.cross(lean_y).normalized()
		log_mi.basis = Basis(lean_x, lean_y, lean_z)
		log_mi.position = Vector3(cos(la) * outward, cyl.height * 0.4, sin(la) * outward)
		log_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fire.add_child(log_mi)

	var ember_mi := MeshInstance3D.new()
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
		var fb := StandardMaterial3D.new()
		fb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fb.albedo_color = Color(1.0, 0.4, 0.05)
		fb.emission_enabled = true
		fb.emission = Color(1.0, 0.4, 0.05)
		fb.emission_energy_multiplier = 3.0
		ember_mi.material_override = fb
	fire.add_child(ember_mi)

	var fire_shader := load("res://shaders/fire_flame.gdshader") as Shader
	if fire_shader:
		var inner := MeshInstance3D.new()
		inner.name = "InnerFlame"
		var ic := CylinderMesh.new()
		ic.top_radius = 0.5
		ic.bottom_radius = 0.5
		ic.height = 2.0
		ic.radial_segments = 12
		ic.rings = 8
		inner.mesh = ic
		inner.position.y = 0.08
		inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var imat := ShaderMaterial.new()
		imat.shader = fire_shader
		imat.set_shader_parameter("top_radius", 0.10)
		imat.set_shader_parameter("bottom_radius", 0.2)
		imat.set_shader_parameter("center_radius", 0.22)
		imat.set_shader_parameter("center_position", 0.5)
		imat.set_shader_parameter("cylinder_height", 0.75)
		imat.set_shader_parameter("bottom_curve", 0.6)
		imat.set_shader_parameter("vibrate_amplitude", 0.012)
		imat.set_shader_parameter("vibrate_frequency", 100.0)
		imat.set_shader_parameter("speed", 3.0)
		imat.set_shader_parameter("noise_scale", 3.5)
		imat.set_shader_parameter("brightness", 0.95)
		imat.set_shader_parameter("cutoff_base", 0.18)
		imat.set_shader_parameter("band_steps", 5.0)
		imat.set_shader_parameter("color_core", Color(1.0, 1.0, 0.9))
		imat.set_shader_parameter("color_mid", Color(1.0, 0.7, 0.15))
		imat.set_shader_parameter("color_outer", Color(1.0, 0.35, 0.04))
		imat.set_shader_parameter("color_edge", Color(0.7, 0.12, 0.0))
		inner.material_override = imat
		fire.add_child(inner)

		var outer := MeshInstance3D.new()
		outer.name = "OuterFlame"
		var oc := CylinderMesh.new()
		oc.top_radius = 0.5
		oc.bottom_radius = 0.5
		oc.height = 2.0
		oc.radial_segments = 10
		oc.rings = 6
		outer.mesh = oc
		outer.position.y = 0.04
		outer.scale = Vector3(1.1, 1.05, 1.1)
		outer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var omat := ShaderMaterial.new()
		omat.shader = fire_shader
		omat.set_shader_parameter("top_radius", 0.22)
		omat.set_shader_parameter("bottom_radius", 0.25)
		omat.set_shader_parameter("center_radius", 0.34)
		omat.set_shader_parameter("center_position", 0.55)
		omat.set_shader_parameter("cylinder_height", 0.68)
		omat.set_shader_parameter("bottom_curve", 0.6)
		omat.set_shader_parameter("vibrate_amplitude", 0.024)
		omat.set_shader_parameter("vibrate_frequency", 50.0)
		omat.set_shader_parameter("speed", 2.0)
		omat.set_shader_parameter("noise_scale", 4.0)
		omat.set_shader_parameter("brightness", 0.75)
		omat.set_shader_parameter("cutoff_base", 0.14)
		omat.set_shader_parameter("band_steps", 4.0)
		omat.set_shader_parameter("color_core", Color(1.0, 0.8, 0.25))
		omat.set_shader_parameter("color_mid", Color(1.0, 0.4, 0.06))
		omat.set_shader_parameter("color_outer", Color(0.75, 0.15, 0.0))
		omat.set_shader_parameter("color_edge", Color(0.3, 0.04, 0.0))
		outer.material_override = omat
		fire.add_child(outer)

	var fire_light := OmniLight3D.new()
	fire_light.light_color = Color(1.0, 0.6, 0.2)
	fire_light.light_energy = 8.0
	fire_light.omni_range = 30.0
	fire_light.omni_attenuation = 1.2
	fire_light.shadow_enabled = false
	fire_light.position = Vector3(0, 0.5, 0)
	fire.add_child(fire_light)

	var angle := rng.randf_range(0, TAU)
	var dist := rng.randf_range(16.0, 20.0)
	fire.position = Vector3(cos(angle) * dist, 0, sin(angle) * dist)
	camp_root.add_child(fire)


static func _build_goblin_camp_chest(camp_root: Node3D, rng: RandomNumberGenerator) -> void:
	var chest := StaticBody3D.new()
	chest.name = "GoblinChest"
	chest.collision_layer = 4
	chest.collision_mask = 0
	chest.add_to_group(&"interactables")
	chest.add_to_group(&"chests")
	chest.set_meta("build_id", &"chest")

	var sz := Vector3(1.92, 1.44, 1.2)

	var is_locked := rng.randf() < 0.15
	chest.set_meta("is_locked", is_locked)

	var contents := _fill_goblin_camp_chest(rng, is_locked)
	chest.set_meta("chest_contents", contents)

	var max_stars := VillageGenerator._get_chest_max_stars(contents)
	var chest_color := ItemDatabase.get_rarity_color(max_stars) if max_stars > 0 else Color(0.5, 0.4, 0.2)

	if is_locked:
		_build_locked_chest_visual(chest, sz, chest_color)
	else:
		PlayerBuilding.build_chest_visual(chest, sz)

	VillageGenerator._add_chest_rarity_sheen(chest, contents, sz)

	var col := CollisionShape3D.new()
	var box_col := BoxShape3D.new()
	box_col.size = sz
	col.shape = box_col
	col.position.y = sz.y * 0.5
	chest.add_child(col)

	chest.position = Vector3(1.5, 0, 0)
	chest.rotation.y = PI * 0.5
	camp_root.add_child(chest)


static func _build_locked_chest_visual(structure: Node3D, sz: Vector3, tint: Color) -> void:
	PlayerBuilding.build_chest_visual(structure, sz)

	var body_node: MeshInstance3D = null
	for child in structure.get_children():
		if child is MeshInstance3D and child.name == "Body":
			body_node = child as MeshInstance3D
			break
	if body_node:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(tint.r * 0.6, tint.g * 0.6, tint.b * 0.6)
		mat.roughness = 0.7
		mat.metallic = 0.2
		body_node.set_surface_override_material(0, mat)

	var lock_mi := MeshInstance3D.new()
	lock_mi.name = "LockIcon"
	var lock_mesh := BoxMesh.new()
	lock_mesh.size = Vector3(0.15, 0.2, 0.08)
	lock_mi.mesh = lock_mesh
	var lock_mat := StandardMaterial3D.new()
	lock_mat.albedo_color = Color(0.7, 0.55, 0.1)
	lock_mat.metallic = 0.6
	lock_mat.roughness = 0.3
	lock_mi.set_surface_override_material(0, lock_mat)
	lock_mi.position = Vector3(0.0, sz.y * 0.8, sz.z * 0.5 + 0.05)
	lock_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	structure.add_child(lock_mi)


static func _fill_goblin_camp_chest(rng: RandomNumberGenerator, is_locked: bool) -> Array:
	var slots: Array = []
	slots.resize(32)
	for i in 32:
		slots[i] = {}

	var pool := _GOBLIN_CAMP_LOOT_MATERIALS.duplicate()
	for si in range(pool.size() - 1, 0, -1):
		var sj := rng.randi_range(0, si)
		var tmp: Dictionary = pool[si]
		pool[si] = pool[sj]
		pool[sj] = tmp

	var mat_count := rng.randi_range(2, 4)
	for i in mini(mat_count, pool.size()):
		var entry: Dictionary = pool[i]
		slots[i] = {"item_id": entry["id"], "count": rng.randi_range(entry["min"], entry["max"])}

	var gear_count := 1 + (1 if is_locked else 0)
	for gi in gear_count:
		var gear_id: StringName = _GOBLIN_CAMP_LOOT_GEAR[rng.randi_range(0, _GOBLIN_CAMP_LOOT_GEAR.size() - 1)]
		var stars := _roll_goblin_camp_star(rng)
		if stars > 0:
			var affixes: Array[StringName] = []
			var affix_rolls: Dictionary = {}
			if stars >= 2:
				var slot_key: String = _GOBLIN_CAMP_GEAR_AFFIX_SLOT.get(gear_id, "")
				if slot_key != "":
					affixes = ItemDatabase.roll_affixes(stars, slot_key)
					affix_rolls = ItemDatabase.roll_affix_magnitudes(affixes)
			gear_id = ItemDatabase.make_star_id(gear_id, stars, affixes, affix_rolls)
		var slot_idx := mat_count + gi
		if slot_idx < 32:
			slots[slot_idx] = {"item_id": gear_id, "count": 1}

	return slots


static func _roll_goblin_camp_star(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	var cumulative := 0.0
	for i in _GOBLIN_CAMP_STAR_WEIGHTS.size():
		cumulative += _GOBLIN_CAMP_STAR_WEIGHTS[i]
		if roll < cumulative:
			return i + 1
	return 5


static func _get_saved_horses() -> Array:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		return []
	var wss_nodes := tree.get_nodes_in_group(&"world_state_sync")
	if wss_nodes.is_empty():
		return []
	var wss: Node = wss_nodes[0]
	if wss.has_method(&"get_saved_horses"):
		return wss.get_saved_horses()
	return []


static func _restore_saved_horses_in_zone(zone_root: Node, coord: Vector2i, height_func: Callable) -> void:
	var saved := _get_saved_horses()
	if saved.is_empty():
		return
	var origin_x: float = coord.x * ZONE_SIZE
	var origin_z: float = coord.y * ZONE_SIZE
	for entry in saved:
		var hx: float = float(entry.get("x", 0.0))
		var hz: float = float(entry.get("z", 0.0))
		var zx := int(floorf(hx / ZONE_SIZE))
		var zz := int(floorf(hz / ZONE_SIZE))
		if zx != coord.x or zz != coord.y:
			continue
		var star: int = int(entry.get("star_level", 0))
		var horse := _create_horse(null, star)
		horse.set_meta("spawn_zone", coord)
		zone_root.add_child(horse)
		var local_x := hx - origin_x
		var local_z := hz - origin_z
		var snap_y := _hg_snap_height(hx, hz)
		horse.position = Vector3(local_x, snap_y, local_z)


# ─── Water Plants ─────────────────────────────────────────────────────────────

static func _ensure_water_plants() -> void:
	if _water_plants_ready:
		return
	_water_plants_ready = true

	# Lily pad — flat green disc
	_lily_pad_mesh = _gen_lily_pad_mesh()
	_lily_pad_mat = StandardMaterial3D.new()
	_lily_pad_mat.albedo_color = Color(0.15, 0.42, 0.12)
	_lily_pad_mat.roughness = 0.9
	_lily_pad_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_lily_pad_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Lily flower — detailed pink/white bloom with vertex color gradient
	_lily_flower_mesh = _gen_lily_flower_mesh()
	_lily_flower_mat = StandardMaterial3D.new()
	_lily_flower_mat.albedo_color = Color(1.0, 0.88, 0.88)
	_lily_flower_mat.vertex_color_use_as_albedo = true
	_lily_flower_mat.roughness = 0.75
	_lily_flower_mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_lily_flower_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_lily_flower_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Lily pad stem — dark underwater branch
	_lily_stem_mat = StandardMaterial3D.new()
	_lily_stem_mat.albedo_color = Color(0.05, 0.08, 0.03)
	_lily_stem_mat.roughness = 0.95
	_lily_stem_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# Cattail stalk
	_cattail_mat = StandardMaterial3D.new()
	_cattail_mat.albedo_color = Color(0.22, 0.38, 0.15)
	_cattail_mat.roughness = 0.9
	_cattail_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# Cattail brown head
	_cattail_head_mat = StandardMaterial3D.new()
	_cattail_head_mat.albedo_color = Color(0.35, 0.22, 0.10)
	_cattail_head_mat.roughness = 0.95
	_cattail_head_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# Loosestrife stalk
	_loosestrife_mat = StandardMaterial3D.new()
	_loosestrife_mat.albedo_color = Color(0.20, 0.35, 0.12)
	_loosestrife_mat.roughness = 0.9
	_loosestrife_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# Loosestrife purple flower
	_loosestrife_flower_mat = StandardMaterial3D.new()
	_loosestrife_flower_mat.albedo_color = Color(0.62, 0.18, 0.58)
	_loosestrife_flower_mat.roughness = 0.85
	_loosestrife_flower_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

	# Reeds — tall vegetation, reuse billboard shader for wind sway
	if _billboard_shader:
		_reed_mat = ShaderMaterial.new()
		_reed_mat.shader = _billboard_shader
		var reed_tex := _gen_reed_texture()
		_reed_mat.set_shader_parameter("albedo_texture", reed_tex)
		_reed_mat.set_shader_parameter("albedo_color", Color(1.0, 1.0, 1.0))
		_reed_mat.set_shader_parameter("alpha_cutoff", 0.4)
		_reed_mat.set_shader_parameter("wind_strength", 0.3)
		_reed_mat.set_shader_parameter("wind_speed", 1.2)
		_reed_mat.set_shader_parameter("wind_turbulence", 0.6)

	# Ground grass — uses same billboard shader with tighter distance culling
	if _billboard_shader:
		_grass_texture = _gen_grass_texture()
		_grass_mat = ShaderMaterial.new()
		_grass_mat.shader = _billboard_shader
		_grass_mat.set_shader_parameter("albedo_texture", _grass_texture)
		_grass_mat.set_shader_parameter("albedo_color", Color(0.85, 0.95, 0.80))
		_grass_mat.set_shader_parameter("alpha_cutoff", 0.35)
		_grass_mat.set_shader_parameter("wind_strength", 0.6)
		_grass_mat.set_shader_parameter("wind_speed", 1.8)
		_grass_mat.set_shader_parameter("wind_turbulence", 0.9)
		_grass_mat.set_shader_parameter("density_near", 32.0)
		_grass_mat.set_shader_parameter("density_far", 120.0)


static func _gen_lily_pad_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var segs := 32
	var radius := 0.5
	var slit_half := deg_to_rad(8.0)
	var arc := TAU - 2.0 * slit_half

	verts.append(Vector3.ZERO)
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 0.5))

	for i in range(segs + 1):
		var angle := slit_half + float(i) / float(segs) * arc
		var wobble := 0.97 + 0.03 * sin(float(i) * 4.1 + 2.7)
		var r := radius * wobble
		verts.append(Vector3(cos(angle) * r, 0.0, sin(angle) * r))
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.5 + cos(angle) * 0.5, 0.5 + sin(angle) * 0.5))

	for i in range(segs):
		indices.append(0)
		indices.append(i + 1)
		indices.append(i + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _gen_lily_flower_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var white := Color(1.0, 0.92, 0.92)
	var pink_base := Color(1.0, 0.55, 0.62)
	var pink_deep := Color(0.95, 0.38, 0.45)
	var yellow := Color(0.95, 0.75, 0.25)

	# Outer petals — 8 wide, gently cupped petals with 3 segments each
	for p in 8:
		var angle := float(p) / 8.0 * TAU + 0.04
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-sin(angle), 0.0, cos(angle))
		var petal_n := (dir * 0.3 + Vector3.UP).normalized()

		var bi := verts.size()
		# Base (center attachment)
		verts.append(Vector3(0.0, 0.05, 0.0))
		normals.append(Vector3.UP)
		colors.append(white)
		uvs.append(Vector2(0.5, 0.0))
		# Mid-left
		verts.append(dir * 0.06 + side * 0.045 + Vector3(0, 0.07, 0))
		normals.append(petal_n)
		colors.append(lerp(white, pink_base, 0.3))
		uvs.append(Vector2(0.25, 0.4))
		# Mid-right
		verts.append(dir * 0.06 - side * 0.045 + Vector3(0, 0.07, 0))
		normals.append(petal_n)
		colors.append(lerp(white, pink_base, 0.3))
		uvs.append(Vector2(0.75, 0.4))
		# Wide-left
		verts.append(dir * 0.11 + side * 0.055 + Vector3(0, 0.065, 0))
		normals.append(petal_n)
		colors.append(lerp(pink_base, pink_deep, 0.3))
		uvs.append(Vector2(0.15, 0.7))
		# Wide-right
		verts.append(dir * 0.11 - side * 0.055 + Vector3(0, 0.065, 0))
		normals.append(petal_n)
		colors.append(lerp(pink_base, pink_deep, 0.3))
		uvs.append(Vector2(0.85, 0.7))
		# Tip (slightly drooping)
		verts.append(dir * 0.16 + Vector3(0, 0.055, 0))
		normals.append((dir * 0.5 + Vector3.UP * 0.5).normalized())
		colors.append(pink_deep)
		uvs.append(Vector2(0.5, 1.0))

		indices.append(bi); indices.append(bi + 1); indices.append(bi + 2)
		indices.append(bi + 1); indices.append(bi + 3); indices.append(bi + 5)
		indices.append(bi + 1); indices.append(bi + 5); indices.append(bi + 2)
		indices.append(bi + 2); indices.append(bi + 5); indices.append(bi + 4)

	# Middle petals — 8 narrower, angled upward, offset half-step
	for p in 8:
		var angle := (float(p) + 0.5) / 8.0 * TAU
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-sin(angle), 0.0, cos(angle))
		var petal_n := (dir * 0.2 + Vector3.UP * 0.8).normalized()

		var bi := verts.size()
		verts.append(Vector3(0.0, 0.08, 0.0))
		normals.append(Vector3.UP)
		colors.append(white)
		uvs.append(Vector2(0.5, 0.0))
		verts.append(dir * 0.04 + side * 0.035 + Vector3(0, 0.11, 0))
		normals.append(petal_n)
		colors.append(lerp(white, pink_base, 0.5))
		uvs.append(Vector2(0.3, 0.4))
		verts.append(dir * 0.04 - side * 0.035 + Vector3(0, 0.11, 0))
		normals.append(petal_n)
		colors.append(lerp(white, pink_base, 0.5))
		uvs.append(Vector2(0.7, 0.4))
		verts.append(dir * 0.10 + Vector3(0, 0.13, 0))
		normals.append(petal_n)
		colors.append(pink_base)
		uvs.append(Vector2(0.5, 1.0))

		indices.append(bi); indices.append(bi + 1); indices.append(bi + 2)
		indices.append(bi + 1); indices.append(bi + 3); indices.append(bi + 2)

	# Inner petals — 6 small, steep, cupping the center
	for p in 6:
		var angle := float(p) / 6.0 * TAU + 0.12
		var dir := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-sin(angle), 0.0, cos(angle))
		var petal_n := (dir * 0.15 + Vector3.UP).normalized()

		var bi := verts.size()
		verts.append(Vector3(0.0, 0.11, 0.0))
		normals.append(Vector3.UP)
		colors.append(lerp(white, yellow, 0.2))
		uvs.append(Vector2(0.5, 0.0))
		verts.append(dir * 0.025 + side * 0.02 + Vector3(0, 0.14, 0))
		normals.append(petal_n)
		colors.append(lerp(white, pink_base, 0.4))
		uvs.append(Vector2(0.3, 0.5))
		verts.append(dir * 0.025 - side * 0.02 + Vector3(0, 0.14, 0))
		normals.append(petal_n)
		colors.append(lerp(white, pink_base, 0.4))
		uvs.append(Vector2(0.7, 0.5))
		verts.append(dir * 0.055 + Vector3(0, 0.155, 0))
		normals.append(petal_n)
		colors.append(pink_base)
		uvs.append(Vector2(0.5, 1.0))

		indices.append(bi); indices.append(bi + 1); indices.append(bi + 2)
		indices.append(bi + 1); indices.append(bi + 3); indices.append(bi + 2)

	# Center pistil — yellow dome with stamens
	var cb := verts.size()
	verts.append(Vector3(0.0, 0.17, 0.0))
	normals.append(Vector3.UP)
	colors.append(Color(0.95, 0.90, 0.20))
	uvs.append(Vector2(0.5, 0.5))
	for i in 10:
		var a := float(i) / 10.0 * TAU
		verts.append(Vector3(cos(a) * 0.025, 0.12, sin(a) * 0.025))
		normals.append(Vector3(cos(a), 0.3, sin(a)).normalized())
		colors.append(Color(0.90, 0.80, 0.15))
		uvs.append(Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5))
	for i in 10:
		indices.append(cb)
		indices.append(cb + 1 + i)
		indices.append(cb + 1 + (i + 1) % 10)

	# Stamens — thin spikes radiating from center
	for s in 12:
		var a := float(s) / 12.0 * TAU + 0.15
		var sd := Vector3(cos(a), 0.0, sin(a))
		var bi := verts.size()
		verts.append(Vector3(cos(a) * 0.015, 0.13, sin(a) * 0.015))
		normals.append(Vector3.UP)
		colors.append(Color(0.85, 0.75, 0.10))
		uvs.append(Vector2(0.5, 0.0))
		verts.append(sd * 0.04 + Vector3(0, 0.155 + sin(a * 3.0) * 0.01, 0))
		normals.append((sd + Vector3.UP).normalized())
		colors.append(yellow)
		uvs.append(Vector2(0.5, 0.8))
		# Anther tip — small triangle cap
		verts.append(sd * 0.045 + Vector3(0.003, 0.16 + sin(a * 3.0) * 0.01, 0))
		normals.append(Vector3.UP)
		colors.append(Color(0.98, 0.92, 0.30))
		uvs.append(Vector2(0.5, 1.0))
		indices.append(bi); indices.append(bi + 1); indices.append(bi + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _gen_reed_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 55123
	var w := 32
	var h := 64
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var wheat := Color(0.72, 0.62, 0.35)
	var green := Color(0.30, 0.52, 0.18)
	for _blade in rng.randi_range(3, 5):
		var cx := rng.randi_range(8, w - 9)
		var blade_h := rng.randi_range(40, h - 4)
		var blade_w := rng.randi_range(1, 3)
		var curve := rng.randf_range(-0.04, 0.04)
		for dy in blade_h:
			var t := float(dy) / float(blade_h)
			var width := int(lerpf(float(blade_w), 1.0, t * 0.8))
			var ox := int(curve * dy * dy * 0.01)
			var col_t := smoothstep(0.20, 0.35, t)
			var blade_col := wheat.lerp(green, col_t)
			blade_col *= lerpf(0.7, 1.0, t)
			blade_col.a = 1.0
			for dx in range(-width, width + 1):
				var px := cx + dx + ox
				var py := h - 1 - dy
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, blade_col)
	return ImageTexture.create_from_image(img)


static func _gen_grass_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77042
	var w := 32
	var h := 48
	var img := Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var greens := [
		Color(0.22, 0.48, 0.14),
		Color(0.28, 0.55, 0.18),
		Color(0.18, 0.42, 0.12),
		Color(0.32, 0.58, 0.22),
		Color(0.25, 0.50, 0.16),
	]
	for _blade in rng.randi_range(6, 9):
		var cx := rng.randi_range(4, w - 5)
		var blade_h := rng.randi_range(20, h - 6)
		var blade_w := rng.randi_range(1, 2)
		var curve := rng.randf_range(-0.06, 0.06)
		var base_col: Color = greens[rng.randi() % greens.size()]
		for dy in blade_h:
			var t := float(dy) / float(blade_h)
			var bw := int(lerpf(float(blade_w), 0.5, t * 0.9))
			var ox := int(curve * dy * dy * 0.008)
			var col := base_col * lerpf(0.65, 1.1, t)
			col.a = 1.0
			for dx in range(-bw, bw + 1):
				var px := cx + dx + ox
				var py := h - 1 - dy
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, col)
	return ImageTexture.create_from_image(img)


static func _create_cattail(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Cattail"
	var stalk_h := rng.randf_range(1.2, 2.0)
	var stalk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.015
	cyl.bottom_radius = 0.025
	cyl.height = stalk_h
	cyl.radial_segments = 5
	cyl.rings = 1
	stalk.mesh = cyl
	stalk.material_override = _cattail_mat
	stalk.position.y = stalk_h * 0.5
	stalk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(stalk)
	var head := MeshInstance3D.new()
	var head_cyl := CylinderMesh.new()
	head_cyl.top_radius = 0.04
	head_cyl.bottom_radius = 0.045
	head_cyl.height = 0.20
	head_cyl.radial_segments = 5
	head_cyl.rings = 1
	head.mesh = head_cyl
	head.material_override = _cattail_head_mat
	head.position.y = stalk_h - 0.05
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(head)
	return root


static func _create_loosestrife(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Loosestrife"
	var stem_h := rng.randf_range(1.0, 1.8)
	var stem := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.03
	cyl.height = stem_h
	cyl.radial_segments = 4
	cyl.rings = 1
	stem.mesh = cyl
	stem.material_override = _loosestrife_mat
	stem.position.y = stem_h * 0.5
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(stem)
	var flower_cluster_h := rng.randf_range(0.25, 0.45)
	var num_blobs := rng.randi_range(4, 8)
	for _bi in num_blobs:
		var blob := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = rng.randf_range(0.06, 0.12)
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = 4
		sphere.rings = 2
		blob.mesh = sphere
		blob.material_override = _loosestrife_flower_mat
		blob.position = Vector3(
			rng.randf_range(-0.06, 0.06),
			stem_h - 0.05 + rng.randf_range(0.0, flower_cluster_h),
			rng.randf_range(-0.06, 0.06))
		blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(blob)
	return root


static func _scatter_berry_bushes(
	zone_root: Node3D,
	coord: Vector2i,
	biome: StringName,
	rng: RandomNumberGenerator,
	height_func: Callable,
	origin_x: float,
	origin_z: float,
) -> void:
	if biome != &"hearthlands":
		return
	if not _berry_bushes_ready:
		return

	var structs := _get_structures_cached()

	# Per-zone hash for density variation
	var zone_hash := absf(sin(float(coord.x * 51637 + coord.y * 83291) * 0.073))

	# Blueberries — forest floor near trees, clusters of 2-4
	var bb_clusters := 0
	if zone_hash > 0.35:
		bb_clusters = rng.randi_range(1, 3)
	for _ci in bb_clusters:
		var cx := rng.randf_range(6.0, ZONE_SIZE - 6.0)
		var cz := rng.randf_range(6.0, ZONE_SIZE - 6.0)
		var wx := origin_x + cx
		var wz := origin_z + cz
		var sn := _hg_snap_and_normal(wx, wz)
		if sn.x < _MIN_LAND_Y or sn.y < 0.85:
			continue
		if get_path_factor(wx, wz) > 0.3:
			continue
		if _is_near_structure(wx, wz, 5.0, structs):
			continue
		var cluster_size := rng.randi_range(2, 4)
		for _bi in cluster_size:
			var ox := cx + rng.randf_range(-1.8, 1.8)
			var oz := cz + rng.randf_range(-1.8, 1.8)
			var owx := origin_x + ox
			var owz := origin_z + oz
			var bsn := _hg_snap_and_normal(owx, owz)
			if bsn.x < _MIN_LAND_Y or bsn.y < 0.85:
				continue
			var bush := _create_blueberry_bush(rng)
			zone_root.add_child(bush)
			bush.position = Vector3(ox, bsn.x + 0.08, oz)
			bush.rotation.y = rng.randf_range(0.0, TAU)

	# Lingonberries — open/rocky areas, clusters of 2-5
	var lb_hash := absf(sin(float(coord.x * 37159 + coord.y * 61843) * 0.091))
	var lb_clusters := 0
	if lb_hash > 0.40:
		lb_clusters = rng.randi_range(1, 3)
	for _ci in lb_clusters:
		var cx := rng.randf_range(6.0, ZONE_SIZE - 6.0)
		var cz := rng.randf_range(6.0, ZONE_SIZE - 6.0)
		var wx := origin_x + cx
		var wz := origin_z + cz
		var sn := _hg_snap_and_normal(wx, wz)
		if sn.x < _MIN_LAND_Y or sn.y < 0.82:
			continue
		if get_path_factor(wx, wz) > 0.3:
			continue
		if _is_near_structure(wx, wz, 5.0, structs):
			continue
		var cluster_size := rng.randi_range(2, 5)
		for _bi in cluster_size:
			var ox := cx + rng.randf_range(-1.5, 1.5)
			var oz := cz + rng.randf_range(-1.5, 1.5)
			var owx := origin_x + ox
			var owz := origin_z + oz
			var bsn := _hg_snap_and_normal(owx, owz)
			if bsn.x < _MIN_LAND_Y or bsn.y < 0.82:
				continue
			var bush := _create_lingonberry_bush(rng)
			zone_root.add_child(bush)
			bush.position = Vector3(ox, bsn.x + 0.08, oz)
			bush.rotation.y = rng.randf_range(0.0, TAU)


static func _scatter_water_plants(
	zone_root: Node3D,
	coord: Vector2i,
	biome: StringName,
	rng: RandomNumberGenerator,
	height_func: Callable,
) -> void:
	if biome != &"hearthlands":
		return
	if not _water_plants_ready:
		return

	var origin_x: float = coord.x * ZONE_SIZE
	var origin_z: float = coord.y * ZONE_SIZE

	# ── Lily pads — float on water where terrain is submerged ──
	# Per-zone hash: ~40% of zones get no lilies, rest get varying density (max 40% of old count)
	var lily_hash := absf(sin(float(coord.x * 73 + coord.y * 137) * 0.1))
	var lily_count := 0
	if lily_hash > 0.4:
		var lily_d := (lily_hash - 0.4) / 0.6
		lily_count = rng.randi_range(int(6.0 + lily_d * 20.0), int(16.0 + lily_d * 56.0))
	for _i in lily_count:
		var lx := rng.randf_range(2.0, ZONE_SIZE - 2.0)
		var lz := rng.randf_range(2.0, ZONE_SIZE - 2.0)
		var wx := origin_x + lx
		var wz := origin_z + lz
		var mesh_h := _hg_snap_height(wx, wz)
		if mesh_h > -1.5 or mesh_h < -4.0:
			continue
		var pad := MeshInstance3D.new()
		pad.mesh = _lily_pad_mesh
		pad.material_override = _lily_pad_mat
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pad_scale := rng.randf_range(1.5, 3.5)
		pad.scale = Vector3(pad_scale, 1.0, pad_scale)
		pad.rotation.y = rng.randf_range(0.0, TAU)
		pad.position = Vector3(lx, _WATER_LEVEL + 0.02, lz)
		zone_root.add_child(pad)

		# Underwater stem connecting pad to the pool bottom
		if _lily_stem_mat:
			var stem_len := absf(mesh_h)
			var stem_mesh := CylinderMesh.new()
			stem_mesh.top_radius = 0.01
			stem_mesh.bottom_radius = 0.015
			stem_mesh.height = stem_len
			stem_mesh.radial_segments = 5
			stem_mesh.rings = 1
			var stem := MeshInstance3D.new()
			stem.mesh = stem_mesh
			stem.material_override = _lily_stem_mat
			stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			stem.position = Vector3(0.0, -stem_len * 0.5, 0.0)
			stem.rotation.x = rng.randf_range(-0.08, 0.08)
			stem.rotation.z = rng.randf_range(-0.08, 0.08)
			pad.add_child(stem)

		if rng.randf() < 0.1 and _lily_flower_mesh:
			var flower := MeshInstance3D.new()
			flower.mesh = _lily_flower_mesh
			flower.material_override = _lily_flower_mat
			flower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flower.scale = Vector3(1.3, 1.3, 1.3)
			var off_angle := rng.randf_range(0.0, TAU)
			var off_dist := rng.randf_range(0.0, 0.12)
			flower.position = Vector3(cos(off_angle) * off_dist, 0.0, sin(off_angle) * off_dist)
			pad.add_child(flower)

	# ── Cattails — emergent plants right at the waterline ──
	var cattail_count := rng.randi_range(5, 12)
	for _i in cattail_count:
		var lx := rng.randf_range(2.0, ZONE_SIZE - 2.0)
		var lz := rng.randf_range(2.0, ZONE_SIZE - 2.0)
		var wx := origin_x + lx
		var wz := origin_z + lz
		var mesh_h := _hg_snap_height(wx, wz)
		if mesh_h < -0.15 or mesh_h > 0.25:
			continue
		if _is_near_structure(wx, wz):
			continue
		var clump_size := rng.randi_range(2, 4)
		for _ci in clump_size:
			var ox := rng.randf_range(-0.4, 0.4)
			var oz := rng.randf_range(-0.4, 0.4)
			var cattail := _create_cattail(rng)
			var ground_y := maxf(_hg_snap_height(wx + ox, wz + oz), _WATER_LEVEL - 0.05)
			cattail.position = Vector3(lx + ox, ground_y, lz + oz)
			zone_root.add_child(cattail)

	# ── Purple Loosestrife — damp bank just above the waterline ──
	var loosestrife_count := rng.randi_range(16, 40)
	for _i in loosestrife_count:
		var lx := rng.randf_range(2.0, ZONE_SIZE - 2.0)
		var lz := rng.randf_range(2.0, ZONE_SIZE - 2.0)
		var wx := origin_x + lx
		var wz := origin_z + lz
		var mesh_h := _hg_snap_height(wx, wz)
		if mesh_h < 0.0 or mesh_h > 0.5:
			continue
		if _is_near_structure(wx, wz):
			continue
		var clump := rng.randi_range(1, 3)
		for _ci in clump:
			var ox := rng.randf_range(-0.5, 0.5)
			var oz := rng.randf_range(-0.5, 0.5)
			var plant := _create_loosestrife(rng)
			var ground_y := maxf(_hg_snap_height(wx + ox, wz + oz), _WATER_LEVEL + 0.02)
			plant.position = Vector3(lx + ox, ground_y, lz + oz)
			zone_root.add_child(plant)

	# ── Reeds — clumped along water edges, per-zone variation ──
	if not _reed_mat or not _billboard_quad_mesh:
		return
	var reed_hash := absf(sin(float(coord.x * 97 + coord.y * 163) * 0.1))
	var num_clumps := 0
	if reed_hash > 0.88:
		var reed_d := (reed_hash - 0.88) / 0.12
		num_clumps = rng.randi_range(int(2.0 + reed_d * 4.0), int(4.0 + reed_d * 8.0))

	var transforms: Array[Transform3D] = []
	for _c in num_clumps:
		var cx := 0.0
		var cz := 0.0
		var found := false
		for _try in 20:
			cx = rng.randf_range(4.0, ZONE_SIZE - 4.0)
			cz = rng.randf_range(4.0, ZONE_SIZE - 4.0)
		var ch := _hg_snap_height(origin_x + cx, origin_z + cz)
		if ch >= -0.25 and ch <= _WATER_LEVEL:
				found = true
				break
		if not found:
			continue
		var reeds_in_clump := rng.randi_range(30, 70)
		for _r in reeds_in_clump:
			var ox := rng.randf_range(-3.0, 3.0)
			var oz := rng.randf_range(-3.0, 3.0)
			var wx := origin_x + cx + ox
			var wz := origin_z + cz + oz
			var mesh_h := _hg_snap_height(wx, wz)
			if mesh_h < -0.3 or mesh_h > _WATER_LEVEL:
				continue
			if _is_near_structure(wx, wz):
				continue
			var ground_y := maxf(mesh_h, _WATER_LEVEL - 0.15)
			var sc := rng.randf_range(1.5, 2.8)
			var rot := rng.randf_range(0.0, TAU)
			var basis := Basis(Vector3.UP, rot).scaled(Vector3(0.6 * sc, 1.2 * sc, 0.6 * sc))
			transforms.append(Transform3D(basis, Vector3(cx + ox, ground_y, cz + oz)))

	if transforms.is_empty():
		return
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.mesh = _billboard_quad_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.instance_count = transforms.size()
	for idx in transforms.size():
		mm.set_instance_transform(idx, transforms[idx])
	mmi.multimesh = mm
	mmi.name = "Reeds"
	mmi.material_override = _reed_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone_root.add_child(mmi)


static func _scatter_creek_rocks(
	zone_root: Node3D,
	coord: Vector2i,
	rng: RandomNumberGenerator,
	height_func: Callable,
) -> void:
	var wg := _get_world_generator()
	if not wg or not wg.has_method("get_creek_segments_for_zone"):
		return

	var segments: Array = wg.get_creek_segments_for_zone(coord)
	if segments.is_empty():
		return

	var origin_x: float = coord.x * ZONE_SIZE
	var origin_z: float = coord.y * ZONE_SIZE
	var structs := _get_structures_cached()

	for seg in segments:
		var points: PackedVector3Array = seg["points"]
		var widths: PackedFloat32Array = seg["widths"]
		if points.size() < 2:
			continue

		var num_rocks := maxi(2, points.size() / 4)
		var num_pebbles := num_rocks * 3

		for _i in num_rocks:
			var idx := rng.randi_range(0, points.size() - 1)
			var center := points[idx]
			var half_w: float = widths[idx] if idx < widths.size() else 1.0

			var side := 1.0 if rng.randf() > 0.5 else -1.0
			var perp := Vector2.ZERO
			if idx < points.size() - 1:
				var dir := Vector2(points[idx + 1].x - center.x, points[idx + 1].z - center.z).normalized()
				perp = Vector2(-dir.y, dir.x)
			elif idx > 0:
				var dir := Vector2(center.x - points[idx - 1].x, center.z - points[idx - 1].z).normalized()
				perp = Vector2(-dir.y, dir.x)
			else:
				perp = Vector2(1, 0)

			var offset_dist := half_w + rng.randf_range(0.5, 3.0)
			var wx := center.x + perp.x * side * offset_dist
			var wz := center.z + perp.y * side * offset_dist
			var lx := wx - origin_x
			var lz := wz - origin_z

			if lx < 1.0 or lx > ZONE_SIZE - 1.0 or lz < 1.0 or lz > ZONE_SIZE - 1.0:
				continue

			var ground_y := _hg_snap_height(wx, wz)
			if ground_y < _MIN_LAND_Y:
				continue
			if _is_near_structure(wx, wz, 3.0, structs):
				continue

			var rock := _create_rock(rng)
			rock.scale *= rng.randf_range(0.4, 0.8)
			zone_root.add_child(rock)
			rock.position = Vector3(lx, ground_y, lz)

		for _i in num_pebbles:
			var idx := rng.randi_range(0, points.size() - 1)
			var center := points[idx]
			var half_w: float = widths[idx] if idx < widths.size() else 1.0

			var side := 1.0 if rng.randf() > 0.5 else -1.0
			var perp := Vector2.ZERO
			if idx < points.size() - 1:
				var dir := Vector2(points[idx + 1].x - center.x, points[idx + 1].z - center.z).normalized()
				perp = Vector2(-dir.y, dir.x)
			elif idx > 0:
				var dir := Vector2(center.x - points[idx - 1].x, center.z - points[idx - 1].z).normalized()
				perp = Vector2(-dir.y, dir.x)
			else:
				perp = Vector2(1, 0)

			var offset_dist := half_w * rng.randf_range(0.3, 1.2) + rng.randf_range(-0.5, 1.5)
			var wx := center.x + perp.x * side * offset_dist
			var wz := center.z + perp.y * side * offset_dist
			var lx := wx - origin_x
			var lz := wz - origin_z

			if lx < 0.5 or lx > ZONE_SIZE - 0.5 or lz < 0.5 or lz > ZONE_SIZE - 0.5:
				continue

			var ground_y := _hg_snap_height(wx, wz)
			if ground_y < _MIN_LAND_Y - 0.3:
				continue

			var peb := _create_pebble(rng)
			zone_root.add_child(peb)
			peb.position = Vector3(lx, ground_y + 0.03, lz)


static func _scatter_creek_vegetation(
	zone_root: Node3D,
	coord: Vector2i,
	rng: RandomNumberGenerator,
	height_func: Callable,
) -> void:
	if not _water_plants_ready:
		return

	var wg := _get_world_generator()
	if not wg or not wg.has_method("get_creek_segments_for_zone"):
		return

	var segments: Array = wg.get_creek_segments_for_zone(coord)
	if segments.is_empty():
		return

	var origin_x: float = coord.x * ZONE_SIZE
	var origin_z: float = coord.y * ZONE_SIZE
	var structs := _get_structures_cached()

	var reed_transforms: Array[Transform3D] = []

	for seg in segments:
		var points: PackedVector3Array = seg["points"]
		var widths: PackedFloat32Array = seg["widths"]
		if points.size() < 2:
			continue

		var num_cattails := maxi(1, points.size() / 6)
		var num_reeds := maxi(2, points.size() / 3)

		for _i in num_cattails:
			var idx := rng.randi_range(0, points.size() - 1)
			var center := points[idx]
			var half_w: float = widths[idx] if idx < widths.size() else 1.0

			var side := 1.0 if rng.randf() > 0.5 else -1.0
			var perp := Vector2.ZERO
			if idx < points.size() - 1:
				var dir := Vector2(points[idx + 1].x - center.x, points[idx + 1].z - center.z).normalized()
				perp = Vector2(-dir.y, dir.x)
			elif idx > 0:
				var dir := Vector2(center.x - points[idx - 1].x, center.z - points[idx - 1].z).normalized()
				perp = Vector2(-dir.y, dir.x)
			else:
				perp = Vector2(1, 0)

			var offset_dist := half_w * rng.randf_range(0.8, 1.1)
			var wx := center.x + perp.x * side * offset_dist
			var wz := center.z + perp.y * side * offset_dist
			var lx := wx - origin_x
			var lz := wz - origin_z

			if lx < 1.0 or lx > ZONE_SIZE - 1.0 or lz < 1.0 or lz > ZONE_SIZE - 1.0:
				continue
			if _is_near_structure(wx, wz):
				continue

			var ground_y := _hg_snap_height(wx, wz)
			var clump_size := rng.randi_range(2, 4)
			for _ci in clump_size:
				var ox := rng.randf_range(-0.3, 0.3)
				var oz := rng.randf_range(-0.3, 0.3)
				var cattail := _create_cattail(rng)
				var cy := maxf(_hg_snap_height(wx + ox, wz + oz), ground_y - 0.1)
				cattail.position = Vector3(lx + ox, cy, lz + oz)
				zone_root.add_child(cattail)

		for _i in num_reeds:
			var idx := rng.randi_range(0, points.size() - 1)
			var center := points[idx]
			var half_w: float = widths[idx] if idx < widths.size() else 1.0

			var side := 1.0 if rng.randf() > 0.5 else -1.0
			var perp := Vector2.ZERO
			if idx < points.size() - 1:
				var dir := Vector2(points[idx + 1].x - center.x, points[idx + 1].z - center.z).normalized()
				perp = Vector2(-dir.y, dir.x)
			elif idx > 0:
				var dir := Vector2(center.x - points[idx - 1].x, center.z - points[idx - 1].z).normalized()
				perp = Vector2(-dir.y, dir.x)
			else:
				perp = Vector2(1, 0)

			var offset_dist := half_w * rng.randf_range(0.7, 1.05)
			var base_wx := center.x + perp.x * side * offset_dist
			var base_wz := center.z + perp.y * side * offset_dist

			if _is_near_structure(base_wx, base_wz):
				continue

			var reeds_in_clump := rng.randi_range(8, 20)
			for _r in reeds_in_clump:
				var ox := rng.randf_range(-1.0, 1.0)
				var oz := rng.randf_range(-1.0, 1.0)
				var wx := base_wx + ox
				var wz := base_wz + oz
				var lx := wx - origin_x
				var lz := wz - origin_z

				if lx < 0.5 or lx > ZONE_SIZE - 0.5 or lz < 0.5 or lz > ZONE_SIZE - 0.5:
					continue

				var ground_y := _hg_snap_height(wx, wz)
				var sc := rng.randf_range(1.2, 2.2)
				var rot := rng.randf_range(0.0, TAU)
				var basis := Basis(Vector3.UP, rot).scaled(Vector3(0.5 * sc, 1.0 * sc, 0.5 * sc))
				reed_transforms.append(Transform3D(basis, Vector3(lx, ground_y, lz)))

	if reed_transforms.is_empty() or not _reed_mat or not _billboard_quad_mesh:
		return

	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.mesh = _billboard_quad_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.instance_count = reed_transforms.size()
	for idx in reed_transforms.size():
		mm.set_instance_transform(idx, reed_transforms[idx])
	mmi.multimesh = mm
	mmi.name = "CreekReeds"
	mmi.material_override = _reed_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone_root.add_child(mmi)
