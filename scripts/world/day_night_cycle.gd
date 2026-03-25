extends Node3D
## Drives the sun arc, sky colors, ambient light, fog, glow, and tonemap
## across a full day/night cycle. Attach to the scene root or as a child
## of the world node that also holds DirectionalLight3D + WorldEnvironment.

# ── Time ─────────────────────────────────────────────────────────────────
const DAY_LENGTH_SECONDS := 1200.0  # 20 real-minutes = one full day
var game_time: float = 0.3          # 0.0–1.0, 0.0 = midnight, 0.5 = noon
var time_speed: float = 1.0
var paused: bool = false

# ── Node refs (resolved at runtime) ─────────────────────────────────────
var _sun: DirectionalLight3D
var _env: Environment
var _sky_mat: ProceduralSkyMaterial

# ── Cached base values from the scene (so biome tweaks layer on top) ────
var _base_fog_density: float = 0.0005
var _base_fog_color: Color = Color(0.65, 0.72, 0.82)
var _base_ambient_color: Color = Color(0.38, 0.42, 0.58)

# ── Weather multipliers (set by WeatherSystem integration) ──────────────
var weather_sun_mult: float = 1.0
var weather_fog_mult: float = 1.0
var weather_ambient_mult: float = 1.0

# ── Sun arc parameters ──────────────────────────────────────────────────
var SUN_AXIS := Vector3(-1.0, 0.0, -0.5).normalized()
const MOON_OFFSET := PI  # moon is opposite the sun

# ── Gradient keyframes: time → value ────────────────────────────────────
# Times: 0.0=midnight(00:00), 0.125=03:00 (dawn begins),
#         0.167=04:00 (golden hour), 0.229=05:30 (full day),
#         0.5=noon(12:00), 0.875=21:00 (sunset begins),
#         0.917=22:00 (golden hour), 0.958=23:00 (last sun),
#         1.0=midnight(00:00)
# Pitch dark: 00:00–03:00.  Sunset begins 21:00, dark by midnight.

const NIGHT_END   := 0.125   # 03:00 — end of full darkness / dawn trigger
const NIGHT_START := 0.0     # 00:00 — midnight, full darkness begins

const SUN_ENERGY_KEYS := [
	[0.0,    0.0],    # midnight — pitch dark
	[0.125,  0.0],    # 03:00 — still dark, about to rise
	[0.146,  0.2],    # 03:30 — first hint of light
	[0.167,  0.6],    # 04:00 — golden hour glow
	[0.229,  1.5],    # 05:30 — full day
	[0.35,   1.7],    # 08:24 — mid-morning
	[0.50,   1.9],    # 12:00 — noon peak
	[0.70,   1.7],    # 16:48 — afternoon
	[0.83,   1.5],    # 19:55 — bright evening
	[0.875,  1.2],    # 21:00 — sunset begins
	[0.917,  0.6],    # 22:00 — golden hour
	[0.958,  0.15],   # 23:00 — last efforts of sun
	[0.98,   0.0],    # 23:31 — dark
	[1.0,    0.0],    # midnight
]

const SUN_COLOR_KEYS := [
	[0.0,    Color(0.15, 0.18, 0.35)],  # midnight blue
	[0.125,  Color(0.15, 0.18, 0.35)],  # 03:00 blue
	[0.146,  Color(1.0, 0.45, 0.20)],   # 03:30 dawn orange
	[0.167,  Color(1.0, 0.60, 0.30)],   # 04:00 golden
	[0.229,  Color(1.0, 0.85, 0.60)],   # 05:30 morning gold
	[0.50,   Color(1.0, 0.95, 0.88)],   # noon white-warm
	[0.80,   Color(1.0, 0.85, 0.60)],   # afternoon gold
	[0.875,  Color(1.0, 0.65, 0.35)],   # 21:00 sunset warm
	[0.917,  Color(1.0, 0.50, 0.22)],   # 22:00 golden orange
	[0.958,  Color(0.50, 0.25, 0.30)],  # 23:00 deep reddish
	[0.98,   Color(0.15, 0.18, 0.35)],  # 23:31 night blue
	[1.0,    Color(0.15, 0.18, 0.35)],  # midnight
]

const AMBIENT_ENERGY_KEYS := [
	[0.0,    0.03],   # midnight — pitch dark
	[0.125,  0.03],   # 03:00 — pitch dark
	[0.146,  0.15],   # 03:30 — first glow
	[0.167,  0.30],   # 04:00 — dawn ambient
	[0.229,  0.55],   # 05:30 — full day
	[0.50,   0.70],   # noon
	[0.80,   0.55],   # afternoon
	[0.875,  0.45],   # 21:00 — sunset
	[0.917,  0.25],   # 22:00 — golden
	[0.958,  0.08],   # 23:00 — last light
	[0.98,   0.03],   # near midnight
	[1.0,    0.03],   # midnight
]

const AMBIENT_COLOR_KEYS := [
	[0.0,    Color(0.08, 0.08, 0.15)],  # midnight deep blue
	[0.125,  Color(0.08, 0.08, 0.15)],  # 03:00
	[0.146,  Color(0.35, 0.28, 0.40)],  # dawn purple
	[0.167,  Color(0.45, 0.38, 0.50)],  # 04:00 purple-pink
	[0.229,  Color(0.40, 0.45, 0.60)],  # morning
	[0.50,   Color(0.38, 0.42, 0.58)],  # noon
	[0.80,   Color(0.40, 0.45, 0.60)],  # afternoon
	[0.875,  Color(0.45, 0.40, 0.48)],  # 21:00 sunset warm
	[0.917,  Color(0.35, 0.28, 0.40)],  # golden warm
	[0.958,  Color(0.15, 0.15, 0.25)],  # dusk
	[0.98,   Color(0.08, 0.08, 0.15)],  # near midnight
	[1.0,    Color(0.08, 0.08, 0.15)],  # midnight
]

const SKY_TOP_KEYS := [
	[0.0,    Color(0.02, 0.02, 0.06)],  # pitch dark sky
	[0.125,  Color(0.02, 0.02, 0.06)],  # 03:00
	[0.146,  Color(0.10, 0.08, 0.22)],  # pre-dawn
	[0.167,  Color(0.15, 0.12, 0.30)],  # dawn purple
	[0.229,  Color(0.18, 0.35, 0.70)],  # morning blue
	[0.50,   Color(0.22, 0.42, 0.78)],  # noon
	[0.80,   Color(0.18, 0.35, 0.70)],  # afternoon
	[0.875,  Color(0.22, 0.25, 0.50)],  # 21:00 sunset blue-purple
	[0.917,  Color(0.18, 0.12, 0.30)],  # golden purple
	[0.958,  Color(0.06, 0.05, 0.14)],  # near dark
	[0.98,   Color(0.02, 0.02, 0.06)],  # dark
	[1.0,    Color(0.02, 0.02, 0.06)],  # midnight
]

const SKY_HORIZON_KEYS := [
	[0.0,    Color(0.04, 0.04, 0.08)],  # pitch dark
	[0.125,  Color(0.04, 0.04, 0.08)],  # 03:00
	[0.146,  Color(0.55, 0.30, 0.18)],  # dawn orange
	[0.167,  Color(0.85, 0.50, 0.28)],  # golden orange horizon
	[0.229,  Color(0.60, 0.65, 0.78)],  # morning
	[0.50,   Color(0.50, 0.62, 0.78)],  # noon
	[0.80,   Color(0.60, 0.65, 0.78)],  # afternoon
	[0.875,  Color(0.85, 0.50, 0.25)],  # 21:00 sunset orange
	[0.917,  Color(0.80, 0.35, 0.18)],  # golden deep orange
	[0.958,  Color(0.25, 0.12, 0.10)],  # last glow
	[0.98,   Color(0.04, 0.04, 0.08)],  # dark
	[1.0,    Color(0.04, 0.04, 0.08)],  # midnight
]

const FOG_DENSITY_KEYS := [
	[0.0,    2.0],    # midnight: dense
	[0.125,  2.0],    # 03:00
	[0.146,  1.5],    # dawn: misty
	[0.229,  1.0],    # morning: clearing
	[0.50,   1.0],    # noon: base
	[0.80,   1.0],    # afternoon
	[0.917,  1.3],    # 22:00 golden mist
	[0.958,  1.8],    # near dark
	[1.0,    2.0],    # midnight
]

const FOG_COLOR_KEYS := [
	[0.0,    Color(0.05, 0.05, 0.10)],  # very dark
	[0.125,  Color(0.05, 0.05, 0.10)],  # 03:00
	[0.146,  Color(0.50, 0.35, 0.28)],  # dawn warm fog
	[0.229,  Color(0.65, 0.72, 0.82)],  # morning
	[0.50,   Color(0.65, 0.72, 0.82)],  # noon
	[0.80,   Color(0.65, 0.72, 0.82)],  # afternoon
	[0.875,  Color(0.65, 0.48, 0.32)],  # 21:00 sunset warm
	[0.917,  Color(0.50, 0.32, 0.22)],  # golden
	[0.958,  Color(0.12, 0.10, 0.16)],  # near dark
	[1.0,    Color(0.05, 0.05, 0.10)],  # midnight
]

const SUN_SCATTER_KEYS := [
	[0.0,    0.0],
	[0.125,  0.0],
	[0.146,  0.7],    # dawn scatter
	[0.167,  0.9],    # golden dawn
	[0.229,  0.4],
	[0.50,   0.3],    # noon: mild
	[0.80,   0.4],
	[0.875,  0.7],    # sunset scatter
	[0.917,  0.9],    # golden hour
	[0.958,  0.3],
	[0.98,   0.0],
	[1.0,    0.0],
]

const GLOW_INTENSITY_KEYS := [
	[0.0,    0.15],   # minimal at night
	[0.125,  0.15],
	[0.146,  0.35],
	[0.167,  0.5],    # dawn glow
	[0.50,   0.6],    # noon
	[0.875,  0.5],    # sunset glow
	[0.917,  0.5],    # golden glow
	[0.958,  0.25],
	[0.98,   0.15],
	[1.0,    0.15],
]

const TONEMAP_EXPOSURE_KEYS := [
	[0.0,    0.65],   # dark night
	[0.125,  0.65],
	[0.146,  0.80],
	[0.167,  0.90],   # dawn
	[0.229,  1.0],    # full day
	[0.50,   1.0],    # noon
	[0.80,   1.0],
	[0.875,  0.95],   # sunset
	[0.917,  0.85],   # golden
	[0.958,  0.70],   # last light
	[0.98,   0.65],
	[1.0,    0.65],
]

const SATURATION_KEYS := [
	[0.0,    0.50],   # desaturated at night
	[0.125,  0.50],
	[0.146,  0.70],
	[0.167,  0.90],   # dawn boosted
	[0.229,  1.05],
	[0.50,   0.95],   # noon
	[0.80,   1.05],   # golden hour boosted
	[0.917,  0.85],   # sunset
	[0.958,  0.60],
	[0.98,   0.50],
	[1.0,    0.50],
]

const SHADOW_OPACITY_KEYS := [
	[0.0,    0.0],    # night: no shadows
	[0.125,  0.0],
	[0.146,  0.20],
	[0.167,  0.45],   # dawn
	[0.229,  0.70],   # full day
	[0.35,   0.75],
	[0.50,   0.75],   # noon
	[0.70,   0.75],
	[0.83,   0.70],
	[0.875,  0.55],   # sunset
	[0.917,  0.30],   # golden
	[0.958,  0.10],   # last light
	[0.98,   0.0],
	[1.0,    0.0],
]

# ── Volumetric fog (god rays) ───────────────────────────────────────────
const VOLUMETRIC_DENSITY_KEYS := [
	[0.0,    0.0],
	[0.125,  0.0],
	[0.146,  0.010],  # dawn rays
	[0.167,  0.015],  # golden dawn
	[0.229,  0.005],
	[0.50,   0.002],  # noon: subtle
	[0.80,   0.005],
	[0.875,  0.010],  # sunset rays
	[0.917,  0.015],  # golden sunset
	[0.958,  0.005],
	[0.98,   0.0],
	[1.0,    0.0],
]


func _ready() -> void:
	_find_scene_nodes()
	game_time = 0.35  # start at mid-morning


func _find_scene_nodes() -> void:
	await get_tree().process_frame
	for node in get_tree().get_nodes_in_group(&"sun"):
		if node is DirectionalLight3D:
			_sun = node as DirectionalLight3D
			break
	if not _sun:
		_sun = _find_child_of_type("DirectionalLight3D") as DirectionalLight3D

	var we: WorldEnvironment
	for node in get_tree().get_nodes_in_group(&"world_environment"):
		if node is WorldEnvironment:
			we = node as WorldEnvironment
			break
	if not we:
		we = _find_child_of_type("WorldEnvironment") as WorldEnvironment
	if we:
		_env = we.environment
		if _env and _env.sky and _env.sky.sky_material is ProceduralSkyMaterial:
			_sky_mat = _env.sky.sky_material as ProceduralSkyMaterial
		_base_fog_density = _env.fog_density if _env else 0.0005
		_base_fog_color = _env.fog_light_color if _env else Color(0.65, 0.72, 0.82)
		_base_ambient_color = _env.ambient_light_color if _env else Color(0.38, 0.42, 0.58)


func _find_child_of_type(type_name: String) -> Node:
	var root := get_tree().current_scene
	if not root:
		return null
	for child in root.get_children():
		if child.get_class() == type_name:
			return child
	return null


func _process(delta: float) -> void:
	if paused or not _sun:
		return

	game_time += (delta / DAY_LENGTH_SECONDS) * time_speed
	if game_time >= 1.0:
		game_time -= 1.0

	_update_sun()
	_update_environment()

	var is_day := game_time > NIGHT_END
	var was_day: bool = get_meta("_was_day", true)
	if is_day != was_day:
		set_meta("_was_day", is_day)
		GameEvents.day_night_changed.emit(is_day)


func _update_sun() -> void:
	var sun_angle := (game_time - 0.5) * TAU
	var rot := Basis(SUN_AXIS, sun_angle)
	var sun_dir := rot * Vector3.UP
	_sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.FORWARD)
	_sun.global_position.y = 20.0

	_sun.light_energy = _sample_float(SUN_ENERGY_KEYS, game_time) * weather_sun_mult
	_sun.light_color = _sample_color(SUN_COLOR_KEYS, game_time)
	_sun.shadow_opacity = _sample_float(SHADOW_OPACITY_KEYS, game_time)


func _update_environment() -> void:
	if not _env:
		return

	# Sky colors
	if _sky_mat:
		_sky_mat.sky_top_color = _sample_color(SKY_TOP_KEYS, game_time)
		_sky_mat.sky_horizon_color = _sample_color(SKY_HORIZON_KEYS, game_time)

	# Ambient
	_env.ambient_light_energy = _sample_float(AMBIENT_ENERGY_KEYS, game_time) * weather_ambient_mult
	_env.ambient_light_color = _sample_color(AMBIENT_COLOR_KEYS, game_time)

	# Fog
	var fog_time_mult := _sample_float(FOG_DENSITY_KEYS, game_time)
	_env.fog_density = _base_fog_density * fog_time_mult * weather_fog_mult
	_env.fog_light_color = _sample_color(FOG_COLOR_KEYS, game_time)
	_env.fog_sun_scatter = _sample_float(SUN_SCATTER_KEYS, game_time)

	# Glow
	_env.glow_intensity = _sample_float(GLOW_INTENSITY_KEYS, game_time)

	# Tonemap
	_env.tonemap_exposure = _sample_float(TONEMAP_EXPOSURE_KEYS, game_time)

	# Color grading
	_env.adjustment_saturation = _sample_float(SATURATION_KEYS, game_time)

	# Volumetric fog (god rays)
	var vol_density := _sample_float(VOLUMETRIC_DENSITY_KEYS, game_time) * weather_fog_mult
	if vol_density > 0.0001:
		if not _env.volumetric_fog_enabled:
			_env.volumetric_fog_enabled = true
		_env.volumetric_fog_density = vol_density
		_env.volumetric_fog_albedo = _env.fog_light_color.lerp(Color.WHITE, 0.3)
		_env.volumetric_fog_emission = _sun.light_color * 0.15
		_env.volumetric_fog_emission_energy = _sun.light_energy * 0.5
		_env.volumetric_fog_gi_inject = 0.5
		_env.volumetric_fog_anisotropy = 0.6
		_env.volumetric_fog_length = 120.0
	else:
		if _env.volumetric_fog_enabled:
			_env.volumetric_fog_enabled = false


# ── Gradient sampling helpers ────────────────────────────────────────────

static func _sample_float(keys: Array, t: float) -> float:
	if keys.is_empty():
		return 0.0
	if t <= keys[0][0]:
		return float(keys[0][1])
	if t >= keys[-1][0]:
		return float(keys[-1][1])
	for i in range(keys.size() - 1):
		var k0: Array = keys[i]
		var k1: Array = keys[i + 1]
		if t >= k0[0] and t <= k1[0]:
			var frac: float = (t - float(k0[0])) / (float(k1[0]) - float(k0[0]))
			frac = frac * frac * (3.0 - 2.0 * frac)  # smoothstep
			return lerpf(float(k0[1]), float(k1[1]), frac)
	return float(keys[-1][1])


static func _sample_color(keys: Array, t: float) -> Color:
	if keys.is_empty():
		return Color.WHITE
	if t <= keys[0][0]:
		return keys[0][1] as Color
	if t >= keys[-1][0]:
		return keys[-1][1] as Color
	for i in range(keys.size() - 1):
		var k0: Array = keys[i]
		var k1: Array = keys[i + 1]
		if t >= k0[0] and t <= k1[0]:
			var frac: float = (t - float(k0[0])) / (float(k1[0]) - float(k0[0]))
			frac = frac * frac * (3.0 - 2.0 * frac)
			return (k0[1] as Color).lerp(k1[1] as Color, frac)
	return keys[-1][1] as Color


# ── Public API ───────────────────────────────────────────────────────────

func get_hour() -> int:
	return int(game_time * 24.0) % 24

func get_time_string() -> String:
	var total_minutes := int(game_time * 24.0 * 60.0)
	var h := (total_minutes / 60) % 24
	var m := total_minutes % 60
	return "%02d:%02d" % [h, m]

func is_daytime() -> bool:
	return game_time > NIGHT_END

func set_time(new_time: float) -> void:
	game_time = fmod(new_time, 1.0)
