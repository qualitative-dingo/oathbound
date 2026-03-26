class_name PlayerAnimation
extends Node

## Animation sub-module for PlayerController. Stores reference to parent and accesses state via pc.
const _DEBUG_LOG := false

var pc: PlayerController

# Constants
const IDLE_FRAME_DURATION := 0.35
const RUN_FRAME_DURATION := 0.1
const SPRINT_FRAME_DURATION := 0.07
const SPRITE_BASE_Y := 0.9
const ATTACK_FRAME_DURATION_FIST := 0.05
const ATTACK_FRAME_DURATION_TOOL := 0.07
const ATTACK_FRAME_DURATION_BOW := 0.08
const JUMP_FRAME_DURATION := 0.08
const HORSE_WALK_FRAME_DURATION := 0.14
const HORSE_RUN_FRAME_DURATION := 0.09
const SIT_IDLE_FRAME_DURATION := 0.12

const _UPPER_BODY_BONES: Array[String] = [
	"mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2",
	"mixamorig_Neck", "mixamorig_Head",
	"mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
	"mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand",
]


# ===================================================================
# SETUP
# ===================================================================

func setup_player_sprite() -> void:
	for key in ["south", "west", "east", "north"]:
		var path := "res://textures/player/player_%s.png" % key
		if ResourceLoader.exists(path):
			pc._player_textures[key] = load(path)

	load_idle_frames()
	load_attack_frames()
	load_run_frames()
	load_jump_frames()
	pc._sit_idle_frames = load_anim_set("sit-idle_%s_%d.png", 16)

	if pc._player_textures.is_empty():
		return

	if pc._model:
		var old_node := pc._model.get_node_or_null("PlayerSprite")
		if old_node:
			old_node.queue_free()

	var gltf_path := "res://models/player/Lowpolyvikingwithaxe/barbarian+3d+model.glb"
	if not ResourceLoader.exists(gltf_path):
		gltf_path = "res://models/player/Pahlevan/Warrior Idle.fbx"
	if not ResourceLoader.exists(gltf_path):
		gltf_path = "res://models/player/Pahlevan/Pahlevan.glb"
	if not ResourceLoader.exists(gltf_path):
		gltf_path = "res://models/player/viking_base_v4.gltf"
	var gltf_scene: PackedScene = load(gltf_path) as PackedScene
	if gltf_scene:
		pc._player_sprite = gltf_scene.instantiate()
		pc._player_sprite.name = "PlayerSprite"
		var is_tripo_barbarian := gltf_path.contains("Lowpolyvikingwithaxe") or gltf_path.contains("barbarian")
		var is_mixamo_fbx := gltf_path.ends_with(".fbx")
		var is_lowpoly_viking := is_tripo_barbarian
		pc._is_lowpoly_viking = is_lowpoly_viking
		var is_tripo_model := is_tripo_barbarian or gltf_path.contains("muscular+warrior") or gltf_path.contains("Pahlevan")
		var s := 4.0 if is_tripo_barbarian else (400.0 if is_lowpoly_viking else (200.0 if is_mixamo_fbx else (2.5 if is_tripo_model else 0.7)))
		pc._player_sprite.scale = Vector3(s, s, s)
		if is_tripo_barbarian:
			pc._player_yaw_offset = -PI / 2.0
		if pc._model and pc._player_yaw_offset != 0.0:
			pc._model.rotation.y = pc._player_yaw_offset
		pc._base_sprite_y = 0.0
		pc._player_sprite.position.y = pc._base_sprite_y
		if pc._model:
			pc._model.add_child(pc._player_sprite)
		if _DEBUG_LOG: print("[PLAYER MODEL] Loaded %s — scale=%.2f" % [gltf_path.get_file(), s])
		pc._gltf_anim_player = find_anim_player(pc._player_sprite)
		if pc._gltf_anim_player:
			pc._gltf_anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			pc._rename_nla_tracks()
			if not is_tripo_barbarian:
				pc._load_external_animations()
			var anim_list := pc._gltf_anim_player.get_animation_list()
			if _DEBUG_LOG: print("[PLAYER MODEL] Available animations: ", anim_list)
			var non_looping := [
				"jump", "standing_jump", "punch", "punch_alt", "kick",
				"sword_slash", "spin_attack", "jump_attack", "heavy_swing",
				"bow_draw", "bow_hold", "lie_down", "equip", "hit_react",
				"chop", "afraid", "attack_right", "attack_left",
			]
			for anim_name in anim_list:
				var anim := pc._gltf_anim_player.get_animation(anim_name)
				if anim:
					if anim_name in non_looping:
						anim.loop_mode = Animation.LOOP_NONE
					else:
						anim.loop_mode = Animation.LOOP_LINEAR
					pc._strip_root_motion(anim)
			rebuild_axe_swing_horizontal()
			rebuild_bow_draw_animation()
			rebuild_bow_release_animation()
			rebuild_club_smash_animation()
			rebuild_sword_slash_animation()
			gltf_play("idle")
		pc._gltf_all_meshes = []
		collect_mesh_instances(pc._player_sprite, pc._gltf_all_meshes)
		if is_tripo_barbarian:
			apply_tripo_player_texture()
		elif is_lowpoly_viking:
			apply_viking_texture()
		elif is_mixamo_fbx and is_tripo_model:
			apply_pahlevan_texture()
		elif not is_tripo_model and not is_mixamo_fbx:
			apply_oathbound_shader()
			pc._enhance_character_model()
		else:
			if _DEBUG_LOG: print("[PLAYER MODEL] Tripo model — skipping Blockbench shaders")
		pc.call_deferred("_update_equipped_weapon_model")
		call_deferred("update_armor_visuals")
	else:
		pc._player_model_3d = PlayerModel3D.new()
		pc._player_model_3d.build()
		pc._player_sprite = pc._player_model_3d
		pc._player_sprite.name = "PlayerSprite"
		pc._base_sprite_y = 0.82
		pc._player_sprite.position.y = pc._base_sprite_y
		if pc._model:
			pc._model.add_child(pc._player_sprite)


func get_armor_aabb(instance: Node3D) -> AABB:
	var combined := AABB()
	var first := true
	var meshes: Array[Node] = instance.find_children("*", "MeshInstance3D", true)
	for m: Node in meshes:
		var mi: MeshInstance3D = m as MeshInstance3D
		if mi and mi.mesh:
			var transformed: AABB = mi.transform * mi.mesh.get_aabb()
			if first:
				combined = transformed
				first = false
			else:
				combined = combined.merge(transformed)
	return combined


func update_armor_visuals() -> void:
	for slot: String in pc._armor_nodes.keys():
		var node: Node3D = pc._armor_nodes[slot] as Node3D
		if is_instance_valid(node):
			node.queue_free()
	pc._armor_nodes.clear()

	if not pc._player_sprite:
		return

	if pc._is_lowpoly_viking:
		return

	var skel := find_skeleton(pc._player_sprite)
	if not skel:
		return

	var hips_idx := skel.find_bone("mixamorig_Hips")
	var head_idx := skel.find_bone("mixamorig_Head")
	if hips_idx < 0 or head_idx < 0:
		return
	var hips_rest: Vector3 = skel.get_bone_global_rest(hips_idx).origin
	var head_rest: Vector3 = skel.get_bone_global_rest(head_idx).origin
	var torso_height: float = (head_rest - hips_rest).length()

	var foot_idx := skel.find_bone("mixamorig_LeftFoot")
	var foot_rest: Vector3 = skel.get_bone_global_rest(foot_idx).origin if foot_idx >= 0 else hips_rest

	var l_shoulder_idx := skel.find_bone("mixamorig_LeftShoulder")
	var r_shoulder_idx := skel.find_bone("mixamorig_RightShoulder")
	var shoulder_width := torso_height * 0.6
	if l_shoulder_idx >= 0 and r_shoulder_idx >= 0:
		var l_pos := skel.get_bone_global_rest(l_shoulder_idx).origin
		var r_pos := skel.get_bone_global_rest(r_shoulder_idx).origin
		shoulder_width = (l_pos - r_pos).length()

	var slot_coverage: Dictionary = {
		"chest": 1.4,
		"legs": 1.7,
		"feet": 0.9,
	}
	var bone_target: Dictionary = {
		"chest": "mixamorig_Spine1",
		"legs": "mixamorig_Hips",
		"feet": "mixamorig_Hips",
	}

	for slot in Inventory.EQUIPMENT_SLOTS:
		var item_id: StringName = Inventory.get_equipped(slot)
		if item_id == &"":
			continue
		var data: Dictionary = ItemDatabase.get_item(item_id)
		var model_path: String = str(data.get("model", ""))
		if model_path.is_empty() or not ResourceLoader.exists(model_path):
			continue
		var scene: PackedScene = load(model_path) as PackedScene
		if not scene:
			continue
		var instance: Node3D = scene.instantiate()
		instance.name = "Armor_" + slot

		var aabb: AABB = get_armor_aabb(instance)
		var model_height: float = aabb.size.y
		if model_height < 0.0001:
			model_height = maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z)
		if model_height < 0.0001:
			instance.queue_free()
			continue

		var coverage: float = slot_coverage.get(slot, 0.5) as float
		var target_size_skel: float = torso_height * coverage
		var armor_scale: float = target_size_skel / model_height
		var model_center: Vector3 = aabb.get_center()

		var xz_auto: float = 1.0
		if slot == "chest":
			var model_width := maxf(aabb.size.x, aabb.size.z)
			if model_width > 0.0001:
				xz_auto = (shoulder_width * 1.15) / (model_width * armor_scale)

		var fit_scale: Vector3 = data.get("fit_scale", Vector3.ONE) as Vector3
		var fit_offset: Vector3 = data.get("fit_offset", Vector3.ZERO) as Vector3
		var fit_rotation: Vector3 = data.get("fit_rotation", Vector3(0.0, -90.0, 0.0)) as Vector3

		var sx := armor_scale * xz_auto * fit_scale.x
		var sy := armor_scale * fit_scale.y
		var sz := armor_scale * xz_auto * fit_scale.z
		instance.scale = Vector3(sx, sy, sz)
		if _DEBUG_LOG: print("[ARMOR %s] aabb=%s height=%.4f width=%.4f armor_scale=%.4f xz_auto=%.4f shoulder_w=%.4f torso_h=%.4f final_scale=%s" % [slot, aabb, model_height, maxf(aabb.size.x, aabb.size.z), armor_scale, xz_auto, shoulder_width, torso_height, instance.scale])

		var bname: String = bone_target.get(slot, "mixamorig_Hips") as String
		var bone_idx := skel.find_bone(bname)
		if bone_idx < 0:
			bone_idx = hips_idx
			bname = "mixamorig_Hips"

		var bone_rest: Vector3 = skel.get_bone_global_rest(bone_idx).origin
		var local_offset := Vector3(
			-model_center.x * sx,
			-model_center.y * sy,
			-model_center.z * sz)

		if slot == "feet":
			local_offset.y += (foot_rest.y - bone_rest.y)
		elif slot == "legs":
			local_offset.y += (foot_rest.y - bone_rest.y) * 0.35

		local_offset += fit_offset

		instance.position = local_offset
		instance.rotation = Vector3(
			deg_to_rad(fit_rotation.x),
			deg_to_rad(fit_rotation.y),
			deg_to_rad(fit_rotation.z))

		var attachment := BoneAttachment3D.new()
		attachment.name = "ArmorAttach_" + slot
		attachment.bone_name = bname
		attachment.bone_idx = bone_idx
		skel.add_child(attachment)
		attachment.add_child(instance)
		pc._armor_nodes[slot] = attachment

	hide_body_under_armor(skel)


func hide_body_under_armor(skel: Skeleton3D) -> void:
	if pc._gltf_all_meshes.is_empty() or not skel:
		return

	var slot_bone_names: Dictionary = {
		"chest": [
			"mixamorig_Hips",
			"mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2",
			"mixamorig_Neck",
			"mixamorig_LeftShoulder", "mixamorig_RightShoulder",
			"mixamorig_LeftArm", "mixamorig_RightArm",
		],
		"legs": [
			"mixamorig_Hips",
			"mixamorig_LeftUpLeg", "mixamorig_RightUpLeg",
			"mixamorig_LeftLeg", "mixamorig_RightLeg",
		],
		"feet": [
			"mixamorig_LeftFoot", "mixamorig_RightFoot",
			"mixamorig_LeftToeBase", "mixamorig_RightToeBase",
		],
	}

	var bones_to_hide: Array[int] = []
	for slot in Inventory.EQUIPMENT_SLOTS:
		var item_id: StringName = Inventory.get_equipped(slot)
		if item_id == &"":
			continue
		var names: Array = slot_bone_names.get(slot, []) as Array
		for bname in names:
			var bidx := skel.find_bone(bname as String)
			if bidx >= 0 and bidx not in bones_to_hide:
				bones_to_hide.append(bidx)

	var hide_arr := PackedInt32Array()
	hide_arr.resize(32)
	hide_arr.fill(-1)
	for k in bones_to_hide.size():
		if k < 32:
			hide_arr[k] = bones_to_hide[k]

	for mi in pc._gltf_all_meshes:
		if not mi.mesh:
			continue
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(si)
			if mat is ShaderMaterial:
				var smat: ShaderMaterial = mat as ShaderMaterial
				smat.set_shader_parameter("hide_bone_count", bones_to_hide.size())
				smat.set_shader_parameter("hide_bones", hide_arr)


func load_idle_frames() -> void:
	for direction in ["south", "west", "east", "north"]:
		var frames: Array[Texture2D] = []
		for i in range(16):
			var path := "res://textures/player/idle_%s_%d.png" % [direction, i]
			if ResourceLoader.exists(path):
				var tex := load(path) as Texture2D
				if tex:
					frames.append(tex)
		if not frames.is_empty():
			pc._idle_frames[direction] = frames


func load_attack_frames() -> void:
	pc._fist_frames = load_anim_set("punch_%s_%d.png", 16)
	pc._kick_frames_attack = load_anim_set("kick_%s_%d.png", 7)
	pc._weapon_attack_frames = load_anim_set("axe-swing_%s_%d.png", 16)
	pc._pickaxe_attack_frames = load_anim_set("pickaxe-swing_%s_%d.png", 16)
	pc._sword_attack_frames = load_anim_set("sword-swing_%s_%d.png", 16)
	pc._bow_attack_frames = load_anim_set("bow-shoot_%s_%d.png", 16)
	pc._attack_frames = pc._fist_frames if pc._fist_frames.is_empty() else pc._weapon_attack_frames


func load_anim_set(pattern: String, frame_count: int) -> Dictionary:
	var result: Dictionary = {}
	for direction in ["south", "west", "east", "north"]:
		var frames: Array[Texture2D] = []
		for i in range(frame_count):
			var path := "res://textures/player/%s" % (pattern % [direction, i])
			if ResourceLoader.exists(path):
				var tex := load(path) as Texture2D
				if tex:
					frames.append(tex)
		if not frames.is_empty():
			result[direction] = frames
	return result


func load_run_frames() -> void:
	for direction in ["south", "west", "east", "north"]:
		var frames: Array[Texture2D] = []
		for i in range(16):
			var path := "res://textures/player/jog_%s_%d.png" % [direction, i]
			if ResourceLoader.exists(path):
				var tex := load(path) as Texture2D
				if tex:
					frames.append(tex)
		if not frames.is_empty():
			pc._run_frames[direction] = frames


func load_jump_frames() -> void:
	for anim_prefix in ["jump", "flip"]:
		var target: Dictionary = pc._jump_frames if anim_prefix == "jump" else pc._flip_frames
		for direction in ["south", "west", "east", "north"]:
			var frames: Array[Texture2D] = []
			for i in range(16):
				var path := "res://textures/player/%s_%s_%d.png" % [anim_prefix, direction, i]
				if ResourceLoader.exists(path):
					var tex := load(path) as Texture2D
					if tex:
						frames.append(tex)
			if not frames.is_empty():
				target[direction] = frames


# ===================================================================
# MOVEMENT AUDIO
# ===================================================================

func setup_movement_audio() -> void:
	pc._footstep_player = AudioStreamPlayer.new()
	pc._footstep_player.bus = &"SFX"
	pc._footstep_player.volume_db = -8.5
	pc.add_child(pc._footstep_player)
	pc._footstep_player.finished.connect(on_footstep_finished)

	pc._gallop_player = AudioStreamPlayer.new()
	pc._gallop_player.bus = &"SFX"
	pc._gallop_player.volume_db = -9.6
	pc.add_child(pc._gallop_player)
	pc._gallop_player.finished.connect(on_gallop_finished)

	var fs := AudioManager.get_stream("grass_step")
	if fs:
		pc._footstep_player.stream = fs
	pc._gallop_normal_stream = AudioManager.get_stream("horse_gallop")
	pc._gallop_fast_stream = AudioManager.get_stream("horse_gallop_fast")


func on_footstep_finished() -> void:
	if pc._footstep_player and pc._footstep_player.stream and not pc._mounted:
		var spd := Vector2(pc.velocity.x, pc.velocity.z).length()
		if spd > 0.5 and pc.is_on_floor():
			pc._footstep_player.play()


func on_gallop_finished() -> void:
	if pc._gallop_player and pc._gallop_player.stream and pc._mounted and pc.is_on_floor():
		var spd := Vector2(pc.velocity.x, pc.velocity.z).length()
		if spd > 0.5:
			pc._gallop_player.play()


func tick_footstep_sfx(_delta: float) -> void:
	if not pc._footstep_player or not pc._footstep_player.stream:
		return
	var flat_speed := Vector2(pc.velocity.x, pc.velocity.z).length()
	var want_playing := not pc._mounted and flat_speed > 0.5 and pc.is_on_floor() and not pc._is_swimming
	if want_playing:
		var speed_ratio := clampf(flat_speed / pc.walk_speed, 0.4, 2.2) * 0.65
		pc._footstep_player.pitch_scale = speed_ratio
	if want_playing and not pc._footstep_player.playing:
		pc._footstep_player.play()
	elif not want_playing and pc._footstep_player.playing:
		pc._footstep_player.stop()


func tick_gallop_sfx(_delta: float) -> void:
	if not pc._gallop_player:
		return
	var want_playing := pc._mounted and Vector2(pc.velocity.x, pc.velocity.z).length() > 0.5 and pc.is_on_floor()
	var want_stream: AudioStream = pc._gallop_fast_stream if pc._is_sprinting else pc._gallop_normal_stream
	if not want_stream:
		return
	if want_playing:
		if pc._gallop_player.stream != want_stream:
			pc._gallop_player.stream = want_stream
			pc._gallop_player.play()
		elif not pc._gallop_player.playing:
			pc._gallop_player.play()
	elif pc._gallop_player.playing:
		pc._gallop_player.stop()


# ===================================================================
# SPRITE DIRECTION & ROTATION
# ===================================================================

func get_camera_relative_dir() -> String:
	var move_dir := Vector3(pc.velocity.x, 0.0, pc.velocity.z)
	if move_dir.length_squared() < 0.1:
		return pc._current_run_dir
	move_dir = move_dir.normalized()
	var cam_forward := -pc._camera_pivot.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right := pc._camera_pivot.global_transform.basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	var forward_dot := move_dir.dot(cam_forward)
	var right_dot := move_dir.dot(cam_right)
	if absf(forward_dot) >= absf(right_dot):
		return "north" if forward_dot > 0.0 else "south"
	else:
		return "east" if right_dot > 0.0 else "west"


func rotate_model() -> void:
	if not pc._model:
		return
	var flat_velocity := Vector3(pc.velocity.x, 0.0, pc.velocity.z)
	if flat_velocity.length_squared() > 0.1:
		var target_rotation := atan2(flat_velocity.x, flat_velocity.z) + pc._player_yaw_offset
		pc._model.rotation.y = lerp_angle(pc._model.rotation.y, target_rotation, 0.15)
	update_sprite_direction()


func update_sprite_direction() -> void:
	if not pc._player_sprite or pc._player_textures.is_empty() or pc._is_attacking or pc._is_run_animating or pc._is_jumping or pc._bow_drawing:
		return
	var move_dir := Vector3(pc.velocity.x, 0.0, pc.velocity.z)
	if move_dir.length_squared() < 0.1:
		return
	var key := get_camera_relative_dir()
	if pc._player_textures.has(key):
		pc._set_player_sprite_tex(pc._player_textures[key] as Texture2D)


# ===================================================================
# JUMP ANIMATION
# ===================================================================

func start_jump_animation() -> void:
	if pc._bow_drawing:
		return
	pc._is_jumping = true
	if pc._gltf_anim_player:
		pc._gltf_current_anim = ""
		gltf_play("jump")
		return
	pc._is_flipping = randf() < 0.25 and not pc._flip_frames.is_empty()
	var frames_dict: Dictionary = pc._flip_frames if pc._is_flipping else pc._jump_frames
	if frames_dict.is_empty():
		return
	pc._jump_frame_idx = 0
	pc._jump_frame_timer = JUMP_FRAME_DURATION
	var dir := get_camera_relative_dir()
	if frames_dict.has(dir):
		var arr: Array = Array(frames_dict[dir])
		if not arr.is_empty():
			var tex := arr[0] as Texture2D
			if tex and pc._player_sprite:
				pc._set_player_sprite_tex(tex)


func tick_jump_animation(delta: float) -> void:
	if not pc._is_jumping or not pc._player_sprite or pc._bow_drawing:
		return
	if pc._gltf_anim_player:
		if pc.is_on_floor() and pc.velocity.y <= 0.0:
			pc._is_jumping = false
			pc._is_flipping = false
			pc._gltf_current_anim = ""
			gltf_play("idle")
		return
	if pc.is_on_floor() and pc.velocity.y <= 0.0:
		pc._is_jumping = false
		pc._is_flipping = false
		revert_to_idle_sprite()
		return
	pc._jump_frame_timer -= delta
	if pc._jump_frame_timer > 0.0:
		return
	var dir := get_camera_relative_dir()
	var frames_dict: Dictionary = pc._flip_frames if pc._is_flipping else pc._jump_frames
	if not frames_dict.has(dir):
		return
	var arr: Array = Array(frames_dict[dir])
	pc._jump_frame_idx += 1
	if pc._jump_frame_idx >= arr.size():
		pc._jump_frame_idx = arr.size() - 1
		return
	var tex := arr[pc._jump_frame_idx] as Texture2D
	if tex:
		pc._set_player_sprite_tex(tex)
	pc._jump_frame_timer = JUMP_FRAME_DURATION


# ===================================================================
# RUNNING ANIMATION
# ===================================================================

func tick_run_animation(delta: float) -> void:
	if not pc._player_sprite:
		return
	if pc._gltf_anim_player:
		return
	var flat_speed := Vector2(pc.velocity.x, pc.velocity.z).length()
	var is_moving := flat_speed > 0.5 and pc.is_on_floor() and not pc._is_attacking and not pc._is_jumping and not pc._bow_drawing

	if is_moving and not pc._run_frames.is_empty():
		var dir := get_camera_relative_dir()
		pc._current_run_dir = dir
		if not pc._run_frames.has(dir):
			pc._is_run_animating = false
			return
		pc._is_run_animating = true
		var frame_dur := SPRINT_FRAME_DURATION if pc._is_sprinting else RUN_FRAME_DURATION
		pc._run_frame_timer -= delta
		if pc._run_frame_timer <= 0.0:
			var frames_arr: Array = Array(pc._run_frames[dir])
			pc._run_frame_idx = (pc._run_frame_idx + 1) % frames_arr.size()
			var tex := frames_arr[pc._run_frame_idx] as Texture2D
			if tex:
				pc._set_player_sprite_tex(tex)
			pc._run_frame_timer = frame_dur
		pc._player_sprite.position.y = pc._base_sprite_y
		pc._player_sprite.scale = Vector3.ONE
		pc._player_sprite.rotation.x = 0.0
	else:
		if pc._is_run_animating:
			pc._is_run_animating = false
			pc._run_frame_idx = 0
		pc._player_sprite.position.y = pc._base_sprite_y
		pc._player_sprite.scale = Vector3.ONE
		pc._player_sprite.rotation.x = 0.0


func tick_idle_animation(delta: float) -> void:
	if not pc._player_sprite or pc._idle_frames.is_empty():
		return
	if pc._gltf_anim_player:
		return
	if pc._is_attacking or pc._is_run_animating or pc._is_jumping or pc._bow_drawing:
		pc._idle_frame_timer = 0.0
		return

	var flat_speed := Vector2(pc.velocity.x, pc.velocity.z).length()
	if flat_speed > 0.5:
		return

	var dir := get_camera_relative_dir()
	pc._current_idle_dir = dir
	if not pc._idle_frames.has(dir):
		return

	pc._idle_frame_timer -= delta
	if pc._idle_frame_timer <= 0.0:
		var frames_arr: Array = Array(pc._idle_frames[dir])
		pc._idle_frame_idx = (pc._idle_frame_idx + 1) % frames_arr.size()
		var tex := frames_arr[pc._idle_frame_idx] as Texture2D
		if tex:
			pc._set_player_sprite_tex(tex)
		pc._idle_frame_timer = IDLE_FRAME_DURATION


func tick_swim_visual(delta: float) -> void:
	if not pc._player_sprite:
		return
	if pc._is_swimming:
		pc._swim_time += delta
		var bob := sin(pc._swim_time * 3.0) * 0.06
		pc._player_sprite.position.y = pc._base_sprite_y - 0.35 + bob
		var tilt := sin(pc._swim_time * 2.2) * 0.08
		pc._player_sprite.rotation.z = tilt
		var flat_speed := Vector2(pc.velocity.x, pc.velocity.z).length()
		if flat_speed > 0.3:
			var paddle := sin(pc._swim_time * 6.0) * 0.12
			pc._player_sprite.rotation.z += paddle
	else:
		if pc._swim_time > 0.0:
			pc._swim_time = 0.0
			pc._player_sprite.position.y = pc._base_sprite_y
			pc._player_sprite.rotation.z = 0.0


func tick_3d_model(delta: float) -> void:
	if pc._gltf_anim_player:
		var flat_speed := Vector2(pc.velocity.x, pc.velocity.z).length()
		var moving := flat_speed > 0.5 and pc.is_on_floor() and not pc._is_swimming
		var _needs_torso_lock := false
		var _needs_advance := true
		var _weapon_needed := false
		if pc._mounted:
			gltf_play("sit")
		elif pc._is_attacking:
			if pc._gltf_attack_timer > 0.0:
				pc._gltf_attack_timer -= delta
				if pc._gltf_attack_timer <= 0.0:
					pc._is_attacking = false
			if pc._gltf_attack_anim != "":
				gltf_play(pc._gltf_attack_anim)
			else:
				gltf_play("attack_right")
			_needs_torso_lock = true
			_weapon_needed = true
			if pc._bow_arrow_node:
				pc._bow_arrow_node.visible = false
		elif pc._bow_drawing:
			var bow_anim_name := ""
			for candidate in ["animation.bow_draw", "animation_bow_draw", "bow_draw"]:
				if pc._gltf_anim_player.has_animation(candidate):
					bow_anim_name = candidate
					break
			if bow_anim_name != "":
				if pc._gltf_current_anim != bow_anim_name:
					pc._gltf_current_anim = bow_anim_name
					pc._gltf_anim_player.play(bow_anim_name, -1, 0.0)
				var pct := clampf(pc._bow_tension / pc.BOW_MAX_DRAW_TIME, 0.0, 1.0)
				pc._gltf_anim_player.seek(pct * pc._gltf_anim_player.current_animation_length, true)
			_needs_torso_lock = true
			_needs_advance = false
			_weapon_needed = true
			if pc._bow_arrow_node:
				var draw_pct := clampf(pc._bow_tension / pc.BOW_MAX_DRAW_TIME, 0.0, 1.0)
				pc._bow_arrow_node.visible = draw_pct > 0.15
		elif pc._is_jumping:
			gltf_play("jump")
			if pc._bow_arrow_node:
				pc._bow_arrow_node.visible = false
		elif moving:
			gltf_play("run" if pc._is_sprinting else "walk")
			if pc._bow_arrow_node:
				pc._bow_arrow_node.visible = false
		else:
			gltf_play("idle")
			if pc._bow_arrow_node:
				pc._bow_arrow_node.visible = false
		if _weapon_needed and not pc._weapon_drawn:
			pc._draw_weapon()
		elif not _weapon_needed and pc._weapon_drawn:
			pc._stow_weapon()
		if _needs_advance:
			pc._gltf_anim_player.advance(delta)
		if _needs_torso_lock:
			lock_torso_height()
		if pc._weapon_drawn:
			update_2h_left_grip()
		return
	if not pc._player_model_3d:
		return
	var flat_speed := Vector2(pc.velocity.x, pc.velocity.z).length()
	var moving := flat_speed > 0.5 and pc.is_on_floor() and not pc._is_swimming
	pc._player_model_3d.tick(delta, moving, pc._is_sprinting, pc._is_attacking)


# ===================================================================
# ATTACK ANIMATION
# ===================================================================

func tick_attack_animation(delta: float) -> void:
	if not pc._is_attacking or not pc._player_sprite:
		return
	if pc._gltf_anim_player:
		return
	pc._attack_frame_timer -= delta
	if pc._attack_frame_timer > 0.0:
		return
	if not pc._attack_frames.has(pc._current_attack_dir):
		pc._is_attacking = false
		revert_to_idle_sprite()
		return
	var frames_arr: Array = Array(pc._attack_frames[pc._current_attack_dir])
	pc._attack_frame_idx += 1
	if pc._attack_frame_idx >= frames_arr.size():
		pc._is_attacking = false
		revert_to_idle_sprite()
		return
	var tex := frames_arr[pc._attack_frame_idx] as Texture2D
	if tex:
		pc._set_player_sprite_tex(tex)
	pc._attack_frame_timer = pc._current_attack_frame_duration


func revert_to_idle_sprite() -> void:
	if not pc._player_sprite:
		return
	var dir := pc._current_attack_dir
	if pc._idle_frames.has(dir) and not pc._idle_frames[dir].is_empty():
		pc._set_player_sprite_tex((pc._idle_frames[dir] as Array)[0] as Texture2D)
		pc._idle_frame_idx = 0
		pc._idle_frame_timer = IDLE_FRAME_DURATION
	elif pc._player_textures.has(dir):
		pc._set_player_sprite_tex(pc._player_textures[dir] as Texture2D)


# ===================================================================
# BOW DRAW SPRITE
# ===================================================================

func update_bow_draw_sprite() -> void:
	if pc._gltf_anim_player:
		return
	if pc._bow_attack_frames.is_empty() or not pc._player_sprite:
		return
	var dir := get_camera_relative_dir()
	if not pc._bow_attack_frames.has(dir):
		return
	var frames_arr: Array = Array(pc._bow_attack_frames[dir])
	if frames_arr.is_empty():
		return
	var tension_pct := clampf(pc._bow_tension / pc.BOW_MAX_DRAW_TIME, 0.0, 1.0)
	var draw_frames := int(ceilf(frames_arr.size() * 0.6))
	var frame_idx := int(tension_pct * float(draw_frames - 1))
	frame_idx = clampi(frame_idx, 0, draw_frames - 1)
	var tex := frames_arr[frame_idx] as Texture2D
	if tex:
		pc._set_player_sprite_tex(tex)


# ===================================================================
# GLTF ANIMATION HELPERS
# ===================================================================

func find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := find_anim_player(child)
		if result:
			return result
	return null


func collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		collect_mesh_instances(child, out)


func gltf_play(anim_name: String) -> void:
	if not pc._gltf_anim_player:
		return

	var aliases := {
		"idle": ["stand", "idle"],
		"axe_swing": ["chop", "axe_swing"],
		"club_smash": ["chop", "club_smash"],
		"sword_slash": ["kick", "sword_slash"],
		"attack_right": ["kick", "attack_right"],
		"attack_left": ["kick", "attack_left"],
		"punch": ["kick", "punch"],
		"punch_alt": ["kick", "punch_alt"],
		"bow_draw": ["bow_draw"],
		"bow_release": ["bow_release"],
		"hit_react": ["afraid", "hit_react"],
		"jump": ["jump"],
	}

	var speed_overrides := {
		"axe_swing": 4.0,
		"club_smash": 4.0,
		"sword_slash": 1.0,
		"hit_react": 2.0,
		"heavy_swing": 1.5,
		"kick": 2.0,
		"punch": 2.5,
		"punch_alt": 2.0,
	}
	var speed := speed_overrides.get(anim_name, 1.0) as float

	var names_to_try: Array[String] = []
	if aliases.has(anim_name):
		for alias in aliases[anim_name]:
			names_to_try.append(alias)
	names_to_try.append(anim_name)

	for base_name in names_to_try:
		var candidates := [
			"animation." + base_name,
			"animation_" + base_name,
			base_name,
		]
		for candidate in candidates:
			if pc._gltf_anim_player.has_animation(candidate):
				if pc._gltf_current_anim != candidate:
					pc._gltf_current_anim = candidate
					pc._gltf_anim_player.speed_scale = speed
					pc._gltf_anim_player.play(candidate)
				return

	if anim_name == "run":
		for base in ["run", "walk"]:
			for candidate in ["animation." + base, "animation_" + base, base]:
				if pc._gltf_anim_player.has_animation(candidate):
					if pc._gltf_current_anim != candidate + "_fast":
						pc._gltf_current_anim = candidate + "_fast"
						pc._gltf_anim_player.speed_scale = 1.4 if base == "walk" else 1.0
						pc._gltf_anim_player.play(candidate)
					return

	if pc._gltf_anim_player.has_animation("NlaTrack"):
		if anim_name == "idle":
			if pc._gltf_current_anim != "NlaTrack_idle":
				pc._gltf_current_anim = "NlaTrack_idle"
				pc._gltf_anim_player.play("NlaTrack")
				pc._gltf_anim_player.seek(0.0, true)
				pc._gltf_anim_player.pause()
			return
		if anim_name in ["walk", "run"]:
			var was_paused := pc._gltf_current_anim == "NlaTrack_idle"
			pc._gltf_current_anim = "NlaTrack"
			if was_paused or not pc._gltf_anim_player.is_playing():
				pc._gltf_anim_player.play("NlaTrack")
			if anim_name == "run":
				pc._gltf_anim_player.speed_scale = 1.4
			else:
				pc._gltf_anim_player.speed_scale = 1.0
			return

	if not pc._gltf_play_warned.has(anim_name):
		pc._gltf_play_warned[anim_name] = true
		if _DEBUG_LOG: print("[PLAYER ANIM] '%s' not found. Available: %s" % [anim_name, pc._gltf_anim_player.get_animation_list()])


func lock_torso_height() -> void:
	if pc._cached_torso_bones.is_empty():
		var rest_positions := {
			"hips": Vector3(0, 1.25, 0),
			"spine": Vector3(0, 0.25, 0),
			"chest": Vector3(0, 0.375, 0),
			"neck": Vector3(0, 0.25, 0),
			"head": Vector3(0, 0.125, 0),
		}
		for bone_name in rest_positions:
			var node := pc._find_node_recursive(pc._player_sprite, bone_name)
			if node and node is Node3D:
				pc._cached_torso_bones[bone_name] = {
					"node": node,
					"rest_pos": rest_positions[bone_name],
				}
	for bone_name in pc._cached_torso_bones:
		var info: Dictionary = pc._cached_torso_bones[bone_name]
		var node: Node3D = info["node"]
		node.position = info["rest_pos"]


func blend_upper_body_attack() -> void:
	if pc._gltf_attack_anim.is_empty() or not pc._gltf_anim_player:
		return
	var skel := find_skeleton(pc._player_sprite)
	if not skel:
		return

	var anim_name := ""
	for candidate in ["animation." + pc._gltf_attack_anim, "animation_" + pc._gltf_attack_anim, pc._gltf_attack_anim]:
		if pc._gltf_anim_player.has_animation(candidate):
			anim_name = candidate
			break
	if anim_name.is_empty():
		return

	var anim: Animation = pc._gltf_anim_player.get_animation(anim_name)
	if not anim:
		return

	var speed_overrides: Dictionary = {
		"kick": 2.0, "punch": 2.5, "punch_alt": 2.0,
	}
	var speed: float = speed_overrides.get(pc._gltf_attack_anim, 1.0)
	var t := clampf(pc._unarmed_attack_time * speed, 0.0, anim.length)

	for i in anim.get_track_count():
		var track_path := anim.track_get_path(i)
		var path_str := str(track_path)
		var bone_name := ""
		if ":" in path_str:
			bone_name = path_str.get_slice(":", 1)
		else:
			bone_name = path_str.split("/")[-1]

		if bone_name not in _UPPER_BODY_BONES:
			continue

		var bone_idx := skel.find_bone(bone_name)
		if bone_idx < 0:
			continue

		match anim.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				var rot: Quaternion = anim.rotation_track_interpolate(i, t)
				skel.set_bone_pose_rotation(bone_idx, rot)
			Animation.TYPE_POSITION_3D:
				var pos: Vector3 = anim.position_track_interpolate(i, t)
				skel.set_bone_pose_position(bone_idx, pos)


func update_2h_left_grip() -> void:
	if not pc._equipped_weapon_node or not pc._l_grip_marker:
		return
	if not pc._cached_l_upper_arm:
		pc._cached_l_upper_arm = pc._find_node_recursive(pc._player_sprite, "L_UpperArm")
	if not pc._cached_l_forearm:
		pc._cached_l_forearm = pc._find_node_recursive(pc._player_sprite, "L_Forearm")
	if not pc._cached_l_hand:
		pc._cached_l_hand = pc._find_node_recursive(pc._player_sprite, "L_Hand")
	if not pc._cached_l_upper_arm or not pc._cached_l_forearm or not pc._cached_l_hand:
		return

	var grip_world := pc._l_grip_marker.global_position
	var upper_world := pc._cached_l_upper_arm.global_position

	var upper_len := pc._cached_l_upper_arm.global_position.distance_to(pc._cached_l_forearm.global_position)
	var lower_len := pc._cached_l_forearm.global_position.distance_to(pc._cached_l_hand.global_position)
	if upper_len < 0.001 or lower_len < 0.001:
		return

	var to_grip := grip_world - upper_world
	var dist := to_grip.length()
	var max_reach := upper_len + lower_len - 0.01
	if dist > max_reach:
		to_grip = to_grip.normalized() * max_reach
		dist = max_reach
	if dist < 0.01:
		return

	var aim_dir := to_grip.normalized()
	var cos_elbow := clampf(
		(upper_len * upper_len + lower_len * lower_len - dist * dist)
		/ (2.0 * upper_len * lower_len), -1.0, 1.0)
	var cos_shoulder := clampf(
		(upper_len * upper_len + dist * dist - lower_len * lower_len)
		/ (2.0 * upper_len * dist), -1.0, 1.0)
	var shoulder_offset := acos(cos_shoulder)

	var parent_upper := pc._cached_l_upper_arm.get_parent() as Node3D
	if not parent_upper:
		return
	var parent_basis_inv := parent_upper.global_basis.inverse()
	var local_aim := (parent_basis_inv * aim_dir).normalized()

	var rest_dir := Vector3(0, -1, 0)
	var upper_quat: Quaternion
	if rest_dir.cross(local_aim).length_squared() > 0.0001:
		var base_quat := Quaternion(rest_dir, local_aim)
		var pitch_axis := rest_dir.cross(local_aim).normalized()
		var pitch_quat := Quaternion(pitch_axis, -shoulder_offset)
		upper_quat = pitch_quat * base_quat
	else:
		upper_quat = Quaternion.IDENTITY

	var anim_upper := pc._cached_l_upper_arm.quaternion
	pc._cached_l_upper_arm.quaternion = anim_upper.slerp(upper_quat, 0.6)

	var fore_parent := pc._cached_l_forearm.get_parent() as Node3D
	if not fore_parent:
		return

	var fore_grip_world := grip_world - pc._cached_l_forearm.global_position
	if fore_grip_world.length() < 0.001:
		return
	var fore_local_dir := (fore_parent.global_basis.inverse() * fore_grip_world.normalized()).normalized()
	var fore_quat: Quaternion
	if rest_dir.cross(fore_local_dir).length_squared() > 0.0001:
		fore_quat = Quaternion(rest_dir, fore_local_dir)
	else:
		fore_quat = Quaternion.IDENTITY

	var anim_fore := pc._cached_l_forearm.quaternion
	pc._cached_l_forearm.quaternion = anim_fore.slerp(fore_quat, 0.6)


# ===================================================================
# ANIMATION REBUILD
# ===================================================================

func rebuild_axe_swing_horizontal() -> void:
	if not pc._gltf_anim_player:
		return

	var old_name := ""
	for candidate in ["animation.axe_swing", "animation_axe_swing", "axe_swing"]:
		if pc._gltf_anim_player.has_animation(candidate):
			old_name = candidate
			break
	if old_name == "":
		return

	var old_anim := pc._gltf_anim_player.get_animation(old_name)

	var bone_paths: Dictionary = {}
	for track_idx in old_anim.get_track_count():
		var path := old_anim.track_get_path(track_idx)
		var node_path := path.get_concatenated_names()
		var parts := node_path.split("/")
		var bone_name: String = parts[-1] if parts.size() > 0 else node_path
		bone_paths[bone_name] = path

	var times: PackedFloat32Array = PackedFloat32Array([0.0, 0.18, 0.42, 0.62, 0.90])

	var bone_keyframes: Dictionary = {
		"spine":      {"x": [3.0, 3.0, 3.0, 3.0, 3.0], "y": [0.0, 14.0, -16.0, -10.0, 0.0]},
		"chest":      {"x": [-1.5, -1.5, -1.5, -1.5, -1.5], "y": [0.0, 6.0, -8.0, -5.0, 0.0]},
		"hips":       {"y": [0.0, 4.0, -5.0, -3.0, 0.0]},
		"head":       {"x": [-2.0, -2.0, -2.0, -2.0, -2.0], "y": [0.0, 4.0, -6.0, -3.0, 0.0]},
		"R_UpperArm": {
			"x": [-30.0, -65.0, -50.0, -42.0, -30.0],
			"y": [0.0, 15.0, -22.0, -12.0, 0.0],
			"z": [0.0, 20.0, -32.0, -18.0, 0.0],
		},
		"L_UpperArm": {
			"x": [-45.0, -72.0, -58.0, -48.0, -45.0],
			"y": [0.0, 18.0, -25.0, -14.0, 0.0],
			"z": [12.0, 38.0, -36.0, -18.0, 12.0],
		},
		"R_Forearm":  {"x": [-40.0, -25.0, -55.0, -45.0, -40.0]},
		"L_Forearm":  {"x": [-55.0, -38.0, -68.0, -52.0, -55.0]},
		"R_Thigh":    {"x": [0.0, 0.0, 0.0, 0.0, 0.0]},
		"L_Thigh":    {"x": [0.0, 0.0, 0.0, 0.0, 0.0]},
		"R_Calf":     {"x": [0.0, 0.0, 0.0, 0.0, 0.0]},
		"L_Calf":     {"x": [0.0, 0.0, 0.0, 0.0, 0.0]},
	}

	var new_anim := Animation.new()
	new_anim.length = 0.90
	new_anim.loop_mode = Animation.LOOP_NONE

	for bone_name in bone_keyframes:
		if not bone_paths.has(bone_name):
			continue
		var path: NodePath = bone_paths[bone_name]
		var axes: Dictionary = bone_keyframes[bone_name]

		var track_idx := new_anim.add_track(Animation.TYPE_ROTATION_3D)
		new_anim.track_set_path(track_idx, path)
		new_anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_LINEAR)

		for ki in times.size():
			var ex: float = deg_to_rad(axes.get("x", [0.0, 0.0, 0.0, 0.0, 0.0])[ki])
			var ey: float = deg_to_rad(axes.get("y", [0.0, 0.0, 0.0, 0.0, 0.0])[ki])
			var ez: float = deg_to_rad(axes.get("z", [0.0, 0.0, 0.0, 0.0, 0.0])[ki])
			var quat := Quaternion.from_euler(Vector3(ex, ey, ez))
			new_anim.rotation_track_insert_key(track_idx, times[ki], quat)

	if bone_paths.has("hips"):
		var pt := new_anim.add_track(Animation.TYPE_POSITION_3D)
		new_anim.track_set_path(pt, bone_paths["hips"])
		new_anim.track_set_interpolation_type(pt, Animation.INTERPOLATION_LINEAR)
		for ki in times.size():
			new_anim.position_track_insert_key(pt, times[ki], Vector3(0, 1.25, 0))

	var lib := pc._gltf_anim_player.get_animation_library("")
	if lib:
		if lib.has_animation(old_name):
			lib.remove_animation(old_name)
		lib.add_animation(old_name, new_anim)


func rebuild_bow_draw_animation() -> void:
	if not pc._gltf_anim_player:
		return
	var ref_name := ""
	for candidate in ["animation.axe_swing", "animation_axe_swing", "axe_swing"]:
		if pc._gltf_anim_player.has_animation(candidate):
			ref_name = candidate
			break
	if ref_name == "":
		return
	var ref_anim := pc._gltf_anim_player.get_animation(ref_name)
	var bone_paths: Dictionary = {}
	for track_idx in ref_anim.get_track_count():
		var path := ref_anim.track_get_path(track_idx)
		var parts := path.get_concatenated_names().split("/")
		bone_paths[parts[-1] if parts.size() > 0 else path.get_concatenated_names()] = path

	var times: PackedFloat32Array = PackedFloat32Array([0.0, 0.15, 0.40, 0.70, 1.0])
	var kf: Dictionary = {
		"L_UpperArm": {
			"x": [-30.0, -30.0, -65.0, -80.0, -85.0],
			"y": [0.0,    0.0,  -8.0, -12.0, -15.0],
			"z": [-4.0,  -4.0, -12.0, -18.0, -20.0],
		},
		"L_Forearm": {"x": [-8.0, -8.0, -6.0, -4.0, -3.0]},
		"R_UpperArm": {
			"x": [-30.0, -55.0, -65.0, -75.0, -78.0],
			"y": [0.0,  -25.0,  10.0,  30.0,  40.0],
			"z": [4.0,   12.0,  10.0,  15.0,  18.0],
		},
		"R_Forearm": {"x": [-8.0, -90.0, -80.0, -120.0, -145.0]},
		"spine": {"x": [3.0, 3.0, 5.0, 5.0, 5.0], "y": [0.0, 0.0, -6.0, -10.0, -14.0]},
		"chest": {"x": [-1.5, -1.5, -2.0, -2.0, -2.0], "y": [0.0, 0.0, -4.0, -7.0, -10.0]},
		"head":  {"x": [-2.0, -2.0, -4.0, -5.0, -5.0], "y": [3.0, 0.0, -8.0, -14.0, -18.0]},
		"hips":  {"y": [0.0, 0.0, -2.0, -3.0, -4.0]},
	}

	var anim := Animation.new()
	anim.length = 1.0
	anim.loop_mode = Animation.LOOP_NONE
	for bone_name in kf:
		if not bone_paths.has(bone_name):
			continue
		var track_idx := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track_idx, bone_paths[bone_name])
		anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_LINEAR)
		var axes: Dictionary = kf[bone_name]
		for ki in times.size():
			var ex := deg_to_rad(axes.get("x", [0.0, 0.0, 0.0, 0.0, 0.0])[ki])
			var ey := deg_to_rad(axes.get("y", [0.0, 0.0, 0.0, 0.0, 0.0])[ki])
			var ez := deg_to_rad(axes.get("z", [0.0, 0.0, 0.0, 0.0, 0.0])[ki])
			anim.rotation_track_insert_key(track_idx, times[ki], Quaternion.from_euler(Vector3(ex, ey, ez)))

	if bone_paths.has("hips"):
		var pos_t := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(pos_t, bone_paths["hips"])
		for ki in times.size():
			anim.position_track_insert_key(pos_t, times[ki], Vector3(0, 1.25, 0))

	var lib := pc._gltf_anim_player.get_animation_library("")
	if lib:
		var anim_name := "animation.bow_draw"
		if lib.has_animation(anim_name):
			lib.remove_animation(anim_name)
		lib.add_animation(anim_name, anim)


func rebuild_bow_release_animation() -> void:
	if not pc._gltf_anim_player:
		return
	var ref_name := ""
	for candidate in ["animation.axe_swing", "animation_axe_swing", "axe_swing"]:
		if pc._gltf_anim_player.has_animation(candidate):
			ref_name = candidate
			break
	if ref_name == "":
		return
	var ref_anim := pc._gltf_anim_player.get_animation(ref_name)
	var bone_paths: Dictionary = {}
	for track_idx in ref_anim.get_track_count():
		var path := ref_anim.track_get_path(track_idx)
		var parts := path.get_concatenated_names().split("/")
		bone_paths[parts[-1] if parts.size() > 0 else path.get_concatenated_names()] = path

	var times: PackedFloat32Array = PackedFloat32Array([0.0, 0.06, 0.15, 0.30, 0.45])
	var kf: Dictionary = {
		"R_UpperArm": {
			"x": [-78.0, -68.0, -55.0, -40.0, -30.0],
			"y": [40.0,  45.0,  30.0,  12.0,   0.0],
			"z": [18.0,  22.0,  14.0,   8.0,   4.0],
		},
		"R_Forearm": {"x": [-145.0, -60.0, -30.0, -15.0, -8.0]},
		"L_UpperArm": {
			"x": [-85.0, -88.0, -75.0, -50.0, -30.0],
			"y": [-15.0, -15.0, -10.0,  -5.0,   0.0],
			"z": [-20.0, -22.0, -14.0,  -8.0,  -4.0],
		},
		"L_Forearm": {"x": [-3.0, -3.0, -5.0, -7.0, -8.0]},
		"spine": {"x": [5.0, 6.0, 4.5, 3.5, 3.0], "y": [-14.0, -14.0, -8.0, -3.0, 0.0]},
		"chest": {"x": [-2.0, -2.5, -2.0, -1.5, -1.5], "y": [-10.0, -10.0, -6.0, -2.0, 0.0]},
		"head":  {"x": [-5.0, -5.0, -4.0, -3.0, -2.0], "y": [-18.0, -18.0, -10.0, -3.0, 3.0]},
		"hips":  {"y": [-4.0, -4.0, -2.0, -1.0, 0.0]},
	}

	var anim := Animation.new()
	anim.length = 0.45
	anim.loop_mode = Animation.LOOP_NONE
	for bone_name in kf:
		if not bone_paths.has(bone_name):
			continue
		var track_idx := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(track_idx, bone_paths[bone_name])
		anim.track_set_interpolation_type(track_idx, Animation.INTERPOLATION_LINEAR)
		var axes: Dictionary = kf[bone_name]
		for ki in times.size():
			var ex := deg_to_rad(axes.get("x", [0.0, 0.0, 0.0, 0.0, 0.0])[ki])
			var ey := deg_to_rad(axes.get("y", [0.0, 0.0, 0.0, 0.0, 0.0])[ki])
			var ez := deg_to_rad(axes.get("z", [0.0, 0.0, 0.0, 0.0, 0.0])[ki])
			anim.rotation_track_insert_key(track_idx, times[ki], Quaternion.from_euler(Vector3(ex, ey, ez)))

	if bone_paths.has("hips"):
		var pos_t := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(pos_t, bone_paths["hips"])
		for ki in times.size():
			anim.position_track_insert_key(pos_t, times[ki], Vector3(0, 1.25, 0))

	var lib := pc._gltf_anim_player.get_animation_library("")
	if lib:
		var anim_name := "animation.bow_release"
		if lib.has_animation(anim_name):
			lib.remove_animation(anim_name)
		lib.add_animation(anim_name, anim)


func build_melee_anim(anim_name: String, length: float, times: PackedFloat32Array, kf: Dictionary) -> void:
	if not pc._gltf_anim_player:
		return
	var ref_name := ""
	for candidate in ["animation.axe_swing", "animation_axe_swing", "axe_swing"]:
		if pc._gltf_anim_player.has_animation(candidate):
			ref_name = candidate
			break
	if ref_name == "":
		return
	var ref_anim := pc._gltf_anim_player.get_animation(ref_name)
	var bone_paths: Dictionary = {}
	for track_idx in ref_anim.get_track_count():
		var path := ref_anim.track_get_path(track_idx)
		var parts := path.get_concatenated_names().split("/")
		bone_paths[parts[-1] if parts.size() > 0 else path.get_concatenated_names()] = path

	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_NONE
	var n_keys := times.size()
	var zeroes: Array = []
	for _i in n_keys:
		zeroes.append(0.0)
	for bone_name in kf:
		if not bone_paths.has(bone_name):
			continue
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, bone_paths[bone_name])
		anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
		var axes: Dictionary = kf[bone_name]
		for ki in n_keys:
			var ex := deg_to_rad(axes.get("x", zeroes)[ki])
			var ey := deg_to_rad(axes.get("y", zeroes)[ki])
			var ez := deg_to_rad(axes.get("z", zeroes)[ki])
			anim.rotation_track_insert_key(t, times[ki], Quaternion.from_euler(Vector3(ex, ey, ez)))
	if bone_paths.has("hips"):
		var pt := anim.add_track(Animation.TYPE_POSITION_3D)
		anim.track_set_path(pt, bone_paths["hips"])
		for ki in n_keys:
			anim.position_track_insert_key(pt, times[ki], Vector3(0, 1.25, 0))
	var lib := pc._gltf_anim_player.get_animation_library("")
	if lib:
		var full_name := "animation." + anim_name
		if lib.has_animation(full_name):
			lib.remove_animation(full_name)
		lib.add_animation(full_name, anim)


func rebuild_club_smash_animation() -> void:
	var times := PackedFloat32Array([0.0, 0.18, 0.42, 0.62, 0.80])
	var kf: Dictionary = {
		"R_UpperArm": {
			"x": [-30.0, -60.0, -48.0, -40.0, -30.0],
			"y": [0.0, 20.0, -28.0, -15.0, 0.0],
			"z": [0.0, 22.0, -30.0, -16.0, 0.0],
		},
		"R_Forearm": {"x": [-40.0, -25.0, -55.0, -45.0, -40.0]},
		"L_UpperArm": {
			"x": [-45.0, -68.0, -55.0, -46.0, -45.0],
			"y": [0.0, 22.0, -30.0, -16.0, 0.0],
			"z": [12.0, 36.0, -34.0, -16.0, 12.0],
		},
		"L_Forearm": {"x": [-55.0, -38.0, -68.0, -52.0, -55.0]},
		"spine":  {"x": [3.0, 3.0, 3.0, 3.0, 3.0], "y": [0.0, 14.0, -16.0, -10.0, 0.0]},
		"chest":  {"x": [-1.5, -1.5, -1.5, -1.5, -1.5], "y": [0.0, 6.0, -8.0, -5.0, 0.0]},
		"head":   {"x": [-2.0, -2.0, -2.0, -2.0, -2.0], "y": [0.0, 4.0, -6.0, -3.0, 0.0]},
		"hips":   {"y": [0.0, 4.0, -5.0, -3.0, 0.0]},
		"R_Thigh": {"x": [0.0, 0.0, 0.0, 0.0, 0.0]},
		"L_Thigh": {"x": [0.0, 0.0, 0.0, 0.0, 0.0]},
		"R_Calf":  {"x": [0.0, 0.0, 0.0, 0.0, 0.0]},
		"L_Calf":  {"x": [0.0, 0.0, 0.0, 0.0, 0.0]},
	}
	build_melee_anim("club_smash", 0.80, times, kf)


func rebuild_sword_slash_animation() -> void:
	var times := PackedFloat32Array([0.0, 0.14, 0.32, 0.50, 0.72])
	var kf: Dictionary = {
		"R_UpperArm": {
			"x": [-30.0, -80.0, -45.0, -22.0, -30.0],
			"y": [0.0, 22.0, -18.0, -8.0, 0.0],
			"z": [0.0, 28.0, -22.0, -10.0, 0.0],
		},
		"R_Forearm": {"x": [-8.0, -40.0, -50.0, -28.0, -8.0]},
		"L_UpperArm": {
			"x": [-30.0, -70.0, -50.0, -28.0, -30.0],
			"y": [0.0, 18.0, -20.0, -10.0, 0.0],
			"z": [0.0, 32.0, -28.0, -14.0, 0.0],
		},
		"L_Forearm": {"x": [-8.0, -35.0, -55.0, -30.0, -8.0]},
		"spine":  {"x": [3.0, 3.0, 3.0, 3.0, 3.0], "y": [0.0, 12.0, -14.0, -8.0, 0.0]},
		"chest":  {"x": [-1.5, -1.5, -1.5, -1.5, -1.5], "y": [0.0, 8.0, -10.0, -5.0, 0.0]},
		"head":   {"x": [-2.0, -2.0, -2.0, -2.0, -2.0], "y": [0.0, 5.0, -8.0, -4.0, 0.0]},
		"hips":   {"y": [0.0, 3.0, -4.0, -2.0, 0.0]},
		"R_Thigh": {"x": [0.0, 0.0, 0.0, 0.0, 0.0]},
		"L_Thigh": {"x": [0.0, 0.0, 0.0, 0.0, 0.0]},
		"R_Calf":  {"x": [0.0, 0.0, 0.0, 0.0, 0.0]},
		"L_Calf":  {"x": [0.0, 0.0, 0.0, 0.0, 0.0]},
	}
	build_melee_anim("sword_slash", 0.72, times, kf)


# ===================================================================
# FLASH & TEXTURES
# ===================================================================

func gltf_flash(col: Color) -> void:
	for mi in pc._gltf_all_meshes:
		var mat := mi.get_active_material(0)
		if mat is ShaderMaterial:
			mat.set_shader_parameter("rim_color", col)
			mat.set_shader_parameter("rim_intensity", 1.0)
			mat.set_shader_parameter("rim_power", 1.5)
		elif mat is StandardMaterial3D:
			mat.emission_enabled = true
			mat.emission = col
			mat.emission_energy_multiplier = 2.0


func gltf_clear_flash() -> void:
	for mi in pc._gltf_all_meshes:
		var mat := mi.get_active_material(0)
		if mat is ShaderMaterial:
			mat.set_shader_parameter("rim_color", Color(1.0, 1.0, 1.0))
			mat.set_shader_parameter("rim_intensity", 0.0)
			mat.set_shader_parameter("rim_power", 2.0)
		elif mat is StandardMaterial3D:
			mat.emission_enabled = false
			mat.emission = Color.BLACK


func apply_pahlevan_texture() -> void:
	var tex_path := "res://models/player/Pahlevan/Pahlevan_tripo_node_641e01bc-4c81-4461-be84-6538ef0e1a1a.jpg"
	if not ResourceLoader.exists(tex_path):
		if _DEBUG_LOG: print("[PLAYER MODEL] Pahlevan texture not found: ", tex_path)
		return
	var tex: Texture2D = load(tex_path)
	if not tex:
		return
	var shader_res: Shader = load("res://shaders/oathbound_character.gdshader") as Shader
	if shader_res:
		for mi in pc._gltf_all_meshes:
			if not mi.mesh:
				continue
			for surf_idx in mi.mesh.get_surface_count():
				var smat := ShaderMaterial.new()
				smat.shader = shader_res
				smat.set_shader_parameter("albedo_texture", tex)
				smat.set_shader_parameter("roughness_value", 0.75)
				mi.set_surface_override_material(surf_idx, smat)
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.roughness = 0.75
		mat.metallic = 0.0
		for mi in pc._gltf_all_meshes:
			mi.material_override = mat
	if _DEBUG_LOG: print("[PLAYER MODEL] Applied Pahlevan texture+shader to %d meshes" % pc._gltf_all_meshes.size())


func apply_tripo_player_texture() -> void:
	var tex_path := "res://models/player/Lowpolyvikingwithaxe/barbarian+3d+model_barbarian3dmodel_basecolor.jpg"
	if not ResourceLoader.exists(tex_path):
		if _DEBUG_LOG: print("[PLAYER MODEL] Tripo barbarian basecolor not found")
		return
	var tex := load(tex_path) as Texture2D
	if not tex:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for mi in pc._gltf_all_meshes:
		mi.material_override = mat
		mi.visible = true
	if _DEBUG_LOG: print("[PLAYER MODEL] Applied Tripo barbarian texture to %d meshes" % pc._gltf_all_meshes.size())


func apply_viking_texture() -> void:
	var glb_path := "res://models/player/Lowpolyviking/low-poly+viking+3d+model.glb"
	if not ResourceLoader.exists(glb_path):
		glb_path = "res://models/player/Lowpolyviking/low-poly+viking+3d+model (1).glb"
	if not ResourceLoader.exists(glb_path):
		if _DEBUG_LOG: print("[PLAYER MODEL] Viking GLB not found")
		return

	var glb_scene: PackedScene = load(glb_path) as PackedScene
	if not glb_scene:
		return

	var glb_inst := glb_scene.instantiate()

	var glb_meshes: Array[MeshInstance3D] = []
	collect_mesh_instances(glb_inst, glb_meshes)

	var glb_materials: Array[Material] = []
	for mi in glb_meshes:
		if not mi.mesh:
			continue
		for surf_idx in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(surf_idx)
			if mat:
				glb_materials.append(mat)

	if _DEBUG_LOG: print("[PLAYER MODEL] Extracted %d materials from GLB" % glb_materials.size())

	var mat_idx := 0
	for mi in pc._gltf_all_meshes:
		mi.visible = true
		if not mi.mesh:
			continue
		for surf_idx in mi.mesh.get_surface_count():
			if mat_idx < glb_materials.size():
				mi.set_surface_override_material(surf_idx, glb_materials[mat_idx])
				mat_idx += 1
			else:
				if not glb_materials.is_empty():
					mi.set_surface_override_material(surf_idx, glb_materials[glb_materials.size() - 1])

	if _DEBUG_LOG: print("[PLAYER MODEL] Applied %d materials to FBX meshes (%d surfaces)" % [glb_materials.size(), mat_idx])

	glb_inst.queue_free()


func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := find_skeleton(child)
		if found:
			return found
	return null


func get_mesh_height(meshes: Array[MeshInstance3D]) -> float:
	var min_y := 99999.0
	var max_y := -99999.0
	for mi in meshes:
		if not mi.mesh:
			continue
		for surf_idx in mi.mesh.get_surface_count():
			var arrays = mi.mesh.surface_get_arrays(surf_idx)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				min_y = minf(min_y, v.y)
				max_y = maxf(max_y, v.y)
	return max_y - min_y


func get_mesh_center_y(meshes: Array[MeshInstance3D]) -> float:
	var min_y := 99999.0
	var max_y := -99999.0
	for mi in meshes:
		if not mi.mesh:
			continue
		for surf_idx in mi.mesh.get_surface_count():
			var arrays = mi.mesh.surface_get_arrays(surf_idx)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				min_y = minf(min_y, v.y)
				max_y = maxf(max_y, v.y)
	return (min_y + max_y) * 0.5


func apply_oathbound_shader() -> void:
	var shader_res := load("res://shaders/oathbound_character.gdshader")
	if not shader_res:
		return
	for mi in pc._gltf_all_meshes:
		if not mi.mesh:
			continue
		for surf_idx in mi.mesh.get_surface_count():
			var old_mat := mi.get_active_material(surf_idx)
			var shader_mat := ShaderMaterial.new()
			shader_mat.shader = shader_res
			if old_mat is StandardMaterial3D:
				var std := old_mat as StandardMaterial3D
				if std.albedo_texture:
					shader_mat.set_shader_parameter("albedo_texture", std.albedo_texture)
				else:
					var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
					img.set_pixel(0, 0, std.albedo_color)
					var fallback_tex := ImageTexture.create_from_image(img)
					shader_mat.set_shader_parameter("albedo_texture", fallback_tex)
			mi.set_surface_override_material(surf_idx, shader_mat)
