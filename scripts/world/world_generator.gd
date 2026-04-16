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
signal zone_explored(coord: Vector2i)
signal world_ready

# ─── World Constants ───────────────────────────────────────────────────────────

@export_group("World")
@export var world_seed: String = "oathbound"
@export var world_radius: float = 10000.0
const ZONE_SIZE := 64.0

@export_group("Loading")
@export var load_radius_zones: int = 2
@export var unload_radius_zones: int = 3
const MAX_ZONES_PER_FRAME := 2
const MESH_RESOLUTION := 48

@export_group("Terrain")
@export var height_scale: float = 30.0
@export var base_frequency: float = 0.003
@export var detail_frequency: float = 0.02

const WATER_LEVEL := 0.0

# ─── Noise Layers ──────────────────────────────────────────────────────────────

var _theme_songs: Array[String] = []
var _seed_hash: int
var _merchant_world_pos: Vector3 = Vector3.ZERO

# ─── Tavern ────────────────────────────────────────────────────────────────────
var _tavern_world_pos := Vector3.ZERO
var _player_in_tavern := false
const _TAVERN_ENTER_DIST := 35.0
const _TAVERN_EXIT_DIST := 50.0
const _TAVERN_MUSIC_PATH := "res://audio/music/tavern/"
var _tavern_songs: Array[String] = [
	_TAVERN_MUSIC_PATH + "song1.mp3",
	_TAVERN_MUSIC_PATH + "song2.mp3",
	_TAVERN_MUSIC_PATH + "song3.mp3",
	_TAVERN_MUSIC_PATH + "song4.mp3",
	_TAVERN_MUSIC_PATH + "song6.mp3",
	_TAVERN_MUSIC_PATH + "song8.mp3",
]
var _merchant_signpost_positions: Array[Vector3] = []
var _marrow_deposit_positions: Array[Vector3] = []
var _continent_noise: FastNoiseLite
var _island_noise: FastNoiseLite
var _mountain_noise: FastNoiseLite
var _mountain_broad_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _mtn_path_noise: FastNoiseLite  # For walkable mountain paths
var _valley_pool_noise: FastNoiseLite  # For water pools in mountain valleys
var _color_noise: FastNoiseLite
var _last_breadth: float = 0.0
var _microbiome_noise: FastNoiseLite
var _microbiome_secondary: FastNoiseLite

# ─── Watershed Grid ───────────────────────────────────────────────────────────

const _WS_CELL := 48.0
const _WS_RIVER_THRESH := 3.5
const _WS_RIVER_FULL := 94.0

const _D8X := [1, 1, 0, -1, -1, -1, 0, 1]
const _D8Z := [0, -1, -1, -1, 0, 1, 1, 1]
const _D8DIST := [1.0, 1.414, 1.0, 1.414, 1.0, 1.414, 1.0, 1.414]

var _ws_dim: int = 0
var _ws_accum: PackedFloat32Array
var _ws_heights: PackedFloat32Array
var _ws_flow: PackedInt32Array

# ─── Elevated Creek Paths ─────────────────────────────────────────────────────
# Creek paths for zones above WATER_LEVEL.  Keyed by zone Vector2i.
# Each value is an Array of Dictionaries:
#   { "points": PackedVector3Array,    -- world XYZ centerline
#     "widths": PackedFloat32Array,    -- half-width at each point
#     "uvs":    PackedFloat32Array }   -- cumulative UV distance for flow scroll
const _CREEK_ACCUM_THRESH := 2.5
const _CREEK_MIN_ELEV := 1.5          # min terrain height above WATER_LEVEL
const _CREEK_MIN_WIDTH := 2.0
const _CREEK_MAX_WIDTH := 33.2
const _CREEK_DEPTH := 2.5             # how deep the channel is carved
const _CREEK_SUBDIV := 8              # interpolation points between grid cells
var _creek_segments: Dictionary = {}   # Vector2i -> Array[Dictionary]
var _creek_shader_mat: ShaderMaterial

# ─── Creek Bed Grid (sparse terrain carving matching creek mesh width) ────────
const _CREEK_BED_CELL := 4.0
var _creek_bed: Dictionary = {}        # Vector2i -> float (target bed height)
var _creek_water_surface: Dictionary = {} # Vector2i -> float (water surface h at cell)

# ─── Terrain Modifications (hoe / leveling) ──────────────────────────────────
# Keyed by Vector2i grid coords (world pos quantized to TERRAIN_MOD_STEP).
# Values are the target height (float).
const TERRAIN_MOD_STEP := ZONE_SIZE / MESH_RESOLUTION  # ~1.33m per grid cell
var _terrain_mods: Dictionary = {}

# ─── Water Physics Grid (Minecraft-style cellular water simulation) ───────────
# Sparse grid aligned with TERRAIN_MOD_STEP. Values are water surface heights.
var _water_grid: Dictionary = {}          # Vector2i -> float (water surface h)
var _water_sources: Dictionary = {}       # Vector2i -> float (permanent source h)
var _water_frontier: Array[Vector2i] = [] # cells queued for propagation
var _water_dirty_zones: Dictionary = {}   # zones needing water mesh rebuild
const WATER_SIM_CELLS_PER_FRAME := 200

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


# ─── Terrain Modification API ─────────────────────────────────────────────────

func flatten_terrain(world_x: float, world_z: float, radius: float) -> void:
	var target_h := get_height_at(world_x, world_z)
	flatten_terrain_to(world_x, world_z, radius, target_h)

const TERRAFORM_MAX_DELTA := 1.0
const TERRAFORM_MIN_HEIGHT := WATER_LEVEL + 2.0

func flatten_terrain_to(world_x: float, world_z: float, radius: float, target_h: float) -> void:
	var affected_zones: Dictionary = {}
	var steps := ceili(radius / TERRAIN_MOD_STEP)
	var cx := roundi(world_x / TERRAIN_MOD_STEP)
	var cz := roundi(world_z / TERRAIN_MOD_STEP)
	var r_sq := radius * radius

	for dz in range(-steps, steps + 1):
		for dx in range(-steps, steps + 1):
			var gx := cx + dx
			var gz := cz + dz
			var wx := gx * TERRAIN_MOD_STEP
			var wz := gz * TERRAIN_MOD_STEP
			var dist_sq := (wx - world_x) * (wx - world_x) + (wz - world_z) * (wz - world_z)
			if dist_sq > r_sq:
				continue
			var blend := 1.0 - sqrt(dist_sq) / radius
			blend = smoothstep(0.0, 1.0, blend)
			var key := Vector2i(gx, gz)
			var existing_h := get_height_at(wx, wz) if not _terrain_mods.has(key) else float(_terrain_mods[key])
			var ideal_h := lerpf(existing_h, target_h, blend)
			var delta := ideal_h - existing_h
			delta = clampf(delta, -TERRAFORM_MAX_DELTA, TERRAFORM_MAX_DELTA)
			var new_h := existing_h + delta
			_terrain_mods[key] = new_h
			var zone := Vector2i(floori(wx / ZONE_SIZE), floori(wz / ZONE_SIZE))
			affected_zones[zone] = true

	for zone_coord: Vector2i in affected_zones:
		rebuild_zone(zone_coord)

	# Water physics notification — disabled until propagation is tuned
	#_notify_water_terrain_changed(world_x, world_z, radius)

var _rebuild_ready_queue: Array = []

func rebuild_zone(coord: Vector2i) -> void:
	_terrain_mesh_cache.erase(coord)
	_terrain_shape_cache.erase(coord)
	_zone_water_cache.erase(coord)

	if coord not in _loaded_zones:
		return
	if coord in _gen_in_flight:
		return
	_gen_in_flight[coord] = true
	WorkerThreadPool.add_task(_bg_rebuild_zone.bind(coord))


func _bg_rebuild_zone(coord: Vector2i) -> void:
	var arrays := _build_zone_mesh(coord)
	var shape := _build_collision_shape(coord)
	_gen_mutex.lock()
	_rebuild_ready_queue.append({"coord": coord, "arrays": arrays, "shape": shape})
	_gen_mutex.unlock()


func _apply_rebuild_results() -> bool:
	# Apply completed terrain rebuilds (from terraform / hoe)
	_gen_mutex.lock()
	if _rebuild_ready_queue.is_empty():
		_gen_mutex.unlock()
		return false
	var item: Dictionary = _rebuild_ready_queue.pop_front()
	_gen_mutex.unlock()

	var coord: Vector2i = item["coord"]
	_gen_in_flight.erase(coord)
	var arrays: Array = item["arrays"]
	var shape: HeightMapShape3D = item["shape"]
	_terrain_mesh_cache[coord] = arrays
	_terrain_shape_cache[coord] = shape

	if coord not in _loaded_zones:
		return false
	var zone_node: Node = _loaded_zones[coord]
	if not zone_node is StaticBody3D:
		return false

	var mi := zone_node.get_node_or_null("TerrainMesh") as MeshInstance3D
	if mi:
		var arr_mesh: ArrayMesh = mi.mesh as ArrayMesh if mi.mesh is ArrayMesh else ArrayMesh.new()
		arr_mesh.clear_surfaces()
		var biome := _determine_biome(coord)
		var biome_mat: Material = _biome_materials.get(biome, _biome_materials[&"hearthlands"])
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		arr_mesh.surface_set_material(0, biome_mat)
		mi.mesh = arr_mesh

	var col := zone_node.get_node_or_null("TerrainCol") as CollisionShape3D
	if col and shape:
		col.shape = shape
		col.position = Vector3(ZONE_SIZE / 2.0, 0.0, ZONE_SIZE / 2.0)
		col.scale = Vector3(ZONE_SIZE / float(MESH_RESOLUTION / 2), 1.0, ZONE_SIZE / float(MESH_RESOLUTION / 2))
		col.disabled = true
		_deferred_collisions.append(col)
		return false
	return false

func get_terrain_mods() -> Dictionary:
	return _terrain_mods.duplicate()

func set_terrain_mods(mods: Dictionary) -> void:
	_terrain_mods = {}
	for key: Vector2i in mods:
		var h := float(mods[key])
		if h < TERRAFORM_MIN_HEIGHT:
			continue
		_terrain_mods[key] = h


func _is_zone_near_player(coord: Vector2i) -> bool:
	for p in _players:
		if p.get("_in_cave"):
			continue
		var pz := world_to_zone(get_world_position(p))
		if absi(coord.x - pz.x) <= 1 and absi(coord.y - pz.y) <= 1:
			return true
	return false


func _force_enable_player_zone_collision(wp: Vector3) -> void:
	var zone_coord := world_to_zone(wp)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var zc := zone_coord + Vector2i(dx, dz)
			var zone_node = _loaded_zones.get(zc)
			if not zone_node:
				continue
			var tc = zone_node.get_node_or_null("TerrainCol")
			if tc and tc.disabled:
				tc.disabled = false
				_deferred_collisions.erase(tc)
			for child in zone_node.get_children():
				if child is CollisionShape3D and child.disabled:
					child.disabled = false
					_deferred_collisions.erase(child)


func _enforce_world_boundary(delta: float) -> void:
	var boundary_start := world_radius * 0.85
	var boundary_hard := world_radius * 0.95
	for p in _players:
		if p.get("_in_cave"):
			continue
		var wp := get_world_position(p)
		var dist := Vector2(wp.x, wp.z).length()
		if dist < boundary_start:
			continue
		var push_t := smoothstep(boundary_start, boundary_hard, dist)
		var push_dir := -Vector2(wp.x, wp.z).normalized()
		var push_mag := lerpf(2.0, 40.0, push_t) * delta
		p.global_position.x += push_dir.x * push_mag
		p.global_position.z += push_dir.y * push_mag
		if dist > boundary_hard:
			var dir_3d := -Vector3(wp.x, 0.0, wp.z).normalized()
			p.global_position += dir_3d * (dist - boundary_hard + 5.0) * 0.1


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
var _pending_zones_set: Dictionary = {}
var _players: Array[Node3D] = []
var _player_cache_timer := 0.0
var _last_player_biome: StringName = &""
var _needs_player_placement := true
var _global_water_plane: MeshInstance3D
var _last_explore_pos := Vector3(INF, INF, INF)
var _zone_water_cache: Dictionary = {}

# Terrain mesh cache: avoids rebuilding ArrayMesh + HeightMapShape3D on zone revisit
var _terrain_mesh_cache: Dictionary = {}  # Vector2i → Array (mesh arrays)
var _terrain_shape_cache: Dictionary = {}  # Vector2i → HeightMapShape3D
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
				zone_explored.emit(zone_coord)
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
	var _t_world_start := Time.get_ticks_usec()
	print("[LAUNCH→WG_READY] start since_launch=%.1fms" % GameEvents.launch_elapsed_ms())
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_ZonePool.flush_all()
	_ZonePopulator.reset_texture_cache()
	_finalize_backlog.clear()
	_populate_backlog.clear()
	_gen_ready_queue.clear()
	_rebuild_ready_queue.clear()
	_gen_in_flight.clear()
	_terrain_mesh_cache.clear()
	_terrain_shape_cache.clear()
	_seed_hash = world_seed.hash()
	add_to_group(&"world_generator")
	var _t0 := Time.get_ticks_usec()
	_init_noise_layers()
	var _t_noise := Time.get_ticks_usec()
	_compute_watershed()
	var _t_watershed := Time.get_ticks_usec()
	_compute_merchant_position()
	var _t_merchant := Time.get_ticks_usec()
	_init_biome_materials()
	_init_water_material()
	_init_creek_material()
	var _t_materials := Time.get_ticks_usec()
	set_render_distance(SaveManager.render_distance)
	_generate_spawn_area()
	var _t_spawn := Time.get_ticks_usec()
	_create_global_water()
	var _t_water := Time.get_ticks_usec()
	var _total_ms := (_t_water - _t_world_start) / 1000.0
	print("[WORLD INIT] total=%.1fms noise=%.1fms watershed=%.1fms merchant=%.1fms materials=%.1fms spawn=%.1fms water=%.1fms seed=%s" % [
		_total_ms,
		(_t_noise - _t0) / 1000.0,
		(_t_watershed - _t_noise) / 1000.0,
		(_t_merchant - _t_watershed) / 1000.0,
		(_t_materials - _t_merchant) / 1000.0,
		(_t_spawn - _t_materials) / 1000.0,
		(_t_water - _t_spawn) / 1000.0,
		world_seed])
	print("[LAUNCH→WG_READY] end since_launch=%.1fms wg_ready_took=%.1fms" % [
		GameEvents.launch_elapsed_ms(), _total_ms])
	_theme_songs = [
		"misty_forest_echoes.mp3",
		"misty_forest_lament.mp3",
		"misty_forest_wanderer_otpjsobu.mp3",
		"misty_forest_wanderer_qh3lws5g.mp3",
		"misty_nordic_forest_theme.mp3",
		"nordic_wilderness_echoes.mp3",
		"whispers_of_the_northern_wild.mp3",
		_TAVERN_MUSIC_PATH + "additional_theme_song.mp3",
	]
	AudioManager.play_music_playlist(_theme_songs, 4.0)
	GameEvents.day_night_changed.connect(_on_day_night_changed)
	world_ready.emit()


func _on_day_night_changed(is_day: bool) -> void:
	if _player_in_tavern:
		return
	if is_day:
		if not _theme_songs.is_empty():
			AudioManager.play_music_playlist(_theme_songs, 4.0)
	else:
		AudioManager.stop_music(3.0)


func _update_tavern_music(player_wp: Vector3) -> void:
	if _tavern_world_pos == Vector3.ZERO:
		return
	var dist := Vector2(player_wp.x - _tavern_world_pos.x, player_wp.z - _tavern_world_pos.z).length()
	if not _player_in_tavern and dist < _TAVERN_ENTER_DIST:
		_player_in_tavern = true
		AudioManager.play_music_playlist(_tavern_songs, 2.0)
	elif _player_in_tavern and dist > _TAVERN_EXIT_DIST:
		_player_in_tavern = false
		var dnc := get_node_or_null("DayNightCycle")
		if dnc and dnc.has_method("is_daytime") and dnc.is_daytime():
			AudioManager.play_music_playlist(_theme_songs, 3.0)
		else:
			AudioManager.stop_music(3.0)


var _diag_timer := 0.0
var _diag_pending := false
var _diag_n_enemies := 0
var _diag_n_interactables := 0
var _diag_n_loot := 0
var _perf_max_queue_ms := 0.0
var _perf_max_pending_ms := 0.0
var _perf_max_unload_ms := 0.0
var _perf_max_explore_ms := 0.0
var _perf_max_total_ms := 0.0
var _perf_pending_size_max := 0
var _last_player_zones: Array[Vector2i] = []  # throttle _queue_zones_around
var _unload_timer := 0.0
var _requeue_timer := 0.0  # periodic re-queue to fill gaps from cap-limited passes
var _any_flying := false
var _clip_recovery_timer := 0.0  # Grace period after clip-through teleport to prevent loop


func _process(_delta: float) -> void:
	if not _diag_pending:
		return
	_diag_pending = false
	var tree := get_tree()
	_diag_n_enemies = tree.get_nodes_in_group(&"enemies").size()
	_diag_n_interactables = tree.get_nodes_in_group(&"interactables").size()
	_diag_n_loot = tree.get_nodes_in_group(&"loot").size()
	var total_nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var vram_mb := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / (1024.0 * 1024.0)
	var buf_mb := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED) / (1024.0 * 1024.0)
	var tex_mb := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED) / (1024.0 * 1024.0)
	var process_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	print("[PERF DIAG] FPS=%d nodes=%d objects=%d draws=%d vram=%.1fMB buf=%.1fMB tex=%.1fMB proc=%.1fms phys=%.1fms zones=%d enemies=%d interact=%d loot=%d explored=%d sub=%d tcache=%d bg=%d mesh_q=%d pop_q=%d %s" % [
		Engine.get_frames_per_second(), int(total_nodes), int(objects),
		int(draw_calls), vram_mb, buf_mb, tex_mb, process_ms, physics_ms,
		_loaded_zones.size(), _diag_n_enemies, _diag_n_interactables, _diag_n_loot,
		_explored_zones.size(), _explored_sub_chunks.size(),
		_terrain_mesh_cache.size(), _gen_in_flight.size(),
		_finalize_backlog.size(), _populate_backlog.size(),
		_ZonePool.get_pool_stats()])
	var displaced := 0
	for coord in _loaded_zones:
		var zn: Node3D = _loaded_zones[coord]
		if is_instance_valid(zn) and zn.is_inside_tree():
			var expected := Vector3(coord.x * ZONE_SIZE, 0.0, coord.y * ZONE_SIZE) - origin_shift
			if zn.global_position.distance_to(expected) > 1.0:
				displaced += 1
	print("[PERF DETAIL] wg_total=%.2fms queue=%.2fms pending=%.2fms unload=%.2fms explore=%.2fms pending_q=%d origin_shift=(%.0f,%.0f) displaced=%d" % [
		_perf_max_total_ms, _perf_max_queue_ms, _perf_max_pending_ms,
		_perf_max_unload_ms, _perf_max_explore_ms, _perf_pending_size_max,
		origin_shift.x, origin_shift.z, displaced])
	# Vegetation debug: count flower MMIs and instances per zone
	var veg_snap := _vegetation_perf_snapshot()
	var cov := _ZonePopulator.get_coverage_stats()
	print("[PERF VEG] fl_mmi=%d fl_inst=%d gr_mmi=%d gr_inst=%d trees=%d grass_cov=%.1f%% (%d/%d) flower_cov=%.1f%% (%d/%d)" % [
		veg_snap["fl_mmi"], veg_snap["fl_inst"], veg_snap["gr_mmi"], veg_snap["gr_inst"], veg_snap["trees"],
		cov["grass_pct"], cov["grass_placed"], cov["grass_tested"],
		cov["flower_pct"], cov["flower_placed"], cov["flower_tested"]])
	if cov["grass_tested"] > 0:
		print("[GRASS REJ] rg=%d (struct=%d river=%d) density=%d (noise=%d path=%d) height=%d slope=%d altitude=%d beach=%d" % [
			cov["rej_rg"], cov["rej_struct"], cov["rej_river"],
			cov["rej_density"], cov.get("rej_density_noise", 0), cov.get("rej_density_path", 0),
			cov["rej_height"], cov["rej_slope"], cov["rej_altitude"], cov.get("rej_beach", 0)])
	_ZonePopulator.reset_coverage_stats()
	_perf_max_queue_ms = 0.0
	_perf_max_pending_ms = 0.0
	_perf_max_unload_ms = 0.0
	_perf_max_explore_ms = 0.0
	_perf_max_total_ms = 0.0
	_perf_pending_size_max = 0


func _vegetation_perf_snapshot() -> Dictionary:
	var fl_mmi := 0
	var fl_inst := 0
	var gr_mmi := 0
	var gr_inst := 0
	var trees := 0
	for coord in _loaded_zones:
		var zone_node: Node3D = _loaded_zones[coord]
		if not is_instance_valid(zone_node):
			continue
		for child in zone_node.get_children():
			if not is_instance_valid(child):
				continue
			var cname: String = child.name
			if cname.begins_with("Flower_") and child is MultiMeshInstance3D:
				fl_mmi += 1
				var mmi := child as MultiMeshInstance3D
				if mmi.multimesh:
					fl_inst += mmi.multimesh.instance_count
			elif cname == "GrassClump" and child is MultiMeshInstance3D:
				gr_mmi += 1
				var mmi := child as MultiMeshInstance3D
				if mmi.multimesh:
					gr_inst += mmi.multimesh.instance_count
			elif child is StaticBody3D and child.has_meta("tree_name"):
				trees += 1
	return {"fl_mmi": fl_mmi, "fl_inst": fl_inst, "gr_mmi": gr_mmi, "gr_inst": gr_inst, "trees": trees}


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()

	_diag_timer -= delta
	if _diag_timer <= 0.0:
		_diag_timer = 5.0
		_diag_pending = true

	_player_cache_timer -= delta
	var _need_refresh := _player_cache_timer <= 0.0 or _players.is_empty()
	if not _need_refresh:
		for p in _players:
			if not is_instance_valid(p):
				_need_refresh = true
				break
	if _need_refresh:
		_player_cache_timer = 1.0
		_players.clear()
		for n in get_tree().get_nodes_in_group(&"player"):
			if n is Node3D and is_instance_valid(n):
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
		if _clip_recovery_timer > 0.0:
			_clip_recovery_timer -= delta
			for p in _players:
				if p.get("_in_cave"):
					continue
				if p.velocity.y < 0.0:
					p.velocity.y = 0.0
		else:
			for p in _players:
				if p.get("_in_cave"):
					continue
				var wp := get_world_position(p)
				var ground := get_height_at(wp.x, wp.z)
				if p.global_position.y < ground - 0.5:
					p.global_position.y = ground + 0.5
					p.velocity = Vector3.ZERO
					_clip_recovery_timer = 0.5
					_force_enable_player_zone_collision(wp)
					var zone_coord := world_to_zone(wp)
					var zone_node = _loaded_zones.get(zone_coord)
					var col_state := "no_zone"
					var lod_level := -1
					if zone_node:
						var tc = zone_node.get_node_or_null("TerrainCol")
						col_state = "enabled" if (tc and not tc.disabled) else ("disabled" if tc else "missing")
						lod_level = zone_node.get_meta(&"lod_level", -1)
					print("[CLIP RECOVERY] frame=%d pos=(%.1f,%.1f,%.1f) world=(%.1f,%.1f,%.1f) ground=%.1f delta=%.1f zone=%s col=%s lod=%d en_q=%d dis_q=%d" % [
						Engine.get_frames_drawn(),
						p.global_position.x, p.global_position.y, p.global_position.z,
						wp.x, wp.y, wp.z, ground, ground - (p.global_position.y - 0.5),
						str(zone_coord), col_state, lod_level,
						_deferred_collisions.size(), _deferred_disable_collisions.size()])

	_enforce_world_boundary(delta)

	var t1 := Time.get_ticks_usec()
	_any_flying = false
	for p in _players:
		if p.get(&"flight_mode"):
			_any_flying = true
			break
	var effective_radius: int = load_radius_zones

	var cur_zones: Array[Vector2i] = []
	for p in _players:
		cur_zones.append(world_to_zone(get_world_position(p)))
	if cur_zones != _last_player_zones:
		_last_player_zones = cur_zones
		for pz in cur_zones:
			_queue_zones_around(pz, effective_radius)
		_requeue_timer = 2.0
	else:
		_requeue_timer -= delta
		if _requeue_timer <= 0.0:
			_requeue_timer = 2.0
			for pz in cur_zones:
				_queue_zones_around(pz, effective_radius)
	var t2 := Time.get_ticks_usec()
	_process_pending_zones()
	var t3 := Time.get_ticks_usec()
	# Adaptive unload: more aggressive when zones accumulate or FPS drops
	var zone_count := _loaded_zones.size()
	var fps := Engine.get_frames_per_second()
	var force_unload := zone_count > _max_loaded_zones * 0.8 or fps < 30
	_unload_timer -= delta
	if force_unload or _unload_timer <= 0.0:
		_unload_timer = 0.2 if force_unload else 0.5
		_unload_distant_zones(_players, force_unload)
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

	# Tavern music zone
	_update_tavern_music(host_wp)


# ═══════════════════════════════════════════════════════════════════════════════
#  NOISE SETUP
# ═══════════════════════════════════════════════════════════════════════════════

func _init_noise_layers() -> void:
	_continent_noise = FastNoiseLite.new()
	_continent_noise.seed = _seed_hash
	_continent_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_continent_noise.frequency = base_frequency
	_continent_noise.fractal_octaves = 4
	_continent_noise.fractal_lacunarity = 2.0
	_continent_noise.fractal_gain = 0.45

	_island_noise = FastNoiseLite.new()
	_island_noise.seed = _seed_hash + 7777
	_island_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_island_noise.frequency = 0.0004
	_island_noise.fractal_octaves = 2
	_island_noise.fractal_lacunarity = 2.0
	_island_noise.fractal_gain = 0.5

	_mountain_noise = FastNoiseLite.new()
	_mountain_noise.seed = _seed_hash + 1000
	_mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mountain_noise.frequency = base_frequency * 1.2
	_mountain_noise.fractal_octaves = 4
	_mountain_noise.fractal_lacunarity = 2.2
	_mountain_noise.fractal_gain = 0.5

	# Large-scale mountain region mask (single octave, very low frequency).
	# Mountains can only grow tall where this noise is strongly positive,
	# ensuring peaks are part of wide mountain chains, not isolated spires.
	_mountain_broad_noise = FastNoiseLite.new()
	_mountain_broad_noise.seed = _seed_hash + 1000
	_mountain_broad_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mountain_broad_noise.frequency = base_frequency * 0.08
	_mountain_broad_noise.fractal_octaves = 1

	_detail_noise = FastNoiseLite.new()
	_detail_noise.seed = _seed_hash + 2000
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = detail_frequency
	_detail_noise.fractal_octaves = 3
	_detail_noise.fractal_lacunarity = 2.0
	_detail_noise.fractal_gain = 0.5

	_ridge_noise = FastNoiseLite.new()
	_ridge_noise.seed = _seed_hash + 3000
	_ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge_noise.frequency = 0.008
	_ridge_noise.fractal_octaves = 3
	_ridge_noise.fractal_lacunarity = 2.0
	_ridge_noise.fractal_gain = 0.5

	# Mountain path noise - creates winding paths up mountains
	_mtn_path_noise = FastNoiseLite.new()
	_mtn_path_noise.seed = _seed_hash + 4000
	_mtn_path_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_mtn_path_noise.frequency = 0.012
	_mtn_path_noise.fractal_octaves = 2
	_mtn_path_noise.fractal_lacunarity = 2.0
	_mtn_path_noise.fractal_gain = 0.5

	# Valley pool noise - creates water in mountain valleys
	_valley_pool_noise = FastNoiseLite.new()
	_valley_pool_noise.seed = _seed_hash + 4500
	_valley_pool_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_valley_pool_noise.frequency = 0.025
	_valley_pool_noise.fractal_octaves = 2
	_valley_pool_noise.fractal_lacunarity = 2.0
	_valley_pool_noise.fractal_gain = 0.5

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

## Sample the broad mountain mask with a guaranteed region near spawn.
func _sample_broad_mountain(wx: float, wz: float) -> float:
	var broad := _mountain_broad_noise.get_noise_2d(wx, wz)
	var spawn_mtn_dist := Vector2(wx - 300.0, wz - 250.0).length()
	return maxf(broad, smoothstep(280.0, 60.0, spawn_mtn_dist))


## Gate fine-detail mountain value by the broad (base-octave) mountain mask.
## Returns 0 where there's no large-scale mountain region, preserving the full
## value inside established mountain chains.
func _gate_mountain(wx: float, wz: float, mountain_raw: float) -> float:
	var spawn_mtn_dist := Vector2(wx - 300.0, wz - 250.0).length()
	var spawn_mtn_boost := smoothstep(280.0, 60.0, spawn_mtn_dist) * 0.5
	mountain_raw = maxf(mountain_raw, spawn_mtn_boost)
	if mountain_raw <= 0.0:
		return 0.0
	var broad := _sample_broad_mountain(wx, wz)
	var breadth := smoothstep(-0.05, 0.30, broad)
	return mountain_raw * breadth


## How strongly this point belongs to a large mountain region (0..1).
## Used to scale peak height so isolated features stay short.
func _mountain_breadth(wx: float, wz: float) -> float:
	var broad := _sample_broad_mountain(wx, wz)
	return smoothstep(-0.05, 0.30, broad)


## Island mask: returns 0..1 where 1 = fully land, 0 = deep ocean.
## Spawn area near (0,0) is always biased toward land.
func _sample_island_mask(wx: float, wz: float) -> float:
	if not _island_noise:
		return 1.0
	var raw := _island_noise.get_noise_2d(wx, wz)
	var spawn_dist := Vector2(wx, wz).length()
	var spawn_bias := smoothstep(2500.0, 400.0, spawn_dist) * 0.55
	raw += spawn_bias
	var s := smoothstep(-0.18, 0.05, raw)
	return s * s * (3.0 - 2.0 * s)


func _get_base_height(wx: float, wz: float) -> float:
	if not _continent_noise:
		return WATER_LEVEL
	var dist := Vector2(wx, wz).length()
	if dist > world_radius * 0.9:
		return -20.0 * ((dist - world_radius * 0.9) / (world_radius * 0.1))

	var island := _sample_island_mask(wx, wz)
	if island < 0.01:
		return WATER_LEVEL - 15.0

	var continent := _continent_noise.get_noise_2d(wx, wz)
	var mountain := _gate_mountain(wx, wz, maxf(_mountain_noise.get_noise_2d(wx, wz) - 0.05, 0.0))
	var breadth := _mountain_breadth(wx, wz)
	var h := continent * height_scale * 0.35

	var foothills := maxf(mountain, 0.0) * smoothstep(0.0, 0.3, mountain)
	h += foothills * height_scale * 1.5
	var peak_ramp := mountain * smoothstep(0.2, 0.5, mountain)
	var peak_intensity := _detail_noise.get_noise_2d(wx * 0.015 + 9000.0, wz * 0.015 + 9000.0)
	peak_intensity = smoothstep(-0.3, 0.6, peak_intensity)
	var mtn_multiplier := lerpf(0.5, 10.0, peak_intensity) * lerpf(0.2, 1.0, breadth)
	h += peak_ramp * height_scale * mtn_multiplier

	var ridge_raw := _ridge_noise.get_noise_2d(wx, wz)
	var ridge := 1.0 - absf(ridge_raw)
	ridge = ridge * ridge * ridge
	var ridge_mult := lerpf(0.1, 1.0, peak_intensity) * lerpf(0.3, 1.0, breadth)
	h += ridge * height_scale * ridge_mult * smoothstep(0.0, 0.15, mountain) - height_scale * 0.02

	var bias := lerpf(7.5, 0.0, smoothstep(world_radius * 0.2, world_radius * 0.80, dist))
	bias *= island
	h += bias

	h = lerpf(WATER_LEVEL - 15.0, h, island)

	var center_dist := Vector2(wx, wz).length()
	if center_dist < 100.0:
		h = lerpf(h, 2.0, 1.0 - smoothstep(0.0, 100.0, center_dist))
	return h


func _compute_watershed() -> void:
	var _t0 := Time.get_ticks_usec()
	_ws_dim = int(ceil(world_radius * 2.0 / _WS_CELL)) + 2
	var n: int = _ws_dim * _ws_dim

	# Step 1 — sample coarse base heights
	_ws_heights = PackedFloat32Array()
	_ws_heights.resize(n)
	var heights := _ws_heights
	for gz in _ws_dim:
		for gx in _ws_dim:
			var wx: float = -world_radius + float(gx) * _WS_CELL
			var wz: float = -world_radius + float(gz) * _WS_CELL
			heights[gz * _ws_dim + gx] = _get_base_height(wx, wz)
	var _t_heights := Time.get_ticks_usec()

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

	# Step 4b — lateral accumulation spreading
	# D8 flow produces 1-cell-wide channels; bilinear interpolation between a
	# river cell and its low-accum neighbor can drop below the carving threshold,
	# leaving terrain uncarved in the middle of rivers.  Spread a fraction of
	# high-accum cells to their immediate neighbors so the carving footprint
	# matches the visual river width.
	var spread := PackedFloat32Array()
	spread.resize(n)
	for i in n:
		spread[i] = _ws_accum[i]
	for gz2 in range(1, _ws_dim - 1):
		for gx2 in range(1, _ws_dim - 1):
			var sidx := gz2 * _ws_dim + gx2
			var src_acc := _ws_accum[sidx]
			if src_acc < _WS_RIVER_THRESH:
				continue
			var give := src_acc * 0.4
			for d in 8:
				var snx: int = gx2 + int(_D8X[d])
				var snz: int = gz2 + int(_D8Z[d])
				if snx < 0 or snx >= _ws_dim or snz < 0 or snz >= _ws_dim:
					continue
				var nidx2: int = snz * _ws_dim + snx
				spread[nidx2] = maxf(spread[nidx2], give)
	_ws_accum = spread

	# Step 5 — store flow directions for creek path tracing
	_ws_flow = flow
	var _t_flow := Time.get_ticks_usec()

	# Step 6 — trace winding outflow streams from noise-driven lakes
	_trace_lake_outflows()
	var _t_lakes := Time.get_ticks_usec()

	# Step 7 — trace elevated creek paths for visual flowing-water strips
	_trace_creek_paths()
	var _t_creeks := Time.get_ticks_usec()

	# Step 8 — stamp creek bed grid for wide terrain carving
	_stamp_creek_bed()
	var _t_bed := Time.get_ticks_usec()

	# Step 9 — water physics source registration — disabled until propagation is tuned
	#_register_water_sources()

	print("[WATERSHED] dim=%d n=%d total=%.1fms heights=%.1fms flow=%.1fms lakes=%.1fms creeks=%.1fms bed=%.1fms creek_segs=%d creek_bed_cells=%d" % [
		_ws_dim, n,
		(_t_bed - _t0) / 1000.0,
		(_t_heights - _t0) / 1000.0,
		(_t_flow - _t_heights) / 1000.0,
		(_t_lakes - _t_flow) / 1000.0,
		(_t_creeks - _t_lakes) / 1000.0,
		(_t_bed - _t_creeks) / 1000.0,
		_creek_segments.size(), _creek_bed.size()])


func _register_water_sources() -> void:
	_water_grid.clear()
	_water_sources.clear()
	_water_frontier.clear()
	for zone_segs in _creek_segments.values():
		for seg in zone_segs:
			var points: PackedVector3Array = seg["points"]
			for i in range(0, points.size(), 3):
				var p := points[i]
				var key := _terrain_mod_key(p.x, p.z)
				_water_sources[key] = p.y


func _simulate_water() -> void:
	if _water_frontier.is_empty():
		return
	var processed := 0
	var next_frontier: Array[Vector2i] = []
	while processed < WATER_SIM_CELLS_PER_FRAME and not _water_frontier.is_empty():
		var cell: Vector2i = _water_frontier.pop_back()
		processed += 1
		if not _water_grid.has(cell):
			continue
		var water_h: float = _water_grid[cell]
		var wx := float(cell.x) * TERRAIN_MOD_STEP
		var wz := float(cell.y) * TERRAIN_MOD_STEP
		var terrain_h := get_height_at(wx, wz)
		if water_h <= terrain_h:
			continue

		var neighbors := [
			Vector2i(cell.x + 1, cell.y),
			Vector2i(cell.x - 1, cell.y),
			Vector2i(cell.x, cell.y + 1),
			Vector2i(cell.x, cell.y - 1),
		]
		for nb in neighbors:
			var nbx := float(nb.x) * TERRAIN_MOD_STEP
			var nbz := float(nb.y) * TERRAIN_MOD_STEP
			var nb_terrain := get_height_at(nbx, nbz)
			var nb_water: float = _water_grid.get(nb, nb_terrain)
			if water_h > nb_water + 0.05:
				var transfer := minf((water_h - nb_water) * 0.25, water_h - terrain_h)
				var new_level := maxf(nb_water + transfer, nb_terrain)
				_water_grid[nb] = new_level
				next_frontier.append(nb)
				var zone := Vector2i(floori(nbx / ZONE_SIZE), floori(nbz / ZONE_SIZE))
				_water_dirty_zones[zone] = true

		if _water_sources.has(cell):
			_water_grid[cell] = maxf(_water_grid[cell], float(_water_sources[cell]))

		var zone := Vector2i(floori(wx / ZONE_SIZE), floori(wz / ZONE_SIZE))
		_water_dirty_zones[zone] = true

	_water_frontier.append_array(next_frontier)


func _notify_water_terrain_changed(world_x: float, world_z: float, radius: float) -> void:
	var steps := ceili(radius / TERRAIN_MOD_STEP) + 2
	var cx := roundi(world_x / TERRAIN_MOD_STEP)
	var cz := roundi(world_z / TERRAIN_MOD_STEP)
	var r_sq := (radius + TERRAIN_MOD_STEP * 2.0) * (radius + TERRAIN_MOD_STEP * 2.0)
	for dz in range(-steps, steps + 1):
		for dx in range(-steps, steps + 1):
			var gx := cx + dx
			var gz := cz + dz
			var wx := float(gx) * TERRAIN_MOD_STEP
			var wz := float(gz) * TERRAIN_MOD_STEP
			var dist_sq := (wx - world_x) * (wx - world_x) + (wz - world_z) * (wz - world_z)
			if dist_sq > r_sq:
				continue
			var key := Vector2i(gx, gz)
			var terrain_h := get_height_at(wx, wz)
			if _water_grid.has(key):
				_water_frontier.append(key)
			else:
				for nb in [Vector2i(gx+1,gz), Vector2i(gx-1,gz), Vector2i(gx,gz+1), Vector2i(gx,gz-1)]:
					if _water_grid.has(nb):
						_water_frontier.append(nb)


func get_water_level_at(x: float, z: float) -> float:
	var key := _terrain_mod_key(x, z)
	if _water_grid.has(key):
		return float(_water_grid[key])
	return get_height_at(x, z)


func get_water_grid() -> Dictionary:
	return _water_grid


func set_water_grid(data: Dictionary) -> void:
	_water_grid = data
	for key: Vector2i in _water_grid:
		if not _water_sources.has(key):
			_water_frontier.append(key)


func _trace_lake_outflows() -> void:
	var claimed := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_hash + 77777

	for gz in range(3, _ws_dim - 3, 3):
		for gx in range(3, _ws_dim - 3, 3):
			var wx: float = -world_radius + float(gx) * _WS_CELL
			var wz: float = -world_radius + float(gz) * _WS_CELL
			var lake_n := _continent_noise.get_noise_2d(wx * 0.7 + 5000.0, wz * 0.7 + 5000.0)
			if lake_n > -0.60:
				continue
			if _ws_accum[gz * _ws_dim + gx] > _WS_RIVER_THRESH:
				continue
			var region := Vector2i(gx / 10, gz / 10)
			if claimed.has(region):
				continue
			claimed[region] = true

			# Find the outflow point: lowest non-lake neighbor
			var best_ex := -1
			var best_ez := -1
			var best_eh := 999999.0
			for sr in range(1, 15):
				for d in 8:
					var ex: int = gx + _D8X[d] * sr
					var ez: int = gz + _D8Z[d] * sr
					if ex < 1 or ex >= _ws_dim - 1 or ez < 1 or ez >= _ws_dim - 1:
						continue
					var ewx := -world_radius + float(ex) * _WS_CELL
					var ewz := -world_radius + float(ez) * _WS_CELL
					var e_lake := _continent_noise.get_noise_2d(ewx * 0.7 + 5000.0, ewz * 0.7 + 5000.0)
					if e_lake >= -0.48:
						var eh := _ws_heights[ez * _ws_dim + ex]
						if eh < best_eh:
							best_eh = eh
							best_ex = ex
							best_ez = ez
				if best_ex >= 0:
					break

			if best_ex < 0:
				continue

			# Trace a winding stream from the outflow point
			var stream_accum := rng.randf_range(5.0, 10.0)
			var pos := Vector2(float(best_ex), float(best_ez))
			var prev_dir := Vector2.ZERO

			for step in 200:
				var cgx := clampi(int(round(pos.x)), 1, _ws_dim - 2)
				var cgz := clampi(int(round(pos.y)), 1, _ws_dim - 2)
				var cidx := cgz * _ws_dim + cgx

				if _ws_accum[cidx] > _WS_RIVER_THRESH * 0.8:
					_ws_accum[cidx] += stream_accum * 0.5
					break

				_ws_accum[cidx] = maxf(_ws_accum[cidx], stream_accum)

				# Steepest descent direction
				var best_d := -1
				var best_s := -999.0
				for d in 8:
					var nx: int = cgx + _D8X[d]
					var nz: int = cgz + _D8Z[d]
					if nx < 0 or nx >= _ws_dim or nz < 0 or nz >= _ws_dim:
						continue
					var s: float = (_ws_heights[cidx] - _ws_heights[nz * _ws_dim + nx]) / _D8DIST[d]
					if s > best_s:
						best_s = s
						best_d = d

				if best_d < 0 or best_s <= 0.0:
					break

				var base_dir := Vector2(float(_D8X[best_d]), float(_D8Z[best_d])).normalized()

				# Noise-driven lateral winding
				var swx := -world_radius + pos.x * _WS_CELL
				var swz := -world_radius + pos.y * _WS_CELL
				var wander := _detail_noise.get_noise_2d(swx * 0.03 + 9000.0, swz * 0.03 + 9000.0)
				var lateral := Vector2(-base_dir.y, base_dir.x)

				var dir := base_dir * 0.7 + lateral * wander * 0.6
				if prev_dir != Vector2.ZERO:
					dir = prev_dir * 0.3 + dir * 0.7
				dir = dir.normalized()
				prev_dir = dir

				pos += dir


func _ws_sample_accum(wx: float, wz: float) -> float:
	if _ws_accum.is_empty() or _ws_dim < 2:
		return 0.0
	var gx: float = (wx + world_radius) / _WS_CELL
	var gz: float = (wz + world_radius) / _WS_CELL
	var ix: int = clampi(int(gx), 0, _ws_dim - 2)
	var iz: int = clampi(int(gz), 0, _ws_dim - 2)
	var max_idx := (iz + 1) * _ws_dim + ix + 1
	if max_idx >= _ws_accum.size():
		return 0.0
	var fx: float = clampf(gx - float(ix), 0.0, 1.0)
	var fz: float = clampf(gz - float(iz), 0.0, 1.0)
	var a: float = _ws_accum[iz * _ws_dim + ix]
	var b: float = _ws_accum[iz * _ws_dim + ix + 1]
	var c: float = _ws_accum[(iz + 1) * _ws_dim + ix]
	var d: float = _ws_accum[(iz + 1) * _ws_dim + ix + 1]
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


func _ws_sample_flow_dir(wx: float, wz: float) -> Vector2:
	if _ws_flow.is_empty() or _ws_dim < 1:
		return Vector2.ZERO
	var gx_f: float = (wx + world_radius) / _WS_CELL
	var gz_f: float = (wz + world_radius) / _WS_CELL
	var gx: int = clampi(int(round(gx_f)), 0, _ws_dim - 1)
	var gz: int = clampi(int(round(gz_f)), 0, _ws_dim - 1)
	var idx := gz * _ws_dim + gx
	if idx >= _ws_flow.size():
		return Vector2.ZERO
	var d_idx: int = _ws_flow[idx]
	if d_idx < 0:
		return Vector2(0, 1)
	return Vector2(float(_D8X[d_idx]), float(_D8Z[d_idx])).normalized()


func _trace_creek_paths() -> void:
	_creek_segments.clear()
	if _ws_accum.is_empty() or _ws_flow.is_empty():
		return

	var visited := {}
	var occupied := {}
	const OCC_CELL := 4.0

	# Collect candidate start cells sorted by accumulation (highest first)
	# so the longest rivers get traced first and shorter tributaries merge into them
	var candidates: Array[Vector3i] = []  # (gx, gz, sort_key)
	for gz in range(1, _ws_dim - 1):
		for gx in range(1, _ws_dim - 1):
			var idx: int = gz * _ws_dim + gx
			var accum: float = _ws_accum[idx]
			if accum < _CREEK_ACCUM_THRESH:
				continue
			var h: float = _ws_heights[idx]
			if h < WATER_LEVEL + _CREEK_MIN_ELEV:
				continue
			# Skip cells already inside the ocean-coast transition zone —
			# rivers spawning there carve ugly trenches along the shoreline.
			var wx_cand: float = -world_radius + float(gx) * _WS_CELL
			var wz_cand: float = -world_radius + float(gz) * _WS_CELL
			if _sample_island_mask(wx_cand, wz_cand) < 0.80:
				continue
			candidates.append(Vector3i(gx, gz, int(accum * 1000.0)))
	candidates.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.z > b.z)

	for cand in candidates:
		var gx: int = cand.x
		var gz: int = cand.y
		var idx: int = gz * _ws_dim + gx
		if visited.has(idx):
			continue

		# Walk upstream against flow to find the highest source point
		var src_gx := gx
		var src_gz := gz
		for _up in 200:
			var best_d := -1
			var best_h := -999.0
			for d in 8:
				var ux: int = src_gx + _D8X[d]
				var uz: int = src_gz + _D8Z[d]
				if ux < 1 or ux >= _ws_dim - 1 or uz < 1 or uz >= _ws_dim - 1:
					continue
				var uid := uz * _ws_dim + ux
				var uflow: int = _ws_flow[uid]
				if uflow < 0:
					continue
				var dnx: int = ux + _D8X[uflow]
				var dnz: int = uz + _D8Z[uflow]
				if dnx == src_gx and dnz == src_gz:
					if _ws_accum[uid] >= _CREEK_ACCUM_THRESH and _ws_heights[uid] > best_h:
						best_d = d
						best_h = _ws_heights[uid]
			if best_d < 0:
				break
			src_gx += _D8X[best_d]
			src_gz += _D8Z[best_d]

		# Trace downstream from the source
		var raw_points: Array[Vector2] = []
		var raw_accums: Array[float] = []
		var cgx := src_gx
		var cgz := src_gz
		var flat_bridges := 0
		for _step in 500:
			var cidx := cgz * _ws_dim + cgx
			if visited.has(cidx):
				raw_points.append(Vector2(float(cgx), float(cgz)))
				raw_accums.append(_ws_accum[cidx])
				break
			visited[cidx] = true

			raw_points.append(Vector2(float(cgx), float(cgz)))
			raw_accums.append(_ws_accum[cidx])

			# Use cached grid height instead of get_height_at — the walk operates
			# at _WS_CELL resolution so the pre-sampled height is exactly what
			# get_height_at would return here, minus much more expensive work.
			var ch: float = _ws_heights[cidx]
			if ch < WATER_LEVEL + 0.1:
				break
			# Stop before we enter the ocean approach zone — rivers that push
			# into it carve weird trenches along the coastline. The ocean is
			# a fine drainage target, we just don't want the last km of river
			# channel to run right along the beach.
			var cur_wx_trace: float = -world_radius + float(cgx) * _WS_CELL
			var cur_wz_trace: float = -world_radius + float(cgz) * _WS_CELL
			if _sample_island_mask(cur_wx_trace, cur_wz_trace) < 0.70:
				break

			var fd: int = _ws_flow[cidx]
			if fd < 0:
				if flat_bridges >= 15:
					break
				var lowest_d := -1
				var lowest_h := ch + 999.0
				for d in 8:
					var bnx: int = cgx + _D8X[d]
					var bnz: int = cgz + _D8Z[d]
					if bnx < 1 or bnx >= _ws_dim - 1 or bnz < 1 or bnz >= _ws_dim - 1:
						continue
					var bh: float = _ws_heights[bnz * _ws_dim + bnx]
					if bh < lowest_h and not visited.has(bnz * _ws_dim + bnx):
						lowest_h = bh
						lowest_d = d
				if lowest_d < 0:
					var best_dx := 0
					var best_dz := 0
					var best_far_h := ch + 999.0
					for fz in range(-2, 3):
						for fx in range(-2, 3):
							if fx == 0 and fz == 0:
								continue
							var fnx := cgx + fx
							var fnz := cgz + fz
							if fnx < 1 or fnx >= _ws_dim - 1 or fnz < 1 or fnz >= _ws_dim - 1:
								continue
							var fid := fnz * _ws_dim + fnx
							if visited.has(fid):
								continue
							var fh: float = _ws_heights[fid]
							if fh < best_far_h:
								best_far_h = fh
								best_dx = fx
								best_dz = fz
					if best_far_h >= ch + 999.0:
						break
					cgx += best_dx
					cgz += best_dz
				else:
					cgx += _D8X[lowest_d]
					cgz += _D8Z[lowest_d]
				flat_bridges += 1
				continue
			flat_bridges = 0
			var nx: int = cgx + _D8X[fd]
			var nz: int = cgz + _D8Z[fd]
			if nx < 0 or nx >= _ws_dim or nz < 0 or nz >= _ws_dim:
				break
			cgx = nx
			cgz = nz

		# Force-extend: if the river ended above water, keep walking toward water.
		# Uses momentum to punch through mountain ridges (gorge carving) rather
		# than wandering along the base. Heights come from the pre-sampled
		# _ws_heights grid so we avoid thousands of expensive get_height_at
		# calls for what are ultimately grid-resolution decisions.
		var ext_idx_end: int = cgz * _ws_dim + cgx
		if _ws_heights[ext_idx_end] > WATER_LEVEL + 0.3 and raw_points.size() >= 2:
			var mom_x := 0.0
			var mom_z := 0.0
			var mom_count: int = mini(raw_points.size(), 6)
			for mi in range(raw_points.size() - mom_count, raw_points.size() - 1):
				mom_x += raw_points[mi + 1].x - raw_points[mi].x
				mom_z += raw_points[mi + 1].y - raw_points[mi].y
			var mom_len := sqrt(mom_x * mom_x + mom_z * mom_z)
			if mom_len > 0.001:
				mom_x /= mom_len
				mom_z /= mom_len

			var ext_visited := {}
			ext_visited[cgz * _ws_dim + cgx] = true
			for _ext in 120:
				var cur_idx: int = cgz * _ws_dim + cgx
				var cur_h: float = _ws_heights[cur_idx]

				var best_d := -1
				var best_h := 99999.0
				for d in 8:
					var enx: int = cgx + _D8X[d]
					var enz: int = cgz + _D8Z[d]
					if enx < 1 or enx >= _ws_dim - 1 or enz < 1 or enz >= _ws_dim - 1:
						continue
					var eid: int = enz * _ws_dim + enx
					if ext_visited.has(eid):
						continue
					var eh: float = _ws_heights[eid]
					if eh < best_h:
						best_h = eh
						best_d = d

				# If all options are uphill and we have momentum, push through
				if best_d >= 0 and best_h > cur_h + 1.0 and mom_len > 0.001:
					var best_mom_d := -1
					var best_dot := -2.0
					for d in 8:
						var enx: int = cgx + _D8X[d]
						var enz: int = cgz + _D8Z[d]
						if enx < 1 or enx >= _ws_dim - 1 or enz < 1 or enz >= _ws_dim - 1:
							continue
						var eid: int = enz * _ws_dim + enx
						if ext_visited.has(eid):
							continue
						var dot := (float(_D8X[d]) * mom_x + float(_D8Z[d]) * mom_z)
						if dot > best_dot:
							best_dot = dot
							best_mom_d = d
					if best_mom_d >= 0 and best_dot > 0.2:
						best_d = best_mom_d
						var mnx: int = cgx + _D8X[best_d]
						var mnz: int = cgz + _D8Z[best_d]
						best_h = _ws_heights[mnz * _ws_dim + mnx]

				if best_d < 0:
					break
				cgx += _D8X[best_d]
				cgz += _D8Z[best_d]
				var ext_idx := cgz * _ws_dim + cgx
				ext_visited[ext_idx] = true
				visited[ext_idx] = true
				var carry_acc: float = raw_accums[raw_accums.size() - 1]
				raw_points.append(Vector2(float(cgx), float(cgz)))
				raw_accums.append(carry_acc)
				if ext_idx < _ws_accum.size():
					_ws_accum[ext_idx] = maxf(_ws_accum[ext_idx], carry_acc)
				if best_h < WATER_LEVEL + 0.1:
					break
				# Same rule as the main trace: stop the forced extension before
				# it rams through the ocean coast.
				var ext_wx: float = -world_radius + float(cgx) * _WS_CELL
				var ext_wz: float = -world_radius + float(cgz) * _WS_CELL
				if _sample_island_mask(ext_wx, ext_wz) < 0.70:
					break

		if raw_points.size() < 2:
			continue

		# Subdivide coarse grid path into smooth world-space polyline
		# with noise-driven lateral meandering and organic width variation
		var points := PackedVector3Array()
		var widths := PackedFloat32Array()
		var flow_uvs := PackedFloat32Array()
		var cum_dist := 0.0
		var entered_pool := false

		for i in raw_points.size() - 1:
			if entered_pool:
				break
			var g0 := raw_points[i]
			var g1 := raw_points[i + 1]
			var a0 := raw_accums[i]
			var a1 := raw_accums[i + 1]

			# Flow direction for perpendicular offset
			var seg_dir := (g1 - g0).normalized()
			var seg_perp := Vector2(-seg_dir.y, seg_dir.x)

			for s in _CREEK_SUBDIV:
				var t_val: float = float(s) / float(_CREEK_SUBDIV)
				var gp := g0.lerp(g1, t_val)
				var wx: float = -world_radius + gp.x * _WS_CELL
				var wz: float = -world_radius + gp.y * _WS_CELL

				# Lateral meandering — multi-scale noise perpendicular to flow
				# Frequencies account for _detail_noise built-in freq of 0.02
				var wander_large := _detail_noise.get_noise_2d(wx * 0.5 + 8000.0, wz * 0.5 + 8000.0) * 3.0
				var wander_med := _detail_noise.get_noise_2d(wx * 2.0 + 9500.0, wz * 2.0 + 9500.0) * 1.5
				var wander_small := _detail_noise.get_noise_2d(wx * 6.0 + 11000.0, wz * 6.0 + 11000.0) * 0.6
				var lateral_offset := wander_large + wander_med + wander_small
				# Taper meander near path endpoints to keep source/sink connected
				var path_t := (float(i) + t_val) / float(raw_points.size() - 1)
				var taper := smoothstep(0.0, 0.12, path_t) * smoothstep(1.0, 0.88, path_t)
				lateral_offset *= taper

				wx += seg_perp.x * lateral_offset * _WS_CELL * 0.18
				wz += seg_perp.y * lateral_offset * _WS_CELL * 0.18

				var occ_key := Vector2i(int(floor(wx / OCC_CELL)), int(floor(wz / OCC_CELL)))
				if occupied.has(occ_key) and not points.is_empty():
					var step_adv := _WS_CELL / float(_CREEK_SUBDIV) * 0.2
					var last_w_occ := widths[widths.size() - 1] if not widths.is_empty() else 1.0
					for ti in 6:
						var tf := float(ti + 1) / 6.0
						var tw := last_w_occ * (1.0 - tf * tf)
						wx += seg_dir.x * step_adv
						wz += seg_dir.y * step_adv
						var ty := get_height_at(wx, wz) + 0.08
						if not points.is_empty():
							cum_dist += Vector3(wx, ty, wz).distance_to(points[points.size() - 1])
						points.append(Vector3(wx, ty, wz))
						widths.append(tw)
						flow_uvs.append(cum_dist)
					entered_pool = true
					break

				var acc := lerpf(a0, a1, t_val)
				var norm_acc := clampf((acc - _CREEK_ACCUM_THRESH) / 20.0, 0.0, 1.0)
				var base_w := lerpf(_CREEK_MIN_WIDTH, _CREEK_MAX_WIDTH, norm_acc) * 0.5
				var width_noise := _detail_noise.get_noise_2d(wx * 1.5 + 13000.0, wz * 1.5 + 13000.0)
				var w := base_w * (0.75 + width_noise * 0.5)

				# Detect pool/water body entry and create smooth transition
				var lake_n := _continent_noise.get_noise_2d(wx * 0.7 + 5000.0, wz * 0.7 + 5000.0)
				var terrain_h := get_height_at(wx, wz)
				var near_pool := lake_n < -0.25 or terrain_h < WATER_LEVEL + 0.3
				var in_pool := (lake_n < -0.35 and terrain_h < WATER_LEVEL - 0.5) or terrain_h < WATER_LEVEL + 0.2

				if in_pool:
					if not points.is_empty():
						var last_y: float = points[points.size() - 1].y
						var drop_y := WATER_LEVEL + 0.05
						var step_advance := _WS_CELL / float(_CREEK_SUBDIV) * 0.3
						for ti in 4:
							var tf := float(ti + 1) / 4.0
							var ease_t := tf * tf
							var ty := lerpf(last_y, drop_y, ease_t)
							wx += seg_dir.x * step_advance
							wz += seg_dir.y * step_advance
							var tw := w * (1.0 + tf * 0.6)
							if not points.is_empty():
								cum_dist += Vector3(wx, ty, wz).distance_to(points[points.size() - 1])
							points.append(Vector3(wx, ty, wz))
							widths.append(tw)
							flow_uvs.append(cum_dist)
					entered_pool = true
					break

				var creek_y: float
				if near_pool:
					var pool_t := 1.0 - clampf((terrain_h - WATER_LEVEL - 0.15) / 0.35, 0.0, 1.0)
					creek_y = lerpf(terrain_h + 0.08, WATER_LEVEL + 0.1, pool_t * pool_t)
				else:
					creek_y = terrain_h + 0.08

				if not points.is_empty():
					var prev := points[points.size() - 1]
					cum_dist += Vector3(wx, creek_y, wz).distance_to(prev)

				points.append(Vector3(wx, creek_y, wz))
				widths.append(w)
				flow_uvs.append(cum_dist)

		# Final point — force a pool transition if the endpoint is near water
		if not entered_pool and points.size() >= 2:
			var last_g := raw_points[raw_points.size() - 1]
			var lwx: float = -world_radius + last_g.x * _WS_CELL
			var lwz: float = -world_radius + last_g.y * _WS_CELL
			# Endpoint sits at a grid cell, so use the cached height instead
			# of a full get_height_at lookup.
			var last_gidx: int = int(last_g.y) * _ws_dim + int(last_g.x)
			var lh: float = _ws_heights[last_gidx] if last_gidx >= 0 and last_gidx < _ws_heights.size() else WATER_LEVEL
			if lh < WATER_LEVEL + 1.0:
				# Close enough to water — add pool transition points
				var last_y: float = points[points.size() - 1].y
				var last_w: float = widths[widths.size() - 1] if not widths.is_empty() else 2.0
				var drop_y := WATER_LEVEL + 0.05
				var last_dir := Vector2.ZERO
				if points.size() >= 2:
					var pa := points[points.size() - 2]
					var pb := points[points.size() - 1]
					last_dir = Vector2(pb.x - pa.x, pb.z - pa.z).normalized()
				if last_dir.length_squared() < 0.001:
					last_dir = Vector2(1, 0)
				var step_advance := _WS_CELL / float(_CREEK_SUBDIV) * 0.3
				for ti in 4:
					var tf := float(ti + 1) / 4.0
					var ease_t := tf * tf
					var ty := lerpf(last_y, drop_y, ease_t)
					lwx += last_dir.x * step_advance
					lwz += last_dir.y * step_advance
					var tw := last_w * (1.0 + tf * 0.6)
					if not points.is_empty():
						cum_dist += Vector3(lwx, ty, lwz).distance_to(points[points.size() - 1])
					points.append(Vector3(lwx, ty, lwz))
					widths.append(tw)
					flow_uvs.append(cum_dist)
				entered_pool = true
			else:
				# Well above water — just add the final point
				var last_acc := raw_accums[raw_accums.size() - 1]
				var last_norm := clampf((last_acc - _CREEK_ACCUM_THRESH) / 20.0, 0.0, 1.0)
				var last_w := lerpf(_CREEK_MIN_WIDTH, _CREEK_MAX_WIDTH, last_norm) * 0.5
				var lw_noise := _detail_noise.get_noise_2d(lwx * 1.5 + 13000.0, lwz * 1.5 + 13000.0)
				last_w *= (0.75 + lw_noise * 0.5)
				if not points.is_empty():
					cum_dist += Vector3(lwx, lh + 0.08, lwz).distance_to(points[points.size() - 1])
				points.append(Vector3(lwx, lh + 0.08, lwz))
				widths.append(last_w)
				flow_uvs.append(cum_dist)

		if points.size() < 2:
			continue

		# Enforce mostly-downhill Y — allow up to 0.3m uphill to follow terrain dips
		var running_min_y := points[0].y
		for pi in range(1, points.size()):
			if points[pi].y > running_min_y + 0.3:
				points[pi].y = running_min_y + 0.3
			running_min_y = minf(running_min_y, points[pi].y)

		# Taper width to zero at source and (non-pool) mouth for smooth endpoints
		var n_pts := points.size()
		var taper_count := mini(6, n_pts / 2)
		for ti in taper_count:
			var t := float(ti) / float(taper_count)
			var ease := t * t
			widths[ti] *= ease
		if not entered_pool:
			for ti in taper_count:
				var t := float(ti) / float(taper_count)
				var ease := t * t
				widths[n_pts - 1 - ti] *= ease

		_bucket_creek_by_zone(points, widths, flow_uvs)

		for pi in points.size():
			var op := points[pi]
			var ow := widths[pi] + 1.0
			var ox_min := int(floor((op.x - ow) / OCC_CELL))
			var ox_max := int(floor((op.x + ow) / OCC_CELL))
			var oz_min := int(floor((op.z - ow) / OCC_CELL))
			var oz_max := int(floor((op.z + ow) / OCC_CELL))
			for ocx in range(ox_min, ox_max + 1):
				for ocz in range(oz_min, oz_max + 1):
					occupied[Vector2i(ocx, ocz)] = true


func _bucket_creek_by_zone(points: PackedVector3Array, widths: PackedFloat32Array, uvs: PackedFloat32Array) -> void:
	var current_zone := Vector2i(floori(points[0].x / ZONE_SIZE), floori(points[0].z / ZONE_SIZE))
	var seg_start := 0

	for i in range(1, points.size()):
		var zone := Vector2i(floori(points[i].x / ZONE_SIZE), floori(points[i].z / ZONE_SIZE))
		if zone != current_zone:
			if i - seg_start >= 2:
				var end_idx := mini(i + 1, points.size())
				_store_creek_segment(current_zone, points, widths, uvs, seg_start, end_idx)
			current_zone = zone
			seg_start = maxi(i - 1, 0)

	if points.size() - seg_start >= 2:
		_store_creek_segment(current_zone, points, widths, uvs, seg_start, points.size())


func _store_creek_segment(zone: Vector2i, points: PackedVector3Array, widths: PackedFloat32Array, uvs: PackedFloat32Array, from: int, to: int) -> void:
	var seg_pts := PackedVector3Array()
	var seg_w := PackedFloat32Array()
	var seg_uv := PackedFloat32Array()
	for i in range(from, to):
		seg_pts.append(points[i])
		seg_w.append(widths[i])
		seg_uv.append(uvs[i])
	if not _creek_segments.has(zone):
		_creek_segments[zone] = []
	(_creek_segments[zone] as Array).append({
		"points": seg_pts,
		"widths": seg_w,
		"uvs": seg_uv,
	})


## Parallel creek-bed stamping. Each worker processes a chunk of creek segments
## into a local Dictionary; main thread min-merges them into _creek_bed.
## Segments only read pre-computed state (_ws_accum, _ws_heights, noise layers,
## _tavern_world_pos) so the inner work is thread-safe.
var _stamp_seg_chunks: Array = []
var _stamp_local_results: Array = []

func _bg_stamp_creek_bed_chunk(i: int) -> void:
	if i < 0 or i >= _stamp_seg_chunks.size():
		return
	var segs: Array = _stamp_seg_chunks[i]
	var local: Dictionary = {}
	var tavern_active := _tavern_world_pos.y > 0.0
	var tavern_x := _tavern_world_pos.x
	var tavern_z := _tavern_world_pos.z
	var tavern_r2 := _TAVERN_FLAT_RADIUS * _TAVERN_FLAT_RADIUS
	for seg in segs:
		var points: PackedVector3Array = seg["points"]
		var widths: PackedFloat32Array = seg["widths"]
		for pi in points.size():
			var p := points[pi]
			var w := widths[pi]

			var raw_h := _get_raw_height_no_paths(p.x, p.z)
			var terrain_excess := maxf(raw_h - p.y, 0.0)
			var local_accum := _ws_sample_accum(p.x, p.z)

			var ridge_bonus := clampf(terrain_excess / 8.0, 0.0, 1.5) * 8.0
			var radius := w + 3.0 + ridge_bonus
			var bed_center := p.y - _CREEK_DEPTH - terrain_excess * 0.4
			if local_accum > _WS_RIVER_THRESH:
				bed_center = minf(bed_center, WATER_LEVEL - 0.5)
			var inner_r := w * 0.75 + ridge_bonus * 0.4

			var cx_min := int(floor((p.x - radius) / _CREEK_BED_CELL))
			var cx_max := int(floor((p.x + radius) / _CREEK_BED_CELL))
			var cz_min := int(floor((p.z - radius) / _CREEK_BED_CELL))
			var cz_max := int(floor((p.z + radius) / _CREEK_BED_CELL))
			var radius_sq := radius * radius

			for cx in range(cx_min, cx_max + 1):
				for cz in range(cz_min, cz_max + 1):
					var cell_wx := (float(cx) + 0.5) * _CREEK_BED_CELL
					var cell_wz := (float(cz) + 0.5) * _CREEK_BED_CELL
					if cell_wx * cell_wx + cell_wz * cell_wz < 2500.0:
						continue
					if tavern_active:
						var t_cdx := cell_wx - tavern_x
						var t_cdz := cell_wz - tavern_z
						if t_cdx * t_cdx + t_cdz * t_cdz < tavern_r2:
							continue
					var dx := cell_wx - p.x
					var dz := cell_wz - p.z
					var dist_sq := dx * dx + dz * dz
					if dist_sq >= radius_sq:
						continue
					var dist := sqrt(dist_sq)
					var carve_h: float
					if dist <= inner_r:
						carve_h = bed_center
					else:
						var bank_t := clampf((dist - inner_r) / maxf(radius - inner_r, 0.01), 0.0, 1.0)
						carve_h = lerpf(bed_center, p.y + 0.5, bank_t * bank_t * bank_t)
					var key := Vector2i(cx, cz)
					if local.has(key):
						local[key] = minf(local[key] as float, carve_h)
					else:
						local[key] = carve_h
	_stamp_local_results[i] = local


func _stamp_creek_bed() -> void:
	_creek_bed.clear()

	# Flatten every zone's segment list into a single array for chunking.
	var all_segs: Array = []
	for zone_segs in _creek_segments.values():
		for seg in zone_segs:
			all_segs.append(seg)
	if all_segs.is_empty():
		return

	# Chunk segments across worker threads. Each chunk builds a local dict
	# independently; we merge with min-reduction at the end. Chunk count
	# matches logical CPU count (capped) to avoid per-task dispatch overhead.
	var chunk_count := clampi(OS.get_processor_count(), 2, 16)
	var per_chunk := int(ceil(float(all_segs.size()) / float(chunk_count)))
	_stamp_seg_chunks.clear()
	var idx := 0
	while idx < all_segs.size():
		var end: int = mini(idx + per_chunk, all_segs.size())
		_stamp_seg_chunks.append(all_segs.slice(idx, end))
		idx = end
	_stamp_local_results.clear()
	_stamp_local_results.resize(_stamp_seg_chunks.size())

	var gid := WorkerThreadPool.add_group_task(_bg_stamp_creek_bed_chunk, _stamp_seg_chunks.size(), -1, true)
	WorkerThreadPool.wait_for_group_task_completion(gid)

	# Merge all per-chunk dictionaries into _creek_bed with min-reduction so
	# overlapping creeks keep the lowest carve depth (deepest channel wins).
	for local: Dictionary in _stamp_local_results:
		for key: Vector2i in local:
			var h: float = local[key]
			if _creek_bed.has(key):
				_creek_bed[key] = minf(_creek_bed[key] as float, h)
			else:
				_creek_bed[key] = h

	_stamp_seg_chunks.clear()
	_stamp_local_results.clear()


# ═══════════════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

func world_to_zone(world_pos: Vector3) -> Vector2i:
	return Vector2i(floori(world_pos.x / ZONE_SIZE), floori(world_pos.z / ZONE_SIZE))


func is_zone_loaded(coord: Vector2i) -> bool:
	return coord in _loaded_zones



func zone_to_world_center(coord: Vector2i) -> Vector3:
	return Vector3(
		(coord.x + 0.5) * ZONE_SIZE,
		0.0,
		(coord.y + 0.5) * ZONE_SIZE
	)


## Returns true if the world position falls inside the carved channel of a
## river/creek (i.e. where water actually flows), not just the gentle banks.
## Grass placement and similar ground clutter use this so plants can grow
## right up to the bank without spawning IN the water.
##
## [param carve_slack] controls how much below the natural (uncarved) terrain
## the bed has to be before the cell counts as "in the channel". Banks in
## [member _creek_bed] store a carve height that lerps up toward the
## surrounding terrain, so a tight slack value excludes them automatically.
func is_in_river_channel(wx: float, wz: float, carve_slack: float = 1.0) -> bool:
	if _creek_bed.is_empty():
		return false
	var cx := int(floor(wx / _CREEK_BED_CELL))
	var cz := int(floor(wz / _CREEK_BED_CELL))
	var key := Vector2i(cx, cz)
	if not _creek_bed.has(key):
		return false
	var raw := _get_raw_height_no_paths(wx, wz)
	return (_creek_bed[key] as float) < raw - carve_slack


## Returns 0..1 ocean-beach factor at (wx, wz). Zero inland and out at sea,
## peaks on the sandy coastal ramp. Mirrors the exact logic used by the
## terrain mesh to paint [member ALBEDO] sand, so populators can reject
## vegetation wherever the terrain renders as beach. Pass the already-known
## terrain height via [param known_h] to avoid a redundant [method
## get_height_at] call on the hot path.
func get_beach_factor(wx: float, wz: float, known_h: float = NAN) -> float:
	if not _island_noise:
		return 0.0
	var island := _sample_island_mask(wx, wz)
	var beach_coast := smoothstep(0.10, 0.35, island) * (1.0 - smoothstep(0.60, 0.95, island))
	if beach_coast <= 0.0:
		return 0.0
	var h: float = known_h if not is_nan(known_h) else get_height_at(wx, wz)
	var beach_alt := clampf(1.0 - smoothstep(WATER_LEVEL - 0.5, WATER_LEVEL + 5.0, h), 0.0, 1.0)
	return clampf(beach_coast * beach_alt, 0.0, 1.0)


func get_biome_at(world_pos: Vector3) -> StringName:
	var zone := world_to_zone(world_pos)
	return _determine_biome(zone)


func get_microbiome_at(world_pos: Vector3) -> StringName:
	var zone := world_to_zone(world_pos)
	return _determine_microbiome(zone)


func get_microbiome_at_zone(coord: Vector2i) -> StringName:
	return _determine_microbiome(coord)


func get_creek_segments_for_zone(coord: Vector2i) -> Array:
	if _creek_segments.has(coord):
		return _creek_segments[coord]
	return []


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
	if accum > _WS_RIVER_THRESH * 0.6:
		micro = &"riverside"
	# Hilly terrain: elevated areas
	elif height > 12.0:
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


func _terrain_mod_key(x: float, z: float) -> Vector2i:
	return Vector2i(roundi(x / TERRAIN_MOD_STEP), roundi(z / TERRAIN_MOD_STEP))


func _sample_terrain_gradient(x: float, z: float, center_h: float) -> float:
	var sample_dist := 4.0
	var h_px := _get_raw_height_no_paths(x + sample_dist, z)
	var h_nx := _get_raw_height_no_paths(x - sample_dist, z)
	var h_pz := _get_raw_height_no_paths(x, z + sample_dist)
	var h_nz := _get_raw_height_no_paths(x, z - sample_dist)
	var dx := (h_px - h_nx) / (sample_dist * 2.0)
	var dz := (h_pz - h_nz) / (sample_dist * 2.0)
	return sqrt(dx * dx + dz * dz)


func _sample_terrain_concavity(x: float, z: float, _mountain_val: float) -> float:
	var sample_dist := 12.0
	var h_c := _get_raw_height_no_paths(x, z)
	var h_px := _get_raw_height_no_paths(x + sample_dist, z)
	var h_nx := _get_raw_height_no_paths(x - sample_dist, z)
	var h_pz := _get_raw_height_no_paths(x, z + sample_dist)
	var h_nz := _get_raw_height_no_paths(x, z - sample_dist)
	var avg_neighbors := (h_px + h_nx + h_pz + h_nz) * 0.25
	return (avg_neighbors - h_c) / maxf(h_c, 1.0)


func _mountain_pool_surface(x: float, z: float) -> float:
	if not _valley_pool_noise:
		return -999.0
	var raw_h := _get_raw_height_no_paths(x, z)
	if raw_h <= 3.0:
		return -999.0
	# Skip areas near river channels — check both creek bed grid and watershed flow
	if _ws_sample_accum(x, z) > _CREEK_ACCUM_THRESH * 0.3:
		return -999.0
	if not _creek_bed.is_empty():
		var cb_ix := int(floor(x / _CREEK_BED_CELL))
		var cb_iz := int(floor(z / _CREEK_BED_CELL))
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				if _creek_bed.has(Vector2i(cb_ix + dx, cb_iz + dz)):
					return -999.0
	var valley_n := _valley_pool_noise.get_noise_2d(x, z)
	if valley_n >= -0.40:
		return -999.0
	var mountain := _gate_mountain(x, z, maxf(_mountain_noise.get_noise_2d(x, z) - 0.15, 0.0))
	var valley_concavity := _sample_terrain_concavity(x, z, mountain)
	if valley_concavity <= 0.3:
		return -999.0
	var pool_t := smoothstep(-0.40, -0.65, valley_n) * smoothstep(0.3, 0.6, valley_concavity)
	if pool_t <= 0.0:
		return -999.0
	var pool_floor := lerpf(raw_h, raw_h - 4.0, pool_t)
	pool_floor = maxf(pool_floor, WATER_LEVEL - 2.0)
	var carved_h := lerpf(raw_h, pool_floor, pool_t * 0.7)
	return lerpf(raw_h, carved_h, 0.5)


func _get_raw_height_no_paths(x: float, z: float) -> float:
	if not _continent_noise:
		return WATER_LEVEL
	var dist := Vector2(x, z).length()
	if dist > world_radius * 0.9:
		return -20.0 * ((dist - world_radius * 0.9) / (world_radius * 0.1))

	var island := _sample_island_mask(x, z)
	if island < 0.01:
		return WATER_LEVEL - 15.0

	var continent := _continent_noise.get_noise_2d(x, z)
	var mountain := _gate_mountain(x, z, maxf(_mountain_noise.get_noise_2d(x, z) - 0.15, 0.0))
	var breadth := _mountain_breadth(x, z)
	var h := continent * height_scale * 0.35
	var foothills := maxf(mountain, 0.0) * smoothstep(0.0, 0.3, mountain)
	h += foothills * height_scale * 1.5
	var peak_ramp := mountain * smoothstep(0.2, 0.5, mountain)
	var peak_intensity := _detail_noise.get_noise_2d(x * 0.015 + 9000.0, z * 0.015 + 9000.0)
	peak_intensity = smoothstep(-0.3, 0.6, peak_intensity)
	var mtn_multiplier := lerpf(0.5, 10.0, peak_intensity) * lerpf(0.2, 1.0, breadth)
	h += peak_ramp * height_scale * mtn_multiplier
	var ridge_raw := _ridge_noise.get_noise_2d(x, z)
	var ridge := 1.0 - absf(ridge_raw)
	ridge = ridge * ridge * ridge
	var ridge_mult := lerpf(0.1, 1.0, peak_intensity) * lerpf(0.3, 1.0, breadth)
	h += ridge * height_scale * ridge_mult * smoothstep(0.0, 0.15, mountain) - height_scale * 0.02

	var bias := lerpf(7.5, 0.0, smoothstep(world_radius * 0.2, world_radius * 0.80, dist))
	bias *= island
	h += bias

	h = lerpf(WATER_LEVEL - 15.0, h, island)
	return h


func get_height_at(x: float, z: float) -> float:
	if not _continent_noise:
		return WATER_LEVEL

	var mod_key := _terrain_mod_key(x, z)
	if _terrain_mods.has(mod_key):
		return _terrain_mods[mod_key] as float

	var dist := Vector2(x, z).length()
	if dist > world_radius * 0.9:
		var edge_factor := (dist - world_radius * 0.9) / (world_radius * 0.1)
		return -20.0 * edge_factor

	var island := _sample_island_mask(x, z)
	if island < 0.01:
		return WATER_LEVEL - 15.0

	var continent := _continent_noise.get_noise_2d(x, z)
	var mountain := _gate_mountain(x, z, maxf(_mountain_noise.get_noise_2d(x, z) - 0.05, 0.0))
	var breadth := _mountain_breadth(x, z)
	_last_breadth = breadth
	var detail := _detail_noise.get_noise_2d(x, z)

	var h := continent * height_scale * 0.35

	var foothills := maxf(mountain, 0.0) * smoothstep(0.0, 0.3, mountain)
	h += foothills * height_scale * 1.5
	var peak_ramp := mountain * smoothstep(0.2, 0.5, mountain)
	var peak_intensity := _detail_noise.get_noise_2d(x * 0.015 + 9000.0, z * 0.015 + 9000.0)
	peak_intensity = smoothstep(-0.3, 0.6, peak_intensity)
	var mtn_multiplier := lerpf(0.5, 10.0, peak_intensity) * lerpf(0.2, 1.0, breadth)
	h += peak_ramp * height_scale * mtn_multiplier

	var ridge_raw := _ridge_noise.get_noise_2d(x, z)
	var ridge := 1.0 - absf(ridge_raw)
	ridge = ridge * ridge * ridge
	var ridge_mult := lerpf(0.1, 1.0, peak_intensity) * lerpf(0.3, 1.0, breadth)
	h += ridge * height_scale * ridge_mult * smoothstep(0.0, 0.15, mountain) - height_scale * 0.02

	h += detail * height_scale * 0.15

	# Broad mountain zone elevation — lifts entire regions so they form
	# connected mountain areas on the map, not scattered peaks
	if breadth > 0.05:
		h += breadth * height_scale * 0.6

	# High-elevation crag detail — reduced and capped for walkable plateaus
	var elev_t := clampf((h - 40.0) / 100.0, 0.0, 1.0)
	if elev_t > 0.0:
		var crag := _detail_noise.get_noise_2d(x * 0.12 + 7000.0, z * 0.12 + 7000.0)
		h += crag * height_scale * 0.06 * elev_t

	# Plateau softening — flatten extreme peaks into explorable plateaus
	var plateau_start := height_scale * 5.0
	if h > plateau_start:
		var excess := h - plateau_start
		h = plateau_start + excess * 0.35

	# Mountain paths - carve wider walkable switchback trails on mountainsides
	if _mtn_path_noise and mountain > 0.20 and h > 12.0:
		var path_raw := _mtn_path_noise.get_noise_2d(x, z)
		var path_raw2 := _mtn_path_noise.get_noise_2d(x * 0.7 + 2000.0, z * 0.7 + 2000.0)
		var path_combined := path_raw * 0.6 + path_raw2 * 0.4
		var path_t := 1.0 - absf(path_combined)
		path_t = smoothstep(0.75, 0.95, path_t)
		if path_t > 0.0:
			var path_width_var := _detail_noise.get_noise_2d(x * 0.08 + 5000.0, z * 0.08 + 5000.0)
			var path_flatten := lerpf(0.4, 0.75, 0.5 + path_width_var * 0.5)
			var mtn_factor := smoothstep(0.20, 0.45, mountain)
			var path_carve := path_t * path_flatten * mtn_factor
			var local_gradient := _sample_terrain_gradient(x, z, h)
			h -= path_carve * local_gradient * height_scale * 0.8

	# Valley pools - water in terrain depressions
	if _valley_pool_noise and h > 3.0:
		var valley_n := _valley_pool_noise.get_noise_2d(x, z)
		var valley_concavity := _sample_terrain_concavity(x, z, mountain)
		if valley_concavity > 0.3 and valley_n < -0.40:
			var pool_t := smoothstep(-0.40, -0.65, valley_n) * smoothstep(0.3, 0.6, valley_concavity)
			if pool_t > 0.0:
				var pool_floor := lerpf(h, h - 4.0, pool_t)
				pool_floor = maxf(pool_floor, WATER_LEVEL - 2.0)
				h = lerpf(h, pool_floor, pool_t * 0.7)

	# Continental bias — fade by distance AND island mask so ocean zones stay submerged
	var bias := lerpf(7.5, 0.0, smoothstep(world_radius * 0.2, world_radius * 0.80, dist))
	bias *= island
	h += bias

	# Sharp shore ramp — snap to full land quickly so only a thin coastal strip goes underwater
	var shore := smoothstep(0.05, 0.25, island)

	# Blend toward deep ocean at island edges for natural shore transitions
	h = lerpf(WATER_LEVEL - 15.0, h, shore)

	# Beach zone — wide band on the ocean side of the coast transition.
	# Peaks where island mask is mid-range (actual shoreline) and fades to
	# zero both out to sea and deeper into the land. We intentionally keep
	# this band wide so every stretch of ocean coast — including noisy
	# pockets where the island mask reaches ~0.90 near the water — still
	# gets a proper beach instead of a grass cliff.
	var beach_zone := smoothstep(0.10, 0.35, island) * (1.0 - smoothstep(0.60, 0.95, island))

	# Land uplift — fill low inland areas with rolling terrain that respects mountain zones
	if shore > 0.3 and h < WATER_LEVEL + 4.0:
		var fill_n := _detail_noise.get_noise_2d(x * 0.008 + 4000.0, z * 0.008 + 4000.0)
		var fill_n2 := _detail_noise.get_noise_2d(x * 0.025 + 6000.0, z * 0.025 + 6000.0)
		var terrain_var := (fill_n * 0.6 + fill_n2 * 0.4) * 4.0 + 2.5
		var base_target := WATER_LEVEL + maxf(terrain_var, 1.0)
		var target := base_target + breadth * height_scale * 0.3
		var lift_t := smoothstep(WATER_LEVEL + 4.0, WATER_LEVEL - 3.0, h)
		# Gate the uplift down inside the beach zone so we don't rebuild the
		# cliff we're trying to eliminate. Near-full suppression (0.98) so
		# beaches stay close to water even when noise would otherwise push
		# them up.
		h = lerpf(h, target, lift_t * shore * (1.0 - beach_zone * 0.98))

	# Watershed river/creek carving — faded out near ocean coasts so rivers
	# stop carving trenches along the shoreline and the coast stays clean
	# for the beach strip instead.
	var coast_carve_mul := smoothstep(0.70, 0.92, island)
	var accum := _ws_sample_accum(x, z)
	if accum > _CREEK_ACCUM_THRESH * 0.5 and coast_carve_mul > 0.01:
		var widen_n := _detail_noise.get_noise_2d(x * 0.025 + 3000.0, z * 0.025 + 3000.0)
		var effective_accum := accum + widen_n * _WS_RIVER_THRESH * 0.35

		if h > WATER_LEVEL + _CREEK_MIN_ELEV and effective_accum < _WS_RIVER_FULL * 0.4:
			var creek_t := smoothstep(_CREEK_ACCUM_THRESH * 0.5, _CREEK_ACCUM_THRESH * 1.5, effective_accum) * coast_carve_mul
			if creek_t > 0.0:
				var norm_acc := clampf((effective_accum - _CREEK_ACCUM_THRESH) / 20.0, 0.0, 1.0)
				var channel_w_factor := lerpf(0.3, 1.0, norm_acc)
				h -= _CREEK_DEPTH * creek_t * channel_w_factor
				if effective_accum > _WS_RIVER_THRESH:
					var river_t := smoothstep(_WS_RIVER_THRESH, _WS_RIVER_THRESH * 3.0, effective_accum)
					var river_floor := WATER_LEVEL - lerpf(0.5, _CREEK_DEPTH, river_t)
					if h > river_floor:
						h = lerpf(h, river_floor, creek_t * river_t)
		else:
			var bank_t := smoothstep(_WS_RIVER_THRESH * 0.5, _WS_RIVER_THRESH * 1.1, effective_accum) * coast_carve_mul
			if bank_t > 0.0:
				h = lerpf(h, WATER_LEVEL + 0.15, bank_t)

			if effective_accum > _WS_RIVER_THRESH:
				var t := smoothstep(_WS_RIVER_THRESH, _WS_RIVER_FULL, effective_accum)
				var depth := lerpf(1.5, 5.0, t)
				var carve := clampf(t * 1.5 + 0.4, 0.0, 1.0) * coast_carve_mul
				h = lerpf(h, WATER_LEVEL - depth, carve)

	# Creek bed grid carving — wide channels matching creek mesh footprints
	if not _creek_bed.is_empty():
		var cb_gx := x / _CREEK_BED_CELL
		var cb_gz := z / _CREEK_BED_CELL
		var cb_ix := int(floor(cb_gx))
		var cb_iz := int(floor(cb_gz))
		var cb_fx := cb_gx - float(cb_ix)
		var cb_fz := cb_gz - float(cb_iz)
		var _CB_NONE := 9999.0
		var a: float = _creek_bed.get(Vector2i(cb_ix, cb_iz), _CB_NONE)
		var b: float = _creek_bed.get(Vector2i(cb_ix + 1, cb_iz), _CB_NONE)
		var c: float = _creek_bed.get(Vector2i(cb_ix, cb_iz + 1), _CB_NONE)
		var d: float = _creek_bed.get(Vector2i(cb_ix + 1, cb_iz + 1), _CB_NONE)
		if a < _CB_NONE or b < _CB_NONE or c < _CB_NONE or d < _CB_NONE:
			a = minf(a, h)
			b = minf(b, h)
			c = minf(c, h)
			d = minf(d, h)
			var bed_h := lerpf(lerpf(a, b, cb_fx), lerpf(c, d, cb_fx), cb_fz)
			if bed_h < h:
				h = bed_h

	# Inland terrain floor — eliminates all sub-water terrain on solid land.
	# The beach zone gets a much lower floor (just above water) and a tiny
	# bit of noise, so we get a smooth sandy ramp instead of the old cliff.
	if shore > 0.5:
		var rolling := (1.0 + continent) * 1.5 + absf(detail) * 2.5
		var floor_h := WATER_LEVEL + 0.5 + rolling + breadth * height_scale * 0.3
		if beach_zone > 0.01:
			var sand_wobble := _detail_noise.get_noise_2d(x * 0.05 + 3700.0, z * 0.05 + 3700.0)
			var beach_floor := WATER_LEVEL + 0.15 + sand_wobble * 0.35
			floor_h = lerpf(floor_h, beach_floor, beach_zone)
		h = maxf(h, floor_h)

	# Active cliff flattening along the ocean coast. maxf above only raises
	# h, so tall coastal cliffs (produced by continent/detail noise) keep
	# their height even inside the beach zone and we end up with grass
	# plateaus that fall straight into the sea. Here we pull any cliff in
	# the beach band down toward the sandy ramp, but only for low/medium
	# cliffs — taller mountains (>6m above water) are left alone so we
	# don't flatten proper coastal cliffs in rocky biomes into beaches.
	if beach_zone > 0.02 and h > WATER_LEVEL + 0.2:
		var over_water := h - WATER_LEVEL
		var flatten_scope := 1.0 - smoothstep(3.0, 6.0, over_water)
		if flatten_scope > 0.0:
			var sand_wobble_f := _detail_noise.get_noise_2d(x * 0.05 + 3700.0, z * 0.05 + 3700.0)
			var beach_target := WATER_LEVEL + 0.15 + sand_wobble_f * 0.35
			h = lerpf(h, beach_target, beach_zone * flatten_scope)

	# Natural lakes — punch through the floor with tight thresholds for rare, large bodies
	if _continent_noise and shore > 0.8:
		var lake_n := _continent_noise.get_noise_2d(x * 0.4 + 5000.0, z * 0.4 + 5000.0)
		if lake_n < -0.58:
			var big_t := smoothstep(-0.68, -0.82, lake_n)
			var small_t := smoothstep(-0.58, -0.72, lake_n)
			var depth := lerpf(lerpf(1.5, 4.0, small_t), lerpf(4.0, 8.0, big_t), big_t)
			var lake_t := maxf(small_t, big_t)
			h = lerpf(h, WATER_LEVEL - depth, lake_t)

	# Flatten spawn area — applied AFTER all water carving so rivers/creeks
	# cannot punch through. Fully flat within 35m, fading out to 80m.
	var center_dist := Vector2(x, z).length()
	if center_dist < 80.0:
		var flatten := 1.0 - smoothstep(35.0, 80.0, center_dist)
		h = lerpf(h, 2.0, flatten)

	# Flatten terrain under the tavern so it sits on level ground
	if _tavern_world_pos.y > 0.0:
		var tdx := x - _tavern_world_pos.x
		var tdz := z - _tavern_world_pos.z
		var tavern_dist := sqrt(tdx * tdx + tdz * tdz)
		if tavern_dist < _TAVERN_FADE_RADIUS:
			var t_flat := 1.0 - smoothstep(_TAVERN_FLAT_RADIUS, _TAVERN_FADE_RADIUS, tavern_dist)
			h = lerpf(h, _tavern_world_pos.y, t_flat)

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
	if dist_norm > 0.9 or (altitude < -2.0 and dist_norm > 0.75):
		biome = &"ocean"
	else:
		biome = &"hearthlands"

	_zone_biome_cache[zone] = biome
	return biome


# ═══════════════════════════════════════════════════════════════════════════════
#  NPC PLACEMENT
# ═══════════════════════════════════════════════════════════════════════════════

func _compute_merchant_position() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_hash + 55555
	var target_dist := 800.0
	const MIN_LAND_H := 4.0
	var best_pos := Vector3.ZERO
	var best_river_dist := 9999.0
	for attempt in 96:
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(target_dist * 0.8, target_dist * 1.2)
		var wx := cos(angle) * dist
		var wz := sin(angle) * dist
		var h := get_height_at(wx, wz)
		if h > WATER_LEVEL + MIN_LAND_H and h < 40.0:
			if _is_solid_land(wx, wz, 8.0, MIN_LAND_H):
				var rdist := _distance_to_nearest_river(wx, wz)
				if rdist < 120.0 and rdist < best_river_dist:
					best_river_dist = rdist
					best_pos = Vector3(wx, h, wz)
				elif best_pos == Vector3.ZERO:
					best_pos = Vector3(wx, h, wz)
	if best_pos != Vector3.ZERO:
		_merchant_world_pos = best_pos
	if _merchant_world_pos == Vector3.ZERO:
		for fallback_attempt in 48:
			var angle := rng.randf_range(0.0, TAU)
			var dist := rng.randf_range(200.0, 600.0)
			var wx := cos(angle) * dist
			var wz := sin(angle) * dist
			var h := get_height_at(wx, wz)
			if h > WATER_LEVEL + MIN_LAND_H and h < 40.0:
				if _is_solid_land(wx, wz, 8.0, MIN_LAND_H):
					_merchant_world_pos = Vector3(wx, h, wz)
					break
	if _merchant_world_pos == Vector3.ZERO:
		_merchant_world_pos = Vector3(600.0, maxf(get_height_at(600.0, 200.0), WATER_LEVEL + MIN_LAND_H), 200.0)
	var mz := Vector2i(int(floor(_merchant_world_pos.x / 64.0)), int(floor(_merchant_world_pos.z / 64.0)))
	print("[MERCHANT] Position set to world (%.1f, %.1f, %.1f) zone %s" % [
		_merchant_world_pos.x, _merchant_world_pos.y, _merchant_world_pos.z, str(mz)])
	_compute_signpost_positions()
	_compute_marrow_positions()


func _is_solid_land(wx: float, wz: float, radius: float, min_h: float) -> bool:
	for dz in [-radius, 0.0, radius]:
		for dx in [-radius, 0.0, radius]:
			if get_height_at(wx + dx, wz + dz) < WATER_LEVEL + min_h:
				return false
	return true


func _compute_signpost_positions() -> void:
	_merchant_signpost_positions.clear()
	var dir := Vector2(_merchant_world_pos.x, _merchant_world_pos.z).normalized()
	var fractions: Array[float] = [0.2, 0.5, 0.75]
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_hash + 55556
	for frac: float in fractions:
		var base: Vector2 = dir * _merchant_world_pos.length() * frac
		var best_pos := Vector3.ZERO
		var search_radius := 40.0
		for attempt in 80:
			if attempt == 20:
				search_radius = 80.0
			elif attempt == 40:
				search_radius = 160.0
			elif attempt == 60:
				search_radius = 300.0
			var offset := Vector2(rng.randf_range(-search_radius, search_radius), rng.randf_range(-search_radius, search_radius))
			var wx: float = base.x + offset.x
			var wz: float = base.y + offset.y
			var h: float = get_height_at(wx, wz)
			if h < WATER_LEVEL + 3.0:
				continue
			if h > 25.0:
				continue
			if not _is_solid_land(wx, wz, 4.0, 2.0):
				continue
			var accum := _ws_sample_accum(wx, wz)
			if accum > 1.5:
				continue
			best_pos = Vector3(wx, h, wz)
			break
		if best_pos == Vector3.ZERO:
			for fallback in 40:
				var angle := rng.randf_range(0.0, TAU)
				var fdist := rng.randf_range(20.0, 200.0)
				var wx := base.x + cos(angle) * fdist
				var wz := base.y + sin(angle) * fdist
				var h := get_height_at(wx, wz)
				if h > WATER_LEVEL + 3.0 and h < 30.0 and _is_solid_land(wx, wz, 4.0, 2.0):
					best_pos = Vector3(wx, h, wz)
					break
		if best_pos == Vector3.ZERO:
			best_pos = _merchant_world_pos
		_merchant_signpost_positions.append(best_pos)


func get_merchant_world_pos() -> Vector3:
	return _merchant_world_pos


func get_signpost_positions() -> Array[Vector3]:
	return _merchant_signpost_positions


func get_marrow_positions() -> Array[Vector3]:
	return _marrow_deposit_positions


func _distance_to_nearest_river(wx: float, wz: float) -> float:
	var best := 9999.0
	var step := 16.0
	for dz in range(-8, 9):
		for dx in range(-8, 9):
			var sx := wx + dx * step
			var sz := wz + dz * step
			var acc := _ws_sample_accum(sx, sz)
			if acc > _WS_RIVER_THRESH * 0.6:
				var dist := sqrt((sx - wx) * (sx - wx) + (sz - wz) * (sz - wz))
				if dist < best:
					best = dist
	return best


func _compute_marrow_positions() -> void:
	_marrow_deposit_positions.clear()
	if _merchant_world_pos == Vector3.ZERO:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_hash + 66666
	var mx := _merchant_world_pos.x
	var mz := _merchant_world_pos.z

	var river_dir := Vector2.ZERO
	var best_acc := 0.0
	var river_pos := Vector2.ZERO
	var step := 12.0
	for dz in range(-10, 11):
		for dx in range(-10, 11):
			var sx := mx + dx * step
			var sz := mz + dz * step
			var acc := _ws_sample_accum(sx, sz)
			if acc > best_acc:
				best_acc = acc
				river_pos = Vector2(sx, sz)
	if best_acc < 1.0:
		river_pos = Vector2(mx + 80.0, mz + 80.0)

	var flow := _ws_sample_flow_dir(river_pos.x, river_pos.y)
	if flow.length_squared() < 0.01:
		flow = Vector2(1, 0)

	var search_center := river_pos + flow * 200.0

	var lake_candidates: Array[Vector3] = []
	for attempt in 120:
		var ox := rng.randf_range(-100.0, 100.0)
		var oz := rng.randf_range(-100.0, 100.0)
		var wx := search_center.x + ox
		var wz := search_center.y + oz
		var h := get_height_at(wx, wz)
		if h > WATER_LEVEL + 0.5 and h < WATER_LEVEL + 5.0:
			var acc := _ws_sample_accum(wx, wz)
			if acc > 1.0 or h < WATER_LEVEL + 2.0:
				lake_candidates.append(Vector3(wx, h, wz))

	if lake_candidates.is_empty():
		for attempt in 60:
			var angle := rng.randf_range(0.0, TAU)
			var dist := rng.randf_range(100.0, 250.0)
			var wx := mx + cos(angle) * dist
			var wz := mz + sin(angle) * dist
			var h := get_height_at(wx, wz)
			if h > WATER_LEVEL + 0.3 and h < WATER_LEVEL + 6.0:
				lake_candidates.append(Vector3(wx, h, wz))

	lake_candidates.shuffle()

	var placed := 0
	var min_spacing := 12.0
	for cand in lake_candidates:
		if placed >= 5:
			break
		var too_close := false
		for existing in _marrow_deposit_positions:
			if cand.distance_to(existing) < min_spacing:
				too_close = true
				break
		if too_close:
			continue
		_marrow_deposit_positions.append(cand)
		placed += 1

	if _marrow_deposit_positions.is_empty():
		var fallback_dir := flow.normalized()
		for i in 5:
			var wx := mx + fallback_dir.x * (150.0 + i * 15.0) + rng.randf_range(-8.0, 8.0)
			var wz := mz + fallback_dir.y * (150.0 + i * 15.0) + rng.randf_range(-8.0, 8.0)
			var h := maxf(get_height_at(wx, wz), WATER_LEVEL + 0.5)
			_marrow_deposit_positions.append(Vector3(wx, h, wz))


# ═══════════════════════════════════════════════════════════════════════════════
#  ZONE LOADING / UNLOADING
# ═══════════════════════════════════════════════════════════════════════════════

func _generate_spawn_area() -> void:
	var _t0 := Time.get_ticks_usec()
	# Find tavern position BEFORE building zone meshes so get_height_at
	# can flatten terrain under the tavern during mesh generation.
	_find_tavern_position()
	var _t_tavern := Time.get_ticks_usec()

	var spawn_zone := world_to_zone(Vector3.ZERO)
	# Collect zones that still need mesh/collision built
	var coords_to_build: Array[Vector2i] = []
	for x in range(spawn_zone.x - 1, spawn_zone.x + 2):
		for z in range(spawn_zone.y - 1, spawn_zone.y + 2):
			var coord := Vector2i(x, z)
			if coord not in _loaded_zones and not _terrain_mesh_cache.has(coord):
				coords_to_build.append(coord)

	# Parallel mesh+collision build across all 9 zones. _build_zone_mesh and
	# _build_collision_shape only read pre-computed noise/watershed data, so
	# they're thread-safe (same invariant the streaming pipeline relies on).
	if not coords_to_build.is_empty():
		_spawn_build_coords = coords_to_build
		_spawn_build_results.clear()
		_spawn_build_results.resize(coords_to_build.size())
		var gid := WorkerThreadPool.add_group_task(_bg_build_spawn_zone, coords_to_build.size(), -1, true)
		WorkerThreadPool.wait_for_group_task_completion(gid)
		for i in coords_to_build.size():
			var c: Vector2i = coords_to_build[i]
			var r: Dictionary = _spawn_build_results[i]
			_terrain_mesh_cache[c] = r["arrays"]
			_terrain_shape_cache[c] = r["shape"]
		_spawn_build_coords.clear()
		_spawn_build_results.clear()
	var _t_build := Time.get_ticks_usec()

	# Finalize all 9 zones (creates scene nodes). Cheap vs the mesh build above.
	for x in range(spawn_zone.x - 1, spawn_zone.x + 2):
		for z in range(spawn_zone.y - 1, spawn_zone.y + 2):
			var coord := Vector2i(x, z)
			if coord not in _loaded_zones and _terrain_mesh_cache.has(coord):
				_finalize_zone(coord, _terrain_mesh_cache[coord], _terrain_shape_cache[coord])
	var _t_finalize := Time.get_ticks_usec()

	# Only enable the CENTER spawn zone's terrain collision immediately (player needs to stand)
	# Leave surrounding zones' terrain in the deferred queue for gradual enabling
	# This prevents a burst from enabling 9+ terrain collision shapes at once
	var center_zone_root = _loaded_zones.get(spawn_zone)
	if center_zone_root:
		var center_col = center_zone_root.get_node_or_null("TerrainCol")
		if center_col:
			center_col.disabled = false
			# Remove it from deferred queue since we enabled it directly
			var idx := _deferred_collisions.find(center_col)
			if idx >= 0:
				_deferred_collisions.remove_at(idx)

	# Force all spawn-area zone roots into the scene tree immediately so that
	# structures added to them are discoverable via get_nodes_in_group.
	# _finalize_zone may have used call_deferred if no players existed yet.
	for x2 in range(spawn_zone.x - 1, spawn_zone.x + 2):
		for z2 in range(spawn_zone.y - 1, spawn_zone.y + 2):
			var zr: Node3D = _loaded_zones.get(Vector2i(x2, z2))
			if zr and not zr.is_inside_tree():
				add_child(zr)

	# Register tavern exclusion zone so vegetation is suppressed even if the
	# tavern node hasn't entered the scene tree yet (belt-and-suspenders).
	_register_tavern_exclusion()

	# Spawn tavern before populating so vegetation avoids its footprint
	_spawn_tavern()

	# Populate phases 0-2 (villages/trees/rocks/creatures) synchronously for ALL
	# 9 spawn zones so the player sees a complete world on spawn. Phases 3-6
	# (grass, flowers, bushes, water plants) are left in _populate_backlog and
	# stream in over the first seconds via _process_pending_zones. A boosted
	# per-frame budget (see _init_populate_boost) drains them quickly without
	# blocking the loading screen.
	var center_pitem: Dictionary = {}
	for i in range(_populate_backlog.size() - 1, -1, -1):
		var pitem: Dictionary = _populate_backlog[i]
		var pcoord: Vector2i = pitem["coord"]
		var zone_root = pitem["zone_root"]
		if not is_instance_valid(zone_root):
			_populate_backlog.remove_at(i)
			continue
		# Run phases 0..2 now — these place trees/rocks/structures which the
		# player would notice missing. Grass/flowers (phases 3-5) and bushes
		# (phase 6) are deferred to the async streaming loop.
		for phase in 3:
			_ZonePopulator.populate_zone_phase(zone_root, pcoord, pitem["biome"], _seed_hash, get_height_at, pitem["micro"], phase, false)
		pitem["phase"] = 3
		var dist := float((pcoord - spawn_zone).length())
		_update_zone_lod(zone_root, dist)
		if pcoord == spawn_zone:
			center_pitem = pitem
	var _t_populate_sync := Time.get_ticks_usec()

	# Fully finish the center zone synchronously so the player lands in a
	# complete environment. Ring zones' remaining phases stream in async.
	if not center_pitem.is_empty():
		var zone_root = center_pitem["zone_root"]
		var pcoord: Vector2i = center_pitem["coord"]
		if is_instance_valid(zone_root):
			var p := int(center_pitem.get("phase", 0))
			while p <= 6:
				var r := _ZonePopulator.populate_zone_phase(zone_root, pcoord, center_pitem["biome"], _seed_hash, get_height_at, center_pitem["micro"], p, false)
				if r >= 1:
					p += 1
			center_pitem["phase"] = 7
			_populate_backlog.erase(center_pitem)
			zone_loaded.emit(pcoord)
	var _t_center := Time.get_ticks_usec()

	# Give the async populate drain a larger budget for the first few seconds
	# so remaining ring-zone phases finish before the player starts exploring.
	_init_populate_boost_frames = 180  # ~3s at 60fps

	_spawn_starter_goblins()
	_dismiss_loading_screen.call_deferred()
	var _t_done := Time.get_ticks_usec()
	print("[SPAWN AREA] total=%.1fms tavern=%.1fms build=%.1fms(x%d parallel) finalize=%.1fms populate_p012=%.1fms center_p346=%.1fms backlog_left=%d" % [
		(_t_done - _t0) / 1000.0,
		(_t_tavern - _t0) / 1000.0,
		(_t_build - _t_tavern) / 1000.0, coords_to_build.size(),
		(_t_finalize - _t_build) / 1000.0,
		(_t_populate_sync - _t_finalize) / 1000.0,
		(_t_center - _t_populate_sync) / 1000.0,
		_populate_backlog.size()])


# ─── Parallel spawn-zone build plumbing ──────────────────────────────────────

var _spawn_build_coords: Array[Vector2i] = []
var _spawn_build_results: Array = []

## Runs on WorkerThreadPool — builds one spawn-area zone's mesh + collision.
func _bg_build_spawn_zone(i: int) -> void:
	if i < 0 or i >= _spawn_build_coords.size():
		return
	var coord: Vector2i = _spawn_build_coords[i]
	var arrays := _build_zone_mesh(coord)
	var shape := _build_collision_shape(coord)
	_spawn_build_results[i] = {"arrays": arrays, "shape": shape}


# Boost populate budget for N physics frames after world init so deferred
# phases (grass/flowers/bushes) for ring zones finish quickly.
var _init_populate_boost_frames: int = 0


func _dismiss_loading_screen() -> void:
	print("[LAUNCH→DISMISS] called since_launch=%.1fms" % GameEvents.launch_elapsed_ms())
	await get_tree().process_frame
	await get_tree().process_frame
	var ls := get_tree().root.get_node_or_null("LoadingScreen")
	if ls and ls.has_method("dismiss"):
		ls.dismiss()
	print("[LAUNCH→DISMISS] done since_launch=%.1fms  <<< user sees world here" % GameEvents.launch_elapsed_ms())


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


func _spawn_village_cave_entrance() -> void:
	var cx := 40.0
	var cz := 32.0
	var cy := get_height_at(cx, cz)
	if cy < 0.5:
		cy = 1.0
	var entrance := CaveGenerator.create_entrance_marker(Vector3.FORWARD)
	add_child(entrance)
	entrance.global_position = world_to_scene_pos(Vector3(cx, cy, cz))
	print("[CAVE] Village cave entrance placed at world (%s, %s, %s) scene %s" % [cx, cy, cz, entrance.global_position])


func _spawn_starter_goblins() -> void:
	_ZonePopulator._ensure_textures()
	var center_x := 32.0
	var center_z := 40.0
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


const _TAVERN_FLAT_RADIUS := 38.0
const _TAVERN_FADE_RADIUS := 50.0

func _find_tavern_position() -> void:
	var best_wx := 48.0
	var best_wz := 10.0
	var best_score := -999.0
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_hash + 77777
	for attempt in 60:
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(40.0, 70.0)
		var wx := cos(angle) * dist
		var wz := sin(angle) * dist
		var h := get_height_at(wx, wz)
		if h < WATER_LEVEL + 1.5 or h > 15.0:
			continue
		var accum := _ws_sample_accum(wx, wz)
		if accum > 1.0:
			continue
		var flat_ok := true
		var h_sum := h
		var h_count := 1
		for si in 8:
			var sa := float(si) * TAU / 8.0
			for sr in [12.0, 24.0, 36.0]:
				var sh := get_height_at(wx + cos(sa) * sr, wz + sin(sa) * sr)
				h_sum += sh
				h_count += 1
				if absf(sh - h) > 2.5:
					flat_ok = false
				var sa_accum := _ws_sample_accum(wx + cos(sa) * sr, wz + sin(sa) * sr)
				if sa_accum > 1.5:
					flat_ok = false
		if not flat_ok:
			continue
		var avg_h := h_sum / float(h_count)
		var score := avg_h - absf(h - avg_h) * 5.0
		if score > best_score:
			best_score = score
			best_wx = wx
			best_wz = wz
	var base_h := maxf(get_height_at(best_wx, best_wz), 2.0)
	_tavern_world_pos = Vector3(best_wx, base_h, best_wz)
	print("[TAVERN] Selected position (%.1f, %.1f) h=%.1f score=%.1f" % [best_wx, best_wz, base_h, best_score])


func _register_tavern_exclusion() -> void:
	if _tavern_world_pos == Vector3.ZERO:
		return
	_ZonePopulator._forced_exclusion_circles.append([
		_tavern_world_pos.x, _tavern_world_pos.z, _TAVERN_FLAT_RADIUS + 2.0])


func _spawn_tavern() -> void:
	if _tavern_world_pos == Vector3.ZERO:
		print("[TAVERN] No valid position found")
		return
	var tavern_wx := _tavern_world_pos.x
	var tavern_wz := _tavern_world_pos.z
	var tavern_h := get_height_at(tavern_wx, tavern_wz)

	var spawn_zone := world_to_zone(Vector3(tavern_wx, 0.0, tavern_wz))
	var zone_root: Node3D = _loaded_zones.get(spawn_zone, null)
	if not zone_root:
		print("[TAVERN] Zone not loaded at ", spawn_zone)
		return

	var zone_origin_x: float = spawn_zone.x * _ZonePopulator.ZONE_SIZE
	var zone_origin_z: float = spawn_zone.y * _ZonePopulator.ZONE_SIZE

	var tavern := _ZonePopulator.build_tavern(
		zone_root, tavern_wx, tavern_wz, tavern_h)
	tavern.position = Vector3(tavern_wx - zone_origin_x, tavern_h - 0.65, tavern_wz - zone_origin_z)

	_tavern_world_pos = Vector3(tavern_wx, tavern_h, tavern_wz)
	print("[TAVERN] Placed at world (%.1f, %.1f, %.1f)" % [tavern_wx, tavern_h, tavern_wz])


var _max_loaded_zones: int = 50

func _queue_zones_around(center: Vector2i, radius: int = -1) -> void:
	if radius < 0:
		radius = load_radius_zones
	var total_queued := _loaded_zones.size() + _pending_zones.size() + _gen_in_flight.size()
	for x in range(center.x - radius, center.x + radius + 1):
		for z in range(center.y - radius, center.y + radius + 1):
			if total_queued >= _max_loaded_zones:
				return
			var coord := Vector2i(x, z)
			if coord in _loaded_zones or coord in _pending_zones_set or coord in _gen_in_flight:
				continue
			var world_center := zone_to_world_center(coord)
			if Vector2(world_center.x, world_center.z).length() > world_radius * 1.1:
				continue
			_pending_zones.append(coord)
			_pending_zones_set[coord] = true
			total_queued += 1
	# Nearest zones first so the player's surroundings always load before distant ones
	_pending_zones.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da := (a - center).length_squared()
		var db := (b - center).length_squared()
		return da < db
	)


var _finalize_backlog: Array = []   # zones ready for mesh setup
var _populate_backlog: Array = []   # zones with mesh ready, waiting for object spawning
var _deferred_collisions: Array = []  # collision shapes to enable next frame (untyped to handle freed instances)
var _deferred_disable_collisions: Array = []  # collision shapes to disable next frame (untyped to handle freed)

func _is_in_load_range(coord: Vector2i) -> bool:
	for p in _players:
		var pz := world_to_zone(get_world_position(p))
		if float((coord - pz).length()) <= unload_radius_zones + 1:
			return true
	return false


const _PENDING_BUDGET_US := 2000  # max microseconds per frame for pending work
const _INIT_POPULATE_BUDGET_US := 8000  # boosted budget during init backlog drain
const _MAX_COLLISION_ENABLES_PER_FRAME := 3
const _MAX_COLLISION_DISABLES_PER_FRAME := 2

var _init_backlog_drained_logged := false

func _process_pending_zones() -> void:
	var t_start := Time.get_ticks_usec()
	# Boost the per-frame budget for a few seconds after world init so the
	# deferred grass/flower phases for ring zones finish before the player
	# notices missing vegetation.
	var budget_us := _PENDING_BUDGET_US
	if _init_populate_boost_frames > 0:
		_init_populate_boost_frames -= 1
		budget_us = _INIT_POPULATE_BUDGET_US

	# One-shot: announce when the initial spawn-area populate backlog is empty
	# (grass/flowers/bushes for all 9 spawn zones done). Combined with gen_in_flight
	# == 0 this tells us when the world is fully "settled" after spawn.
	if not _init_backlog_drained_logged and GameEvents.launch_ts_us > 0:
		if _populate_backlog.is_empty() and _gen_in_flight.is_empty() and _finalize_backlog.is_empty():
			_init_backlog_drained_logged = true
			print("[LAUNCH→BACKLOG_DRAINED] since_launch=%.1fms  <<< async spawn-area populate complete" % GameEvents.launch_elapsed_ms())

	# 0-pre. Build player zone list (used by multiple steps below)
	var player_zones: Array[Vector2i] = []
	for p in _players:
		if p.get("_in_cave"):
			continue
		player_zones.append(world_to_zone(get_world_position(p)))

	# 0a. Guarantee: TerrainCol is ALWAYS enabled in the 3x3 grid around every player.
	# This runs unconditionally every frame — no queue dependency.
	for pz in player_zones:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var zc := pz + Vector2i(dx, dz)
				var zone_node = _loaded_zones.get(zc)
				if not zone_node:
					continue
				var tc = zone_node.get_node_or_null("TerrainCol")
				if tc and tc.disabled:
					tc.disabled = false
					_deferred_collisions.erase(tc)
					_deferred_disable_collisions.erase(tc)

	# 0b. Fast-path: enable queued collision shapes near any player (capped)
	if not _deferred_collisions.is_empty():
		var remaining: Array = []
		var near_enabled := 0
		for col_shape in _deferred_collisions:
			if not is_instance_valid(col_shape):
				continue
			var parent = col_shape.get_parent()
			if not parent:
				remaining.append(col_shape)
				continue
			if not parent.has_meta(&"zone_coord"):
				if near_enabled < 4:
					col_shape.disabled = false
					near_enabled += 1
				else:
					remaining.append(col_shape)
				continue
			var zc: Vector2i = parent.get_meta(&"zone_coord") as Vector2i
			var near_player := false
			for pz in player_zones:
				if absi(zc.x - pz.x) <= 1 and absi(zc.y - pz.y) <= 1:
					near_player = true
					break
			if near_player and near_enabled < 4:
				col_shape.disabled = false
				near_enabled += 1
			else:
				remaining.append(col_shape)
		_deferred_collisions = remaining

	# 0c. Process remaining collision shape toggles under budget
	var enables_this_frame := 0
	while not _deferred_collisions.is_empty() and enables_this_frame < _MAX_COLLISION_ENABLES_PER_FRAME:
		var col_shape = _deferred_collisions.pop_front()
		if is_instance_valid(col_shape):
			col_shape.disabled = false
			enables_this_frame += 1

	# 0d. Process deferred disables — skip any that are near a player
	var disables_this_frame := 0
	var disable_remaining: Array = []
	while not _deferred_disable_collisions.is_empty():
		var col_shape = _deferred_disable_collisions.pop_front()
		if not is_instance_valid(col_shape):
			continue
		var parent = col_shape.get_parent()
		if parent and parent.has_meta(&"zone_coord"):
			var zc: Vector2i = parent.get_meta(&"zone_coord") as Vector2i
			var near := false
			for pz in player_zones:
				if absi(zc.x - pz.x) <= 1 and absi(zc.y - pz.y) <= 1:
					near = true
					break
			if near:
				continue
		if disables_this_frame < _MAX_COLLISION_DISABLES_PER_FRAME:
			col_shape.disabled = true
			disables_this_frame += 1
		else:
			disable_remaining.append(col_shape)
	_deferred_disable_collisions = disable_remaining

	# 0.5. Apply completed terrain rebuilds (from terraform / hoe)
	_apply_rebuild_results()

	# 0.6. Water physics simulation — disabled until propagation is tuned
	#_simulate_water()
	#_rebuild_dirty_water_meshes()

	# 1. Collect completed background builds — cap per frame to prevent burst spikes
	# PERF: Reduced from 4 to 2 to spread work across more frames
	const _MAX_READY_PER_FRAME := 2
	_gen_mutex.lock()
	var ready: Array = _gen_ready_queue.duplicate()
	_gen_ready_queue.clear()
	_gen_mutex.unlock()

	var ready_count := 0
	for item in ready:
		if ready_count >= _MAX_READY_PER_FRAME:
			_gen_mutex.lock()
			_gen_ready_queue.append(item)
			_gen_mutex.unlock()
			continue
		var coord: Vector2i = item["coord"]
		_gen_in_flight.erase(coord)
		if not _terrain_mesh_cache.has(coord):
			_terrain_mesh_cache[coord] = item["arrays"]
			_terrain_shape_cache[coord] = item["shape"]
		if _is_in_load_range(coord):
			_finalize_backlog.append(item)
		elif coord not in _pending_zones_set:
			_pending_zones.append(coord)
			_pending_zones_set[coord] = true
		ready_count += 1

	_evict_terrain_cache()

	# 2. Populate zone objects — budget-checked before EVERY phase so no single phase blows the frame
	#    Sort by distance to closest player so nearby zones fill in first
	if _populate_backlog.size() > 1:
		var _sort_pz := world_to_zone(get_world_position(_players[0])) if not _players.is_empty() else Vector2i.ZERO
		_populate_backlog.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float((a["coord"] - _sort_pz).length_squared()) < float((b["coord"] - _sort_pz).length_squared())
		)
	while not _populate_backlog.is_empty():
		if Time.get_ticks_usec() - t_start > budget_us:
			break
		var pitem: Dictionary = _populate_backlog[0]
		var pcoord: Vector2i = pitem["coord"]
		var zone_root = pitem["zone_root"]  # untyped — may be freed between frames
		var current_zone = _loaded_zones.get(pcoord)
		if not is_instance_valid(zone_root) or not _is_in_load_range(pcoord) or zone_root != current_zone:
			_populate_backlog.pop_front()
			continue
		var phase: int = pitem.get("phase", 0)
		var biome: StringName = pitem["biome"]
		var micro: StringName = pitem["micro"]
		var result := _ZonePopulator.populate_zone_phase(zone_root, pcoord, biome, _seed_hash, get_height_at, micro, phase)
		if result == 2:
			_populate_backlog.pop_front()
			var min_dist := 999.0
			for p in _players:
				var pz := world_to_zone(get_world_position(p))
				var d := float((pcoord - pz).length())
				if d < min_dist:
					min_dist = d
			_update_zone_lod(zone_root, min_dist)
			zone_loaded.emit(pcoord)
			continue
		if result == 1:
			pitem["phase"] = phase + 1

	# 3. Finalize zone meshes — budget-checked after each to prevent stacked heavy frames
	var max_finalize := 2
	var finalized := 0
	if Time.get_ticks_usec() - t_start < budget_us:
		while not _finalize_backlog.is_empty() and finalized < max_finalize:
			if finalized > 0 and Time.get_ticks_usec() - t_start > budget_us:
				break
			var item: Dictionary = _finalize_backlog.pop_front()
			var coord: Vector2i = item["coord"]
			if not _is_in_load_range(coord):
				if coord not in _pending_zones_set and coord not in _loaded_zones:
					_pending_zones.append(coord)
					_pending_zones_set[coord] = true
				continue
			if coord not in _loaded_zones:
				_finalize_zone(coord, item["arrays"], item["shape"])
				finalized += 1

	# 4. Submit new zone builds — stop if backlog is already large
	var max_backlog := 6
	if _finalize_backlog.size() + _gen_in_flight.size() > max_backlog:
		return
	var zones_this_frame := MAX_ZONES_PER_FRAME
	var submitted := 0
	while submitted < zones_this_frame and not _pending_zones.is_empty():
		var coord: Vector2i = _pending_zones.pop_front()
		_pending_zones_set.erase(coord)
		if coord in _loaded_zones or coord in _gen_in_flight:
			continue
		if _terrain_mesh_cache.has(coord):
			var cached_arrays: Array = _terrain_mesh_cache[coord]
			var cached_shape: HeightMapShape3D = _terrain_shape_cache.get(coord)
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


const _MAX_UNLOADS_PER_FRAME := 4


func _clear_zone_collisions_from_queues(zone_node: Node) -> void:
	# Remove collision shapes belonging to this zone from deferred queues
	# This prevents "freed instance" crash when accessing shapes from unloaded zones
	for i in range(_deferred_collisions.size() - 1, -1, -1):
		var shape = _deferred_collisions[i]
		if not is_instance_valid(shape):
			_deferred_collisions.remove_at(i)
		elif is_instance_valid(shape.get_parent()):
			var parent = shape.get_parent()
			if parent == zone_node or (is_instance_valid(parent.get_parent()) and parent.get_parent() == zone_node):
				_deferred_collisions.remove_at(i)
	for i in range(_deferred_disable_collisions.size() - 1, -1, -1):
		var shape = _deferred_disable_collisions[i]
		if not is_instance_valid(shape):
			_deferred_disable_collisions.remove_at(i)
		elif is_instance_valid(shape.get_parent()):
			var parent = shape.get_parent()
			if parent == zone_node or (is_instance_valid(parent.get_parent()) and parent.get_parent() == zone_node):
				_deferred_disable_collisions.remove_at(i)


func _unload_distant_zones(players: Array[Node3D], force_aggressive: bool = false) -> void:
	var any_flying := false
	for p in players:
		if p.get(&"flight_mode"):
			any_flying = true
			break
	var effective_unload: float = float(unload_radius_zones)
	# When forcing aggressive unload, tighten the radius
	if force_aggressive:
		effective_unload = maxf(effective_unload - 1.0, float(load_radius_zones))
	var to_remove: Array[Vector2i] = []
	for coord in _loaded_zones:
		var near_any := false
		for p in players:
			var pz := world_to_zone(get_world_position(p))
			if float((coord - pz).length()) <= effective_unload:
				near_any = true
				break
		if not near_any:
			to_remove.append(coord)
	# Sort by distance so we unload farthest zones first
	if not players.is_empty():
		var primary_pz := world_to_zone(get_world_position(players[0]))
		to_remove.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return (a - primary_pz).length_squared() > (b - primary_pz).length_squared()
		)
	# Cap unloads to avoid physics spikes from tearing down many bodies at once
	# Maximum 6 zones/frame even in aggressive mode (was 16, caused huge spikes)
	var max_unloads := _MAX_UNLOADS_PER_FRAME
	if force_aggressive or any_flying:
		max_unloads = 6  # Capped at 6 to prevent physics spike from mass body removal
	var unloaded := 0
	for coord in to_remove:
		if unloaded >= max_unloads:
			break
		var zone_node: Node = _loaded_zones[coord]
		# Clear collision shapes from deferred queues BEFORE freeing to prevent crash
		_clear_zone_collisions_from_queues(zone_node)
		if zone_node is StaticBody3D:
			_ZonePool.recycle_zone(zone_node as StaticBody3D)
		else:
			zone_node.queue_free()
		_loaded_zones.erase(coord)
		_zone_biome_cache.erase(coord)
		_zone_microbiome_cache.erase(coord)
		_zone_water_cache.erase(coord)
		for i in range(_populate_backlog.size() - 1, -1, -1):
			if _populate_backlog[i]["coord"] == coord:
				_populate_backlog.remove_at(i)
		_ZonePopulator._grass_cursor_clear(coord)
		unloaded += 1
		zone_unloaded.emit(coord)


var _lod_update_index := 0
var _lod_zone_keys: Array = []  # Cache of zone coordinates for cycling
const _MAX_LOD_UPDATES_PER_FRAME := 8  # Process max 8 zones per frame to spread work

func _update_zone_lods(players: Array[Node3D], _delta: float) -> void:
	# Rebuild zone key list if it changed (zones loaded/unloaded)
	var current_keys := _loaded_zones.keys()
	if current_keys.size() != _lod_zone_keys.size():
		_lod_zone_keys = current_keys
		_lod_update_index = 0
	
	if _lod_zone_keys.is_empty():
		return
	
	# Process up to _MAX_LOD_UPDATES_PER_FRAME zones per frame, cycling through all
	var processed := 0
	while processed < _MAX_LOD_UPDATES_PER_FRAME and processed < _lod_zone_keys.size():
		if _lod_update_index >= _lod_zone_keys.size():
			_lod_update_index = 0
		
		var coord: Vector2i = _lod_zone_keys[_lod_update_index]
		_lod_update_index += 1
		processed += 1
		
		# Skip if zone was unloaded
		if coord not in _loaded_zones:
			continue
		
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
	# LOD 0: full detail (≤4.5 zones — all trees/grass/flowers visible)
	# LOD 1: medium — canopy visible but trunk/leaf shadows off
	# LOD 2: far — non-terrain hidden entirely
	var new_lod: int = 0 if zone_dist <= 4.5 else (1 if zone_dist <= 9.0 else 2)
	var old_lod: int = zone_node.get_meta(zone_meta_key, -1)
	if new_lod == old_lod:
		return
	zone_node.set_meta(zone_meta_key, new_lod)
	for child in zone_node.get_children():
		if not is_instance_valid(child):
			continue
		var cname: String = child.name
		if cname == "TerrainCol":
			var col := child as CollisionShape3D
			var should_disable := zone_dist > 2.0
			if should_disable and not col.disabled:
				_deferred_disable_collisions.append(col)
			elif not should_disable and col.disabled:
				_deferred_collisions.append(col)
			continue
		if cname == "TerrainMesh":
			continue
		var is_flower := cname.begins_with("Flower_")
		var is_grass := cname == "GrassClump"
		var is_vegetation := is_flower or is_grass or cname == "Reeds" or cname.begins_with("BlueberryBush")
		var is_tree := child is StaticBody3D and (child as StaticBody3D).has_meta("tree_name")
		if is_flower or is_grass:
			# visibility_range_end on the MMI handles distance culling per-instance;
			# hard LOD toggle removed to avoid rectangular zone-block pop-in
			pass
		elif is_tree:
			# Trees stay visible at LOD 1 so canopy children can render;
			# trunk detail is hidden per-child below.  Only fully hidden at LOD 2.
			child.visible = new_lod <= 1
		elif is_vegetation:
			child.visible = new_lod <= 1
		else:
			child.visible = new_lod <= 1
		if child is StaticBody3D:
			var skip_col_lod: bool = child.get_meta("skip_collision_lod", false)
			for sub in child.get_children():
				if sub is CollisionShape3D:
					if skip_col_lod:
						continue
					if new_lod >= 1:
						if not sub.disabled:
							_deferred_disable_collisions.append(sub)
					elif sub.disabled:
						_deferred_collisions.append(sub)
				elif sub is Node3D and sub.name == "Canopy":
					sub.visible = new_lod <= 1
					if sub.visible:
						for leaf in sub.get_children():
							if leaf is GeometryInstance3D:
								leaf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if new_lod == 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				elif is_tree and sub is Node3D:
					# Hide trunk/detail meshes at LOD 1, only canopy shows
					sub.visible = new_lod == 0


## Build a half-resolution HeightMapShape3D for terrain collision.
## Uses MESH_RESOLUTION/2 grid (25x25 samples) — much cheaper than ConcavePolygonShape3D
## because the physics server uses direct grid lookup instead of BVH cooking.
func _build_collision_shape(coord: Vector2i) -> HeightMapShape3D:
	const COL_RES := MESH_RESOLUTION / 2
	var w := COL_RES + 1
	var step: float = ZONE_SIZE / COL_RES
	var map_data := PackedFloat32Array()
	map_data.resize(w * w)
	for cz in range(w):
		for cx in range(w):
			var wx := float(coord.x * COL_RES + cx) * step
			var wz := float(coord.y * COL_RES + cz) * step
			map_data[cz * w + cx] = get_height_at(wx, wz)
	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = w
	shape.map_data = map_data
	return shape


## Runs on a WorkerThreadPool thread — pure computation, no scene access.
func _bg_build_zone(coord: Vector2i) -> void:
	var arrays := _build_zone_mesh(coord)
	var shape := _build_collision_shape(coord)

	_gen_mutex.lock()
	_gen_ready_queue.append({"coord": coord, "arrays": arrays, "shape": shape})
	_gen_mutex.unlock()


## Main-thread only: creates scene nodes from pre-computed mesh data + shape.
func _finalize_zone(coord: Vector2i, arrays: Array, shape: HeightMapShape3D) -> void:
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

		var near_player := _is_zone_near_player(coord)
		var hm_step := ZONE_SIZE / float(MESH_RESOLUTION / 2)
		if shape:
			if col:
				col.shape = shape
				col.position = Vector3(ZONE_SIZE / 2.0, 0.0, ZONE_SIZE / 2.0)
				col.scale = Vector3(hm_step, 1.0, hm_step)
				if near_player:
					col.disabled = false
				else:
					col.disabled = true
					_deferred_collisions.append(col)
			else:
				col = CollisionShape3D.new()
				col.name = "TerrainCol"
				col.shape = shape
				col.position = Vector3(ZONE_SIZE / 2.0, 0.0, ZONE_SIZE / 2.0)
				col.scale = Vector3(hm_step, 1.0, hm_step)
				if near_player:
					col.disabled = false
				else:
					col.disabled = true
					_deferred_collisions.append(col)
				zone_root.add_child(col)
		if not zone_root.get_parent():
			if near_player:
				add_child(zone_root)
			else:
				call_deferred(&"add_child", zone_root)
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
		var near_player := _is_zone_near_player(coord)
		if shape:
			collision.shape = shape
			collision.position = Vector3(ZONE_SIZE / 2.0, 0.0, ZONE_SIZE / 2.0)
			collision.scale = Vector3(ZONE_SIZE / float(MESH_RESOLUTION / 2), 1.0, ZONE_SIZE / float(MESH_RESOLUTION / 2))
			if near_player:
				collision.disabled = false
			else:
				collision.disabled = true
				_deferred_collisions.append(collision)
		zone_root.add_child(mesh_instance)
		zone_root.add_child(collision)
		if not zone_root.get_parent():
			if near_player:
				add_child(zone_root)
			else:
				call_deferred(&"add_child", zone_root)

	# Local position = world coords; parent (WorldGenerator) global_position handles origin shift
	zone_root.position = Vector3(coord.x * ZONE_SIZE, 0.0, coord.y * ZONE_SIZE)
	zone_root.set_meta(&"zone_coord", coord)
	_loaded_zones[coord] = zone_root
	var _was_explored := _explored_zones.has(coord)
	_explored_zones[coord] = true
	if not _was_explored:
		zone_explored.emit(coord)

	# Build creek/river strip meshes for this zone
	_build_creek_meshes_for_zone(zone_root, coord)

	# Build mountain-top lake water surfaces
	_build_mountain_pool_for_zone(zone_root, coord)

	# Water physics mesh — disabled until propagation is properly tuned
	#_build_water_mesh_for_zone(zone_root, coord)

	# Queue object spawning for the NEXT frame to keep this frame light
	var micro := _determine_microbiome(coord)
	# Clear any stale backlog entries for this coord before adding new one
	for i in range(_populate_backlog.size() - 1, -1, -1):
		if _populate_backlog[i]["coord"] == coord:
			_populate_backlog.remove_at(i)
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


func _load_shader(path: String) -> Shader:
	if ResourceLoader.exists(path):
		return load(path) as Shader
	return null


func _create_global_water() -> void:
	_global_water_plane = MeshInstance3D.new()
	_global_water_plane.name = "GlobalWater"
	var plane := PlaneMesh.new()
	plane.size = _water_plane_size()
	plane.subdivide_width = 48
	plane.subdivide_depth = 48
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


func _init_creek_material() -> void:
	var shader := _load_shader("res://shaders/creek.gdshader")
	if not shader:
		return
	_creek_shader_mat = ShaderMaterial.new()
	_creek_shader_mat.shader = shader
	_creek_shader_mat.set_shader_parameter("water_level", WATER_LEVEL)


func _build_creek_meshes_for_zone(zone_root: Node3D, coord: Vector2i) -> void:
	if not _creek_segments.has(coord):
		return
	var segments: Array = _creek_segments[coord]
	if segments.is_empty():
		return

	var zone_origin := Vector3(coord.x * ZONE_SIZE, 0.0, coord.y * ZONE_SIZE)

	for seg in segments:
		var points: PackedVector3Array = seg["points"]
		var half_widths: PackedFloat32Array = seg["widths"]
		var flow_uvs: PackedFloat32Array = seg["uvs"]

		if points.size() < 2:
			continue

		var tavern_cut := _tavern_world_pos.y > 0.0
		var tavern_r2 := _TAVERN_FLAT_RADIUS * _TAVERN_FLAT_RADIUS
		var pt_in_tavern := PackedByteArray()
		for i in points.size():
			var p := points[i]
			if tavern_cut:
				var tdx := p.x - _tavern_world_pos.x
				var tdz := p.z - _tavern_world_pos.z
				pt_in_tavern.append(1 if tdx * tdx + tdz * tdz < tavern_r2 else 0)
			else:
				pt_in_tavern.append(0)

		# Pre-compute per-point slope (dy/dx) for flow speed modulation
		var slopes := PackedFloat32Array()
		for i in points.size():
			var dy := 0.0
			var dx := 0.0
			if i < points.size() - 1:
				dy = points[i].y - points[i + 1].y
				dx = Vector2(points[i + 1].x - points[i].x, points[i + 1].z - points[i].z).length()
			elif i > 0:
				dy = points[i - 1].y - points[i].y
				dx = Vector2(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z).length()
			var slope_val := clampf(dy / maxf(dx, 0.01), 0.0, 2.0)
			slopes.append(slope_val)

		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var mesh_uvs := PackedVector2Array()
		var colors := PackedColorArray()
		var indices := PackedInt32Array()

		var uv_scale := 0.05

		# Pre-compute smoothed tangent directions to prevent corner kinking
		var tangents := PackedVector2Array()
		for i in points.size():
			var p := points[i]
			var dir_fwd := Vector2.ZERO
			var dir_back := Vector2.ZERO

			if i < points.size() - 1:
				var nxt := points[i + 1]
				dir_fwd = Vector2(nxt.x - p.x, nxt.z - p.z)
				if dir_fwd.length_squared() > 0.0001:
					dir_fwd = dir_fwd.normalized()
			if i > 0:
				var prv := points[i - 1]
				dir_back = Vector2(p.x - prv.x, p.z - prv.z)
				if dir_back.length_squared() > 0.0001:
					dir_back = dir_back.normalized()

			var flow_dir: Vector2
			if dir_fwd.length_squared() > 0.0001 and dir_back.length_squared() > 0.0001:
				flow_dir = (dir_fwd + dir_back).normalized()
			elif dir_fwd.length_squared() > 0.0001:
				flow_dir = dir_fwd
			elif dir_back.length_squared() > 0.0001:
				flow_dir = dir_back
			else:
				flow_dir = Vector2(0, 1)
			tangents.append(flow_dir)

		for i in points.size():
			var p := points[i]

			var raw_h := _get_raw_height_no_paths(p.x, p.z)
			var t_excess := maxf(raw_h - p.y, 0.0)
			var steep_suppress := 1.0 - clampf(slopes[i] / 0.5, 0.0, 1.0)
			var ridge_mesh_bonus := clampf(t_excess / 8.0, 0.0, 1.5) * 8.0 * steep_suppress
			var slope_narrow := 1.0 - clampf(slopes[i] / 0.7, 0.0, 0.7)
			var w := maxf((half_widths[i] + 3.0 + ridge_mesh_bonus) * slope_narrow, 1.5)

			var uv_y := flow_uvs[i] * uv_scale

			var flow_dir := tangents[i]
			var perp := Vector2(-flow_dir.y, flow_dir.x)

			var local_p := p - zone_origin
			local_p.y -= lerpf(1.5, 0.3, clampf(slopes[i] / 0.6, 0.0, 1.0))

			var left_top := Vector3(local_p.x - perp.x * w, local_p.y, local_p.z - perp.y * w)
			var right_top := Vector3(local_p.x + perp.x * w, local_p.y, local_p.z + perp.y * w)

			var left_wx := p.x - perp.x * w
			var left_wz := p.z - perp.y * w
			var right_wx := p.x + perp.x * w
			var right_wz := p.z + perp.y * w
			var left_terrain_y := get_height_at(left_wx, left_wz) - zone_origin.y - 0.3
			var right_terrain_y := get_height_at(right_wx, right_wz) - zone_origin.y - 0.3
			var skirt_depth := _CREEK_DEPTH * (1.0 - clampf(slopes[i] / 0.6, 0.0, 0.8))
			var fixed_bottom := local_p.y - skirt_depth
			# Ensure skirt extends below the global water plane to occlude it
			var global_water_y := WATER_LEVEL - 0.15 - zone_origin.y - 0.5
			var left_bottom_y := minf(minf(fixed_bottom, left_terrain_y), global_water_y)
			var right_bottom_y := minf(minf(fixed_bottom, right_terrain_y), global_water_y)

			var left_bottom := Vector3(left_top.x, left_bottom_y, left_top.z)
			var right_bottom := Vector3(right_top.x, right_bottom_y, right_top.z)

			# Compute proper surface normal from tangent and width direction
			var tangent_3d := Vector3(flow_dir.x, 0.0, flow_dir.y)
			var width_dir := Vector3(perp.x, 0.0, perp.y)
			if i < points.size() - 1:
				tangent_3d.y = (points[i + 1].y - p.y) / maxf(Vector2(points[i + 1].x - p.x, points[i + 1].z - p.z).length(), 0.01)
			elif i > 0:
				tangent_3d.y = (p.y - points[i - 1].y) / maxf(Vector2(p.x - points[i - 1].x, p.z - points[i - 1].z).length(), 0.01)
			tangent_3d = tangent_3d.normalized()
			var surface_normal := width_dir.cross(tangent_3d).normalized()
			if surface_normal.y < 0:
				surface_normal = -surface_normal

			var slope_factor := clampf(slopes[i] / 1.0, 0.0, 1.0)
			var fd := flow_dir.normalized()
			var fd_b := fd.x * 0.5 + 0.5
			var fd_a := fd.y * 0.5 + 0.5
			var col_surface := Color(slope_factor, 1.0, fd_b, fd_a)
			var col_skirt := Color(slope_factor, 0.0, fd_b, fd_a)

			# 4 verts per cross-section: left_bottom, left_top, right_top, right_bottom
			verts.append(left_bottom)
			verts.append(left_top)
			verts.append(right_top)
			verts.append(right_bottom)
			norms.append(surface_normal)
			norms.append(surface_normal)
			norms.append(surface_normal)
			norms.append(surface_normal)
			mesh_uvs.append(Vector2(0.02, uv_y))
			mesh_uvs.append(Vector2(0.10, uv_y))
			mesh_uvs.append(Vector2(0.90, uv_y))
			mesh_uvs.append(Vector2(0.98, uv_y))
			colors.append(col_skirt)
			colors.append(col_surface)
			colors.append(col_surface)
			colors.append(col_skirt)

			if i > 0 and pt_in_tavern[i] == 0 and pt_in_tavern[i - 1] == 0:
				var prev := (i - 1) * 4
				var curr := i * 4
				# Left skirt wall
				indices.append(prev + 0)
				indices.append(prev + 1)
				indices.append(curr + 0)
				indices.append(prev + 1)
				indices.append(curr + 1)
				indices.append(curr + 0)
				# Surface
				indices.append(prev + 1)
				indices.append(prev + 2)
				indices.append(curr + 1)
				indices.append(prev + 2)
				indices.append(curr + 2)
				indices.append(curr + 1)
				# Right skirt wall
				indices.append(prev + 2)
				indices.append(prev + 3)
				indices.append(curr + 2)
				indices.append(prev + 3)
				indices.append(curr + 3)
				indices.append(curr + 2)
				# Bottom floor — seals the creek mesh to occlude the global water plane
				indices.append(prev + 0)
				indices.append(curr + 0)
				indices.append(curr + 3)
				indices.append(prev + 0)
				indices.append(curr + 3)
				indices.append(prev + 3)

		if verts.size() < 8:
			continue

		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV] = mesh_uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices

		var arr_mesh := ArrayMesh.new()
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if _creek_shader_mat:
			arr_mesh.surface_set_material(0, _creek_shader_mat)
		else:
			var fallback := StandardMaterial3D.new()
			fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fallback.albedo_color = Color(0.1, 0.2, 0.15, 0.5)
			fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
			arr_mesh.surface_set_material(0, fallback)

		var mi := MeshInstance3D.new()
		mi.name = "Creek"
		mi.mesh = arr_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		zone_root.add_child(mi)

		_spawn_waterfall_particles(zone_root, points, half_widths, zone_origin)


func _build_mountain_pool_for_zone(zone_root: Node3D, coord: Vector2i) -> void:
	var zone_wx := coord.x * ZONE_SIZE
	var zone_wz := coord.y * ZONE_SIZE
	var zone_origin := Vector3(zone_wx, 0.0, zone_wz)
	var step := 4.0

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var vert_idx := 0

	var gx_min := int(floor(zone_wx / step))
	var gx_max := int(ceil((zone_wx + ZONE_SIZE) / step))
	var gz_min := int(floor(zone_wz / step))
	var gz_max := int(ceil((zone_wz + ZONE_SIZE) / step))

	for gz in range(gz_min, gz_max):
		for gx in range(gx_min, gx_max):
			var wx := float(gx) * step
			var wz := float(gz) * step
			var pool_level := _mountain_pool_surface(wx + step * 0.5, wz + step * 0.5)
			if pool_level < -900.0:
				continue

			# Skip if any part of this quad is near creek bed cells (wider margin)
			if not _creek_bed.is_empty():
				var cb_margin := 3
				var cb_x0 := int(floor(wx / _CREEK_BED_CELL)) - cb_margin
				var cb_x1 := int(ceil((wx + step) / _CREEK_BED_CELL)) + cb_margin
				var cb_z0 := int(floor(wz / _CREEK_BED_CELL)) - cb_margin
				var cb_z1 := int(ceil((wz + step) / _CREEK_BED_CELL)) + cb_margin
				var near_creek := false
				for cbx in range(cb_x0, cb_x1 + 1):
					for cbz in range(cb_z0, cb_z1 + 1):
						if _creek_bed.has(Vector2i(cbx, cbz)):
							near_creek = true
							break
					if near_creek:
						break
				if near_creek:
					continue

			# All 4 corners must be below pool level
			var corners_ok := true
			for ci in 4:
				var cx := wx + (step if ci == 1 or ci == 2 else 0.0)
				var cz := wz + (step if ci == 2 or ci == 3 else 0.0)
				if get_height_at(cx, cz) >= pool_level - 0.3:
					corners_ok = false
					break
			if not corners_ok:
				continue

			var lx := wx - zone_origin.x
			var lz := wz - zone_origin.z
			var ly := pool_level - zone_origin.y

			var s := step
			verts.append(Vector3(lx, ly, lz))
			verts.append(Vector3(lx + s, ly, lz))
			verts.append(Vector3(lx + s, ly, lz + s))
			verts.append(Vector3(lx, ly, lz + s))
			for _n in 4:
				norms.append(Vector3.UP)
			uvs.append(Vector2(wx * 0.1, wz * 0.1))
			uvs.append(Vector2((wx + s) * 0.1, wz * 0.1))
			uvs.append(Vector2((wx + s) * 0.1, (wz + s) * 0.1))
			uvs.append(Vector2(wx * 0.1, (wz + s) * 0.1))
			indices.append(vert_idx)
			indices.append(vert_idx + 1)
			indices.append(vert_idx + 2)
			indices.append(vert_idx)
			indices.append(vert_idx + 2)
			indices.append(vert_idx + 3)
			vert_idx += 4

	if verts.is_empty():
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _water_shader_mat:
		arr_mesh.surface_set_material(0, _water_shader_mat)

	var mi := MeshInstance3D.new()
	mi.name = "MountainPool"
	mi.mesh = arr_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone_root.add_child(mi)


func _build_water_mesh_for_zone(zone_root: Node3D, coord: Vector2i) -> void:
	var zone_wx := coord.x * ZONE_SIZE
	var zone_wz := coord.y * ZONE_SIZE
	var zone_origin := Vector3(zone_wx, 0.0, zone_wz)
	var step := TERRAIN_MOD_STEP
	var gx_min := roundi(zone_wx / step)
	var gx_max := roundi((zone_wx + ZONE_SIZE) / step)
	var gz_min := roundi(zone_wz / step)
	var gz_max := roundi((zone_wz + ZONE_SIZE) / step)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var vert_idx := 0
	var flat_color := Color(0.0, 1.0, 1.0, 1.0)

	for gz in range(gz_min, gz_max):
		for gx in range(gx_min, gx_max):
			var key := Vector2i(gx, gz)
			if not _water_grid.has(key):
				continue
			var water_h: float = _water_grid[key]
			var wx := float(gx) * step
			var wz := float(gz) * step
			var terrain_h := get_height_at(wx, wz)
			if water_h <= terrain_h + 0.1:
				continue
			var lx := wx - zone_origin.x
			var lz := wz - zone_origin.z
			var ly := water_h - zone_origin.y

			var s := step
			verts.append(Vector3(lx, ly, lz))
			verts.append(Vector3(lx + s, ly, lz))
			verts.append(Vector3(lx + s, ly, lz + s))
			verts.append(Vector3(lx, ly, lz + s))
			for _n in 4:
				norms.append(Vector3.UP)
				colors.append(flat_color)
			uvs.append(Vector2(0, 0))
			uvs.append(Vector2(1, 0))
			uvs.append(Vector2(1, 1))
			uvs.append(Vector2(0, 1))
			indices.append(vert_idx)
			indices.append(vert_idx + 1)
			indices.append(vert_idx + 2)
			indices.append(vert_idx)
			indices.append(vert_idx + 2)
			indices.append(vert_idx + 3)
			vert_idx += 4

	if verts.is_empty():
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _creek_shader_mat:
		arr_mesh.surface_set_material(0, _creek_shader_mat)

	var mi := MeshInstance3D.new()
	mi.name = "WaterPhysics"
	mi.mesh = arr_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	zone_root.add_child(mi)


func _rebuild_dirty_water_meshes() -> void:
	if _water_dirty_zones.is_empty():
		return
	var rebuilt := 0
	for zone_coord: Vector2i in _water_dirty_zones:
		if rebuilt >= 2:
			break
		if not _loaded_zones.has(zone_coord):
			continue
		var zone_root: Node3D = _loaded_zones[zone_coord]
		for child in zone_root.get_children():
			if child.name == "WaterPhysics":
				child.queue_free()
				break
		_build_water_mesh_for_zone(zone_root, zone_coord)
		rebuilt += 1
	if rebuilt > 0:
		var done_zones: Array[Vector2i] = []
		var count := 0
		for z: Vector2i in _water_dirty_zones:
			if count >= rebuilt:
				break
			if _loaded_zones.has(z):
				done_zones.append(z)
				count += 1
		for z in done_zones:
			_water_dirty_zones.erase(z)


func _spawn_waterfall_particles(zone_root: Node3D, points: PackedVector3Array, widths: PackedFloat32Array, zone_origin: Vector3) -> void:
	for i in range(1, points.size()):
		var prev := points[i - 1]
		var curr := points[i]
		var dy := prev.y - curr.y
		var dx := Vector2(curr.x - prev.x, curr.z - prev.z).length()
		if dx < 0.01:
			continue
		var slope_val := dy / dx
		if slope_val < 0.10 or dy < 0.5:
			continue

		var seg_w := 1.0
		if widths.size() > 0:
			var w0: float = widths[mini(i - 1, widths.size() - 1)]
			var w1: float = widths[mini(i, widths.size() - 1)]
			seg_w = (w0 + w1) * 0.5

		var mid := (prev + curr) * 0.5
		var local := mid - zone_origin

		var amount := clampi(int((16 + dy * 8) * 2.5), 40, 200)
		var lifetime := clampf(0.7 + dy * 0.15, 0.7, 2.5)
		var vel_max := clampf(3.0 + slope_val * 6.0, 3.0, 12.0)
		var vel_min := vel_max * 0.4
		var emit_x := clampf(seg_w * 0.4, 0.5, 4.0)
		var quad_sz := clampf(0.12 + dy * 0.04, 0.12, 0.5)
		var grav_y := lerpf(-5.0, -12.0, clampf(slope_val, 0.0, 1.0))
		var aabb_h := maxf(6.0, dy * 2.0 + 4.0)

		var particles := GPUParticles3D.new()
		particles.name = "Waterfall"
		particles.amount = amount
		particles.lifetime = lifetime
		particles.explosiveness = 0.1
		particles.randomness = 0.4
		particles.visibility_aabb = AABB(
			Vector3(-emit_x - 2.0, -aabb_h * 0.5, -emit_x - 2.0),
			Vector3((emit_x + 2.0) * 2.0, aabb_h, (emit_x + 2.0) * 2.0))

		var mat := ParticleProcessMaterial.new()
		mat.direction = Vector3(0, -1, 0)
		mat.spread = lerpf(25.0, 15.0, clampf(slope_val, 0.0, 1.0))
		mat.initial_velocity_min = vel_min
		mat.initial_velocity_max = vel_max
		mat.gravity = Vector3(0, grav_y, 0)
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		mat.emission_box_extents = Vector3(emit_x, 0.2, emit_x * 0.3)
		mat.scale_min = quad_sz * 0.5
		mat.scale_max = quad_sz * 1.2
		mat.damping_min = 1.0
		mat.damping_max = 3.0
		mat.color = Color(0.85, 0.92, 0.90, 0.75)
		var alpha_curve := CurveTexture.new()
		var curve := Curve.new()
		curve.add_point(Vector2(0.0, 0.9))
		curve.add_point(Vector2(0.4, 0.7))
		curve.add_point(Vector2(1.0, 0.0))
		alpha_curve.curve = curve
		mat.alpha_curve = alpha_curve
		particles.process_material = mat

		var quad := QuadMesh.new()
		quad.size = Vector2(quad_sz, quad_sz)
		var draw_mat := StandardMaterial3D.new()
		draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		draw_mat.albedo_color = Color(0.92, 0.96, 0.94, 0.8)
		draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		draw_mat.vertex_color_use_as_albedo = true
		quad.material = draw_mat
		particles.draw_pass_1 = quad

		particles.position = local
		zone_root.add_child(particles)

		# Mist / spray cloud at the base of significant drops
		if dy > 3.0:
			var base_local := curr - zone_origin
			var mist_w := clampf(seg_w * 0.6, 1.0, 6.0)
			var mist_amount := clampi(int((12 + dy * 4) * 2.5), 30, 125)
			var mist_sz := clampf(0.3 + dy * 0.05, 0.3, 0.8)

			var mist := GPUParticles3D.new()
			mist.name = "WaterfallMist"
			mist.amount = mist_amount
			mist.lifetime = clampf(1.0 + dy * 0.1, 1.0, 2.0)
			mist.explosiveness = 0.0
			mist.randomness = 0.6
			mist.visibility_aabb = AABB(
				Vector3(-mist_w - 2.0, -1.0, -mist_w - 2.0),
				Vector3((mist_w + 2.0) * 2.0, 6.0, (mist_w + 2.0) * 2.0))

			var mist_mat := ParticleProcessMaterial.new()
			mist_mat.direction = Vector3(0, 1, 0)
			mist_mat.spread = 70.0
			mist_mat.initial_velocity_min = 0.5
			mist_mat.initial_velocity_max = 2.0
			mist_mat.gravity = Vector3(0, -1.5, 0)
			mist_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			mist_mat.emission_box_extents = Vector3(mist_w, 0.3, mist_w * 0.4)
			mist_mat.scale_min = mist_sz * 0.7
			mist_mat.scale_max = mist_sz * 1.5
			mist_mat.damping_min = 2.0
			mist_mat.damping_max = 4.0
			mist_mat.color = Color(0.85, 0.90, 0.88, 0.45)
			var mist_alpha_curve := CurveTexture.new()
			var mist_curve := Curve.new()
			mist_curve.add_point(Vector2(0.0, 0.0))
			mist_curve.add_point(Vector2(0.15, 0.6))
			mist_curve.add_point(Vector2(0.5, 0.4))
			mist_curve.add_point(Vector2(1.0, 0.0))
			mist_alpha_curve.curve = mist_curve
			mist_mat.alpha_curve = mist_alpha_curve
			mist.process_material = mist_mat

			var mist_quad := QuadMesh.new()
			mist_quad.size = Vector2(mist_sz, mist_sz)
			var mist_draw := StandardMaterial3D.new()
			mist_draw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mist_draw.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mist_draw.albedo_color = Color(0.88, 0.93, 0.90, 0.5)
			mist_draw.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mist_draw.vertex_color_use_as_albedo = true
			mist_quad.material = mist_draw
			mist.draw_pass_1 = mist_quad

			mist.position = base_local
			zone_root.add_child(mist)


func _water_plane_size() -> Vector2:
	var extent := ZONE_SIZE * float(load_radius_zones + 1) * 2.0
	return Vector2(extent, extent)


func _resize_water_plane() -> void:
	if _global_water_plane and _global_water_plane.mesh is PlaneMesh:
		(_global_water_plane.mesh as PlaneMesh).size = _water_plane_size()


func set_render_distance(radius: int) -> void:
	load_radius_zones = clampi(radius, 1, 5)
	unload_radius_zones = load_radius_zones + 2
	_max_loaded_zones = (2 * unload_radius_zones + 1) ** 2 + 10
	_resize_water_plane()


# ═══════════════════════════════════════════════════════════════════════════════
#  MESH BUILDING
# ═══════════════════════════════════════════════════════════════════════════════

## Canonical world coordinate — always produces the same float for the same
## logical grid point regardless of which zone computes it.
static func _canonical_wx(zone_x: int, grid_x: int) -> float:
	return float(zone_x * MESH_RESOLUTION + grid_x) * (ZONE_SIZE / float(MESH_RESOLUTION))

static func _canonical_wz(zone_y: int, grid_z: int) -> float:
	return float(zone_y * MESH_RESOLUTION + grid_z) * (ZONE_SIZE / float(MESH_RESOLUTION))

func _build_zone_mesh(coord: Vector2i) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var macro_grads := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var res := MESH_RESOLUTION
	var origin_x: float = coord.x * ZONE_SIZE
	var origin_z: float = coord.y * ZONE_SIZE
	var step: float = ZONE_SIZE / res
	var w := res + 1

	# First pass: sample heights using canonical world coords for cross-zone consistency
	var heights := PackedFloat32Array()
	heights.resize(w * w)
	for z in range(w):
		for x in range(w):
			var wx := _canonical_wx(coord.x, x)
			var wz := _canonical_wz(coord.y, z)
			heights[z * w + x] = get_height_at(wx, wz)

	# Second pass: build vertices, UVs, colors using cached heights
	for z in range(w):
		for x in range(w):
			var wx := _canonical_wx(coord.x, x)
			var wz := _canonical_wz(coord.y, z)
			var h := heights[z * w + x]
			verts.append(Vector3(x * step, h, z * step))
			uvs.append(Vector2(x as float / res, z as float / res))

			var path_f := _ZonePopulator.get_path_factor(wx, wz)

			var bw1 := _detail_noise.get_noise_2d(wx * 0.06 + 4000.0, wz * 0.06 + 4000.0) * 18.0 if _detail_noise else 0.0
			var bw2 := _detail_noise.get_noise_2d(wx * 0.15 + 6000.0, wz * 0.15 + 6000.0) * 8.0 if _detail_noise else 0.0
			var accum_here := _ws_sample_accum(wx + bw1 + bw2, wz + bw1 - bw2)
			var river_bank := smoothstep(_WS_RIVER_THRESH * 0.7, _WS_RIVER_THRESH * 1.3, accum_here)

			# Ocean coast vs inland lake: sample the island mask. Deep water
			# is ~0 and solid inland is ~1, so values in the 0.2–0.85 band are
			# the ocean transition zone. Inland-lake shores are detected via
			# the high-frequency lake_n noise we were already using, but we
			# now gate it by island mask so ocean edges DON'T get the dark
			# muddy bank tint.
			var island_here := _sample_island_mask(wx, wz) if _island_noise else 1.0
			if _detail_noise and island_here > 0.85:
				var lake_n := _continent_noise.get_noise_2d(wx * 0.7 + 5000.0, wz * 0.7 + 5000.0)
				var lake_shore := smoothstep(-0.25, -0.45, lake_n)
				river_bank = maxf(river_bank, lake_shore)

			river_bank = clampf(river_bank, 0.0, 1.0)

			# Beach mask (colors.a): same coast band used by get_height_at so the
			# sand color paints exactly the flattened beach geometry. Gated by
			# altitude so we don't stain the seabed or the inland hills if the
			# mask bleeds a little out of the flat band. Band matches the wider
			# beach_zone in get_height_at, and the altitude limit goes up to
			# WATER_LEVEL+5 so any coastal ramp shorter than a small cliff
			# still reads as sand.
			var beach_coast := smoothstep(0.10, 0.35, island_here) * (1.0 - smoothstep(0.60, 0.95, island_here))
			var beach_alt := clampf(1.0 - smoothstep(WATER_LEVEL - 0.5, WATER_LEVEL + 5.0, h), 0.0, 1.0)
			var beach_mask := clampf(beach_coast * beach_alt, 0.0, 1.0)
			colors.append(Color(path_f, 1.0, river_bank, beach_mask))

	# Third pass: compute normals.
	# Boundary vertices (on any zone edge) use get_height_at for ALL four
	# neighbors so that adjacent zones produce bit-identical normals at shared
	# vertices — avoids float32-cache vs float64-fresh precision mismatches.
	for z in range(w):
		for x in range(w):
			var on_edge := (x == 0 or x == res or z == 0 or z == res)
			var h_left: float
			var h_right: float
			var h_up: float
			var h_down: float
			if x > 0 and not on_edge:
				h_left = heights[z * w + (x - 1)]
			else:
				h_left = get_height_at(_canonical_wx(coord.x, x - 1), _canonical_wz(coord.y, z))
			if x < res and not on_edge:
				h_right = heights[z * w + (x + 1)]
			else:
				h_right = get_height_at(_canonical_wx(coord.x, x + 1), _canonical_wz(coord.y, z))
			if z > 0 and not on_edge:
				h_up = heights[(z - 1) * w + x]
			else:
				h_up = get_height_at(_canonical_wx(coord.x, x), _canonical_wz(coord.y, z - 1))
			if z < res and not on_edge:
				h_down = heights[(z + 1) * w + x]
			else:
				h_down = get_height_at(_canonical_wx(coord.x, x), _canonical_wz(coord.y, z + 1))
			var tangent_x := Vector3(2.0 * step, h_right - h_left, 0.0)
			var tangent_z := Vector3(0.0, h_down - h_up, 2.0 * step)
			normals.append(tangent_z.cross(tangent_x).normalized())

	# Fourth pass: macro gradient from wide-stencil height sampling.
	# Stored in UV2 so the shader can reconstruct a zone-boundary-continuous
	# normal for triplanar blending. The 16m stencil smooths over boundaries.
	macro_grads.resize(w * w)
	const MACRO_R := 8.0
	for z in range(w):
		for x in range(w):
			var wx := _canonical_wx(coord.x, x)
			var wz := _canonical_wz(coord.y, z)
			var hl := get_height_at(wx - MACRO_R, wz)
			var hr := get_height_at(wx + MACRO_R, wz)
			var hu := get_height_at(wx, wz - MACRO_R)
			var hd := get_height_at(wx, wz + MACRO_R)
			var gx := (hr - hl) / (2.0 * MACRO_R)
			var gz := (hd - hu) / (2.0 * MACRO_R)
			macro_grads[z * w + x] = Vector2(gx, gz)
			colors[z * w + x].g = clampf(sqrt(gx * gx + gz * gz), 0.0, 1.0)

	# Surface triangles
	for z in range(res):
		for x in range(res):
			var i := z * (res + 1) + x
			indices.append(i)
			indices.append(i + 1)
			indices.append(i + res + 1)
			indices.append(i + 1)
			indices.append(i + res + 2)
			indices.append(i + res + 1)

	# Skirt geometry — thin vertical strips at zone edges prevent sub-pixel gaps
	# between draw calls. Skirt verts duplicate the edge position but drop Y.
	var skirt_drop := 8.0
	var surface_count := verts.size()
	# Add skirt vertices for all 4 edges
	for z in range(w):
		# Left edge (x=0)
		var vi := z * w
		verts.append(Vector3(verts[vi].x, verts[vi].y - skirt_drop, verts[vi].z))
		normals.append(normals[vi])
		uvs.append(Vector2(0.0, z as float / res))
		macro_grads.append(macro_grads[vi])
		colors.append(colors[vi])
	for z in range(w):
		# Right edge (x=res)
		var vi := z * w + res
		verts.append(Vector3(verts[vi].x, verts[vi].y - skirt_drop, verts[vi].z))
		normals.append(normals[vi])
		uvs.append(Vector2(1.0, z as float / res))
		macro_grads.append(macro_grads[vi])
		colors.append(colors[vi])
	for x in range(w):
		# Top edge (z=0)
		var vi := x
		verts.append(Vector3(verts[vi].x, verts[vi].y - skirt_drop, verts[vi].z))
		normals.append(normals[vi])
		uvs.append(Vector2(x as float / res, 0.0))
		macro_grads.append(macro_grads[vi])
		colors.append(colors[vi])
	for x in range(w):
		# Bottom edge (z=res)
		var vi := res * w + x
		verts.append(Vector3(verts[vi].x, verts[vi].y - skirt_drop, verts[vi].z))
		normals.append(normals[vi])
		uvs.append(Vector2(x as float / res, 1.0))
		macro_grads.append(macro_grads[vi])
		colors.append(colors[vi])

	# Skirt triangle indices — connect edge verts to their dropped duplicates
	var left_base := surface_count
	var right_base := left_base + w
	var top_base := right_base + w
	var bottom_base := top_base + w
	for z in range(res):
		# Left skirt
		var e0 := z * w
		var e1 := (z + 1) * w
		var s0 := left_base + z
		var s1 := left_base + z + 1
		indices.append(e0); indices.append(s0); indices.append(e1)
		indices.append(s0); indices.append(s1); indices.append(e1)
		# Right skirt
		e0 = z * w + res
		e1 = (z + 1) * w + res
		s0 = right_base + z
		s1 = right_base + z + 1
		indices.append(e0); indices.append(e1); indices.append(s0)
		indices.append(s0); indices.append(e1); indices.append(s1)
	for x in range(res):
		# Top skirt
		var e0 := x
		var e1 := x + 1
		var s0 := top_base + x
		var s1 := top_base + x + 1
		indices.append(e0); indices.append(e1); indices.append(s0)
		indices.append(s0); indices.append(e1); indices.append(s1)
		# Bottom skirt
		e0 = res * w + x
		e1 = res * w + x + 1
		s0 = bottom_base + x
		s1 = bottom_base + x + 1
		indices.append(e0); indices.append(s0); indices.append(e1)
		indices.append(s0); indices.append(s1); indices.append(e1)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = macro_grads
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

	var dirt_tex := _load_tex("res://textures/terrain/dirt.png")
	if not dirt_tex:
		dirt_tex = _load_tex("res://textures/materials/bark.png")

	var beach_tex := _load_tex("res://textures/terrain/sand.png")

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
			if beach_tex:
				mat.set_shader_parameter("tex_beach", beach_tex)
			mat.set_shader_parameter("tint_color", Vector3(tint.r, tint.g, tint.b))
			mat.set_shader_parameter("texture_scale", tex_scale)
			mat.set_shader_parameter("origin_shift", origin_shift)
			mat.set_shader_parameter("path_color", Vector3(0.12, 0.07, 0.03))
			mat.set_shader_parameter("bank_color", Vector3(0.12, 0.09, 0.05))
			mat.set_shader_parameter("beach_color", Vector3(0.86, 0.78, 0.58))
			_biome_materials[biome_id] = mat
		else:
			# Fallback if shader fails to load
			var mat := StandardMaterial3D.new()
			mat.albedo_color = _get_biome_terrain_color(biome_id)
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
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
