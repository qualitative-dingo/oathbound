class_name WorldGenerator
extends Node3D
## Procedural world generator with watershed-based rivers and 8 biome rings.
##
## Water placement uses a proper flow-accumulation model:
##   1.  Sample base terrain on a coarse grid covering the whole map.
##   2.  Compute D8 flow directions (each cell -> steepest-descent neighbor).
##   3.  Accumulate flow via topological BFS so every cell knows how many
##       upstream cells drain through it.
##   4.  At runtime, bilinear-sample the accumulation grid.  Cells above
##       a threshold are carved below WATER_LEVEL, forming connected rivers
##       that naturally follow valleys and widen downstream.
##
## World structure:
##   - Circular map, ~10 000 unit radius (20 000 diameter).
##   - Divided into 64x64 unit zones, each with its own terrain mesh.
##   - Biomes in concentric rings from center outward.
##   - Same seed always produces identical worlds.
##   - Terrain generated once per zone on first visit, then cached.

const _ZonePopulator := preload("res://scripts/world/zone_populator.gd")

signal zone_loaded(coord: Vector2i)
signal zone_unloaded(coord: Vector2i)
signal biome_at_player_changed(biome_id: StringName)

# ─── World Constants ───────────────────────────────────────────────────────────

@export_group("World")
@export var world_seed: String = "oathbound"
@export var world_radius: float = 10000.0
const ZONE_SIZE := 64.0

@export_group("Loading")
@export var load_radius_zones: int = 2
@export var unload_radius_zones: int = 3
const MAX_ZONES_PER_FRAME := 1
const MESH_RESOLUTION := 32

@export_group("Terrain")
@export var height_scale: float = 30.0
@export var base_frequency: float = 0.003
@export var detail_frequency: float = 0.02

const WATER_LEVEL := 0.0

# ─── Noise Layers ──────────────────────────────────────────────────────────────

var _seed_hash: int
var _continent_noise: FastNoiseLite
var _mountain_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _biome_temp_noise: FastNoiseLite
var _biome_moisture_noise: FastNoiseLite
var _color_noise: FastNoiseLite
var _microbiome_noise: FastNoiseLite
var _microbiome_secondary: FastNoiseLite

# ─── Watershed Grid ───────────────────────────────────────────────────────────

const _WS_CELL := 64.0
const _WS_RIVER_THRESH := 8.0
const _WS_RIVER_FULL := 80.0

const _D8X := [1, 1, 0, -1, -1, -1, 0, 1]
const _D8Z := [0, -1, -1, -1, 0, 1, 1, 1]
const _D8DIST := [1.0, 1.414, 1.0, 1.414, 1.0, 1.414, 1.0, 1.414]

var _ws_dim: int = 0
var _ws_accum: PackedFloat32Array

# ─── Zone Management ──────────────────────────────────────────────────────────

var _loaded_zones: Dictionary = {}
var _explored_zones: Dictionary = {}
var _explored_sub_chunks: Dictionary = {}
var _zone_biome_cache: Dictionary = {}
var _zone_microbiome_cache: Dictionary = {}
var _biome_materials: Dictionary = {}
var _pending_zones: Array[Vector2i] = []
var _players: Array[Node3D] = []
var _last_player_biome: StringName = &""
var _needs_player_placement := true
var _global_water_plane: MeshInstance3D
var _last_explore_pos := Vector3(INF, INF, INF)
var _zone_water_cache: Dictionary = {}

const SUB_CHUNK_RES := 4


func get_explored_zones() -> Dictionary:
	return _explored_zones


func get_zone_biome_cache() -> Dictionary:
	return _zone_biome_cache


func explore_around(world_pos: Vector3, radius_zones: int = 3) -> void:
	var center_zone := world_to_zone(world_pos)
	var sub_size := ZONE_SIZE / float(SUB_CHUNK_RES)
	var reveal_radius := radius_zones * ZONE_SIZE * 0.6
	var reveal_r_sq := reveal_radius * reveal_radius
	for zx in range(center_zone.x - radius_zones, center_zone.x + radius_zones + 1):
		for zz in range(center_zone.y - radius_zones, center_zone.y + radius_zones + 1):
			var zone_coord := Vector2i(zx, zz)
			if not _explored_zones.has(zone_coord):
				_explored_zones[zone_coord] = true
			var zone_wx: float = zx * ZONE_SIZE
			var zone_wz: float = zz * ZONE_SIZE
			for sx in SUB_CHUNK_RES:
				for sz in SUB_CHUNK_RES:
					var key := Vector4i(zx, zz, sx, sz)
					if _explored_sub_chunks.has(key):
						continue
					var sc_center_x := zone_wx + (sx + 0.5) * sub_size
					var sc_center_z := zone_wz + (sz + 0.5) * sub_size
					var dist_sq := (sc_center_x - world_pos.x) ** 2 + (sc_center_z - world_pos.z) ** 2
					if dist_sq < reveal_r_sq:
						_explored_sub_chunks[key] = true


func is_sub_chunk_explored(zone_x: int, zone_z: int, sx: int, sz: int) -> bool:
	return _explored_sub_chunks.has(Vector4i(zone_x, zone_z, sx, sz))


func get_sub_chunk_explore_fraction(zone_x: int, zone_z: int) -> float:
	var count := 0
	for sx in SUB_CHUNK_RES:
		for sz in SUB_CHUNK_RES:
			if _explored_sub_chunks.has(Vector4i(zone_x, zone_z, sx, sz)):
				count += 1
	return float(count) / float(SUB_CHUNK_RES * SUB_CHUNK_RES)


func _ready() -> void:
	_seed_hash = world_seed.hash()
	add_to_group(&"world_generator")
	_init_noise_layers()
	_compute_watershed()
	_init_biome_materials()
	_init_water_material()
	_generate_spawn_area()
	_create_global_water()
	var theme_songs: Array[String] = [
		"misty_forest_echoes.mp3",
		"misty_forest_lament.mp3",
		"misty_forest_wanderer_otpjsobu.mp3",
		"misty_forest_wanderer_qh3lws5g.mp3",
		"misty_nordic_forest_theme.mp3",
		"nordic_wilderness_echoes.mp3",
		"whispers_of_the_northern_wild.mp3",
	]
	AudioManager.play_music_playlist(theme_songs, 4.0)


func _physics_process(_delta: float) -> void:
	_players.clear()
	for n in get_tree().get_nodes_in_group(&"player"):
		if n is Node3D:
			_players.append(n)
	if _players.is_empty():
		return
	var host: Node3D = _players[0]
	if _needs_player_placement:
		_needs_player_placement = false
		var spawn_h := get_height_at(host.global_position.x, host.global_position.z)
		host.global_position.y = spawn_h + 2.5
		host.velocity = Vector3.ZERO
	else:
		# Safety: never let any player be buried underground
		for p in _players:
			var ground := get_height_at(p.global_position.x, p.global_position.z)
			if p.global_position.y < ground - 0.5:
				p.global_position.y = ground + 2.0
				p.velocity = Vector3.ZERO
	for p in _players:
		_queue_zones_around(world_to_zone(p.global_position))
	_process_pending_zones()
	_unload_distant_zones(_players)
	_check_biome_change(world_to_zone(host.global_position))
	var explore_dist_sq := (host.global_position - _last_explore_pos).length_squared()
	if explore_dist_sq > 16.0:
		for p in _players:
			explore_around(p.global_position, 3)
		_last_explore_pos = host.global_position
	if _global_water_plane:
		# Snap to zone grid so wave vertices don't shift with player movement
		_global_water_plane.global_position.x = floorf(host.global_position.x / ZONE_SIZE) * ZONE_SIZE
		_global_water_plane.global_position.z = floorf(host.global_position.z / ZONE_SIZE) * ZONE_SIZE


# ═══════════════════════════════════════════════════════════════════════════════
#  NOISE SETUP
# ═══════════════════════════════════════════════════════════════════════════════

func _init_noise_layers() -> void:
	_continent_noise = FastNoiseLite.new()
	_continent_noise.seed = _seed_hash
	_continent_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent_noise.frequency = base_frequency
	_continent_noise.fractal_octaves = 2
	_continent_noise.fractal_lacunarity = 2.0
	_continent_noise.fractal_gain = 0.5

	_mountain_noise = FastNoiseLite.new()
	_mountain_noise.seed = _seed_hash + 1000
	_mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mountain_noise.frequency = base_frequency * 2.0
	_mountain_noise.fractal_octaves = 2

	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = _seed_hash + 2000
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = detail_frequency
	_detail_noise.fractal_octaves = 1

	_biome_temp_noise = FastNoiseLite.new()
	_biome_temp_noise.seed = _seed_hash + 3000
	_biome_temp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_biome_temp_noise.frequency = 0.002
	_biome_temp_noise.fractal_octaves = 2

	_biome_moisture_noise = FastNoiseLite.new()
	_biome_moisture_noise.seed = _seed_hash + 4000
	_biome_moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_biome_moisture_noise.frequency = 0.0025
	_biome_moisture_noise.fractal_octaves = 2

	_color_noise = FastNoiseLite.new()
	_color_noise.seed = _seed_hash + 9000
	_color_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_color_noise.frequency = 0.08
	_color_noise.fractal_octaves = 2

	_microbiome_noise = FastNoiseLite.new()
	_microbiome_noise.seed = _seed_hash + 5500
	_microbiome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_microbiome_noise.frequency = 0.006
	_microbiome_noise.fractal_octaves = 2
	_microbiome_noise.fractal_lacunarity = 2.0
	_microbiome_noise.fractal_gain = 0.5

	_microbiome_secondary = FastNoiseLite.new()
	_microbiome_secondary.seed = _seed_hash + 6600
	_microbiome_secondary.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_microbiome_secondary.frequency = 0.008
	_microbiome_secondary.fractal_octaves = 2


# ═══════════════════════════════════════════════════════════════════════════════
#  WATERSHED COMPUTATION — runs once at startup
# ═══════════════════════════════════════════════════════════════════════════════

func _get_base_height(wx: float, wz: float) -> float:
	var dist := Vector2(wx, wz).length()
	if dist > world_radius * 0.9:
		return -20.0 * ((dist - world_radius * 0.9) / (world_radius * 0.1))
	var continent := _continent_noise.get_noise_2d(wx, wz)
	var mountain := _mountain_noise.get_noise_2d(wx, wz)
	var h := continent * height_scale * 0.6
	h += maxf(mountain, 0.0) * height_scale * 1.5
	var center_dist := Vector2(wx, wz).length()
	if center_dist < 200.0:
		h = lerpf(h, 2.0, 1.0 - smoothstep(0.0, 200.0, center_dist))
	return h


func _compute_watershed() -> void:
	_ws_dim = int(ceil(world_radius * 2.0 / _WS_CELL)) + 2
	var n: int = _ws_dim * _ws_dim

	# Step 1 — sample coarse base heights
	var heights := PackedFloat32Array()
	heights.resize(n)
	for gz in _ws_dim:
		for gx in _ws_dim:
			var wx: float = -world_radius + float(gx) * _WS_CELL
			var wz: float = -world_radius + float(gz) * _WS_CELL
			heights[gz * _ws_dim + gx] = _get_base_height(wx, wz)

	# Step 2 — D8 flow directions (steepest-descent neighbor)
	var flow := PackedInt32Array()
	flow.resize(n)
	for i in n:
		flow[i] = -1

	for gz in _ws_dim:
		for gx in _ws_dim:
			var idx: int = gz * _ws_dim + gx
			var h: float = heights[idx]
			var best_d: int = -1
			var best_s: float = 0.0
			for d in 8:
				var nx: int = gx + _D8X[d]
				var nz: int = gz + _D8Z[d]
				if nx < 0 or nx >= _ws_dim or nz < 0 or nz >= _ws_dim:
					continue
				var s: float = (h - heights[nz * _ws_dim + nx]) / _D8DIST[d]
				if s > best_s:
					best_s = s
					best_d = d
			flow[idx] = best_d

	# Step 3 — in-degrees for topological BFS
	var in_deg := PackedInt32Array()
	in_deg.resize(n)
	for idx in n:
		var d: int = flow[idx]
		if d < 0:
			continue
		var gx: int = idx % _ws_dim
		var gz: int = idx / _ws_dim
		var nx: int = gx + _D8X[d]
		var nz: int = gz + _D8Z[d]
		if nx >= 0 and nx < _ws_dim and nz >= 0 and nz < _ws_dim:
			in_deg[nz * _ws_dim + nx] += 1

	# Step 4 — BFS flow accumulation (topological order, O(n))
	_ws_accum = PackedFloat32Array()
	_ws_accum.resize(n)
	for i in n:
		_ws_accum[i] = 1.0

	var queue: Array = []
	for idx in n:
		if in_deg[idx] == 0:
			queue.append(idx)

	var qi: int = 0
	while qi < queue.size():
		var idx: int = queue[qi]
		qi += 1
		var d: int = flow[idx]
		if d < 0:
			continue
		var gx: int = idx % _ws_dim
		var gz: int = idx / _ws_dim
		var nx: int = gx + _D8X[d]
		var nz: int = gz + _D8Z[d]
		if nx >= 0 and nx < _ws_dim and nz >= 0 and nz < _ws_dim:
			var nidx: int = nz * _ws_dim + nx
			_ws_accum[nidx] += _ws_accum[idx]
			in_deg[nidx] -= 1
			if in_deg[nidx] == 0:
				queue.append(nidx)


func _ws_sample_accum(wx: float, wz: float) -> float:
	if _ws_accum.is_empty():
		return 0.0
	var gx: float = (wx + world_radius) / _WS_CELL
	var gz: float = (wz + world_radius) / _WS_CELL
	var ix: int = clampi(int(gx), 0, _ws_dim - 2)
	var iz: int = clampi(int(gz), 0, _ws_dim - 2)
	var fx: float = clampf(gx - float(ix), 0.0, 1.0)
	var fz: float = clampf(gz - float(iz), 0.0, 1.0)
	var a: float = _ws_accum[iz * _ws_dim + ix]
	var b: float = _ws_accum[iz * _ws_dim + ix + 1]
	var c: float = _ws_accum[(iz + 1) * _ws_dim + ix]
	var d: float = _ws_accum[(iz + 1) * _ws_dim + ix + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func world_to_zone(world_pos: Vector3) -> Vector2i:
	return Vector2i(floori(world_pos.x / ZONE_SIZE), floori(world_pos.z / ZONE_SIZE))


func zone_to_world_center(coord: Vector2i) -> Vector3:
	return Vector3(
		(coord.x + 0.5) * ZONE_SIZE,
		0.0,
		(coord.y + 0.5) * ZONE_SIZE
	)


func get_biome_at(world_pos: Vector3) -> StringName:
	var zone := world_to_zone(world_pos)
	return _determine_biome(zone)


func get_microbiome_at(world_pos: Vector3) -> StringName:
	var zone := world_to_zone(world_pos)
	return _determine_microbiome(zone)


func get_microbiome_at_zone(coord: Vector2i) -> StringName:
	return _determine_microbiome(coord)


func _determine_microbiome(zone: Vector2i) -> StringName:
	if _zone_microbiome_cache.has(zone):
		return _zone_microbiome_cache[zone]

	var biome := _determine_biome(zone)
	if biome != &"hearthlands":
		_zone_microbiome_cache[zone] = &"none"
		return &"none"

	var center := zone_to_world_center(zone)
	var n1 := _microbiome_noise.get_noise_2d(center.x, center.z)
	var n2 := _microbiome_secondary.get_noise_2d(center.x, center.z)
	var height := get_height_at(center.x, center.z)
	var accum := _ws_sample_accum(center.x, center.z)

	var micro: StringName

	# River areas: near rivers/streams
	if accum > _WS_RIVER_THRESH * 0.4:
		micro = &"riverside"
	# Hilly terrain: high elevation + mountainous noise
	elif height > 10.0:
		micro = &"hills"
	# Use the two noise layers to partition the rest
	elif n1 > 0.15:
		# Forest area — 10% chance of birch forest
		var birch_seed := hash(Vector2i(zone.x * 7919, zone.y * 4657))
		if (birch_seed % 100) < 10:
			micro = &"birch_forest"
		else:
			micro = &"forest"
	elif n1 < -0.15:
		micro = &"meadow"
	else:
		# Transition zone — use secondary noise for variety
		if n2 > 0.1:
			micro = &"forest"
		elif n2 < -0.1:
			micro = &"meadow"
		else:
			micro = &"meadow"

	_zone_microbiome_cache[zone] = micro
	return micro


func get_height_at(x: float, z: float) -> float:
	var dist := Vector2(x, z).length()
	if dist > world_radius * 0.9:
		var edge_factor := (dist - world_radius * 0.9) / (world_radius * 0.1)
		return -20.0 * edge_factor

	var continent := _continent_noise.get_noise_2d(x, z)
	var mountain := _mountain_noise.get_noise_2d(x, z)
	var detail := _detail_noise.get_noise_2d(x, z)

	var h := continent * height_scale * 0.6
	h += maxf(mountain, 0.0) * height_scale * 1.5
	h += detail * height_scale * 0.1

	# Keep terrain above water unless carved by rivers/lakes
	h = maxf(h, WATER_LEVEL + 0.4)

	# Watershed river carving — accumulation drives depth and width
	var accum := _ws_sample_accum(x, z)
	if accum > _WS_RIVER_THRESH:
		var t := smoothstep(_WS_RIVER_THRESH, _WS_RIVER_FULL, accum)
		var depth := lerpf(1.0, 6.0, t)
		h = lerpf(h, WATER_LEVEL - depth, t)

	# Noise-driven lakes: carve proper basins with gradual shorelines
	if _detail_noise:
		var lake_n := _continent_noise.get_noise_2d(x * 0.7 + 5000.0, z * 0.7 + 5000.0)
		if lake_n < -0.25:
			var lake_t := smoothstep(-0.25, -0.45, lake_n)
			var lake_depth := lerpf(1.5, 5.0, lake_t)
			h = lerpf(h, WATER_LEVEL - lake_depth, lake_t)

	# Flatten spawn area — fully flat within 20m, fading to 80m
	var center_dist := Vector2(x, z).length()
	if center_dist < 80.0:
		var flatten := 1.0 - smoothstep(0.0, 80.0, center_dist)
		h = lerpf(h, 2.0, flatten)

	return h


# ═══════════════════════════════════════════════════════════════════════════════
#  BIOME DETERMINATION
# ═══════════════════════════════════════════════════════════════════════════════

func _determine_biome(zone: Vector2i) -> StringName:
	if _zone_biome_cache.has(zone):
		return _zone_biome_cache[zone]

	var center := zone_to_world_center(zone)
	var dist := Vector2(center.x, center.z).length()
	var altitude := get_height_at(center.x, center.z)
	var temp := _biome_temp_noise.get_noise_2d(center.x, center.z)
	var moisture := _biome_moisture_noise.get_noise_2d(center.x, center.z)
	var dist_norm := dist / world_radius

	var biome: StringName

	if dist_norm > 0.9 or (altitude < -2.0 and dist_norm > 0.3):
		biome = &"ocean"
	elif dist_norm < 0.35:
		biome = &"hearthlands"
	elif dist_norm < 0.65:
		if temp < -0.05:
			biome = &"thornwood"
		else:
			biome = &"hearthlands"
	else:
		if temp < -0.1:
			biome = &"thornwood"
		elif temp > 0.1 and moisture < 0.1:
			biome = &"scorched_steppe"
		else:
			biome = &"hearthlands"

	_zone_biome_cache[zone] = biome
	return biome


# ═══════════════════════════════════════════════════════════════════════════════
#  ZONE LOADING / UNLOADING
# ═══════════════════════════════════════════════════════════════════════════════

func _generate_spawn_area() -> void:
	var spawn_zone := world_to_zone(Vector3.ZERO)
	for x in range(spawn_zone.x - 1, spawn_zone.x + 2):
		for z in range(spawn_zone.y - 1, spawn_zone.y + 2):
			var coord := Vector2i(x, z)
			if coord not in _loaded_zones:
				_generate_zone(coord)


func _queue_zones_around(center: Vector2i) -> void:
	for x in range(center.x - load_radius_zones, center.x + load_radius_zones + 1):
		for z in range(center.y - load_radius_zones, center.y + load_radius_zones + 1):
			var coord := Vector2i(x, z)
			if coord in _loaded_zones or coord in _pending_zones:
				continue
			var world_center := zone_to_world_center(coord)
			if Vector2(world_center.x, world_center.z).length() > world_radius * 1.1:
				continue
			_pending_zones.append(coord)


func _process_pending_zones() -> void:
	var count := 0
	while count < MAX_ZONES_PER_FRAME and not _pending_zones.is_empty():
		var coord: Vector2i = _pending_zones.pop_front()
		if coord not in _loaded_zones:
			_generate_zone(coord)
			count += 1


func _unload_distant_zones(players: Array[Node3D]) -> void:
	var to_remove: Array[Vector2i] = []
	for coord in _loaded_zones:
		var near_any := false
		for p in players:
			var pz := world_to_zone(p.global_position)
			if (coord - pz).length() <= unload_radius_zones:
				near_any = true
				break
		if not near_any:
			to_remove.append(coord)
	for coord in to_remove:
		_loaded_zones[coord].queue_free()
		_loaded_zones.erase(coord)
		_zone_biome_cache.erase(coord)
		_zone_microbiome_cache.erase(coord)
		_zone_water_cache.erase(coord)
		zone_unloaded.emit(coord)


func _generate_zone(coord: Vector2i) -> void:
	var zone_root := StaticBody3D.new()
	zone_root.name = "Zone_%d_%d" % [coord.x, coord.y]
	zone_root.collision_layer = 1

	var biome := _determine_biome(coord)
	var mesh_instance := MeshInstance3D.new()
	var collision := CollisionShape3D.new()

	var arrays := _build_zone_mesh(coord)
	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	arr_mesh.surface_set_material(0, _biome_materials.get(biome, _biome_materials[&"hearthlands"]))

	mesh_instance.mesh = arr_mesh
	collision.shape = arr_mesh.create_trimesh_shape()

	zone_root.add_child(mesh_instance)
	zone_root.add_child(collision)
	add_child(zone_root)

	zone_root.global_position = Vector3(coord.x * ZONE_SIZE, 0.0, coord.y * ZONE_SIZE)
	_loaded_zones[coord] = zone_root
	_explored_zones[coord] = true

	var micro := _determine_microbiome(coord)
	_ZonePopulator.populate_zone(zone_root, coord, biome, _seed_hash, get_height_at, micro)

	zone_loaded.emit(coord)


# ═══════════════════════════════════════════════════════════════════════════════
#  WATER DETECTION & RENDERING
# ═══════════════════════════════════════════════════════════════════════════════

func _zone_has_water(coord: Vector2i) -> bool:
	if _zone_water_cache.has(coord):
		return _zone_water_cache[coord]
	var origin_x: float = coord.x * ZONE_SIZE
	var origin_z: float = coord.y * ZONE_SIZE
	const CHECK_RES := 8
	var step: float = ZONE_SIZE / CHECK_RES
	var water_count := 0
	for z in range(CHECK_RES + 1):
		for x in range(CHECK_RES + 1):
			var h := get_height_at(origin_x + x * step, origin_z + z * step)
			if h < WATER_LEVEL - 0.3:
				water_count += 1
	var has_water := water_count >= 4
	_zone_water_cache[coord] = has_water
	return has_water


var _water_shader_mat: ShaderMaterial

func _init_water_material() -> void:
	var shader := _load_shader("res://shaders/water.gdshader")
	if not shader:
		return
	_water_shader_mat = ShaderMaterial.new()
	_water_shader_mat.shader = shader
	var noise_tex := _load_tex("res://textures/terrain/water.png")
	if not noise_tex:
		noise_tex = _load_tex("res://textures/materials/stone.png")
	if noise_tex:
		_water_shader_mat.set_shader_parameter("surface_noise", noise_tex)


func _load_shader(path: String) -> Shader:
	if ResourceLoader.exists(path):
		return load(path) as Shader
	return null


func _create_global_water() -> void:
	_global_water_plane = MeshInstance3D.new()
	_global_water_plane.name = "GlobalWater"
	var plane := PlaneMesh.new()
	# Cover a large area around the player — bigger than the loaded zone radius
	var water_extent := ZONE_SIZE * float(unload_radius_zones + 2) * 2.0
	plane.size = Vector2(water_extent, water_extent)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	_global_water_plane.mesh = plane

	if _water_shader_mat:
		_global_water_plane.set_surface_override_material(0, _water_shader_mat)
	else:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.1, 0.3, 0.55, 0.75)
		mat.roughness = 0.1
		mat.metallic = 0.2
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_global_water_plane.set_surface_override_material(0, mat)

	_global_water_plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_global_water_plane.global_position.y = WATER_LEVEL - 0.15
	add_child(_global_water_plane)


# ═══════════════════════════════════════════════════════════════════════════════
#  MESH BUILDING
# ═══════════════════════════════════════════════════════════════════════════════

func _build_zone_mesh(coord: Vector2i) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var res := MESH_RESOLUTION
	var origin_x: float = coord.x * ZONE_SIZE
	var origin_z: float = coord.y * ZONE_SIZE
	var step: float = ZONE_SIZE / res

	for z in range(res + 1):
		for x in range(res + 1):
			var wx := origin_x + x * step
			var wz := origin_z + z * step
			var h := get_height_at(wx, wz)
			verts.append(Vector3(x * step, h, z * step))
			uvs.append(Vector2(x as float / res, z as float / res))

			# Micro-noise vertex color for surface variety
			var cn := _color_noise.get_noise_2d(wx, wz)
			var brightness := 0.92 + cn * 0.12
			colors.append(Color(brightness, brightness * 1.01, brightness * 0.98))

	for z in range(res + 1):
		for x in range(res + 1):
			var wx := origin_x + x * step
			var wz := origin_z + z * step
			var h_left := get_height_at(wx - step, wz)
			var h_right := get_height_at(wx + step, wz)
			var h_up := get_height_at(wx, wz - step)
			var h_down := get_height_at(wx, wz + step)
			var tangent_x := Vector3(2.0 * step, h_right - h_left, 0.0)
			var tangent_z := Vector3(0.0, h_down - h_up, 2.0 * step)
			normals.append(tangent_z.cross(tangent_x).normalized())

	for z in range(res):
		for x in range(res):
			var i := z * (res + 1) + x
			indices.append(i)
			indices.append(i + 1)
			indices.append(i + res + 1)
			indices.append(i + 1)
			indices.append(i + res + 2)
			indices.append(i + res + 1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


# ═══════════════════════════════════════════════════════════════════════════════
#  MATERIALS
# ═══════════════════════════════════════════════════════════════════════════════

func _init_biome_materials() -> void:
	var terrain_shader := load("res://shaders/terrain.gdshader") as Shader

	# Shared slope/cliff textures (used by every biome)
	var dirt_tex := _load_tex("res://textures/terrain/dirt.png")
	var stone_tex := _load_tex("res://textures/terrain/stone.png")
	# Fallbacks from our tileable material set
	if not dirt_tex:
		dirt_tex = _load_tex("res://textures/materials/bark.png")
	if not stone_tex:
		stone_tex = _load_tex("res://textures/materials/stone.png")

	# Per-biome: [flat_texture_name, tint_color, tex_scale]
	var biome_cfg: Dictionary = {
		&"hearthlands":     ["grass",        Color(1.0, 1.0, 1.0),  0.5],
		&"thornwood":       ["forest_floor", Color(0.85, 0.9, 0.75), 0.5],
		&"scorched_steppe": ["dirt",         Color(1.0, 0.9, 0.7),  0.5],
		&"ocean":           ["sand",         Color(0.3, 0.5, 0.7),  0.5],
	}

	for biome_id in biome_cfg:
		var cfg: Array = biome_cfg[biome_id]
		var flat_name: String = cfg[0]
		var tint: Color = cfg[1]
		var tex_scale: float = cfg[2]

		var flat_tex := _load_tex("res://textures/terrain/%s.png" % flat_name)

		if terrain_shader:
			var mat := ShaderMaterial.new()
			mat.shader = terrain_shader
			if flat_tex:
				mat.set_shader_parameter("tex_flat", flat_tex)
			if dirt_tex:
				mat.set_shader_parameter("tex_slope", dirt_tex)
			if stone_tex:
				mat.set_shader_parameter("tex_cliff", stone_tex)
			mat.set_shader_parameter("tint_color", Vector3(tint.r, tint.g, tint.b))
			mat.set_shader_parameter("texture_scale", tex_scale)
			_biome_materials[biome_id] = mat
		else:
			# Fallback if shader fails to load
			var mat := StandardMaterial3D.new()
			mat.albedo_color = _get_biome_terrain_color(biome_id)
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			mat.roughness = 0.85
			mat.vertex_color_use_as_albedo = true
			mat.uv1_triplanar = true
			mat.uv1_world_triplanar = true
			mat.uv1_triplanar_sharpness = 1.0
			if flat_tex:
				mat.albedo_texture = flat_tex
			mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
			_biome_materials[biome_id] = mat


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return null


func _get_biome_terrain_color(biome: StringName) -> Color:
	match biome:
		&"hearthlands":     return Color(0.40, 0.55, 0.22)
		&"thornwood":       return Color(0.14, 0.25, 0.10)
		&"scorched_steppe": return Color(0.60, 0.50, 0.25)
		&"ocean":           return Color(0.08, 0.18, 0.38)
		_:                  return Color(0.3, 0.3, 0.3)


func _check_biome_change(player_zone: Vector2i) -> void:
	var current_biome := _determine_biome(player_zone)
	if current_biome != _last_player_biome:
		_last_player_biome = current_biome
		biome_at_player_changed.emit(current_biome)
		GameEvents.biome_entered.emit(current_biome)


func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _get_world_state_sync() -> WorldStateSync:
	var nodes := get_tree().get_nodes_in_group(&"world_state_sync")
	for n in nodes:
		if n is WorldStateSync:
			return n as WorldStateSync
	return null
