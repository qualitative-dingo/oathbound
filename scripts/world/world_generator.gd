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
const _ZonePool := preload("res://scripts/world/zone_pool.gd")
const _DebugPortal := preload("res://scripts/interactables/debug_portal.gd")

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
const MAX_ZONES_PER_FRAME := 2  # can be higher now since builds happen off-thread
const MESH_RESOLUTION := 32

@export_group("Terrain")
@export var height_scale: float = 30.0
@export var base_frequency: float = 0.003
@export var detail_frequency: float = 0.02

const WATER_LEVEL := 0.0

# ─── Noise Layers ──────────────────────────────────────────────────────────────

var _theme_songs: Array[String] = []
var _seed_hash: int
var _continent_noise: FastNoiseLite
var _mountain_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _color_noise: FastNoiseLite
var _microbiome_noise: FastNoiseLite
var _microbiome_secondary: FastNoiseLite

# ─── Watershed Grid ───────────────────────────────────────────────────────────

const _WS_CELL := 48.0
const _WS_RIVER_THRESH := 3.0
const _WS_RIVER_FULL := 80.0

const _D8X := [1, 1, 0, -1, -1, -1, 0, 1]
const _D8Z := [0, -1, -1, -1, 0, 1, 1, 1]
const _D8DIST := [1.0, 1.414, 1.0, 1.414, 1.0, 1.414, 1.0, 1.414]

var _ws_dim: int = 0
var _ws_accum: PackedFloat32Array

# ─── Floating Origin ──────────────────────────────────────────────────────────
# Periodically re-centers the scene around the player so the GPU always works
# with small coordinate values.  Prevents precision/performance degradation at
# large world coordinates (confirmed: solid-green shader still 25 FPS at 5 km
# from origin, 60 FPS when terrain hidden — vertex transforms are the culprit).

var origin_shift := Vector3.ZERO          ## Cumulative world-space offset applied to the scene
const ORIGIN_SHIFT_THRESHOLD := 512.0     ## Shift when player scene-pos exceeds this (lower = sooner, safer for GPU precision)

func get_world_position(node: Node3D) -> Vector3:
	return node.global_position + origin_shift

func get_world_position_vec(scene_pos: Vector3) -> Vector3:
	return scene_pos + origin_shift

func world_to_scene_pos(world_pos: Vector3) -> Vector3:
	return world_pos - origin_shift

func get_height_at_scene(sx: float, sz: float) -> float:
	return get_height_at(sx + origin_shift.x, sz + origin_shift.z)

func _check_origin_shift() -> void:
	if _players.is_empty():
		return
	var scene_pos := _players[0].global_position
	if absf(scene_pos.x) < ORIGIN_SHIFT_THRESHOLD and absf(scene_pos.z) < ORIGIN_SHIFT_THRESHOLD:
		return
	var world_pos := scene_pos + origin_shift
	var new_origin := Vector3(
		floorf(world_pos.x / ZONE_SIZE) * ZONE_SIZE,
		0.0,
		floorf(world_pos.z / ZONE_SIZE) * ZONE_SIZE)
	var delta := new_origin - origin_shift
	if delta.length_squared() < ZONE_SIZE * ZONE_SIZE:
		return
	var root := get_tree().current_scene
	for child in root.get_children():
		if child is Node3D:
			child.global_position -= delta
	origin_shift = new_origin
	_sync_origin_shift_to_shaders()
	print("[FLOATING ORIGIN] Shifted by (%.0f, 0, %.0f), total offset now (%.0f, 0, %.0f)" % [
		delta.x, delta.z, origin_shift.x, origin_shift.z])


func _sync_origin_shift_to_shaders() -> void:
	for biome_id in _biome_materials:
		var mat: ShaderMaterial = _biome_materials[biome_id] as ShaderMaterial
		if mat:
			mat.set_shader_parameter("origin_shift", origin_shift)
	_ZonePopulator.origin_shift = origin_shift

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

# Terrain mesh cache: avoids rebuilding ArrayMesh + ConcavePolygonShape3D on zone revisit
var _terrain_mesh_cache: Dictionary = {}  # Vector2i → Array (mesh arrays)
var _terrain_shape_cache: Dictionary = {}  # Vector2i → ConcavePolygonShape3D
const _MAX_TERRAIN_CACHE := 100

# Threaded zone generation
var _gen_mutex := Mutex.new()
var _gen_ready_queue: Array = []           # [{coord, arrays, shape}] — filled by workers
var _gen_in_flight: Dictionary = {}        # coord → true — zones currently being built on threads

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
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 60
	_ZonePool.flush_all()
	_finalize_backlog.clear()
	_populate_backlog.clear()
	_gen_ready_queue.clear()
	_gen_in_flight.clear()
	_terrain_mesh_cache.clear()
	_terrain_shape_cache.clear()
	_seed_hash = world_seed.hash()
	add_to_group(&"world_generator")
	_init_noise_layers()
	_compute_watershed()
	_init_biome_materials()
	_init_water_material()
	_generate_spawn_area()
	_create_global_water()
	_theme_songs = [
		"misty_forest_echoes.mp3",
		"misty_forest_lament.mp3",
		"misty_forest_wanderer_otpjsobu.mp3",
		"misty_forest_wanderer_qh3lws5g.mp3",
		"misty_nordic_forest_theme.mp3",
		"nordic_wilderness_echoes.mp3",
		"whispers_of_the_northern_wild.mp3",
	]
	AudioManager.play_music_playlist(_theme_songs, 4.0)
	GameEvents.day_night_changed.connect(_on_day_night_changed)

	if multiplayer.has_multiplayer_peer():
		var csm := CreatureSyncManager.new()
		csm.name = "CreatureSyncManager"
		get_parent().call_deferred("add_child", csm, true)


func _on_day_night_changed(is_day: bool) -> void:
	if is_day:
		if not _theme_songs.is_empty():
			AudioManager.play_music_playlist(_theme_songs, 4.0)
	else:
		AudioManager.stop_music(3.0)


var _diag_timer := 0.0
var _perf_max_queue_ms := 0.0
var _perf_max_pending_ms := 0.0
var _perf_max_unload_ms := 0.0
var _perf_max_explore_ms := 0.0
var _perf_max_total_ms := 0.0
var _perf_pending_size_max := 0

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()

	_diag_timer -= delta
	if _diag_timer <= 0.0:
		_diag_timer = 5.0
		var tree := get_tree()
		var total_nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
		var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var vram_mb := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / (1024.0 * 1024.0)
		var buf_mb := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / (1024.0 * 1024.0)
		var tex_mb := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / (1024.0 * 1024.0)
		var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var n_enemies := tree.get_nodes_in_group(&"enemies").size()
		var n_interactables := tree.get_nodes_in_group(&"interactables").size()
		var n_loot := tree.get_nodes_in_group(&"loot").size()
		var n_structures := tree.get_nodes_in_group(&"structures").size()
		print("[PERF DIAG] FPS=%d nodes=%d objects=%d draws=%d vram=%.1fMB buf=%.1fMB tex=%.1fMB proc=%.1fms phys=%.1fms zones=%d enemies=%d interact=%d loot=%d explored=%d sub=%d tcache=%d bg=%d mesh_q=%d pop_q=%d %s" % [
			Engine.get_frames_per_second(), int(total_nodes), int(objects),
			int(draw_calls), vram_mb, buf_mb, tex_mb, process_ms, physics_ms,
			_loaded_zones.size(), n_enemies, n_interactables, n_loot,
			_explored_zones.size(), _explored_sub_chunks.size(),
			_terrain_mesh_cache.size(), _gen_in_flight.size(),
			_finalize_backlog.size(), _populate_backlog.size(),
			_ZonePool.get_pool_stats()])
		print("[PERF DETAIL] wg_total=%.2fms queue=%.2fms pending=%.2fms unload=%.2fms explore=%.2fms pending_q=%d origin_shift=(%.0f,%.0f)" % [
			_perf_max_total_ms, _perf_max_queue_ms, _perf_max_pending_ms,
			_perf_max_unload_ms, _perf_max_explore_ms, _perf_pending_size_max,
			origin_shift.x, origin_shift.z])
		_perf_max_queue_ms = 0.0
		_perf_max_pending_ms = 0.0
		_perf_max_unload_ms = 0.0
		_perf_max_explore_ms = 0.0
		_perf_max_total_ms = 0.0
		_perf_pending_size_max = 0

	_players.clear()
	for n in get_tree().get_nodes_in_group(&"player"):
		if n is Node3D:
			_players.append(n)
	if _players.is_empty():
		return
	_check_origin_shift()
	var host: Node3D = _players[0]
	var host_wp := get_world_position(host)
	if _needs_player_placement:
		_needs_player_placement = false
		var spawn_h := get_height_at(host_wp.x, host_wp.z)
		host.global_position.y = spawn_h + 2.5
		host.velocity = Vector3.ZERO
	else:
		for p in _players:
			var wp := get_world_position(p)
			var ground := get_height_at(wp.x, wp.z)
			if p.global_position.y < ground - 0.5:
				p.global_position.y = ground + 2.0
				p.velocity = Vector3.ZERO

	var t1 := Time.get_ticks_usec()
	for p in _players:
		_queue_zones_around(world_to_zone(get_world_position(p)))
	var t2 := Time.get_ticks_usec()
	_process_pending_zones()
	var t3 := Time.get_ticks_usec()
	_unload_distant_zones(_players)
	var t4 := Time.get_ticks_usec()
	_update_zone_lods(_players, delta)
	_check_biome_change(world_to_zone(host_wp))
	var explore_dist_sq := (host_wp - _last_explore_pos).length_squared()
	if explore_dist_sq > 16.0:
		for p in _players:
			explore_around(get_world_position(p), 3)
		_last_explore_pos = host_wp
	if _global_water_plane:
		_global_water_plane.global_position.x = floorf(host.global_position.x / ZONE_SIZE) * ZONE_SIZE
		_global_water_plane.global_position.z = floorf(host.global_position.z / ZONE_SIZE) * ZONE_SIZE
	var t5 := Time.get_ticks_usec()

	_perf_max_queue_ms = maxf(_perf_max_queue_ms, float(t2 - t1) / 1000.0)
	_perf_max_pending_ms = maxf(_perf_max_pending_ms, float(t3 - t2) / 1000.0)
	_perf_max_unload_ms = maxf(_perf_max_unload_ms, float(t4 - t3) / 1000.0)
	_perf_max_explore_ms = maxf(_perf_max_explore_ms, float(t5 - t4) / 1000.0)
	_perf_max_total_ms = maxf(_perf_max_total_ms, float(t5 - t0) / 1000.0)
	_perf_pending_size_max = maxi(_perf_pending_size_max, _pending_zones.size())


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
	if center_dist < 100.0:
		h = lerpf(h, 2.0, 1.0 - smoothstep(0.0, 100.0, center_dist))
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
	if accum > _WS_RIVER_THRESH * 0.2:
		# Low-frequency noise for smooth, organic river-edge curves
		var widen_n := _detail_noise.get_noise_2d(x * 0.025 + 3000.0, z * 0.025 + 3000.0)
		var effective_accum := accum + widen_n * _WS_RIVER_THRESH * 1.2

		# Bank slope — WIDE zone that gently lowers terrain toward water level.
		# Applied OUTSIDE the carve gate so shoreline has a gradual incline.
		var bank_t := smoothstep(_WS_RIVER_THRESH * 0.3, _WS_RIVER_THRESH * 1.2, effective_accum)
		if bank_t > 0.0:
			h = lerpf(h, WATER_LEVEL + 0.15, bank_t)

		# Channel carving — push below water for the actual riverbed
		if effective_accum > _WS_RIVER_THRESH:
			var t := smoothstep(_WS_RIVER_THRESH, _WS_RIVER_FULL, effective_accum)
			var depth := lerpf(2.0, 8.0, t)
			var carve := clampf(t * 1.5 + 0.4, 0.0, 1.0)
			h = lerpf(h, WATER_LEVEL - depth, carve)

	# Noise-driven lakes with river-confluence bias
	if _detail_noise:
		var lake_n := _continent_noise.get_noise_2d(x * 0.7 + 5000.0, z * 0.7 + 5000.0)
		# Lakes form more easily near rivers (moderate accumulation = natural confluences)
		var accum_bias := smoothstep(1.0, _WS_RIVER_THRESH * 0.8, accum) * 0.08
		lake_n -= accum_bias
		# Gradual shore slope around lake edges (-0.10 to -0.18 transition zone)
		if lake_n < -0.10 and lake_n >= -0.18:
			var shore_t := smoothstep(-0.10, -0.18, lake_n)
			h = lerpf(h, WATER_LEVEL + 0.15, shore_t)
		# Full lake basin carve
		if lake_n < -0.18:
			var lake_t := smoothstep(-0.18, -0.50, lake_n)
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
	var dist_norm := dist / world_radius

	var biome: StringName
	if dist_norm > 0.9 or (altitude < -2.0 and dist_norm > 0.3):
		biome = &"ocean"
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
				var arrays := _build_zone_mesh(coord)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var faces := PackedVector3Array()
				faces.resize(indices.size())
				for i in indices.size():
					faces[i] = verts[indices[i]]
				var shape := ConcavePolygonShape3D.new()
				shape.set_faces(faces)
				_terrain_mesh_cache[coord] = arrays
				_terrain_shape_cache[coord] = shape
				_finalize_zone(coord, arrays, shape)
	# Spawn area must be fully populated before the player lands
	while not _populate_backlog.is_empty():
		var pitem: Dictionary = _populate_backlog.pop_front()
		var pcoord: Vector2i = pitem["coord"]
		var zone_root = pitem["zone_root"]
		if is_instance_valid(zone_root):
			_ZonePopulator.populate_zone(zone_root, pcoord, pitem["biome"], _seed_hash, get_height_at, pitem["micro"])
			_update_zone_lod(zone_root, float((pcoord - spawn_zone).length()))
			zone_loaded.emit(pcoord)

	_spawn_debug_portals()
	_spawn_starter_goblins()
	_dismiss_loading_screen.call_deferred()


func _dismiss_loading_screen() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ls := get_tree().root.get_node_or_null("LoadingScreen")
	if ls and ls.has_method("dismiss"):
		ls.dismiss()


const _PORTAL_FAR_X := 5120.0
const _PORTAL_FAR_Z := 5120.0

func _spawn_debug_portals() -> void:
	var spawn_x := 25.0
	var spawn_z := 20.0
	var spawn_y := get_height_at(spawn_x, spawn_z) + 0.5
	var pos_a := Vector3(spawn_x, spawn_y, spawn_z)

	var far_y := get_height_at(_PORTAL_FAR_X, _PORTAL_FAR_Z)
	if far_y < 0.5:
		far_y = 2.0
	var pos_b := Vector3(_PORTAL_FAR_X, far_y + 0.5, _PORTAL_FAR_Z)

	_DebugPortal.create_portal_pair(self, pos_a, self, pos_b)


func _spawn_starter_goblins() -> void:
	_ZonePopulator._ensure_textures()
	var center_x := 15.0
	var center_z := 15.0
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_hash + 9999
	var spawn_zone := world_to_zone(Vector3(center_x, 0.0, center_z))
	var zone_root: Node3D = _loaded_zones.get(spawn_zone, null)
	if not zone_root:
		print("[WORLD] Starter goblins: zone not loaded at ", spawn_zone)
		return
	var zone_origin_x: float = spawn_zone.x * _ZonePopulator.ZONE_SIZE
	var zone_origin_z: float = spawn_zone.y * _ZonePopulator.ZONE_SIZE
	var spawned := 0
	for i in 5:
		var wx := center_x + rng.randf_range(-5.0, 5.0)
		var wz := center_z + rng.randf_range(-5.0, 5.0)
		var h := get_height_at(wx, wz)
		if h < 0.2:
			h = 1.0
		var goblin := _ZonePopulator._create_enemy(&"hearthlands", rng, &"goblin")
		if not goblin:
			print("[WORLD] Starter goblin %d failed to create" % i)
			continue
		goblin.name = "StarterGoblin_%d" % i
		var lx := wx - zone_origin_x
		var lz := wz - zone_origin_z
		goblin.position = Vector3(lx, h + 0.5, lz)
		zone_root.add_child(goblin)
		spawned += 1
	print("[WORLD] Spawned %d starter goblins near (%.0f, %.0f)" % [spawned, center_x, center_z])


func _queue_zones_around(center: Vector2i) -> void:
	for x in range(center.x - load_radius_zones, center.x + load_radius_zones + 1):
		for z in range(center.y - load_radius_zones, center.y + load_radius_zones + 1):
			var coord := Vector2i(x, z)
			if coord in _loaded_zones or coord in _pending_zones or coord in _gen_in_flight:
				continue
			var world_center := zone_to_world_center(coord)
			if Vector2(world_center.x, world_center.z).length() > world_radius * 1.1:
				continue
			_pending_zones.append(coord)


var _finalize_backlog: Array = []   # zones ready for mesh setup
var _populate_backlog: Array = []   # zones with mesh ready, waiting for object spawning

func _is_in_load_range(coord: Vector2i) -> bool:
	for p in _players:
		var pz := world_to_zone(get_world_position(p))
		if float((coord - pz).length()) <= unload_radius_zones + 1:
			return true
	return false


func _process_pending_zones() -> void:
	# 1. Collect completed background builds — discard stale ones immediately
	_gen_mutex.lock()
	var ready := _gen_ready_queue.duplicate()
	_gen_ready_queue.clear()
	_gen_mutex.unlock()

	for item in ready:
		var coord: Vector2i = item["coord"]
		_gen_in_flight.erase(coord)
		if not _terrain_mesh_cache.has(coord):
			_terrain_mesh_cache[coord] = item["arrays"]
			_terrain_shape_cache[coord] = item["shape"]
		if _is_in_load_range(coord):
			_finalize_backlog.append(item)

	_evict_terrain_cache()

	# 2. Populate one zone's objects (spread across 4 frames per zone)
	while not _populate_backlog.is_empty():
		var pitem: Dictionary = _populate_backlog[0]
		var pcoord: Vector2i = pitem["coord"]
		var zone_root = pitem["zone_root"]  # untyped — may be freed between frames
		if not is_instance_valid(zone_root) or not _is_in_load_range(pcoord):
			_populate_backlog.pop_front()
			continue
		var phase: int = pitem.get("phase", 0)
		var biome: StringName = pitem["biome"]
		var micro: StringName = pitem["micro"]
		var done := _ZonePopulator.populate_zone_phase(zone_root, pcoord, biome, _seed_hash, get_height_at, micro, phase)
		if done:
			_populate_backlog.pop_front()
			var min_dist := 999.0
			for p in _players:
				var pz := world_to_zone(get_world_position(p))
				var d := float((pcoord - pz).length())
				if d < min_dist:
					min_dist = d
			_update_zone_lod(zone_root, min_dist)
			zone_loaded.emit(pcoord)
		else:
			pitem["phase"] = phase + 1
		return  # don't finalize mesh AND populate on the same frame

	# 3. Finalize up to 1 zone mesh per frame to avoid stalls
	var finalized := 0
	while finalized < 1 and not _finalize_backlog.is_empty():
		var item: Dictionary = _finalize_backlog.pop_front()
		var coord: Vector2i = item["coord"]
		if not _is_in_load_range(coord):
			continue
		if coord not in _loaded_zones:
			_finalize_zone(coord, item["arrays"], item["shape"])
			finalized += 1

	# 4. Submit new zone builds — stop if backlog is already large
	if _finalize_backlog.size() + _gen_in_flight.size() > 30:
		return
	var submitted := 0
	while submitted < MAX_ZONES_PER_FRAME and not _pending_zones.is_empty():
		var coord: Vector2i = _pending_zones.pop_front()
		if coord in _loaded_zones or coord in _gen_in_flight:
			continue
		if _terrain_mesh_cache.has(coord):
			var cached_arrays: Array = _terrain_mesh_cache[coord]
			var cached_shape: ConcavePolygonShape3D = _terrain_shape_cache.get(coord)
			_finalize_backlog.append({"coord": coord, "arrays": cached_arrays, "shape": cached_shape})
			submitted += 1
			continue
		_gen_in_flight[coord] = true
		WorkerThreadPool.add_task(_bg_build_zone.bind(coord))
		submitted += 1


func _evict_terrain_cache() -> void:
	if _terrain_mesh_cache.size() <= _MAX_TERRAIN_CACHE:
		return
	var player_zone := world_to_zone(get_world_position(_players[0])) if not _players.is_empty() else Vector2i.ZERO
	var keep_r := unload_radius_zones + 2.0
	var to_evict: Array[Vector2i] = []
	for coord: Vector2i in _terrain_mesh_cache:
		if float((coord - player_zone).length()) > keep_r:
			to_evict.append(coord)
	for coord in to_evict:
		_terrain_mesh_cache.erase(coord)
		_terrain_shape_cache.erase(coord)


const _MAX_UNLOADS_PER_FRAME := 2

func _unload_distant_zones(players: Array[Node3D]) -> void:
	var to_remove: Array[Vector2i] = []
	for coord in _loaded_zones:
		var near_any := false
		for p in players:
			var pz := world_to_zone(get_world_position(p))
			if float((coord - pz).length()) <= unload_radius_zones:
				near_any = true
				break
		if not near_any:
			to_remove.append(coord)
	var unloaded := 0
	for coord in to_remove:
		if unloaded >= _MAX_UNLOADS_PER_FRAME:
			break
		var zone_node: Node = _loaded_zones[coord]
		if zone_node is StaticBody3D:
			_ZonePool.recycle_zone(zone_node as StaticBody3D)
		else:
			zone_node.queue_free()
		_loaded_zones.erase(coord)
		_zone_biome_cache.erase(coord)
		_zone_microbiome_cache.erase(coord)
		_zone_water_cache.erase(coord)
		unloaded += 1
		zone_unloaded.emit(coord)


var _lod_timer := 0.0
const _LOD_INTERVAL := 0.5

func _update_zone_lods(players: Array[Node3D], delta: float) -> void:
	_lod_timer -= delta
	if _lod_timer > 0.0:
		return
	_lod_timer = _LOD_INTERVAL
	var nearest_pz := world_to_zone(get_world_position(players[0])) if not players.is_empty() else Vector2i.ZERO
	for coord in _loaded_zones:
		var min_dist := 999.0
		for p in players:
			var pz := world_to_zone(get_world_position(p))
			var d := float((coord - pz).length())
			if d < min_dist:
				min_dist = d
		var zone_node: Node3D = _loaded_zones[coord]
		if is_instance_valid(zone_node):
			_update_zone_lod(zone_node, min_dist)


func _update_zone_lod(zone_node: Node3D, zone_dist: float) -> void:
	var zone_meta_key := &"lod_level"
	var new_lod: int = 0 if zone_dist <= 1.0 else (1 if zone_dist <= 2.5 else 2)
	var old_lod: int = zone_node.get_meta(zone_meta_key, -1)
	if new_lod == old_lod:
		return
	zone_node.set_meta(zone_meta_key, new_lod)
	for child in zone_node.get_children():
		if not is_instance_valid(child):
			continue
		var cname: String = child.name
		if cname == "TerrainMesh" or cname == "TerrainCol":
			continue
		if cname.begins_with("Grass_") or cname.begins_with("Sapling"):
			child.visible = new_lod <= 1


## Runs on a WorkerThreadPool thread — pure computation, no scene access.
func _bg_build_zone(coord: Vector2i) -> void:
	var arrays := _build_zone_mesh(coord)
	# Build ConcavePolygonShape3D from raw arrays (no ArrayMesh needed)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in indices.size():
		faces[i] = verts[indices[i]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)

	_gen_mutex.lock()
	_gen_ready_queue.append({"coord": coord, "arrays": arrays, "shape": shape})
	_gen_mutex.unlock()


## Main-thread only: creates scene nodes from pre-computed mesh data + shape.
func _finalize_zone(coord: Vector2i, arrays: Array, shape: ConcavePolygonShape3D) -> void:
	if coord in _loaded_zones:
		return
	var biome := _determine_biome(coord)
	var biome_mat: Material = _biome_materials.get(biome, _biome_materials[&"hearthlands"])

	var zone_root := _ZonePool.get_zone_root() as StaticBody3D
	if zone_root:
		zone_root.name = "Zone_%d_%d" % [coord.x, coord.y]
		var mi := zone_root.get_node_or_null("TerrainMesh") as MeshInstance3D
		var col := zone_root.get_node_or_null("TerrainCol") as CollisionShape3D

		var arr_mesh: ArrayMesh = mi.mesh as ArrayMesh if mi and mi.mesh is ArrayMesh else null
		if arr_mesh:
			arr_mesh.clear_surfaces()
		else:
			arr_mesh = ArrayMesh.new()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		arr_mesh.surface_set_material(0, biome_mat)

		if mi:
			mi.mesh = arr_mesh
		else:
			mi = MeshInstance3D.new()
			mi.name = "TerrainMesh"
			mi.mesh = arr_mesh
			zone_root.add_child(mi)
		mi.visible = not _terrain_hidden

		if shape:
			if col:
				col.shape = shape
			else:
				col = CollisionShape3D.new()
				col.name = "TerrainCol"
				col.shape = shape
				zone_root.add_child(col)
		add_child(zone_root)
	else:
		zone_root = StaticBody3D.new()
		zone_root.name = "Zone_%d_%d" % [coord.x, coord.y]
		zone_root.collision_layer = 1
		var arr_mesh := ArrayMesh.new()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		arr_mesh.surface_set_material(0, biome_mat)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "TerrainMesh"
		mesh_instance.mesh = arr_mesh
		mesh_instance.visible = not _terrain_hidden
		var collision := CollisionShape3D.new()
		collision.name = "TerrainCol"
		if shape:
			collision.shape = shape
		zone_root.add_child(mesh_instance)
		zone_root.add_child(collision)
		add_child(zone_root)

	zone_root.global_position = world_to_scene_pos(Vector3(coord.x * ZONE_SIZE, 0.0, coord.y * ZONE_SIZE))
	_loaded_zones[coord] = zone_root
	_explored_zones[coord] = true

	# Queue object spawning for the NEXT frame to keep this frame light
	var micro := _determine_microbiome(coord)
	_populate_backlog.append({
		"coord": coord,
		"zone_root": zone_root,
		"biome": biome,
		"micro": micro,
	})


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
	plane.subdivide_width = 64
	plane.subdivide_depth = 64
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
	add_child(_global_water_plane)
	_global_water_plane.global_position.y = WATER_LEVEL - 0.15


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

			var cn := _color_noise.get_noise_2d(wx, wz)
			var brightness := 0.92 + cn * 0.12
			var path_f := _ZonePopulator.get_path_factor(wx, wz)
			# Blue channel = river bank proximity (0..1) for muddy shoreline blending
			var accum_here := _ws_sample_accum(wx, wz)
			var river_bank := smoothstep(_WS_RIVER_THRESH * 0.3, _WS_RIVER_THRESH * 1.2, accum_here)
			river_bank = clampf(river_bank, 0.0, 1.0)
			colors.append(Color(path_f, brightness, river_bank))

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

var _terrain_shader_fancy: Shader
var _terrain_shader_fast: Shader

var _terrain_hidden := false

func set_terrain_visible(vis: bool) -> void:
	_terrain_hidden = not vis
	for coord in _loaded_zones:
		var zone_node: Node = _loaded_zones[coord]
		if is_instance_valid(zone_node):
			var mi := zone_node.get_node_or_null("TerrainMesh") as MeshInstance3D
			if mi:
				mi.visible = vis


func set_fast_terrain_shader(fast: bool) -> void:
	var target := _terrain_shader_fast if fast else _terrain_shader_fancy
	if not target:
		return
	for biome_id in _biome_materials:
		var mat: ShaderMaterial = _biome_materials[biome_id] as ShaderMaterial
		if mat:
			mat.shader = target


func _init_biome_materials() -> void:
	_terrain_shader_fancy = load("res://shaders/terrain.gdshader") as Shader
	_terrain_shader_fast = load("res://shaders/terrain_fast.gdshader") as Shader
	var terrain_shader := _terrain_shader_fancy

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
		&"hearthlands":     ["grass",        Color(0.20, 0.40, 0.12),  0.5],
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
			mat.set_shader_parameter("origin_shift", origin_shift)
			mat.set_shader_parameter("path_color", Vector3(0.12, 0.07, 0.03))
			mat.set_shader_parameter("bank_color", Vector3(0.12, 0.09, 0.05))
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
	if biome == &"ocean":
		return Color(0.08, 0.18, 0.38)
	return Color(0.20, 0.40, 0.12)


func _check_biome_change(player_zone: Vector2i) -> void:
	var current_biome := _determine_biome(player_zone)
	if current_biome != _last_player_biome:
		_last_player_biome = current_biome
		biome_at_player_changed.emit(current_biome)
		GameEvents.biome_entered.emit(current_biome)


func smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
