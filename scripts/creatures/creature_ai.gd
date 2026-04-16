class_name CreatureAI
extends CharacterBody3D

const _DEBUG_LOG := false

## Basic enemy creature with wander / aggro / chase / attack states.
## Visual is a Sprite3D billboard added by ZonePopulator.

const _DamageNumber := preload("res://scripts/ui/damage_number.gd")
const _LootDrop := preload("res://scripts/items/loot_drop.gd")

enum State { IDLE, WANDER, CHASE, ATTACK, DEAD, PERCH, DIVE_FISH, CARRY_FISH, EAT_FISH }

@export var max_health: float = 50.0
@export var attack_damage: float = 10.0
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 2.0
@export var aggro_range: float = 12.0
@export var leash_range: float = 45.0
@export var move_speed: float = 3.0
@export var display_name: String = "Creature"
@export var creature_type: String = "boar"
@export var is_flying: bool = false
@export var is_passive: bool = false
var fly_height: float = 22.0
var star_level: int = 0
var creature_kind: StringName = &""
var loot_table: Array = []
var rare_loot_table: Array = []
var sprite_textures: Dictionary = {}
var walk_frames: Dictionary = {}
var run_frames: Dictionary = {}
var attack_frames: Dictionary = {}

var current_health: float
var _current_dir := "south"
var _state: State = State.IDLE

# Status effects (from player affixes)
var _slow_timer: float = 0.0
var _slow_factor: float = 1.0
var _stun_timer: float = 0.0
var _poison_timer: float = 0.0
var _poison_dps: float = 0.0
var _poison_source: Node3D = null
var _fire_exposure: float = 0.0  # seconds standing in campfire
var _fire_damage_timer: float = 0.0  # cooldown between fire damage ticks
var _campfire_check_timer: float = 0.0
var _campfire_in_fire: bool = false
var _disorient_timer: float = 0.0
var _armor_shred_timer: float = 0.0
var _armor_shred_factor: float = 0.0
var _target: Node3D
var _cached_player: Node3D
var _player_cache_timer: float = 0.0
var _cached_world_gen: Node
var _spawn_position: Vector3
var _wander_direction: Vector3 = Vector3.ZERO
var _wander_timer: float = 0.0
var _aggro_check_cd: float = 0.0
var _attack_timer: float = 0.0
var _attack_hit_done: bool = false
var _idle_timer: float = 0.0
var _hit_flash_timer: float = 0.0
var _spawn_recorded := false
var _hp_bar_visible_timer: float = 0.0
var _hud_targeted: bool = false
var _hp_bar_fill: Sprite3D
var _hp_bar_bg: Sprite3D
var _hp_bar_full_width: float = 0.35
var _nameplate_label: Label3D
var _stars_label: Label3D
var _nameplate_bg: Sprite3D
var _accent_bar: Sprite3D
var _floating_ui: Node3D
static var _shared_panel_tex: ImageTexture
static var _shared_accent_tex: ImageTexture
const _BANNER_W := 128
const _BANNER_H := 32
var _anim_frame_idx: int = 0
var _anim_frame_timer: float = 0.0
var _roar_cooldown: float = 0.0
var _holding_at_target: bool = false
var _combat_timer: float = 0.0
var _evading: bool = false
var _perch_timer: float = 0.0
var _perch_target: Node3D = null
var _perch_settled: bool = false
var _dying_fall: bool = false
var _death_visual_started: bool = false
var idle_frames: Dictionary = {}
var _sync_target_position: Vector3 = Vector3.ZERO
var _sync_initialized: bool = false

var _fish_target: Node3D = null
var _carried_fish_sprite: Sprite3D = null
var _fish_scan_cooldown: float = 0.0
var _eat_timer: float = 0.0
const _WALK_FRAME_DURATION := 0.14
const _RUN_FRAME_DURATION := 0.1
const _ATTACK_FRAME_DURATION := 0.08

var _walk_bob_phase: float = 0.0
var _sprite_base_y: float = -1.0
const _WALK_BOB_AMPLITUDE := 0.055
const _WALK_BOB_SPEED := 13.0
const _WALK_LEAN_MAX := 0.09

# 3D model support (GLTF)
var use_3d_model: bool = false
var _model_node: Node3D = null
var _model_anim_player: AnimationPlayer = null
var arrow_hit_radius: float = -1.0
var arrow_hit_height: float = -1.0
var arrow_hit_y_offset: float = -1.0
var _model_current_anim := ""
var _model_yaw_offset: float = 0.0

const GRAVITY := 9.8


func _set_sprite_texture(sprite: Sprite3D, tex: Texture2D) -> void:
	if not tex:
		return
	sprite.texture = tex
	var mat := sprite.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("sprite_texture", tex)


var _anim_map: Dictionary = {}

func _build_anim_map(anim_list: PackedStringArray) -> void:
	# Map logical names (idle, walk, run, attack) to actual animation names.
	# Handles Blockbench ("animation.idle"), Meshy AI ("Walking"), Tripo NlaTracks, etc.
	var keywords := {
		"idle": ["idle", "Idle", "standing", "Standing", "rest", "Rest"],
		"walk": ["walk", "Walk", "Walking", "walking"],
		"run": ["run", "Run", "Running", "running", "sprint", "Sprint"],
		"attack": ["attack", "Attack", "Attacking", "attacking", "hit", "Hit", "slash", "Slash"],
		"death": ["death", "Death", "die", "Die", "dying", "Dying", "dead", "Dead"],
		"fly": ["fly", "Fly", "Flying", "flying", "glide", "Glide"],
	}

	# Step 1: Try keyword matching
	for logical_name in keywords:
		for anim_name in anim_list:
			var lower := anim_name.to_lower()
			for kw in keywords[logical_name]:
				if lower.contains(kw.to_lower()):
					_anim_map[logical_name] = anim_name
					break
			if _anim_map.has(logical_name):
				break
		if not _anim_map.has(logical_name):
			var full: String = "animation." + str(logical_name)
			if anim_list.has(full):
				_anim_map[logical_name] = full

	# Step 2: If keyword matching found nothing, handle NlaTrack-style names (Tripo).
	# Use per-creature mappings since Tripo export order varies per model.
	if _anim_map.is_empty() and anim_list.size() >= 2:
		var sorted_anims: Array[String] = []
		for a in anim_list:
			if "NlaTrack" in a or a.begins_with("Armature|"):
				sorted_anims.append(a)
		sorted_anims.sort()
		var is_nla := sorted_anims.size() >= 2
		if is_nla:

			# Per-creature logical order (index -> action)
			var logical_order: Array[String]
			if creature_kind == &"goblin":
				logical_order = ["walk", "run", "death", "attack", "idle"]
			elif creature_kind in [&"cyclops", &"orc_brute"]:
				logical_order = ["walk", "attack", "run", "attack", "attack", "death"]
			elif creature_kind == &"minotaur":
				logical_order = ["walk", "attack", "run", "attack", "death", "idle"]
			else:
				logical_order = ["idle", "walk", "run", "attack", "death"]

			for i in mini(sorted_anims.size(), logical_order.size()):
				var action: String = logical_order[i]
				if not _anim_map.has(action):
					_anim_map[action] = sorted_anims[i]

	# Ensure "walk" exists — fall back to run if no dedicated walk track
	if not _anim_map.has("walk") and _anim_map.has("run"):
		_anim_map["walk"] = _anim_map["run"]

	# Ensure "idle" exists — fall back to walk or run if no dedicated idle track
	if not _anim_map.has("idle"):
		if _anim_map.has("walk"):
			_anim_map["idle"] = _anim_map["walk"]
		elif _anim_map.has("run"):
			_anim_map["idle"] = _anim_map["run"]

	# Step 3: Fallback — single animation used for everything
	if _anim_map.is_empty() and anim_list.size() > 0:
		var first_anim: String = anim_list[0]
		for logical_name in keywords:
			_anim_map[logical_name] = first_anim

	if _DEBUG_LOG: print("[CREATURE] %s (kind=%s) anim_map=%s full_list=%s" % [display_name, str(creature_kind), str(_anim_map), str(anim_list)])


func _play_model_anim(anim_name: String) -> void:
	if not _model_anim_player:
		return
	if _model_current_anim == anim_name:
		return
	var resolved: String = _anim_map.get(anim_name, "") as String
	var played := ""
	if resolved != "" and _model_anim_player.has_animation(resolved):
		_model_anim_player.play(resolved)
		played = resolved
		_model_current_anim = anim_name
	elif _model_anim_player.has_animation(anim_name):
		_model_anim_player.play(anim_name)
		played = anim_name
		_model_current_anim = anim_name

	if played != "":
		if anim_name == "attack" and attack_cooldown > 0.0:
			var anim := _model_anim_player.get_animation(played)
			if anim and anim.length > 0.0:
				_model_anim_player.speed_scale = anim.length / attack_cooldown
		else:
			_model_anim_player.speed_scale = 1.0


func _strip_root_motion(anim: Animation) -> void:
	for i in range(anim.get_track_count() - 1, -1, -1):
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			anim.remove_track(i)


func _find_anim_player_recursive(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim_player_recursive(child)
		if found:
			return found
	return null


func _ready() -> void:
	current_health = max_health
	add_to_group(&"enemies")
	collision_layer = 16
	if is_flying:
		collision_mask = 0
	else:
		collision_mask = 1
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(70.0)
	floor_stop_on_slope = true
	_fly_bob_phase = randf_range(0.0, TAU)
	_campfire_check_timer = randf_range(0.0, 0.5)
	_create_floating_ui()

	# Host-authoritative creatures: only server runs AI; clients receive synced state
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_state = State.IDLE
		if use_3d_model and _model_node:
			_compute_arrow_hitbox()
			_cache_model_material_colors(_model_node)
			if _model_anim_player:
				var anim_list := _model_anim_player.get_animation_list()
				_build_anim_map(anim_list)
				var death_anim_name: String = _anim_map.get("death", "") as String
				for anim_name in anim_list:
					var anim := _model_anim_player.get_animation(anim_name)
					if anim:
						if anim_name == death_anim_name:
							anim.loop_mode = Animation.LOOP_NONE
						else:
							anim.loop_mode = Animation.LOOP_LINEAR
							_strip_root_motion(anim)
		return

	if use_3d_model and _model_node:
		_compute_arrow_hitbox()
		_cache_model_material_colors(_model_node)
		if _model_anim_player:
			var anim_list := _model_anim_player.get_animation_list()
			if _DEBUG_LOG: print("[CREATURE] %s animations: %s" % [display_name, str(anim_list)])
			_build_anim_map(anim_list)
			var death_anim_name: String = _anim_map.get("death", "") as String
			for anim_name in anim_list:
				var anim := _model_anim_player.get_animation(anim_name)
				if anim:
					if anim_name == death_anim_name:
						anim.loop_mode = Animation.LOOP_NONE
					else:
						anim.loop_mode = Animation.LOOP_LINEAR
						_strip_root_motion(anim)


## Phase 3a — reset runtime state to "freshly spawned" so this creature can
## be reused from the ZonePool without paying the physics body creation cost.
## Must only be called on the main thread when the creature is detached from
## a zone (no parent) or about to be re-parented into one. The model tree
## and nameplate stay intact — only combat state, timers, and AI state reset.
func reset_for_pool() -> void:
	current_health = max_health
	_state = State.IDLE
	velocity = Vector3.ZERO
	_target = null
	_cached_player = null
	_player_cache_timer = 0.0
	_wander_direction = Vector3.ZERO
	_wander_timer = 0.0
	_aggro_check_cd = 0.0
	_attack_timer = 0.0
	_attack_hit_done = false
	_idle_timer = 0.0
	_hit_flash_timer = 0.0
	_spawn_recorded = false
	_hp_bar_visible_timer = 0.0
	_hud_targeted = false
	_slow_timer = 0.0
	_slow_factor = 1.0
	_stun_timer = 0.0
	_poison_timer = 0.0
	_poison_dps = 0.0
	_poison_source = null
	_fire_exposure = 0.0
	_fire_damage_timer = 0.0
	_campfire_in_fire = false
	_disorient_timer = 0.0
	_armor_shred_timer = 0.0
	_armor_shred_factor = 0.0
	_anim_frame_idx = 0
	_anim_frame_timer = 0.0
	_roar_cooldown = 0.0
	_holding_at_target = false
	_combat_timer = 0.0
	_evading = false
	_perch_timer = 0.0
	_perch_target = null
	_perch_settled = false
	_dying_fall = false
	_death_visual_started = false
	_fish_target = null
	_fish_scan_cooldown = 0.0
	_eat_timer = 0.0
	_sync_initialized = false
	if _hp_bar_fill:
		_hp_bar_fill.visible = false
	if _hp_bar_bg:
		_hp_bar_bg.visible = false
	visible = true
	collision_layer = 16
	collision_mask = 0 if is_flying else 1
	process_mode = Node.PROCESS_MODE_INHERIT


func _physics_process(delta: float) -> void:
	if not _spawn_recorded:
		_spawn_recorded = true
		_spawn_position = global_position
		_recompute_ui_height()

	_player_cache_timer -= delta
	_aggro_check_cd -= delta
	_update_proximity_label()

	if _state == State.DEAD:
		# Client: when DEAD state syncs in, play death visual once
		if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
			if not _death_visual_started:
				_death_visual_started = true
				_play_death_sound()
				if _floating_ui:
					_floating_ui.visible = true
				_spawn_loot_and_play_ground_death()
			return
		if _dying_fall:
			velocity.y -= 25.0 * delta
			velocity.x = move_toward(velocity.x, 0.0, 2.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 2.0 * delta)
			move_and_slide()
			if is_on_floor():
				_dying_fall = false
				_finish_death_on_ground()
		return

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		if _sync_initialized:
			global_position = global_position.lerp(_sync_target_position, delta * 12.0)
		_update_hit_flash(delta)
		_update_sprite_direction()
		_tick_animation(delta)
		return

	# Status effect ticks
	_tick_status_effects(delta)
	if _combat_timer > 0.0:
		_combat_timer -= delta
	if _stun_timer > 0.0:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_flying:
			if is_on_floor():
				velocity.y = -0.5
			else:
				velocity.y -= GRAVITY * delta
		move_and_slide()
		return

	if is_flying and _state != State.PERCH and _state != State.DIVE_FISH and _state != State.EAT_FISH:
		_apply_flying_hover(delta)
	elif not is_flying:
		if is_on_floor():
			velocity.y = -0.5
		else:
			velocity.y -= GRAVITY * delta

	_update_hit_flash(delta)
	if _roar_cooldown > 0.0:
		_roar_cooldown -= delta

	if _fish_scan_cooldown > 0.0:
		_fish_scan_cooldown -= delta

	match _state:
		State.IDLE:
			_process_idle(delta)
		State.WANDER:
			_process_wander(delta)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK:
			_process_attack(delta)
		State.PERCH:
			_process_perch(delta)
		State.DIVE_FISH:
			_process_dive_fish(delta)
		State.CARRY_FISH:
			_process_carry_fish(delta)
		State.EAT_FISH:
			_process_eat_fish(delta)

	var _skip_sweep := not is_flying \
		and (_state == State.IDLE or _state == State.WANDER) \
		and Engine.get_physics_frames() % 2 != get_index() % 2

	if not _skip_sweep:
		var y_before := global_position.y
		move_and_slide()

		if not is_flying:
			if velocity.y > 8.0:
				velocity.y = 0.0
			_clamp_to_terrain()
			_avoid_water()
			var y_rise := global_position.y - y_before
			if y_rise > 0.4:
				global_position.y = y_before + 0.4
				velocity.y = 0.0

	_update_sprite_direction()
	_tick_animation(delta)


var _fly_bob_phase: float = 0.0

func _apply_flying_hover(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	if not space:
		return
	var from := Vector3(global_position.x, global_position.y + 20.0, global_position.z)
	var to := Vector3(global_position.x, global_position.y - 40.0, global_position.z)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid()]
	var result := space.intersect_ray(query)
	var terrain_y := 0.0
	if not result.is_empty():
		terrain_y = result["position"].y

	_fly_bob_phase += delta * 1.5
	var bob := sin(_fly_bob_phase) * 0.4
	var target_y := terrain_y + fly_height + bob
	velocity.y = (target_y - global_position.y) * 3.0


func _clamp_to_terrain() -> void:
	if global_position.y < -100.0:
		return

	if not is_instance_valid(_cached_world_gen):
		var wgs := get_tree().get_nodes_in_group(&"world_generator")
		_cached_world_gen = wgs[0] if not wgs.is_empty() else null
	if not _cached_world_gen or not _cached_world_gen.has_method(&"get_height_at_scene"):
		return

	# Raycast to find actual collision surface first
	var space := get_world_3d().direct_space_state
	if space:
		var from := Vector3(global_position.x, global_position.y + 5.0, global_position.z)
		var to := Vector3(global_position.x, global_position.y - 15.0, global_position.z)
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		query.exclude = [get_rid()]
		var result := space.intersect_ray(query)
		if not result.is_empty():
			var surface_y: float = result["position"].y
			if global_position.y < surface_y - 0.1:
				global_position.y = surface_y + 0.05
				if velocity.y < 0.0:
					velocity.y = 0.0
			return

	# Raycast missed (collision disabled) — use analytic height
	var wg: Node = _cached_world_gen
	var analytic_y: float = wg.get_height_at_scene(global_position.x, global_position.z)
	if global_position.y < analytic_y - 0.2:
		global_position.y = analytic_y + 0.1
		if velocity.y < 0.0:
			velocity.y = 0.0


var _water_avoid_cd: float = 0.0

func _avoid_water() -> void:
	if global_position.y < -100.0:
		return
	_water_avoid_cd -= get_physics_process_delta_time()
	if _water_avoid_cd > 0.0:
		return
	_water_avoid_cd = 0.15

	if not is_instance_valid(_cached_world_gen) or not _cached_world_gen.has_method(&"get_height_at_scene"):
		return
	var vel_flat := Vector2(velocity.x, velocity.z)
	if vel_flat.length_squared() < 0.1:
		return
	var look := vel_flat.normalized()
	var ahead_x := global_position.x + look.x * 2.0
	var ahead_z := global_position.z + look.y * 2.0
	var ahead_y: float = _cached_world_gen.get_height_at_scene(ahead_x, ahead_z)
	if ahead_y < 0.3:
		velocity.x = -velocity.x
		velocity.z = -velocity.z
		if _state == State.WANDER:
			_wander_direction = -_wander_direction
		elif _state == State.CHASE:
			velocity.x *= 0.3
			velocity.z *= 0.3


func _process_idle(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 10.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 10.0 * delta)

	_idle_timer -= delta
	if _idle_timer <= 0.0:
		if _try_find_fish():
			return
		_state = State.WANDER
		_pick_wander_direction()
		return

	_check_aggro()


func _process_wander(delta: float) -> void:
	if _evading:
		var to_spawn := _spawn_position - global_position
		to_spawn.y = 0.0
		var dist_to_spawn := to_spawn.length()
		if dist_to_spawn < 3.0:
			_evading = false
			_state = State.IDLE
			_idle_timer = randf_range(1.0, 3.0)
			current_health = max_health
			_update_hp_bar()
			return
		var evade_speed := _get_effective_speed() * 1.5
		_wander_direction = to_spawn.normalized()
		velocity.x = _wander_direction.x * evade_speed
		velocity.z = _wander_direction.z * evade_speed
		return

	var wander_spd := _get_effective_speed() * (0.95 if is_flying else 0.4)
	velocity.x = _wander_direction.x * wander_spd
	velocity.z = _wander_direction.z * wander_spd

	_wander_timer -= delta
	if _wander_timer <= 0.0:
		if _try_find_fish():
			return
		if is_flying and randf() < 0.4:
			var tree := _find_nearby_tree(20.0)
			if tree:
				_begin_perch(tree)
				return
		_state = State.IDLE
		_idle_timer = randf_range(2.0, 5.0) if not is_flying else randf_range(1.0, 3.0)
		return

	var wander_leash := 25.0 if is_flying else 15.0
	var dist_from_spawn := Vector2(global_position.x - _spawn_position.x, global_position.z - _spawn_position.z).length()
	if dist_from_spawn > wander_leash:
		var ret := (_spawn_position - global_position)
		ret.y = 0.0
		_wander_direction = ret.normalized()

	_check_aggro()


func _process_chase(delta: float) -> void:
	if not is_instance_valid(_target):
		_state = State.IDLE
		_idle_timer = 1.0
		_holding_at_target = false
		return

	_attack_timer -= delta

	var to_target := _target.global_position - global_position
	var flat_offset := Vector3(to_target.x, 0.0, to_target.z)
	var hdist := flat_offset.length()
	var flat_dir := flat_offset.normalized() if hdist > 0.01 else Vector3.ZERO

	if global_position.distance_to(_spawn_position) > leash_range and _combat_timer <= 0.0:
		_target = null
		_state = State.WANDER
		_holding_at_target = false
		_evading = true
		_wander_direction = (_spawn_position - global_position).normalized()
		_wander_timer = 99.0
		return

	var v_dist := absf(to_target.y)
	var v_reach := attack_range + 2.0
	var in_range := hdist <= attack_range and v_dist <= v_reach
	var resume_chase_dist := attack_range * 2.5
	if _holding_at_target and hdist <= resume_chase_dist and v_dist <= v_reach:
		in_range = true

	if in_range:
		if _attack_timer <= 0.0:
			_state = State.ATTACK
			_attack_timer = attack_cooldown
			_attack_hit_done = false
			_model_current_anim = ""
			_holding_at_target = false
		else:
			_holding_at_target = true
		var decel := 12.0 * delta
		velocity.x = move_toward(velocity.x, 0.0, decel)
		velocity.z = move_toward(velocity.z, 0.0, decel)
		return

	_holding_at_target = false
	var eff_speed := _get_effective_speed()
	velocity.x = move_toward(velocity.x, flat_dir.x * eff_speed, 10.0 * delta)
	velocity.z = move_toward(velocity.z, flat_dir.z * eff_speed, 10.0 * delta)

	if is_flying:
		velocity.y = (_target.global_position.y + 2.5 - global_position.y) * 2.0


func _process_attack(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)

	_attack_timer -= delta
	# Deal damage at the midpoint of the animation (weapon connects)
	if not _attack_hit_done and _attack_timer <= attack_cooldown * 0.5:
		_attack_hit_done = true
		_do_attack()
	# End attack state once the full animation has played
	if _attack_timer <= 0.0:
		_state = State.CHASE
		_attack_timer = 0.0


func _find_nearby_tree(radius: float) -> Node3D:
	var best: Node3D = null
	var best_dist := radius * radius
	var parent := get_parent()
	if not parent:
		return null
	for child in parent.get_children():
		if not (child is Node3D) or not child.has_meta("tree_name"):
			continue
		var node: Node3D = child as Node3D
		var d2 := Vector2(node.global_position.x - global_position.x, node.global_position.z - global_position.z).length_squared()
		if d2 < best_dist:
			best_dist = d2
			best = node
	return best


func _begin_perch(tree: Node3D) -> void:
	_state = State.PERCH
	_perch_target = tree
	_perch_timer = randf_range(5.0, 15.0)
	_perch_settled = false


func _process_perch(delta: float) -> void:
	if not is_instance_valid(_perch_target):
		_state = State.IDLE
		_idle_timer = 1.0
		_perch_target = null
		return

	_check_aggro()
	if _state != State.PERCH:
		_perch_target = null
		return

	var tree_pos := _perch_target.global_position
	var canopy := _perch_target.get_node_or_null("Canopy")
	var perch_y := tree_pos.y + 12.0
	if canopy:
		perch_y = canopy.global_position.y + 0.6

	var to_tree := Vector2(tree_pos.x - global_position.x, tree_pos.z - global_position.z)
	var hdist := to_tree.length()

	if not _perch_settled:
		if hdist > 0.5:
			var dir := to_tree.normalized()
			velocity.x = dir.x * move_speed * 0.8
			velocity.z = dir.y * move_speed * 0.8
		else:
			velocity.x = move_toward(velocity.x, 0.0, 15.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 15.0 * delta)

		velocity.y = (perch_y - global_position.y) * 3.0
		if hdist < 0.5 and absf(global_position.y - perch_y) < 0.5:
			_perch_settled = true
			velocity = Vector3.ZERO
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = (perch_y - global_position.y) * 2.0

		_perch_timer -= delta
		if _perch_timer <= 0.0:
			_perch_target = null
			_perch_settled = false
			_state = State.WANDER
			_pick_wander_direction()


# ═══════════════════════════════════════════════════════════════════════════════
#  SEAGULL FISH BEHAVIOR
# ═══════════════════════════════════════════════════════════════════════════════

func _try_find_fish() -> bool:
	if creature_type != "hawk" or display_name != "Seagull":
		return false
	if _fish_scan_cooldown > 0.0:
		return false
	_fish_scan_cooldown = 8.0
	if randf() < 0.55:
		return false
	var best: Node3D = null
	var best_dist := 900.0
	for node: Node3D in get_tree().get_nodes_in_group(&"fish"):
		if node.get_meta("claimed", false):
			continue
		var d2 := Vector2(node.global_position.x - global_position.x, node.global_position.z - global_position.z).length_squared()
		if d2 < best_dist:
			best_dist = d2
			best = node
	if best:
		_fish_target = best
		best.set_meta("claimed", true)
		_state = State.DIVE_FISH
		return true
	return false


func _process_dive_fish(_delta: float) -> void:
	if not is_instance_valid(_fish_target):
		_abort_fish()
		return

	var fish_pos := _fish_target.global_position
	var to_fish := fish_pos - global_position
	var flat_dist := Vector2(to_fish.x, to_fish.z).length()

	var target_y := fish_pos.y + 0.3
	if flat_dist > 2.0:
		target_y = lerpf(global_position.y, fish_pos.y + 1.0, 0.05)

	var flat_dir := Vector2(to_fish.x, to_fish.z).normalized()
	var dive_speed := move_speed * 1.2
	velocity.x = flat_dir.x * dive_speed
	velocity.z = flat_dir.y * dive_speed
	velocity.y = (target_y - global_position.y) * 4.0

	if flat_dist < 1.0 and absf(global_position.y - fish_pos.y) < 1.5:
		_grab_fish()


func _grab_fish() -> void:
	if is_instance_valid(_fish_target):
		_fish_target.queue_free()
	_fish_target = null

	_carried_fish_sprite = Sprite3D.new()
	_carried_fish_sprite.name = "CarriedFish"
	var fish_tex: Texture2D = null
	var fish_tex_dict: Dictionary = ZonePopulator._tex_fish
	if fish_tex_dict.has("south"):
		fish_tex = fish_tex_dict["south"] as Texture2D
	if fish_tex:
		_carried_fish_sprite.texture = fish_tex
	else:
		var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.3, 0.5, 0.7))
		_carried_fish_sprite.texture = ImageTexture.create_from_image(img)
	_carried_fish_sprite.pixel_size = 0.02
	_carried_fish_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_carried_fish_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_carried_fish_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	_carried_fish_sprite.transparent = true
	_carried_fish_sprite.shaded = true
	_carried_fish_sprite.double_sided = true
	_carried_fish_sprite.position.y = -0.2
	add_child(_carried_fish_sprite)
	_carried_fish_sprite.add_to_group(&"carried_fish")
	_carried_fish_sprite.set_meta("owner_creature", self)

	_state = State.CARRY_FISH
	fly_height = 22.0


func _process_carry_fish(delta: float) -> void:
	_apply_flying_hover(delta)

	var tree := _find_nearby_tree(30.0)
	if tree:
		_perch_target = tree
		_state = State.EAT_FISH
		_perch_settled = false
		_eat_timer = randf_range(4.0, 8.0)
		return

	var to_spawn := _spawn_position - global_position
	to_spawn.y = 0.0
	var dir := to_spawn.normalized() if to_spawn.length_squared() > 1.0 else _wander_direction
	velocity.x = dir.x * move_speed * 0.8
	velocity.z = dir.z * move_speed * 0.8


func _process_eat_fish(delta: float) -> void:
	if not is_instance_valid(_perch_target):
		_state = State.CARRY_FISH
		return

	var tree_pos := _perch_target.global_position
	var canopy := _perch_target.get_node_or_null("Canopy")
	var perch_y := tree_pos.y + 12.0
	if canopy:
		perch_y = canopy.global_position.y + 0.6

	var to_tree := Vector2(tree_pos.x - global_position.x, tree_pos.z - global_position.z)
	var hdist := to_tree.length()

	if not _perch_settled:
		if hdist > 0.5:
			var dir := to_tree.normalized()
			velocity.x = dir.x * move_speed * 0.8
			velocity.z = dir.y * move_speed * 0.8
		else:
			velocity.x = move_toward(velocity.x, 0.0, 15.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 15.0 * delta)

		velocity.y = (perch_y - global_position.y) * 3.0
		if hdist < 0.5 and absf(global_position.y - perch_y) < 0.5:
			_perch_settled = true
			velocity = Vector3.ZERO
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = (perch_y - global_position.y) * 2.0

		_eat_timer -= delta
		if _eat_timer <= 0.0:
			_finish_eating()


func _finish_eating() -> void:
	if _carried_fish_sprite:
		_carried_fish_sprite.remove_from_group(&"carried_fish")
		_carried_fish_sprite.queue_free()
		_carried_fish_sprite = null
	_perch_target = null
	_perch_settled = false
	_state = State.WANDER
	_pick_wander_direction()


func drop_carried_fish() -> void:
	if not _carried_fish_sprite:
		return
	var drop_pos := _carried_fish_sprite.global_position
	_carried_fish_sprite.remove_from_group(&"carried_fish")
	_carried_fish_sprite.queue_free()
	_carried_fish_sprite = null

	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var fish_rng := RandomNumberGenerator.new()
	fish_rng.randomize()
	var stars := ItemDatabase.roll_star_level(fish_rng)
	if NetworkManager.is_connected_to_game() and NetworkManager.is_server():
		for n in get_tree().get_nodes_in_group(&"world_state_sync"):
			var wss := n as WorldStateSync
			if wss:
				wss.spawn_loot_synced(drop_pos, &"raw_fish", 1, stars)
				break
	else:
		var drop := _LootDrop.new()
		drop.item_id = &"raw_fish"
		drop.star_level = stars
		drop.amount = 1
		get_tree().current_scene.add_child(drop)
		drop.global_position = drop_pos

	if _state == State.CARRY_FISH or _state == State.EAT_FISH:
		_perch_target = null
		_perch_settled = false
		_state = State.WANDER
		_pick_wander_direction()


func _abort_fish() -> void:
	if is_instance_valid(_fish_target):
		_fish_target.set_meta("claimed", false)
	_fish_target = null
	_state = State.WANDER
	_pick_wander_direction()


func _do_attack() -> void:
	if not is_instance_valid(_target):
		return
	var offset := _target.global_position - global_position
	var h_dist := Vector2(offset.x, offset.z).length()
	if h_dist > attack_range * 1.5:
		return
	if absf(offset.y) > attack_range + 2.0:
		return
	_combat_timer = 8.0
	if _target.has_method("take_damage"):
		var eff_dmg := attack_damage
		if _disorient_timer > 0.0:
			eff_dmg *= 0.8
		var target_peer := _target.get_multiplayer_authority()
		if not multiplayer.has_multiplayer_peer() or target_peer == multiplayer.get_unique_id():
			_target.take_damage(eff_dmg, self)
		else:
			deal_damage_to_player.rpc_id(target_peer, target_peer, eff_dmg)


func _get_nearest_player() -> Node3D:
	var players := get_tree().get_nodes_in_group(&"player")
	var nearest: Node3D = null
	var best_dist := INF
	for node in players:
		var p := node as Node3D
		if not is_instance_valid(p):
			continue
		var d := global_position.distance_to(p.global_position)
		if d < best_dist:
			best_dist = d
			nearest = p
	return nearest


func _get_player() -> Node3D:
	if is_instance_valid(_cached_player) and _player_cache_timer > 0.0:
		return _cached_player
	var nearest := _get_nearest_player()
	_cached_player = nearest
	_player_cache_timer = 0.5
	return _cached_player


func _check_aggro() -> void:
	if is_passive:
		return
	if is_instance_valid(_target):
		return
	if _aggro_check_cd > 0.0:
		return
	_aggro_check_cd = 0.25
	var best_target: Node3D = null
	var best_dist := INF
	var p := _get_player()
	if is_instance_valid(p):
		var effective_aggro := aggro_range
		if p.has_method("_has_affix") and p._has_affix(&"light_step"):
			effective_aggro *= 0.6
		var d := global_position.distance_to(p.global_position)
		if d < effective_aggro and d < best_dist:
			best_dist = d
			best_target = p
	if best_target:
		_target = best_target
		_cached_player = best_target
		_state = State.CHASE
		_combat_timer = 8.0
		_hp_bar_visible_timer = 10.0
		if creature_type in ["lion", "wolf", "hyena", "bear"] and _roar_cooldown <= 0.0:
			AudioManager.play_sfx_at("lion_roar", global_position, -6.0, 0.2)
			_roar_cooldown = 8.0
		if _floating_ui:
			_floating_ui.visible = true


func _pick_wander_direction() -> void:
	var angle := randf_range(0.0, TAU)
	_wander_direction = Vector3(cos(angle), 0.0, sin(angle))
	_wander_timer = randf_range(2.0, 5.0)


func _update_sprite_direction() -> void:
	if sprite_textures.is_empty():
		return

	var look_dir: Vector3
	if _holding_at_target and is_instance_valid(_target):
		look_dir = _target.global_position - global_position
		look_dir.y = 0.0
		if look_dir.length_squared() < 0.01:
			return
		look_dir = look_dir.normalized()
	else:
		look_dir = Vector3(velocity.x, 0.0, velocity.z)
		if look_dir.length_squared() < 0.1:
			return
		look_dir = look_dir.normalized()

	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var cam_forward := -cam.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right := cam.global_transform.basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	var fwd_dot := look_dir.dot(cam_forward)
	var right_dot := look_dir.dot(cam_right)
	var new_dir: String
	if absf(fwd_dot) >= absf(right_dot):
		new_dir = "north" if fwd_dot > 0.0 else "south"
	else:
		new_dir = "east" if right_dot > 0.0 else "west"
	if new_dir != _current_dir and sprite_textures.has(new_dir):
		_current_dir = new_dir
		var body_sprite := get_node_or_null("BodySprite") as Sprite3D
		if body_sprite:
			_set_sprite_texture(body_sprite, sprite_textures[new_dir] as Texture2D)


func _apply_procedural_walk(delta: float, body_sprite: Sprite3D) -> void:
	if _sprite_base_y < 0.0:
		_sprite_base_y = body_sprite.position.y

	var flat_speed := Vector2(velocity.x, velocity.z).length()

	if flat_speed > 0.3:
		var speed_factor := clampf(flat_speed / maxf(move_speed, 1.0), 0.4, 1.5)
		_walk_bob_phase += delta * _WALK_BOB_SPEED * speed_factor
		var bob := sin(_walk_bob_phase) * _WALK_BOB_AMPLITUDE * speed_factor
		body_sprite.position.y = _sprite_base_y + bob
		var lean := sin(_walk_bob_phase * 0.5) * _WALK_LEAN_MAX * speed_factor
		body_sprite.rotation.z = lean
	else:
		body_sprite.position.y = lerpf(body_sprite.position.y, _sprite_base_y, delta * 10.0)
		body_sprite.rotation.z = lerpf(body_sprite.rotation.z, 0.0, delta * 10.0)
		if absf(body_sprite.position.y - _sprite_base_y) < 0.002:
			body_sprite.position.y = _sprite_base_y
			body_sprite.rotation.z = 0.0
		_walk_bob_phase = 0.0


func _tick_animation(delta: float) -> void:
	if use_3d_model:
		_tick_3d_animation()
		return

	var body_sprite := get_node_or_null("BodySprite") as Sprite3D
	if not body_sprite:
		return

	if _state == State.ATTACK and not attack_frames.is_empty() and attack_frames.has(_current_dir):
		_anim_frame_timer -= delta
		if _anim_frame_timer <= 0.0:
			_anim_frame_timer = _ATTACK_FRAME_DURATION
			var frames: Array = attack_frames[_current_dir] as Array
			if not frames.is_empty():
				_anim_frame_idx = (_anim_frame_idx + 1) % frames.size()
				_set_sprite_texture(body_sprite, frames[_anim_frame_idx] as Texture2D)
		return

	var is_settled := _holding_at_target or (_state == State.PERCH and _perch_settled) or (_state == State.EAT_FISH and _perch_settled)
	if is_settled:
		if not idle_frames.is_empty() and idle_frames.has(_current_dir):
			_anim_frame_timer -= delta
			if _anim_frame_timer <= 0.0:
				_anim_frame_timer = _RUN_FRAME_DURATION
				var frames: Array = idle_frames[_current_dir] as Array
				if not frames.is_empty():
					_anim_frame_idx = (_anim_frame_idx + 1) % frames.size()
					_set_sprite_texture(body_sprite, frames[_anim_frame_idx] as Texture2D)
			return
		if sprite_textures.has(_current_dir):
			_set_sprite_texture(body_sprite, sprite_textures[_current_dir] as Texture2D)
		_anim_frame_idx = 0
		_anim_frame_timer = 0.0
		return

	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var is_moving := flat_speed > 0.3
	var is_aggressive := _state == State.CHASE or _state == State.ATTACK or _evading

	if is_moving or (is_flying and not is_settled):
		var use_run := is_aggressive and not run_frames.is_empty() and run_frames.has(_current_dir)
		var use_walk := not use_run and not walk_frames.is_empty() and walk_frames.has(_current_dir)
		var use_run_fallback := not use_run and not use_walk and not run_frames.is_empty() and run_frames.has(_current_dir)

		var anim_source: Dictionary = {}
		var frame_dur := _RUN_FRAME_DURATION
		if use_run:
			anim_source = run_frames
			frame_dur = _RUN_FRAME_DURATION
		elif use_walk:
			anim_source = walk_frames
			frame_dur = _WALK_FRAME_DURATION
		elif use_run_fallback:
			anim_source = run_frames
			frame_dur = _WALK_FRAME_DURATION

		if not anim_source.is_empty() and anim_source.has(_current_dir):
			_anim_frame_timer -= delta
			if _anim_frame_timer <= 0.0:
				_anim_frame_timer = frame_dur
				var frames: Array = anim_source[_current_dir] as Array
				if not frames.is_empty():
					_anim_frame_idx = (_anim_frame_idx + 1) % frames.size()
					_set_sprite_texture(body_sprite, frames[_anim_frame_idx] as Texture2D)
			return

		_apply_procedural_walk(delta, body_sprite)
		return

	if not is_moving and sprite_textures.has(_current_dir):
		_anim_frame_idx = 0
		_anim_frame_timer = 0.0
		_set_sprite_texture(body_sprite, sprite_textures[_current_dir] as Texture2D)
		_apply_procedural_walk(delta, body_sprite)


func _tick_3d_animation() -> void:
	if not _model_node:
		return

	var flat_vel := Vector2(velocity.x, velocity.z)

	if _state == State.ATTACK and _target and is_instance_valid(_target):
		var to_target := _target.global_position - global_position
		var face_angle := atan2(to_target.x, to_target.z) + _model_yaw_offset
		_model_node.rotation.y = lerp_angle(_model_node.rotation.y, face_angle, 0.25)
		_play_model_anim("attack")
		return

	if flat_vel.length() > 0.3:
		var target_angle := atan2(velocity.x, velocity.z) + _model_yaw_offset
		_model_node.rotation.y = lerp_angle(_model_node.rotation.y, target_angle, 0.15)

	if _state == State.DEAD:
		return
	if _state == State.ATTACK:
		_play_model_anim("attack")
		return
	var is_moving := flat_vel.length() > 0.3
	var is_aggressive := _state == State.CHASE or _state == State.ATTACK or _evading
	if is_flying:
		var is_settled := _holding_at_target or (_state == State.PERCH and _perch_settled)
		if is_settled:
			_play_model_anim("idle")
		elif is_moving or not is_on_floor():
			_play_model_anim("fly")
		else:
			_play_model_anim("idle")
	elif is_moving:
		if is_aggressive:
			_play_model_anim("run")
			_model_anim_player.speed_scale = 1.0
		else:
			_play_model_anim("walk")
			var wander_ratio := clampf(flat_vel.length() / maxf(move_speed, 1.0), 0.25, 1.0)
			_model_anim_player.speed_scale = wander_ratio
	else:
		var idle_track: String = _anim_map.get("idle", "") as String
		var walk_track: String = _anim_map.get("walk", "") as String
		if idle_track != "" and idle_track == walk_track:
			_play_model_anim("idle")
			_model_anim_player.speed_scale = 0.0
		else:
			_play_model_anim("idle")


@rpc("any_peer", "reliable")
func request_damage(amount: float, source_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var clamped := clampf(amount, 0.0, 9999.0)
	if clamped != amount:
		if _DEBUG_LOG: print("[CREATURE] WARN: peer %d sent suspicious damage %.1f, clamped to %.1f" % [source_peer, amount, clamped])
	if _DEBUG_LOG: print("[CREATURE] request_damage received: %.1f from peer %d on '%s'" % [clamped, source_peer, name])
	take_damage(clamped, _get_player_by_peer(source_peer))


@rpc("authority", "reliable")
func deal_damage_to_player(peer_id: int, amount: float) -> void:
	# Called on the target client to apply creature damage to local player
	var player := _get_player_by_peer(peer_id)
	if player and player.has_method("take_damage"):
		player.take_damage(amount, self)


func _get_player_by_peer(peer_id: int) -> Node3D:
	var players := get_tree().get_nodes_in_group(&"player")
	for node in players:
		var p := node as Node3D
		if not is_instance_valid(p):
			continue
		if p.get_multiplayer_authority() == peer_id:
			return p
	return null


func take_damage(amount: float, source: Node3D = null) -> void:
	if _state == State.DEAD:
		return
	var eff_amount := amount
	if _armor_shred_factor > 0.0:
		eff_amount *= (1.0 + _armor_shred_factor)
	current_health = maxf(current_health - eff_amount, 0.0)
	_hit_flash_timer = 0.2
	_hp_bar_visible_timer = 5.0
	_update_hp_bar()

	if _floating_ui:
		_floating_ui.visible = true

	_play_hurt_sound()

	_combat_timer = 8.0
	_evading = false
	if source and source.is_in_group(&"player"):
		_target = source
		_cached_player = source
		_perch_target = null
		_perch_settled = false
		if _state != State.ATTACK:
			_state = State.CHASE

	if current_health <= 0.0:
		_die()


func apply_slow(factor: float, duration: float) -> void:
	_slow_factor = minf(_slow_factor, factor)
	_slow_timer = maxf(_slow_timer, duration)

func apply_stun(duration: float) -> void:
	_stun_timer = maxf(_stun_timer, duration)

func apply_poison(dps: float, duration: float, source: Node3D = null) -> void:
	_poison_dps = maxf(_poison_dps, dps)
	_poison_timer = maxf(_poison_timer, duration)
	if source:
		_poison_source = source

func is_dead() -> bool:
	return _state == State.DEAD

func is_stunned() -> bool:
	return _stun_timer > 0.0

func apply_disorient(duration: float) -> void:
	_disorient_timer = maxf(_disorient_timer, duration)

func apply_armor_shred(factor: float, duration: float) -> void:
	_armor_shred_factor = maxf(_armor_shred_factor, factor)
	_armor_shred_timer = maxf(_armor_shred_timer, duration)

func _get_effective_speed() -> float:
	if _slow_timer > 0.0:
		return move_speed * _slow_factor
	return move_speed

func _tick_status_effects(delta: float) -> void:
	if _stun_timer > 0.0:
		_stun_timer -= delta
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_factor = 1.0
	if _poison_timer > 0.0:
		_poison_timer -= delta
		var tick_dmg := _poison_dps * delta
		if tick_dmg > 0.0 and _state != State.DEAD:
			current_health = maxf(current_health - tick_dmg, 0.0)
			_hp_bar_visible_timer = 5.0
			_update_hp_bar()
			if current_health <= 0.0:
				_die()
		if _poison_timer <= 0.0:
			_poison_dps = 0.0
			_poison_source = null
	# -- Campfire burn damage --
	if _state != State.DEAD:
		_campfire_check_timer -= delta
		if _campfire_check_timer <= 0.0:
			_campfire_check_timer = 0.5
			_campfire_in_fire = false
			for node in get_tree().get_nodes_in_group(&"campfire"):
				if node is Node3D:
					var cf2 := node as Node3D
					var dx2 := cf2.global_position.x - global_position.x
					var dz2 := cf2.global_position.z - global_position.z
					if dx2*dx2 + dz2*dz2 < 1.0:
						_campfire_in_fire = true
						break
		if _campfire_in_fire:
			_fire_exposure += delta
			if _fire_exposure >= 1.0:
				_fire_damage_timer -= delta
				if _fire_damage_timer <= 0.0:
					_fire_damage_timer = 1.0
					current_health = maxf(current_health - 10.0, 0.0)
					_hp_bar_visible_timer = 5.0
					_update_hp_bar()
					if current_health <= 0.0:
						_die()
		else:
			_fire_exposure = maxf(_fire_exposure - delta * 2.0, 0.0)
	if _disorient_timer > 0.0:
		_disorient_timer -= delta
	if _armor_shred_timer > 0.0:
		_armor_shred_timer -= delta
		if _armor_shred_timer <= 0.0:
			_armor_shred_factor = 0.0


func _die() -> void:
	_state = State.DEAD
	collision_layer = 0

	if _carried_fish_sprite:
		drop_carried_fish()

	if _floating_ui:
		_floating_ui.visible = true
	_play_death_sound()

	if is_flying and not is_on_floor():
		_dying_fall = true
		is_flying = false
		collision_mask = 1
		velocity = Vector3(velocity.x * 0.3, -0.5, velocity.z * 0.3)
		if use_3d_model and _model_node:
			_tint_model_meshes_flash(true)
			var tween := create_tween()
			tween.tween_callback(func(): _tint_model_meshes_flash(false)).set_delay(0.2)
			tween.parallel().tween_property(_model_node, "rotation:x", deg_to_rad(-45.0), 0.3)
		else:
			var body_sprite := get_node_or_null("BodySprite") as Sprite3D
			if body_sprite:
				body_sprite.modulate = Color(2.0, 0.3, 0.3)
				var tween := create_tween()
				tween.tween_property(body_sprite, "modulate", Color.WHITE, 0.2)
				tween.parallel().tween_property(body_sprite, "rotation:x", deg_to_rad(-45.0), 0.3)
	else:
		velocity = Vector3.ZERO
		collision_mask = 0
		_spawn_loot_and_play_ground_death()


func _finish_death_on_ground() -> void:
	velocity = Vector3.ZERO
	collision_mask = 0
	_spawn_loot_and_play_ground_death()


func _spawn_loot_and_play_ground_death() -> void:
	if use_3d_model and _model_node:
		const DESIRED_DEATH_TIME := 1.75
		var death_resolved: String = _anim_map.get("death", "") as String
		var death_len := 0.0
		if death_resolved != "" and _model_anim_player and _model_anim_player.has_animation(death_resolved):
			var anim := _model_anim_player.get_animation(death_resolved)
			if anim and anim.length > 0.0:
				death_len = anim.length
				_model_anim_player.speed_scale = death_len / DESIRED_DEATH_TIME
			else:
				_model_anim_player.speed_scale = 1.0
			_model_anim_player.play(death_resolved)
			_model_current_anim = "death"

		var tween := create_tween()
		if death_len > 0.1:
			tween.tween_interval(DESIRED_DEATH_TIME)
		else:
			if _model_anim_player:
				_model_anim_player.stop()
			tween.tween_property(_model_node, "rotation:z", deg_to_rad(90.0), 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
			tween.parallel().tween_property(_model_node, "position:y", 0.1, 0.4).set_ease(Tween.EASE_IN)
			tween.tween_interval(0.4)
		tween.tween_callback(_explode_and_free)
	else:
		var body_sprite := get_node_or_null("BodySprite") as Sprite3D
		if body_sprite:
			var tween := create_tween()
			body_sprite.modulate = Color(2.0, 0.3, 0.3)
			tween.tween_property(body_sprite, "modulate", Color.WHITE, 0.15)
			tween.tween_property(body_sprite, "rotation:z", deg_to_rad(90.0), 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
			tween.parallel().tween_property(body_sprite, "position:y", 0.15, 0.35).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(body_sprite, "rotation:x", 0.0, 0.2)
			tween.tween_interval(0.4)
			tween.tween_callback(_explode_and_free)
		else:
			_explode_and_free()


func _explode_and_free() -> void:
	if _floating_ui:
		_floating_ui.visible = false
	GameEvents.creature_killed.emit(global_position)

	# Loot and affix application only on host (host spawns loot via WorldStateSync)
	if multiplayer.is_server() or not multiplayer.has_multiplayer_peer():
		if not loot_table.is_empty():
			_LootDrop.spawn_loot(get_tree(), global_position, loot_table, star_level, rare_loot_table)

		for node in get_tree().get_nodes_in_group(&"player"):
			var player = node
			if not is_instance_valid(player) or not player.has_method("_has_affix"):
				continue
			if player._has_affix(&"adrenaline"):
				player._adrenaline_timer = 4.0
			if player._has_affix(&"crushing_momentum"):
				player._crushing_momentum_timer = 4.0

	var burst_pos := global_position + Vector3.UP * 0.8
	var scene_root := get_tree().current_scene
	if not scene_root:
		queue_free()
		return

	var chunk_count := 14
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var base_color := Color(0.7, 0.5, 0.3)
	if use_3d_model and _model_node:
		for mi in _model_node.find_children("*", "MeshInstance3D", true):
			var mesh_mi := mi as MeshInstance3D
			if mesh_mi and mesh_mi.mesh and mesh_mi.mesh.get_surface_count() > 0:
				var mat = mesh_mi.get_active_material(0)
				if mat is StandardMaterial3D:
					base_color = (mat as StandardMaterial3D).albedo_color
					break

	for i in chunk_count:
		var chunk := MeshInstance3D.new()
		var box := BoxMesh.new()
		var sz := rng.randf_range(0.08, 0.22)
		box.size = Vector3(sz, sz, sz)
		chunk.mesh = box

		var mat := StandardMaterial3D.new()
		mat.albedo_color = base_color.lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.35)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		chunk.set_surface_override_material(0, mat)

		chunk.global_position = burst_pos + Vector3(
			rng.randf_range(-0.3, 0.3),
			rng.randf_range(-0.2, 0.4),
			rng.randf_range(-0.3, 0.3))
		scene_root.add_child(chunk)

		var angle := rng.randf_range(0.0, TAU)
		var speed := rng.randf_range(2.0, 5.0)
		var vel := Vector3(cos(angle) * speed, rng.randf_range(3.0, 6.0), sin(angle) * speed)

		var tw := chunk.create_tween()
		tw.set_parallel(true)
		tw.tween_property(chunk, "global_position",
			chunk.global_position + vel * 0.5 + Vector3.DOWN * 2.0, 0.7) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(chunk, "rotation",
			Vector3(rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0), rng.randf_range(-8.0, 8.0)), 0.7)
		tw.chain().tween_callback(chunk.queue_free)

	queue_free()


func _update_hit_flash(delta: float) -> void:
	if _state == State.DEAD:
		pass
	elif _hp_bar_visible_timer > 0.0:
		_hp_bar_visible_timer -= delta
		var show := _hp_bar_visible_timer > 0.0 or _state == State.CHASE
		if _floating_ui:
			_floating_ui.visible = show

	if _hit_flash_timer <= 0.0:
		return
	_hit_flash_timer -= delta

	if use_3d_model and _model_node:
		_tint_model_meshes_flash(_hit_flash_timer > 0.0)
		return

	var sprite := get_node_or_null("BodySprite") as Sprite3D
	if not sprite:
		return
	if _hit_flash_timer > 0.0:
		sprite.modulate = Color(3.0, 0.3, 0.3)
	else:
		sprite.modulate = Color.WHITE


var _original_mat_colors: Array[Dictionary] = []

func _cache_model_material_colors(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count() if mi.mesh else 0:
			var mat := mi.get_active_material(i)
			if mat is StandardMaterial3D:
				var unique_mat := mat.duplicate() as StandardMaterial3D
				mi.set_surface_override_material(i, unique_mat)
				_original_mat_colors.append({mat = unique_mat, color = unique_mat.albedo_color})
	for child in node.get_children():
		_cache_model_material_colors(child)

func _tint_model_meshes_flash(is_flashing: bool) -> void:
	for entry in _original_mat_colors:
		var mat: StandardMaterial3D = entry.mat as StandardMaterial3D
		if is_flashing:
			mat.albedo_color = Color(3.0, 0.3, 0.3)
		else:
			mat.albedo_color = entry.color as Color


func _compute_arrow_hitbox() -> void:
	if not _model_node:
		return
	var min_y := 999.0
	var max_y := -999.0
	var max_xz := 0.0
	for child in _model_node.find_children("*", "MeshInstance3D", true):
		var mi: MeshInstance3D = child as MeshInstance3D
		if not mi or not mi.mesh:
			continue
		var aabb := mi.mesh.get_aabb()
		var corners: Array[Vector3] = [
			aabb.position,
			aabb.position + Vector3(aabb.size.x, 0, 0),
			aabb.position + Vector3(0, aabb.size.y, 0),
			aabb.position + Vector3(0, 0, aabb.size.z),
			aabb.end,
			aabb.end - Vector3(aabb.size.x, 0, 0),
			aabb.end - Vector3(0, aabb.size.y, 0),
			aabb.end - Vector3(0, 0, aabb.size.z),
		]
		for corner in corners:
			var world_pt := (mi.global_transform * corner) - global_position
			min_y = minf(min_y, world_pt.y)
			max_y = maxf(max_y, world_pt.y)
			var xz_dist := Vector2(world_pt.x, world_pt.z).length()
			max_xz = maxf(max_xz, xz_dist)
	if max_y > min_y and max_xz > 0.1:
		arrow_hit_height = max_y - min_y
		arrow_hit_radius = maxf(max_xz * 0.7, 0.5)
		arrow_hit_y_offset = (min_y + max_y) * 0.5


func _estimate_model_top(model: Node3D) -> float:
	var max_y := 0.0
	for child in model.find_children("*", "MeshInstance3D", true):
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi and mi.mesh:
			var aabb := mi.mesh.get_aabb()
			var top_local := aabb.position.y + aabb.size.y
			var top_world := (mi.global_transform * Vector3(0, top_local, 0)).y - global_position.y
			if top_world > max_y:
				max_y = top_world
	return max_y if max_y > 0.5 else 1.6


const _UI_HEIGHT_OVERRIDES := {
	&"grizzly": 4.2,
}

func _recompute_ui_height() -> void:
	if not use_3d_model or not _model_node:
		return
	if not _floating_ui:
		return
	var top := _estimate_model_top(_model_node)
	if creature_kind in _UI_HEIGHT_OVERRIDES:
		top = maxf(top, _UI_HEIGHT_OVERRIDES[creature_kind])
	_floating_ui.position.y = top + 0.5


func _create_floating_ui() -> void:
	var ui_root := Node3D.new()
	ui_root.name = "FloatingUI"
	_floating_ui = ui_root

	var ui_y := 1.2 if is_flying else 1.6
	if use_3d_model and _model_node:
		var top := _estimate_model_top(_model_node)
		if creature_kind in _UI_HEIGHT_OVERRIDES:
			top = maxf(top, _UI_HEIGHT_OVERRIDES[creature_kind])
		ui_y = top + 0.5
	ui_root.position.y = ui_y
	ui_root.visible = false
	add_child(ui_root)

	var full_text := display_name
	var star_text := ""
	if star_level > 0:
		star_text = " "
		for i in star_level:
			star_text += "★"
		full_text += star_text

	var label_fs := 32
	var label_px := 0.0075

	_nameplate_label = Label3D.new()
	_nameplate_label.name = "NameplateLabel"
	_nameplate_label.text = display_name
	_nameplate_label.font_size = label_fs
	_nameplate_label.pixel_size = label_px
	_nameplate_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nameplate_label.no_depth_test = false
	_nameplate_label.modulate = Color.WHITE
	_nameplate_label.outline_modulate = Color(0, 0, 0, 0.95)
	_nameplate_label.outline_size = 10
	_nameplate_label.render_priority = 1

	if star_level > 0:
		_nameplate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stars_label = Label3D.new()
		_stars_label.name = "StarsLabel"
		_stars_label.text = star_text
		_stars_label.font_size = label_fs
		_stars_label.pixel_size = label_px
		_stars_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_stars_label.no_depth_test = false
		_stars_label.modulate = ItemDatabase.get_rarity_color(star_level)
		_stars_label.outline_modulate = Color(0, 0, 0, 0.95)
		_stars_label.outline_size = 10
		_stars_label.render_priority = 1
		_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	var font: Font = _nameplate_label.font if _nameplate_label.font else ThemeDB.fallback_font
	var actual_name_w := font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs).x * label_px
	var actual_stars_w := 0.0
	if _stars_label:
		actual_stars_w = font.get_string_size(star_text, HORIZONTAL_ALIGNMENT_LEFT, -1, label_fs).x * label_px
	var total_w := actual_name_w + actual_stars_w

	var em := float(label_fs) * label_px
	var star_outline := label_px * 14.0 if _stars_label else 0.0
	var padding := em * 1.5 + star_outline
	var text_h := em * 0.77
	var pad_y := text_h * 0.35
	var bg_w := total_w + padding
	var bg_h := text_h + pad_y * 2.0

	var label_y := 0.15
	if _stars_label:
		var junction_x := (actual_name_w - actual_stars_w) * 0.5 + em * 0.22
		_nameplate_label.position = Vector3(junction_x, label_y, 0)
		_stars_label.position = Vector3(junction_x, label_y, 0)
		ui_root.add_child(_stars_label)
	else:
		_nameplate_label.position.y = label_y
	ui_root.add_child(_nameplate_label)

	# Background panel (rectangle, matching target HUD style)
	_attach_nameplate_bg(ui_root, bg_w, bg_h, label_y)

	_hp_bar_full_width = bg_w * 0.92

	# Health bar below the nameplate
	var bar_y := label_y - bg_h * 0.5 - 0.04
	var bar_h := 0.025

	_hp_bar_bg = Sprite3D.new()
	_hp_bar_bg.name = "HPBarBG"
	_hp_bar_bg.pixel_size = 0.001
	_hp_bar_bg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar_bg.no_depth_test = false
	_hp_bar_bg.render_priority = 0
	var bg_img := Image.create(128, 8, false, Image.FORMAT_RGBA8)
	bg_img.fill(Color(0.1, 0.1, 0.1, 0.85))
	_hp_bar_bg.texture = ImageTexture.create_from_image(bg_img)
	_hp_bar_bg.scale = Vector3(_hp_bar_full_width / 0.128, bar_h / 0.008, 1.0)
	_hp_bar_bg.position = Vector3(0.0, bar_y, 0.001)
	ui_root.add_child(_hp_bar_bg)

	_hp_bar_fill = Sprite3D.new()
	_hp_bar_fill.name = "HPBarFill"
	_hp_bar_fill.pixel_size = 0.001
	_hp_bar_fill.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_bar_fill.no_depth_test = false
	_hp_bar_fill.render_priority = 1
	var fill_img := Image.create(128, 8, false, Image.FORMAT_RGBA8)
	fill_img.fill(Color.WHITE)
	_hp_bar_fill.texture = ImageTexture.create_from_image(fill_img)
	_hp_bar_fill.scale = Vector3(_hp_bar_full_width / 0.128, bar_h / 0.008, 1.0)
	_hp_bar_fill.position = Vector3(0.0, bar_y, 0.002)
	_hp_bar_fill.modulate = Color(0.1, 0.85, 0.15)
	ui_root.add_child(_hp_bar_fill)


static func _estimate_text_width(text: String, unit: float) -> float:
	var w := 0.0
	for c in text:
		if c == "★":
			w += unit * 0.72
		elif c == " ":
			w += unit * 0.3
		elif c in "mwMW":
			w += unit * 0.7
		elif c in "iltILT.,!|":
			w += unit * 0.3
		else:
			w += unit * 0.52
	return w


static func _smoothstep(edge0: float, edge1: float, x: float) -> float:
	var t := clampf((x - edge0) / maxf(edge1 - edge0, 0.0001), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _ensure_panel_tex() -> void:
	if _shared_panel_tex:
		return

	var img := Image.create(_BANNER_W, _BANNER_H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var taper := 0.14
	var border_width := 0.10
	var interior := Color(0.06, 0.06, 0.10)
	var border_col := Color(0.22, 0.19, 0.15)

	for x in _BANNER_W:
		for y in _BANNER_H:
			var ux := float(x) / float(_BANNER_W - 1)
			var uy := float(y) / float(_BANNER_H - 1)

			var edge_dist := minf(ux, 1.0 - ux)
			var taper_factor := _smoothstep(0.0, taper, edge_dist)

			var half_h := 0.5 * taper_factor
			var center_dist := absf(uy - 0.5)
			if center_dist > half_h:
				continue

			var dist_from_edge := half_h - center_dist
			var edge_soft := _smoothstep(0.0, 0.06, dist_from_edge)

			var border_amt := 1.0 - _smoothstep(0.0, border_width * maxf(taper_factor, 0.3), dist_from_edge)
			var col := interior.lerp(border_col, border_amt)

			var sheen := 1.0 - (center_dist / maxf(half_h, 0.001))
			col = col.lerp(Color(0.10, 0.09, 0.13), sheen * 0.12)

			var alpha := 0.78 * edge_soft * _smoothstep(0.0, taper * 0.35, edge_dist)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, alpha))

	_shared_panel_tex = ImageTexture.create_from_image(img)

	if not _shared_accent_tex:
		var accent_img := Image.create(64, 4, false, Image.FORMAT_RGBA8)
		accent_img.fill(Color(0, 0, 0, 0))
		for ax in 64:
			var aux := float(ax) / 63.0
			var ae := minf(aux, 1.0 - aux)
			var aa := _smoothstep(0.0, 0.18, ae) * 0.7
			for ay in 4:
				var auy := float(ay) / 3.0
				var vert_fade := 1.0 - absf(auy - 0.5) * 1.6
				accent_img.set_pixel(ax, ay, Color(1, 1, 1, aa * maxf(vert_fade, 0.0)))
		_shared_accent_tex = ImageTexture.create_from_image(accent_img)


func _attach_nameplate_bg(_ui_root: Node3D, _bg_w: float, _bg_h: float, _label_y: float) -> void:
	pass


func _update_hp_bar() -> void:
	if not _hp_bar_fill or not _hp_bar_bg:
		return
	var bar_hidden := _hud_targeted
	_hp_bar_fill.visible = not bar_hidden
	_hp_bar_bg.visible = not bar_hidden
	if bar_hidden:
		return
	var ratio := clampf(current_health / max_health, 0.0, 1.0)
	var fill_color: Color
	if ratio > 0.5:
		fill_color = Color(0.1, 0.85, 0.15).lerp(Color(0.9, 0.85, 0.1), (1.0 - ratio) * 2.0)
	else:
		fill_color = Color(0.9, 0.85, 0.1).lerp(Color(0.85, 0.15, 0.1), (0.5 - ratio) * 2.0)
	_hp_bar_fill.modulate = fill_color
	var full_scale_x := _hp_bar_full_width / 0.128
	_hp_bar_fill.scale.x = full_scale_x * maxf(ratio, 0.001)
	_hp_bar_fill.position.x = -_hp_bar_full_width * (1.0 - ratio) * 0.5


func _play_hurt_sound() -> void:
	var sfx_name: String
	match creature_type:
		"boar":
			sfx_name = "boar_hurt"
		"bear":
			sfx_name = "lion_hurt"
		"lion", "wolf", "hyena":
			sfx_name = "lion_hurt"
		"hawk":
			sfx_name = "boar_hurt"
		_:
			sfx_name = "boar_hurt"
	AudioManager.play_sfx_at(sfx_name, global_position, -4.0, 0.15)


func _play_death_sound() -> void:
	var sfx_name: String
	match creature_type:
		"boar":
			sfx_name = "boar_hurt"
		"bear":
			sfx_name = "lion_death"
		"lion", "wolf", "hyena":
			sfx_name = "lion_death"
		"hawk":
			sfx_name = "boar_hurt"
		_:
			sfx_name = "boar_hurt"
	AudioManager.play_sfx_at(sfx_name, global_position, -2.0, 0.1)


const _LABEL_SHOW_DIST := 70.0
const _LABEL_HIDE_DIST := 84.0

func _update_proximity_label() -> void:
	if _state == State.DEAD:
		return
	if _hp_bar_visible_timer > 0.0 or _state == State.CHASE:
		return
	if not _floating_ui:
		return
	var player := _get_player()
	if not player:
		return
	var dist := global_position.distance_to(player.global_position)
	if dist < _LABEL_SHOW_DIST:
		_floating_ui.visible = true
	elif dist > _LABEL_HIDE_DIST:
		_floating_ui.visible = false
