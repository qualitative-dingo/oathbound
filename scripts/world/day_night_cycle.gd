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
# Times: 0.0=midnight(00:00), ~0.21=dawn(05:00), 0.5=noon(12:00),
#         ~0.71=dusk(17:00), 1.0=midnight(00:00)

const SUN_ENERGY_KEYS := [
	[0.0,  0.0],   # midnight
	[0.16, 0.0],   # pre-dawn
	[0.21, 0.4],   # dawn start (05:00)
	[0.26, 1.2],   # dawn
	[0.31, 1.6],   # morning
	[0.50, 1.9],   # noon
	[0.61, 1.6],   # afternoon
	[0.66, 1.2],   # dusk
	[0.71, 0.4],   # dusk end (17:00)
	[0.76, 0.0],   # post-dusk
	[1.0,  0.0],   # midnight
]

const SUN_COLOR_KEYS := [
	[0.0,  Color(0.15, 0.18, 0.35)],  # midnight blue (moon)
	[0.18, Color(0.15, 0.18, 0.35)],  # pre-dawn
	[0.22, Color(1.0, 0.55, 0.25)],   # dawn orange
	[0.28, Color(1.0, 0.82, 0.55)],   # morning gold
	[0.50, Color(1.0, 0.95, 0.88)],   # noon white-warm
	[0.64, Color(1.0, 0.82, 0.55)],   # afternoon gold
	[0.70, Color(1.0, 0.50, 0.22)],   # dusk orange
	[0.74, Color(0.15, 0.18, 0.35)],  # post-dusk
	[1.0,  Color(0.15, 0.18, 0.35)],  # midnight
]

const AMBIENT_ENERGY_KEYS := [
	[0.0,  0.30],  # midnight (brighter so not pitch black)
	[0.18, 0.30],
	[0.24, 0.45],  # dawn
	[0.50, 0.70],  # noon
	[0.68, 0.45],  # dusk
	[0.74, 0.30],
	[1.0,  0.30],
]

const AMBIENT_COLOR_KEYS := [
	[0.0,  Color(0.15, 0.17, 0.32)],  # midnight blue (brighter)
	[0.18, Color(0.16, 0.18, 0.33)],
	[0.24, Color(0.45, 0.38, 0.50)],  # dawn purple-pink
	[0.40, Color(0.40, 0.45, 0.60)],  # morning
	[0.50, Color(0.38, 0.42, 0.58)],  # noon (matches original)
	[0.60, Color(0.40, 0.45, 0.60)],
	[0.68, Color(0.45, 0.35, 0.45)],  # dusk warm
	[0.74, Color(0.16, 0.18, 0.33)],
	[1.0,  Color(0.15, 0.17, 0.32)],
]

const SKY_TOP_KEYS := [
	[0.0,  Color(0.04, 0.04, 0.10)],  # night sky (slightly brighter)
	[0.18, Color(0.04, 0.04, 0.10)],
	[0.23, Color(0.15, 0.12, 0.30)],  # pre-dawn purple
	[0.28, Color(0.18, 0.35, 0.70)],  # dawn blue
	[0.50, Color(0.22, 0.42, 0.78)],  # noon
	[0.64, Color(0.18, 0.35, 0.70)],
	[0.69, Color(0.25, 0.12, 0.30)],  # dusk purple
	[0.74, Color(0.04, 0.04, 0.10)],
	[1.0,  Color(0.04, 0.04, 0.10)],
]

const SKY_HORIZON_KEYS := [
	[0.0,  Color(0.08, 0.08, 0.16)],  # night (slightly brighter)
	[0.18, Color(0.08, 0.08, 0.16)],
	[0.22, Color(0.85, 0.45, 0.25)],  # dawn orange horizon
	[0.28, Color(0.60, 0.65, 0.78)],
	[0.50, Color(0.50, 0.62, 0.78)],  # noon
	[0.64, Color(0.60, 0.65, 0.78)],
	[0.70, Color(0.85, 0.40, 0.20)],  # dusk orange
	[0.74, Color(0.08, 0.08, 0.16)],
	[1.0,  Color(0.08, 0.08, 0.16)],
]

const FOG_DENSITY_KEYS := [
	[0.0,  1.8],   # night: foggy
	[0.21, 1.5],   # dawn: misty
	[0.31, 1.0],   # morning: clearing
	[0.50, 1.0],   # noon: base
	[0.61, 1.0],
	[0.71, 1.5],   # dusk: mist returns
	[1.0,  1.8],
]

const FOG_COLOR_KEYS := [
	[0.0,  Color(0.10, 0.12, 0.22)],  # night (slightly brighter)
	[0.18, Color(0.10, 0.12, 0.22)],
	[0.23, Color(0.60, 0.45, 0.35)],  # dawn warm fog
	[0.31, Color(0.65, 0.72, 0.82)],
	[0.50, Color(0.65, 0.72, 0.82)],  # noon
	[0.61, Color(0.65, 0.72, 0.82)],
	[0.69, Color(0.60, 0.42, 0.30)],  # dusk warm
	[0.74, Color(0.10, 0.12, 0.22)],
	[1.0,  Color(0.10, 0.12, 0.22)],
]

const SUN_SCATTER_KEYS := [
	[0.0,  0.0],
	[0.18, 0.0],
	[0.22, 0.9],   # dawn: strong scatter
	[0.31, 0.4],
	[0.50, 0.3],   # noon: mild
	[0.61, 0.4],
	[0.70, 0.9],   # dusk: strong scatter
	[0.74, 0.0],
	[1.0,  0.0],
]

const GLOW_INTENSITY_KEYS := [
	[0.0,  0.3],
	[0.21, 0.5],   # dawn glow
	[0.50, 0.6],   # noon
	[0.71, 0.5],   # dusk glow
	[1.0,  0.3],
]

const TONEMAP_EXPOSURE_KEYS := [
	[0.0,  0.85],  # night: slightly brighter exposure
	[0.18, 0.85],
	[0.26, 1.0],   # dawn
	[0.50, 1.0],   # noon
	[0.66, 1.0],   # dusk
	[0.74, 0.85],
	[1.0,  0.85],
]

const SATURATION_KEYS := [
	[0.0,  0.70],  # night: slightly less desaturated
	[0.18, 0.70],
	[0.24, 1.05],  # dawn: slightly boosted
	[0.50, 0.95],  # noon (matches original)
	[0.68, 1.05],  # dusk: slightly boosted
	[0.74, 0.70],
	[1.0,  0.70],
]

const SHADOW_OPACITY_KEYS := [
	[0.0,  0.0],   # night: no shadows
	[0.18, 0.0],
	[0.24, 0.55],  # dawn
	[0.31, 0.70],
	[0.50, 0.75],  # noon: strong shadows
	[0.61, 0.70],
	[0.68, 0.55],
	[0.74, 0.0],
	[1.0,  0.0],
]

# ── Volumetric fog (god rays) ───────────────────────────────────────────
const VOLUMETRIC_DENSITY_KEYS := [
	[0.0,  0.0],
	[0.19, 0.0],
	[0.22, 0.015],  # dawn god rays
	[0.28, 0.005],
	[0.50, 0.002],  # noon: subtle
	[0.64, 0.005],
	[0.70, 0.015],  # dusk god rays
	[0.74, 0.0],
	[1.0,  0.0],
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

	var is_day := game_time > 0.21 and game_time < 0.71
	# Emit once on transitions (simple edge detect via meta)
	var was_day: bool = get_meta("_was_day", true)
	if is_day != was_day:
		set_meta("_was_day", is_day)
		GameEvents.day_night_changed.emit(is_day)


func _update_sun() -> void:
	var sun_angle := (game_time - 0.21) * TAU
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
	return game_time > 0.21 and game_time < 0.71

func set_time(new_time: float) -> void:
	game_time = fmod(new_time, 1.0)
