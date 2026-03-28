extends Node3D

@export var force_nearest_filter := false

var _env: Environment
var _tween: Tween
const BIOME_TRANSITION_TIME := 3.0

var _biome_cache: Dictionary = {}

func _ready() -> void:
	_force_nearest_recursive(self)
	child_entered_tree.connect(_on_child_entered)

	var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we:
		_env = we.environment

	_cache_biomes()

	var wg := get_node_or_null("WorldGenerator")
	if wg and wg.has_signal("biome_at_player_changed"):
		wg.biome_at_player_changed.connect(_on_biome_changed)

func _cache_biomes() -> void:
	var dir := DirAccess.open("res://resources/biomes/")
	if not dir:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".tres"):
			var res := load("res://resources/biomes/" + fname)
			if res is BiomeData:
				_biome_cache[res.id] = res
		fname = dir.get_next()

func _on_biome_changed(biome_id: StringName) -> void:
	var data: BiomeData = _biome_cache.get(biome_id)
	if not data:
		return
	var dnc := get_node_or_null("DayNightCycle")
	if dnc:
		if _tween and _tween.is_valid():
			_tween.kill()
		_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		_tween.tween_property(dnc, "_base_fog_density", data.fog_density, BIOME_TRANSITION_TIME)
		_tween.tween_property(dnc, "_base_fog_color", data.fog_color, BIOME_TRANSITION_TIME)
		_tween.tween_property(dnc, "_base_ambient_color", data.ambient_color, BIOME_TRANSITION_TIME)
	elif _env:
		if _tween and _tween.is_valid():
			_tween.kill()
		_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		_tween.tween_property(_env, "fog_light_color", data.fog_color, BIOME_TRANSITION_TIME)
		_tween.tween_property(_env, "fog_density", data.fog_density, BIOME_TRANSITION_TIME)
		_tween.tween_property(_env, "ambient_light_color", data.ambient_color, BIOME_TRANSITION_TIME)

func _on_child_entered(node: Node) -> void:
	if force_nearest_filter:
		_force_nearest_recursive.call_deferred(node)

func _force_nearest_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		_force_nearest_mesh(node)
	if node is GeometryInstance3D:
		var mat := (node as GeometryInstance3D).material_override
		if mat is StandardMaterial3D:
			_force_nearest_standard(mat)
	for child in node.get_children():
		_force_nearest_recursive(child)

func _force_nearest_mesh(mi: MeshInstance3D) -> void:
	var mesh := mi.mesh
	if not mesh:
		return
	for i in mesh.get_surface_count():
		var mat := mi.get_active_material(i)
		if mat is StandardMaterial3D:
			_force_nearest_standard(mat)

func _force_nearest_standard(mat: StandardMaterial3D) -> void:
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
