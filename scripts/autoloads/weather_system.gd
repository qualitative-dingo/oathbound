extends Node
## Global weather system. Cycles between sun/wind/rain/storm.
## Other systems read current_weather and wind_intensity.
## Pushes lighting multipliers to DayNightCycle when weather changes.

enum Weather { SUN, WIND, RAIN, STORM }

signal weather_changed(new_weather: Weather)

var current_weather: Weather = Weather.SUN
var wind_intensity: float = 0.45

var _timer: float = 0.0
var _next_change: float = 120.0
var _rng := RandomNumberGenerator.new()
var _target_intensity: float = 0.45

var _cloud_parent: Node3D
var _clouds: Array[MeshInstance3D] = []
var _cloud_target_color := Color(1.0, 1.0, 1.0, 0.55)
var _cloud_current_color := Color(1.0, 1.0, 1.0, 0.55)
const CLOUD_COUNT := 30
const CLOUD_Y := 80.0
const CLOUD_SPREAD := 200.0
var _cached_player: Node3D
var _cached_day_night: Node
var _cached_world_gen: Node

var _tumble_parent: Node3D
var _tumble_leaves: Array[MeshInstance3D] = []
const TUMBLE_COUNT := 12
const TUMBLE_SPREAD := 60.0

var _horizon_parent: Node3D
var _horizon_meshes: Array[MeshInstance3D] = []
const HORIZON_DIST := 280.0
const HORIZON_COUNT := 8

const WEATHER_DURATIONS := {
	Weather.SUN:   Vector2(90.0, 200.0),
	Weather.WIND:  Vector2(60.0, 150.0),
	Weather.RAIN:  Vector2(40.0, 120.0),
	Weather.STORM: Vector2(30.0, 80.0),
}

const WEATHER_WIND := {
	Weather.SUN:   0.45,
	Weather.WIND:  0.6,
	Weather.RAIN:  0.6,
	Weather.STORM: 1.0,
}

const WEATHER_CLOUD_COLOR := {
	Weather.SUN:   Color(1.0, 1.0, 1.0, 0.55),
	Weather.WIND:  Color(0.9, 0.9, 0.92, 0.65),
	Weather.RAIN:  Color(0.5, 0.52, 0.55, 0.8),
	Weather.STORM: Color(0.32, 0.33, 0.38, 0.9),
}

const WEATHER_SUN_MULT := {
	Weather.SUN:   1.0,
	Weather.WIND:  0.9,
	Weather.RAIN:  0.45,
	Weather.STORM: 0.25,
}

const WEATHER_FOG_MULT := {
	Weather.SUN:   1.0,
	Weather.WIND:  1.3,
	Weather.RAIN:  2.5,
	Weather.STORM: 4.0,
}

const WEATHER_AMBIENT_MULT := {
	Weather.SUN:   1.0,
	Weather.WIND:  0.95,
	Weather.RAIN:  0.7,
	Weather.STORM: 0.5,
}

const WEATHER_WEIGHTS := [0.40, 0.25, 0.20, 0.15]

var _target_sun_mult: float = 1.0
var _target_fog_mult: float = 1.0
var _target_ambient_mult: float = 1.0


func _ready() -> void:
	_rng.seed = int(Time.get_unix_time_from_system())
	_pick_next_duration()
	call_deferred("_spawn_clouds")
	call_deferred("_spawn_tumble_leaves")
	call_deferred("_spawn_horizon_silhouettes")


func _spawn_clouds() -> void:
	_cloud_parent = Node3D.new()
	_cloud_parent.name = "CloudLayer"
	get_tree().current_scene.add_child.call_deferred(_cloud_parent)

	await get_tree().process_frame

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false

	for i in CLOUD_COUNT:
		var mi := MeshInstance3D.new()
		mi.name = "Cloud%d" % i
		var quad := QuadMesh.new()
		var w := _rng.randf_range(30.0, 70.0)
		var h := _rng.randf_range(12.0, 30.0)
		quad.size = Vector2(w, h)
		mi.mesh = quad

		var cloud_mat := mat.duplicate() as StandardMaterial3D
		cloud_mat.albedo_color = _cloud_current_color
		mi.set_surface_override_material(0, cloud_mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		mi.rotation.x = -PI * 0.5
		mi.position = Vector3(
			_rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD),
			CLOUD_Y + _rng.randf_range(-5.0, 5.0),
			_rng.randf_range(-CLOUD_SPREAD, CLOUD_SPREAD))

		mi.set_meta("drift_speed", Vector3(
			_rng.randf_range(1.0, 4.0),
			0.0,
			_rng.randf_range(-0.5, 0.5)))
		mi.set_meta("y_offset", _rng.randf_range(-5.0, 5.0))

		_cloud_parent.add_child(mi)
		_clouds.append(mi)


func _spawn_tumble_leaves() -> void:
	_tumble_parent = Node3D.new()
	_tumble_parent.name = "TumblingLeaves"
	get_tree().current_scene.add_child.call_deferred(_tumble_parent)
	await get_tree().process_frame

	var shader: Shader
	if ResourceLoader.exists("res://shaders/tumbling_leaf.gdshader"):
		shader = load("res://shaders/tumbling_leaf.gdshader") as Shader

	var leaf_colors := [
		Color(0.50, 0.38, 0.12),  # dry brown
		Color(0.55, 0.30, 0.10),  # autumn brown
		Color(0.60, 0.45, 0.15),  # golden
		Color(0.35, 0.45, 0.12),  # greenish
		Color(0.65, 0.25, 0.10),  # rusty orange
	]

	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)

	for i in TUMBLE_COUNT:
		var mi := MeshInstance3D.new()
		mi.name = "TumbleLeaf%d" % i
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat: Material
		if shader:
			var smat := ShaderMaterial.new()
			smat.shader = shader
			var col: Color = leaf_colors[i % leaf_colors.size()]
			col = col.lerp(Color(_rng.randf_range(0.3, 0.7), _rng.randf_range(0.2, 0.5), _rng.randf_range(0.05, 0.2)), 0.3)
			smat.set_shader_parameter("albedo_color", Color(col, 1.0))
			smat.set_shader_parameter("tumble_speed", _rng.randf_range(1.5, 4.0))
			mat = smat
		else:
			var smat := StandardMaterial3D.new()
			smat.albedo_color = leaf_colors[i % leaf_colors.size()]
			smat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat = smat
		mi.set_surface_override_material(0, mat)

		var scale := _rng.randf_range(0.6, 1.4)
		mi.scale = Vector3(scale, scale, scale)
		mi.position = Vector3(
			_rng.randf_range(-TUMBLE_SPREAD, TUMBLE_SPREAD),
			0.15,
			_rng.randf_range(-TUMBLE_SPREAD, TUMBLE_SPREAD))

		mi.set_meta("drift_speed", Vector3(
			_rng.randf_range(1.5, 5.0),
			0.0,
			_rng.randf_range(-1.0, 1.0)))
		mi.set_meta("ground_offset", _rng.randf_range(0.08, 0.25))

		_tumble_parent.add_child(mi)
		_tumble_leaves.append(mi)


func _spawn_horizon_silhouettes() -> void:
	_horizon_parent = Node3D.new()
	_horizon_parent.name = "HorizonSilhouettes"
	get_tree().current_scene.add_child.call_deferred(_horizon_parent)
	await get_tree().process_frame

	for i in HORIZON_COUNT:
		var angle := (float(i) / float(HORIZON_COUNT)) * TAU + _rng.randf_range(-0.15, 0.15)
		var dist := HORIZON_DIST + _rng.randf_range(-20.0, 20.0)
		var px := cos(angle) * dist
		var pz := sin(angle) * dist

		var mi := MeshInstance3D.new()
		mi.name = "HorizonMtn%d" % i
		mi.mesh = _build_mountain_mesh(_rng)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat := StandardMaterial3D.new()
		var brightness := _rng.randf_range(0.25, 0.38)
		mat.albedo_color = Color(brightness * 0.8, brightness * 0.85, brightness, 1.0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.set_surface_override_material(0, mat)

		mi.position = Vector3(px, 0.0, pz)
		mi.set_meta("angle", angle)
		mi.set_meta("dist", dist)

		_horizon_parent.add_child(mi)
		_horizon_meshes.append(mi)


func _build_mountain_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var width := rng.randf_range(60.0, 120.0)
	var peak_count := rng.randi_range(2, 4)

	for _p in peak_count:
		var peak_x := rng.randf_range(-width * 0.3, width * 0.3)
		var peak_h := rng.randf_range(15.0, 40.0)
		var base_w := rng.randf_range(20.0, 50.0)

		verts.append(Vector3(peak_x - base_w * 0.5, -5.0, 0.0))
		verts.append(Vector3(peak_x + rng.randf_range(-3.0, 3.0), peak_h, rng.randf_range(-2.0, 2.0)))
		verts.append(Vector3(peak_x + base_w * 0.5, -5.0, 0.0))
		for _n in 3:
			normals.append(Vector3(0.0, 0.0, 1.0))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _process(delta: float) -> void:
	_timer += delta
	if _timer >= _next_change:
		_timer = 0.0
		_advance_weather()

	wind_intensity = move_toward(wind_intensity, _target_intensity, delta * 0.15)
	RenderingServer.global_shader_parameter_set(&"leaf_wind_multiplier", wind_intensity)

	_cloud_current_color = _cloud_current_color.lerp(_cloud_target_color, delta * 0.2)

	_push_weather_to_day_night(delta)

	if not is_instance_valid(_cached_player):
		_cached_player = null
		var players := get_tree().get_nodes_in_group(&"player")
		if not players.is_empty():
			_cached_player = players[0] as Node3D
	var player: Node3D = _cached_player

	for cloud in _clouds:
		if not is_instance_valid(cloud):
			continue
		var drift: Vector3 = cloud.get_meta("drift_speed", Vector3.ZERO)
		cloud.position += drift * wind_intensity * delta

		if player and cloud.position.x - player.global_position.x > CLOUD_SPREAD:
			cloud.position.x -= CLOUD_SPREAD * 2.0
		elif player and cloud.position.x - player.global_position.x < -CLOUD_SPREAD:
			cloud.position.x += CLOUD_SPREAD * 2.0
		if player and cloud.position.z - player.global_position.z > CLOUD_SPREAD:
			cloud.position.z -= CLOUD_SPREAD * 2.0
		elif player and cloud.position.z - player.global_position.z < -CLOUD_SPREAD:
			cloud.position.z += CLOUD_SPREAD * 2.0

		if player:
			var target_y: float = player.global_position.y + CLOUD_Y + float(cloud.get_meta("y_offset", 0.0))
			cloud.position.y = lerpf(cloud.position.y, target_y, delta * 0.5)

		var cloud_mat := cloud.get_surface_override_material(0) as StandardMaterial3D
		if cloud_mat:
			cloud_mat.albedo_color = _cloud_current_color
	
	_update_tumble_leaves(delta, player)
	_update_horizon_silhouettes(delta, player)


func _update_horizon_silhouettes(delta: float, player: Node3D) -> void:
	if not player or not is_instance_valid(player) or not is_instance_valid(_horizon_parent):
		return
	var pp := player.global_position
	for mi in _horizon_meshes:
		if not is_instance_valid(mi):
			continue
		var angle: float = mi.get_meta("angle", 0.0)
		var dist: float = mi.get_meta("dist", HORIZON_DIST)
		mi.global_position = Vector3(
			pp.x + cos(angle) * dist,
			lerpf(mi.global_position.y, pp.y - 5.0, delta * 0.5),
			pp.z + sin(angle) * dist)
		mi.look_at(Vector3(pp.x, mi.global_position.y, pp.z), Vector3.UP)


func _update_tumble_leaves(delta: float, player: Node3D) -> void:
	if not is_instance_valid(_tumble_parent):
		return
	if player and not is_instance_valid(player):
		return
	if not is_instance_valid(_cached_world_gen):
		var scene := get_tree().current_scene
		if scene:
			_cached_world_gen = scene.get_node_or_null("WorldGenerator")
	var wg := _cached_world_gen

	for leaf in _tumble_leaves:
		if not is_instance_valid(leaf):
			continue
		var drift: Vector3 = leaf.get_meta("drift_speed", Vector3.ZERO)
		leaf.global_position += drift * wind_intensity * delta

		if player:
			var gp := leaf.global_position
			var dx := gp.x - player.global_position.x
			var dz := gp.z - player.global_position.z
			if dx > TUMBLE_SPREAD:
				leaf.global_position.x -= TUMBLE_SPREAD * 2.0
			elif dx < -TUMBLE_SPREAD:
				leaf.global_position.x += TUMBLE_SPREAD * 2.0
			if dz > TUMBLE_SPREAD:
				leaf.global_position.z -= TUMBLE_SPREAD * 2.0
			elif dz < -TUMBLE_SPREAD:
				leaf.global_position.z += TUMBLE_SPREAD * 2.0

			if wg and wg.has_method("get_height_at_scene"):
				var ground_y: float = wg.get_height_at_scene(leaf.global_position.x, leaf.global_position.z)
				var offset: float = leaf.get_meta("ground_offset", 0.15)
				var target_y := ground_y + offset
				if target_y < wg.WATER_LEVEL:
					target_y = wg.WATER_LEVEL + offset
				leaf.global_position.y = lerpf(leaf.global_position.y, target_y, delta * 3.0)


func _advance_weather() -> void:
	# TODO: re-enable weather variety once FPS cost is addressed
	current_weather = Weather.SUN
	_target_intensity = WEATHER_WIND[current_weather]
	_cloud_target_color = WEATHER_CLOUD_COLOR[current_weather]
	_target_sun_mult = WEATHER_SUN_MULT[current_weather]
	_target_fog_mult = WEATHER_FOG_MULT[current_weather]
	_target_ambient_mult = WEATHER_AMBIENT_MULT[current_weather]
	_pick_next_duration()
	weather_changed.emit(current_weather)


func _push_weather_to_day_night(delta: float) -> void:
	if not is_instance_valid(_cached_day_night):
		var scene := get_tree().current_scene
		if scene:
			_cached_day_night = scene.get_node_or_null("DayNightCycle")
	if not _cached_day_night:
		return
	var lerp_speed := delta * 0.3
	_cached_day_night.weather_sun_mult = lerpf(_cached_day_night.weather_sun_mult, _target_sun_mult, lerp_speed)
	_cached_day_night.weather_fog_mult = lerpf(_cached_day_night.weather_fog_mult, _target_fog_mult, lerp_speed)
	_cached_day_night.weather_ambient_mult = lerpf(_cached_day_night.weather_ambient_mult, _target_ambient_mult, lerp_speed)


func _pick_next_duration() -> void:
	var dur_range: Vector2 = WEATHER_DURATIONS[current_weather]
	_next_change = _rng.randf_range(dur_range.x, dur_range.y)


func get_weather_emoji() -> String:
	var is_night := _is_nighttime()
	match current_weather:
		Weather.SUN:   return "~" if is_night else "*"
		Weather.WIND:  return "w"
		Weather.RAIN:  return "R"
		Weather.STORM: return "S"
		_:             return "~" if is_night else "*"


func _is_nighttime() -> bool:
	if _cached_day_night and _cached_day_night.has_method("get_hour"):
		var hour: int = _cached_day_night.get_hour()
		return hour >= 21 or hour < 5
	return false


func get_weather_name() -> String:
	match current_weather:
		Weather.SUN:   return "Clear"
		Weather.WIND:  return "Windy"
		Weather.RAIN:  return "Rain"
		Weather.STORM: return "Storm"
		_:             return "Clear"
