class_name PlayerMovement
extends Node

var pc: PlayerController

const STEP_HEIGHT := 0.35
const SWIM_SPEED := 3.0
const SWIM_SPRINT_SPEED := 4.5
const BUOYANCY_FORCE := 12.0
const WATER_DAMPING := 4.0
const SWIM_STAMINA_COST := 6.0
const MOUNT_SPEED_MULT := 2.0


func apply_gravity(delta: float) -> void:
	var water_y := WaterSystem.get_surface_y(pc.global_position.x, pc.global_position.z)
	var feet_y := pc.global_position.y
	var submersion := water_y - feet_y

	if submersion > 0.2:
		# Under water — apply buoyancy and damping instead of gravity
		pc._is_swimming = true
		var buoy := submersion * BUOYANCY_FORCE
		pc.velocity.y += buoy * delta
		pc.velocity.y -= pc.velocity.y * WATER_DAMPING * delta
		# Clamp so we don't rocket out of the water
		pc.velocity.y = clampf(pc.velocity.y, -6.0, 4.0)
	elif submersion > -0.3 and pc.velocity.y < 0.0:
		# Near surface falling — gentle decel (bobbing zone)
		pc._is_swimming = true
		pc.velocity.y *= 1.0 - 3.0 * delta
	else:
		pc._is_swimming = false
		if not pc.is_on_floor():
			var grav_mult := pc.fall_gravity_multiplier if pc.velocity.y < 0.0 else pc.gravity_multiplier
			pc.velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) * grav_mult * delta
		if pc._mounted:
			pc.velocity.y = clampf(pc.velocity.y, -18.0, 1.0)


func snap_to_ground() -> void:
	var space := pc.get_world_3d().direct_space_state
	if not space:
		return
	var from := Vector3(pc.global_position.x, pc.global_position.y + 50.0, pc.global_position.z)
	var to := Vector3(pc.global_position.x, pc.global_position.y - 100.0, pc.global_position.z)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [pc.get_rid()]
	var result := space.intersect_ray(query)
	if not result.is_empty():
		pc.global_position.y = result["position"].y + 0.15
		pc.velocity = Vector3.ZERO
		pc._last_safe_position = pc.global_position


func clamp_to_terrain() -> void:
	if pc._in_cave:
		return

	var dt := pc.get_physics_process_delta_time()
	if pc._respawn_grace > 0.0:
		pc._respawn_grace -= dt
		if pc.velocity.y > 0.0:
			pc.velocity.y = 0.0
		return

	var space := pc.get_world_3d().direct_space_state
	if not space:
		return

	var from := Vector3(pc.global_position.x, pc.global_position.y + 3.0, pc.global_position.z)
	var to := Vector3(pc.global_position.x, pc.global_position.y - 25.0, pc.global_position.z)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [pc.get_rid()]
	var result := space.intersect_ray(query)

	if result.is_empty():
		if pc._last_safe_position != Vector3.ZERO and pc.global_position.y < pc._last_safe_position.y - 12.0:
			pc.global_position = pc._last_safe_position
			pc.velocity = Vector3.ZERO
		return

	var surface_y: float = result["position"].y
	var below_surface := surface_y - pc.global_position.y
	var snap_threshold := 0.05 if pc._mounted else 0.15
	var max_snap := 1.5 if pc._mounted else 2.0
	if below_surface > snap_threshold and below_surface < max_snap:
		pc.global_position.y = surface_y + 0.15
		pc.velocity.y = maxf(pc.velocity.y, 0.0)

	if pc.global_position.y >= surface_y - 0.5 and pc.global_position.y <= surface_y + 3.0:
		pc._safe_pos_timer += dt
		var save_interval := 0.1 if pc._mounted else 0.25
		if pc._safe_pos_timer > save_interval:
			pc._safe_pos_timer = 0.0
			pc._last_safe_position = pc.global_position


func handle_jump() -> void:
	if pc._is_swimming:
		# In water: hold jump to swim upward
		if Input.is_action_pressed(&"jump") and can_spend_stamina(0.1):
			pc.velocity.y = lerpf(pc.velocity.y, 3.0, 0.15)
			var swim_cost := SWIM_STAMINA_COST
			if pc._has_affix(&"warmth"):
				swim_cost *= 0.6
			spend_stamina(swim_cost * pc.get_physics_process_delta_time())
		return
	if Input.is_action_just_pressed(&"jump") and pc.is_on_floor() and not pc._is_blocking and not pc._mounted:
		pc.velocity.y = pc.jump_velocity
		pc._start_jump_animation()


func step_up_move_and_slide() -> void:
	var flat_vel := Vector2(pc.velocity.x, pc.velocity.z)
	if not pc.is_on_floor() or flat_vel.length() < 0.1:
		pc.move_and_slide()
		return

	var saved_vel := pc.velocity
	var saved_pos := pc.global_position

	pc.move_and_slide()

	var moved := Vector2(pc.global_position.x - saved_pos.x, pc.global_position.z - saved_pos.z).length()
	var wanted := flat_vel.length() * pc.get_physics_process_delta_time()
	if moved >= wanted * 0.5:
		return

	pc.global_position = saved_pos
	pc.velocity = saved_vel

	pc.global_position.y += STEP_HEIGHT
	pc.move_and_slide()

	var space := pc.get_world_3d().direct_space_state
	if space:
		var ray_from := pc.global_position
		var ray_to := pc.global_position - Vector3(0, STEP_HEIGHT + 0.1, 0)
		var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, pc.collision_mask)
		query.exclude = [pc.get_rid()]
		var result := space.intersect_ray(query)
		if not result.is_empty():
			pc.global_position.y = result["position"].y
		else:
			pc.global_position.y = saved_pos.y


func handle_movement(delta: float) -> void:
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if pc._auto_run:
		if input_dir.length_squared() > 0.01:
			pc._auto_run = false
		else:
			input_dir.y = -1.0

	var cam_basis := pc._camera_pivot.global_transform.basis
	var direction := (cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	direction.y = 0.0

	pc._is_sprinting = (
		Input.is_action_pressed(&"sprint")
		and input_dir != Vector2.ZERO
		and not pc._is_crouching
		and not pc._is_blocking
		and can_spend_stamina(0.1)
	)

	var speed := pc.walk_speed
	if pc._is_swimming:
		speed = SWIM_SPRINT_SPEED if pc._is_sprinting else SWIM_SPEED
		if pc._has_affix(&"aquatic"):
			speed *= 1.3
	elif pc._is_crouching:
		speed = pc.crouch_speed
	elif pc._is_sprinting:
		speed = pc.sprint_speed
	elif pc._walk_mode:
		speed = pc.walk_speed * 0.55
	if pc._mounted:
		speed *= MOUNT_SPEED_MULT
	if pc._has_affix(&"swiftness"):
		speed *= 1.1
	if pc._is_swimming and pc._has_affix(&"trailblazer"):
		speed *= 1.15
	if pc._adrenaline_timer > 0.0:
		speed *= 1.15
	if pc._has_affix(&"tenacity"):
		speed = maxf(speed, pc.walk_speed * 0.6)
	if not pc._is_swimming and pc.is_on_floor() and not pc._has_affix(&"sure_footed"):
		var floor_n := pc.get_floor_normal()
		if floor_n.y < 0.95 and floor_n.y > 0.3:
			var slope_penalty := 1.0 - (1.0 - floor_n.y) * 0.5
			speed *= clampf(slope_penalty, 0.6, 1.0)
	if direction.length() > 0.01:
		var accel := pc.acceleration if pc.is_on_floor() else pc.acceleration * pc.air_control
		pc.velocity.x = move_toward(pc.velocity.x, direction.x * speed, accel * delta)
		pc.velocity.z = move_toward(pc.velocity.z, direction.z * speed, accel * delta)
	else:
		var decel := pc.deceleration if pc.is_on_floor() else pc.deceleration * pc.air_control
		pc.velocity.x = move_toward(pc.velocity.x, 0.0, decel * delta)
		pc.velocity.z = move_toward(pc.velocity.z, 0.0, decel * delta)


func try_dodge() -> void:
	if not can_spend_stamina(pc.dodge_stamina_cost) or not pc.is_on_floor():
		return
	spend_stamina(pc.dodge_stamina_cost)
	pc._is_dodging = true
	pc._dodge_timer = pc.dodge_duration
	pc._is_blocking = false
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if input_dir.length_squared() > 0.01:
		var cam_basis := pc._camera_pivot.global_transform.basis
		pc._dodge_dir = (cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		pc._dodge_dir.y = 0.0
	else:
		pc._dodge_dir = -pc._camera_pivot.global_transform.basis.z
		pc._dodge_dir.y = 0.0
		pc._dodge_dir = pc._dodge_dir.normalized()


func tick_dodge(delta: float) -> void:
	pc.velocity.x = pc._dodge_dir.x * pc.dodge_speed
	pc.velocity.z = pc._dodge_dir.z * pc.dodge_speed
	pc._dodge_timer -= delta
	if pc._dodge_timer <= 0.0:
		pc._is_dodging = false


func handle_stamina(delta: float) -> void:
	if pc._is_blocking and not pc._has_affix(&"steadfast_guard"):
		spend_stamina(3.0 * delta)
	if pc._is_sprinting:
		var sprint_cost := pc.sprint_stamina_cost
		if pc._has_affix(&"fleet"):
			sprint_cost *= 0.75
		spend_stamina(sprint_cost * delta)
	else:
		pc._stamina_regen_timer -= delta
		if pc._stamina_regen_timer <= 0.0:
			var regen := pc.stamina_regen_rate
			if pc._has_affix(&"resilience"):
				regen *= 1.25
			pc.current_stamina = minf(pc.current_stamina + regen * delta, pc.max_stamina)
	GameEvents.player_stamina_changed.emit(pc.current_stamina, pc.max_stamina)


func can_spend_stamina(amount: float) -> bool:
	return pc.current_stamina >= amount


func spend_stamina(amount: float) -> void:
	pc.current_stamina = maxf(pc.current_stamina - amount, 0.0)
	pc._stamina_regen_timer = pc.stamina_regen_delay


func rotate_camera(mouse_delta: Vector2) -> void:
	pc._camera_pivot.rotate_y(-mouse_delta.x * pc.mouse_sensitivity)
	pc._spring_arm.rotation.x = clampf(
		pc._spring_arm.rotation.x - mouse_delta.y * pc.mouse_sensitivity,
		deg_to_rad(pc.min_pitch), deg_to_rad(pc.max_pitch)
	)
