class_name PlayerCombat
extends Node
## Combat sub-module for PlayerController: bow, melee, harvestables, damage, death.

var pc: PlayerController

const MELEE_HIT_DELAY := 0.18
const BOW_MAX_DRAW_TIME := 1.8
const BOW_MIN_DAMAGE_MULT := 0.2
const BOW_MAX_DAMAGE_MULT := 2.0
const BOW_RETICLE_MAX_RADIUS := 60.0
const BOW_RETICLE_MIN_RADIUS := 6.0
const ARROW_GRAVITY := 9.8
const ARROW_MAX_LIFETIME := 5.0

const _DamageNumber = preload("res://scripts/ui/damage_number.gd")
const _LootDrop = preload("res://scripts/items/loot_drop.gd")


# --- Bow ---
func is_bow_weapon(wpn: StringName) -> bool:
	if wpn == &"crude_bow":
		return true
	var data: Dictionary = ItemDatabase.get_item(wpn)
	return str(data.get("name", "")).to_lower().contains("bow")


func tick_bow_draw(delta: float, holding_draw: bool) -> void:
	if holding_draw and not pc._is_attacking and not pc._is_dodging:
		if not pc._bow_drawing:
			pc._bow_drawing = true
			pc._bow_tension = 0.0
			if not pc._weapon_drawn:
				pc._draw_weapon()
			show_bow_reticle()
			start_bow_creak()
		var draw_mult := 1.15 if has_affix(&"rapid_draw") else 1.0
		pc._bow_tension = minf(pc._bow_tension + delta * draw_mult, BOW_MAX_DRAW_TIME)
		update_bow_creak(delta)
		update_bow_draw_sprite()
	elif pc._bow_drawing:
		cancel_bow_draw()

	if pc._bow_drawing and pc._bow_reticle and pc._bow_reticle.visible:
		pc._bow_reticle.queue_redraw()


func start_bow_creak() -> void:
	if not pc._bow_creak_player:
		pc._bow_creak_player = AudioStreamPlayer3D.new()
		pc._bow_creak_player.bus = &"SFX"
		pc._bow_creak_player.max_distance = 20.0
		pc._bow_creak_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
		pc.add_child(pc._bow_creak_player)
	var stream := AudioManager.get_random_stream("bow_creak")
	if not stream:
		return
	pc._bow_creak_player.stream = stream
	pc._bow_creak_player.volume_db = -4.0
	pc._bow_creak_player.pitch_scale = 1.0
	pc._bow_creak_player.global_position = pc.global_position
	pc._bow_creak_player.play()


func update_bow_creak(_delta: float) -> void:
	if pc._bow_creak_player:
		pc._bow_creak_player.global_position = pc.global_position


func stop_bow_creak() -> void:
	if pc._bow_creak_player and pc._bow_creak_player.playing:
		pc._bow_creak_player.stop()


func cancel_bow_draw() -> void:
	pc._bow_drawing = false
	pc._bow_tension = 0.0
	hide_bow_reticle()
	stop_bow_creak()
	if pc._bow_arrow_node:
		pc._bow_arrow_node.visible = false
	pc._revert_to_idle_sprite()


func fire_bow() -> void:
	if not pc._bow_drawing:
		return
	var bow_id: StringName = Inventory.get_equipped("bow")
	var bow_data: Dictionary = ItemDatabase.get_item(bow_id) if bow_id != &"" else {}
	var tension_pct := clampf(pc._bow_tension / BOW_MAX_DRAW_TIME, 0.0, 1.0)
	var base_damage: float = float(bow_data.get("damage", 8.0)) * randf_range(0.7, 1.3)
	var damage_mult := lerpf(BOW_MIN_DAMAGE_MULT, BOW_MAX_DAMAGE_MULT, tension_pct)
	var final_damage: float = base_damage * damage_mult
	var wpn_stamina: float = float(bow_data.get("stamina_cost", 4.0))
	var wpn_knockback: float = float(bow_data.get("knockback", 10.0)) * tension_pct

	pc._bow_drawing = false
	pc._bow_tension = 0.0
	hide_bow_reticle()
	stop_bow_creak()
	if pc._bow_arrow_node:
		pc._bow_arrow_node.visible = false

	if not pc._can_spend_stamina(wpn_stamina):
		pc._revert_to_idle_sprite()
		return
	pc._spend_stamina(wpn_stamina)

	start_attack_animation()

	var cam: Camera3D = pc._spring_arm.get_child(0) if pc._spring_arm.get_child_count() > 0 else null
	if not cam:
		return

	var reticle_screen := get_reticle_center()
	var ray_origin := cam.project_ray_origin(reticle_screen)
	var ray_dir := cam.project_ray_normal(reticle_screen)
	var aim_target := ray_origin + ray_dir * 50.0

	var cam_right := cam.global_transform.basis.x
	var spawn_pos := pc.global_position + Vector3.UP * 1.6 + cam_right * 0.6
	var aim_dir := (aim_target - spawn_pos).normalized()
	var affixes := get_active_affixes()
	var crit_chance := 5.0 + pc.base_dexterity * 0.5
	var crit_dmg_mult := (150.0 + pc.base_strength * 2.0) / 100.0
	if affixes.has(&"steady_aim") and pc.velocity.length() < 0.5:
		crit_chance += 12.0
	if randf() < crit_chance / 100.0:
		final_damage *= crit_dmg_mult

	var arrow_speed := lerpf(8.0, 32.0, tension_pct)
	if affixes.has(&"rapid_draw"):
		arrow_speed *= 1.15
	var launch_dir := aim_dir + Vector3.UP * lerpf(0.08, 0.02, tension_pct)
	spawn_arrow(spawn_pos, launch_dir.normalized() * arrow_speed, final_damage, wpn_knockback, tension_pct)
	AudioManager.play_sfx_at("arrow_swoosh", spawn_pos, -2.0)

	if affixes.has(&"multishot") and randf() < 0.20:
		var offset_dir := cam_right * 0.3
		spawn_arrow(spawn_pos + offset_dir, launch_dir.normalized() * arrow_speed, final_damage, wpn_knockback, tension_pct)
		AudioManager.play_sfx_at("arrow_swoosh", spawn_pos, -4.0)
	if affixes.has(&"quiver_mastery") and randf() < 0.15:
		var offset_dir := cam_right * -0.3
		spawn_arrow(spawn_pos + offset_dir, launch_dir.normalized() * arrow_speed, final_damage, wpn_knockback, tension_pct)


func spawn_arrow(origin: Vector3, vel: Vector3, damage: float, knockback: float, tension_pct: float = 1.0) -> void:
	var arrow := Node3D.new()
	arrow.name = "Arrow"
	arrow.global_position = origin

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "ArrowMesh"
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 0.8)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.3, 0.12)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.set_surface_override_material(0, mat)
	arrow.add_child(mesh_inst)

	var tip_inst := MeshInstance3D.new()
	tip_inst.name = "Tip"
	var tip_mesh := BoxMesh.new()
	tip_mesh.size = Vector3(0.08, 0.08, 0.12)
	tip_inst.mesh = tip_mesh
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(0.3, 0.3, 0.3)
	tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tip_inst.set_surface_override_material(0, tip_mat)
	tip_inst.position.z = -0.42
	arrow.add_child(tip_inst)

	var fletch_inst := MeshInstance3D.new()
	fletch_inst.name = "Fletch"
	var fletch_mesh := BoxMesh.new()
	fletch_mesh.size = Vector3(0.1, 0.1, 0.1)
	fletch_inst.mesh = fletch_mesh
	var fletch_mat := StandardMaterial3D.new()
	fletch_mat.albedo_color = Color(0.8, 0.8, 0.75)
	fletch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fletch_inst.set_surface_override_material(0, fletch_mat)
	fletch_inst.position.z = 0.38
	arrow.add_child(fletch_inst)

	arrow.set_meta("velocity", vel)
	arrow.set_meta("damage", damage)
	arrow.set_meta("knockback", knockback)
	arrow.set_meta("tension", tension_pct)
	arrow.set_meta("lifetime", 0.0)
	arrow.set_meta("hit", false)
	arrow.add_to_group(&"arrows")

	pc.get_tree().current_scene.add_child(arrow)


func tick_arrows(delta: float) -> void:
	for node: Node in pc.get_tree().get_nodes_in_group(&"arrows"):
		var arrow := node as Node3D
		if not arrow or arrow.get_meta("hit", false):
			continue

		var vel: Vector3 = arrow.get_meta("velocity") as Vector3
		var t_pct: float = arrow.get_meta("tension", 1.0) as float
		var gravity := lerpf(ARROW_GRAVITY * 2.0, ARROW_GRAVITY * 0.4, t_pct)
		vel.y -= gravity * delta
		arrow.set_meta("velocity", vel)

		var old_pos := arrow.global_position
		arrow.global_position += vel * delta
		var new_pos := arrow.global_position

		if vel.length_squared() > 0.5:
			var target_pos := arrow.global_position + vel.normalized()
			arrow.look_at(target_pos, Vector3.UP)

		var lifetime: float = arrow.get_meta("lifetime") as float + delta
		arrow.set_meta("lifetime", lifetime)

		if arrow.global_position.y < 0.1:
			arrow.set_meta("hit", true)
			stick_arrow(arrow)
			continue

		if lifetime > ARROW_MAX_LIFETIME:
			arrow.queue_free()
			continue

		var dmg: float = arrow.get_meta("damage") as float
		var kb: float = arrow.get_meta("knockback") as float
		var travel := new_pos - old_pos
		var travel_len := travel.length()
		var step_count := maxi(1, ceili(travel_len / 0.4))
		for enemy_node: Node in pc.get_tree().get_nodes_in_group(&"enemies"):
			var enemy := enemy_node as Node3D
			if not enemy:
				continue
			var cap_radius := 0.5
			var cap_height := 1.6
			var cap_y_offset := 0.8
			var visual_r: float = enemy.get("arrow_hit_radius") as float if enemy.get("arrow_hit_radius") != null else -1.0
			var visual_h: float = enemy.get("arrow_hit_height") as float if enemy.get("arrow_hit_height") != null else -1.0
			var visual_y: float = enemy.get("arrow_hit_y_offset") as float if enemy.get("arrow_hit_y_offset") != null else -1.0
			if visual_r > 0.0 and visual_h > 0.0:
				cap_radius = visual_r
				cap_height = visual_h
				cap_y_offset = visual_y
			else:
				var col_shape := enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
				if col_shape and col_shape.shape is CapsuleShape3D:
					var cap: CapsuleShape3D = col_shape.shape as CapsuleShape3D
					cap_radius = cap.radius
					cap_height = cap.height
					cap_y_offset = col_shape.position.y
			var cap_bottom := enemy.global_position.y + cap_y_offset - cap_height * 0.5
			var cap_top := enemy.global_position.y + cap_y_offset + cap_height * 0.5
			var hit_margin := cap_radius + 0.3
			var did_hit := false
			var hit_pos := new_pos
			for si in step_count + 1:
				var t := float(si) / float(step_count)
				var sample := old_pos.lerp(new_pos, t)
				var clamped_y := clampf(sample.y, cap_bottom, cap_top)
				var closest_axis := Vector3(enemy.global_position.x, clamped_y, enemy.global_position.z)
				if sample.distance_to(closest_axis) < hit_margin:
					did_hit = true
					hit_pos = sample
					break
			if did_hit:
				arrow.global_position = hit_pos
				var hit_height := hit_pos.y - enemy.global_position.y
				var is_headshot := hit_height > cap_height * 0.7
				var head_mult := 1.3
				if is_headshot and has_affix(&"precision"):
					head_mult = 1.5
				var final_dmg := dmg * head_mult if is_headshot else dmg
				if has_affix(&"sniper"):
					var dist_to_enemy := pc.global_position.distance_to(enemy.global_position)
					if dist_to_enemy > 15.0:
						final_dmg *= 1.25
				if enemy.has_method("take_damage"):
					enemy.take_damage(final_dmg, pc)
					pc._set_target_creature(enemy)
					_DamageNumber.spawn(pc.get_tree(), enemy.global_position + Vector3.UP * 1.5, final_dmg, is_headshot)
				if has_affix(&"frost_arrow") and randf() < 0.35 and enemy.has_method("apply_slow"):
					enemy.apply_slow(0.65, 3.0)
				if has_affix(&"poison_tip") and randf() < 0.30 and enemy.has_method("apply_poison"):
					var mhp: float = float(enemy.get("max_health")) if enemy.get("max_health") != null else 100.0
					enemy.apply_poison(mhp * 0.02, 4.0, pc)
				if has_affix(&"explosive") and randf() < 0.10:
					var aoe_dmg := dmg * 0.4
					for aoe_node: Node in pc.get_tree().get_nodes_in_group(&"enemies"):
						var aoe_e := aoe_node as Node3D
						if not aoe_e or aoe_e == enemy:
							continue
						if enemy.global_position.distance_to(aoe_e.global_position) < 4.0:
							if aoe_e.has_method("take_damage"):
								aoe_e.take_damage(aoe_dmg, pc)
								_DamageNumber.spawn(pc.get_tree(), aoe_e.global_position + Vector3.UP * 1.0, aoe_dmg)
				if kb > 0.0 and enemy is CharacterBody3D:
					var kb_dir := (enemy.global_position - hit_pos).normalized()
					kb_dir.y = 0.0
					(enemy as CharacterBody3D).velocity += kb_dir * kb * 0.1
				var pierce_count: int = arrow.get_meta("pierce_count", 0) as int
				if has_affix(&"piercing") and pierce_count < 1:
					arrow.set_meta("pierce_count", pierce_count + 1)
				else:
					arrow.set_meta("hit", true)
					stick_arrow(arrow)
				break

		if not arrow.get_meta("hit", false):
			for fish_node: Node in pc.get_tree().get_nodes_in_group(&"carried_fish"):
				var fish := fish_node as Node3D
				if not fish:
					continue
				if arrow.global_position.distance_to(fish.global_position) < 1.5:
					arrow.set_meta("hit", true)
					var owner_creature = fish.get_meta("owner_creature", null)
					if owner_creature and owner_creature.has_method("drop_carried_fish"):
						owner_creature.drop_carried_fish()
					stick_arrow(arrow)
					break

		if not arrow.get_meta("hit", false):
			for res_node: Node in pc.get_tree().get_nodes_in_group(&"interactables"):
				var obj := res_node as Node3D
				if not obj:
					continue
				if arrow.global_position.distance_to(obj.global_position + Vector3.UP * 0.5) < 1.5:
					if obj.has_meta("harvestable"):
						arrow.set_meta("hit", true)
						hit_harvestable(obj, dmg)
						stick_arrow(arrow)
						break


func stick_arrow(arrow: Node3D) -> void:
	arrow.remove_from_group(&"arrows")
	var tween := arrow.create_tween()
	tween.tween_interval(4.0)
	tween.tween_callback(arrow.queue_free)


func update_bow_draw_sprite() -> void:
	if pc._gltf_anim_player:
		return
	if pc._bow_attack_frames.is_empty() or not pc._player_sprite:
		return
	var dir := pc._get_camera_relative_dir()
	if not pc._bow_attack_frames.has(dir):
		return
	var frames_arr: Array = Array(pc._bow_attack_frames[dir])
	if frames_arr.is_empty():
		return
	var tension_pct := clampf(pc._bow_tension / BOW_MAX_DRAW_TIME, 0.0, 1.0)
	var draw_frames := int(ceilf(frames_arr.size() * 0.6))
	var frame_idx := int(tension_pct * float(draw_frames - 1))
	frame_idx = clampi(frame_idx, 0, draw_frames - 1)
	var tex := frames_arr[frame_idx] as Texture2D
	if tex:
		pc._set_player_sprite_tex(tex)


func show_bow_reticle() -> void:
	if not pc._bow_reticle and pc._hud_root:
		pc._bow_reticle = Control.new()
		pc._bow_reticle.name = "BowReticle"
		pc._bow_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pc._bow_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc._bow_reticle.draw.connect(draw_bow_reticle)
		pc._hud_root.add_child(pc._bow_reticle)
	if pc._bow_reticle:
		pc._bow_reticle.visible = true


func hide_bow_reticle() -> void:
	if pc._bow_reticle:
		pc._bow_reticle.visible = false


func get_reticle_center() -> Vector2:
	var cam: Camera3D = pc._spring_arm.get_child(0) if pc._spring_arm.get_child_count() > 0 else null
	if not cam or not cam.is_inside_tree():
		return pc._bow_reticle.get_viewport_rect().size * 0.5 if pc._bow_reticle else Vector2.ZERO
	var head_world := pc.global_position + Vector3.UP * 1.8
	var screen_pos := cam.unproject_position(head_world)
	return screen_pos + Vector2(110, -120)


func draw_bow_reticle() -> void:
	if not pc._bow_reticle or not pc._bow_drawing:
		return
	var center := get_reticle_center()
	var tension_pct := clampf(pc._bow_tension / BOW_MAX_DRAW_TIME, 0.0, 1.0)
	var radius := lerpf(BOW_RETICLE_MAX_RADIUS, BOW_RETICLE_MIN_RADIUS, tension_pct)

	var ring_color := Color(1.0, 1.0, 1.0, 0.7)
	if tension_pct >= 1.0:
		ring_color = Color(1.0, 0.3, 0.2, 0.9)

	var point_count := 48
	var ring_points := PackedVector2Array()
	for i in range(point_count + 1):
		var angle := TAU * float(i) / float(point_count)
		ring_points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	for i in range(point_count):
		pc._bow_reticle.draw_line(ring_points[i], ring_points[i + 1], ring_color, 1.5, true)

	var ch_size := 5.0
	var ch_gap := 2.0
	var ch_color := Color(1.0, 1.0, 1.0, 0.9)
	pc._bow_reticle.draw_line(center + Vector2(-ch_size - ch_gap, 0), center + Vector2(-ch_gap, 0), ch_color, 1.5)
	pc._bow_reticle.draw_line(center + Vector2(ch_gap, 0), center + Vector2(ch_size + ch_gap, 0), ch_color, 1.5)
	pc._bow_reticle.draw_line(center + Vector2(0, -ch_size - ch_gap), center + Vector2(0, -ch_gap), ch_color, 1.5)
	pc._bow_reticle.draw_line(center + Vector2(0, ch_gap), center + Vector2(0, ch_size + ch_gap), ch_color, 1.5)

	pc._bow_reticle.draw_circle(center, 1.5, ch_color)

	if tension_pct > 0.01 and tension_pct < 1.0:
		var arc_radius := radius + 4.0
		var arc_color := Color(0.9, 0.75, 0.2, 0.8)
		var arc_start := -PI * 0.5
		var arc_end := arc_start + TAU * tension_pct
		var arc_points := PackedVector2Array()
		var arc_segs := int(point_count * tension_pct) + 2
		for i in range(arc_segs):
			var t := float(i) / float(arc_segs - 1)
			var a := lerpf(arc_start, arc_end, t)
			arc_points.append(center + Vector2(cos(a), sin(a)) * arc_radius)
		for i in range(arc_points.size() - 1):
			pc._bow_reticle.draw_line(arc_points[i], arc_points[i + 1], arc_color, 2.0, true)


func start_attack_animation() -> void:
	if pc._gltf_anim_player:
		pc._is_jumping = false
		pc._is_flipping = false
		pc._is_attacking = true
		if not pc._weapon_drawn:
			pc._draw_weapon()
		var wclass := ItemDatabase.get_weapon_class(pc.equipped_weapon)
		var wpn_speed: float = get_weapon_stat("attack_speed", 0.6)
		if has_affix(&"rapid_strikes") or has_affix(&"rapid_chop") or has_affix(&"quick_strike"):
			wpn_speed *= 0.88
		pc._gltf_attack_timer = wpn_speed
		match wclass:
			"bow":
				pc._gltf_attack_timer = 0.45
				pc._gltf_attack_anim = "bow_release"
			"axe":
				pc._gltf_attack_anim = "axe_swing"
			"sword":
				pc._gltf_attack_anim = "sword_slash"
			"pickaxe":
				pc._gltf_attack_anim = "club_smash"
			_:
				var roll := randf()
				if roll < 0.33:
					pc._gltf_attack_anim = "kick"
				elif roll < 0.66:
					pc._gltf_attack_anim = "punch"
				else:
					pc._gltf_attack_anim = "punch_alt"
				pc._unarmed_attack_time = 0.0
				pc._unarmed_attack_duration = pc._gltf_attack_timer
		AudioManager.play_sfx("arrow_swoosh", -6.0, 0.15)
		pc._gltf_current_anim = ""
		fit_attack_anim_to_timer()
		return

	if pc.equipped_weapon == &"stone_pickaxe":
		pc._attack_frames = pc._pickaxe_attack_frames if not pc._pickaxe_attack_frames.is_empty() else pc._weapon_attack_frames
		pc._current_attack_frame_duration = 0.07  # ATTACK_FRAME_DURATION_TOOL
	elif pc.equipped_weapon == &"crude_bow":
		pc._attack_frames = pc._bow_attack_frames if not pc._bow_attack_frames.is_empty() else pc._weapon_attack_frames
		pc._current_attack_frame_duration = 0.08  # ATTACK_FRAME_DURATION_BOW
	elif pc.equipped_weapon == &"stone_axe":
		pc._attack_frames = pc._weapon_attack_frames if not pc._weapon_attack_frames.is_empty() else pc._fist_frames
		pc._current_attack_frame_duration = 0.07
	elif pc.equipped_weapon == &"fists" or pc.equipped_weapon == &"":
		if not pc._kick_frames_attack.is_empty() and randf() < 0.3:
			pc._attack_frames = pc._kick_frames_attack
		else:
			pc._attack_frames = pc._fist_frames if not pc._fist_frames.is_empty() else pc._weapon_attack_frames
		pc._current_attack_frame_duration = 0.05  # ATTACK_FRAME_DURATION_FIST
	else:
		var item_data: Dictionary = ItemDatabase.get_item(pc.equipped_weapon)
		var item_type: String = str(item_data.get("type", ""))
		var item_name: String = str(item_data.get("name", "")).to_lower()
		if item_type != "weapon" and item_type != "tool":
			if not pc._kick_frames_attack.is_empty() and randf() < 0.3:
				pc._attack_frames = pc._kick_frames_attack
			else:
				pc._attack_frames = pc._fist_frames if not pc._fist_frames.is_empty() else pc._weapon_attack_frames
			pc._current_attack_frame_duration = 0.05
		else:
			if item_name.contains("sword") and not pc._sword_attack_frames.is_empty():
				pc._attack_frames = pc._sword_attack_frames
			elif item_name.contains("pickaxe") and not pc._pickaxe_attack_frames.is_empty():
				pc._attack_frames = pc._pickaxe_attack_frames
			elif item_name.contains("axe") and not pc._weapon_attack_frames.is_empty():
				pc._attack_frames = pc._weapon_attack_frames
			elif item_name.contains("bow") and not pc._bow_attack_frames.is_empty():
				pc._attack_frames = pc._bow_attack_frames
			elif not pc._weapon_attack_frames.is_empty():
				pc._attack_frames = pc._weapon_attack_frames
			else:
				pc._attack_frames = pc._fist_frames
			pc._current_attack_frame_duration = 0.07

	if pc._attack_frames.is_empty():
		return
	pc._current_attack_dir = pc._get_camera_relative_dir()
	if not pc._attack_frames.has(pc._current_attack_dir):
		return
	pc._is_jumping = false
	pc._is_flipping = false
	pc._is_attacking = true
	pc._attack_frame_idx = 0
	pc._attack_frame_timer = pc._current_attack_frame_duration
	var frames_arr: Array = Array(pc._attack_frames[pc._current_attack_dir])
	if not frames_arr.is_empty():
		var tex := frames_arr[0] as Texture2D
		if tex and pc._player_sprite:
			pc._set_player_sprite_tex(tex)


func fit_attack_anim_to_timer() -> void:
	if not pc._gltf_anim_player or pc._gltf_attack_anim.is_empty() or pc._gltf_attack_timer <= 0.0:
		return
	var aliases := {
		"axe_swing": ["chop", "axe_swing"],
		"club_smash": ["chop", "club_smash"],
		"sword_slash": ["kick", "sword_slash"],
		"kick": ["kick"],
		"punch": ["kick", "punch"],
		"punch_alt": ["kick", "punch_alt"],
		"bow_release": ["bow_release"],
	}
	var names_to_try: Array[String] = []
	if aliases.has(pc._gltf_attack_anim):
		for alias in aliases[pc._gltf_attack_anim]:
			names_to_try.append(alias)
	names_to_try.append(pc._gltf_attack_anim)
	for base_name in names_to_try:
		for candidate in ["animation." + base_name, "animation_" + base_name, base_name]:
			if pc._gltf_anim_player.has_animation(candidate):
				var anim: Animation = pc._gltf_anim_player.get_animation(candidate)
				if anim and anim.length > 0.0:
					pc._gltf_anim_player.speed_scale = anim.length / pc._gltf_attack_timer
					pc._gltf_anim_player.play(candidate)
					pc._gltf_current_anim = candidate
				return

	if pc.equipped_weapon == &"stone_pickaxe":
		pc._attack_frames = pc._pickaxe_attack_frames if not pc._pickaxe_attack_frames.is_empty() else pc._weapon_attack_frames
		pc._current_attack_frame_duration = 0.07
	elif pc.equipped_weapon == &"crude_bow":
		pc._attack_frames = pc._bow_attack_frames if not pc._bow_attack_frames.is_empty() else pc._weapon_attack_frames
		pc._current_attack_frame_duration = 0.08
	elif pc.equipped_weapon == &"stone_axe":
		pc._attack_frames = pc._weapon_attack_frames if not pc._weapon_attack_frames.is_empty() else pc._fist_frames
		pc._current_attack_frame_duration = 0.07
	elif pc.equipped_weapon == &"fists" or pc.equipped_weapon == &"":
		if not pc._kick_frames_attack.is_empty() and randf() < 0.3:
			pc._attack_frames = pc._kick_frames_attack
		else:
			pc._attack_frames = pc._fist_frames if not pc._fist_frames.is_empty() else pc._weapon_attack_frames
		pc._current_attack_frame_duration = 0.05
	else:
		var item_data: Dictionary = ItemDatabase.get_item(pc.equipped_weapon)
		var item_type: String = str(item_data.get("type", ""))
		var item_name: String = str(item_data.get("name", "")).to_lower()
		if item_type != "weapon" and item_type != "tool":
			if not pc._kick_frames_attack.is_empty() and randf() < 0.3:
				pc._attack_frames = pc._kick_frames_attack
			else:
				pc._attack_frames = pc._fist_frames if not pc._fist_frames.is_empty() else pc._weapon_attack_frames
			pc._current_attack_frame_duration = 0.05
		else:
			if item_name.contains("sword") and not pc._sword_attack_frames.is_empty():
				pc._attack_frames = pc._sword_attack_frames
			elif item_name.contains("pickaxe") and not pc._pickaxe_attack_frames.is_empty():
				pc._attack_frames = pc._pickaxe_attack_frames
			elif item_name.contains("axe") and not pc._weapon_attack_frames.is_empty():
				pc._attack_frames = pc._weapon_attack_frames
			elif item_name.contains("bow") and not pc._bow_attack_frames.is_empty():
				pc._attack_frames = pc._bow_attack_frames
			elif not pc._weapon_attack_frames.is_empty():
				pc._attack_frames = pc._weapon_attack_frames
			else:
				pc._attack_frames = pc._fist_frames
			pc._current_attack_frame_duration = 0.07

	if pc._attack_frames.is_empty():
		return
	pc._current_attack_dir = pc._get_camera_relative_dir()
	if not pc._attack_frames.has(pc._current_attack_dir):
		return
	pc._is_jumping = false
	pc._is_flipping = false
	pc._is_attacking = true
	pc._attack_frame_idx = 0
	pc._attack_frame_timer = pc._current_attack_frame_duration
	var frames_arr: Array = Array(pc._attack_frames[pc._current_attack_dir])
	if not frames_arr.is_empty():
		var tex := frames_arr[0] as Texture2D
		if tex and pc._player_sprite:
			pc._set_player_sprite_tex(tex)


# --- Weapon stats & affixes ---
func get_weapon_stat(stat: String, fallback: float) -> float:
	var data: Dictionary = ItemDatabase.get_item(pc.equipped_weapon)
	if data.has(stat):
		return float(data[stat])
	return fallback


func get_active_affixes() -> Dictionary:
	if not pc._affix_cache_dirty:
		return pc._cached_affixes
	pc._cached_affixes.clear()
	var wpn_parsed := ItemDatabase.parse_star_id(pc.equipped_weapon)
	for a: StringName in wpn_parsed.get("affixes", []):
		pc._cached_affixes[a] = true
	for slot: String in Inventory.EQUIPMENT_SLOTS:
		if slot == "weapon":
			continue
		var eq_id: StringName = Inventory.get_equipped(slot)
		if eq_id == &"":
			continue
		var eq_parsed := ItemDatabase.parse_star_id(eq_id)
		for a: StringName in eq_parsed.get("affixes", []):
			pc._cached_affixes[a] = true
	pc._affix_cache_dirty = false
	pc._regenerator_active = pc._cached_affixes.has(&"regenerator")
	pc._rally_cry_active = pc._cached_affixes.has(&"rally_cry")
	pc._fortress_active = pc._cached_affixes.has(&"fortress")
	return pc._cached_affixes


func has_affix(affix_id: StringName) -> bool:
	return get_active_affixes().has(affix_id)


func get_weapon_affixes() -> Array:
	var parsed := ItemDatabase.parse_star_id(pc.equipped_weapon)
	return parsed.get("affixes", [])


func invalidate_affix_cache() -> void:
	pc._affix_cache_dirty = true


func apply_affix_stat_bonuses() -> void:
	var base_max_hp := 100.0
	var base_max_stam := 100.0
	var affixes := get_active_affixes()
	var new_max_hp := base_max_hp
	var new_max_stam := base_max_stam
	if affixes.has(&"vitality"):
		new_max_hp += 15.0
	if affixes.has(&"endurance"):
		new_max_stam += 20.0
	if new_max_hp != pc.max_health:
		var hp_ratio := pc.current_health / pc.max_health if pc.max_health > 0 else 1.0
		pc.max_health = new_max_hp
		pc.current_health = pc.max_health * hp_ratio
		GameEvents.player_health_changed.emit(pc.current_health, pc.max_health)
	if new_max_stam != pc.max_stamina:
		var stam_ratio := pc.current_stamina / pc.max_stamina if pc.max_stamina > 0 else 1.0
		pc.max_stamina = new_max_stam
		pc.current_stamina = pc.max_stamina * stam_ratio
		GameEvents.player_stamina_changed.emit(pc.current_stamina, pc.max_stamina)


# --- Melee attack ---
func try_attack() -> void:
	if pc._is_blocking or pc._is_dodging:
		return
	if pc._bow_drawing:
		return
	var wpn_speed: float = get_weapon_stat("attack_speed", 0.6)
	if has_affix(&"rapid_strikes") or has_affix(&"rapid_chop") or has_affix(&"quick_strike"):
		wpn_speed *= 0.88
	if pc._crushing_momentum_timer > 0.0:
		wpn_speed *= 0.80
	var wpn_stamina: float = get_weapon_stat("stamina_cost", 4.0)
	if has_affix(&"efficient_miner"):
		wpn_stamina *= 0.8

	if pc._attack_cooldown > 0.0 or not pc._can_spend_stamina(wpn_stamina):
		return
	pc._spend_stamina(wpn_stamina)
	pc._attack_cooldown = wpn_speed
	start_attack_animation()

	var wpn_data := ItemDatabase.get_item(pc.equipped_weapon)
	var is_2h := str(wpn_data.get("hands", "1h")) == "2h"

	if pc._model:
		pc._model.position = Vector3.ZERO
		var tween := pc.create_tween()
		if is_2h:
			tween.tween_property(pc._model, "position:z", -0.20, 0.10)
			tween.tween_property(pc._model, "position:z", 0.0, 0.20)
		else:
			tween.tween_property(pc._model, "position:z", -0.3, 0.05)
			tween.tween_property(pc._model, "position:z", 0.0, 0.15)

	var wpn_damage: float = get_weapon_stat("damage", 5.0)
	var wpn_range: float = get_weapon_stat("range", 2.5)
	if has_affix(&"reaching"):
		wpn_range *= 1.2
	var wpn_knockback: float = get_weapon_stat("knockback", 10.0)
	var is_unarmed := pc.equipped_weapon == &"fists"
	var hit_delay := 0.30 if is_2h else MELEE_HIT_DELAY
	pc.get_tree().create_timer(hit_delay).timeout.connect(
		resolve_attack.bind(wpn_damage, wpn_range, wpn_knockback, is_unarmed)
	)


func resolve_attack(wpn_damage: float, wpn_range: float, wpn_knockback: float, single_target: bool = false) -> void:
	var cam: Camera3D = pc._spring_arm.get_child(0) if pc._spring_arm.get_child_count() > 0 else null
	if not cam:
		return
	var forward := -cam.global_transform.basis.z
	var fwd_flat := Vector3(forward.x, 0.0, forward.z).normalized()
	var check_origin := pc.global_position + Vector3.UP * 1.0

	var affixes := get_active_affixes()

	var cone_threshold := 0.5 if single_target else 0.0
	if affixes.has(&"cleaving") and not single_target:
		cone_threshold = -0.3

	var dmg := wpn_damage * randf_range(0.7, 1.3)
	if affixes.has(&"berserker"):
		var missing_pct := 1.0 - (pc.current_health / pc.max_health)
		dmg *= 1.0 + minf(missing_pct * 0.5, 0.5)
	if affixes.has(&"momentum"):
		dmg *= 1.0 + pc._momentum_stacks * 0.04
	if affixes.has(&"relentless_fury"):
		dmg *= 1.0 + pc._momentum_stacks * 0.05
	if pc._retaliation_timer > 0.0:
		dmg *= 1.3

	var kb := wpn_knockback
	if affixes.has(&"brutal_force"):
		kb *= 1.25

	var crit_chance := 5.0 + pc.base_dexterity * 0.5
	var crit_dmg := 150.0 + pc.base_strength * 2.0
	if affixes.has(&"sharpened"):
		crit_chance += 10.0
	if affixes.has(&"savage"):
		crit_dmg += 40.0
	var did_crit := randf() < crit_chance / 100.0
	if did_crit:
		dmg *= crit_dmg / 100.0

	var hit_something := false
	var hit_enemies: Array[Node3D] = []
	var best_enemy: Node3D = null
	var best_dist := INF

	for node: Node in pc.get_tree().get_nodes_in_group(&"enemies"):
		var enemy: Node3D = node as Node3D
		if not enemy:
			continue
		var to_enemy: Vector3 = enemy.global_position - check_origin
		to_enemy.y = 0.0
		var dist: float = to_enemy.length()
		if dist > wpn_range:
			continue
		var dir_to: Vector3 = to_enemy.normalized()
		var dot: float = dir_to.dot(fwd_flat)
		if dot < cone_threshold:
			continue
		if single_target:
			if dist < best_dist:
				best_dist = dist
				best_enemy = enemy
		else:
			var final_dmg := dmg
			if affixes.has(&"executioner"):
				var ehp: float = enemy.get("current_health") if enemy.get("current_health") != null else 999.0
				var emhp: float = enemy.get("max_health") if enemy.get("max_health") != null else 999.0
				if emhp > 0.0 and ehp / emhp < 0.3:
					final_dmg *= 1.3
			if affixes.has(&"skull_crusher") and enemy.has_method("is_stunned") and enemy.is_stunned():
				final_dmg *= 1.25
			if affixes.has(&"bane") and randf() < 0.08:
				final_dmg *= 2.0
			if enemy.has_method("take_damage"):
				enemy.take_damage(final_dmg, pc)
				pc._set_target_creature(enemy)
				_DamageNumber.spawn(pc.get_tree(), enemy.global_position + Vector3.UP * 1.0, final_dmg, did_crit)
				hit_something = true
				hit_enemies.append(enemy)
			if kb > 0.0 and enemy is CharacterBody3D:
				var kb_dir: Vector3 = (enemy.global_position - pc.global_position).normalized()
				kb_dir.y = 0.0
				(enemy as CharacterBody3D).velocity += kb_dir * kb * 0.1

	if single_target and best_enemy:
		var final_dmg := dmg
		if affixes.has(&"executioner"):
			var ehp: float = best_enemy.get("current_health") if best_enemy.get("current_health") != null else 999.0
			var emhp: float = best_enemy.get("max_health") if best_enemy.get("max_health") != null else 999.0
			if emhp > 0.0 and ehp / emhp < 0.3:
				final_dmg *= 1.3
		if affixes.has(&"skull_crusher") and best_enemy.has_method("is_stunned") and best_enemy.is_stunned():
			final_dmg *= 1.25
		if affixes.has(&"bane") and randf() < 0.08:
			final_dmg *= 2.0
		if best_enemy.has_method("take_damage"):
			best_enemy.take_damage(final_dmg, pc)
			pc._set_target_creature(best_enemy)
			_DamageNumber.spawn(pc.get_tree(), best_enemy.global_position + Vector3.UP * 1.0, final_dmg, did_crit)
			hit_something = true
			hit_enemies.append(best_enemy)
		if kb > 0.0 and best_enemy is CharacterBody3D:
			var kb_dir: Vector3 = (best_enemy.global_position - pc.global_position).normalized()
			kb_dir.y = 0.0
			(best_enemy as CharacterBody3D).velocity += kb_dir * kb * 0.1

	for enemy in hit_enemies:
		if not is_instance_valid(enemy):
			continue
		if affixes.has(&"lifesteal"):
			var heal_amt := dmg * 0.08
			pc.current_health = minf(pc.current_health + heal_amt, pc.max_health)
			GameEvents.player_health_changed.emit(pc.current_health, pc.max_health)
		if affixes.has(&"siphon"):
			pc.current_stamina = minf(pc.current_stamina + 3.0, pc.max_stamina)
			GameEvents.player_stamina_changed.emit(pc.current_stamina, pc.max_stamina)
		if affixes.has(&"firebrand") and randf() < 0.15:
			var fire_dmg := wpn_damage * 0.5
			if enemy.has_method("take_damage"):
				enemy.take_damage(fire_dmg, pc)
				var fire_num := _DamageNumber.new()
				fire_num.text = "%.0f" % fire_dmg
				fire_num.font_size = 22
				fire_num.pixel_size = 0.008
				fire_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				fire_num.no_depth_test = true
				fire_num.modulate = Color(1.0, 0.5, 0.1)
				fire_num.outline_modulate = Color.BLACK
				fire_num.outline_size = 5
				fire_num._velocity = Vector3(randf_range(-0.5, 0.5), 2.5, 0)
				pc.get_tree().current_scene.add_child(fire_num)
				fire_num.global_position = enemy.global_position + Vector3.UP * 1.5
		if affixes.has(&"chain_lightning") and randf() < 0.10:
			var arc_dmg := wpn_damage * 0.4
			var nearest: Node3D = null
			var nearest_dist := 8.0
			for other: Node in pc.get_tree().get_nodes_in_group(&"enemies"):
				var other_3d := other as Node3D
				if not other_3d or other_3d == enemy:
					continue
				var d := enemy.global_position.distance_to(other_3d.global_position)
				if d < nearest_dist:
					nearest_dist = d
					nearest = other_3d
			if nearest and nearest.has_method("take_damage"):
				nearest.take_damage(arc_dmg, pc)
				var arc_num := _DamageNumber.new()
				arc_num.text = "⚡%.0f" % arc_dmg
				arc_num.font_size = 22
				arc_num.pixel_size = 0.008
				arc_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				arc_num.no_depth_test = true
				arc_num.modulate = Color(0.4, 0.7, 1.0)
				arc_num.outline_modulate = Color.BLACK
				arc_num.outline_size = 5
				arc_num._velocity = Vector3(0, 2.5, 0)
				pc.get_tree().current_scene.add_child(arc_num)
				arc_num.global_position = nearest.global_position + Vector3.UP * 1.5
		if affixes.has(&"runic") and randf() < 0.12:
			var aoe_dmg := wpn_damage * 0.25
			for other: Node in pc.get_tree().get_nodes_in_group(&"enemies"):
				var other_3d := other as Node3D
				if not other_3d or other_3d == enemy:
					continue
				if enemy.global_position.distance_to(other_3d.global_position) < 5.0:
					if other_3d.has_method("take_damage"):
						other_3d.take_damage(aoe_dmg, pc)
						_DamageNumber.spawn(pc.get_tree(), other_3d.global_position + Vector3.UP * 1.0, aoe_dmg)
		if affixes.has(&"frostbite") and randf() < 0.20:
			if enemy.has_method("apply_slow"):
				enemy.apply_slow(0.6, 3.0)
		if affixes.has(&"venomous") and randf() < 0.12:
			if enemy.has_method("apply_poison"):
				var max_hp: float = float(enemy.get("max_health")) if enemy.get("max_health") != null else 100.0
				enemy.apply_poison(max_hp * 0.03, 4.0, pc)
		if affixes.has(&"stunning_blow") and randf() < 0.08:
			if enemy.has_method("apply_stun"):
				enemy.apply_stun(1.5)
		if affixes.has(&"concussive") and randf() < 0.20:
			if enemy.has_method("apply_disorient"):
				enemy.apply_disorient(3.0)
		if affixes.has(&"bone_breaker") and randf() < 0.10:
			if enemy.has_method("apply_armor_shred"):
				enemy.apply_armor_shred(0.30, 5.0)
		if affixes.has(&"earthshaker") and randf() < 0.12:
			var slam_dmg := wpn_damage * 0.30
			for aoe_node: Node in pc.get_tree().get_nodes_in_group(&"enemies"):
				var aoe_e := aoe_node as Node3D
				if not aoe_e or aoe_e == enemy:
					continue
				if enemy.global_position.distance_to(aoe_e.global_position) < 3.0:
					if aoe_e.has_method("take_damage"):
						aoe_e.take_damage(slam_dmg, pc)
						_DamageNumber.spawn(pc.get_tree(), aoe_e.global_position + Vector3.UP * 1.0, slam_dmg)
		if affixes.has(&"staggering") and randf() < 0.18:
			if enemy.has_method("apply_stun"):
				enemy.apply_stun(0.8)
		if affixes.has(&"thunderclap") and randf() < 0.08:
			var thunder_dmg := wpn_damage * 0.25
			for t_node: Node in pc.get_tree().get_nodes_in_group(&"enemies"):
				var t_e := t_node as Node3D
				if not t_e or t_e == enemy:
					continue
				if enemy.global_position.distance_to(t_e.global_position) < 3.0:
					if t_e.has_method("take_damage"):
						t_e.take_damage(thunder_dmg, pc)
						var t_num := _DamageNumber.new()
						t_num.text = "⚡%.0f" % thunder_dmg
						t_num.font_size = 22
						t_num.pixel_size = 0.008
						t_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
						t_num.no_depth_test = true
						t_num.modulate = Color(0.4, 0.7, 1.0)
						t_num.outline_modulate = Color.BLACK
						t_num.outline_size = 5
						t_num._velocity = Vector3(0, 2.5, 0)
						pc.get_tree().current_scene.add_child(t_num)
						t_num.global_position = t_e.global_position + Vector3.UP * 1.5

	if (affixes.has(&"momentum") or affixes.has(&"relentless_fury")) and not hit_enemies.is_empty():
		pc._momentum_stacks = mini(pc._momentum_stacks + 1, 5)
		pc._momentum_timer = 3.0

	if affixes.has(&"windfury") and not pc._windfury_guard and not hit_enemies.is_empty():
		if randf() < 0.30:
			pc._windfury_guard = true
			resolve_attack(wpn_damage, wpn_range, wpn_knockback, single_target)
			resolve_attack(wpn_damage, wpn_range, wpn_knockback, single_target)
			pc._windfury_guard = false

	var harvestable_candidates: Array[Dictionary] = []
	for node: Node in pc.get_tree().get_nodes_in_group(&"interactables"):
		var res_node: Node3D = node as Node3D
		if not res_node:
			continue
		var to_res: Vector3 = res_node.global_position - check_origin
		to_res.y = 0.0
		var dist: float = to_res.length()
		if dist > wpn_range + 1.5:
			continue
		var dir_to: Vector3 = to_res.normalized()
		var dot: float = dir_to.dot(fwd_flat)
		if dot < 0.0:
			continue
		if res_node.has_method("interact"):
			res_node.interact(pc)
			hit_something = true
		elif res_node.has_meta("harvestable"):
			harvestable_candidates.append({"node": res_node, "dist": dist})

	harvestable_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])
	var max_harvestable_hits := 3 if has_affix(&"timber_cleave") else 2
	for i in mini(harvestable_candidates.size(), max_harvestable_hits):
		var h_node: Node3D = harvestable_candidates[i]["node"] as Node3D
		var drop_id: StringName = h_node.get_meta("drop_id", &"wood") as StringName
		var harvest_slot := "pickaxe" if drop_id == &"stone" else "weapon"
		var harvest_id: StringName = Inventory.get_equipped(harvest_slot)
		var harvest_data: Dictionary = ItemDatabase.get_item(harvest_id) if harvest_id != &"" else {}
		var harvest_dmg: float = float(harvest_data.get("damage", 5.0)) * randf_range(0.7, 1.3)
		hit_harvestable(h_node, harvest_dmg)
		hit_something = true


func hit_harvestable(node: Node3D, damage: float) -> void:
	var drop_id: StringName = node.get_meta("drop_id", &"wood") as StringName

	var requires_tool: StringName = node.get_meta("requires_tool", &"") as StringName
	if requires_tool != &"":
		var pick_id: StringName = Inventory.get_equipped("pickaxe")
		var has_pickaxe := pick_id != &""
		if not has_pickaxe:
			_DamageNumber.spawn(pc.get_tree(), node.global_position + Vector3.UP * 1.5, 0.0, false, "player")
			var msg := _DamageNumber.new()
			msg.text = "Need Pickaxe"
			msg.font_size = 20
			msg.pixel_size = 0.008
			msg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			msg.no_depth_test = true
			msg.modulate = Color(1.0, 0.6, 0.2)
			msg.outline_modulate = Color.BLACK
			msg.outline_size = 5
			msg._velocity = Vector3(0, 1.5, 0)
			pc.get_tree().current_scene.add_child(msg)
			msg.global_position = node.global_position + Vector3(0, 2.0, 0)
			AudioManager.play_sfx_at("stone_rubble", node.global_position, -8.0)
			return

	var hp: float = float(node.get_meta("hp", 0.0))
	var effective_dmg := damage
	if drop_id == &"wood" and has_affix(&"deep_cut"):
		effective_dmg *= 1.5
	elif drop_id == &"stone" and has_affix(&"stone_breaker"):
		effective_dmg *= 1.5
	hp -= effective_dmg
	node.set_meta("hp", hp)

	var mesh := node.get_node_or_null("MeshInstance3D")
	if not mesh:
		mesh = node.get_node_or_null("Trunk")
	if mesh:
		var tween := node.create_tween()
		tween.tween_property(mesh, "rotation:z", deg_to_rad(1.5), 0.06)
		tween.tween_property(mesh, "rotation:z", deg_to_rad(-1.0), 0.07)
		tween.tween_property(mesh, "rotation:z", deg_to_rad(0.4), 0.06)
		tween.tween_property(mesh, "rotation:z", 0.0, 0.1)

	var canopy := node.get_node_or_null("Canopy") as Node3D
	if canopy:
		var base_rz: float = canopy.rotation.z
		var base_rx: float = canopy.rotation.x
		var c_tween := node.create_tween()
		c_tween.tween_property(canopy, "rotation:z", base_rz + deg_to_rad(14.0), 0.08)
		c_tween.tween_property(canopy, "rotation:z", base_rz + deg_to_rad(-10.0), 0.10)
		c_tween.tween_property(canopy, "rotation:z", base_rz + deg_to_rad(5.0), 0.09)
		c_tween.tween_property(canopy, "rotation:z", base_rz + deg_to_rad(-2.0), 0.08)
		c_tween.tween_property(canopy, "rotation:z", base_rz, 0.12)
		var cx_tween := node.create_tween()
		cx_tween.tween_property(canopy, "rotation:x", base_rx + deg_to_rad(8.0), 0.09)
		cx_tween.tween_property(canopy, "rotation:x", base_rx - deg_to_rad(5.0), 0.10)
		cx_tween.tween_property(canopy, "rotation:x", base_rx + deg_to_rad(2.0), 0.08)
		cx_tween.tween_property(canopy, "rotation:x", base_rx, 0.11)
	_DamageNumber.spawn(pc.get_tree(), node.global_position + Vector3.UP * 2.0, effective_dmg)

	if drop_id == &"wood" and has_affix(&"sharpened_edge") and randf() < 0.25 and hp > 0.0:
		hit_harvestable(node, effective_dmg)
		hit_harvestable(node, effective_dmg)
	elif drop_id == &"stone" and has_affix(&"precision_strike") and randf() < 0.25 and hp > 0.0:
		hit_harvestable(node, effective_dmg)
		hit_harvestable(node, effective_dmg)

	if drop_id == &"wood":
		var sfx := "axe_chop" if pc.equipped_weapon != &"fists" and pc.equipped_weapon != &"" else "fist_hit_tree"
		AudioManager.play_sfx(sfx, -4.0)
	elif drop_id == &"stone":
		AudioManager.play_sfx("pickaxe_hit", -4.0)

	if hp <= 0.0:
		if drop_id == &"stone":
			destroy_rock(node)
		else:
			fell_tree(node)


func destroy_rock(node: Node3D) -> void:
	var drop_id: StringName = node.get_meta("drop_id", &"stone") as StringName
	var drop_min: int = int(node.get_meta("drop_min", 2))
	var drop_max: int = int(node.get_meta("drop_max", 4))

	node.remove_from_group(&"interactables")
	node.set_meta("harvestable", false)
	var col := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		col.disabled = true

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var total := rng.randi_range(drop_min, drop_max)
	if drop_id == &"stone" and has_affix(&"prospector"):
		total = ceili(total * 1.4)
	elif drop_id == &"copper_ore" and has_affix(&"ore_seeker"):
		total = ceili(total * 1.3)
	if has_affix(&"rich_vein") and rng.randf() < 0.10:
		total *= 2
	var master_miner := has_affix(&"heavy_swing")
	for i in total:
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(0.8, 2.5)
		var offset := Vector3(cos(angle) * dist, 0.5, sin(angle) * dist)
		var stars := ItemDatabase.roll_star_level(rng)
		if master_miner:
			var reroll := ItemDatabase.roll_star_level(rng)
			if reroll > stars:
				stars = reroll
			reroll = ItemDatabase.roll_star_level(rng)
			if reroll > stars:
				stars = reroll
		var drop := _LootDrop.new()
		drop.item_id = drop_id
		drop.star_level = stars
		drop.amount = 1
		pc.get_tree().current_scene.add_child(drop)
		drop.global_position = node.global_position + offset

	if rng.randf() < 0.4:
		var flint_stars := ItemDatabase.roll_star_level(rng)
		var flint_drop := _LootDrop.new()
		flint_drop.item_id = &"flint"
		flint_drop.star_level = flint_stars
		flint_drop.amount = rng.randi_range(1, 2)
		pc.get_tree().current_scene.add_child(flint_drop)
		flint_drop.global_position = node.global_position + Vector3(rng.randf_range(-1.0, 1.0), 0.5, rng.randf_range(-1.0, 1.0))

	if has_affix(&"vein_finder") and rng.randf() < 0.30:
		var ore_drop := _LootDrop.new()
		ore_drop.item_id = &"copper_ore"
		ore_drop.star_level = ItemDatabase.roll_star_level(rng)
		ore_drop.amount = rng.randi_range(1, 2)
		pc.get_tree().current_scene.add_child(ore_drop)
		ore_drop.global_position = node.global_position + Vector3(rng.randf_range(-1.0, 1.0), 0.5, rng.randf_range(-1.0, 1.0))

	if has_affix(&"geologist") and rng.randf() < 0.20:
		var rare_items: Array[StringName] = [&"gemstone", &"ancient_bone", &"ember_stone"]
		var rare_id: StringName = rare_items[rng.randi_range(0, rare_items.size() - 1)]
		var rare_drop := _LootDrop.new()
		rare_drop.item_id = rare_id
		rare_drop.star_level = ItemDatabase.roll_star_level(rng)
		rare_drop.amount = 1
		pc.get_tree().current_scene.add_child(rare_drop)
		rare_drop.global_position = node.global_position + Vector3(rng.randf_range(-1.0, 1.0), 0.5, rng.randf_range(-1.0, 1.0))

	AudioManager.play_sfx_at("rock_fall", node.global_position, 2.0)
	AudioManager.play_sfx_at("stone_rubble", node.global_position, -2.0)
	node.queue_free()


func get_terrain_slope_dir(pos: Vector3) -> Vector3:
	var wg := pc._find_world_generator()
	if not wg:
		return Vector3.ZERO
	var sample_dist := 2.0
	var h_center := wg.get_height_at(pos.x, pos.z)
	var h_px := wg.get_height_at(pos.x + sample_dist, pos.z)
	var h_nx := wg.get_height_at(pos.x - sample_dist, pos.z)
	var h_pz := wg.get_height_at(pos.x, pos.z + sample_dist)
	var h_nz := wg.get_height_at(pos.x, pos.z - sample_dist)
	var slope := Vector3(h_nx - h_px, 0.0, h_nz - h_pz)
	if slope.length_squared() < 0.001:
		return Vector3.ZERO
	return slope.normalized()


func fell_tree(node: Node3D, override_angle: float = NAN, can_domino: bool = true) -> void:
	var drop_id: StringName = node.get_meta("drop_id", &"wood") as StringName
	var drop_min: int = int(node.get_meta("drop_min", 2))
	var drop_max: int = int(node.get_meta("drop_max", 4))

	node.remove_from_group(&"interactables")
	node.set_meta("harvestable", false)
	var col := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		col.disabled = true

	var tree_base := node.global_position
	var trunk_h: float = float(node.get_meta("trunk_h", 15.0))

	var fall_angle: float
	if is_nan(override_angle):
		var to_tree := node.global_position - pc.global_position
		to_tree.y = 0.0
		var player_dir := to_tree.normalized()

		var slope_dir := get_terrain_slope_dir(tree_base)
		var blended_dir: Vector3
		if slope_dir.length_squared() > 0.01:
			blended_dir = (player_dir * 0.6 + slope_dir * 0.4).normalized()
		else:
			blended_dir = player_dir

		fall_angle = atan2(blended_dir.x, blended_dir.z)
		fall_angle += randf_range(-0.3, 0.3)
	else:
		fall_angle = override_angle + randf_range(-0.15, 0.15)

	AudioManager.play_sfx("tree_fall", 4.0, 0.08)

	spawn_tree_stump(node, tree_base)

	var fall_tween := node.create_tween()
	fall_tween.set_ease(Tween.EASE_IN)
	fall_tween.set_trans(Tween.TRANS_QUAD)

	node.rotation.y = fall_angle
	var fall_duration := 0.82 if has_affix(&"splitter") else 1.17
	fall_tween.tween_property(node, "rotation:x", deg_to_rad(-85.0), fall_duration)

	var fall_dir := Vector3(-sin(fall_angle), 0.0, -cos(fall_angle))
	fall_tween.tween_callback(func():
		if can_domino:
			check_tree_domino(tree_base, fall_angle, trunk_h)
		AudioManager.play_sfx_at("tree_fall", tree_base + fall_dir * trunk_h * 0.5, 0.0)
	)
	fall_tween.tween_interval(0.4)
	fall_tween.tween_callback(func():
		node.queue_free()

		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var log_count := rng.randi_range(drop_min, drop_max)
		if has_affix(&"lumberjack"):
			log_count = ceili(log_count * 1.4)
		if has_affix(&"double_yield") and rng.randf() < 0.10:
			log_count *= 2
		var master_woodsman := has_affix(&"heavy_chop")
		for i in log_count:
			var t := rng.randf_range(0.2, 0.9)
			var along := fall_dir * trunk_h * t
			var lateral := rng.randf_range(-1.5, 1.5)
			var perp := Vector3(-fall_dir.z, 0.0, fall_dir.x)
			var offset := along + perp * lateral + Vector3.UP * 0.5
			var stars := ItemDatabase.roll_star_level(rng)
			if master_woodsman:
				var reroll := ItemDatabase.roll_star_level(rng)
				if reroll > stars:
					stars = reroll
				reroll = ItemDatabase.roll_star_level(rng)
				if reroll > stars:
					stars = reroll
			var drop := _LootDrop.new()
			drop.item_id = drop_id
			drop.star_level = stars
			drop.amount = 1
			pc.get_tree().current_scene.add_child(drop)
			drop.global_position = tree_base + offset

		if has_affix(&"bark_stripper") and rng.randf() < 0.25:
			var resin_drop := _LootDrop.new()
			resin_drop.item_id = &"resin"
			resin_drop.star_level = ItemDatabase.roll_star_level(rng)
			resin_drop.amount = rng.randi_range(1, 2)
			pc.get_tree().current_scene.add_child(resin_drop)
			resin_drop.global_position = tree_base + Vector3(rng.randf_range(-1.0, 1.0), 0.5, rng.randf_range(-1.0, 1.0))

		if has_affix(&"sap_drinker") and rng.randf() < 0.20:
			var rare_items: Array[StringName] = [&"amber", &"living_wood", &"fairy_dust"]
			var rare_id: StringName = rare_items[rng.randi_range(0, rare_items.size() - 1)]
			var rare_drop := _LootDrop.new()
			rare_drop.item_id = rare_id
			rare_drop.star_level = ItemDatabase.roll_star_level(rng)
			rare_drop.amount = 1
			pc.get_tree().current_scene.add_child(rare_drop)
			rare_drop.global_position = tree_base + Vector3(rng.randf_range(-1.0, 1.0), 0.5, rng.randf_range(-1.0, 1.0))
	)


func spawn_tree_stump(tree_node: Node3D, base_pos: Vector3) -> void:
	var trunk_mi := tree_node.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if not trunk_mi:
		trunk_mi = tree_node.get_node_or_null("Trunk") as MeshInstance3D
	if not trunk_mi or not trunk_mi.mesh:
		return

	var trunk_h: float = float(tree_node.get_meta("trunk_h", 15.0))
	var bark_mat := trunk_mi.get_active_material(0)

	var stump_h := clampf(trunk_h * 0.06, 0.3, 1.2)
	var bot_r := 0.0
	var top_r := 0.0
	if trunk_mi.mesh is CylinderMesh:
		var cyl := trunk_mi.mesh as CylinderMesh
		bot_r = cyl.bottom_radius
		top_r = lerpf(cyl.bottom_radius, cyl.top_radius, stump_h / trunk_h)
	else:
		bot_r = 0.4
		top_r = 0.35

	var stump_mesh := CylinderMesh.new()
	stump_mesh.bottom_radius = bot_r
	stump_mesh.top_radius = top_r
	stump_mesh.height = stump_h
	stump_mesh.radial_segments = 8
	stump_mesh.rings = 1

	var stump_mi := MeshInstance3D.new()
	stump_mi.mesh = stump_mesh
	if bark_mat:
		stump_mi.set_surface_override_material(0, bark_mat)
	stump_mi.position.y = stump_h * 0.5
	stump_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var col_shape := CollisionShape3D.new()
	var cyl_col := CylinderShape3D.new()
	cyl_col.radius = maxf(bot_r, top_r) + 0.05
	cyl_col.height = stump_h
	col_shape.shape = cyl_col
	col_shape.position.y = stump_h * 0.5

	var is_sapling_stump := trunk_h < 8.0

	var stump_root := StaticBody3D.new()
	stump_root.name = "Stump"
	stump_root.collision_layer = 0 if is_sapling_stump else 1
	stump_root.collision_mask = 0
	stump_root.global_position = base_pos
	stump_root.set_meta("stump_radius", maxf(bot_r, top_r) + 0.1)
	stump_root.add_to_group(&"stumps")
	pc.get_tree().current_scene.add_child(stump_root)
	stump_root.add_child(stump_mi)
	if not is_sapling_stump:
		stump_root.add_child(col_shape)

	pc.get_tree().create_timer(120.0).timeout.connect(stump_root.queue_free)


func check_tree_domino(base_pos: Vector3, fall_angle: float, trunk_h: float = 15.0) -> void:
	var fall_dir := Vector3(-sin(fall_angle), 0.0, -cos(fall_angle))
	var hit_radius := maxf(1.5, trunk_h * 0.08)
	var faller_is_sapling := trunk_h < 8.0
	var felled: Array[Node3D] = []
	for node in pc.get_tree().get_nodes_in_group(&"interactables"):
		var n3d := node as Node3D
		if not n3d:
			continue
		if not n3d.get_meta("harvestable", false):
			continue
		if n3d.get_meta("drop_id", &"") != &"wood":
			continue
		var target_trunk_h: float = float(n3d.get_meta("trunk_h", 15.0))
		if faller_is_sapling and target_trunk_h >= 8.0:
			continue
		var target_pos := n3d.global_position
		target_pos.y = base_pos.y
		var to_target := target_pos - base_pos
		var trunk_len := trunk_h
		var raw_t := to_target.dot(fall_dir) / trunk_len
		if raw_t < 0.15:
			continue
		var t := clampf(raw_t, 0.15, 1.0)
		var closest_on_trunk := base_pos + fall_dir * trunk_len * t
		var dist := closest_on_trunk.distance_to(target_pos)
		var effective_radius := hit_radius + t * trunk_h * 0.12
		if dist < effective_radius:
			felled.append(n3d)
	for n3d in felled:
		var push_dir := n3d.global_position - base_pos
		push_dir.y = 0.0
		var push_angle := atan2(push_dir.x, push_dir.z)
		fell_tree(n3d, push_angle, false)


func check_tree_crush_player(base_pos: Vector3, fall_angle: float, trunk_h: float) -> void:
	var fall_dir := Vector3(sin(fall_angle), 0.0, cos(fall_angle))
	var player_pos := pc.global_position
	var crush_damage := 60.0 + trunk_h * 2.0

	var crush_steps: Array[float] = [0.4, 0.55, 0.7, 0.85, 1.0]
	for t in crush_steps:
		var check_pos: Vector3 = base_pos + fall_dir * trunk_h * t
		check_pos.y = player_pos.y
		var dist := check_pos.distance_to(player_pos)
		var hit_radius := lerpf(1.5, 3.5, t)
		if dist < hit_radius:
			take_damage(crush_damage)
			var knockback_dir := (player_pos - base_pos).normalized()
			knockback_dir.y = 0.2
			pc.velocity += knockback_dir * 8.0
			return


# --- Damage, regen, death ---
func take_damage(amount: float, _source: Node3D = null) -> void:
	if pc.current_health <= 0.0:
		return
	if pc._is_dodging:
		return
	if _source and _source.has_method("take_damage"):
		pc._set_target_creature(_source)

	var pre_vel := pc.velocity
	var affixes := get_active_affixes()

	if affixes.has(&"iron_skin") and randf() < 0.08:
		var dodge_num := _DamageNumber.new()
		dodge_num.text = "Absorbed"
		dodge_num.font_size = 20
		dodge_num.pixel_size = 0.008
		dodge_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		dodge_num.no_depth_test = true
		dodge_num.modulate = Color(0.6, 0.8, 1.0)
		dodge_num.outline_modulate = Color.BLACK
		dodge_num.outline_size = 5
		dodge_num._velocity = Vector3(0, 2.0, 0)
		pc.get_tree().current_scene.add_child(dodge_num)
		dodge_num.global_position = pc.global_position + Vector3.UP * 2.5
		return
	var dodge_roll := 0.0
	if affixes.has(&"evasion"):
		dodge_roll += 0.05
	if affixes.has(&"nimble") and pc._is_sprinting:
		dodge_roll += 0.08
	if dodge_roll > 0.0 and randf() < dodge_roll:
		var evade_num := _DamageNumber.new()
		evade_num.text = "Evaded"
		evade_num.font_size = 20
		evade_num.pixel_size = 0.008
		evade_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		evade_num.no_depth_test = true
		evade_num.modulate = Color(0.5, 1.0, 0.5)
		evade_num.outline_modulate = Color.BLACK
		evade_num.outline_size = 5
		evade_num._velocity = Vector3(0, 2.0, 0)
		pc.get_tree().current_scene.add_child(evade_num)
		evade_num.global_position = pc.global_position + Vector3.UP * 2.5
		return

	var final_amount := amount

	if affixes.has(&"deflection") and not pc._is_blocking and randf() < 0.15:
		if _source and _source.global_position.distance_to(pc.global_position) > 5.0:
			var defl_num := _DamageNumber.new()
			defl_num.text = "Deflected"
			defl_num.font_size = 20
			defl_num.pixel_size = 0.008
			defl_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			defl_num.no_depth_test = true
			defl_num.modulate = Color(0.7, 0.9, 1.0)
			defl_num.outline_modulate = Color.BLACK
			defl_num.outline_size = 5
			defl_num._velocity = Vector3(0, 2.0, 0)
			pc.get_tree().current_scene.add_child(defl_num)
			defl_num.global_position = pc.global_position + Vector3.UP * 2.5
			return

	if affixes.has(&"shield_wall") and not pc._is_blocking and randf() < 0.15:
		final_amount *= 0.3

	if pc._aegis_shield > 0.0:
		var absorbed := minf(final_amount, pc._aegis_shield)
		pc._aegis_shield -= absorbed
		final_amount -= absorbed
	if affixes.has(&"aegis") and randf() < 0.10 and pc._aegis_timer <= 0.0:
		pc._aegis_shield = pc.max_health * 0.15
		pc._aegis_timer = 5.0

	if affixes.has(&"iron_will") and pc._is_attacking:
		final_amount *= 0.9
	if affixes.has(&"thick_skinned") and pc._thick_skinned_cooldown <= 0.0:
		final_amount *= 0.7
		pc._thick_skinned_cooldown = 10.0
	var did_block := pc._is_blocking
	if pc._is_blocking:
		if affixes.has(&"unbreakable") and pc.current_health / pc.max_health < 0.25:
			final_amount = 0.0
		else:
			var block_mult := 0.2 if affixes.has(&"guardian") else 0.3
			final_amount *= block_mult
	var armor_value := Inventory.get_total_armor()
	if affixes.has(&"bulwark"):
		armor_value += 3.0
	if pc._fortress_active:
		armor_value += 5.0
	if armor_value > 0.0:
		final_amount *= maxf(1.0 - (armor_value * 0.02), 0.2)
	if affixes.has(&"fortified"):
		final_amount *= 0.92
	if affixes.has(&"last_stand") and pc.current_health / pc.max_health < 0.25:
		final_amount *= 0.75
	if affixes.has(&"battle_hardened"):
		var nearby_count := 0
		for node: Node in pc.get_tree().get_nodes_in_group(&"enemies"):
			var e := node as Node3D
			if e and pc.global_position.distance_to(e.global_position) < 10.0:
				nearby_count += 1
				if nearby_count >= 3:
					break
		final_amount *= maxf(1.0 - nearby_count * 0.05, 0.85)

	pc.current_health = maxf(pc.current_health - final_amount, 0.0)
	pc._hp_pulse = 1.0
	var regen_delay := pc.health_regen_delay
	if affixes.has(&"quick_recovery"):
		regen_delay -= 2.0
	pc._health_regen_timer = regen_delay
	GameEvents.player_health_changed.emit(pc.current_health, pc.max_health)
	AudioManager.play_sfx("player_hurt", -2.0)

	if did_block:
		if affixes.has(&"retaliation"):
			pc._retaliation_timer = 3.0
		if affixes.has(&"shield_bash") and randf() < 0.25 and _source and _source.has_method("apply_stun"):
			_source.apply_stun(1.0)
	if not pc._gltf_all_meshes.is_empty():
		pc._gltf_flash(Color(1.0, 0.2, 0.2))
		pc.get_tree().create_timer(0.15).timeout.connect(func():
			pc._gltf_clear_flash()
		)
	elif pc._player_model_3d:
		pc._player_model_3d.flash(Color(1.0, 0.2, 0.2))
		pc.get_tree().create_timer(0.15).timeout.connect(func():
			if pc._player_model_3d:
				pc._player_model_3d.clear_flash()
		)

	if affixes.has(&"steadfast"):
		pc.velocity = pre_vel
	elif affixes.has(&"stalwart"):
		var kb_change := pc.velocity - pre_vel
		pc.velocity = pre_vel + kb_change * 0.7

	if affixes.has(&"thorns") and _source and _source.has_method("take_damage"):
		_source.take_damage(amount * 0.15, pc)

	if affixes.has(&"second_wind") and pc._second_wind_cooldown <= 0.0:
		if pc.current_health > 0.0 and pc.current_health / pc.max_health < 0.20:
			pc.current_health = minf(pc.current_health + pc.max_health * 0.20, pc.max_health)
			pc._second_wind_cooldown = 45.0
			GameEvents.player_health_changed.emit(pc.current_health, pc.max_health)

	if pc.current_health <= 0.0:
		if affixes.has(&"undying") and pc._undying_cooldown <= 0.0:
			pc.current_health = pc.max_health * 0.10
			pc._undying_cooldown = 300.0
			GameEvents.player_health_changed.emit(pc.current_health, pc.max_health)
			var revive_num := _DamageNumber.new()
			revive_num.text = "Undying!"
			revive_num.font_size = 26
			revive_num.pixel_size = 0.01
			revive_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			revive_num.no_depth_test = true
			revive_num.modulate = Color(1.0, 0.85, 0.2)
			revive_num.outline_modulate = Color.BLACK
			revive_num.outline_size = 6
			revive_num._velocity = Vector3(0, 2.5, 0)
			pc.get_tree().current_scene.add_child(revive_num)
			revive_num.global_position = pc.global_position + Vector3.UP * 2.5
		else:
			on_death()


func handle_health_regen(delta: float) -> void:
	pc._health_regen_timer -= delta
	if pc._health_regen_timer <= 0.0 and pc.current_health < pc.max_health:
		var regen := pc.health_regen_rate
		if has_affix(&"rejuvenation"):
			regen *= 1.3
		pc.current_health = minf(pc.current_health + regen * delta, pc.max_health)
		GameEvents.player_health_changed.emit(pc.current_health, pc.max_health)
	if pc._regenerator_active and pc.current_health < pc.max_health and pc._health_regen_timer > 0.0:
		pc.current_health = minf(pc.current_health + 1.0 * delta, pc.max_health)
		GameEvents.player_health_changed.emit(pc.current_health, pc.max_health)


func tick_affix_timers(delta: float) -> void:
	if pc._momentum_timer > 0.0:
		pc._momentum_timer -= delta
		if pc._momentum_timer <= 0.0:
			pc._momentum_stacks = 0
	if pc._second_wind_cooldown > 0.0:
		pc._second_wind_cooldown -= delta
	if pc._thick_skinned_cooldown > 0.0:
		pc._thick_skinned_cooldown -= delta
	if pc._undying_cooldown > 0.0:
		pc._undying_cooldown -= delta
	if pc._adrenaline_timer > 0.0:
		pc._adrenaline_timer -= delta
	if pc._crushing_momentum_timer > 0.0:
		pc._crushing_momentum_timer -= delta
	if pc._retaliation_timer > 0.0:
		pc._retaliation_timer -= delta
	if pc._aegis_timer > 0.0:
		pc._aegis_timer -= delta
		if pc._aegis_timer <= 0.0:
			pc._aegis_shield = 0.0
	if pc._rally_cry_active and pc.current_health < pc.max_health:
		pc.current_health = minf(pc.current_health + 2.0 * delta, pc.max_health)
		GameEvents.player_health_changed.emit(pc.current_health, pc.max_health)


func on_death() -> void:
	GameEvents.player_died.emit()
	AudioManager.play_sfx("player_death", 0.0, 0.0)
	if pc._footstep_player and pc._footstep_player.playing:
		pc._footstep_player.stop()
	if pc._gallop_player and pc._gallop_player.playing:
		pc._gallop_player.stop()
	if pc._mounted:
		pc._force_dismount()
	pc.velocity = Vector3.ZERO
	pc.set_physics_process(false)
	await pc.get_tree().create_timer(2.0).timeout
	respawn()
	pc.set_physics_process(true)


func respawn() -> void:
	if pc._in_cave:
		pc._exit_cave()
	if pc._mounted:
		pc._force_dismount()
	if pc._bow_drawing:
		cancel_bow_draw()
	pc.velocity = Vector3.ZERO
	pc.current_health = pc.max_health
	pc._last_safe_position = Vector3.ZERO
	pc._respawn_grace = 3.0
	var spawn_x := 0.0
	var spawn_z := 0.0
	var spawn_y := 0.5
	var wg := pc._find_world_generator()
	if wg:
		spawn_y = wg.get_height_at(spawn_x, spawn_z) + 0.2
	if spawn_y > 5.0 or spawn_y < -5.0:
		spawn_y = 0.5
	pc.global_position = Vector3(spawn_x, spawn_y, spawn_z)
	pc.velocity = Vector3.ZERO
	pc._is_attacking = false
	pc._is_jumping = false
	pc._is_flipping = false
	pc._is_run_animating = false
	pc._is_dodging = false
	pc._is_swimming = false
	pc._swim_time = 0.0
	if pc._player_sprite:
		pc._player_sprite.visible = true
		if not pc._gltf_all_meshes.is_empty():
			pc._gltf_clear_flash()
		elif pc._player_model_3d:
			pc._player_model_3d.clear_flash()
		pc._player_sprite.position.y = pc._base_sprite_y
		if pc._gltf_anim_player:
			var s := 4.0 if pc._is_lowpoly_viking else 0.7
			pc._player_sprite.scale = Vector3(s, s, s)
		else:
			pc._player_sprite.scale = Vector3.ONE
		pc._player_sprite.rotation = Vector3.ZERO
	if pc._model and pc._player_yaw_offset != 0.0:
		pc._model.rotation.y = pc._player_yaw_offset
	GameEvents.player_health_changed.emit(pc.current_health, pc.max_health)
