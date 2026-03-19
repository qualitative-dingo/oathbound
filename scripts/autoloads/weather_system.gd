extends Node
## Global weather system. Cycles between sun/wind/rain/storm.
## Other systems read current_weather and wind_intensity.

enum Weather { SUN, WIND, RAIN, STORM }

signal weather_changed(new_weather: Weather)

var current_weather: Weather = Weather.SUN
var wind_intensity: float = 0.3

var _timer: float = 0.0
var _next_change: float = 120.0
var _rng := RandomNumberGenerator.new()
var _target_intensity: float = 0.3

var _cloud_parent: Node3D
var _clouds: Array[MeshInstance3D] = []
var _cloud_target_color := Color(1.0, 1.0, 1.0, 0.55)
var _cloud_current_color := Color(1.0, 1.0, 1.0, 0.55)
const CLOUD_COUNT := 18
const CLOUD_Y := 80.0
const CLOUD_SPREAD := 200.0
var _cached_player: Node3D

const WEATHER_DURATIONS := {
	Weather.SUN:   Vector2(90.0, 200.0),
	Weather.WIND:  Vector2(60.0, 150.0),
	Weather.RAIN:  Vector2(40.0, 120.0),
	Weather.STORM: Vector2(30.0, 80.0),
}

const WEATHER_WIND := {
	Weather.SUN:   0.3,
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

const WEATHER_WEIGHTS := [0.40, 0.25, 0.20, 0.15]


func _ready() -> void:
	_rng.seed = int(Time.get_unix_time_from_system())
	_pick_next_duration()
	call_deferred("_spawn_clouds")


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


func _process(delta: float) -> void:
	# Weather cycling disabled during development — locked to SUN
	#_timer += delta
	#if _timer >= _next_change:
	#	_timer = 0.0
	#	_advance_weather()

	wind_intensity = move_toward(wind_intensity, _target_intensity, delta * 0.15)
	RenderingServer.global_shader_parameter_set(&"leaf_wind_multiplier", wind_intensity)

	_cloud_current_color = _cloud_current_color.lerp(_cloud_target_color, delta * 0.2)

	if not is_instance_valid(_cached_player):
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


func _advance_weather() -> void:
	var roll := _rng.randf()
	var accum := 0.0
	var new_w := Weather.SUN
	for i in WEATHER_WEIGHTS.size():
		accum += WEATHER_WEIGHTS[i]
		if roll < accum:
			new_w = i as Weather
			break
	current_weather = new_w
	_target_intensity = WEATHER_WIND[current_weather]
	_cloud_target_color = WEATHER_CLOUD_COLOR[current_weather]
	_pick_next_duration()
	weather_changed.emit(current_weather)


func _pick_next_duration() -> void:
	var dur_range: Vector2 = WEATHER_DURATIONS[current_weather]
	_next_change = _rng.randf_range(dur_range.x, dur_range.y)


func get_weather_emoji() -> String:
	match current_weather:
		Weather.SUN:   return "☀"
		Weather.WIND:  return "💨"
		Weather.RAIN:  return "🌧"
		Weather.STORM: return "⛈"
		_:             return "☀"


func get_weather_name() -> String:
	match current_weather:
		Weather.SUN:   return "Clear"
		Weather.WIND:  return "Windy"
		Weather.RAIN:  return "Rain"
		Weather.STORM: return "Storm"
		_:             return "Clear"
