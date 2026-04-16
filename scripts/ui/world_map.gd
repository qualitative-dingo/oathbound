class_name WorldMap
extends CanvasLayer

## Full-screen rectangular world map.
## Renders a precomputed overview texture once at world load and then just
## scales/crops it for zoom+pan. Fog-of-war is a separate per-zone mask with
## an animated noise shader. Markers and player arrow are drawn on top via
## Control._draw(). Replaces the per-frame CPU chunked renderer that used to
## live in player_controller.gd.

signal opened
signal closed

const BASE_TEX_RES := 1024                # resolution of the precomputed world texture
const PRECOMPUTE_BUDGET_US := 3000        # per-frame budget while precomputing
const ZOOM_MIN := 1.0
const ZOOM_MAX := 8.0
const ZOOM_STEP := 0.4
const ZOOM_LERP_SPEED := 14.0
const PAN_MARGIN_PX := 32                 # keep at least this much texture visible

const _FOG_NOISE_RES := 128
const _FOG_COLOR := Color(0.04, 0.03, 0.08)
const _BG_COLOR := Color(0.02, 0.02, 0.04, 0.72)
const _FRAME_COLOR := Color(0.32, 0.26, 0.18, 1.0)
const _INNER_FRAME_COLOR := Color(0.12, 0.09, 0.06, 1.0)

var _wg: WorldGenerator
var _player: Node3D
var _camera_ref: Camera3D

# Precompute state
var _precompute_image: Image
var _precompute_tex: ImageTexture
var _precompute_row: int = 0
var _precompute_done: bool = false
var _precompute_started: bool = false

# Fog of war state. The mask lives at BASE_TEX_RES so UVs line up exactly
# with the terrain overview texture. Each zone fills the rectangle of pixels
# that covers it in world space.
var _fog_image: Image
var _fog_tex: ImageTexture
var _fog_dirty: bool = false
var _fog_seeded: bool = false
var _reveal_all: bool = false
var _fog_time: float = 0.0

# UI nodes
var _root_panel: Panel
var _frame: Panel
var _viewport: Control
var _terrain_rect: TextureRect
var _fog_rect: ColorRect
var _fog_material: ShaderMaterial
var _overlay: Control
var _title_label: Label
var _biome_label: Label
var _hint_label: Label
var _compass_labels: Array[Label] = []

# Zoom/pan
var _zoom: float = 1.0
var _zoom_target: float = 1.0
var _pan_tex: Vector2 = Vector2(512, 512)  # texture pixel shown at viewport center
var _is_panning: bool = false
var _pan_last_mouse: Vector2

# Markers (world-space)
var _markers: Array[Dictionary] = []

# Player arrow
var _arrow_texture: ImageTexture

# State
var _is_open: bool = false
var _is_disabled: bool = false
var _viewport_size: Vector2 = Vector2(960, 720)
const _VIEWPORT_MARGIN := Vector2(80, 140)  # space reserved for title/labels/hint

# Cached biome/height samples per texture pixel so the colours match the
# minimap's _biome_map_color pipeline.
const _BIOME_HEARTHLANDS := &"hearthlands"
const _BIOME_OCEAN := &"ocean"


func _ready() -> void:
	layer = 8   # above HUD (which sits on the default CanvasLayer)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_recompute_viewport_size()
	_build_ui()
	_arrow_texture = _generate_arrow_texture(64)
	get_viewport().size_changed.connect(_on_window_resized)


func _recompute_viewport_size() -> void:
	var screen := Vector2.ZERO
	var vp := get_viewport()
	if vp:
		screen = vp.get_visible_rect().size
	if screen.x <= 0.0 or screen.y <= 0.0:
		screen = Vector2(1280, 720)
	var max_w := screen.x - _VIEWPORT_MARGIN.x
	var max_h := screen.y - _VIEWPORT_MARGIN.y
	var side := minf(max_w, max_h)
	side = clampf(side, 400.0, 1400.0)
	_viewport_size = Vector2(side, side)


func _on_window_resized() -> void:
	_recompute_viewport_size()
	if _viewport:
		_viewport.custom_minimum_size = _viewport_size
		_viewport.size = _viewport_size
	if _overlay:
		_overlay.size = _viewport_size
	if _frame:
		_frame.custom_minimum_size = _viewport_size + Vector2(24, 24)
	_reposition_compass_labels()
	_clamp_pan()
	_update_layout()


# ───────────────────────── Public API ──────────────────────────────────────────

func setup(player: Node3D, wg: WorldGenerator) -> void:
	_player = player
	_bind_world_generator(wg)


## Connect to the WorldGenerator and (re)seed fog. If [param wg] is null we
## fall back to searching the scene; if still missing, we retry once per frame
## via [method _process] until the generator appears. This keeps us safe when
## the player spawns before world generation finishes.
func _bind_world_generator(wg: WorldGenerator) -> void:
	if wg == null:
		wg = _find_world_generator_in_tree()
	if wg == null:
		return
	if _wg == wg and _fog_seeded:
		return
	_wg = wg
	if not _wg.zone_explored.is_connected(_on_zone_explored):
		_wg.zone_explored.connect(_on_zone_explored)
	_seed_fog_from_explored()
	_kickoff_precompute_when_ready()


func _find_world_generator_in_tree() -> WorldGenerator:
	if not is_inside_tree():
		return null
	var nodes := get_tree().get_nodes_in_group(&"world_generator")
	for n in nodes:
		if n is WorldGenerator:
			return n as WorldGenerator
	return null


func set_camera(cam: Camera3D) -> void:
	_camera_ref = cam


func toggle() -> void:
	if _is_disabled:
		return
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	if _is_disabled or _is_open:
		return
	_is_open = true
	visible = true
	_zoom = _zoom_target
	_center_on_player()
	if _biome_label and _wg and _player:
		var pp := _wg.get_world_position(_player)
		_biome_label.text = _biome_display_name(_wg.get_biome_at(pp))
	_queue_overlay_redraw()
	opened.emit()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	_is_panning = false
	closed.emit()


func is_open() -> bool:
	return _is_open


func set_disabled(val: bool) -> void:
	_is_disabled = val
	if val and _is_open:
		close()


func is_disabled() -> bool:
	return _is_disabled


func set_reveal_all(val: bool) -> void:
	if _reveal_all == val:
		return
	_reveal_all = val
	if _fog_material:
		_fog_material.set_shader_parameter(&"reveal_all", val)


func reveal_marker(marker_id: String, world_pos: Vector3, label_text: String) -> void:
	for m in _markers:
		if m.get("id", "") == marker_id:
			return
	_markers.append({
		"id": marker_id,
		"pos": world_pos,
		"label": label_text,
		"color": Color(1.0, 0.85, 0.3),
	})
	_queue_overlay_redraw()


func clear_markers() -> void:
	_markers.clear()
	_queue_overlay_redraw()


# ───────────────────────── UI construction ─────────────────────────────────────

func _build_ui() -> void:
	_root_panel = Panel.new()
	_root_panel.name = "WorldMapBackground"
	_root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := StyleBoxFlat.new()
	bg.bg_color = _BG_COLOR
	_root_panel.add_theme_stylebox_override("panel", bg)
	add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_bottom = 0.5
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	_root_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "WORLD MAP"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_title_label)

	_biome_label = Label.new()
	_biome_label.text = ""
	_biome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_biome_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.6))
	_biome_label.add_theme_font_size_override("font_size", 14)
	_biome_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_biome_label)

	# Ornamented frame around the map
	_frame = Panel.new()
	_frame.custom_minimum_size = _viewport_size + Vector2(24, 24)
	var frame_sb := StyleBoxFlat.new()
	frame_sb.bg_color = _INNER_FRAME_COLOR
	frame_sb.border_color = _FRAME_COLOR
	frame_sb.border_width_top = 6
	frame_sb.border_width_bottom = 6
	frame_sb.border_width_left = 6
	frame_sb.border_width_right = 6
	frame_sb.corner_radius_top_left = 6
	frame_sb.corner_radius_top_right = 6
	frame_sb.corner_radius_bottom_left = 6
	frame_sb.corner_radius_bottom_right = 6
	_frame.add_theme_stylebox_override("panel", frame_sb)
	_frame.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(_frame)

	_viewport = Control.new()
	_viewport.name = "MapViewport"
	_viewport.custom_minimum_size = _viewport_size
	_viewport.size = _viewport_size
	_viewport.position = Vector2(12, 12)
	_viewport.clip_contents = true
	_viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport.gui_input.connect(_on_viewport_gui_input)
	_frame.add_child(_viewport)

	_precompute_image = Image.create(BASE_TEX_RES, BASE_TEX_RES, false, Image.FORMAT_RGBA8)
	_precompute_image.fill(_deep_water_color())
	_precompute_tex = ImageTexture.create_from_image(_precompute_image)

	_terrain_rect = TextureRect.new()
	_terrain_rect.name = "Terrain"
	_terrain_rect.texture = _precompute_tex
	_terrain_rect.size = Vector2(BASE_TEX_RES, BASE_TEX_RES)
	_terrain_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_terrain_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_terrain_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_terrain_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_terrain_rect)

	# Use a ColorRect so the shader always runs, even before fog_mask is
	# populated. A TextureRect with no .texture refuses to draw, which would
	# bypass the fog shader entirely and leave the whole map revealed.
	_fog_rect = ColorRect.new()
	_fog_rect.name = "Fog"
	_fog_rect.size = Vector2(BASE_TEX_RES, BASE_TEX_RES)
	_fog_rect.color = Color(1, 1, 1, 1)  # replaced by shader; just needs to be opaque
	_fog_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_fog_rect)

	# Allocate the fog mask at terrain resolution *before* anything else, so
	# the shader always has a valid all-black sampler even if world generation
	# isn't ready yet. (Unset sampler2D uniforms default to white, i.e. "fully
	# explored", which would reveal the whole map.)
	_fog_image = Image.create(BASE_TEX_RES, BASE_TEX_RES, false, Image.FORMAT_R8)
	_fog_image.fill(Color(0, 0, 0, 1))
	_fog_tex = ImageTexture.create_from_image(_fog_image)

	_fog_material = ShaderMaterial.new()
	_fog_material.shader = _build_fog_shader()
	_fog_material.set_shader_parameter(&"fog_color", _FOG_COLOR)
	_fog_material.set_shader_parameter(&"reveal_all", false)
	_fog_material.set_shader_parameter(&"noise_tex", _build_fog_noise_texture())
	_fog_material.set_shader_parameter(&"fog_mask", _fog_tex)
	_fog_material.set_shader_parameter(&"time", 0.0)
	_fog_rect.material = _fog_material

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.size = _viewport_size
	_overlay.position = Vector2.ZERO
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_viewport.add_child(_overlay)

	_build_compass_labels()

	_hint_label = Label.new()
	_hint_label.text = "Scroll to zoom  |  Drag to pan  |  [M] or [Esc] Close"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", Color(0.45, 0.42, 0.35))
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_hint_label)

	_update_layout()


func _build_compass_labels() -> void:
	for text in ["N", "S", "E", "W"]:
		var lbl := Label.new()
		lbl.text = text
		lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
		lbl.add_theme_constant_override("shadow_offset_x", 1)
		lbl.add_theme_constant_override("shadow_offset_y", 1)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.z_index = 5
		_viewport.add_child(lbl)
		_compass_labels.append(lbl)
	_reposition_compass_labels()


func _reposition_compass_labels() -> void:
	if _compass_labels.size() < 4:
		return
	_compass_labels[0].position = Vector2(_viewport_size.x * 0.5 - 6.0, 6.0)               # N
	_compass_labels[1].position = Vector2(_viewport_size.x * 0.5 - 6.0, _viewport_size.y - 28.0)  # S
	_compass_labels[2].position = Vector2(_viewport_size.x - 24.0, _viewport_size.y * 0.5 - 10.0)  # E
	_compass_labels[3].position = Vector2(8.0, _viewport_size.y * 0.5 - 10.0)              # W


func _build_fog_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;

uniform sampler2D fog_mask : filter_linear, repeat_disable;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform vec3 fog_color = vec3(0.04, 0.03, 0.08);
uniform bool reveal_all = false;
uniform float time = 0.0;

void fragment() {
    float explored = texture(fog_mask, UV).r;
    if (reveal_all) {
        COLOR = vec4(0.0);
        return;
    }
    // Animated low-frequency noise so the fog looks like drifting clouds
    // rather than a flat wash, but it modulates COLOR (lightness), not
    // alpha — unexplored areas must be fully opaque so the player can't
    // just read the terrain through thin fog.
    vec2 n_uv_a = UV * 3.0 + vec2(time * 0.015, time * 0.008);
    vec2 n_uv_b = UV * 7.0 - vec2(time * 0.022, time * 0.014);
    float n = texture(noise_tex, n_uv_a).r * 0.6 + texture(noise_tex, n_uv_b).r * 0.4;
    vec3 c = fog_color * mix(0.85, 1.25, n);
    // Soft feather along the boundary of explored regions so edges don't
    // look like pixel stairsteps.
    float feather = smoothstep(0.35, 0.92, explored);
    float alpha = 1.0 - feather;
    COLOR = vec4(c, alpha);
}
"""
	return sh


func _build_fog_noise_texture() -> ImageTexture:
	var img := Image.create(_FOG_NOISE_RES, _FOG_NOISE_RES, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.04
	noise.fractal_octaves = 3
	noise.seed = 1337
	for y in _FOG_NOISE_RES:
		for x in _FOG_NOISE_RES:
			var v := (noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return ImageTexture.create_from_image(img)


# ───────────────────────── Precompute (world overview) ─────────────────────────

func _kickoff_precompute_when_ready() -> void:
	if _precompute_started or not _wg:
		return
	_precompute_started = true
	_precompute_row = 0
	_precompute_done = false
	# Defer by one frame so _wg has a chance to finish its _ready.
	call_deferred(&"_precompute_defer_step")


func _precompute_defer_step() -> void:
	# Invoked each frame via _process until done.
	pass


func _precompute_tick() -> void:
	if _precompute_done or not _wg:
		return

	var world_radius: float = _wg.world_radius
	var meters_per_px := (world_radius * 2.0) / float(BASE_TEX_RES)
	var zone_size: float = _wg.ZONE_SIZE
	var water_color := _deep_water_color()

	var t0 := Time.get_ticks_usec()
	while _precompute_row < BASE_TEX_RES:
		for px in range(BASE_TEX_RES):
			var world_x := (float(px) - 0.5 * BASE_TEX_RES) * meters_per_px
			var world_z := (float(_precompute_row) - 0.5 * BASE_TEX_RES) * meters_per_px
			var dist := Vector2(world_x, world_z).length()
			if dist > world_radius:
				_precompute_image.set_pixel(px, _precompute_row, water_color)
				continue
			var h: float = _wg._get_base_height(world_x, world_z)
			if h < _wg.WATER_LEVEL:
				_precompute_image.set_pixel(px, _precompute_row, water_color)
				continue
			var zone := Vector2i(floori(world_x / zone_size), floori(world_z / zone_size))
			var biome: StringName = _wg._determine_biome(zone)
			var mtn_b: float = _wg._mountain_breadth(world_x, world_z)
			var map_h := h
			if mtn_b > 0.15:
				map_h = maxf(map_h, 12.0 + mtn_b * 25.0)
			var col := _biome_map_color(biome, &"none", map_h)
			var bright := clampf(lerpf(0.7, 1.25, (h + 5.0) / 30.0), 0.0, 1.0)
			_precompute_image.set_pixel(px, _precompute_row,
				Color(clampf(col.r * bright, 0.0, 1.0),
					clampf(col.g * bright, 0.0, 1.0),
					clampf(col.b * bright, 0.0, 1.0),
					1.0))
		_precompute_row += 1
		if Time.get_ticks_usec() - t0 > PRECOMPUTE_BUDGET_US:
			break

	_precompute_tex.update(_precompute_image)
	if _precompute_row >= BASE_TEX_RES:
		_precompute_done = true
		print("[WORLD MAP] Precompute complete (%dx%d)" % [BASE_TEX_RES, BASE_TEX_RES])


# ───────────────────────── Fog of war ──────────────────────────────────────────

func _seed_fog_from_explored() -> void:
	if not _wg:
		return
	# The mask image is already allocated in _build_ui() at BASE_TEX_RES, black.
	# Reset to fully unexplored and mark each known zone.
	if _fog_image == null:
		_fog_image = Image.create(BASE_TEX_RES, BASE_TEX_RES, false, Image.FORMAT_R8)
	_fog_image.fill(Color(0, 0, 0, 1))
	for key in _wg._explored_zones.keys():
		_mark_fog_zone(key as Vector2i)
	if _fog_tex == null:
		_fog_tex = ImageTexture.create_from_image(_fog_image)
	else:
		_fog_tex.update(_fog_image)
	_fog_material.set_shader_parameter(&"fog_mask", _fog_tex)
	_fog_seeded = true
	_fog_dirty = false


## Fill the block of pixels covering the given world zone.
func _mark_fog_zone(zone: Vector2i) -> void:
	if _fog_image == null or _wg == null:
		return
	var world_radius: float = _wg.world_radius
	var zone_size: float = _wg.ZONE_SIZE
	var meters_per_px: float = (world_radius * 2.0) / float(BASE_TEX_RES)
	if meters_per_px <= 0.0:
		return
	var wx0: float = float(zone.x) * zone_size
	var wz0: float = float(zone.y) * zone_size
	var wx1: float = wx0 + zone_size
	var wz1: float = wz0 + zone_size
	var px0: int = int(floor((wx0 + world_radius) / meters_per_px))
	var py0: int = int(floor((wz0 + world_radius) / meters_per_px))
	var px1: int = int(floor((wx1 + world_radius) / meters_per_px))
	var py1: int = int(floor((wz1 + world_radius) / meters_per_px))
	px0 = clampi(px0, 0, BASE_TEX_RES - 1)
	py0 = clampi(py0, 0, BASE_TEX_RES - 1)
	px1 = clampi(px1, 0, BASE_TEX_RES - 1)
	py1 = clampi(py1, 0, BASE_TEX_RES - 1)
	var white := Color(1, 1, 1, 1)
	for y in range(py0, py1 + 1):
		for x in range(px0, px1 + 1):
			_fog_image.set_pixel(x, y, white)


func _on_zone_explored(zone: Vector2i) -> void:
	if _fog_image == null:
		return
	if not _fog_seeded and _wg:
		_seed_fog_from_explored()
		return
	_mark_fog_zone(zone)
	_fog_dirty = true


func _upload_fog_if_dirty() -> void:
	if _fog_dirty and _fog_tex and _fog_image:
		_fog_tex.update(_fog_image)
		_fog_dirty = false


# ───────────────────────── Coordinate helpers ──────────────────────────────────

## Convert a world position to a pixel inside the viewport.
func _world_to_viewport(world_pos: Vector3) -> Vector2:
	var tex := _world_to_texture(Vector2(world_pos.x, world_pos.z))
	return _texture_to_viewport(tex)


func _world_to_texture(world_xz: Vector2) -> Vector2:
	if not _wg:
		return Vector2(BASE_TEX_RES * 0.5, BASE_TEX_RES * 0.5)
	var world_radius: float = _wg.world_radius
	var meters_per_px := (world_radius * 2.0) / float(BASE_TEX_RES)
	return Vector2(
		world_xz.x / meters_per_px + BASE_TEX_RES * 0.5,
		world_xz.y / meters_per_px + BASE_TEX_RES * 0.5)


func _texture_to_viewport(tex: Vector2) -> Vector2:
	var scale := _display_scale() * _zoom
	return (tex - _pan_tex) * scale + _viewport_size * 0.5


func _display_scale() -> float:
	return _viewport_size.x / float(BASE_TEX_RES)


func _center_on_player() -> void:
	if _player == null:
		return
	if _wg == null:
		return
	var pp := _wg.get_world_position(_player)
	_pan_tex = _world_to_texture(Vector2(pp.x, pp.z))
	_clamp_pan()
	_update_layout()


func _clamp_pan() -> void:
	var scale := _display_scale() * _zoom
	if scale <= 0.0:
		return
	# pan_tex is the texture pixel shown at viewport center. We want the texture
	# to fully cover the viewport, otherwise user sees empty panel behind.
	var half_vp_tex := (_viewport_size * 0.5) / scale
	var min_pan := half_vp_tex
	var max_pan := Vector2(BASE_TEX_RES, BASE_TEX_RES) - half_vp_tex
	if min_pan.x > max_pan.x:
		_pan_tex.x = BASE_TEX_RES * 0.5
	else:
		_pan_tex.x = clampf(_pan_tex.x, min_pan.x, max_pan.x)
	if min_pan.y > max_pan.y:
		_pan_tex.y = BASE_TEX_RES * 0.5
	else:
		_pan_tex.y = clampf(_pan_tex.y, min_pan.y, max_pan.y)


func _update_layout() -> void:
	if _terrain_rect == null:
		return
	var scale := _display_scale() * _zoom
	var origin := _viewport_size * 0.5 - _pan_tex * scale
	_terrain_rect.position = origin
	_terrain_rect.scale = Vector2(scale, scale)
	_fog_rect.position = origin
	_fog_rect.scale = Vector2(scale, scale)
	_queue_overlay_redraw()


func _queue_overlay_redraw() -> void:
	if _overlay:
		_overlay.queue_redraw()


# ───────────────────────── Per-frame process ───────────────────────────────────

func _process(delta: float) -> void:
	# If we were set up before the WorldGenerator existed, keep trying to
	# bind until it appears. Without this the fog mask never gets seeded
	# from real world data, and the shader's default white sampler reveals
	# the entire map.
	if _wg == null or not _fog_seeded:
		_bind_world_generator(null)

	if not _precompute_done:
		_precompute_tick()

	if not _is_open:
		return

	# Smooth zoom lerp toward target
	if not is_equal_approx(_zoom, _zoom_target):
		_zoom = lerpf(_zoom, _zoom_target, clampf(delta * ZOOM_LERP_SPEED, 0.0, 1.0))
		if absf(_zoom - _zoom_target) < 0.005:
			_zoom = _zoom_target
		_clamp_pan()
		_update_layout()

	# Keep centered on player when not panning (and when zoomed in)
	if not _is_panning and _zoom <= 1.0 + 0.01:
		_center_on_player()
	elif not _is_panning:
		# Follow the player at higher zooms too, but only if the user hasn't
		# actively panned since the map was opened. Simple heuristic: do nothing
		# here — the user can re-centre by closing/reopening.
		pass

	_fog_time += delta
	if _fog_material:
		_fog_material.set_shader_parameter(&"time", _fog_time)
	_upload_fog_if_dirty()

	if _player:
		set_reveal_all(_player_has_god_axe())

	if _biome_label and _wg and _player:
		var pp := _wg.get_world_position(_player)
		var display := _biome_display_name(_wg.get_biome_at(pp))
		var micro := _wg.get_microbiome_at(pp)
		if micro != &"none":
			display += " - " + _microbiome_display_name(micro)
		_biome_label.text = display

	_queue_overlay_redraw()


# ───────────────────────── Input / zoom / pan ──────────────────────────────────

func _on_viewport_gui_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom_step(+ZOOM_STEP, mb.position)
			_viewport.accept_event()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom_step(-ZOOM_STEP, mb.position)
			_viewport.accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_is_panning = mb.pressed
			_pan_last_mouse = mb.position
			_viewport.accept_event()
			return
	if event is InputEventMouseMotion and _is_panning:
		var mm := event as InputEventMouseMotion
		var delta := mm.position - _pan_last_mouse
		_pan_last_mouse = mm.position
		var scale := _display_scale() * _zoom
		if scale > 0.0:
			_pan_tex -= delta / scale
			_clamp_pan()
			_update_layout()
		_viewport.accept_event()


func _apply_zoom_step(dz: float, _anchor_vp: Vector2) -> void:
	_zoom_target = clampf(_zoom_target + dz, ZOOM_MIN, ZOOM_MAX)


# ───────────────────────── Overlay drawing ─────────────────────────────────────

func _draw_overlay() -> void:
	if not _wg or not _player or not _overlay:
		return

	# Marrow quest ring
	if _player.has_method("get") and _player.get(&"_quest_bones_accepted") == true and _player.get(&"_quest_bones_completed") != true:
		_draw_marrow_ring()

	# Structure dots (villages are excluded; tavern handled separately if named)
	var tree := get_tree()
	if tree:
		for node in tree.get_nodes_in_group(&"structures"):
			var n3d := node as Node3D
			if not n3d:
				continue
			if n3d.is_in_group(&"village"):
				continue
			if n3d.name == "Tavern":
				continue
			var wp := _wg.get_world_position(n3d)
			if not _zone_explored(wp):
				continue
			var view_pos := _world_to_viewport(wp)
			_draw_map_dot(view_pos, Color(0.9, 0.75, 0.3), 4.0)

		# Cave entrances
		for node in tree.get_nodes_in_group(&"cave_entrances"):
			var n3d := node as Node3D
			if not n3d:
				continue
			var wp := _wg.get_world_position(n3d)
			if not _zone_explored(wp):
				continue
			var view_pos := _world_to_viewport(wp)
			_draw_map_dot(view_pos, Color(0.5, 0.35, 0.2), 4.0)

	# Signposts ("!" markers)
	if _wg.has_method("get_signpost_positions"):
		var sp_positions: Array = _wg.get_signpost_positions()
		for sp_world in sp_positions:
			var sp_vec := sp_world as Vector3
			if not _zone_explored(sp_vec):
				continue
			var view_pos := _world_to_viewport(_wg.world_to_scene_pos(sp_vec))
			_draw_map_exclamation(view_pos, Color(1.0, 0.9, 0.3))

	# Named markers (quests, etc.)
	for marker in _markers:
		var wpos: Vector3 = marker.get("pos", Vector3.ZERO) as Vector3
		var col: Color = marker.get("color", Color.GOLD) as Color
		var scene_pos := _wg.world_to_scene_pos(wpos)
		var view_pos := _world_to_viewport(scene_pos)
		_draw_map_dot(view_pos, col, 5.0)
		# Soft ring
		_overlay.draw_arc(view_pos, 8.0, 0.0, TAU, 24, Color(col.r, col.g, col.b, 0.65), 2.0, true)
		# Label
		var text := str(marker.get("label", ""))
		if text != "":
			var font := _overlay.get_theme_default_font()
			var fs := 13
			_overlay.draw_string(font, view_pos + Vector2(10, -8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(0, 0, 0, 0.85))
			_overlay.draw_string(font, view_pos + Vector2(9, -9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(1.0, 0.9, 0.5))

	# Player arrow (camera yaw)
	_draw_player_arrow()


func _draw_map_dot(view_pos: Vector2, col: Color, radius: float) -> void:
	if not _point_in_viewport(view_pos, radius):
		return
	_overlay.draw_circle(view_pos, radius, Color(0.0, 0.0, 0.0, 0.9))
	_overlay.draw_circle(view_pos, radius - 1.2, col)


func _draw_map_exclamation(view_pos: Vector2, col: Color) -> void:
	if not _point_in_viewport(view_pos, 10.0):
		return
	var outline := Color(0.15, 0.10, 0.0, 0.95)
	var stem_rect := Rect2(view_pos + Vector2(-1.5, -8.0), Vector2(3.0, 8.0))
	_overlay.draw_rect(stem_rect.grow(1.0), outline, true)
	_overlay.draw_rect(stem_rect, col, true)
	var dot_rect := Rect2(view_pos + Vector2(-1.5, 3.0), Vector2(3.0, 3.0))
	_overlay.draw_rect(dot_rect.grow(1.0), outline, true)
	_overlay.draw_rect(dot_rect, col, true)


func _draw_marrow_ring() -> void:
	if not _wg.has_method("get_marrow_positions"):
		return
	var positions: Array = _wg.get_marrow_positions()
	if positions.is_empty():
		return
	var center := Vector3.ZERO
	for p in positions:
		center += (p as Vector3)
	center /= float(positions.size())
	var max_dist := 0.0
	for p in positions:
		var pv := p as Vector3
		var d := Vector2(pv.x - center.x, pv.z - center.z).length()
		if d > max_dist:
			max_dist = d
	var world_radius := max_dist + 30.0
	var view_center := _world_to_viewport(center)
	var meters_per_tex_px := (_wg.world_radius * 2.0) / float(BASE_TEX_RES)
	var scale := _display_scale() * _zoom
	var px_radius := (world_radius / meters_per_tex_px) * scale
	_overlay.draw_arc(view_center, px_radius, 0.0, TAU, 64, Color(0.85, 0.55, 0.15, 0.9), 2.0, true)


func _draw_player_arrow() -> void:
	var pp := _wg.get_world_position(_player)
	var view_pos := _world_to_viewport(pp)
	if not _point_in_viewport(view_pos, 32.0):
		return
	var size := Vector2(36, 36)
	var angle := 0.0
	if _camera_ref and is_instance_valid(_camera_ref):
		var fwd := -_camera_ref.global_transform.basis.z
		angle = atan2(fwd.x, -fwd.z)
	if _arrow_texture:
		var draw_transform := Transform2D(angle, view_pos)
		_overlay.draw_set_transform_matrix(draw_transform)
		_overlay.draw_texture_rect(_arrow_texture, Rect2(-size * 0.5, size), false)
		_overlay.draw_set_transform_matrix(Transform2D.IDENTITY)


func _point_in_viewport(p: Vector2, radius: float) -> bool:
	return p.x >= -radius and p.y >= -radius and p.x <= _viewport_size.x + radius and p.y <= _viewport_size.y + radius


func _zone_explored(world_pos: Vector3) -> bool:
	if _reveal_all:
		return true
	if _wg == null:
		return false
	var zone := _wg.world_to_zone(world_pos)
	return _wg._explored_zones.has(zone)


# ───────────────────────── Colors / biomes (ported) ────────────────────────────

func _deep_water_color() -> Color:
	return Color(0.12, 0.28, 0.52)


func _player_has_god_axe() -> bool:
	if _player == null:
		return false
	var equipped: Variant = _player.get(&"equipped_weapon")
	if equipped != null:
		var parsed := ItemDatabase.parse_star_id(equipped)
		if parsed.get("base_id", &"") == &"god_axe":
			return true
	var inv_wpn := Inventory.get_equipped("weapon")
	if inv_wpn != null and String(inv_wpn) != "":
		var inv_parsed := ItemDatabase.parse_star_id(inv_wpn)
		if inv_parsed.get("base_id", &"") == &"god_axe":
			return true
	return false


func _biome_map_color(biome: StringName, micro: StringName, height: float) -> Color:
	if height > 10.0:
		var grass_col := Color(0.45, 0.52, 0.32)
		var stone_col := Color(0.52, 0.50, 0.45)
		var snow_col  := Color(0.92, 0.92, 0.95)
		var rock_t := clampf((height - 10.0) / 20.0, 0.0, 1.0)
		var snow_t := clampf((height - 28.0) / 20.0, 0.0, 1.0)
		var col := grass_col.lerp(stone_col, rock_t)
		return col.lerp(snow_col, snow_t)
	if biome == _BIOME_HEARTHLANDS and micro != &"none":
		match micro:
			&"meadow":        return Color(0.42, 0.62, 0.28)
			&"forest":        return Color(0.2, 0.4, 0.15)
			&"birch_forest":  return Color(0.35, 0.55, 0.22)
			&"hills":         return Color(0.45, 0.52, 0.32)
			&"riverside":     return Color(0.32, 0.52, 0.35)
	if biome == _BIOME_OCEAN:
		return Color(0.1, 0.2, 0.4)
	return Color(0.35, 0.55, 0.25)


func _biome_display_name(biome: StringName) -> String:
	if biome == _BIOME_OCEAN:
		return "Ocean"
	return "Hearthlands"


func _microbiome_display_name(micro: StringName) -> String:
	match micro:
		&"meadow":        return "Meadow"
		&"forest":        return "Forest"
		&"birch_forest":  return "Birch Forest"
		&"hills":         return "Hills"
		&"riverside":     return "Riverside"
		_:                return ""


# ───────────────────────── Player arrow texture (ported) ───────────────────────

func _generate_arrow_texture(sz: int) -> ImageTexture:
	# Classic map-arrow chevron pointing up (-Y). Four corners: tip, right
	# wing, rear notch, left wing. Filled red with a soft black outline.
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var fsz := float(sz)
	var tip   := Vector2(fsz * 0.5,  fsz * 0.08)
	var right := Vector2(fsz * 0.92, fsz * 0.92)
	var notch := Vector2(fsz * 0.5,  fsz * 0.70)
	var left  := Vector2(fsz * 0.08, fsz * 0.92)
	var fill_col := Color(0.95, 0.22, 0.18, 1.0)
	var fill_dark := Color(0.55, 0.10, 0.08, 1.0)
	var border := Color(0.05, 0.02, 0.02, 1.0)
	for y in sz:
		for x in sz:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var d_right := _sd_triangle(p, tip, right, notch)
			var d_left  := _sd_triangle(p, tip, notch, left)
			var d := minf(d_right, d_left)  # negative inside, positive outside
			if d > 1.2:
				continue
			var grad_t := clampf((p.y - tip.y) / maxf(notch.y - tip.y, 0.01), 0.0, 1.0)
			var fill := fill_col.lerp(fill_dark, grad_t * 0.6)
			if d > -1.0:
				# Antialiased border band
				var b_t := clampf((d + 1.0) / 2.2, 0.0, 1.0)
				var col := fill.lerp(border, b_t)
				col.a = clampf(1.2 - d, 0.0, 1.0)
				img.set_pixel(x, y, col)
			else:
				img.set_pixel(x, y, fill)
	return ImageTexture.create_from_image(img)


## Signed distance from point p to triangle (a, b, c). Negative inside, positive outside.
func _sd_triangle(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> float:
	var d_ab := _sd_segment(p, a, b)
	var d_bc := _sd_segment(p, b, c)
	var d_ca := _sd_segment(p, c, a)
	var d := minf(d_ab, minf(d_bc, d_ca))
	var inside := _sign_tri(p, a, b, c) >= 0.0
	return -d if inside else d


func _sd_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ap := p - a
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * t).length()


## Returns +1 if p is inside triangle abc (CCW-ish), -1 if outside.
func _sign_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> float:
	var d1 := (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var d2 := (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var d3 := (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	var has_neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
	var has_pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
	return -1.0 if (has_neg and has_pos) else 1.0
