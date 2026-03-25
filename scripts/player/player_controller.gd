class_name PlayerController
extends CharacterBody3D

const _DEBUG_LOG := false

# --- Movement tuning ---
@export_group("Movement")
@export var walk_speed: float = 6.24
@export var sprint_speed: float = 9.24
@export var crouch_speed: float = 2.0
@export var acceleration: float = 55.0
@export var deceleration: float = 65.0
@export var jump_velocity: float = 9.9
@export var gravity_multiplier: float = 2.34
@export var fall_gravity_multiplier: float = 3.2
@export var air_control: float = 0.3
@export var dodge_speed: float = 12.0
@export var dodge_duration: float = 0.3
@export var dodge_stamina_cost: float = 15.0

# --- Stamina ---
@export_group("Stamina")
@export var max_stamina: float = 115.0
@export var stamina_regen_rate: float = 15.0
@export var stamina_regen_delay: float = 1.5
@export var sprint_stamina_cost: float = 12.0

# --- Combat ---
@export_group("Combat")
@export var max_health: float = 100.0
@export var health_regen_rate: float = 2.0
@export var health_regen_delay: float = 5.0

# --- Camera ---
@export_group("Camera")
@export var mouse_sensitivity: float = 0.002
@export var min_pitch: float = -80.0
@export var max_pitch: float = 60.0
@export var zoom_speed: float = 0.5
@export var min_zoom: float = 2.0
@export var max_zoom: float = 12.0

var current_health: float
var current_stamina: float

var base_strength: int = 10
var base_dexterity: int = 10
var base_vitality: int = 10
var _stamina_regen_timer: float = 0.0
var _health_regen_timer: float = 0.0
var _is_sprinting: bool = false
var _is_crouching: bool = false
var _is_blocking: bool = false
var _double_jump_used: bool = false
var _auto_run: bool = false
var _walk_mode: bool = false
var _weapon_hidden: bool = false
var _attack_cooldown: float = 0.0
var _inventory_open: bool = false
var _map_open: bool = false
var _map_disabled: bool = false
var _map_zoom: float = 40.0
var _map_zoom_target: float = 40.0
const MAP_ZOOM_MIN := 8.0
const MAP_ZOOM_MAX := 100.0
const MAP_ZOOM_STEP := 6.0
const MAP_ZOOM_SPEED := 10.0
const MAP_PX := 512

var equipped_weapon: StringName = &"fists"
## Synced for multiplayer; updated when animation changes.
var synced_animation: String = ""
## Full equipment state for remote players (slot -> item_id).
var synced_equipped: Dictionary = {}
var _selected_slot: int = 0

# Affix system state
var _cached_affixes: Dictionary = {}
var _affix_cache_dirty: bool = true
var _windfury_guard: bool = false
var _momentum_stacks: int = 0
var _momentum_timer: float = 0.0
var _second_wind_cooldown: float = 0.0
var _thick_skinned_cooldown: float = 0.0
var _undying_cooldown: float = 0.0
var _adrenaline_timer: float = 0.0
var _regenerator_active: bool = false
var _prev_velocity_y: float = 0.0
var _fall_start_y: float = NAN
var _retaliation_timer: float = 0.0
var _crushing_momentum_timer: float = 0.0
var _aegis_shield: float = 0.0
var _aegis_timer: float = 0.0
var _rally_cry_active: bool = false
var _fortress_active: bool = false

# Build mode
var _build_mode: bool = false
var _build_from_workbench: bool = false
var _build_menu_open: bool = false
var _build_ghost: Node3D
var _build_selected: StringName = &""
var _build_rotation: float = 0.0
var _build_snap_enabled: bool = true
var _build_snapped: bool = false
var _build_snap_side: int = 0  # 0=forward 1=back 2=left 3=right 4=top 5=bottom
var _build_snap_side_label: Label = null
var _build_height_offset: float = 0.0
const BUILD_MAX_DISTANCE := 12.0
const BUILD_HEIGHT_STEP := 0.3
var _snap_label: Label
var _build_crosshair: Control
var _build_menu_panel: PanelContainer
var _build_menu_grid: GridContainer
var _workbench_panel: PanelContainer
var _workbench_grid: VBoxContainer
var _workbench_open: bool = false
var _workbench_category: String = "Tools"
var _workbench_tab_buttons: Array[Button] = []
var _workbench_quality_tier: String = "low"
var _workbench_tier_slider: HSlider
var _workbench_tier_row: HBoxContainer
var _workbench_tier_labels: Array[Label] = []
var _workbench_tier_info_panel: PanelContainer
var _workbench_auto_discard_star: int = -1
var _workbench_discard_btn: Button
var _workbench_preview_panel: PanelContainer
var _workbench_selected_id: StringName = &""
var _workbench_craft_btn: Button
var _workbench_equip_filter: String = "All"
var _workbench_equip_filter_row: HBoxContainer
var _workbench_equip_filter_buttons: Array[Button] = []
var _interact_prompt: Label
var _world_name_label: Label
var _fps_label: Label
var _interact_check_timer: float = 0.0
var _loot_check_timer: float = 0.0
var _chest_open: bool = false
var _chest_panel: PanelContainer
var _chest_grid: GridContainer
var _chest_node: Node3D

# Mounting
var _mounted: bool = false
var _mount_node: Node3D
var _mount_star_level: int = 0
var _mount_stamina: float = 100.0
var _mount_max_stamina: float = 100.0
var _mount_stamina_regen_timer: float = 0.0
var _on_raft: bool = false
var _raft_node: Node3D = null
var _raft_paddle_timer: float = 0.0
var _raft_paddle_side: bool = false  # false=left, true=right
var _last_safe_position: Vector3 = Vector3.ZERO
var _safe_pos_timer: float = 0.0
var _respawn_grace: float = 0.0
const MOUNT_SPEED_MULT_BASE := 2.0
const MOUNT_SPEED_PER_STAR := 0.2
const MOUNT_STAMINA_COST := 14.0
const MOUNT_STAMINA_REGEN_RATE := 18.0
const MOUNT_STAMINA_REGEN_DELAY := 1.2

# Flight mode (debug): 150% of a 5-star horse sprint speed
var flight_mode: bool = true
const FLIGHT_SPEED := 34.65


func _get_mount_speed_mult() -> float:
	return MOUNT_SPEED_MULT_BASE + _mount_star_level * MOUNT_SPEED_PER_STAR
var _horse_walk_frames: Dictionary = {}  # {dir -> Array[Texture2D]}
var _horse_run_frames: Dictionary = {}   # {dir -> Array[Texture2D]}
var _horse_anim_idx: int = 0
var _horse_anim_timer: float = 0.0
var _sit_idle_frames: Dictionary = {}  # {dir -> Array[Texture2D]}
var _sit_idle_anim_idx: int = 0
var _sit_idle_anim_timer: float = 0.0

# Cave instancing
var _in_cave: bool = false
var _cave_instance: Node3D = null
var _cave_return_pos: Vector3 = Vector3.ZERO
var _cave_entrance_node: Node3D = null

# Movement audio â€” dedicated looping players (one per sound type, no stacking)
var _footstep_player: AudioStreamPlayer
var _gallop_player: AudioStreamPlayer
var _gallop_fast_stream: AudioStream
var _gallop_normal_stream: AudioStream

# Bow draw
var _bow_drawing: bool = false
var _bow_tension: float = 0.0
var _bow_creak_player: AudioStreamPlayer3D = null
const BOW_MAX_DRAW_TIME := 1.2
const BOW_MIN_DAMAGE_MULT := 0.2
const BOW_MAX_DAMAGE_MULT := 2.0
const BOW_RETICLE_MAX_RADIUS := 60.0
const BOW_RETICLE_MIN_RADIUS := 6.0
var _bow_reticle: Control

# Dodge
var _is_dodging: bool = false
var _dodge_timer: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO

# Swimming / buoyancy
var _is_swimming := false
var _swim_time := 0.0
const SWIM_SPEED := 3.0
const SWIM_SPRINT_SPEED := 4.5
const BUOYANCY_FORCE := 12.0
const WATER_DAMPING := 4.0
const SWIM_STAMINA_COST := 6.0

# Swim fatigue / drowning
var _swim_fatigue: float = 0.0
const SWIM_FATIGUE_MAX: float = 15.0
const SWIM_FATIGUE_RECOVER_RATE: float = 5.0
var _swim_fatigue_pulse: float = 0.0
var _drown_tick_timer: float = 0.0
const _DROWN_TICK_INTERVAL: float = 2.0
const _DROWN_TICK_FRACTION: float = 0.13

# HUD drown bar (2D, above hotbar)
var _drown_bar_container: Control
var _drown_bar_fill: ColorRect
var _drown_bar_bg: ColorRect

# Jump animation
var _is_jumping := false
var _is_flipping := false
var _jump_frames: Dictionary = {}
var _flip_frames: Dictionary = {}
var _jump_frame_idx := 0
var _jump_frame_timer := 0.0
const _JUMP_FRAME_DURATION := 0.08

# Drag-to-hotbar state
var _dragging_item: StringName = &""
var _drag_from_slot: int = -1
var _drag_icon: TextureRect

# Valheim-style equip progress bar
var _equip_progresses: Dictionary = {}  # slot_idx -> {item, progress, bar}
const EQUIP_HOLD_TIME := 0.5

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _spring_arm: SpringArm3D = $CameraPivot/SpringArm3D
@onready var _model: Node3D = $PlayerModel if has_node("PlayerModel") else null

var _player_sprite: Node3D
var _player_model_3d: PlayerModel3D
var _gltf_anim_player: AnimationPlayer
var _gltf_current_anim := ""
var _gltf_playing_clip := ""
var _gltf_playing_speed: float = 1.0
var _gltf_all_meshes: Array[MeshInstance3D] = []
var _is_lowpoly_viking := false
var _player_yaw_offset := 0.0
var _gltf_play_warned := {}
var _gltf_attack_anim := ""
var _gltf_attack_timer := 0.0
var _equipped_weapon_node: Node3D = null
var _r_hand_anchor: Node3D = null
var _l_hand_anchor: Node3D = null
var _back_anchor: Node3D = null
var _weapon_drawn := false
var _weapon_back_transform: Dictionary = {}  # scale, pos, rot for back
var _weapon_hand_transform: Dictionary = {}  # scale, pos, rot for hand
var _cached_l_upper_arm: Node3D = null
var _cached_l_forearm: Node3D = null
var _cached_l_hand: Node3D = null
var _l_grip_marker: Node3D = null
var _bow_arrow_node: Node3D = null
var _quiver_node: Node3D = null
var _armor_nodes: Dictionary = {}  # { "chest": Node3D, "legs": Node3D, "feet": Node3D }
var _cached_torso_bones: Dictionary = {}  # bone_name -> {node, rest_pos}
var _unarmed_attack_time := 0.0
var _unarmed_attack_duration := 0.0
var _base_sprite_y := 0.82
var _player_textures: Dictionary = {}
var _attack_frames: Dictionary = {}
var _fist_frames: Dictionary = {}
var _kick_frames_attack: Dictionary = {}
var _weapon_attack_frames: Dictionary = {}
var _pickaxe_attack_frames: Dictionary = {}
var _sword_attack_frames: Dictionary = {}
var _bow_attack_frames: Dictionary = {}
var _run_frames: Dictionary = {}
var _is_attacking := false
var _attack_frame_idx := 0
var _attack_frame_timer := 0.0
var _current_attack_dir := "south"

var _is_run_animating := false
var _run_frame_idx := 0
var _run_frame_timer := 0.0
var _current_run_dir := "south"

# Idle breathing animation
var _idle_frames: Dictionary = {}
var _idle_frame_idx := 0
var _idle_frame_timer := 0.0
var _current_idle_dir := "south"
const _IDLE_FRAME_DURATION := 0.35
const _RUN_FRAME_DURATION := 0.1
const _SPRINT_FRAME_DURATION := 0.07
const _SPRITE_BASE_Y := 0.9

const ATTACK_FRAME_DURATION_FIST := 0.05
const ATTACK_FRAME_DURATION_TOOL := 0.07
const ATTACK_FRAME_DURATION_BOW := 0.08
var _current_attack_frame_duration := 0.06
const _DamageNumber := preload("res://scripts/ui/damage_number.gd")
const _LootDrop := preload("res://scripts/items/loot_drop.gd")
const _PlayerCombat := preload("res://scripts/player/player_combat.gd")

# Floating bars above player (3D, shader-driven)
var _bar_anchor: Node3D
var _hp_bar: MeshInstance3D
var _stam_bar: MeshInstance3D
var _mount_stam_bar: MeshInstance3D
var _hp_pulse: float = 0.0
var _bar_shader: Shader
var _remote_nameplate_label: Label3D = null
var _synced_position: Vector3 = Vector3.ZERO
var character_display_name: String = ""
var _rpc_sync_tick: int = 0
var _last_broadcast_clip: String = ""

# HUD references
var _hud_root: Control
var _pause_overlay: CanvasLayer
var _pause_open := false
var _pause_res_options: OptionButton
var _pause_mode_options: OptionButton
var _pause_resolutions: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]
var _debug_panel: Node  # DebugPanel (CanvasLayer)
var _target_hud_panel: PanelContainer
var _target_hud_name: Label
var _target_hud_stars: Label
var _target_hud_hp_bar: ColorRect
var _target_hud_hp_fill: ColorRect
var _target_hud_hp_label: Label
var _target_creature: Node3D = null
var _target_hud_timer: float = 0.0
var _chat_panel: PanelContainer
var _chat_log: VBoxContainer
var _chat_input: LineEdit
var _chat_focused: bool = false
var _chat_scroll: ScrollContainer
var _chat_fade_timer: float = 0.0
var _chat_visible: bool = false
var _player_list_panel: PanelContainer
var _player_list_visible: bool = false
var _inventory_panel: PanelContainer
var _inventory_grid: GridContainer
var _cached_grouped: Array = []
var _equip_bar: Control
var _equip_bar_slots: Dictionary = {}
var _equip_bar_icons: Dictionary = {}
var _equip_bar_ghost: Dictionary = {}
var _torch_light: OmniLight3D
var _stats_panel: PanelContainer
var _stats_arrow: Button
var _stats_open: bool = false
var _stats_labels: Dictionary = {}
var _crafting_panel: PanelContainer
var _crafting_grid: VBoxContainer
var _hotbar_slots: Array[PanelContainer] = []
var _hotbar_labels: Array[Label] = []
var _hotbar_icons: Array[TextureRect] = []
var _hotbar_qty_labels: Array[Label] = []
var _tooltip_panel: PanelContainer
var _tooltip_label: RichTextLabel
var _map_panel: PanelContainer
var _map_biome_label: Label
var _map_texture_rect: TextureRect
var _map_image: Image
var _map_image_tex: ImageTexture
var _map_circle_mask: Image
var _map_dirty := true
var _map_last_player_pos := Vector3.ZERO
var _map_refresh_timer := 0.0
var _map_fog_time := 0.0
var _map_fog_noise: FastNoiseLite

const MINIMAP_PX := 180
const MINIMAP_RING := 5
var _minimap_zoom: float = 6.0
const MINIMAP_ZOOM_MIN := 3.0
const MINIMAP_ZOOM_MAX := 20.0
const MINIMAP_ZOOM_STEP := 1.5
var _minimap_tex_rect: TextureRect
var _minimap_image: Image
var _minimap_image_tex: ImageTexture
var _minimap_circle_mask: Image
var _minimap_player_arrow_img: Image
var _minimap_biome_label: Label
var _minimap_weather_label: Label
var _minimap_time_label: Label
var _minimap_refresh_timer := 0.0
var _minimap_needs_refresh := true
var _minimap_paused := false
var _minimap_outer: Control

## Phase 5: Report player data to host for save on disconnect
const _REPORT_DATA_INTERVAL := 8.0
var _report_data_timer := 0.0

var _movement: PlayerMovement
var _combat: Node
var _building: PlayerBuilding
var _inventory_ui: PlayerInventoryUI
var _workbench_ui: PlayerWorkbenchUI
var _hud_module: PlayerHUD
var _interaction: PlayerInteraction
var _anim: PlayerAnimation


func _set_player_sprite_tex(_tex: Texture2D) -> void:
	pass


func _ready() -> void:
	# In multiplayer, the node name is the peer ID (set by NetworkManager).
	# Both host and client create player nodes via _create_player_node / _rpc_create_player.
	# Ensure authority matches the peer ID encoded in the node name.
	if multiplayer.has_multiplayer_peer() and name.is_valid_int():
		var peer_id := name.to_int()
		set_multiplayer_authority(peer_id)
		if _DEBUG_LOG: print("[PLAYER] _ready: name=%s peer_id=%d my_id=%d is_authority=%s" % [name, peer_id, multiplayer.get_unique_id(), str(is_multiplayer_authority())])

	if not is_multiplayer_authority():
		set_process_unhandled_input(false)
		set_process_input(false)
		if _camera_pivot:
			_camera_pivot.queue_free()
			_camera_pivot = null
		_synced_position = global_position
		add_to_group(&"player")
		_setup_multiplayer_sync()
		_setup_player_sprite()
		_setup_remote_nameplate()
		_setup_floating_bars()
		var anim_list: PackedStringArray = _gltf_anim_player.get_animation_list() if _gltf_anim_player else PackedStringArray()
		if _DEBUG_LOG: print("[PLAYER] Remote peer '%s' setup complete | model=%s sprite=%s anim_player=%s anims=%s pos=%s" % [
			name, str(_model != null), str(_player_sprite != null),
			str(_gltf_anim_player != null), str(anim_list), str(global_position)])
		return

	if _DEBUG_LOG: print("[PLAYER] LOCAL player setup starting for peer %s (my_id=%d) pos=%s" % [name, multiplayer.get_unique_id(), str(global_position)])
	if not SaveManager._settings_loaded:
		var _music_bus := AudioServer.get_bus_index(&"Music")
		if _music_bus != -1:
			AudioServer.set_bus_volume_db(_music_bus, linear_to_db(0.05))
		var _sfx_bus := AudioServer.get_bus_index(&"SFX")
		if _sfx_bus != -1:
			AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(0.07))
	current_health = max_health
	current_stamina = max_stamina
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	add_to_group(&"player")
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(55.0)
	_respawn_grace = 3.0

	_movement = PlayerMovement.new()
	_movement.name = "PlayerMovement"
	add_child(_movement)
	_movement.pc = self

	_combat = _PlayerCombat.new()
	_combat.name = "PlayerCombat"
	add_child(_combat)
	_combat.pc = self

	_building = PlayerBuilding.new()
	_building.name = "PlayerBuilding"
	add_child(_building)
	_building.pc = self

	_inventory_ui = PlayerInventoryUI.new()
	_inventory_ui.name = "PlayerInventoryUI"
	add_child(_inventory_ui)
	_inventory_ui.pc = self

	_workbench_ui = PlayerWorkbenchUI.new()
	_workbench_ui.name = "PlayerWorkbenchUI"
	add_child(_workbench_ui)
	_workbench_ui.pc = self

	_hud_module = PlayerHUD.new()
	_hud_module.name = "PlayerHUD"
	add_child(_hud_module)
	_hud_module.pc = self

	_interaction = PlayerInteraction.new()
	_interaction.name = "PlayerInteraction"
	add_child(_interaction)
	_interaction.pc = self

	_anim = PlayerAnimation.new()
	_anim.name = "PlayerAnimation"
	add_child(_anim)
	_anim.pc = self

	# Per-player inventory: reuse existing local inventory (already populated by
	# SaveManager._deferred_load_save or give_starting_gear before the player node exists)
	var my_inventory := Inventory.get_local()
	if multiplayer.multiplayer_peer:
		Inventory.register_inventory(multiplayer.get_unique_id(), my_inventory)

	_setup_multiplayer_sync()
	_setup_player_sprite()
	if NetworkManager.is_connected_to_game():
		character_display_name = str(SaveManager.current_character.get("name", "Unknown"))
		call_deferred("_broadcast_display_name")
		call_deferred("_announce_join")
	_setup_floating_bars()
	_build_hud()
	if _spring_arm:
		_spring_arm.spring_length = min_zoom + 0.85 * (max_zoom - min_zoom)
	# Delay camera activation and terrain snap by one frame to let the scene tree settle
	call_deferred("_activate_camera")
	call_deferred("_snap_to_terrain")
	_setup_movement_audio()
	GameEvents.inventory_changed.connect(_on_inventory_changed)
	if NetworkManager.is_connected_to_game():
		NetworkManager.chest_contents_received.connect(_on_chest_contents_received)


func _activate_camera() -> void:
	if not is_multiplayer_authority():
		return
	var cam := get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if cam:
		cam.make_current()
		if _DEBUG_LOG: print("[PLAYER] Camera NOW ACTIVE for peer %s at pos %s" % [name, str(global_position)])
	else:
		push_error("[PLAYER] CAMERA NOT FOUND for peer %s! CameraPivot=%s SpringArm=%s" % [name, str(_camera_pivot), str(_spring_arm)])


func _snap_to_terrain() -> void:
	if not is_multiplayer_authority():
		return
	var wg := _find_world_generator()
	if wg:
		var terrain_y: float = wg.get_height_at_scene(global_position.x, global_position.z) + 0.5
		if global_position.y > terrain_y + 5.0:
			global_position.y = terrain_y
			velocity = Vector3.ZERO
			if _DEBUG_LOG: print("[PLAYER] Snapped to terrain at Y=%.1f (was too high)" % terrain_y)
	else:
		global_position.y = 0.5
		velocity = Vector3.ZERO
		if _DEBUG_LOG: print("[PLAYER] No WorldGenerator found, defaulting to Y=0.5")


func _on_chest_contents_received(chest_path: String, contents: Array) -> void:
	var chest := get_tree().root.get_node_or_null(chest_path) as Node3D
	if not chest:
		return
	chest.set_meta("chest_contents", contents)
	if _chest_node == null:
		_interaction.open_chest(chest)
	elif _chest_node == chest:
		_interaction.refresh_chest_ui()
		_refresh_inventory_ui()


func _exit_tree() -> void:
	if is_multiplayer_authority():
		if multiplayer.multiplayer_peer:
			Inventory.unregister_inventory(multiplayer.get_unique_id())
		if NetworkManager.is_connected_to_game():
			NetworkManager.chest_contents_received.disconnect(_on_chest_contents_received)


func _report_player_data_to_host() -> void:
	## Phase 5: Report our player and inventory data to host for save on disconnect.
	var char_id: String = str(SaveManager.current_character.get("id", ""))
	var wp := global_position
	var wg := _find_world_generator()
	if wg:
		wp = wg.get_world_position(self)
	var player_data := {
		"position": {"x": wp.x, "y": wp.y, "z": wp.z},
		"rotation_y": rotation.y,
		"health": current_health,
		"stamina": current_stamina,
		"equipped_weapon": str(equipped_weapon),
		"selected_slot": _selected_slot,
		"base_strength": base_strength,
		"base_dexterity": base_dexterity,
		"base_vitality": base_vitality,
	}
	var inv := Inventory.get_local()
	var inv_data: Dictionary = {}
	if inv:
		inv_data["items"] = inv.get_all_items().duplicate()
		var order_strings: Array[String] = []
		for sid: StringName in inv.get_order():
			order_strings.append(String(sid))
		inv_data["order"] = order_strings
		var eq: Dictionary = {}
		for slot: String in inv.get_all_equipped().keys():
			eq[slot] = String(inv.get_equipped(slot))
		inv_data["equipped"] = eq
	NetworkManager.report_player_data.rpc_id(1, char_id, player_data, inv_data)


func _setup_multiplayer_sync() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var sync := get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
	if not sync:
		sync = MultiplayerSynchronizer.new()
		sync.name = "MultiplayerSynchronizer"
		sync.root_path = NodePath("..")
		var cfg := SceneReplicationConfig.new()
		sync.replication_config = cfg
		cfg.add_property(NodePath(":_synced_position"))
		cfg.property_set_replication_mode(NodePath(":_synced_position"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		cfg.add_property(NodePath(":velocity"))
		cfg.property_set_replication_mode(NodePath(":velocity"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		cfg.add_property(NodePath(":rotation"))
		cfg.property_set_replication_mode(NodePath(":rotation"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		cfg.add_property(NodePath(":synced_animation"))
		cfg.property_set_replication_mode(NodePath(":synced_animation"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
		cfg.add_property(NodePath(":equipped_weapon"))
		cfg.property_set_replication_mode(NodePath(":equipped_weapon"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
		cfg.add_property(NodePath(":synced_equipped"))
		cfg.property_set_replication_mode(NodePath(":synced_equipped"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
		cfg.add_property(NodePath(":character_display_name"))
		cfg.property_set_replication_mode(NodePath(":character_display_name"), SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
		sync.set_multiplayer_authority(get_multiplayer_authority())
		add_child(sync)
		if _DEBUG_LOG: print("[SYNC] Created MultiplayerSynchronizer for '%s' | player_auth=%d sync_auth=%d root_path='%s' resolved='%s'" % [
			name, get_multiplayer_authority(), sync.get_multiplayer_authority(),
			str(sync.root_path), str(sync.get_node(sync.root_path).get_path()) if sync.get_node_or_null(sync.root_path) else "UNRESOLVED"])
	else:
		if _DEBUG_LOG: print("[SYNC] Reusing existing MultiplayerSynchronizer for '%s' | player_auth=%d sync_auth=%d" % [
			name, get_multiplayer_authority(), sync.get_multiplayer_authority()])
	if not is_multiplayer_authority():
		sync.synchronized.connect(_on_sync_received)


func _setup_remote_nameplate() -> void:
	## Floating Label3D above remote players showing character name.
	_remote_nameplate_label = Label3D.new()
	_remote_nameplate_label.name = "RemoteNameplate"
	_remote_nameplate_label.text = character_display_name if character_display_name != "" else "Player"
	_remote_nameplate_label.font_size = 28
	_remote_nameplate_label.pixel_size = 0.00096
	_remote_nameplate_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_remote_nameplate_label.fixed_size = true
	_remote_nameplate_label.no_depth_test = false
	_remote_nameplate_label.modulate = Color.WHITE
	_remote_nameplate_label.outline_modulate = Color(0, 0, 0, 0.9)
	_remote_nameplate_label.outline_size = 6
	_remote_nameplate_label.render_priority = 1
	_remote_nameplate_label.position = Vector3(0.0, 4.5, 0.0)
	add_child(_remote_nameplate_label)


var _sync_diag_count: int = 0

func _on_sync_received() -> void:
	_sync_diag_count += 1
	if _sync_diag_count <= 3 or _sync_diag_count % 300 == 0:
		if _DEBUG_LOG: print("[SYNC-RECV] peer '%s' sync #%d | pos=%s anim='%s' weapon='%s'" % [
			name, _sync_diag_count, str(_synced_position), synced_animation, str(equipped_weapon)])
	_update_equipped_weapon_model()
	if _remote_nameplate_label and character_display_name != "":
		_remote_nameplate_label.text = character_display_name


@rpc("any_peer", "unreliable")
func _broadcast_state(pos: Vector3, model_rot_y: float, vel: Vector3, anim_clip: String, anim_speed: float, weapon: StringName, hp: float = -1.0, hp_max: float = -1.0, stam: float = -1.0, stam_max: float = -1.0) -> void:
	if is_multiplayer_authority():
		return
	var _wg := _find_world_generator()
	_synced_position = _wg.world_to_scene_pos(pos) if _wg else pos
	velocity = vel
	_remote_model_target_yaw = model_rot_y
	_remote_model_yaw_set = true
	if hp_max > 0.0:
		current_health = hp
		max_health = hp_max
		current_stamina = stam
		max_stamina = stam_max
	if anim_clip != "" and _gltf_anim_player:
		var has_anim := _gltf_anim_player.has_animation(anim_clip)
		if not has_anim:
			if _gltf_playing_clip != anim_clip:
				if _DEBUG_LOG: print("[ANIM-RECV] Animation '%s' NOT FOUND on remote player '%s'" % [anim_clip, name])
		else:
			var clip_changed := _gltf_playing_clip != anim_clip
			var speed_changed := not is_equal_approx(_gltf_playing_speed, anim_speed)
			# Re-trigger finished non-looping anims (attacks); skip for intentionally paused (idle)
			var stopped := anim_speed > 0.01 and not _gltf_anim_player.is_playing()
			if clip_changed or speed_changed or stopped:
				if clip_changed:
					if _DEBUG_LOG: print("[ANIM-RECV] Playing '%s' speed=%.1f on remote '%s'" % [anim_clip, anim_speed, name])
				_gltf_playing_clip = anim_clip
				_gltf_playing_speed = anim_speed
				_gltf_current_anim = anim_clip
				synced_animation = anim_clip
				_gltf_anim_player.speed_scale = maxf(anim_speed, 0.001)
				_gltf_anim_player.play(anim_clip)
				if anim_speed <= 0.01:
					_gltf_anim_player.seek(0.0, true)
					_gltf_anim_player.pause()

	if weapon != equipped_weapon:
		equipped_weapon = weapon
		_update_equipped_weapon_model()


@rpc("any_peer", "reliable")
func _receive_display_name(display_name: String) -> void:
	if is_multiplayer_authority():
		return
	character_display_name = display_name
	if _remote_nameplate_label:
		_remote_nameplate_label.text = display_name


func _broadcast_display_name() -> void:
	if not is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		return
	_receive_display_name.rpc(character_display_name)


func _announce_join() -> void:
	if not is_multiplayer_authority() or not multiplayer.has_multiplayer_peer():
		return
	ChatManager.announce_join(character_display_name)


@rpc("any_peer", "reliable")
func _broadcast_equipment(equipment: Dictionary) -> void:
	if is_multiplayer_authority():
		return
	synced_equipped = equipment
	_update_equipped_weapon_model()
	call_deferred("_update_armor_visuals")


func _on_inventory_changed() -> void:
	_invalidate_affix_cache()
	_apply_affix_stat_bonuses()
	_refresh_inventory_ui()
	_refresh_equip_bar()
	_update_hotbar_selection()
	if _player_sprite:
		_update_armor_visuals()
	# Don't override equipped_weapon if a tool is active from the hotbar
	var hotbar := _get_hotbar_items()
	var active_item: StringName = hotbar[_selected_slot] if _selected_slot < hotbar.size() else &""
	var active_data: Dictionary = ItemDatabase.get_item(active_item) if active_item != &"" else {}
	if str(active_data.get("type", "")) == "tool":
		equipped_weapon = active_item
	else:
		var new_weapon: StringName = Inventory.get_equipped("sword")
		if new_weapon == &"":
			new_weapon = &"fists"
		if new_weapon != equipped_weapon:
			equipped_weapon = new_weapon
			_update_equipped_weapon_model()
	synced_equipped = Inventory.get_all_equipped().duplicate()
	if NetworkManager.is_connected_to_game() and is_multiplayer_authority():
		_broadcast_equipment.rpc(synced_equipped)
	_refresh_stats_panel()
	_position_stats_panel.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()


func _input(event: InputEvent) -> void:
	if _workbench_open and (event.is_action_pressed(&"interact") or event.is_action_pressed(&"inventory") or event.is_action_pressed(&"quit_game")):
		_workbench_ui.close_workbench()
		get_viewport().set_input_as_handled()
		return
	if (_build_menu_open or _build_mode) and event.is_action_pressed(&"block"):
		_toggle_build_menu()
		get_viewport().set_input_as_handled()
		return


func _unhandled_input(event: InputEvent) -> void:
	# Debug: F9/F10 cycle animations to identify them
	if event is InputEventKey and (event as InputEventKey).pressed and _gltf_anim_player:
		var ke := event as InputEventKey
		if ke.physical_keycode == KEY_F9 or ke.physical_keycode == KEY_F10:
			var all_anims := _gltf_anim_player.get_animation_list()
			if all_anims.is_empty():
				return
			if ke.physical_keycode == KEY_F9:
				_nla_debug_index = (_nla_debug_index - 1) if _nla_debug_index > 0 else all_anims.size() - 1
			else:
				_nla_debug_index = (_nla_debug_index + 1) % all_anims.size()
			var track_name: String = all_anims[_nla_debug_index]
			_gltf_anim_player.play(track_name)
			_gltf_anim_player.speed_scale = 1.0
			var anim := _gltf_anim_player.get_animation(track_name)
			if _DEBUG_LOG: print("[ANIM DEBUG] Playing #%d: %s (%.2fs)" % [_nla_debug_index, track_name, anim.length if anim else 0.0])
			return

	# F3 toggles debug panel
	if event is InputEventKey and (event as InputEventKey).pressed:
		var ke := event as InputEventKey
		if ke.physical_keycode == KEY_F3:
			_ensure_debug_panel()
			_debug_panel.toggle_panel()
			get_viewport().set_input_as_handled()
			return

	# Alt+F4 or Cmd+F4 always quits immediately
	if event is InputEventKey and (event as InputEventKey).pressed:
		var ke := event as InputEventKey
		if (ke.alt_pressed or ke.meta_pressed) and ke.physical_keycode == KEY_F4:
			get_tree().quit()
			return

	if event.is_action_pressed(&"chat") and _chat_input and not _chat_focused:
		_chat_input.grab_focus()
		_chat_focused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"player_list") and _player_list_panel and NetworkManager.is_connected_to_game():
		_player_list_visible = not _player_list_visible
		_player_list_panel.visible = _player_list_visible
		if _player_list_visible:
			_hud_module._refresh_player_list(self)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"quit_game"):
		if _pause_open:
			_close_pause_menu()
			return
		if _debug_panel and is_instance_valid(_debug_panel) and _debug_panel.visible:
			_debug_panel.toggle_panel()
			return
		if _bow_drawing:
			_cancel_bow_draw()
			return
		if _chest_open:
			_interaction.close_chest()
		elif _workbench_open:
			_workbench_ui.close_workbench()
		elif _build_mode:
			_cancel_build_mode()
		elif _build_menu_open:
			_close_build_menu()
		elif _map_open:
			_close_map()
		elif _inventory_open:
			_close_inventory()
		else:
			_open_pause_menu()
		return

	if event.is_action_pressed(&"inventory"):
		if _chest_open:
			_interaction.close_chest()
			return
		if _build_menu_open:
			_close_build_menu()
			return
		if _build_mode:
			_cancel_build_mode()
			return
		if _map_open:
			_close_map()
		_toggle_inventory()
		return

	if event.is_action_pressed(&"map"):
		if _chest_open:
			_interaction.close_chest()
		if _inventory_open:
			_close_inventory()
		_toggle_map()
		return

	if _build_mode and event is InputEventKey and (event as InputEventKey).pressed:
		var ke := event as InputEventKey
		if ke.physical_keycode == KEY_SHIFT:
			_build_snap_enabled = not _build_snap_enabled
			if _snap_label:
				_snap_label.text = "Snap: ON" if _build_snap_enabled else "Snap: OFF"
				_snap_label.add_theme_color_override("font_color",
					Color(0.6, 1.0, 0.6) if _build_snap_enabled else Color(1.0, 0.5, 0.5))
			return
		if ke.physical_keycode == KEY_ALT:
			_build_snap_side = (_build_snap_side + 1) % 6
			_update_snap_side_label()
			return

	if _build_mode and event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.ctrl_pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_build_height_offset += BUILD_HEIGHT_STEP
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_build_height_offset -= BUILD_HEIGHT_STEP
				return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _build_snapped:
				_build_rotation = snappedf(_build_rotation - deg_to_rad(45.0), deg_to_rad(45.0))
			else:
				_build_rotation -= deg_to_rad(15.0)
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _build_snapped:
				_build_rotation = snappedf(_build_rotation + deg_to_rad(45.0), deg_to_rad(45.0))
			else:
				_build_rotation += deg_to_rad(15.0)
			return

	# Map zoom with scroll wheel â€” smooth target, no instant rebuild
	if _map_open and event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_map_zoom_target = clampf(_map_zoom_target - MAP_ZOOM_STEP, MAP_ZOOM_MIN, MAP_ZOOM_MAX)
			_map_dirty = true
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_map_zoom_target = clampf(_map_zoom_target + MAP_ZOOM_STEP, MAP_ZOOM_MIN, MAP_ZOOM_MAX)
			_map_dirty = true
			return

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		if not _inventory_open and not _workbench_open and not _build_menu_open and not _map_open and not _chest_open:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	for i in range(8):
		var action_name: String = "hotbar_%d" % (i + 1)
		if event.is_action_pressed(StringName(action_name)):
			if _bow_drawing:
				_cancel_bow_draw()
			_selected_slot = i
			var hotbar := _get_hotbar_items()
			var slot_item: StringName = hotbar[i] if hotbar[i] != &"" else &""
			var slot_data: Dictionary = ItemDatabase.get_item(slot_item) if slot_item != &"" else {}
			if str(slot_data.get("type", "")) == "tool":
				equipped_weapon = slot_item
				_update_equipped_weapon_model()
			elif slot_data.has("armor_slot") and str(slot_data["armor_slot"]) == "weapon":
				Inventory.equip_armor(slot_item)
			else:
				var new_weapon: StringName = Inventory.get_equipped("sword")
				if new_weapon == &"":
					new_weapon = &"fists"
				equipped_weapon = new_weapon
				_update_equipped_weapon_model()
			if _build_menu_open:
				_close_build_menu()
			if _build_mode:
				_cancel_build_mode()
			_update_hotbar_selection()

	# Hammer right-click -> toggle build menu (must be checked before the mouse-mode gate)
	if event.is_action_pressed(&"block") and equipped_weapon == &"hammer" and not _inventory_open:
		_toggle_build_menu()
		return

	# Hammer middle-click -> salvage structure
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_MIDDLE and (event as InputEventMouseButton).pressed:
		if equipped_weapon == &"hammer" and not _inventory_open and not _build_mode and not _build_menu_open:
			_try_salvage_structure()
			return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or _inventory_open:
		return

	# Build mode: left-click places, right-click/ESC cancels
	if _build_mode:
		if event.is_action_pressed(&"attack"):
			_place_build()
			return
		if event.is_action_pressed(&"block") or event.is_action_pressed(&"ui_cancel"):
			_cancel_build_mode()
			return

	if event.is_action_pressed(&"attack"):
		if _bow_drawing:
			_fire_bow()
			return
		_try_attack()
		return

	if event.is_action_pressed(&"jump") and _is_blocking and not _is_dodging:
		_try_dodge()
		return

	if event is InputEventMouseMotion:
		_rotate_camera(event.relative)

	if event.is_action_pressed(&"zoom_in"):
		_spring_arm.spring_length = maxf(_spring_arm.spring_length - zoom_speed, min_zoom)
	elif event.is_action_pressed(&"zoom_out"):
		_spring_arm.spring_length = minf(_spring_arm.spring_length + zoom_speed, max_zoom)

	if event.is_action_pressed(&"interact"):
		_interaction.try_interact()
	if event.is_action_pressed(&"auto_run"):
		_auto_run = not _auto_run
	if event.is_action_pressed(&"toggle_walk"):
		_walk_mode = not _walk_mode
	if event.is_action_pressed(&"hide_weapon"):
		_weapon_hidden = not _weapon_hidden


var _remote_diag_timer: float = 0.0
var _remote_model_target_yaw: float = 0.0
var _remote_model_yaw_set: bool = false

func _physics_process(delta: float) -> void:
	var _phys_t0 := Time.get_ticks_usec()
	if not is_multiplayer_authority():
		global_position = global_position.lerp(_synced_position, delta * 15.0)
		if _gltf_anim_player:
			_gltf_anim_player.advance(delta)
		if _model and _remote_model_yaw_set:
			_model.rotation.y = lerp_angle(_model.rotation.y, _remote_model_target_yaw, 0.2)
		_update_floating_bars(delta)
		_remote_diag_timer += delta
		if _remote_diag_timer >= 3.0:
			_remote_diag_timer = 0.0
			var anim_info := ""
			if _gltf_anim_player:
				anim_info = "clip='%s' playing=%s speed=%.1f" % [
					_gltf_playing_clip, str(_gltf_anim_player.is_playing()),
					_gltf_anim_player.speed_scale]
			if _DEBUG_LOG: print("[REMOTE] peer '%s' | pos=%s sync=%d %s" % [
				name, str(global_position), _sync_diag_count, anim_info])
		return

	var wants_block := Input.is_action_pressed(&"block") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _inventory_open
	var _bow_slot_item: StringName = Inventory.get_equipped("bow")
	var _has_bow_equipped := _bow_slot_item != &""
	if _has_bow_equipped:
		_is_blocking = false
		_tick_bow_draw(delta, wants_block)
	else:
		_is_blocking = wants_block and equipped_weapon != &"hammer"
		_tick_bow_draw(delta, false)
	_is_crouching = Input.is_action_pressed(&"crouch")

	if flight_mode:
		_handle_flight(delta)
	else:
		if not _on_raft:
			_apply_gravity(delta)

		if _respawn_grace > 0.0 and velocity.y > 0.0:
			velocity.y = 0.0

		if _on_raft:
			pass
		elif _is_dodging:
			_tick_dodge(delta)
		else:
			_handle_jump()
			_handle_movement(delta)

		if _mounted:
			var flat_spd := Vector2(velocity.x, velocity.z).length()
			var max_mount_spd := sprint_speed * _get_mount_speed_mult() * 1.1
			if flat_spd > max_mount_spd:
				var scale_f := max_mount_spd / flat_spd
				velocity.x *= scale_f
				velocity.z *= scale_f

		var pre_move_pos := global_position
		var was_in_air := not is_on_floor()
		if not _on_raft:
			_step_up_move_and_slide()

		if was_in_air and is_on_floor():
			var height_fallen: float = 0.0 if is_nan(_fall_start_y) else _fall_start_y - global_position.y
			if height_fallen > 5.0:
				# True damage: 1 dmg/unit beyond 5u safe zone, only featherfall reduces
				var fall_dmg := (height_fallen - 5.0) * 1.0
				if _has_affix(&"featherfall"):
					fall_dmg *= (1.0 - _affix_val(&"featherfall"))
				if fall_dmg > 0.5:
					current_health = maxf(current_health - fall_dmg, 0.0)
					_hp_pulse = 1.0
					_health_regen_timer = health_regen_delay
					GameEvents.player_health_changed.emit(current_health, max_health)
					DamageNumber.spawn(get_tree(), global_position + Vector3.UP * 2.0, fall_dmg, false, "enemy")
					if current_health <= 0.0:
						_on_death()
		elif not was_in_air and not is_on_floor():
			_fall_start_y = global_position.y
		if is_nan(_fall_start_y):
			_fall_start_y = global_position.y
		_prev_velocity_y = velocity.y

		if _mounted and not _in_cave:
			var y_drop := pre_move_pos.y - global_position.y
			if y_drop > 2.0:
				global_position.y = pre_move_pos.y - 2.0
				velocity.y = maxf(velocity.y, -12.0)
			var space := get_world_3d().direct_space_state
			if space:
				var check_from := Vector3(global_position.x, global_position.y + 3.0, global_position.z)
				var check_to := Vector3(global_position.x, global_position.y - 10.0, global_position.z)
				var q := PhysicsRayQueryParameters3D.create(check_from, check_to, 1)
				q.exclude = [get_rid()]
				var r := space.intersect_ray(q)
				if not r.is_empty():
					var surf: float = r["position"].y
					if global_position.y < surf - 0.3 and surf - global_position.y < 3.0:
						global_position.y = surf + 0.15
						velocity.y = 0.0

		if not _on_raft:
			_clamp_to_terrain()
	_handle_stamina(delta)
	_handle_health_regen(delta)
	_tick_affix_timers(delta)
	_tick_swim_fatigue(delta)
	_rotate_model()
	_update_target_hud(delta)
	_tick_attack_animation(delta)
	_tick_jump_animation(delta)
	_tick_run_animation(delta)
	_tick_idle_animation(delta)
	_tick_swim_visual(delta)
	_tick_3d_model(delta)
	_tick_arrows(delta)
	_tick_footstep_sfx(delta)
	_tick_gallop_sfx(delta)
	_update_floating_bars(delta)

	if NetworkManager.is_connected_to_game():
		_synced_position = global_position
		_rpc_sync_tick += 1
		var anim_changed := _gltf_playing_clip != _last_broadcast_clip
		if anim_changed:
			if _DEBUG_LOG: print("[ANIM-SEND] clip changed: '%s' -> '%s' speed=%.1f" % [_last_broadcast_clip, _gltf_playing_clip, _gltf_playing_speed])
		if _rpc_sync_tick % 3 == 0 or anim_changed:
			_last_broadcast_clip = _gltf_playing_clip
			var model_yaw: float = _model.rotation.y if _model else 0.0
			var _wg := _find_world_generator()
			var net_pos := global_position
			if _wg:
				net_pos = _wg.get_world_position(self)
			_broadcast_state.rpc(net_pos, model_yaw, velocity, _gltf_playing_clip, _gltf_playing_speed, equipped_weapon, current_health, max_health, current_stamina, max_stamina)
		if _rpc_sync_tick % 300 == 5 and character_display_name != "":
			_broadcast_display_name()

	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	if _build_mode and _build_ghost:
		_update_build_ghost()

	if _on_raft:
		_interaction.tick_raft(delta)
	elif _mounted:
		if not is_instance_valid(_mount_node):
			_interaction.force_dismount()
		elif _mount_node:
			_mount_node.global_position = global_position
			_mount_node.rotation.y = rotation.y + PI
			_interaction.tick_horse_animation(delta)

	if global_position.y < -10.0 and not _in_cave:
		if _last_safe_position != Vector3.ZERO:
			global_position = _last_safe_position
			velocity = Vector3.ZERO
		else:
			_respawn()

	_loot_check_timer -= delta
	if _loot_check_timer <= 0.0:
		_loot_check_timer = 0.1
		var flat_spd := Vector2(velocity.x, velocity.z).length()
		if flat_spd < 0.3:
			pass
		else:
			var px := global_position.x
			var py := global_position.y
			var pz := global_position.z
			var my_peer := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
			for loot_node: Node in get_tree().get_nodes_in_group(&"loot"):
				var loot := loot_node as Node3D
				if not loot or not loot.has_method("pickup"):
					continue
				if "pickup_grace" in loot and loot.pickup_grace > 0.0:
					if "drop_owner_peer" in loot and loot.drop_owner_peer == my_peer:
						continue
				var lp := loot.global_position
				var dx := px - lp.x
				var dz := pz - lp.z
				if dx * dx + dz * dz < 4.28:
					var dy := py - lp.y
					if dx * dx + dy * dy + dz * dz < 4.28:
						loot.pickup(self)

	_interact_check_timer -= delta
	if _interact_check_timer <= 0.0:
		_interact_check_timer = 0.15
		_interaction.update_interact_prompt()

	var _phys_ms := float(Time.get_ticks_usec() - _phys_t0) / 1000.0
	_pc_proc_max_physics = maxf(_pc_proc_max_physics, _phys_ms)


# ===================================================================
# GRAVITY / JUMP / MOVEMENT / DODGE / STAMINA / CAMERA
# ===================================================================

func _apply_gravity(delta: float) -> void:
	var water_y := WaterSystem.get_surface_y(global_position.x, global_position.z)
	var feet_y := global_position.y
	var submersion := water_y - feet_y
	var grounded := is_on_floor()

	if submersion > 0.2 and (not grounded or submersion > 0.6):
		# Under water â€” apply buoyancy and damping instead of gravity
		# When grounded (walking on riverbed), require deeper submersion to swim
		_is_swimming = true
		var buoy := submersion * BUOYANCY_FORCE
		velocity.y += buoy * delta
		velocity.y -= velocity.y * WATER_DAMPING * delta
		velocity.y = clampf(velocity.y, -6.0, 4.0)
	elif submersion > -0.3 and velocity.y < 0.0 and not grounded:
		# Near surface falling â€” gentle decel (bobbing zone)
		# Only when airborne; grounded players follow terrain normally
		_is_swimming = true
		velocity.y *= 1.0 - 3.0 * delta
	else:
		_is_swimming = false
		if not grounded:
			var grav_mult := fall_gravity_multiplier if velocity.y < 0.0 else gravity_multiplier
			velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) * grav_mult * delta
		if _mounted:
			velocity.y = clampf(velocity.y, -18.0, jump_velocity)


func _snap_to_ground() -> void:
	var space := get_world_3d().direct_space_state
	if not space:
		return
	var from := Vector3(global_position.x, global_position.y + 50.0, global_position.z)
	var to := Vector3(global_position.x, global_position.y - 100.0, global_position.z)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid()]
	var result := space.intersect_ray(query)
	if not result.is_empty():
		global_position.y = result["position"].y + 0.15
		velocity = Vector3.ZERO
		_last_safe_position = global_position


func _clamp_to_terrain() -> void:
	if _in_cave:
		return

	var dt := get_physics_process_delta_time()
	if _respawn_grace > 0.0:
		_respawn_grace -= dt
		if velocity.y > 0.0:
			velocity.y = 0.0
		return

	var space := get_world_3d().direct_space_state
	if not space:
		return

	var from := Vector3(global_position.x, global_position.y + 3.0, global_position.z)
	var to := Vector3(global_position.x, global_position.y - 25.0, global_position.z)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.exclude = [get_rid()]
	var result := space.intersect_ray(query)

	if result.is_empty():
		return

	var surface_y: float = result["position"].y
	var below_surface := surface_y - global_position.y
	# Don't snap upward when airborne â€” let gravity work
	if not is_on_floor():
		return
	var snap_threshold := 0.05 if _mounted else 0.15
	var max_snap := 1.5 if _mounted else 2.0
	if below_surface > snap_threshold and below_surface < max_snap:
		global_position.y = surface_y + 0.15
		velocity.y = maxf(velocity.y, 0.0)


func _handle_jump() -> void:
	if _chat_focused:
		return
	if is_on_floor():
		_double_jump_used = false
	if _is_swimming:
		if Input.is_action_pressed(&"jump") and _can_spend_stamina(0.1):
			velocity.y = lerpf(velocity.y, 3.0, 0.15)
			var swim_cost := SWIM_STAMINA_COST
			if _has_affix(&"warmth"):
				swim_cost *= (1.0 - _affix_val(&"warmth"))
			_spend_stamina(swim_cost * get_physics_process_delta_time())
		return
	if Input.is_action_just_pressed(&"jump") and not _is_blocking:
		if is_on_floor():
			velocity.y = jump_velocity
			_start_jump_animation()
		elif not _double_jump_used and _has_affix(&"double_jump"):
			_double_jump_used = true
			velocity.y = jump_velocity * 0.85
			_start_jump_animation()


const STEP_HEIGHT := 0.35

func _step_up_move_and_slide() -> void:
	var flat_vel := Vector2(velocity.x, velocity.z)
	if not is_on_floor() or flat_vel.length() < 0.1:
		move_and_slide()
		return

	var saved_vel := velocity
	var saved_pos := global_position

	move_and_slide()

	# If we left the floor (walked off an edge), let gravity take over â€” don't retry
	if not is_on_floor():
		return

	var moved := Vector2(global_position.x - saved_pos.x, global_position.z - saved_pos.z).length()
	var wanted := flat_vel.length() * get_physics_process_delta_time()
	if moved >= wanted * 0.5:
		return

	global_position = saved_pos
	velocity = saved_vel

	global_position.y += STEP_HEIGHT
	move_and_slide()

	var space := get_world_3d().direct_space_state
	if space:
		var ray_from := global_position
		var ray_to := global_position - Vector3(0, STEP_HEIGHT + 0.1, 0)
		var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, collision_mask)
		query.exclude = [get_rid()]
		var result := space.intersect_ray(query)
		if not result.is_empty():
			global_position.y = result["position"].y
		else:
			global_position.y = saved_pos.y


func _handle_flight(delta: float) -> void:
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var cam: Camera3D = _spring_arm.get_child(0) if _spring_arm and _spring_arm.get_child_count() > 0 else null
	var cam_basis: Basis = cam.global_transform.basis if cam else _camera_pivot.global_transform.basis
	var forward := -cam_basis.z
	var right := cam_basis.x
	var move_dir := right * input_dir.x + forward * (-input_dir.y)
	if Input.is_action_pressed(&"jump"):
		move_dir.y += 1.0
	if Input.is_action_pressed(&"crouch"):
		move_dir.y -= 1.0
	if move_dir.length() > 0.01:
		move_dir = move_dir.normalized()
	var speed := FLIGHT_SPEED
	if Input.is_action_pressed(&"sprint"):
		speed *= 2.0
	velocity = Vector3.ZERO
	global_position += move_dir * speed * delta
	var wg_nodes := get_tree().get_nodes_in_group(&"world_generator")
	if not wg_nodes.is_empty() and wg_nodes[0].has_method(&"get_height_at_scene"):
		var ground_y: float = wg_nodes[0].get_height_at_scene(global_position.x, global_position.z)
		if global_position.y < ground_y + 0.5:
			global_position.y = ground_y + 0.5


func _handle_movement(delta: float) -> void:
	if _chat_focused:
		_is_sprinting = false
		velocity.x = move_toward(velocity.x, 0.0, deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, deceleration * delta)
		return
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if _auto_run:
		if input_dir.length_squared() > 0.01:
			_auto_run = false
		else:
			input_dir.y = -1.0

	var cam_basis := _camera_pivot.global_transform.basis
	var direction := (cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	direction.y = 0.0

	_is_sprinting = (
		Input.is_action_pressed(&"sprint")
		and input_dir != Vector2.ZERO
		and not _is_crouching
		and not _is_blocking
		and _can_spend_stamina(0.1)
	)

	var speed := walk_speed
	if _is_swimming:
		speed = SWIM_SPRINT_SPEED if _is_sprinting else SWIM_SPEED
		if _has_affix(&"aquatic"):
			speed *= (1.0 + _affix_val(&"aquatic"))
	elif _is_crouching:
		speed = crouch_speed
	elif _is_sprinting:
		speed = sprint_speed
	elif _walk_mode:
		speed = walk_speed * 0.55
	if _mounted:
		speed *= _get_mount_speed_mult()
	if _has_affix(&"swiftness"):
		speed *= (1.0 + _affix_val(&"swiftness"))
	if _is_swimming and _has_affix(&"trailblazer"):
		speed *= (1.0 + _affix_val(&"trailblazer"))
	if _adrenaline_timer > 0.0:
		speed *= 1.15
	if _has_affix(&"tenacity"):
		speed = maxf(speed, walk_speed * _affix_val(&"tenacity"))
	if not _is_swimming and is_on_floor() and not _has_affix(&"sure_footed"):
		var floor_n := get_floor_normal()
		if floor_n.y < 0.95 and floor_n.y > 0.3:
			var slope_penalty := 1.0 - (1.0 - floor_n.y) * 0.5
			speed *= clampf(slope_penalty, 0.6, 1.0)
	if direction.length() > 0.01:
		var accel := acceleration if is_on_floor() else acceleration * air_control
		velocity.x = move_toward(velocity.x, direction.x * speed, accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, accel * delta)
	else:
		var decel := deceleration if is_on_floor() else deceleration * air_control
		velocity.x = move_toward(velocity.x, 0.0, decel * delta)
		velocity.z = move_toward(velocity.z, 0.0, decel * delta)


func _try_dodge() -> void:
	if not _can_spend_stamina(dodge_stamina_cost) or not is_on_floor():
		return
	_spend_stamina(dodge_stamina_cost)
	_is_dodging = true
	_dodge_timer = dodge_duration
	_is_blocking = false
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if input_dir.length_squared() > 0.01:
		var cam_basis := _camera_pivot.global_transform.basis
		_dodge_dir = (cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
		_dodge_dir.y = 0.0
	else:
		_dodge_dir = -_camera_pivot.global_transform.basis.z
		_dodge_dir.y = 0.0
		_dodge_dir = _dodge_dir.normalized()


func _tick_dodge(delta: float) -> void:
	velocity.x = _dodge_dir.x * dodge_speed
	velocity.z = _dodge_dir.z * dodge_speed
	_dodge_timer -= delta
	if _dodge_timer <= 0.0:
		_is_dodging = false


func _handle_stamina(delta: float) -> void:
	var prev_stamina := current_stamina
	if _is_blocking and not _has_affix(&"steadfast_guard"):
		_spend_stamina(3.0 * delta)
	if _is_sprinting and _mounted:
		_mount_stamina_regen_timer = MOUNT_STAMINA_REGEN_DELAY
		_mount_stamina = maxf(_mount_stamina - MOUNT_STAMINA_COST * delta, 0.0)
		if _mount_stamina <= 0.0:
			_is_sprinting = false
	elif _is_sprinting and not _mounted:
		var sprint_cost := sprint_stamina_cost
		if _has_affix(&"fleet"):
			sprint_cost *= (1.0 - _affix_val(&"fleet"))
		_spend_stamina(sprint_cost * delta)
	else:
		_stamina_regen_timer -= delta
		if _stamina_regen_timer <= 0.0:
			var regen := stamina_regen_rate
			if _has_affix(&"resilience"):
				regen *= (1.0 + _affix_val(&"resilience"))
			current_stamina = minf(current_stamina + regen * delta, max_stamina)
	if _mounted:
		if not _is_sprinting:
			_mount_stamina_regen_timer -= delta
			if _mount_stamina_regen_timer <= 0.0:
				_mount_stamina = minf(_mount_stamina + MOUNT_STAMINA_REGEN_RATE * delta, _mount_max_stamina)
	if not is_equal_approx(current_stamina, prev_stamina):
		GameEvents.player_stamina_changed.emit(current_stamina, max_stamina)


func _can_spend_stamina(amount: float) -> bool:
	return current_stamina >= amount


func _spend_stamina(amount: float) -> void:
	current_stamina = maxf(current_stamina - amount, 0.0)
	_stamina_regen_timer = stamina_regen_delay


func _rotate_camera(mouse_delta: Vector2) -> void:
	_camera_pivot.rotate_y(-mouse_delta.x * mouse_sensitivity)
	_spring_arm.rotation.x = clampf(
		_spring_arm.rotation.x - mouse_delta.y * mouse_sensitivity,
		deg_to_rad(min_pitch), deg_to_rad(max_pitch)
	)


# ===================================================================
# FLOATING HEALTH / STAMINA BARS (3D above player)
# ===================================================================

func _setup_floating_bars() -> void:
	const BAR_W := 1.352
	const BAR_H := 0.1014
	const STAM_H := 0.0754
	const GAP := 0.031

	_bar_shader = load("res://shaders/bar_hud.gdshader") as Shader

	_bar_anchor = Node3D.new()
	_bar_anchor.name = "BarAnchor"
	_bar_anchor.position = Vector3(0.0, 4.2, 0.0)
	add_child(_bar_anchor)

	_hp_bar = _make_shader_bar(BAR_W, BAR_H,
		Color(0.5, 0.05, 0.05), Color(0.95, 0.15, 0.15))
	_hp_bar.position = Vector3.ZERO
	_bar_anchor.add_child(_hp_bar)

	_stam_bar = _make_shader_bar(BAR_W, STAM_H,
		Color(0.35, 0.25, 0.05), Color(0.95, 0.75, 0.15))
	_stam_bar.position = Vector3(0.0, -(BAR_H * 0.5 + STAM_H * 0.5 + GAP), 0.0)
	_bar_anchor.add_child(_stam_bar)

	_mount_stam_bar = _make_shader_bar(BAR_W, STAM_H,
		Color(0.05, 0.35, 0.10), Color(0.15, 0.85, 0.25))
	_mount_stam_bar.position = Vector3(0.0, -(BAR_H * 0.5 + STAM_H * 1.5 + GAP * 2.0), 0.0)
	_mount_stam_bar.visible = false
	_bar_anchor.add_child(_mount_stam_bar)



func _make_shader_bar(w: float, h: float, col_a: Color, col_b: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	mi.mesh = qm
	var mat := ShaderMaterial.new()
	mat.shader = _bar_shader
	mat.set_shader_parameter("fill_ratio", 1.0)
	mat.set_shader_parameter("color_a", Vector3(col_a.r, col_a.g, col_a.b))
	mat.set_shader_parameter("color_b", Vector3(col_b.r, col_b.g, col_b.b))
	mat.set_shader_parameter("pulse", 0.0)
	mat.set_shader_parameter("aspect_ratio", w / h)
	mat.set_shader_parameter("glow_intensity", 0.45)
	mat.set_shader_parameter("border_softness", 0.025)
	mi.set_surface_override_material(0, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _update_floating_bars(delta: float) -> void:
	if _bar_anchor:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var anchor_world := _bar_anchor.global_position
			var cam_pos := cam.global_position
			var dir := (cam_pos - anchor_world)
			dir.y = 0.0
			if dir.length_squared() > 0.001:
				dir = dir.normalized()
				_bar_anchor.global_transform.basis = Basis.looking_at(-dir, Vector3.UP)

	_hp_pulse = move_toward(_hp_pulse, 0.0, delta * 3.0)

	if _hp_bar:
		_hp_bar.visible = true
		var mat: ShaderMaterial = _hp_bar.get_surface_override_material(0) as ShaderMaterial
		if mat:
			mat.set_shader_parameter("fill_ratio", clampf(current_health / max_health, 0.0, 1.0))
			mat.set_shader_parameter("pulse", _hp_pulse)

	if _stam_bar:
		_stam_bar.visible = not _mounted
		if not _mounted:
			var mat: ShaderMaterial = _stam_bar.get_surface_override_material(0) as ShaderMaterial
			if mat:
				mat.set_shader_parameter("fill_ratio", clampf(current_stamina / max_stamina, 0.0, 1.0))

	if _mount_stam_bar:
		_mount_stam_bar.visible = _mounted
		if _mounted:
			_mount_stam_bar.position.y = _stam_bar.position.y if _stam_bar else -0.12
			var mmat: ShaderMaterial = _mount_stam_bar.get_surface_override_material(0) as ShaderMaterial
			if mmat:
				mmat.set_shader_parameter("fill_ratio", clampf(_mount_stamina / _mount_max_stamina, 0.0, 1.0))

	_update_drown_bar()


# ===================================================================
# SPRITE SETUP & DIRECTION
# ===================================================================

func _setup_player_sprite() -> void:
	for key in ["south", "west", "east", "north"]:
		var path := "res://textures/player/player_%s.png" % key
		if ResourceLoader.exists(path):
			_player_textures[key] = load(path)

	_load_idle_frames()
	_load_attack_frames()
	_load_run_frames()
	_load_jump_frames()
	_sit_idle_frames = _load_anim_set("sit-idle_%s_%d.png", 16)

	if _player_textures.is_empty():
		if _DEBUG_LOG: print("[PLAYER MODEL] peer '%s': _player_textures is EMPTY, aborting sprite setup" % name)
		return

	if _model:
		var old_node := _model.get_node_or_null("PlayerSprite")
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
		_player_sprite = gltf_scene.instantiate()
		_player_sprite.name = "PlayerSprite"
		var is_tripo_barbarian := gltf_path.contains("Lowpolyvikingwithaxe") or gltf_path.contains("barbarian")
		var is_mixamo_fbx := gltf_path.ends_with(".fbx")
		var is_lowpoly_viking := is_tripo_barbarian
		_is_lowpoly_viking = is_lowpoly_viking
		var is_tripo_model := is_tripo_barbarian or gltf_path.contains("muscular+warrior") or gltf_path.contains("Pahlevan")
		var s := 4.0 if is_tripo_barbarian else (400.0 if is_lowpoly_viking else (200.0 if is_mixamo_fbx else (2.5 if is_tripo_model else 0.7)))
		_player_sprite.scale = Vector3(s, s, s)
		if is_tripo_barbarian:
			_player_yaw_offset = -PI / 2.0
		if _model and _player_yaw_offset != 0.0:
			_model.rotation.y = _player_yaw_offset
		_base_sprite_y = 0.0
		_player_sprite.position.y = _base_sprite_y
		if _model:
			_model.add_child(_player_sprite)
		if _DEBUG_LOG: print("[PLAYER MODEL] Loaded %s â€” scale=%.2f" % [gltf_path.get_file(), s])
		_gltf_anim_player = _find_anim_player(_player_sprite)
		if _gltf_anim_player:
			_gltf_anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			_rename_nla_tracks()
			if not is_tripo_barbarian:
				_load_external_animations()
			var anim_list := _gltf_anim_player.get_animation_list()
			if _DEBUG_LOG: print("[PLAYER MODEL] Available animations: ", anim_list)
			var non_looping := [
				"jump", "standing_jump", "punch", "punch_alt", "kick",
				"sword_slash", "spin_attack", "jump_attack", "heavy_swing",
				"bow_draw", "bow_hold", "lie_down", "equip", "hit_react",
				"chop", "afraid", "attack_right", "attack_left",
			]
			for anim_name in anim_list:
				var anim := _gltf_anim_player.get_animation(anim_name)
				if anim:
					if anim_name in non_looping:
						anim.loop_mode = Animation.LOOP_NONE
					else:
						anim.loop_mode = Animation.LOOP_LINEAR
					_strip_root_motion(anim)
			_rebuild_axe_swing_horizontal()
			_rebuild_bow_draw_animation()
			_rebuild_bow_release_animation()
			_rebuild_club_smash_animation()
			_rebuild_sword_slash_animation()
			_gltf_play("idle")
		_gltf_all_meshes = []
		_collect_mesh_instances(_player_sprite, _gltf_all_meshes)
		if is_tripo_barbarian:
			_apply_tripo_player_texture()
		elif is_lowpoly_viking:
			_apply_viking_texture()
		elif is_mixamo_fbx and is_tripo_model:
			_apply_pahlevan_texture()
		elif not is_tripo_model and not is_mixamo_fbx:
			_apply_oathbound_shader()
			_enhance_character_model()
		else:
			if _DEBUG_LOG: print("[PLAYER MODEL] Tripo model â€” skipping Blockbench shaders")
		call_deferred("_update_equipped_weapon_model")
		call_deferred("_update_armor_visuals")
	else:
		_player_model_3d = PlayerModel3D.new()
		_player_model_3d.build()
		_player_sprite = _player_model_3d
		_player_sprite.name = "PlayerSprite"
		_base_sprite_y = 0.82
		_player_sprite.position.y = _base_sprite_y
		if _model:
			_model.add_child(_player_sprite)

func _get_armor_aabb(instance: Node3D) -> AABB:
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


func _get_equipped_for_display(slot: String) -> StringName:
	if is_multiplayer_authority():
		return Inventory.get_equipped(slot)
	return (synced_equipped.get(slot, &"") as StringName) if synced_equipped.has(slot) else &""


func _update_armor_visuals() -> void:
	for slot: String in _armor_nodes.keys():
		var node: Node3D = _armor_nodes[slot] as Node3D
		if is_instance_valid(node):
			node.queue_free()
	_armor_nodes.clear()

	if not _player_sprite:
		return

	if _is_lowpoly_viking:
		return

	var skel := _find_skeleton(_player_sprite)
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
		var item_id: StringName = _get_equipped_for_display(slot)
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

		var aabb: AABB = _get_armor_aabb(instance)
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
		_armor_nodes[slot] = attachment

	_hide_body_under_armor(skel)


func _hide_body_under_armor(skel: Skeleton3D) -> void:
	if _gltf_all_meshes.is_empty() or not skel:
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
		var item_id: StringName = _get_equipped_for_display(slot)
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

	for mi in _gltf_all_meshes:
		if not mi.mesh:
			continue
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(si)
			if mat is ShaderMaterial:
				var smat: ShaderMaterial = mat as ShaderMaterial
				smat.set_shader_parameter("hide_bone_count", bones_to_hide.size())
				smat.set_shader_parameter("hide_bones", hide_arr)


func _load_idle_frames() -> void:
	for direction in ["south", "west", "east", "north"]:
		var frames: Array[Texture2D] = []
		for i in range(16):
			var path := "res://textures/player/idle_%s_%d.png" % [direction, i]
			if ResourceLoader.exists(path):
				var tex := load(path) as Texture2D
				if tex:
					frames.append(tex)
		if not frames.is_empty():
			_idle_frames[direction] = frames


func _load_attack_frames() -> void:
	_fist_frames = _load_anim_set("punch_%s_%d.png", 16)
	_kick_frames_attack = _load_anim_set("kick_%s_%d.png", 7)
	_weapon_attack_frames = _load_anim_set("axe-swing_%s_%d.png", 16)
	_pickaxe_attack_frames = _load_anim_set("pickaxe-swing_%s_%d.png", 16)
	_sword_attack_frames = _load_anim_set("sword-swing_%s_%d.png", 16)
	_bow_attack_frames = _load_anim_set("bow-shoot_%s_%d.png", 16)
	_attack_frames = _fist_frames if not _fist_frames.is_empty() else _weapon_attack_frames


func _load_anim_set(pattern: String, frame_count: int) -> Dictionary:
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


func _load_run_frames() -> void:
	for direction in ["south", "west", "east", "north"]:
		var frames: Array[Texture2D] = []
		for i in range(16):
			var path := "res://textures/player/jog_%s_%d.png" % [direction, i]
			if ResourceLoader.exists(path):
				var tex := load(path) as Texture2D
				if tex:
					frames.append(tex)
		if not frames.is_empty():
			_run_frames[direction] = frames


func _load_jump_frames() -> void:
	for anim_prefix in ["jump", "flip"]:
		var target: Dictionary = _jump_frames if anim_prefix == "jump" else _flip_frames
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


func _setup_movement_audio() -> void:
	_footstep_player = AudioStreamPlayer.new()
	_footstep_player.bus = &"SFX"
	_footstep_player.volume_db = -8.5
	add_child(_footstep_player)
	_footstep_player.finished.connect(_on_footstep_finished)

	_gallop_player = AudioStreamPlayer.new()
	_gallop_player.bus = &"SFX"
	_gallop_player.volume_db = -9.6
	add_child(_gallop_player)
	_gallop_player.finished.connect(_on_gallop_finished)

	# Grab the already-loaded streams from AudioManager (guaranteed to work)
	var fs := AudioManager.get_stream("grass_step")
	if fs:
		_footstep_player.stream = fs
	_gallop_normal_stream = AudioManager.get_stream("horse_gallop")
	_gallop_fast_stream = AudioManager.get_stream("horse_gallop_fast")


func _on_footstep_finished() -> void:
	if _footstep_player and _footstep_player.stream and not _mounted:
		var spd := Vector2(velocity.x, velocity.z).length()
		if spd > 0.5 and is_on_floor():
			_footstep_player.play()


func _on_gallop_finished() -> void:
	if _gallop_player and _gallop_player.stream and _mounted and is_on_floor():
		var spd := Vector2(velocity.x, velocity.z).length()
		if spd > 0.5:
			_gallop_player.play()


func _tick_footstep_sfx(_delta: float) -> void:
	if not _footstep_player or not _footstep_player.stream:
		return
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var want_playing := not _mounted and flat_speed > 0.5 and is_on_floor() and not _is_swimming
	if want_playing:
		var speed_ratio := clampf(flat_speed / walk_speed, 0.4, 2.2) * 0.65
		_footstep_player.pitch_scale = speed_ratio
	if want_playing and not _footstep_player.playing:
		_footstep_player.play()
	elif not want_playing and _footstep_player.playing:
		_footstep_player.stop()


func _tick_gallop_sfx(_delta: float) -> void:
	if not _gallop_player:
		return
	var want_playing := _mounted and Vector2(velocity.x, velocity.z).length() > 0.5 and is_on_floor()
	var want_stream: AudioStream = _gallop_fast_stream if _is_sprinting else _gallop_normal_stream
	if not want_stream:
		return
	if want_playing:
		if _gallop_player.stream != want_stream:
			_gallop_player.stream = want_stream
			_gallop_player.play()
		elif not _gallop_player.playing:
			_gallop_player.play()
	elif _gallop_player.playing:
		_gallop_player.stop()


func _get_camera_relative_dir() -> String:
	var move_dir := Vector3(velocity.x, 0.0, velocity.z)
	if move_dir.length_squared() < 0.1:
		return _current_run_dir
	move_dir = move_dir.normalized()
	var cam_forward := -_camera_pivot.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()
	var cam_right := _camera_pivot.global_transform.basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	var forward_dot := move_dir.dot(cam_forward)
	var right_dot := move_dir.dot(cam_right)
	if absf(forward_dot) >= absf(right_dot):
		return "north" if forward_dot > 0.0 else "south"
	else:
		return "east" if right_dot > 0.0 else "west"


func _rotate_model() -> void:
	if not _model:
		return
	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)
	if flat_velocity.length_squared() > 0.1:
		var target_rotation := atan2(flat_velocity.x, flat_velocity.z) + _player_yaw_offset
		_model.rotation.y = lerp_angle(_model.rotation.y, target_rotation, 0.15)
	_update_sprite_direction()


func _update_sprite_direction() -> void:
	if not _player_sprite or _player_textures.is_empty() or _is_attacking or _is_run_animating or _is_jumping or _bow_drawing:
		return
	var move_dir := Vector3(velocity.x, 0.0, velocity.z)
	if move_dir.length_squared() < 0.1:
		return
	var key := _get_camera_relative_dir()
	if _player_textures.has(key):
		_set_player_sprite_tex(_player_textures[key] as Texture2D)


# ===================================================================
# JUMP ANIMATION
# ===================================================================

func _start_jump_animation() -> void:
	if _bow_drawing:
		return
	_is_jumping = true
	if _gltf_anim_player:
		_gltf_current_anim = ""
		_gltf_play("jump")
		return
	_is_flipping = randf() < 0.25 and not _flip_frames.is_empty()
	var frames_dict: Dictionary = _flip_frames if _is_flipping else _jump_frames
	if frames_dict.is_empty():
		return
	_jump_frame_idx = 0
	_jump_frame_timer = _JUMP_FRAME_DURATION
	var dir := _get_camera_relative_dir()
	if frames_dict.has(dir):
		var arr: Array = Array(frames_dict[dir])
		if not arr.is_empty():
			var tex := arr[0] as Texture2D
			if tex and _player_sprite:
				_set_player_sprite_tex(tex)


func _tick_jump_animation(delta: float) -> void:
	if not _is_jumping or not _player_sprite or _bow_drawing:
		return
	if _gltf_anim_player:
		if is_on_floor() and velocity.y <= 0.0:
			_is_jumping = false
			_is_flipping = false
			_gltf_current_anim = ""
			_gltf_play("idle")
		return
	if is_on_floor() and velocity.y <= 0.0:
		_is_jumping = false
		_is_flipping = false
		_revert_to_idle_sprite()
		return
	_jump_frame_timer -= delta
	if _jump_frame_timer > 0.0:
		return
	var dir := _get_camera_relative_dir()
	var frames_dict: Dictionary = _flip_frames if _is_flipping else _jump_frames
	if not frames_dict.has(dir):
		return
	var arr: Array = Array(frames_dict[dir])
	_jump_frame_idx += 1
	if _jump_frame_idx >= arr.size():
		_jump_frame_idx = arr.size() - 1
		return
	var tex := arr[_jump_frame_idx] as Texture2D
	if tex:
		_set_player_sprite_tex(tex)
	_jump_frame_timer = _JUMP_FRAME_DURATION


# ===================================================================
# RUNNING ANIMATION
# ===================================================================

func _tick_run_animation(delta: float) -> void:
	if not _player_sprite:
		return
	if _gltf_anim_player:
		return
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var is_moving := flat_speed > 0.5 and is_on_floor() and not _is_attacking and not _is_jumping and not _bow_drawing

	if is_moving and not _run_frames.is_empty():
		var dir := _get_camera_relative_dir()
		_current_run_dir = dir
		if not _run_frames.has(dir):
			_is_run_animating = false
			return
		_is_run_animating = true
		var frame_dur := _SPRINT_FRAME_DURATION if _is_sprinting else _RUN_FRAME_DURATION
		_run_frame_timer -= delta
		if _run_frame_timer <= 0.0:
			var frames_arr: Array = Array(_run_frames[dir])
			_run_frame_idx = (_run_frame_idx + 1) % frames_arr.size()
			var tex := frames_arr[_run_frame_idx] as Texture2D
			if tex:
				_set_player_sprite_tex(tex)
			_run_frame_timer = frame_dur
		_player_sprite.position.y = _base_sprite_y
		_player_sprite.scale = Vector3.ONE
		_player_sprite.rotation.x = 0.0
	else:
		if _is_run_animating:
			_is_run_animating = false
			_run_frame_idx = 0
		_player_sprite.position.y = _base_sprite_y
		_player_sprite.scale = Vector3.ONE
		_player_sprite.rotation.x = 0.0


func _tick_idle_animation(delta: float) -> void:
	if not _player_sprite or _idle_frames.is_empty():
		return
	if _gltf_anim_player:
		return
	if _is_attacking or _is_run_animating or _is_jumping or _bow_drawing:
		_idle_frame_timer = 0.0
		return

	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if flat_speed > 0.5:
		return

	var dir := _get_camera_relative_dir()
	_current_idle_dir = dir
	if not _idle_frames.has(dir):
		return

	_idle_frame_timer -= delta
	if _idle_frame_timer <= 0.0:
		var frames_arr: Array = Array(_idle_frames[dir])
		_idle_frame_idx = (_idle_frame_idx + 1) % frames_arr.size()
		var tex := frames_arr[_idle_frame_idx] as Texture2D
		if tex:
			_set_player_sprite_tex(tex)
		_idle_frame_timer = _IDLE_FRAME_DURATION


func _tick_swim_fatigue(delta: float) -> void:
	if current_health <= 0.0:
		return
	_swim_fatigue_pulse = move_toward(_swim_fatigue_pulse, 0.0, delta * 3.0)
	var in_water := _is_swimming and not _on_raft
	if in_water:
		if _mounted:
			_interaction.force_dismount()
		_swim_fatigue += delta
		if _swim_fatigue >= SWIM_FATIGUE_MAX * 0.75:
			_swim_fatigue_pulse = 1.0
		if _swim_fatigue >= SWIM_FATIGUE_MAX:
			_swim_fatigue = SWIM_FATIGUE_MAX
			_drown_tick_timer += delta
			if _drown_tick_timer >= _DROWN_TICK_INTERVAL:
				_drown_tick_timer -= _DROWN_TICK_INTERVAL
				var dmg := max_health * _DROWN_TICK_FRACTION
				current_health = maxf(current_health - dmg, 0.0)
				GameEvents.player_health_changed.emit(current_health, max_health)
				var drown_num := DamageNumber.new()
				drown_num.text = str(int(dmg))
				drown_num.font_size = 22
				drown_num.pixel_size = 0.01
				drown_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				drown_num.no_depth_test = true
				drown_num.modulate = Color(0.3, 0.6, 1.0)
				drown_num.outline_modulate = Color.BLACK
				drown_num.outline_size = 6
				drown_num._velocity = Vector3(0, 2.5, 0)
				get_tree().current_scene.add_child(drown_num)
				drown_num.global_position = global_position + Vector3.UP * 2.5
				if current_health <= 0.0:
					_on_death()
	else:
		if _swim_fatigue > 0.0:
			_swim_fatigue = maxf(_swim_fatigue - SWIM_FATIGUE_RECOVER_RATE * delta, 0.0)
		_drown_tick_timer = 0.0


func _tick_swim_visual(delta: float) -> void:
	if not _player_sprite:
		return
	if _is_swimming:
		_swim_time += delta
		var bob := sin(_swim_time * 3.0) * 0.06
		_player_sprite.position.y = _base_sprite_y - 0.35 + bob
		var tilt := sin(_swim_time * 2.2) * 0.08
		_player_sprite.rotation.z = tilt
		var flat_speed := Vector2(velocity.x, velocity.z).length()
		if flat_speed > 0.3:
			var paddle := sin(_swim_time * 6.0) * 0.12
			_player_sprite.rotation.z += paddle
	else:
		if _swim_time > 0.0:
			_swim_time = 0.0
			_player_sprite.position.y = _base_sprite_y
			_player_sprite.rotation.z = 0.0


func _tick_3d_model(delta: float) -> void:
	if _gltf_anim_player:
		var flat_speed := Vector2(velocity.x, velocity.z).length()
		var moving := flat_speed > 0.5 and is_on_floor() and not _is_swimming
		var _needs_torso_lock := false
		var _needs_advance := true
		var _weapon_needed := false
		if _mounted:
			_gltf_play("sit")
		elif _is_attacking:
			if _gltf_attack_timer > 0.0:
				_gltf_attack_timer -= delta
				if _gltf_attack_timer <= 0.0:
					_is_attacking = false
			if _gltf_attack_anim != "":
				_gltf_play(_gltf_attack_anim)
			else:
				_gltf_play("attack_right")
			_needs_torso_lock = true
			_weapon_needed = true
			if _bow_arrow_node:
				_bow_arrow_node.visible = false
		elif _bow_drawing:
			var bow_anim_name := ""
			for candidate in ["animation.bow_draw", "animation_bow_draw", "bow_draw"]:
				if _gltf_anim_player.has_animation(candidate):
					bow_anim_name = candidate
					break
			if bow_anim_name != "":
				if _gltf_current_anim != bow_anim_name:
					_gltf_current_anim = bow_anim_name
					_gltf_anim_player.play(bow_anim_name, -1, 0.0)
				var pct := clampf(_bow_tension / BOW_MAX_DRAW_TIME, 0.0, 1.0)
				_gltf_anim_player.seek(pct * _gltf_anim_player.current_animation_length, true)
			_needs_torso_lock = true
			_needs_advance = false
			_weapon_needed = true
			if _bow_arrow_node:
				var draw_pct := clampf(_bow_tension / BOW_MAX_DRAW_TIME, 0.0, 1.0)
				_bow_arrow_node.visible = draw_pct > 0.15
		elif _is_jumping:
			_gltf_play("jump")
			if _bow_arrow_node:
				_bow_arrow_node.visible = false
		elif moving:
			_gltf_play("run" if _is_sprinting else "walk")
			if _bow_arrow_node:
				_bow_arrow_node.visible = false
		else:
			_gltf_play("idle")
			if _bow_arrow_node:
				_bow_arrow_node.visible = false
		if _weapon_needed and not _weapon_drawn:
			_draw_weapon()
		elif not _weapon_needed and _weapon_drawn:
			_stow_weapon()
		if _needs_advance:
			_gltf_anim_player.advance(delta)
		if _needs_torso_lock:
			_lock_torso_height()
		if _weapon_drawn:
			_update_2h_left_grip()
		return
	if not _player_model_3d:
		return
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var moving := flat_speed > 0.5 and is_on_floor() and not _is_swimming
	_player_model_3d.tick(delta, moving, _is_sprinting, _is_attacking)


# ===================================================================
# ATTACK ANIMATION
# ===================================================================

func _tick_attack_animation(delta: float) -> void:
	if not _is_attacking or not _player_sprite:
		return
	if _gltf_anim_player:
		return
	_attack_frame_timer -= delta
	if _attack_frame_timer > 0.0:
		return
	if not _attack_frames.has(_current_attack_dir):
		_is_attacking = false
		_revert_to_idle_sprite()
		return
	var frames_arr: Array = Array(_attack_frames[_current_attack_dir])
	_attack_frame_idx += 1
	if _attack_frame_idx >= frames_arr.size():
		_is_attacking = false
		_revert_to_idle_sprite()
		return
	var tex := frames_arr[_attack_frame_idx] as Texture2D
	if tex:
		_set_player_sprite_tex(tex)
	_attack_frame_timer = _current_attack_frame_duration


func _revert_to_idle_sprite() -> void:
	if not _player_sprite:
		return
	var dir := _current_attack_dir
	if _idle_frames.has(dir) and not _idle_frames[dir].is_empty():
		_set_player_sprite_tex((_idle_frames[dir] as Array)[0] as Texture2D)
		_idle_frame_idx = 0
		_idle_frame_timer = _IDLE_FRAME_DURATION
	elif _player_textures.has(dir):
		_set_player_sprite_tex(_player_textures[dir] as Texture2D)


# ===================================================================
# BOW DRAW & FIRE
# ===================================================================

func _is_bow_weapon(wpn: StringName) -> bool:
	if wpn == &"crude_bow":
		return true
	var data: Dictionary = ItemDatabase.get_item(wpn)
	return str(data.get("name", "")).to_lower().contains("bow")


func _tick_bow_draw(delta: float, holding_draw: bool) -> void:
	if holding_draw and not _is_attacking and not _is_dodging:
		if not _bow_drawing:
			_bow_drawing = true
			_bow_tension = 0.0
			if not _weapon_drawn:
				_draw_weapon()
			_show_bow_reticle()
			_start_bow_creak()
		var draw_mult := 1.0
		if _has_affix(&"quickdraw"):
			draw_mult += _affix_val(&"quickdraw")
		if _has_affix(&"rapid_draw"):
			draw_mult += _affix_val(&"rapid_draw")
		_bow_tension = minf(_bow_tension + delta * draw_mult, BOW_MAX_DRAW_TIME)
		_update_bow_creak(delta)
		_update_bow_draw_sprite()
	elif _bow_drawing:
		_cancel_bow_draw()

	if _bow_drawing and _bow_reticle and _bow_reticle.visible:
		_bow_reticle.queue_redraw()


func _start_bow_creak() -> void:
	if not _bow_creak_player:
		_bow_creak_player = AudioStreamPlayer3D.new()
		_bow_creak_player.bus = &"SFX"
		_bow_creak_player.max_distance = 20.0
		_bow_creak_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
		add_child(_bow_creak_player)
	var stream := AudioManager.get_random_stream("bow_creak")
	if not stream:
		return
	var draw_mult := 1.0
	if _has_affix(&"quickdraw"):
		draw_mult += _affix_val(&"quickdraw")
	if _has_affix(&"rapid_draw"):
		draw_mult += _affix_val(&"rapid_draw")
	var draw_duration := BOW_MAX_DRAW_TIME / draw_mult
	var sound_length := stream.get_length()
	_bow_creak_player.stream = stream
	_bow_creak_player.volume_db = -4.0
	_bow_creak_player.pitch_scale = sound_length / draw_duration if draw_duration > 0.01 else 1.0
	_bow_creak_player.global_position = global_position
	_bow_creak_player.play()


func _update_bow_creak(_delta: float) -> void:
	if _bow_creak_player:
		_bow_creak_player.global_position = global_position


func _stop_bow_creak() -> void:
	if _bow_creak_player and _bow_creak_player.playing:
		_bow_creak_player.stop()


func _cancel_bow_draw() -> void:
	_bow_drawing = false
	_bow_tension = 0.0
	_hide_bow_reticle()
	_stop_bow_creak()
	if _bow_arrow_node:
		_bow_arrow_node.visible = false
	_revert_to_idle_sprite()


func _fire_bow() -> void:
	if not _bow_drawing:
		return
	var bow_id: StringName = Inventory.get_equipped("bow")
	var bow_data: Dictionary = ItemDatabase.get_item(bow_id) if bow_id != &"" else {}
	var tension_pct := clampf(_bow_tension / BOW_MAX_DRAW_TIME, 0.0, 1.0)
	var base_damage: float = float(bow_data.get("damage", 8.0)) * randf_range(0.7, 1.3)
	var damage_mult := lerpf(BOW_MIN_DAMAGE_MULT, BOW_MAX_DAMAGE_MULT, tension_pct)
	var final_damage: float = base_damage * damage_mult
	var wpn_stamina: float = float(bow_data.get("stamina_cost", 4.0))
	var wpn_knockback: float = float(bow_data.get("knockback", 10.0)) * tension_pct

	_bow_drawing = false
	_bow_tension = 0.0
	_hide_bow_reticle()
	_stop_bow_creak()
	if _bow_arrow_node:
		_bow_arrow_node.visible = false

	if not _can_spend_stamina(wpn_stamina):
		_revert_to_idle_sprite()
		return
	_spend_stamina(wpn_stamina)

	_start_attack_animation()

	var cam: Camera3D = _spring_arm.get_child(0) if _spring_arm.get_child_count() > 0 else null
	if not cam:
		return

	# Shoot toward where the reticle is aiming in 3D
	var reticle_screen := _get_reticle_center()
	var ray_origin := cam.project_ray_origin(reticle_screen)
	var ray_dir := cam.project_ray_normal(reticle_screen)
	var aim_target := ray_origin + ray_dir * 50.0

	# Offset spawn point toward the reticle's 3D position so arrow visually starts near the crosshair
	var cam_right := cam.global_transform.basis.x
	var spawn_pos := global_position + Vector3.UP * 1.6 + cam_right * 0.6
	var aim_dir := (aim_target - spawn_pos).normalized()
	var affixes := _get_active_affixes()
	var crit_chance := 5.0 + base_dexterity * 0.5
	var crit_dmg_mult := (150.0 + base_strength * 2.0) / 100.0
	if affixes.has(&"steady_aim") and velocity.length() < 0.5:
		crit_chance += _affix_val(&"steady_aim")
	if randf() < crit_chance / 100.0:
		final_damage *= crit_dmg_mult

	var base_wpn_damage: float = float(bow_data.get("damage", 8.0))
	var arrow_speed := lerpf(8.0, 32.0, tension_pct)
	if affixes.has(&"rapid_draw"):
		arrow_speed *= (1.0 + _affix_val(&"rapid_draw"))
	var launch_dir := aim_dir + Vector3.UP * lerpf(0.08, 0.02, tension_pct)
	var bow_parsed: Dictionary = ItemDatabase.parse_star_id(bow_id)
	var bow_stars: int = int(bow_parsed.get("stars", 0))
	var bow_qcolor: Variant = bow_data.get("quality_color", null)
	_spawn_arrow(spawn_pos, launch_dir.normalized() * arrow_speed, final_damage, wpn_knockback, tension_pct, bow_stars, bow_qcolor)
	AudioManager.play_sfx_at("arrow_swoosh", spawn_pos, -2.0)

	if affixes.has(&"echoing_shot"):
		var echo_chance: float = _affix_val(&"echoing_shot")
		var offset_sign := 1.0
		while randf() < echo_chance:
			var echo_dmg := base_wpn_damage * randf_range(0.7, 1.3) * damage_mult
			if randf() < crit_chance / 100.0:
				echo_dmg *= crit_dmg_mult
			var offset_dir := cam_right * (0.3 * offset_sign)
			_spawn_arrow(spawn_pos + offset_dir, launch_dir.normalized() * arrow_speed, echo_dmg, wpn_knockback, tension_pct, bow_stars, bow_qcolor)
			AudioManager.play_sfx_at("arrow_swoosh", spawn_pos, -4.0)
			offset_sign *= -1.0


func _arrow_aura_color(_stars: int, _qcol: Variant) -> Color:
	return Color(0.55, 0.1, 0.9)


func _make_aura_mat(col: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.no_depth_test = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return m


func _spawn_arrow(origin: Vector3, vel: Vector3, damage: float, knockback: float, tension_pct: float = 1.0, bow_stars: int = 0, quality_color: Variant = null) -> void:
	var arrow := Node3D.new()
	arrow.name = "Arrow"

	var is_legendary := bow_stars >= 4
	var aura_col := _arrow_aura_color(bow_stars, quality_color)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "ArrowMesh"
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 0.8)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if is_legendary:
		mat.albedo_color = aura_col
		mat.emission_enabled = true
		mat.emission = aura_col
		mat.emission_energy_multiplier = 8.0
	else:
		mat.albedo_color = Color(0.45, 0.3, 0.12)
	mesh_inst.set_surface_override_material(0, mat)
	arrow.add_child(mesh_inst)

	var tip_inst := MeshInstance3D.new()
	tip_inst.name = "Tip"
	var tip_mesh := BoxMesh.new()
	tip_mesh.size = Vector3(0.08, 0.08, 0.12)
	tip_inst.mesh = tip_mesh
	var tip_mat := StandardMaterial3D.new()
	tip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if is_legendary:
		tip_mat.albedo_color = Color(1.0, 1.0, 0.9)
		tip_mat.emission_enabled = true
		tip_mat.emission = aura_col
		tip_mat.emission_energy_multiplier = 12.0
	else:
		tip_mat.albedo_color = Color(0.3, 0.3, 0.3)
	tip_inst.set_surface_override_material(0, tip_mat)
	tip_inst.position.z = -0.42
	arrow.add_child(tip_inst)

	var fletch_inst := MeshInstance3D.new()
	fletch_inst.name = "Fletch"
	var fletch_mesh := BoxMesh.new()
	fletch_mesh.size = Vector3(0.1, 0.1, 0.1)
	fletch_inst.mesh = fletch_mesh
	var fletch_mat := StandardMaterial3D.new()
	fletch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if is_legendary:
		fletch_mat.albedo_color = aura_col
		fletch_mat.emission_enabled = true
		fletch_mat.emission = aura_col
		fletch_mat.emission_energy_multiplier = 6.0
	else:
		fletch_mat.albedo_color = Color(0.8, 0.8, 0.75)
	fletch_inst.set_surface_override_material(0, fletch_mat)
	fletch_inst.position.z = 0.38
	arrow.add_child(fletch_inst)

	if is_legendary:
		var light := OmniLight3D.new()
		light.name = "AuraLight"
		light.light_color = aura_col
		light.light_energy = 5.0
		light.omni_range = 4.0
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		arrow.add_child(light)

		var core := MeshInstance3D.new()
		core.name = "AuraCore"
		var cq := QuadMesh.new()
		cq.size = Vector2(0.5, 0.5)
		core.mesh = cq
		core.set_surface_override_material(0, _make_aura_mat(aura_col, 0.8, 16.0))
		arrow.add_child(core)

		var mid := MeshInstance3D.new()
		mid.name = "AuraMid"
		var mq := QuadMesh.new()
		mq.size = Vector2(1.0, 1.0)
		mid.mesh = mq
		mid.set_surface_override_material(0, _make_aura_mat(aura_col, 0.4, 10.0))
		arrow.add_child(mid)

		var outer := MeshInstance3D.new()
		outer.name = "AuraOuter"
		var oq := QuadMesh.new()
		oq.size = Vector2(1.75, 1.75)
		outer.mesh = oq
		outer.set_surface_override_material(0, _make_aura_mat(aura_col, 0.15, 6.0))
		arrow.add_child(outer)

		var trail := GPUParticles3D.new()
		trail.name = "AuraTrail"
		trail.amount = 30
		trail.lifetime = 0.5
		trail.explosiveness = 0.0
		trail.one_shot = false
		trail.local_coords = false
		trail.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
		var pmesh := QuadMesh.new()
		pmesh.size = Vector2(0.18, 0.18)
		trail.draw_pass_1 = pmesh
		var pmat := ParticleProcessMaterial.new()
		pmat.direction = Vector3(0, 0, 0)
		pmat.spread = 25.0
		pmat.initial_velocity_min = 0.2
		pmat.initial_velocity_max = 0.6
		pmat.gravity = Vector3.ZERO
		pmat.damping_min = 3.0
		pmat.damping_max = 6.0
		pmat.scale_min = 0.4
		pmat.scale_max = 1.2
		pmat.color = Color(aura_col.r, aura_col.g, aura_col.b, 1.0)
		var grad := Gradient.new()
		grad.colors = PackedColorArray([Color(aura_col, 1.0), Color(aura_col, 0.0)])
		grad.offsets = PackedFloat32Array([0.0, 1.0])
		var cramp := GradientTexture1D.new()
		cramp.gradient = grad
		pmat.color_ramp = cramp
		pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pmat.emission_sphere_radius = 0.1
		trail.process_material = pmat
		trail.material_override = _make_aura_mat(aura_col, 0.9, 12.0)
		arrow.add_child(trail)

	arrow.set_meta("velocity", vel)
	arrow.set_meta("damage", damage)
	arrow.set_meta("knockback", knockback)
	arrow.set_meta("tension", tension_pct)
	arrow.set_meta("lifetime", 0.0)
	arrow.set_meta("hit", false)
	arrow.add_to_group(&"arrows")

	get_tree().current_scene.add_child(arrow)
	arrow.global_position = origin


const ARROW_GRAVITY := 9.8
const ARROW_MAX_LIFETIME := 5.0
const HEATSEEK_RADIUS := 12.0
const HEATSEEK_CONE_DOT := 0.4
const HEATSEEK_TURN_SPEED := 4.5
const BOUNCE_SEARCH_RADIUS := 16.8


func _find_bounce_target(arrow: Node3D, hit_enemy: Node3D, all_enemies: Array[Node]) -> Node3D:
	var best: Node3D = null
	var best_dist := BOUNCE_SEARCH_RADIUS
	for e_node: Node in all_enemies:
		var e := e_node as Node3D
		if not e or e == hit_enemy:
			continue
		if e.has_method("is_dead") and e.is_dead():
			continue
		var d := arrow.global_position.distance_to(e.global_position)
		if d < best_dist:
			best_dist = d
			best = e
	return best


func _bounce_arrow_to(arrow: Node3D, target: Node3D) -> void:
	var speed: float = (arrow.get_meta("velocity") as Vector3).length()
	speed = maxf(speed * 0.5, 6.0)
	var target_center := target.global_position + Vector3.UP * 0.8
	var dir := (target_center - arrow.global_position).normalized()
	arrow.set_meta("velocity", dir * speed)
	arrow.set_meta("lifetime", 0.0)

func _tick_arrows(delta: float) -> void:
	var arrow_nodes := get_tree().get_nodes_in_group(&"arrows")
	if arrow_nodes.is_empty():
		return
	var do_heatseek := _has_affix(&"heatseeking")
	var all_enemies := get_tree().get_nodes_in_group(&"enemies")
	var all_fish := get_tree().get_nodes_in_group(&"carried_fish")
	var all_interactables := get_tree().get_nodes_in_group(&"interactables")
	var arrow_wg := _find_world_generator()
	for node: Node in arrow_nodes:
		var arrow := node as Node3D
		if not arrow or arrow.get_meta("hit", false):
			continue

		var vel: Vector3 = arrow.get_meta("velocity") as Vector3
		var t_pct: float = arrow.get_meta("tension", 1.0) as float
		var gravity := lerpf(ARROW_GRAVITY * 2.0, ARROW_GRAVITY * 0.4, t_pct)
		vel.y -= gravity * delta

		if do_heatseek:
			var speed := vel.length()
			if speed > 1.0:
				var fwd := vel / speed
				var best_enemy: Node3D = null
				var best_dot := HEATSEEK_CONE_DOT
				for e: Node in all_enemies:
					var enemy := e as Node3D
					if not enemy or not is_instance_valid(enemy):
						continue
					if enemy.has_method("is_dead") and enemy.is_dead():
						continue
					var to_e := (enemy.global_position + Vector3.UP * 0.8) - arrow.global_position
					var dist := to_e.length()
					if dist > HEATSEEK_RADIUS or dist < 0.5:
						continue
					var d := fwd.dot(to_e / dist)
					if d > best_dot:
						best_dot = d
						best_enemy = enemy
				if best_enemy:
					var desired := ((best_enemy.global_position + Vector3.UP * 0.8) - arrow.global_position).normalized()
					vel = (fwd.lerp(desired, HEATSEEK_TURN_SPEED * delta)).normalized() * speed

		arrow.set_meta("velocity", vel)

		var old_pos := arrow.global_position
		arrow.global_position += vel * delta
		var new_pos := arrow.global_position

		if vel.length_squared() > 0.5:
			var target_pos := arrow.global_position + vel.normalized()
			arrow.look_at(target_pos, Vector3.UP)

		var lifetime: float = arrow.get_meta("lifetime") as float + delta
		arrow.set_meta("lifetime", lifetime)

		var terrain_y := 0.0
		if arrow_wg:
			terrain_y = arrow_wg.get_height_at_scene(arrow.global_position.x, arrow.global_position.z)
		if arrow.global_position.y < terrain_y + 0.1:
			arrow.global_position.y = terrain_y + 0.05
			arrow.set_meta("hit", true)
			_stick_arrow(arrow)
			continue

		if lifetime > ARROW_MAX_LIFETIME:
			arrow.queue_free()
			continue

		var dmg: float = arrow.get_meta("damage") as float
		var kb: float = arrow.get_meta("knockback") as float
		# Swept collision: check multiple points along the arrow's path
		var travel := new_pos - old_pos
		var travel_len := travel.length()
		var step_count := maxi(1, ceili(travel_len / 0.4))
		for enemy_node: Node in all_enemies:
			var enemy := enemy_node as Node3D
			if not enemy:
				continue
			if enemy.has_method("is_dead") and enemy.is_dead():
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
				var hit_bonus := 0.0
				if is_headshot:
					hit_bonus += _affix_val(&"precision") if _has_affix(&"precision") else 0.3
				if _has_affix(&"sniper"):
					var dist_to_enemy := global_position.distance_to(enemy.global_position)
					if dist_to_enemy > 15.0:
						hit_bonus += _affix_val(&"sniper")
				var final_dmg := dmg * (1.0 + hit_bonus)
				if enemy.has_method("take_damage"):
					_apply_damage_to_creature(enemy, final_dmg)
					_set_target_creature(enemy)
					_DamageNumber.spawn(get_tree(), enemy.global_position + Vector3.UP * 1.5, final_dmg, is_headshot, "auto")
				if _has_affix(&"frost_arrow") and randf() < _affix_val(&"frost_arrow") and enemy.has_method("apply_slow"):
					enemy.apply_slow(0.65, 3.0)
				if _has_affix(&"poison_tip") and randf() < 0.30 and enemy.has_method("apply_poison"):
					var mhp: float = float(enemy.get("max_health")) if enemy.get("max_health") != null else 100.0
					enemy.apply_poison(mhp * _affix_val(&"poison_tip"), 4.0, self)
				if _has_affix(&"explosive") and randf() < _affix_val(&"explosive"):
					var aoe_dmg := dmg * 0.4
					for aoe_node: Node in all_enemies:
						var aoe_e := aoe_node as Node3D
						if not aoe_e or aoe_e == enemy:
							continue
						if aoe_e.has_method("is_dead") and aoe_e.is_dead():
							continue
						if enemy.global_position.distance_to(aoe_e.global_position) < 4.0:
							if aoe_e.has_method("take_damage"):
								_apply_damage_to_creature(aoe_e, aoe_dmg)
								_DamageNumber.spawn(get_tree(), aoe_e.global_position + Vector3.UP * 1.0, aoe_dmg, false, "ability")
				if kb > 0.0 and enemy is CharacterBody3D:
					var kb_dir := (enemy.global_position - hit_pos).normalized()
					kb_dir.y = 0.0
					(enemy as CharacterBody3D).velocity += kb_dir * kb * 0.1
				# Bouncing Shot: redirect arrow toward nearest other enemy
				if _has_affix(&"bouncing_shot") and randf() < _affix_val(&"bouncing_shot"):
					var bounce_target := _find_bounce_target(arrow, enemy, all_enemies)
					if bounce_target:
						_bounce_arrow_to(arrow, bounce_target)
					else:
						arrow.set_meta("hit", true)
						_stick_arrow(arrow)
				else:
					arrow.set_meta("hit", true)
					_stick_arrow(arrow)
				break

		# PvP arrow hits
		if not arrow.get_meta("hit", false) and NetworkManager.pvp_enabled:
			for p_node: Node in get_tree().get_nodes_in_group(&"player"):
				var other := p_node as CharacterBody3D
				if not other or other == self:
					continue
				if other.get("current_health") != null and float(other.current_health) <= 0.0:
					continue
				var p_radius := 0.5
				var p_height := 1.8
				var p_y_offset := 0.9
				var p_bottom := other.global_position.y + p_y_offset - p_height * 0.5
				var p_top := other.global_position.y + p_y_offset + p_height * 0.5
				var p_hit_margin := p_radius + 0.3
				var p_did_hit := false
				var p_hit_pos := new_pos
				for si in step_count + 1:
					var t := float(si) / float(step_count)
					var sample := old_pos.lerp(new_pos, t)
					var clamped_y := clampf(sample.y, p_bottom, p_top)
					var closest_axis := Vector3(other.global_position.x, clamped_y, other.global_position.z)
					if sample.distance_to(closest_axis) < p_hit_margin:
						p_did_hit = true
						p_hit_pos = sample
						break
				if p_did_hit:
					arrow.global_position = p_hit_pos
					_apply_damage_to_player(other, dmg)
					_DamageNumber.spawn(get_tree(), other.global_position + Vector3.UP * 1.5, dmg, false, "auto")
					if kb > 0.0:
						var kb_dir := (other.global_position - p_hit_pos).normalized()
						kb_dir.y = 0.0
						other.velocity += kb_dir * kb * 0.1
					arrow.set_meta("hit", true)
					_stick_arrow(arrow)
					break

		if not arrow.get_meta("hit", false):
			for fish_node: Node in all_fish:
				var fish := fish_node as Node3D
				if not fish:
					continue
				if arrow.global_position.distance_to(fish.global_position) < 1.5:
					arrow.set_meta("hit", true)
					var owner_creature = fish.get_meta("owner_creature", null)
					if owner_creature and owner_creature.has_method("drop_carried_fish"):
						owner_creature.drop_carried_fish()
					_stick_arrow(arrow)
					break

		if not arrow.get_meta("hit", false):
			for res_node: Node in all_interactables:
				var obj := res_node as Node3D
				if not obj:
					continue
				if arrow.global_position.distance_to(obj.global_position + Vector3.UP * 0.5) < 1.5:
					if obj.has_meta("harvestable") and obj.get_meta("drop_id", &"") != &"wood":
						arrow.set_meta("hit", true)
						_hit_harvestable(obj, dmg)
						_stick_arrow(arrow)
						break


func _stick_arrow(arrow: Node3D) -> void:
	arrow.remove_from_group(&"arrows")
	for n in ["AuraLight", "AuraCore", "AuraMid", "AuraOuter", "AuraTrail"]:
		var child := arrow.get_node_or_null(n)
		if child:
			child.queue_free()
	var shaft := arrow.get_node_or_null("ArrowMesh") as MeshInstance3D
	if shaft:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.45, 0.3, 0.12)
		shaft.set_surface_override_material(0, m)
	var tip := arrow.get_node_or_null("Tip") as MeshInstance3D
	if tip:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.3, 0.3, 0.3)
		tip.set_surface_override_material(0, m)
	var fletch := arrow.get_node_or_null("Fletch") as MeshInstance3D
	if fletch:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.8, 0.8, 0.75)
		fletch.set_surface_override_material(0, m)
	var tween := arrow.create_tween()
	tween.tween_interval(4.0)
	tween.tween_callback(arrow.queue_free)


func _update_bow_draw_sprite() -> void:
	if _gltf_anim_player:
		return
	if _bow_attack_frames.is_empty() or not _player_sprite:
		return
	var dir := _get_camera_relative_dir()
	if not _bow_attack_frames.has(dir):
		return
	var frames_arr: Array = Array(_bow_attack_frames[dir])
	if frames_arr.is_empty():
		return
	var tension_pct := clampf(_bow_tension / BOW_MAX_DRAW_TIME, 0.0, 1.0)
	# Use the first ~60% of frames for the draw, freeze the last frame at full draw
	var draw_frames := int(ceilf(frames_arr.size() * 0.6))
	var frame_idx := int(tension_pct * float(draw_frames - 1))
	frame_idx = clampi(frame_idx, 0, draw_frames - 1)
	var tex := frames_arr[frame_idx] as Texture2D
	if tex:
		_set_player_sprite_tex(tex)


func _show_bow_reticle() -> void:
	if not _bow_reticle and _hud_root:
		_bow_reticle = Control.new()
		_bow_reticle.name = "BowReticle"
		_bow_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_bow_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bow_reticle.draw.connect(_draw_bow_reticle)
		_hud_root.add_child(_bow_reticle)
	if _bow_reticle:
		_bow_reticle.visible = true


func _hide_bow_reticle() -> void:
	if _bow_reticle:
		_bow_reticle.visible = false


func _get_reticle_center() -> Vector2:
	var cam: Camera3D = _spring_arm.get_child(0) if _spring_arm.get_child_count() > 0 else null
	if not cam or not cam.is_inside_tree():
		return _bow_reticle.get_viewport_rect().size * 0.5 if _bow_reticle else Vector2.ZERO
	var head_world := global_position + Vector3.UP * 1.8
	var screen_pos := cam.unproject_position(head_world)
	return screen_pos + Vector2(110, -120)


func _draw_bow_reticle() -> void:
	if not _bow_reticle or not _bow_drawing:
		return
	var center := _get_reticle_center()
	var tension_pct := clampf(_bow_tension / BOW_MAX_DRAW_TIME, 0.0, 1.0)
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
		_bow_reticle.draw_line(ring_points[i], ring_points[i + 1], ring_color, 1.5, true)

	var ch_size := 5.0
	var ch_gap := 2.0
	var ch_color := Color(1.0, 1.0, 1.0, 0.9)
	_bow_reticle.draw_line(center + Vector2(-ch_size - ch_gap, 0), center + Vector2(-ch_gap, 0), ch_color, 1.5)
	_bow_reticle.draw_line(center + Vector2(ch_gap, 0), center + Vector2(ch_size + ch_gap, 0), ch_color, 1.5)
	_bow_reticle.draw_line(center + Vector2(0, -ch_size - ch_gap), center + Vector2(0, -ch_gap), ch_color, 1.5)
	_bow_reticle.draw_line(center + Vector2(0, ch_gap), center + Vector2(0, ch_size + ch_gap), ch_color, 1.5)

	_bow_reticle.draw_circle(center, 1.5, ch_color)

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
			_bow_reticle.draw_line(arc_points[i], arc_points[i + 1], arc_color, 2.0, true)


func _start_attack_animation() -> void:
	if _gltf_anim_player:
		_is_jumping = false
		_is_flipping = false
		_is_attacking = true
		if not _weapon_drawn:
			_draw_weapon()
		var wclass := ItemDatabase.get_weapon_class(equipped_weapon)
		var wpn_speed: float = _get_weapon_stat("attack_speed", 0.6)
		if _has_affix(&"rapid_strikes"):
			wpn_speed *= (1.0 - _affix_val(&"rapid_strikes"))
		elif _has_affix(&"rapid_chop"):
			wpn_speed *= (1.0 - _affix_val(&"rapid_chop"))
		elif _has_affix(&"quick_strike"):
			wpn_speed *= (1.0 - _affix_val(&"quick_strike"))
		_gltf_attack_timer = wpn_speed
		match wclass:
			"bow":
				_gltf_attack_timer = 0.45
				_gltf_attack_anim = "bow_release"
			"axe":
				_gltf_attack_anim = "axe_swing"
			"sword":
				_gltf_attack_anim = "sword_slash"
			"pickaxe":
				_gltf_attack_anim = "club_smash"
			_:
				var roll := randf()
				if roll < 0.33:
					_gltf_attack_anim = "kick"
				elif roll < 0.66:
					_gltf_attack_anim = "punch"
				else:
					_gltf_attack_anim = "punch_alt"
				_unarmed_attack_time = 0.0
				_unarmed_attack_duration = _gltf_attack_timer
		AudioManager.play_sfx("arrow_swoosh", -6.0, 0.15)
		_gltf_current_anim = ""
		_fit_attack_anim_to_timer()
		return


func _fit_attack_anim_to_timer() -> void:
	if not _gltf_anim_player or _gltf_attack_anim.is_empty() or _gltf_attack_timer <= 0.0:
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
	if aliases.has(_gltf_attack_anim):
		for alias in aliases[_gltf_attack_anim]:
			names_to_try.append(alias)
	names_to_try.append(_gltf_attack_anim)
	for base_name in names_to_try:
		for candidate in ["animation." + base_name, "animation_" + base_name, base_name]:
			if _gltf_anim_player.has_animation(candidate):
				var anim: Animation = _gltf_anim_player.get_animation(candidate)
				if anim and anim.length > 0.0:
					var speed: float = anim.length / _gltf_attack_timer
					_gltf_anim_player.speed_scale = speed
					_gltf_anim_player.play(candidate)
					_gltf_current_anim = candidate
					_gltf_playing_clip = candidate
					_gltf_playing_speed = speed
					synced_animation = candidate
				return


	if equipped_weapon == &"stone_pickaxe":
		_attack_frames = _pickaxe_attack_frames if not _pickaxe_attack_frames.is_empty() else _weapon_attack_frames
		_current_attack_frame_duration = ATTACK_FRAME_DURATION_TOOL
	elif equipped_weapon == &"crude_bow":
		_attack_frames = _bow_attack_frames if not _bow_attack_frames.is_empty() else _weapon_attack_frames
		_current_attack_frame_duration = ATTACK_FRAME_DURATION_BOW
	elif equipped_weapon == &"stone_axe":
		_attack_frames = _weapon_attack_frames if not _weapon_attack_frames.is_empty() else _fist_frames
		_current_attack_frame_duration = ATTACK_FRAME_DURATION_TOOL
	elif equipped_weapon == &"fists" or equipped_weapon == &"":
		if not _kick_frames_attack.is_empty() and randf() < 0.3:
			_attack_frames = _kick_frames_attack
		else:
			_attack_frames = _fist_frames if not _fist_frames.is_empty() else _weapon_attack_frames
		_current_attack_frame_duration = ATTACK_FRAME_DURATION_FIST
	else:
		var item_data: Dictionary = ItemDatabase.get_item(equipped_weapon)
		var item_type: String = str(item_data.get("type", ""))
		var item_name: String = str(item_data.get("name", "")).to_lower()
		if item_type != "weapon" and item_type != "tool":
			if not _kick_frames_attack.is_empty() and randf() < 0.3:
				_attack_frames = _kick_frames_attack
			else:
				_attack_frames = _fist_frames if not _fist_frames.is_empty() else _weapon_attack_frames
			_current_attack_frame_duration = ATTACK_FRAME_DURATION_FIST
		else:
			if item_name.contains("sword") and not _sword_attack_frames.is_empty():
				_attack_frames = _sword_attack_frames
			elif item_name.contains("pickaxe") and not _pickaxe_attack_frames.is_empty():
				_attack_frames = _pickaxe_attack_frames
			elif item_name.contains("axe") and not _weapon_attack_frames.is_empty():
				_attack_frames = _weapon_attack_frames
			elif item_name.contains("bow") and not _bow_attack_frames.is_empty():
				_attack_frames = _bow_attack_frames
			elif not _weapon_attack_frames.is_empty():
				_attack_frames = _weapon_attack_frames
			else:
				_attack_frames = _fist_frames
			_current_attack_frame_duration = ATTACK_FRAME_DURATION_TOOL

	if _attack_frames.is_empty():
		return
	_current_attack_dir = _get_camera_relative_dir()
	if not _attack_frames.has(_current_attack_dir):
		return
	_is_jumping = false
	_is_flipping = false
	_is_attacking = true
	_attack_frame_idx = 0
	_attack_frame_timer = _current_attack_frame_duration
	var frames_arr: Array = Array(_attack_frames[_current_attack_dir])
	if not frames_arr.is_empty():
		var tex := frames_arr[0] as Texture2D
		if tex and _player_sprite:
			_set_player_sprite_tex(tex)


# ===================================================================
# INVENTORY & HOTBAR UI
# ===================================================================

func _get_hotbar_items() -> Array[StringName]:
	var grouped: Array = Inventory.get_grouped_item_list()
	var result: Array[StringName] = []
	for i in range(8):
		if i < grouped.size():
			var entry: Dictionary = grouped[i]
			result.append(entry.get("exact_id", entry["base_id"]) as StringName)
		else:
			result.append(&"")
	return result


func _toggle_inventory() -> void:
	_auto_run = false
	_inventory_open = not _inventory_open
	if _inventory_open:
		_cancel_drag()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if _inventory_panel:
			_inventory_panel.visible = true
		if _crafting_panel:
			_crafting_panel.visible = true
		if _stats_arrow:
			_stats_arrow.visible = true
		if _stats_open and _stats_panel:
			_stats_panel.visible = true
		_refresh_inventory_ui()
		_position_stats_panel.call_deferred()
		if _stats_open:
			_refresh_stats_panel()
	else:
		_close_inventory()


func _close_inventory() -> void:
	_inventory_open = false
	_cancel_drag()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if _inventory_panel:
		_inventory_panel.visible = false
	if _crafting_panel:
		_crafting_panel.visible = false
	if _stats_arrow:
		_stats_arrow.visible = false
	if _stats_panel:
		_stats_panel.visible = false


func _toggle_map() -> void:
	if _map_disabled:
		return
	_map_open = not _map_open
	if _map_open:
		_map_zoom = _map_zoom_target
		_map_dirty = true
		if _map_panel:
			_map_panel.visible = true
		_refresh_map()
		_map_dirty = false
	else:
		_close_map()


func _close_map() -> void:
	_map_open = false
	if _map_panel:
		_map_panel.visible = false


func _build_hud() -> void:
	var hud := get_node_or_null("HUD") as CanvasLayer
	if not hud:
		return

	_hud_root = Control.new()
	_hud_root.name = "HUDRoot"
	_hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_hud_root)

	_build_hotbar(_hud_root)
	_build_drown_bar(_hud_root)
	_build_inventory_panel(_hud_root)
	_build_tooltip(_hud_root)
	_build_map_panel(_hud_root)
	_build_drag_icon(_hud_root)
	_build_build_menu(_hud_root)
	_workbench_ui = PlayerWorkbenchUI.new()
	add_child(_workbench_ui)
	_workbench_ui.pc = self
	_workbench_ui.build_workbench_panel(_hud_root)
	_interaction.build_chest_panel(_hud_root)
	_build_interaction_prompt(_hud_root)
	_build_world_name_label(_hud_root)
	_build_snap_label(_hud_root)
	_build_build_crosshair(_hud_root)
	_build_minimap(_hud_root)
	_build_fps_counter(_hud_root)
	_build_target_hud(_hud_root)
	_hud_module.build_chat_ui(_hud_root)
	_build_pause_menu()


func _build_pause_menu() -> void:
	_pause_overlay = CanvasLayer.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.layer = 100
	_pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	var input_catcher := Control.new()
	input_catcher.name = "PauseInputCatcher"
	input_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	input_catcher.process_mode = Node.PROCESS_MODE_ALWAYS
	input_catcher.focus_mode = Control.FOCUS_ALL
	input_catcher.gui_input.connect(func(event: InputEvent) -> void:
		if event.is_action_pressed(&"quit_game") and _pause_open:
			_close_pause_menu()
			input_catcher.get_viewport().set_input_as_handled()
	)
	_pause_overlay.add_child(input_catcher)

	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.55)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_catcher.add_child(bg)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.offset_left = -220
	center.offset_right = 220
	center.offset_top = -300
	center.offset_bottom = 300
	center.add_theme_constant_override("separation", 0)
	_pause_overlay.add_child(center)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	panel_style.border_color = Color(0.3, 0.28, 0.22)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	vbox.add_child(title)

	var music_idx := AudioServer.get_bus_index(&"Music")
	var music_db := AudioServer.get_bus_volume_db(music_idx) if music_idx != -1 else linear_to_db(0.7)
	var music_pct := db_to_linear(music_db)
	_add_volume_slider(vbox, "Music Volume", music_pct, func(val: float) -> void:
		var idx := AudioServer.get_bus_index(&"Music")
		if idx != -1:
			AudioServer.set_bus_volume_db(idx, linear_to_db(val))
		SaveManager.save_settings()
	)

	var sfx_idx := AudioServer.get_bus_index(&"SFX")
	var sfx_db := AudioServer.get_bus_volume_db(sfx_idx) if sfx_idx != -1 else linear_to_db(0.7)
	var sfx_pct := db_to_linear(sfx_db)
	_add_volume_slider(vbox, "SFX Volume", sfx_pct, func(val: float) -> void:
		var idx := AudioServer.get_bus_index(&"SFX")
		if idx != -1:
			AudioServer.set_bus_volume_db(idx, linear_to_db(val))
		SaveManager.save_settings()
	)

	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 10)
	res_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var res_label := Label.new()
	res_label.text = "Resolution"
	res_label.add_theme_font_size_override("font_size", 14)
	res_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.45))
	res_row.add_child(res_label)
	_pause_res_options = OptionButton.new()
	_pause_res_options.add_theme_font_size_override("font_size", 14)
	var current_size := DisplayServer.window_get_size()
	var selected_idx := -1
	for i in _pause_resolutions.size():
		var r: Vector2i = _pause_resolutions[i]
		_pause_res_options.add_item("%d x %d" % [r.x, r.y], i)
		if r == current_size:
			selected_idx = i
	if selected_idx >= 0:
		_pause_res_options.selected = selected_idx
	_pause_res_options.item_selected.connect(_on_resolution_selected)
	res_row.add_child(_pause_res_options)
	vbox.add_child(res_row)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 10)
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var mode_label := Label.new()
	mode_label.text = "Display"
	mode_label.add_theme_font_size_override("font_size", 14)
	mode_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.45))
	mode_row.add_child(mode_label)
	_pause_mode_options = OptionButton.new()
	_pause_mode_options.add_theme_font_size_override("font_size", 14)
	_pause_mode_options.add_item("Windowed", 0)
	_pause_mode_options.add_item("Fullscreen", 1)
	_pause_mode_options.add_item("Windowed Fullscreen", 2)
	var cur_wmode := get_window().mode
	if cur_wmode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		_pause_mode_options.selected = 1
	elif cur_wmode == Window.MODE_FULLSCREEN:
		_pause_mode_options.selected = 2
	else:
		_pause_mode_options.selected = 0
	_pause_mode_options.item_selected.connect(_on_display_mode_selected)
	mode_row.add_child(_pause_mode_options)
	vbox.add_child(mode_row)

	var rd_initial: float = float(SaveManager.render_distance)
	_add_render_distance_slider(vbox, "Render Distance", rd_initial, func(val: float) -> void:
		var r := int(val)
		SaveManager.render_distance = r
		var wg := get_tree().get_first_node_in_group(&"world_generator")
		if wg and wg.has_method(&"set_render_distance"):
			wg.set_render_distance(r)
		SaveManager.save_settings()
	)

	var pvp_row := HBoxContainer.new()
	pvp_row.add_theme_constant_override("separation", 10)
	pvp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var pvp_label := Label.new()
	pvp_label.text = "Enable PvP"
	pvp_label.add_theme_font_size_override("font_size", 14)
	pvp_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.45))
	pvp_row.add_child(pvp_label)
	var pvp_check := CheckButton.new()
	pvp_check.button_pressed = NetworkManager.pvp_enabled
	pvp_check.disabled = not NetworkManager.is_server()
	pvp_check.toggled.connect(func(on: bool) -> void:
		NetworkManager.set_pvp_enabled(on)
	)
	pvp_row.add_child(pvp_check)
	if not NetworkManager.is_connected_to_game():
		pvp_row.visible = false
	vbox.add_child(pvp_row)

	if NetworkManager.use_steam and NetworkManager.steam_lobby_id > 0:
		var invite_btn := _make_pause_button("Invite Friend (Steam)", Color(0.2, 0.35, 0.55))
		var invite_hint := Label.new()
		invite_hint.text = ""
		invite_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		invite_hint.add_theme_font_size_override("font_size", 12)
		invite_hint.add_theme_color_override("font_color", Color(0.8, 0.6, 0.3))
		invite_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		invite_hint.custom_minimum_size = Vector2(380, 0)
		invite_btn.pressed.connect(func() -> void:
			var s := SteamManager.get_steam()
			if s and s.isOverlayEnabled():
				_close_pause_menu()
				SteamManager.open_invite_dialog()
			else:
				invite_hint.text = "Steam overlay not available.\nTell your friend to right-click your name\nin Steam and click \"Join Game\"."
		)
		vbox.add_child(invite_btn)
		vbox.add_child(invite_hint)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	vbox.add_child(spacer)

	var resume_btn := _make_pause_button("Resume", Color(0.2, 0.45, 0.3))
	resume_btn.pressed.connect(_close_pause_menu)
	vbox.add_child(resume_btn)

	var char_btn := _make_pause_button("Exit to Character Screen", Color(0.5, 0.35, 0.2))
	char_btn.pressed.connect(func() -> void:
		_close_pause_menu()
		SaveManager.stop_game()
		if NetworkManager.is_connected_to_game():
			NetworkManager.disconnect_game()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
	)
	vbox.add_child(char_btn)

	var debug_btn := _make_pause_button("Debug Panel", Color(0.3, 0.3, 0.45))
	debug_btn.pressed.connect(func() -> void:
		_close_pause_menu()
		_ensure_debug_panel()
		_debug_panel.toggle_panel()
	)
	vbox.add_child(debug_btn)

	var quit_btn := _make_pause_button("Exit Game", Color(0.5, 0.15, 0.15))
	quit_btn.pressed.connect(func() -> void:
		SaveManager.stop_game()
		get_tree().quit()
	)
	vbox.add_child(quit_btn)


func _add_volume_slider(parent: VBoxContainer, label_text: String, initial: float, on_change: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.custom_minimum_size = Vector2(0, 24)

	var slider_style := StyleBoxFlat.new()
	slider_style.bg_color = Color(0.18, 0.18, 0.22)
	slider_style.set_corner_radius_all(4)
	slider_style.content_margin_top = 8
	slider_style.content_margin_bottom = 8
	slider.add_theme_stylebox_override("slider", slider_style)

	var grabber_style := StyleBoxFlat.new()
	grabber_style.bg_color = Color(0.85, 0.75, 0.55)
	grabber_style.set_corner_radius_all(4)

	slider.value_changed.connect(func(val: float) -> void: on_change.call(val))
	row.add_child(slider)
	parent.add_child(row)


func _add_render_distance_slider(parent: VBoxContainer, label_text: String, initial: float, on_change: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	header.add_child(lbl)

	var val_lbl := Label.new()
	val_lbl.text = str(int(initial))
	val_lbl.add_theme_font_size_override("font_size", 15)
	val_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.55))
	header.add_child(val_lbl)

	row.add_child(header)

	var slider := HSlider.new()
	slider.min_value = 1.0
	slider.max_value = 5.0
	slider.step = 1.0
	slider.value = initial
	slider.custom_minimum_size = Vector2(0, 24)

	var slider_style := StyleBoxFlat.new()
	slider_style.bg_color = Color(0.18, 0.18, 0.22)
	slider_style.set_corner_radius_all(4)
	slider_style.content_margin_top = 8
	slider_style.content_margin_bottom = 8
	slider.add_theme_stylebox_override("slider", slider_style)

	slider.value_changed.connect(func(val: float) -> void:
		val_lbl.text = str(int(val))
		on_change.call(val)
	)
	row.add_child(slider)
	parent.add_child(row)


func _make_pause_button(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 16)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.1)
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn


func _open_pause_menu() -> void:
	_pause_open = true
	_pause_overlay.visible = true
	if not NetworkManager.is_connected_to_game():
		get_tree().paused = true
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var catcher := _pause_overlay.get_node_or_null("PauseInputCatcher") as Control
	if catcher:
		catcher.grab_focus()


func _close_pause_menu() -> void:
	_pause_open = false
	_pause_overlay.visible = false
	if not NetworkManager.is_connected_to_game():
		get_tree().paused = false
	AudioServer.set_bus_mute(AudioServer.get_bus_index(&"Master"), false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_resolution_selected(idx: int) -> void:
	var r: Vector2i = _pause_resolutions[idx]
	get_window().mode = Window.MODE_WINDOWED
	get_window().borderless = false
	get_window().size = r
	get_window().position = (DisplayServer.screen_get_size() - r) / 2
	if _pause_mode_options:
		_pause_mode_options.selected = 0
	SaveManager.save_settings()


func _on_display_mode_selected(idx: int) -> void:
	match idx:
		0:
			get_window().mode = Window.MODE_WINDOWED
			get_window().borderless = false
			var r: Vector2i = _pause_resolutions[_pause_res_options.selected] if _pause_res_options and _pause_res_options.selected >= 0 else Vector2i(1920, 1080)
			get_window().size = r
			get_window().position = (DisplayServer.screen_get_size() - r) / 2
		1:
			get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		2:
			get_window().mode = Window.MODE_FULLSCREEN
	SaveManager.save_settings()


func _ensure_debug_panel() -> void:
	if _debug_panel and is_instance_valid(_debug_panel):
		return
	var DebugPanelClass := load("res://scripts/debug/debug_panel.gd")
	_debug_panel = DebugPanelClass.new()
	_debug_panel.setup(self)
	add_child(_debug_panel)


func _build_fps_counter(root: Control) -> void:
	_fps_label = Label.new()
	_fps_label.name = "FPSLabel"
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	_fps_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_fps_label.add_theme_constant_override("shadow_offset_x", 1)
	_fps_label.add_theme_constant_override("shadow_offset_y", 1)
	_fps_label.position = Vector2(10, 10)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.z_index = 100
	root.add_child(_fps_label)


func _build_target_hud(root: Control) -> void:
	_target_hud_panel = PanelContainer.new()
	_target_hud_panel.name = "TargetHUD"
	_target_hud_panel.visible = false
	_target_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_hud_panel.z_index = 90

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.85)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.35, 0.25, 0.6)
	_target_hud_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 4)
	_target_hud_panel.add_child(vbox)

	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(name_row)

	_target_hud_name = Label.new()
	_target_hud_name.add_theme_font_size_override("font_size", 22)
	_target_hud_name.add_theme_color_override("font_color", Color.WHITE)
	_target_hud_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_target_hud_name.add_theme_constant_override("shadow_offset_x", 1)
	_target_hud_name.add_theme_constant_override("shadow_offset_y", 1)
	_target_hud_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(_target_hud_name)

	_target_hud_stars = Label.new()
	_target_hud_stars.add_theme_font_size_override("font_size", 22)
	_target_hud_stars.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_target_hud_stars.add_theme_constant_override("shadow_offset_x", 1)
	_target_hud_stars.add_theme_constant_override("shadow_offset_y", 1)
	_target_hud_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.add_child(_target_hud_stars)

	var bar_bg := ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(330, 20)
	bar_bg.color = Color(0.15, 0.15, 0.15, 0.9)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(bar_bg)
	_target_hud_hp_bar = bar_bg

	_target_hud_hp_fill = ColorRect.new()
	_target_hud_hp_fill.color = Color(0.8, 0.15, 0.15, 1.0)
	_target_hud_hp_fill.position = Vector2.ZERO
	_target_hud_hp_fill.size = Vector2(330, 20)
	_target_hud_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(_target_hud_hp_fill)

	_target_hud_hp_label = Label.new()
	_target_hud_hp_label.add_theme_font_size_override("font_size", 14)
	_target_hud_hp_label.add_theme_color_override("font_color", Color.WHITE)
	_target_hud_hp_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_target_hud_hp_label.add_theme_constant_override("shadow_offset_x", 1)
	_target_hud_hp_label.add_theme_constant_override("shadow_offset_y", 1)
	_target_hud_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_hud_hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_hud_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bar_bg.add_child(_target_hud_hp_label)

	root.add_child(_target_hud_panel)


func _update_target_hud(delta: float) -> void:
	if not _target_hud_panel:
		return

	var cam: Camera3D = _spring_arm.get_child(0) if _spring_arm and _spring_arm.get_child_count() > 0 else null
	if cam and cam.is_inside_tree() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var ray_origin := cam.global_position
		var ray_dir := -cam.global_transform.basis.z
		var ray_end := ray_origin + ray_dir * 200.0
		var space := get_world_3d().direct_space_state
		if space:
			var q := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 0xFFFFFFFF)
			q.exclude = [get_rid()]
			q.collide_with_bodies = true
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var obj := hit["collider"] as Node3D
				var creature: Node3D = null
				if obj and obj.is_in_group(&"enemies"):
					creature = obj
				elif obj and obj.get_parent() and obj.get_parent().is_in_group(&"enemies"):
					creature = obj.get_parent()
				if creature and creature.has_method("take_damage"):
					_set_target_creature(creature)

	if _target_hud_timer > 0.0:
		_target_hud_timer -= delta
		if _target_hud_timer <= 0.0:
			_target_creature = null
			_target_hud_panel.visible = false
			return

	if _target_creature and is_instance_valid(_target_creature):
		_target_hud_panel.visible = true
		var hp: float = _target_creature.get("current_health") if _target_creature.get("current_health") != null else 0.0
		var max_hp: float = _target_creature.get("max_health") if _target_creature.get("max_health") != null else 1.0
		var pct := clampf(hp / maxf(max_hp, 0.01), 0.0, 1.0)
		_target_hud_hp_fill.size.x = 330.0 * pct
		if pct > 0.5:
			_target_hud_hp_fill.color = Color(0.2, 0.75, 0.2, 1.0)
		elif pct > 0.25:
			_target_hud_hp_fill.color = Color(0.85, 0.7, 0.1, 1.0)
		else:
			_target_hud_hp_fill.color = Color(0.8, 0.15, 0.15, 1.0)
		_target_hud_hp_label.text = "%d / %d" % [ceili(hp), ceili(max_hp)]

		_target_hud_panel.reset_size()
		var vp_w := get_viewport().get_visible_rect().size.x
		_target_hud_panel.position = Vector2((vp_w - _target_hud_panel.size.x) * 0.5, 50)
	elif _target_creature and not is_instance_valid(_target_creature):
		_target_creature = null
		_target_hud_panel.visible = false


func _set_target_creature(creature: Node3D) -> void:
	if not is_multiplayer_authority():
		return
	if creature == _target_creature and _target_hud_timer > 0.0:
		_target_hud_timer = 5.0
		return
	_target_creature = creature
	_target_hud_timer = 5.0

	if not _target_hud_name:
		return
	var dname: String = creature.get("display_name") if creature.get("display_name") != null else "Unknown"
	var stars: int = creature.get("star_level") if creature.get("star_level") != null else 0
	_target_hud_name.text = dname
	if stars > 0:
		var star_str := " "
		for i in stars:
			star_str += "★"
		_target_hud_stars.text = star_str
		_target_hud_stars.add_theme_color_override("font_color", ItemDatabase.get_rarity_color(stars))
		_target_hud_stars.visible = true
	else:
		_target_hud_stars.text = ""
		_target_hud_stars.visible = false


func _build_world_name_label(root: Control) -> void:
	_world_name_label = Label.new()
	_world_name_label.name = "WorldNameLabel"
	_world_name_label.visible = false
	_world_name_label.add_theme_font_size_override("font_size", 16)
	_world_name_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	_world_name_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_world_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_world_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_world_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_name_label.z_index = 80
	root.add_child(_world_name_label)


func _minimap_do_zoom(delta_zoom: float) -> void:
	_minimap_zoom = clampf(_minimap_zoom + delta_zoom, MINIMAP_ZOOM_MIN, MINIMAP_ZOOM_MAX)
	_minimap_needs_refresh = true
	_refresh_minimap()


func _build_minimap(root: Control) -> void:
	var map_margin := 8
	var circle_d := MINIMAP_PX
	var frame_extra := 28
	var total_w := circle_d + frame_extra * 2
	var banner_h := 26
	var banner_y := 0
	var circle_x := frame_extra
	var circle_y := banner_h + 4
	var bottom_y := circle_y + circle_d

	var outer := Control.new()
	outer.name = "MinimapOuter"
	outer.anchor_left = 1.0
	outer.anchor_right = 1.0
	outer.anchor_top = 0.0
	outer.anchor_bottom = 0.0
	outer.offset_left = -(total_w + map_margin)
	outer.offset_right = -map_margin
	outer.offset_top = map_margin
	outer.offset_bottom = float(bottom_y + 36)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(outer)
	_minimap_outer = outer

	# â”€â”€ Biome name banner (grey translucent box, like WoW's "Mulgore") â”€â”€
	var banner := PanelContainer.new()
	banner.name = "BiomeBanner"
	var bstyle := StyleBoxFlat.new()
	bstyle.bg_color = Color(0.15, 0.15, 0.17, 0.80)
	bstyle.set_border_width_all(2)
	bstyle.border_color = Color(0.42, 0.38, 0.28, 0.9)
	bstyle.set_corner_radius_all(4)
	bstyle.set_content_margin_all(2)
	bstyle.content_margin_left = 12
	bstyle.content_margin_right = 12
	banner.add_theme_stylebox_override("panel", bstyle)
	banner.position = Vector2(8, banner_y)
	banner.size = Vector2(total_w - 16, banner_h)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(banner)

	_minimap_biome_label = Label.new()
	_minimap_biome_label.name = "BiomeLabel"
	_minimap_biome_label.text = ""
	_minimap_biome_label.add_theme_font_size_override("font_size", 15)
	_minimap_biome_label.add_theme_color_override("font_color", Color(0.92, 0.84, 0.52))
	_minimap_biome_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_minimap_biome_label.add_theme_constant_override("shadow_offset_x", 1)
	_minimap_biome_label.add_theme_constant_override("shadow_offset_y", 1)
	_minimap_biome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_minimap_biome_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_minimap_biome_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_minimap_biome_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_minimap_biome_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(_minimap_biome_label)

	# â”€â”€ Map circle area (the circular texture) â”€â”€
	var map_clip := Control.new()
	map_clip.name = "MapClip"
	map_clip.position = Vector2(circle_x, circle_y)
	map_clip.custom_minimum_size = Vector2(circle_d, circle_d)
	map_clip.size = Vector2(circle_d, circle_d)
	map_clip.clip_contents = true
	map_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(map_clip)

	_minimap_tex_rect = TextureRect.new()
	_minimap_tex_rect.custom_minimum_size = Vector2(circle_d, circle_d)
	_minimap_tex_rect.size = Vector2(circle_d, circle_d)
	_minimap_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_minimap_tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_minimap_tex_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_minimap_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_clip.add_child(_minimap_tex_rect)

	# â”€â”€ "N" compass indicator at top of circle â”€â”€
	var north_lbl := Label.new()
	north_lbl.text = "N"
	north_lbl.add_theme_font_size_override("font_size", 13)
	north_lbl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	north_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	north_lbl.add_theme_constant_override("shadow_offset_x", 1)
	north_lbl.add_theme_constant_override("shadow_offset_y", 1)
	north_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	north_lbl.position = Vector2(circle_d / 2 - 6, MINIMAP_RING + 1)
	north_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	north_lbl.z_index = 6
	map_clip.add_child(north_lbl)

	# â”€â”€ Icons placed on the circle ring edge â”€â”€
	var half_d := float(circle_d) / 2.0
	var ring_r := half_d - 1.0

	# Weather icon â€” top-right (about 1:30 on a clock, ~60Â° from top)
	var weather_angle := -PI * 0.28
	var wx := circle_x + half_d + ring_r * sin(weather_angle) - 14.0
	var wy := circle_y + half_d - ring_r * cos(weather_angle) - 14.0
	var weather_frame := _make_minimap_icon_frame(28)
	weather_frame.position = Vector2(wx, wy)
	outer.add_child(weather_frame)

	_minimap_weather_label = Label.new()
	_minimap_weather_label.name = "WeatherIcon"
	_minimap_weather_label.text = "â˜€"
	_minimap_weather_label.add_theme_font_size_override("font_size", 16)
	_minimap_weather_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	_minimap_weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_minimap_weather_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_minimap_weather_label.position = Vector2(2, 2)
	_minimap_weather_label.size = Vector2(24, 24)
	_minimap_weather_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weather_frame.add_child(_minimap_weather_label)

	# Zoom + button â€” bottom-right (about 4 o'clock, ~120Â° from top)
	var zp_angle := PI * 0.35
	var zp_x := circle_x + half_d + ring_r * sin(zp_angle) - 13.0
	var zp_y := circle_y + half_d - ring_r * cos(zp_angle) - 13.0
	var zoom_in_frame := _make_minimap_icon_frame(26)
	zoom_in_frame.position = Vector2(zp_x, zp_y)
	outer.add_child(zoom_in_frame)

	var zoom_in_btn := Button.new()
	zoom_in_btn.text = "+"
	zoom_in_btn.position = Vector2.ZERO
	zoom_in_btn.size = Vector2(26, 26)
	zoom_in_btn.custom_minimum_size = Vector2(26, 26)
	zoom_in_btn.add_theme_font_size_override("font_size", 16)
	zoom_in_btn.flat = true
	zoom_in_btn.add_theme_color_override("font_color", Color(0.9, 0.82, 0.45))
	zoom_in_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	zoom_in_btn.z_index = 10
	zoom_in_btn.pressed.connect(func() -> void: _minimap_do_zoom(-MINIMAP_ZOOM_STEP))
	zoom_in_frame.add_child(zoom_in_btn)

	# Zoom - button â€” below + (about 5 o'clock, ~150Â° from top)
	var zm_angle := PI * 0.45
	var zm_x := circle_x + half_d + ring_r * sin(zm_angle) - 13.0
	var zm_y := circle_y + half_d - ring_r * cos(zm_angle) - 13.0
	var zoom_out_frame := _make_minimap_icon_frame(26)
	zoom_out_frame.position = Vector2(zm_x, zm_y)
	outer.add_child(zoom_out_frame)

	var zoom_out_btn := Button.new()
	zoom_out_btn.text = "-"
	zoom_out_btn.position = Vector2.ZERO
	zoom_out_btn.size = Vector2(26, 26)
	zoom_out_btn.custom_minimum_size = Vector2(26, 26)
	zoom_out_btn.add_theme_font_size_override("font_size", 16)
	zoom_out_btn.flat = true
	zoom_out_btn.add_theme_color_override("font_color", Color(0.9, 0.82, 0.45))
	zoom_out_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	zoom_out_btn.z_index = 10
	zoom_out_btn.pressed.connect(func() -> void: _minimap_do_zoom(MINIMAP_ZOOM_STEP))
	zoom_out_frame.add_child(zoom_out_btn)

	# â”€â”€ Time label (bottom center, in a small dark banner) â”€â”€
	var time_banner := PanelContainer.new()
	time_banner.name = "TimeBanner"
	var tstyle := StyleBoxFlat.new()
	tstyle.bg_color = Color(0.10, 0.10, 0.12, 0.85)
	tstyle.set_border_width_all(1)
	tstyle.border_color = Color(0.42, 0.38, 0.28, 0.8)
	tstyle.set_corner_radius_all(3)
	tstyle.set_content_margin_all(1)
	tstyle.content_margin_left = 8
	tstyle.content_margin_right = 8
	time_banner.add_theme_stylebox_override("panel", tstyle)
	time_banner.position = Vector2(circle_x + circle_d / 2 - 28, float(bottom_y) + 2.0)
	time_banner.size = Vector2(56, 20)
	time_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(time_banner)

	_minimap_time_label = Label.new()
	_minimap_time_label.name = "TimeLabel"
	_minimap_time_label.text = "12:00"
	_minimap_time_label.add_theme_font_size_override("font_size", 12)
	_minimap_time_label.add_theme_color_override("font_color", Color(0.85, 0.80, 0.65))
	_minimap_time_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_minimap_time_label.add_theme_constant_override("shadow_offset_x", 1)
	_minimap_time_label.add_theme_constant_override("shadow_offset_y", 1)
	_minimap_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_minimap_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_minimap_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_minimap_time_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_minimap_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_banner.add_child(_minimap_time_label)

	# â”€â”€ Pre-compute circular mask (ring = gold, inside = white, outside = transparent) â”€â”€
	_minimap_image = Image.create(MINIMAP_PX, MINIMAP_PX, false, Image.FORMAT_RGBA8)
	_minimap_image_tex = ImageTexture.new()
	_minimap_circle_mask = Image.create(MINIMAP_PX, MINIMAP_PX, false, Image.FORMAT_RGBA8)
	var half := float(MINIMAP_PX) * 0.5
	var ring_outer := half
	var ring_inner := half - float(MINIMAP_RING)
	for y in MINIMAP_PX:
		for x in MINIMAP_PX:
			var dx := float(x) - half
			var dy := float(y) - half
			var dist := sqrt(dx * dx + dy * dy)
			if dist > ring_outer:
				_minimap_circle_mask.set_pixel(x, y, Color(0, 0, 0, 0))
			elif dist > ring_inner:
				var t := (dist - ring_inner) / float(MINIMAP_RING)
				var edge_fade := 1.0 - t
				var highlight := 0.5 + 0.2 * (1.0 - t)
				var inner_glow := lerpf(0.7, 0.35, t)
				_minimap_circle_mask.set_pixel(x, y, Color(
					inner_glow * highlight,
					inner_glow * highlight * 0.78,
					inner_glow * highlight * 0.32,
					clampf(edge_fade + 0.5, 0.0, 1.0)))
			else:
				_minimap_circle_mask.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))


func _make_minimap_icon_frame(sz: int) -> PanelContainer:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.11, 0.10, 0.85)
	style.set_border_width_all(2)
	style.border_color = Color(0.50, 0.43, 0.28, 0.95)
	style.set_corner_radius_all(sz / 2)
	style.set_content_margin_all(0)
	frame.add_theme_stylebox_override("panel", style)
	frame.custom_minimum_size = Vector2(sz, sz)
	frame.size = Vector2(sz, sz)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.z_index = 8
	return frame


func _draw_arrow_on_image(img: Image, half_px: int, scale: float = 1.0) -> void:
	var cam := get_viewport().get_camera_3d()
	var facing := 0.0
	if cam:
		var fwd := -cam.global_transform.basis.z
		facing = atan2(fwd.x, -fwd.z)

	var arrow_col := Color(1.0, 0.3, 0.2)
	var outline_col := Color(0.15, 0.05, 0.02)
	var center_col := Color(1.0, 1.0, 1.0)
	var img_sz := img.get_width()

	var verts: Array[Vector2] = [
		Vector2(0.0, -5.0) * scale,
		Vector2(-3.0, 4.0) * scale,
		Vector2(0.0, 1.5) * scale,
		Vector2(3.0, 4.0) * scale,
	]
	var cos_a := cos(facing)
	var sin_a := sin(facing)
	var reach := int(7.0 * scale) + 1

	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var px_x := half_px + dx
			var px_y := half_px + dy
			if px_x < 0 or px_x >= img_sz or px_y < 0 or px_y >= img_sz:
				continue
			var pt := Vector2(
				float(dx) * cos_a + float(dy) * sin_a,
				-float(dx) * sin_a + float(dy) * cos_a)
			if _point_in_arrow(pt, verts, 1.2):
				img.set_pixel(px_x, px_y, outline_col)

	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var px_x := half_px + dx
			var px_y := half_px + dy
			if px_x < 0 or px_x >= img_sz or px_y < 0 or px_y >= img_sz:
				continue
			var pt := Vector2(
				float(dx) * cos_a + float(dy) * sin_a,
				-float(dx) * sin_a + float(dy) * cos_a)
			if _point_in_arrow(pt, verts, 1.0):
				img.set_pixel(px_x, px_y, arrow_col)

	if half_px >= 0 and half_px < img_sz:
		img.set_pixel(half_px, half_px, center_col)


const _MINIMAP_LO := 36  # 180 / 5 â€” one pixel per stride cell

var _minimap_lo_image: Image
var _minimap_mask_lut: PackedByteArray  # 0=skip, 1=ring, 2=terrain
var _minimap_ring_colors: PackedColorArray
var _minimap_zone_color_cache: Dictionary = {}  # Vector2i -> Color
var _minimap_last_pos: Vector3 = Vector3.ZERO

func _ensure_minimap_lut() -> void:
	if not _minimap_mask_lut.is_empty():
		return
	_minimap_lo_image = Image.create(_MINIMAP_LO, _MINIMAP_LO, false, Image.FORMAT_RGBA8)
	var stride := MINIMAP_PX / _MINIMAP_LO
	var count := _MINIMAP_LO * _MINIMAP_LO
	_minimap_mask_lut.resize(count)
	_minimap_ring_colors.resize(count)
	for ly in _MINIMAP_LO:
		for lx in _MINIMAP_LO:
			var px := lx * stride
			var py := ly * stride
			var idx := ly * _MINIMAP_LO + lx
			var mask_px := _minimap_circle_mask.get_pixel(px, py)
			if mask_px.a < 0.01:
				_minimap_mask_lut[idx] = 0
			elif (mask_px.r < 0.95 or mask_px.g < 0.95 or mask_px.b < 0.95) and mask_px.r < 0.9:
				_minimap_mask_lut[idx] = 1
				_minimap_ring_colors[idx] = Color(mask_px.r, mask_px.g, mask_px.b, mask_px.a)
			else:
				_minimap_mask_lut[idx] = 2


func _refresh_minimap() -> void:
	if not _minimap_image or not _minimap_tex_rect:
		return
	var wg := _find_world_generator()
	if not wg:
		return

	_minimap_needs_refresh = false
	_ensure_minimap_lut()

	var player_pos := wg.get_world_position(self)
	var half_lo := _MINIMAP_LO / 2
	var zone_size: float = wg.ZONE_SIZE
	var water_col := Color(0.12, 0.28, 0.52)
	var water_shallow := Color(0.18, 0.38, 0.55)
	var transparent := Color(0, 0, 0, 0)

	var world_radius_map := _minimap_zoom * zone_size
	var meters_per_lo_pixel := world_radius_map / float(half_lo)

	for ly in _MINIMAP_LO:
		for lx in _MINIMAP_LO:
			var idx := ly * _MINIMAP_LO + lx
			var mask_type: int = _minimap_mask_lut[idx]
			if mask_type == 0:
				_minimap_lo_image.set_pixel(lx, ly, transparent)
				continue
			if mask_type == 1:
				_minimap_lo_image.set_pixel(lx, ly, _minimap_ring_colors[idx])
				continue

			var world_x := player_pos.x + float(lx - half_lo) * meters_per_lo_pixel
			var world_z := player_pos.z + float(ly - half_lo) * meters_per_lo_pixel
			var zone_coord := Vector2i(
				floori(world_x / zone_size),
				floori(world_z / zone_size))

			var col: Color
			if _minimap_zone_color_cache.has(zone_coord):
				col = _minimap_zone_color_cache[zone_coord] as Color
			else:
				var zx := (float(zone_coord.x) + 0.5) * zone_size
				var zz := (float(zone_coord.y) + 0.5) * zone_size
				var zh := wg.get_height_at(zx, zz)
				if zh < wg.WATER_LEVEL:
					var depth := clampf((wg.WATER_LEVEL - zh) / 6.0, 0.0, 1.0)
					col = water_shallow.lerp(water_col, depth)
				else:
					var biome: StringName = wg._determine_biome(zone_coord)
					var micro := wg.get_microbiome_at_zone(zone_coord)
					col = _biome_map_color(biome, micro)
					var bright := clampf(lerpf(0.7, 1.25, (zh + 5.0) / 30.0), 0.0, 1.0)
					col = Color(
						clampf(col.r * bright, 0.0, 1.0),
						clampf(col.g * bright, 0.0, 1.0),
						clampf(col.b * bright, 0.0, 1.0))
				_minimap_zone_color_cache[zone_coord] = col
			_minimap_lo_image.set_pixel(lx, ly, col)

	_draw_arrow_on_image(_minimap_lo_image, _MINIMAP_LO / 2, 0.52)

	_minimap_image_tex.set_image(_minimap_lo_image)
	if _minimap_tex_rect.texture != _minimap_image_tex:
		_minimap_tex_rect.texture = _minimap_image_tex

	if _minimap_biome_label:
		var current_biome: StringName = wg.get_biome_at(player_pos)
		_minimap_biome_label.text = _biome_display_name(current_biome)
	if _minimap_weather_label:
		_minimap_weather_label.text = WeatherSystem.get_weather_emoji()
	if _minimap_time_label:
		var dnc := get_tree().current_scene.get_node_or_null("DayNightCycle") if get_tree().current_scene else null
		if dnc and dnc.has_method("get_time_string"):
			_minimap_time_label.text = dnc.get_time_string()
		else:
			var dict := Time.get_time_dict_from_system()
			_minimap_time_label.text = "%02d:%02d" % [dict["hour"], dict["minute"]]


func _build_hotbar(root: Control) -> void:
	var bar := HBoxContainer.new()
	bar.name = "Hotbar"
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 4)
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -270
	bar.offset_right = 270
	bar.offset_top = -68
	bar.offset_bottom = -4
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bar)

	for i in range(8):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(60, 60)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.mouse_entered.connect(_on_hotbar_hover.bind(i))
		slot.mouse_exited.connect(_hide_tooltip)

		var stack := Control.new()
		stack.custom_minimum_size = Vector2(56, 56)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var icon_rect := TextureRect.new()
		icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(icon_rect)

		var num := Label.new()
		num.text = str(i + 1)
		num.add_theme_font_size_override("font_size", 9)
		num.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 0.6))
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		num.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		num.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(num)

		var qty_label := Label.new()
		qty_label.add_theme_font_size_override("font_size", 12)
		qty_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
		qty_label.add_theme_constant_override("outline_size", 3)
		qty_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
		qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		qty_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		qty_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		qty_label.text = ""
		stack.add_child(qty_label)

		slot.add_child(stack)
		bar.add_child(slot)
		_hotbar_slots.append(slot)
		_hotbar_labels.append(num)
		_hotbar_icons.append(icon_rect)
		_hotbar_qty_labels.append(qty_label)

	_update_hotbar_selection()


func _build_drown_bar(root: Control) -> void:
	_drown_bar_container = Control.new()
	_drown_bar_container.name = "DrownBar"
	_drown_bar_container.anchor_left = 0.5
	_drown_bar_container.anchor_right = 0.5
	_drown_bar_container.anchor_top = 1.0
	_drown_bar_container.anchor_bottom = 1.0
	_drown_bar_container.offset_left = -160
	_drown_bar_container.offset_right = 160
	_drown_bar_container.offset_top = -90
	_drown_bar_container.offset_bottom = -76
	_drown_bar_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_drown_bar_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drown_bar_container.visible = false
	root.add_child(_drown_bar_container)

	_drown_bar_bg = ColorRect.new()
	_drown_bar_bg.color = Color(0.02, 0.04, 0.08, 0.85)
	_drown_bar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drown_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drown_bar_container.add_child(_drown_bar_bg)

	var border := ColorRect.new()
	border.color = Color(0.15, 0.35, 0.55, 0.9)
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.offset_left = -1
	border.offset_right = 1
	border.offset_top = -1
	border.offset_bottom = 1
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.z_index = -1
	_drown_bar_container.add_child(border)

	_drown_bar_fill = ColorRect.new()
	_drown_bar_fill.color = Color(0.15, 0.55, 0.95, 0.95)
	_drown_bar_fill.anchor_left = 0.0
	_drown_bar_fill.anchor_right = 1.0
	_drown_bar_fill.anchor_top = 0.0
	_drown_bar_fill.anchor_bottom = 1.0
	_drown_bar_fill.offset_left = 0
	_drown_bar_fill.offset_right = 0
	_drown_bar_fill.offset_top = 0
	_drown_bar_fill.offset_bottom = 0
	_drown_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drown_bar_container.add_child(_drown_bar_fill)

	var icon_label := Label.new()
	icon_label.text = "O2"
	icon_label.add_theme_font_size_override("font_size", 10)
	icon_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0, 0.9))
	icon_label.add_theme_constant_override("outline_size", 2)
	icon_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drown_bar_container.add_child(icon_label)


func _update_drown_bar() -> void:
	if not _drown_bar_container:
		return
	var show_bar := _swim_fatigue > 0.0 and current_health > 0.0
	_drown_bar_container.visible = show_bar
	if show_bar:
		var remaining := clampf(1.0 - _swim_fatigue / SWIM_FATIGUE_MAX, 0.0, 1.0)
		_drown_bar_fill.anchor_right = remaining
		var pulse := _swim_fatigue_pulse * 0.3
		_drown_bar_fill.color = Color(
			0.15 + pulse, 0.55 - pulse * 0.3, 0.95 - pulse * 0.5, 0.95)


func _build_inventory_panel(root: Control) -> void:
	# --- Inventory window (top-left) ---
	_inventory_panel = PanelContainer.new()
	_inventory_panel.name = "InventoryPanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	style.border_color = Color(0.4, 0.35, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(16)
	_inventory_panel.add_theme_stylebox_override("panel", style)

	_inventory_panel.anchor_left = 0.0
	_inventory_panel.anchor_right = 0.0
	_inventory_panel.anchor_top = 0.0
	_inventory_panel.anchor_bottom = 0.0
	_inventory_panel.offset_left = 30
	_inventory_panel.offset_top = 30
	_inventory_panel.visible = false
	_inventory_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var inv_vbox := VBoxContainer.new()
	inv_vbox.add_theme_constant_override("separation", 8)

	var inv_title := Label.new()
	inv_title.text = "INVENTORY"
	inv_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	inv_title.add_theme_font_size_override("font_size", 20)
	inv_vbox.add_child(inv_title)

	var inv_sep := HSeparator.new()
	inv_vbox.add_child(inv_sep)

	var inv_scroll := ScrollContainer.new()
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	inv_scroll.custom_minimum_size.y = 4 * 60 + 3 * 4

	_inventory_grid = GridContainer.new()
	_inventory_grid.columns = 8
	_inventory_grid.add_theme_constant_override("h_separation", 4)
	_inventory_grid.add_theme_constant_override("v_separation", 4)
	inv_scroll.add_child(_inventory_grid)
	inv_vbox.add_child(inv_scroll)

	_build_equip_bar(inv_vbox)

	_inventory_panel.add_child(inv_vbox)
	root.add_child(_inventory_panel)

	_build_stats_panel(root)
	_refresh_equip_bar()

	# --- Crafting window (right side, vertically centered) ---
	_crafting_panel = PanelContainer.new()
	_crafting_panel.name = "CraftingPanel"
	var craft_style := StyleBoxFlat.new()
	craft_style.bg_color = Color(0.1, 0.09, 0.14, 0.92)
	craft_style.border_color = Color(0.35, 0.3, 0.2)
	craft_style.set_border_width_all(2)
	craft_style.set_corner_radius_all(6)
	craft_style.set_content_margin_all(14)
	_crafting_panel.add_theme_stylebox_override("panel", craft_style)

	_crafting_panel.anchor_left = 1.0
	_crafting_panel.anchor_right = 1.0
	_crafting_panel.anchor_top = 0.1
	_crafting_panel.anchor_bottom = 0.7
	_crafting_panel.offset_left = -510
	_crafting_panel.offset_right = -200
	_crafting_panel.visible = false
	_crafting_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var craft_vbox := VBoxContainer.new()
	craft_vbox.add_theme_constant_override("separation", 6)

	var title_row := HBoxContainer.new()
	var craft_title := Label.new()
	craft_title.text = "CRAFTING"
	craft_title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	craft_title.add_theme_font_size_override("font_size", 20)
	craft_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(craft_title)

	var info_btn := Button.new()
	info_btn.text = "i"
	info_btn.custom_minimum_size = Vector2(26, 26)
	info_btn.add_theme_font_size_override("font_size", 14)
	info_btn.tooltip_text = "Material Quality Info"
	title_row.add_child(info_btn)
	craft_vbox.add_child(title_row)

	var info_panel := PanelContainer.new()
	info_panel.visible = false
	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	info_style.border_color = Color(0.4, 0.35, 0.25, 0.6)
	info_style.set_border_width_all(1)
	info_style.set_corner_radius_all(4)
	info_style.set_content_margin_all(10)
	info_panel.add_theme_stylebox_override("panel", info_style)

	var info_rtl := RichTextLabel.new()
	info_rtl.bbcode_enabled = true
	info_rtl.fit_content = true
	info_rtl.scroll_active = false
	info_rtl.add_theme_font_size_override("normal_font_size", 11)
	info_rtl.text = "[color=#e6c84a]* Material Quality System[/color]\n\n" \
		+ "[color=#aaaaaa]Items can drop with [/color][color=#ffffff]star ratings (0-5*)[/color][color=#aaaaaa] from monsters and resources. " \
		+ "Higher stars = better quality.[/color]\n\n" \
		+ "[color=#e6c84a]Non-Equipment Crafting[/color]\n" \
		+ "[color=#aaaaaa]Building pieces, tools, arrows, and other non-equipment recipes " \
		+ "only consume [/color][color=#ffffff]unstarred (0*)[/color][color=#aaaaaa] materials. " \
		+ "Your starred materials are kept safe for equipment crafting.[/color]\n\n" \
		+ "[color=#e6c84a]Equipment Crafting[/color]\n" \
		+ "[color=#aaaaaa]Weapons and armor use starred materials based on the quality tier " \
		+ "selected at the workbench. The star quality of ingredients affects the outcome.[/color]"
	info_panel.add_child(info_rtl)
	craft_vbox.add_child(info_panel)
	info_btn.pressed.connect(func(): info_panel.visible = not info_panel.visible)

	var craft_sep := HSeparator.new()
	craft_vbox.add_child(craft_sep)

	var craft_scroll := ScrollContainer.new()
	craft_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	craft_scroll.mouse_filter = Control.MOUSE_FILTER_PASS

	_crafting_grid = VBoxContainer.new()
	_crafting_grid.add_theme_constant_override("separation", 8)
	craft_scroll.add_child(_crafting_grid)
	craft_vbox.add_child(craft_scroll)

	_crafting_panel.add_child(craft_vbox)
	root.add_child(_crafting_panel)


func _build_equip_bar(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.5, 0.42, 0.28, 0.8)
	sep_style.content_margin_top = 4
	sep_style.content_margin_bottom = 4
	sep.add_theme_stylebox_override("separator", sep_style)
	parent.add_child(sep)

	const GHOST_ICONS := {
		"weapon": "res://textures/items/stone_axe.png",
		"sword": "res://textures/items/stone_sword.png",
		"bow": "res://textures/items/crude_bow.png",
		"pickaxe": "res://textures/items/stone_pickaxe.png",
		"torch": "res://textures/items/torch.png",
		"shield": "res://textures/items/wood_shield.png",
		"chest": "res://textures/items/leather_vest.png",
		"legs": "res://textures/items/leather_pants.png",
		"feet": "res://textures/items/leather_boots.png",
	}
	const SLOT_LABELS := {
		"weapon": "Woodaxe",
		"sword": "Melee",
		"bow": "Ranged",
		"pickaxe": "Pick",
		"torch": "Torch",
		"shield": "Shield",
		"chest": "Chest",
		"legs": "Legs",
		"feet": "Boots",
	}
	const TOOL_SLOTS: Array[String] = ["weapon", "pickaxe", "torch"]
	const EQUIP_SLOTS: Array[String] = ["sword", "bow", "shield", "chest", "legs", "feet"]

	var wrapper := PanelContainer.new()
	var wrapper_style := StyleBoxFlat.new()
	wrapper_style.bg_color = Color(0.06, 0.055, 0.04, 0.5)
	wrapper_style.set_corner_radius_all(4)
	wrapper_style.set_content_margin_all(6)
	wrapper.add_theme_stylebox_override("panel", wrapper_style)

	var equip_vbox := VBoxContainer.new()
	equip_vbox.add_theme_constant_override("separation", 4)

	var tools_lbl := Label.new()
	tools_lbl.text = "TOOLS"
	tools_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.4))
	tools_lbl.add_theme_font_size_override("font_size", 11)
	equip_vbox.add_child(tools_lbl)

	var tools_row := HBoxContainer.new()
	tools_row.add_theme_constant_override("separation", 4)
	equip_vbox.add_child(tools_row)

	var equip_spacer := Control.new()
	equip_spacer.custom_minimum_size = Vector2(0, 6)
	equip_vbox.add_child(equip_spacer)

	var equip_lbl := Label.new()
	equip_lbl.text = "EQUIPMENT"
	equip_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.4))
	equip_lbl.add_theme_font_size_override("font_size", 11)
	equip_vbox.add_child(equip_lbl)

	var equip_row := HBoxContainer.new()
	equip_row.add_theme_constant_override("separation", 4)
	equip_vbox.add_child(equip_row)

	var all_slots: Array[String] = []
	all_slots.append_array(TOOL_SLOTS)
	all_slots.append_array(EQUIP_SLOTS)
	for slot_name in all_slots:
		var target_row: HBoxContainer = tools_row if slot_name in TOOL_SLOTS else equip_row

		var slot_col := VBoxContainer.new()
		slot_col.add_theme_constant_override("separation", 2)

		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(60, 60)
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(0.12, 0.11, 0.08, 0.9)
		slot_style.border_color = Color(0.45, 0.38, 0.22)
		slot_style.set_border_width_all(1)
		slot_style.set_corner_radius_all(4)
		slot_style.set_content_margin_all(2)
		slot.add_theme_stylebox_override("panel", slot_style)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP

		var stack := Control.new()
		stack.custom_minimum_size = Vector2(56, 56)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var ghost := TextureRect.new()
		ghost.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ghost.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.modulate = Color(1, 1, 1, 0.25)
		var ghost_path: String = GHOST_ICONS.get(slot_name, "")
		if ghost_path != "" and ResourceLoader.exists(ghost_path):
			ghost.texture = load(ghost_path) as Texture2D
		stack.add_child(ghost)
		_equip_bar_ghost[slot_name] = ghost

		var icon := TextureRect.new()
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.visible = false
		stack.add_child(icon)
		_equip_bar_icons[slot_name] = icon

		slot.add_child(stack)
		slot.gui_input.connect(_on_equip_bar_slot_input.bind(slot_name))
		slot.mouse_entered.connect(_on_equip_bar_hover.bind(slot_name))
		slot.mouse_exited.connect(_hide_tooltip)
		_equip_bar_slots[slot_name] = slot
		slot_col.add_child(slot)

		var lbl := Label.new()
		lbl.text = SLOT_LABELS.get(slot_name, slot_name)
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.55, 0.5, 0.38))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.custom_minimum_size.x = 60
		slot_col.add_child(lbl)

		target_row.add_child(slot_col)

	wrapper.add_child(equip_vbox)
	parent.add_child(wrapper)
	_equip_bar = wrapper


func _refresh_equip_bar() -> void:
	if not _equip_bar:
		return
	const SLOT_ORDER: Array[String] = ["weapon", "sword", "bow", "pickaxe", "torch", "shield", "chest", "legs", "feet"]
	for slot_name in SLOT_ORDER:
		var eq_id: StringName = Inventory.get_equipped(slot_name)
		var icon: TextureRect = _equip_bar_icons.get(slot_name) as TextureRect
		var ghost: TextureRect = _equip_bar_ghost.get(slot_name) as TextureRect
		var slot_panel: PanelContainer = _equip_bar_slots.get(slot_name) as PanelContainer
		if not icon or not ghost or not slot_panel:
			continue

		if eq_id != &"":
			var tex: Texture2D = ItemDatabase.get_icon(eq_id)
			if tex:
				icon.texture = tex
				icon.visible = true
			else:
				icon.visible = false
			ghost.visible = false

			var parsed := ItemDatabase.parse_star_id(eq_id)
			var stars: int = parsed["stars"]
			var eq_data: Dictionary = ItemDatabase.get_item(eq_id)
			var style: StyleBoxFlat = slot_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			if stars > 0:
				style.border_color = ItemDatabase.get_rarity_color(stars)
				style.set_border_width_all(2)
			elif eq_data.has("quality_color"):
				style.border_color = (eq_data["quality_color"] as Color).darkened(0.3)
				style.set_border_width_all(1)
			else:
				style.border_color = Color(0.45, 0.38, 0.22)
				style.set_border_width_all(1)
			slot_panel.add_theme_stylebox_override("panel", style)
		else:
			icon.visible = false
			ghost.visible = true
			var style: StyleBoxFlat = slot_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			style.border_color = Color(0.45, 0.38, 0.22)
			style.set_border_width_all(1)
			slot_panel.add_theme_stylebox_override("panel", style)
	_update_torch_light()


func _update_torch_light() -> void:
	var has_torch := Inventory.get_equipped("torch") != &""
	if has_torch and not _torch_light:
		_torch_light = OmniLight3D.new()
		_torch_light.name = "PlayerTorchLight"
		_torch_light.light_color = Color(1.0, 0.65, 0.25)
		_torch_light.light_energy = 4.0
		_torch_light.omni_range = 48.0
		_torch_light.omni_attenuation = 1.2
		_torch_light.shadow_enabled = true
		_torch_light.position = Vector3(0.0, 1.8, 0.0)
		add_child(_torch_light)
	elif not has_torch and _torch_light:
		_torch_light.queue_free()
		_torch_light = null


func _on_equip_bar_slot_input(event: InputEvent, slot_name: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var eq_id: StringName = Inventory.get_equipped(slot_name)
			if eq_id != &"":
				_unequip_item_deferred.call_deferred(slot_name)


func _try_drop_on_equip_bar() -> bool:
	if _dragging_item == &"" or not _hud_root:
		return false
	var mouse_pos := _hud_root.get_global_mouse_position()
	for slot_name: String in _equip_bar_slots.keys():
		var panel: PanelContainer = _equip_bar_slots[slot_name] as PanelContainer
		if panel and panel.get_global_rect().has_point(mouse_pos):
			var data: Dictionary = ItemDatabase.get_item(_dragging_item)
			var item_type: String = str(data.get("type", ""))
			var item_slot: String = str(data.get("armor_slot", ""))
			if (item_type == "weapon" or item_type == "armor" or item_type == "tool") and item_slot == slot_name:
				Inventory.equip_armor(_dragging_item)
				_refresh_inventory_ui()
				_refresh_equip_bar()
			_cancel_drag()
			return true
	return false


func _on_equip_bar_hover(slot_name: String) -> void:
	var eq_id: StringName = Inventory.get_equipped(slot_name)
	if eq_id != &"":
		_show_tooltip_for_item(eq_id)
	else:
		const SLOT_LABELS := {"weapon": "Woodaxe", "sword": "Melee", "bow": "Ranged", "pickaxe": "Pickaxe", "torch": "Torch", "shield": "Shield", "chest": "Chest Armor", "legs": "Leg Armor", "feet": "Boots"}
		var hint: String = SLOT_LABELS.get(slot_name, slot_name)
		if _tooltip_label and _tooltip_panel:
			_tooltip_label.text = "[color=#888888]Empty %s slot[/color]" % hint
			_tooltip_panel.visible = true


func _build_stats_panel(root: Control) -> void:
	_stats_arrow = Button.new()
	_stats_arrow.name = "StatsArrow"
	_stats_arrow.text = "â–¶"
	_stats_arrow.custom_minimum_size = Vector2(20, 60)
	_stats_arrow.add_theme_font_size_override("font_size", 14)
	_stats_arrow.add_theme_color_override("font_color", Color(0.8, 0.75, 0.55))
	var arrow_style := StyleBoxFlat.new()
	arrow_style.bg_color = Color(0.12, 0.12, 0.16, 0.9)
	arrow_style.border_color = Color(0.4, 0.35, 0.25)
	arrow_style.set_border_width_all(1)
	arrow_style.border_width_left = 0
	arrow_style.set_corner_radius_all(0)
	arrow_style.corner_radius_top_right = 4
	arrow_style.corner_radius_bottom_right = 4
	arrow_style.set_content_margin_all(2)
	_stats_arrow.add_theme_stylebox_override("normal", arrow_style)
	var arrow_hover := arrow_style.duplicate() as StyleBoxFlat
	arrow_hover.bg_color = Color(0.18, 0.18, 0.22, 0.95)
	_stats_arrow.add_theme_stylebox_override("hover", arrow_hover)
	_stats_arrow.add_theme_stylebox_override("pressed", arrow_hover)
	_stats_arrow.visible = false
	_stats_arrow.mouse_filter = Control.MOUSE_FILTER_STOP
	_stats_arrow.pressed.connect(_toggle_stats_panel)
	root.add_child(_stats_arrow)

	_stats_panel = PanelContainer.new()
	_stats_panel.name = "StatsPanel"
	var sp_style := StyleBoxFlat.new()
	sp_style.bg_color = Color(0.08, 0.08, 0.12, 0.92)
	sp_style.border_color = Color(0.4, 0.35, 0.25)
	sp_style.set_border_width_all(2)
	sp_style.border_width_left = 0
	sp_style.set_corner_radius_all(0)
	sp_style.corner_radius_top_right = 6
	sp_style.corner_radius_bottom_right = 6
	sp_style.set_content_margin_all(12)
	_stats_panel.add_theme_stylebox_override("panel", sp_style)
	_stats_panel.visible = false
	_stats_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_stats_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "CHARACTER"
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	title.add_theme_font_size_override("font_size", 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	var stat_keys: Array[String] = [
		"strength", "dexterity", "vitality",
		"_sep1",
		"crit_chance", "crit_damage",
		"_sep2",
		"weapon", "attack_speed", "dps",
		"_sep3",
		"armor",
	]
	var stat_display: Dictionary = {
		"strength": "Strength",
		"dexterity": "Dexterity",
		"vitality": "Vitality",
		"crit_chance": "Crit Chance",
		"crit_damage": "Crit Damage",
		"weapon": "Weapon",
		"attack_speed": "Attack Speed",
		"dps": "DPS",
		"armor": "Armor",
	}

	for key in stat_keys:
		if key.begins_with("_sep"):
			var s2 := HSeparator.new()
			s2.modulate = Color(1, 1, 1, 0.3)
			vbox.add_child(s2)
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var name_lbl := Label.new()
		name_lbl.text = stat_display.get(key, key)
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)

		var val_lbl := Label.new()
		val_lbl.text = "â€”"
		val_lbl.add_theme_font_size_override("font_size", 12)
		val_lbl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.75))
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(val_lbl)
		_stats_labels[key] = val_lbl

		vbox.add_child(row)

	_stats_panel.add_child(vbox)


func _toggle_stats_panel() -> void:
	_stats_open = not _stats_open
	_stats_panel.visible = _stats_open
	_stats_arrow.text = "â—€" if _stats_open else "â–¶"
	if _stats_open:
		_refresh_stats_panel()
	_position_stats_panel()


func _position_stats_panel() -> void:
	if not _inventory_panel or not _stats_arrow:
		return
	var inv_rect := _inventory_panel.get_rect()
	var right_edge := inv_rect.position.x + inv_rect.size.x
	var top := inv_rect.position.y + 40.0

	_stats_arrow.position = Vector2(right_edge, top)
	if _stats_open and _stats_panel:
		_stats_panel.position = Vector2(right_edge + _stats_arrow.size.x, top)


func _refresh_stats_panel() -> void:
	if not _stats_open:
		return

	var str_val := base_strength
	var dex_val := base_dexterity
	var vit_val := base_vitality

	var crit_chance := 5.0 + dex_val * 0.5
	var crit_dmg := 150.0 + str_val * 2.0

	var wpn_data := ItemDatabase.get_item(equipped_weapon)
	var wpn_name: String = wpn_data.get("name", "Fists") as String
	var wpn_damage: float = float(wpn_data.get("damage", 5.0))
	var wpn_speed: float = float(wpn_data.get("attack_speed", 1.0))
	var hits_per_sec := 1.0 / maxf(wpn_speed, 0.1)
	var base_dps := wpn_damage * hits_per_sec
	var effective_dps := base_dps * (1.0 + (crit_chance / 100.0) * ((crit_dmg - 100.0) / 100.0))

	var armor_val := Inventory.get_total_armor()

	if _stats_labels.has("strength"):
		(_stats_labels["strength"] as Label).text = str(str_val)
	if _stats_labels.has("dexterity"):
		(_stats_labels["dexterity"] as Label).text = str(dex_val)
	if _stats_labels.has("vitality"):
		(_stats_labels["vitality"] as Label).text = str(vit_val)
	if _stats_labels.has("crit_chance"):
		(_stats_labels["crit_chance"] as Label).text = "%.1f%%" % crit_chance
	if _stats_labels.has("crit_damage"):
		(_stats_labels["crit_damage"] as Label).text = "%.0f%%" % crit_dmg
	if _stats_labels.has("weapon"):
		(_stats_labels["weapon"] as Label).text = wpn_name
	if _stats_labels.has("attack_speed"):
		(_stats_labels["attack_speed"] as Label).text = "%.2fs" % wpn_speed
	if _stats_labels.has("dps"):
		(_stats_labels["dps"] as Label).text = "%.1f" % effective_dps
		(_stats_labels["dps"] as Label).add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	if _stats_labels.has("armor"):
		(_stats_labels["armor"] as Label).text = "%.0f" % armor_val


func _build_tooltip(root: Control) -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.name = "Tooltip"
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.05, 0.1, 0.95)
	s.border_color = Color(0.5, 0.45, 0.3)
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.set_content_margin_all(10)
	_tooltip_panel.add_theme_stylebox_override("panel", s)
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index = 100

	_tooltip_label = RichTextLabel.new()
	_tooltip_label.bbcode_enabled = true
	_tooltip_label.fit_content = true
	_tooltip_label.scroll_active = false
	_tooltip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tooltip_label.custom_minimum_size = Vector2(180, 0)
	_tooltip_label.add_theme_font_size_override("normal_font_size", 12)
	_tooltip_label.add_theme_color_override("default_color", Color.WHITE)
	_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.add_child(_tooltip_label)
	root.add_child(_tooltip_panel)
	_tooltip_panel.resized.connect(_cap_tooltip_height)


func _cap_tooltip_height() -> void:
	if not _tooltip_panel or not _tooltip_panel.visible:
		return
	var max_h := _hud_root.get_viewport_rect().size.y - 32.0
	if _tooltip_panel.size.y > max_h:
		_tooltip_label.fit_content = false
		_tooltip_label.scroll_active = true
		_tooltip_label.custom_minimum_size.y = max_h - 20.0
		_tooltip_panel.reset_size()
	else:
		_tooltip_label.fit_content = true
		_tooltip_label.scroll_active = false
		_tooltip_label.custom_minimum_size.y = 0


func _build_drag_icon(root: Control) -> void:
	_drag_icon = TextureRect.new()
	_drag_icon.custom_minimum_size = Vector2(32, 32)
	_drag_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_icon.visible = false
	_drag_icon.z_index = 200
	_drag_icon.modulate = Color(1, 1, 1, 0.8)
	root.add_child(_drag_icon)


const BUILD_TABS := ["Misc", "Crafting", "Building", "Heavy Build", "Furniture", "Vehicles"]

const BUILD_RECIPES: Array[Dictionary] = [
	# Misc
	{"id": &"campfire", "name": "Campfire", "tab": "Misc",
	 "cost": [{"item": &"stone", "amount": 5}, {"item": &"wood", "amount": 2}],
	 "mesh": "campfire", "color": Color(0.5, 0.3, 0.15), "size": Vector3(0.6, 0.3, 0.6)},
	{"id": &"torch_post", "name": "Standing Torch", "tab": "Misc",
	 "cost": [{"item": &"wood", "amount": 1}, {"item": &"resin", "amount": 2}],
	 "mesh": "cylinder", "color": Color(0.35, 0.25, 0.1), "size": Vector3(0.15, 1.8, 0.15),
	 "model": "res://models/building/standing_torch.glb"},
	{"id": &"wall_torch", "name": "Wall Torch", "tab": "Misc",
	 "cost": [{"item": &"torch", "amount": 1}],
	 "mesh": "wall_torch", "color": Color(0.35, 0.25, 0.1), "size": Vector3(0.1, 0.6, 0.1),
	 "model": "res://models/building/wall_torch.glb"},
	# Crafting
	{"id": &"workbench", "name": "Workbench", "tab": "Crafting",
	 "cost": [{"item": &"wood", "amount": 10}],
	 "mesh": "workbench", "color": Color(0.45, 0.3, 0.15), "size": Vector3(4.2, 2.7, 2.4)},
	# Building
	{"id": &"wood_wall", "name": "Wood Wall", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "box", "color": Color(0.4, 0.28, 0.12), "size": Vector3(3.6, 5.0, 0.20)},
	{"id": &"wood_floor", "name": "Wood Floor", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "box", "color": Color(0.45, 0.32, 0.15), "size": Vector3(3.6, 0.1, 3.6)},
	{"id": &"wood_stair", "name": "Wood Stairs", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 6}],
	 "mesh": "stair", "color": Color(0.42, 0.3, 0.14), "size": Vector3(3.6, 5.0, 3.6)},
	{"id": &"wood_door", "name": "Wood Door", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 6}],
	 "mesh": "door", "color": Color(0.4, 0.28, 0.12), "size": Vector3(3.6, 5.0, 0.20)},
	# Heavy Build
	{"id": &"stone_wall", "name": "Stone Wall", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 6}],
	 "mesh": "box", "color": Color(0.4, 0.4, 0.42), "size": Vector3(3.6, 5.0, 0.20)},
	{"id": &"stone_floor", "name": "Stone Floor", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 6}],
	 "mesh": "box", "color": Color(0.45, 0.45, 0.47), "size": Vector3(3.6, 0.1, 3.6)},
	{"id": &"stone_door", "name": "Stone Door", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 8}],
	 "mesh": "door", "color": Color(0.4, 0.4, 0.42), "size": Vector3(3.6, 5.0, 0.20)},
	# Roofing â€“ Building tab (wood)
	{"id": &"thatch_roof_45", "name": "Thatch Roof 45\u00b0", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 6}],
	 "mesh": "roof_45", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 2.0, 2.0),
	 "model": "res://models/building/thatch_roof_45.glb"},
	{"id": &"thatch_roof_26", "name": "Thatch Roof 26\u00b0", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "roof_26", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 1.0, 2.0),
	 "model": "res://models/building/thatch_roof_26.glb"},
	{"id": &"thatch_roof_45_ocorner", "name": "Thatch Outer Corner 45\u00b0", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 6}],
	 "mesh": "roof_45_ocorner", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 2.0, 2.0)},
	{"id": &"thatch_roof_26_ocorner", "name": "Thatch Outer Corner 26\u00b0", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "roof_26_ocorner", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 1.0, 2.0)},
	{"id": &"thatch_roof_45_icorner", "name": "Thatch Inner Corner 45\u00b0", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 6}],
	 "mesh": "roof_45_icorner", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 2.0, 2.0)},
	{"id": &"thatch_roof_26_icorner", "name": "Thatch Inner Corner 26\u00b0", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 4}],
	 "mesh": "roof_26_icorner", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 1.0, 2.0)},
	{"id": &"thatch_roof_ridge", "name": "Thatch Ridge Cap", "tab": "Building",
	 "cost": [{"item": &"wood", "amount": 2}],
	 "mesh": "roof_ridge", "color": Color(0.55, 0.45, 0.25), "size": Vector3(2.0, 0.15, 0.4)},
	# Roofing â€“ Heavy Build tab (stone)
	{"id": &"slate_roof_45", "name": "Slate Roof 45\u00b0", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 6}],
	 "mesh": "roof_45", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 2.0, 2.0)},
	{"id": &"slate_roof_26", "name": "Slate Roof 26\u00b0", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 4}],
	 "mesh": "roof_26", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 1.0, 2.0)},
	{"id": &"slate_roof_45_ocorner", "name": "Slate Outer Corner 45\u00b0", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 6}],
	 "mesh": "roof_45_ocorner", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 2.0, 2.0)},
	{"id": &"slate_roof_26_ocorner", "name": "Slate Outer Corner 26\u00b0", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 4}],
	 "mesh": "roof_26_ocorner", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 1.0, 2.0)},
	{"id": &"slate_roof_45_icorner", "name": "Slate Inner Corner 45\u00b0", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 6}],
	 "mesh": "roof_45_icorner", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 2.0, 2.0)},
	{"id": &"slate_roof_26_icorner", "name": "Slate Inner Corner 26\u00b0", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 4}],
	 "mesh": "roof_26_icorner", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 1.0, 2.0)},
	{"id": &"slate_roof_ridge", "name": "Slate Ridge Cap", "tab": "Heavy Build",
	 "cost": [{"item": &"stone", "amount": 2}],
	 "mesh": "roof_ridge", "color": Color(0.35, 0.35, 0.4), "size": Vector3(2.0, 0.15, 0.4)},
	# Furniture
	{"id": &"chest", "name": "Chest", "tab": "Furniture",
	 "cost": [{"item": &"wood", "amount": 10}],
	 "mesh": "box", "color": Color(0.5, 0.35, 0.15), "size": Vector3(2.4, 1.8, 1.5)},
	{"id": &"bed", "name": "Bed", "tab": "Furniture",
	 "cost": [{"item": &"wood", "amount": 8}, {"item": &"leather", "amount": 4}],
	 "mesh": "bed", "color": Color(0.5, 0.3, 0.2), "size": Vector3(1.2, 0.6, 2.2)},
	# Vehicles
	{"id": &"raft", "name": "Raft", "tab": "Vehicles",
	 "cost": [{"item": &"wood", "amount": 20}],
	 "mesh": "raft", "color": Color(0.45, 0.32, 0.18), "size": Vector3(3.0, 0.2, 4.0),
	 "water_only": true},
]

var _build_tab_buttons: Array[Button] = []
var _build_current_tab := "Misc"


func _build_build_menu(root: Control) -> void:
	_build_menu_panel = PanelContainer.new()
	_build_menu_panel.name = "BuildMenu"
	_build_menu_panel.visible = false
	_build_menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	_build_menu_panel.position = Vector2(-220, -180)
	_build_menu_panel.custom_minimum_size = Vector2(440, 360)
	_build_menu_panel.z_index = 90

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.06, 0.1, 0.95)
	bg.border_color = Color(0.6, 0.45, 0.2)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(14)
	_build_menu_panel.add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 4)
	_build_tab_buttons.clear()
	for tab_name: String in BUILD_TABS:
		var tb := Button.new()
		tb.text = tab_name
		tb.add_theme_font_size_override("font_size", 11)
		tb.custom_minimum_size = Vector2(0, 28)
		tb.pressed.connect(_on_build_tab_pressed.bind(tab_name))
		tab_bar.add_child(tb)
		_build_tab_buttons.append(tb)
	vbox.add_child(tab_bar)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(410, 280)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_menu_grid = GridContainer.new()
	_build_menu_grid.columns = 1
	_build_menu_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_build_menu_grid)
	vbox.add_child(scroll)

	_build_menu_panel.add_child(vbox)
	root.add_child(_build_menu_panel)


func _on_build_tab_pressed(tab_name: String) -> void:
	_build_current_tab = tab_name
	_refresh_build_menu()


func _refresh_build_menu() -> void:
	if not _build_menu_grid:
		return
	for c in _build_menu_grid.get_children():
		_build_menu_grid.remove_child(c)
		c.free()

	for i in range(_build_tab_buttons.size()):
		var tb: Button = _build_tab_buttons[i]
		var active: bool = (BUILD_TABS[i] as String) == _build_current_tab
		tb.modulate = Color(1.0, 0.85, 0.5) if active else Color(0.6, 0.6, 0.6)

	for recipe: Dictionary in BUILD_RECIPES:
		if recipe.get("tab", "Misc") as String != _build_current_tab:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var rid_icon: StringName = recipe["id"] as StringName
		var icon_tex := _get_build_icon(rid_icon)
		if icon_tex:
			var tex_rect := TextureRect.new()
			tex_rect.texture = icon_tex
			tex_rect.custom_minimum_size = Vector2(36, 36)
			tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(tex_rect)

		var info_vb := VBoxContainer.new()
		info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vb.add_theme_constant_override("separation", 1)

		var name_lbl := Label.new()
		name_lbl.text = recipe["name"] as String
		name_lbl.add_theme_font_size_override("font_size", 13)

		var cost_text := ""
		var can_afford := true
		for mat: Dictionary in (recipe["cost"] as Array):
			var mat_id: StringName = mat["item"] as StringName
			var mat_amt: int = int(mat["amount"])
			var have: int = Inventory.get_amount_any_star(mat_id)
			var mat_name: String = (ItemDatabase.get_item(mat_id) as Dictionary).get("name", str(mat_id)) as String
			if have < mat_amt and not Inventory.has_free_craft():
				can_afford = false
			var have_color := "aaffaa" if (have >= mat_amt or Inventory.has_free_craft()) else "ff6666"
			if cost_text != "":
				cost_text += "  "
			cost_text += "[color=#%s]%s %d/%d[/color]" % [have_color, mat_name, have, mat_amt]

		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7) if can_afford else Color(0.5, 0.45, 0.4))
		info_vb.add_child(name_lbl)

		var cost_lbl := RichTextLabel.new()
		cost_lbl.bbcode_enabled = true
		cost_lbl.text = cost_text
		cost_lbl.fit_content = true
		cost_lbl.scroll_active = false
		cost_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		cost_lbl.custom_minimum_size.y = 16
		cost_lbl.add_theme_font_size_override("normal_font_size", 10)
		info_vb.add_child(cost_lbl)

		row.add_child(info_vb)

		var btn := Button.new()
		btn.text = "Build"
		btn.disabled = not can_afford
		btn.custom_minimum_size = Vector2(60, 30)
		var rid: StringName = recipe["id"] as StringName
		btn.pressed.connect(_on_build_item_selected.bind(rid))
		row.add_child(btn)

		_build_menu_grid.add_child(row)


func _toggle_build_menu() -> void:
	if _build_mode:
		_cancel_build_mode()
		return
	_build_menu_open = not _build_menu_open
	if _build_menu_open:
		_refresh_build_menu()
		_build_menu_panel.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_build_menu_panel.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _close_build_menu() -> void:
	_build_menu_open = false
	if _build_menu_panel:
		_build_menu_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_build_item_selected(build_id: StringName) -> void:
	_build_selected = build_id
	_close_build_menu()
	_enter_build_mode()


func _enter_raft_placement() -> void:
	_build_selected = &"raft"
	_build_from_workbench = true
	_enter_build_mode()


func _enter_build_mode() -> void:
	_build_mode = true
	_build_rotation = 0.0
	_build_snapped = false
	_build_snap_side = 0
	_build_height_offset = 0.0
	var recipe := _get_build_recipe(_build_selected)
	if recipe.is_empty():
		_build_mode = false
		return
	var mesh_type: String = recipe.get("mesh", "box") as String
	var color: Color = recipe.get("color", Color(0.5, 0.4, 0.2)) as Color
	var sz: Vector3 = recipe.get("size", Vector3(1, 1, 1)) as Vector3
	var build_id: StringName = recipe.get("id", &"") as StringName

	_build_ghost = Node3D.new()
	var ghost_mat := _make_ghost_material(build_id, color)
	var model_path: String = recipe.get("model", "") as String
	var used_glb := false
	if not model_path.is_empty():
		used_glb = _add_building_glb(_build_ghost, model_path, sz, ghost_mat)
	if not used_glb:
		var mi := MeshInstance3D.new()
		var mesh: Mesh
		if mesh_type in ["roof_45", "roof_26"]:
			mesh = _build_roof_mesh(sz, sz.y)
		elif mesh_type in ["roof_45_ocorner", "roof_26_ocorner"]:
			mesh = _build_roof_ocorner_mesh(sz, sz.y)
		elif mesh_type in ["roof_45_icorner", "roof_26_icorner"]:
			mesh = _build_roof_icorner_mesh(sz, sz.y)
		elif mesh_type == "roof_ridge":
			mesh = _build_roof_ridge_mesh(sz)
		elif mesh_type == "stair":
			mesh = _build_stair_mesh(sz)
		elif mesh_type == "cylinder":
			var cyl := CylinderMesh.new()
			cyl.top_radius = sz.x * 0.5
			cyl.bottom_radius = sz.x * 0.5
			cyl.height = sz.y
			mesh = cyl
		else:
			var bx := BoxMesh.new()
			bx.size = sz
			mesh = bx
		mi.mesh = mesh
		mi.set_surface_override_material(0, ghost_mat)
		if mesh_type.begins_with("roof"):
			mi.position.y = 0.0
		else:
			mi.position.y = 0.0 if mesh_type == "stair" else sz.y * 0.5
		_build_ghost.add_child(mi)
	get_tree().current_scene.add_child(_build_ghost)

	if _snap_label:
		_snap_label.visible = true
		_snap_label.text = "Snap: ON" if _build_snap_enabled else "Snap: OFF"
		_snap_label.add_theme_color_override("font_color",
			Color(0.6, 1.0, 0.6) if _build_snap_enabled else Color(1.0, 0.5, 0.5))
	if _build_crosshair:
		_build_crosshair.visible = true


func _update_build_ghost() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return

	var recipe := _get_build_recipe(_build_selected)
	var is_water_only := recipe.get("water_only", false) as bool

	# Raycast from camera through screen center into the world
	var vp := get_viewport()
	var screen_center := vp.get_visible_rect().size * 0.5
	var ray_origin := cam.project_ray_origin(screen_center)
	var ray_dir := cam.project_ray_normal(screen_center)

	var place_pos := global_position + (-cam.global_transform.basis.z * Vector3(1, 0, 1)).normalized() * 3.5
	place_pos.y = global_position.y

	var result_hit_node: Node3D = null
	var space := get_world_3d().direct_space_state
	if space:
		var ray_end := ray_origin + ray_dir * 50.0
		var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 1)
		query.exclude = [get_rid()]
		var result := space.intersect_ray(query)
		if not result.is_empty():
			var hit_pos: Vector3 = result["position"]
			var dist_to_player := Vector2(hit_pos.x - global_position.x, hit_pos.z - global_position.z).length()
			if dist_to_player <= BUILD_MAX_DISTANCE:
				place_pos = hit_pos
				var collider: Node = result.get("collider") as Node
				if collider:
					var p: Node = collider.get_parent()
					if p is Node3D and (p as Node3D).is_in_group(&"structures"):
						result_hit_node = p as Node3D
					elif collider is Node3D and (collider as Node3D).is_in_group(&"structures"):
						result_hit_node = collider as Node3D

	if is_water_only:
		var water_y := WaterSystem.get_surface_y(place_pos.x, place_pos.z)
		place_pos.y = water_y
		var terrain_y := place_pos.y - 10.0
		if space:
			var wray_from := Vector3(place_pos.x, water_y + 50.0, place_pos.z)
			var wray_to := Vector3(place_pos.x, water_y - 50.0, place_pos.z)
			var wquery := PhysicsRayQueryParameters3D.create(wray_from, wray_to, 1)
			wquery.exclude = [get_rid()]
			var wresult := space.intersect_ray(wquery)
			if not wresult.is_empty():
				terrain_y = wresult["position"].y
		if terrain_y > water_y - 0.1:
			_build_ghost.global_position = place_pos
			_build_ghost.rotation.y = _build_rotation
			var mi := _build_ghost.get_child(0) as MeshInstance3D
			if mi:
				var mat := mi.get_surface_override_material(0) as StandardMaterial3D
				if mat:
					mat.albedo_color = Color(0.9, 0.2, 0.2, 0.4)
			return
	else:
		var bid: StringName = recipe.get("id", &"") as StringName
		if bid in [&"wood_floor", &"stone_floor"]:
			place_pos.y -= 0.05

	place_pos.y += _build_height_offset

	var use_rot := _build_rotation
	_build_snapped = false

	if _build_snap_enabled and not is_water_only:
		if not recipe.is_empty():
			var bid: StringName = recipe.get("id", &"") as StringName
			var sz: Vector3 = recipe.get("size", Vector3.ONE) as Vector3
			if result_hit_node and is_instance_valid(result_hit_node):
				# Side-based snap: offset from focused structure's center by its half-size + ghost half-size
				var exist_id: StringName = result_hit_node.get_meta("build_id", &"") as StringName
				var exist_recipe := _get_build_recipe(exist_id)
				var exist_sz: Vector3 = exist_recipe.get("size", Vector3.ONE) as Vector3 if not exist_recipe.is_empty() else Vector3.ONE
				var exist_basis := Basis(Vector3.UP, result_hit_node.rotation.y)
				const SIDE_DIRS := [Vector3(0,0,-1), Vector3(0,0,1), Vector3(-1,0,0), Vector3(1,0,0), Vector3(0,1,0), Vector3(0,-1,0)]
				const SIDE_HALF_EXIST := [Vector3(0,0,1), Vector3(0,0,1), Vector3(1,0,0), Vector3(1,0,0), Vector3(0,1,0), Vector3(0,1,0)]
				const SIDE_HALF_NEW := [Vector3(0,0,1), Vector3(0,0,1), Vector3(1,0,0), Vector3(1,0,0), Vector3(0,1,0), Vector3(0,1,0)]
				var side_dir: Vector3 = exist_basis * SIDE_DIRS[_build_snap_side]
				var exist_half: float = (exist_sz * SIDE_HALF_EXIST[_build_snap_side]).length() * 0.5
				var new_half: float = (sz * SIDE_HALF_NEW[_build_snap_side]).length() * 0.5
				place_pos = result_hit_node.global_position + side_dir * (exist_half + new_half)
				use_rot = result_hit_node.rotation.y + _build_rotation
				_build_snapped = true
				if _build_snap_side_label:
					_build_snap_side_label.visible = true
					_update_snap_side_label()
			else:
				if _build_snap_side_label:
					_build_snap_side_label.visible = false
				var snap := _find_best_snap(place_pos, _build_rotation, bid, sz, null)
				if not snap.is_empty():
					place_pos = snap["pos"] as Vector3
					use_rot = snap["rot_y"] as float
					_build_snapped = true

	_build_ghost.global_position = place_pos
	_build_ghost.rotation.y = use_rot
	_update_ghost_snap_color(_build_snapped)


func _place_build() -> void:
	var recipe := _get_build_recipe(_build_selected)
	if recipe.is_empty():
		_cancel_build_mode()
		return

	var is_water_only := recipe.get("water_only", false) as bool
	if is_water_only:
		var ghost_pos := _build_ghost.global_position
		var water_y := WaterSystem.get_surface_y(ghost_pos.x, ghost_pos.z)
		var space := get_world_3d().direct_space_state
		var terrain_y := water_y - 20.0
		if space:
			var ray_from := Vector3(ghost_pos.x, water_y + 50.0, ghost_pos.z)
			var ray_to := Vector3(ghost_pos.x, water_y - 50.0, ghost_pos.z)
			var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to, 1)
			query.exclude = [get_rid()]
			var result := space.intersect_ray(query)
			if not result.is_empty():
				terrain_y = result["position"].y
		if terrain_y > water_y - 0.1:
			return

	if not _build_from_workbench and not Inventory.has_free_craft():
		var costs: Array = recipe.get("cost", []) as Array
		for mat: Dictionary in costs:
			var mat_id: StringName = mat["item"] as StringName
			var mat_amt: int = int(mat["amount"])
			if not Inventory.has_item_any_star(mat_id, mat_amt):
				return
		for mat: Dictionary in costs:
			Inventory.remove_item_any_star(mat["item"] as StringName, int(mat["amount"]))
	_build_from_workbench = false

	var build_id: StringName = recipe.get("id", &"") as StringName
	var sz: Vector3 = recipe.get("size", Vector3(1, 1, 1)) as Vector3
	var color: Color = recipe.get("color", Color(0.5, 0.4, 0.2)) as Color
	var mesh_type: String = recipe.get("mesh", "box") as String

	if build_id == &"raft":
		_interaction.spawn_raft(_build_ghost.global_position, _build_ghost.rotation.y)
		AudioManager.play_sfx_at("wood_thud", _build_ghost.global_position, -2.0, 0.2)
		return

	var structure := StaticBody3D.new()
	var _deferred_campfire := mesh_type == "campfire"
	var _is_workbench := mesh_type == "workbench"
	var _is_chest := build_id == &"chest"
	var _is_wall_torch := mesh_type == "wall_torch"
	var _is_bed := mesh_type == "bed"
	var _is_door := mesh_type == "door"

	structure.add_to_group(&"structures")
	structure.set_meta("build_id", build_id)

	var model_path: String = recipe.get("model", "") as String
	var _used_glb := false
	if not model_path.is_empty():
		_used_glb = _add_building_glb(structure, model_path, sz, null, color)

	if not _used_glb:
		if _is_workbench:
			_build_workbench_visual(structure, sz, color)
		elif _is_chest:
			_build_chest_visual(structure, sz)
		elif _is_wall_torch:
			_build_wall_torch_visual(structure)
		elif _is_bed:
			_build_bed_visual(structure, sz)
		elif _is_door:
			_build_door_visual(structure, sz, build_id)

	if _is_workbench:
		structure.add_to_group(&"workbenches")
	elif _is_chest:
		structure.add_to_group(&"chests")
	elif _is_door:
		structure.add_to_group(&"doors")
		structure.set_meta("door_open", false)

	var _is_roof := mesh_type.begins_with("roof")

	if not _used_glb:
		if _deferred_campfire:
			pass
		elif not _is_workbench and not _is_chest and not _is_wall_torch and not _is_bed and not _is_door:
			var mi := MeshInstance3D.new()
			var mesh: Mesh
			if mesh_type in ["roof_45", "roof_26"]:
				mesh = _build_roof_mesh(sz, sz.y)
			elif mesh_type in ["roof_45_ocorner", "roof_26_ocorner"]:
				mesh = _build_roof_ocorner_mesh(sz, sz.y)
			elif mesh_type in ["roof_45_icorner", "roof_26_icorner"]:
				mesh = _build_roof_icorner_mesh(sz, sz.y)
			elif mesh_type == "roof_ridge":
				mesh = _build_roof_ridge_mesh(sz)
			elif mesh_type == "stair":
				mesh = _build_stair_mesh(sz)
			elif mesh_type == "cylinder":
				var cyl := CylinderMesh.new()
				cyl.top_radius = sz.x * 0.5
				cyl.bottom_radius = sz.x * 0.5
				cyl.height = sz.y
				mesh = cyl
			else:
				var bx := BoxMesh.new()
				bx.size = sz
				mesh = bx
			mi.mesh = mesh
			var bmat := _get_building_material(build_id)
			if bmat:
				mi.set_surface_override_material(0, bmat)
			else:
				var mat := StandardMaterial3D.new()
				mat.albedo_color = color
				mat.roughness = 0.85
				mi.set_surface_override_material(0, mat)
			if _is_roof:
				mi.position.y = 0.0
			else:
				mi.position.y = 0.0 if mesh_type == "stair" else sz.y * 0.5
			structure.add_child(mi)

	var _is_stair := mesh_type == "stair"
	if _is_stair:
		_add_stair_collision(structure, sz)
	elif _is_door:
		pass
	else:
		var col_shape := CollisionShape3D.new()
		var col: Shape3D
		if mesh_type == "cylinder" or mesh_type == "campfire":
			var cyl_col := CylinderShape3D.new()
			cyl_col.radius = sz.x * 0.5
			cyl_col.height = sz.y
			col = cyl_col
		elif _is_wall_torch:
			var box_col := BoxShape3D.new()
			box_col.size = Vector3(0.2, 0.6, 0.2)
			col = box_col
		elif _is_roof:
			var box_col := BoxShape3D.new()
			box_col.size = Vector3(sz.x, sz.y * 0.5, sz.z)
			col = box_col
			col_shape.position.y = sz.y * 0.25
		else:
			var box_col := BoxShape3D.new()
			box_col.size = sz
			col = box_col
		col_shape.shape = col
		if not _is_roof:
			col_shape.position.y = sz.y * 0.5
		structure.add_child(col_shape)

	var target_pos := _build_ghost.global_position
	var target_rot := _build_ghost.rotation.y
	get_tree().current_scene.add_child(structure)
	structure.global_position = target_pos
	structure.rotation.y = target_rot

	var snap_pts := _get_snap_points_for(build_id, sz)
	if not snap_pts.is_empty():
		structure.set_meta("snap_points", snap_pts)

	if _deferred_campfire:
		_build_campfire_visual(structure, sz)
	else:
		_setup_structure_distance_cull(structure)

	if build_id == &"torch_post":
		_add_torch_light(structure, Vector3(0.0, sz.y + 0.1, 0.0))

	_disable_structure_shadows(structure)
	AudioManager.play_sfx_at("wood_thud", structure.global_position, -4.0, 0.2)

	# Network sync: broadcast building placement to other clients
	var wss := _get_world_state_sync()
	if wss and NetworkManager.is_connected_to_game():
		var chest_contents: Array = []
		if build_id == &"chest" and structure.has_meta("chest_contents"):
			chest_contents = structure.get_meta("chest_contents", [])
		var bld_wg := _find_world_generator()
		var bld_wp := target_pos
		if bld_wg:
			bld_wp = bld_wg.get_world_position_vec(target_pos)
		var entry := {
			"build_id": str(build_id),
			"px": bld_wp.x,
			"py": bld_wp.y,
			"pz": bld_wp.z,
			"ry": target_rot,
			"chest_contents": chest_contents,
		}
		if NetworkManager.is_server():
			wss.record_building_placed(build_id, bld_wp, target_rot, chest_contents)
		else:
			wss.request_building_placed.rpc_id(1, entry)


func rebuild_structure(build_id_str: String, pos: Vector3, rot_y: float) -> void:
	var build_id := StringName(build_id_str)
	var recipe: Dictionary = {}
	for r: Dictionary in BUILD_RECIPES:
		if r.get("id", &"") == build_id:
			recipe = r
			break
	if recipe.is_empty():
		return

	var sz: Vector3 = recipe.get("size", Vector3(1, 1, 1)) as Vector3
	var color: Color = recipe.get("color", Color(0.5, 0.4, 0.2)) as Color
	var mesh_type: String = recipe.get("mesh", "box") as String

	var structure := StaticBody3D.new()
	var is_campfire := mesh_type == "campfire"
	var is_workbench := mesh_type == "workbench"
	var is_chest := build_id == &"chest"
	var is_wall_torch := mesh_type == "wall_torch"
	var is_bed := mesh_type == "bed"
	var is_door := mesh_type == "door"

	structure.add_to_group(&"structures")
	structure.set_meta("build_id", build_id)

	var is_roof := mesh_type.begins_with("roof")

	var rb_model_path: String = recipe.get("model", "") as String
	var rb_used_glb := false
	if not rb_model_path.is_empty():
		rb_used_glb = _add_building_glb(structure, rb_model_path, sz, null, color)

	if not rb_used_glb:
		if is_workbench:
			_build_workbench_visual(structure, sz, color)
		elif is_chest:
			_build_chest_visual(structure, sz)
		elif is_wall_torch:
			_build_wall_torch_visual(structure)
		elif is_bed:
			_build_bed_visual(structure, sz)
		elif is_door:
			_build_door_visual(structure, sz, build_id)
		elif not is_campfire:
			var mi := MeshInstance3D.new()
			var mesh: Mesh
			if mesh_type in ["roof_45", "roof_26"]:
				mesh = _build_roof_mesh(sz, sz.y)
			elif mesh_type in ["roof_45_ocorner", "roof_26_ocorner"]:
				mesh = _build_roof_ocorner_mesh(sz, sz.y)
			elif mesh_type in ["roof_45_icorner", "roof_26_icorner"]:
				mesh = _build_roof_icorner_mesh(sz, sz.y)
			elif mesh_type == "roof_ridge":
				mesh = _build_roof_ridge_mesh(sz)
			elif mesh_type == "stair":
				mesh = _build_stair_mesh(sz)
			elif mesh_type == "cylinder":
				var cyl := CylinderMesh.new()
				cyl.top_radius = sz.x * 0.5
				cyl.bottom_radius = sz.x * 0.5
				cyl.height = sz.y
				mesh = cyl
			else:
				var bx := BoxMesh.new()
				bx.size = sz
				mesh = bx
			mi.mesh = mesh
			var bmat := _get_building_material(build_id)
			if bmat:
				mi.set_surface_override_material(0, bmat)
			else:
				var mat := StandardMaterial3D.new()
				mat.albedo_color = color
				mat.roughness = 0.85
				mi.set_surface_override_material(0, mat)
			if is_roof:
				mi.position.y = 0.0
			else:
				mi.position.y = 0.0 if mesh_type == "stair" else sz.y * 0.5
			structure.add_child(mi)

	if is_workbench:
		structure.add_to_group(&"workbenches")
	elif is_chest:
		structure.add_to_group(&"chests")
	elif is_door:
		structure.add_to_group(&"doors")
		structure.set_meta("door_open", false)

	var is_stair := mesh_type == "stair"
	if is_stair:
		_add_stair_collision(structure, sz)
	elif is_door:
		pass
	else:
		var col_shape := CollisionShape3D.new()
		var col: Shape3D
		if mesh_type == "cylinder" or mesh_type == "campfire":
			var cyl_col := CylinderShape3D.new()
			cyl_col.radius = sz.x * 0.5
			cyl_col.height = sz.y
			col = cyl_col
		elif is_wall_torch:
			var box_col := BoxShape3D.new()
			box_col.size = Vector3(0.2, 0.6, 0.2)
			col = box_col
		elif is_roof:
			var box_col := BoxShape3D.new()
			box_col.size = Vector3(sz.x, sz.y * 0.5, sz.z)
			col = box_col
			col_shape.position.y = sz.y * 0.25
		else:
			var box_col := BoxShape3D.new()
			box_col.size = sz
			col = box_col
		col_shape.shape = col
		if not is_roof:
			col_shape.position.y = sz.y * 0.5
		structure.add_child(col_shape)

	get_tree().current_scene.add_child(structure)
	structure.global_position = pos
	structure.rotation.y = rot_y

	_clear_vegetation_at(pos, sz)

	var snap_pts := _get_snap_points_for(build_id, sz)
	if not snap_pts.is_empty():
		structure.set_meta("snap_points", snap_pts)

	if is_campfire:
		_build_campfire_visual(structure, sz)
	else:
		_setup_structure_distance_cull(structure)

	if build_id == &"torch_post":
		_add_torch_light(structure, Vector3(0.0, sz.y + 0.1, 0.0))

	_disable_structure_shadows(structure)


func _clear_vegetation_at(pos: Vector3, sz: Vector3) -> void:
	var radius := maxf(sz.x, sz.z) * 0.55
	var r2 := radius * radius

	for node: Node3D in get_tree().get_nodes_in_group(&"interactables"):
		if not is_instance_valid(node):
			continue
		var dx := node.global_position.x - pos.x
		var dz := node.global_position.z - pos.z
		if dx * dx + dz * dz < r2:
			node.queue_free()

	_clear_grass_multimesh_at(pos, r2)


func _clear_grass_multimesh_at(pos: Vector3, r2: float) -> void:
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	for zone in scene_root.get_children():
		if not zone is Node3D:
			continue
		var zone_origin := (zone as Node3D).global_position
		for child in zone.get_children():
			var mmi := child as MultiMeshInstance3D
			if not mmi or not mmi.name.begins_with("Grass_"):
				continue
			var mm := mmi.multimesh
			if not mm or mm.instance_count == 0:
				continue
			var kept: Array[Transform3D] = []
			for i in mm.instance_count:
				var t := mm.get_instance_transform(i)
				var wx := zone_origin.x + t.origin.x
				var wz := zone_origin.z + t.origin.z
				var dx := wx - pos.x
				var dz := wz - pos.z
				if dx * dx + dz * dz >= r2:
					kept.append(t)
			if kept.size() == mm.instance_count:
				continue
			if kept.is_empty():
				mmi.queue_free()
			else:
				mm.instance_count = kept.size()
				for idx in kept.size():
					mm.set_instance_transform(idx, kept[idx])


func _cancel_build_mode() -> void:
	if _build_from_workbench and _build_selected != &"":
		var item_data := ItemDatabase.get_item(_build_selected)
		var recipe_var = item_data.get("recipe", [])
		var recipe: Array = recipe_var if recipe_var is Array else []
		for ingredient in recipe:
			if not ingredient is Dictionary:
				continue
			var req_id: StringName = StringName(str(ingredient.get("item_id", "")))
			var req_amount: int = int(ingredient.get("amount", 0))
			Inventory.add_item(req_id, req_amount)
	_build_from_workbench = false
	_build_mode = false
	_build_selected = &""
	_build_snapped = false
	if _build_ghost:
		_build_ghost.queue_free()
		_build_ghost = null
	if _snap_label:
		_snap_label.visible = false
	if _build_snap_side_label:
		_build_snap_side_label.visible = false
	if _build_crosshair:
		_build_crosshair.visible = false


func _try_salvage_structure() -> void:
	var cam: Camera3D = _spring_arm.get_child(0) if _spring_arm.get_child_count() > 0 else null
	if not cam:
		return
	var from := cam.global_position
	var forward := -cam.global_transform.basis.z
	var to := from + forward * 5.0

	var best_node: Node3D = null
	var best_dist := INF

	for node in get_tree().get_nodes_in_group(&"structures"):
		var s3d := node as Node3D
		if not s3d or not is_instance_valid(s3d):
			continue
		var dist := s3d.global_position.distance_to(global_position)
		if dist > 5.0:
			continue
		var to_struct := (s3d.global_position - from)
		to_struct.y = 0.0
		var fwd_flat := Vector3(forward.x, 0.0, forward.z).normalized()
		if to_struct.normalized().dot(fwd_flat) < 0.3:
			continue
		if dist < best_dist:
			best_dist = dist
			best_node = s3d

	if not best_node:
		return

	var build_id: StringName = best_node.get_meta("build_id", &"") as StringName
	if build_id == &"":
		return

	var recipe := _get_build_recipe(build_id)
	var costs: Array = recipe.get("cost", []) as Array
	for mat: Dictionary in costs:
		var mat_id: StringName = mat.get("item", &"") as StringName
		var mat_amt: int = int(mat.get("amount", 0))
		var refund := maxi(ceili(mat_amt * 0.5), 1)
		Inventory.add_item(mat_id, refund)

	AudioManager.play_sfx_at("wood_thud", best_node.global_position, -2.0, 0.15)

	var msg := DamageNumber.new()
	msg.text = "Salvaged"
	msg.font_size = 18
	msg.pixel_size = 0.008
	msg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	msg.no_depth_test = true
	msg.modulate = Color(1.0, 0.85, 0.4)
	msg.outline_modulate = Color.BLACK
	msg.outline_size = 5
	msg._velocity = Vector3(0, 1.5, 0)
	get_tree().current_scene.add_child(msg)
	msg.global_position = best_node.global_position + Vector3(0, 1.5, 0)

	best_node.queue_free()


func _get_build_recipe(build_id: StringName) -> Dictionary:
	for recipe: Dictionary in BUILD_RECIPES:
		if recipe["id"] as StringName == build_id:
			return recipe
	return {}


# â”€â”€ Building material cache â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
static var _bmat_wood: StandardMaterial3D
static var _bmat_stone: StandardMaterial3D
static var _bmat_thatch: StandardMaterial3D
static var _bmat_slate: StandardMaterial3D

static func _ensure_building_materials() -> void:
	if _bmat_wood != null:
		return
	_bmat_wood = _load_building_mat("res://textures/building/wood_planks.png",
		Color(0.50, 0.38, 0.22), 0.80, Vector3(4.0, 4.0, 1.0))
	_bmat_stone = _load_building_mat("res://textures/building/cobblestone.png",
		Color(0.70, 0.70, 0.73), 0.92, Vector3(4.0, 4.0, 1.0))
	_bmat_thatch = _load_building_mat("res://textures/building/thatch.png",
		Color(0.60, 0.50, 0.30), 0.85, Vector3(2.0, 2.0, 1.0))
	_bmat_slate = _load_building_mat("res://textures/building/slate_roof.png",
		Color(0.50, 0.50, 0.55), 0.90, Vector3(2.0, 2.0, 1.0))

static func _load_building_mat(path: String, tint: Color, rough: float, uv_scale: Vector3) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tex := load(path) as Texture2D
	if tex:
		mat.albedo_texture = tex
		mat.albedo_color = tint
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	else:
		mat.albedo_color = tint
	mat.roughness = rough
	mat.uv1_scale = uv_scale
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _get_building_material(build_id: StringName) -> StandardMaterial3D:
	_ensure_building_materials()
	if build_id in [&"wood_wall", &"wood_floor", &"wood_stair", &"wood_door"]:
		return _bmat_wood
	elif build_id in [&"stone_wall", &"stone_floor", &"stone_door"]:
		return _bmat_stone
	elif build_id.begins_with(&"thatch_roof"):
		return _bmat_thatch
	elif build_id.begins_with(&"slate_roof"):
		return _bmat_slate
	return null

func _make_ghost_material(build_id: StringName, fallback_color: Color) -> StandardMaterial3D:
	var base := _get_building_material(build_id)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if base and base.albedo_texture:
		mat.albedo_texture = base.albedo_texture
		mat.albedo_color = Color(base.albedo_color.r, base.albedo_color.g, base.albedo_color.b, 0.45)
		mat.uv1_scale = base.uv1_scale
		mat.texture_filter = base.texture_filter
	else:
		mat.albedo_color = Color(fallback_color.r, fallback_color.g, fallback_color.b, 0.45)
	return mat


# â”€â”€ Roof wedge mesh â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
static func _build_roof_mesh(sz: Vector3, rise: float) -> ArrayMesh:
	var hw := sz.x * 0.5
	var hd := sz.z * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var v0 := Vector3(-hw, 0.0, -hd)
	var v1 := Vector3( hw, 0.0, -hd)
	var v2 := Vector3( hw, 0.0,  hd)
	var v3 := Vector3(-hw, 0.0,  hd)
	var v4 := Vector3(-hw, rise,  hd)
	var v5 := Vector3( hw, rise,  hd)

	# Slope face (visible from above)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_uv(Vector2(1, 0)); st.add_vertex(v1)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v5)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v5)
	st.set_uv(Vector2(0, 1)); st.add_vertex(v4)

	# Bottom face
	st.set_uv(Vector2(0, 0)); st.add_vertex(v3)
	st.set_uv(Vector2(1, 0)); st.add_vertex(v2)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v1)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v3)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v1)
	st.set_uv(Vector2(0, 1)); st.add_vertex(v0)

	# Back face (vertical at +Z)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v3)
	st.set_uv(Vector2(0, 1)); st.add_vertex(v4)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v5)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v3)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v5)
	st.set_uv(Vector2(1, 0)); st.add_vertex(v2)

	# Left triangle
	st.set_uv(Vector2(0, 1)); st.add_vertex(v0)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v4)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v3)

	# Right triangle
	st.set_uv(Vector2(1, 1)); st.add_vertex(v1)
	st.set_uv(Vector2(0, 1)); st.add_vertex(v2)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v5)

	st.generate_normals()
	return st.commit()


static func _build_roof_ocorner_mesh(sz: Vector3, rise: float) -> ArrayMesh:
	var hw := sz.x * 0.5
	var hd := sz.z * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var peak := Vector3(hw, rise, hd)
	var bl := Vector3(-hw, 0.0, -hd)
	var br := Vector3( hw, 0.0, -hd)
	var fl := Vector3(-hw, 0.0,  hd)
	var fr := Vector3( hw, 0.0,  hd)
	# Front slope (-Z face, from front-left and front-right up to peak)
	st.set_uv(Vector2(0, 1)); st.add_vertex(bl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	st.set_uv(Vector2(1, 0)); st.add_vertex(peak)
	# Right slope (+X face, from front-right and back-right up to peak)
	st.set_uv(Vector2(0, 1)); st.add_vertex(br)
	st.set_uv(Vector2(1, 1)); st.add_vertex(fr)
	st.set_uv(Vector2(1, 0)); st.add_vertex(peak)
	# Back wall (+Z face)
	st.set_uv(Vector2(0, 1)); st.add_vertex(fr)
	st.set_uv(Vector2(0, 0)); st.add_vertex(peak)
	st.set_uv(Vector2(1, 1)); st.add_vertex(fl)
	# Left wall (-X face)
	st.set_uv(Vector2(0, 1)); st.add_vertex(fl)
	st.set_uv(Vector2(0, 0)); st.add_vertex(peak)
	st.set_uv(Vector2(1, 1)); st.add_vertex(bl)
	# Bottom face
	st.set_uv(Vector2(0, 0)); st.add_vertex(fl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(fr)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	st.set_uv(Vector2(0, 0)); st.add_vertex(fl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	st.set_uv(Vector2(0, 1)); st.add_vertex(bl)
	st.generate_normals()
	return st.commit()


static func _build_roof_icorner_mesh(sz: Vector3, rise: float) -> ArrayMesh:
	var hw := sz.x * 0.5
	var hd := sz.z * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tl := Vector3(-hw, rise,  hd)
	var tr := Vector3( hw, rise,  hd)
	var tb := Vector3( hw, rise, -hd)
	var valley := Vector3(-hw, 0.0, -hd)
	var bl := Vector3(-hw, 0.0, -hd)
	var br := Vector3( hw, 0.0, -hd)
	var fl := Vector3(-hw, 0.0,  hd)
	# Left slope: tl â†’ fl â†’ valley (triangle covering -X side)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
	st.set_uv(Vector2(0, 1)); st.add_vertex(fl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(valley)
	# Front slope: tl â†’ valley â†’ tb (the inner valley surface)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(valley)
	st.set_uv(Vector2(1, 0)); st.add_vertex(tb)
	# Right slope: tb â†’ valley â†’ br (triangle covering -Z side)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tb)
	st.set_uv(Vector2(0, 1)); st.add_vertex(valley)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	# Back wall (+Z face, vertical)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(tr)
	st.set_uv(Vector2(1, 1)); st.add_vertex(fl)
	# Right wall (+X face, vertical)
	st.set_uv(Vector2(0, 0)); st.add_vertex(tr)
	st.set_uv(Vector2(1, 0)); st.add_vertex(tb)
	st.set_uv(Vector2(1, 1)); st.add_vertex(br)
	# Top flat between ridges
	st.set_uv(Vector2(0, 0)); st.add_vertex(tl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(tr)
	st.set_uv(Vector2(1, 1)); st.add_vertex(tb)
	# Bottom face
	st.set_uv(Vector2(0, 0)); st.add_vertex(fl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(br)
	st.set_uv(Vector2(1, 1)); st.add_vertex(bl)
	st.generate_normals()
	return st.commit()


static func _build_roof_ridge_mesh(sz: Vector3) -> ArrayMesh:
	var hw := sz.x * 0.5
	var hh := sz.y * 0.5
	var hd := sz.z * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v0 := Vector3(-hw, -hh, -hd)
	var v1 := Vector3( hw, -hh, -hd)
	var v2 := Vector3( hw,  hh, -hd)
	var v3 := Vector3(-hw,  hh, -hd)
	var v4 := Vector3(-hw, -hh,  hd)
	var v5 := Vector3( hw, -hh,  hd)
	var v6 := Vector3( hw,  hh,  hd)
	var v7 := Vector3(-hw,  hh,  hd)
	var faces := [
		[v3, v2, v1, v0],
		[v4, v5, v6, v7],
		[v0, v1, v5, v4],
		[v2, v3, v7, v6],
		[v3, v0, v4, v7],
		[v1, v2, v6, v5],
	]
	for f in faces:
		st.set_uv(Vector2(0, 0)); st.add_vertex(f[0])
		st.set_uv(Vector2(1, 0)); st.add_vertex(f[1])
		st.set_uv(Vector2(1, 1)); st.add_vertex(f[2])
		st.set_uv(Vector2(0, 0)); st.add_vertex(f[0])
		st.set_uv(Vector2(1, 1)); st.add_vertex(f[2])
		st.set_uv(Vector2(0, 1)); st.add_vertex(f[3])
	st.generate_normals()
	return st.commit()


static func _build_stair_mesh(sz: Vector3, step_count: int = 6) -> ArrayMesh:
	var hw := sz.x * 0.5
	var step_h := sz.y / float(step_count)
	var step_d := sz.z / float(step_count)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(step_count):
		var y0 := step_h * float(i)
		var y1 := step_h * float(i + 1)
		var z0 := -sz.z * 0.5 + step_d * float(i)
		var z1 := -sz.z * 0.5 + step_d * float(i + 1)

		var a := Vector3(-hw, y1, z0)
		var b := Vector3( hw, y1, z0)
		var c := Vector3( hw, y1, z1)
		var d := Vector3(-hw, y1, z1)
		var e := Vector3(-hw, y0, z0)
		var f := Vector3( hw, y0, z0)

		# Top face (tread)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a)
		st.set_uv(Vector2(1, 0)); st.add_vertex(b)
		st.set_uv(Vector2(1, 1)); st.add_vertex(c)
		st.set_uv(Vector2(0, 0)); st.add_vertex(a)
		st.set_uv(Vector2(1, 1)); st.add_vertex(c)
		st.set_uv(Vector2(0, 1)); st.add_vertex(d)

		# Front face (riser)
		st.set_uv(Vector2(0, 0)); st.add_vertex(e)
		st.set_uv(Vector2(1, 0)); st.add_vertex(f)
		st.set_uv(Vector2(1, 1)); st.add_vertex(b)
		st.set_uv(Vector2(0, 0)); st.add_vertex(e)
		st.set_uv(Vector2(1, 1)); st.add_vertex(b)
		st.set_uv(Vector2(0, 1)); st.add_vertex(a)

	# Left side face
	var bl := Vector3(-hw, 0.0, -sz.z * 0.5)
	var tl := Vector3(-hw, sz.y, sz.z * 0.5)
	var br := Vector3(-hw, 0.0, sz.z * 0.5)
	st.set_uv(Vector2(0, 0)); st.add_vertex(bl)
	st.set_uv(Vector2(1, 1)); st.add_vertex(tl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(br)

	# Right side face
	var rbl := Vector3(hw, 0.0, -sz.z * 0.5)
	var rtl := Vector3(hw, sz.y, sz.z * 0.5)
	var rbr := Vector3(hw, 0.0, sz.z * 0.5)
	st.set_uv(Vector2(0, 0)); st.add_vertex(rbl)
	st.set_uv(Vector2(1, 0)); st.add_vertex(rbr)
	st.set_uv(Vector2(1, 1)); st.add_vertex(rtl)

	# Bottom face
	var b0 := Vector3(-hw, 0.0, -sz.z * 0.5)
	var b1 := Vector3( hw, 0.0, -sz.z * 0.5)
	var b2 := Vector3( hw, 0.0,  sz.z * 0.5)
	var b3 := Vector3(-hw, 0.0,  sz.z * 0.5)
	st.set_uv(Vector2(0, 0)); st.add_vertex(b3)
	st.set_uv(Vector2(1, 0)); st.add_vertex(b2)
	st.set_uv(Vector2(1, 1)); st.add_vertex(b1)
	st.set_uv(Vector2(0, 0)); st.add_vertex(b3)
	st.set_uv(Vector2(1, 1)); st.add_vertex(b1)
	st.set_uv(Vector2(0, 1)); st.add_vertex(b0)

	st.generate_normals()
	return st.commit()


static func _add_stair_collision(structure: StaticBody3D, sz: Vector3, _step_count: int = 6) -> void:
	var phys_steps := ceili(sz.y / 0.3)
	var step_h := sz.y / float(phys_steps)
	var step_d := sz.z / float(phys_steps)
	for i in range(phys_steps):
		var col_shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		var height := step_h * float(i + 1)
		box.size = Vector3(sz.x, height, step_d)
		col_shape.shape = box
		var z_center := -sz.z * 0.5 + step_d * (float(i) + 0.5)
		col_shape.position = Vector3(0.0, height * 0.5, z_center)
		structure.add_child(col_shape)


# â”€â”€ Snap system â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const Z_FIGHT_OFFSET := 0.001

const SNAP_COMPAT: Dictionary = {
	&"wall_base":      [&"wall_top", &"floor_edge"],
	&"wall_top":       [&"wall_base", &"floor_edge", &"roof_base_45", &"roof_base_26"],
	&"wall_side":      [&"wall_side"],
	&"floor_edge":     [&"wall_base", &"wall_top", &"floor_edge"],
	&"floor_corner":   [&"floor_corner"],
	&"roof_base_45":   [&"wall_top", &"roof_ridge_45"],
	&"roof_base_26":   [&"wall_top", &"roof_ridge_26"],
	&"roof_ridge_45":  [&"roof_ridge_45", &"roof_base_45"],
	&"roof_ridge_26":  [&"roof_ridge_26", &"roof_base_26"],
	&"roof_side_45":   [&"roof_side_45"],
	&"roof_side_26":   [&"roof_side_26"],
	&"ridge_cap_end":  [&"ridge_cap_end", &"roof_ridge_45", &"roof_ridge_26"],
}

static func _get_roof_angle_group(build_id: StringName) -> int:
	if "45" in str(build_id):
		return 45
	elif "26" in str(build_id):
		return 26
	return 0

func _get_snap_points_for(build_id: StringName, sz: Vector3) -> Array[Dictionary]:
	var pts: Array[Dictionary] = []
	var hw := sz.x * 0.5
	var hd := sz.z * 0.5
	var h := sz.y

	if build_id in [&"wood_wall", &"stone_wall", &"wood_door", &"stone_door"]:
		var edge_overlap := 0.10
		for x in [-hw + edge_overlap, 0.0, hw - edge_overlap]:
			pts.append({"pos": Vector3(x, 0.0, 0.0), "type": &"wall_base"})
			pts.append({"pos": Vector3(x, h, 0.0), "type": &"wall_top"})
		pts.append({"pos": Vector3(-hw + edge_overlap, h * 0.5, 0.0), "type": &"wall_side"})
		pts.append({"pos": Vector3( hw - edge_overlap, h * 0.5, 0.0), "type": &"wall_side"})

	elif build_id == &"wood_stair":
		pts.append({"pos": Vector3( 0.0, 0.0, -hd), "type": &"floor_edge"})
		pts.append({"pos": Vector3( 0.0, h,    hd), "type": &"floor_edge"})
		pts.append({"pos": Vector3(-hw,  0.0, -hd), "type": &"floor_corner"})
		pts.append({"pos": Vector3( hw,  0.0, -hd), "type": &"floor_corner"})
		pts.append({"pos": Vector3(-hw,  h,    hd), "type": &"floor_corner"})
		pts.append({"pos": Vector3( hw,  h,    hd), "type": &"floor_corner"})

	elif build_id in [&"wood_floor", &"stone_floor"]:
		pts.append({"pos": Vector3( 0.0, h, -hd), "type": &"floor_edge"})
		pts.append({"pos": Vector3( 0.0, h,  hd), "type": &"floor_edge"})
		pts.append({"pos": Vector3(-hw,  h, 0.0), "type": &"floor_edge"})
		pts.append({"pos": Vector3( hw,  h, 0.0), "type": &"floor_edge"})
		pts.append({"pos": Vector3(-hw, h, -hd), "type": &"floor_corner"})
		pts.append({"pos": Vector3( hw, h, -hd), "type": &"floor_corner"})
		pts.append({"pos": Vector3(-hw, h,  hd), "type": &"floor_corner"})
		pts.append({"pos": Vector3( hw, h,  hd), "type": &"floor_corner"})

	elif build_id.begins_with("thatch_roof") or build_id.begins_with("slate_roof"):
		var ag := _get_roof_angle_group(build_id)
		var base_type: StringName = &"roof_base_45" if ag == 45 else &"roof_base_26"
		var ridge_type: StringName = &"roof_ridge_45" if ag == 45 else &"roof_ridge_26"
		var side_type: StringName = &"roof_side_45" if ag == 45 else &"roof_side_26"
		var mesh_type: String = str((_get_build_recipe(build_id) as Dictionary).get("mesh", ""))

		if mesh_type in ["roof_45", "roof_26"]:
			for x in [-hw, 0.0, hw]:
				pts.append({"pos": Vector3(x, 0.0, -hd), "type": base_type})
			for x in [-hw, 0.0, hw]:
				pts.append({"pos": Vector3(x, h, hd), "type": ridge_type})
			pts.append({"pos": Vector3(-hw, h * 0.5, 0.0), "type": side_type})
			pts.append({"pos": Vector3( hw, h * 0.5, 0.0), "type": side_type})

		elif mesh_type in ["roof_45_ocorner", "roof_26_ocorner"]:
			for x in [-hw, 0.0, hw]:
				pts.append({"pos": Vector3(x, 0.0, -hd), "type": base_type})
			for z in [-hd, 0.0, hd]:
				pts.append({"pos": Vector3(hw, 0.0, z), "type": base_type})
			pts.append({"pos": Vector3(hw, h, hd), "type": ridge_type})

		elif mesh_type in ["roof_45_icorner", "roof_26_icorner"]:
			for x in [-hw, 0.0, hw]:
				pts.append({"pos": Vector3(x, 0.0, -hd), "type": base_type})
			for z in [-hd, 0.0, hd]:
				pts.append({"pos": Vector3(-hw, 0.0, z), "type": base_type})
			for x in [-hw, 0.0, hw]:
				pts.append({"pos": Vector3(x, h, hd), "type": ridge_type})
			for z in [-hd, 0.0, hd]:
				pts.append({"pos": Vector3(hw, h, z), "type": ridge_type})

		elif mesh_type == "roof_ridge":
			pts.append({"pos": Vector3(-hw, 0.0, 0.0), "type": &"ridge_cap_end"})
			pts.append({"pos": Vector3( hw, 0.0, 0.0), "type": &"ridge_cap_end"})
			pts.append({"pos": Vector3( 0.0, 0.0, -hd), "type": &"ridge_cap_end"})
			pts.append({"pos": Vector3( 0.0, 0.0,  hd), "type": &"ridge_cap_end"})

	return pts


func _find_best_snap(ghost_pos: Vector3, ghost_rot_y: float, build_id: StringName, sz: Vector3, priority_structure: Node3D = null) -> Dictionary:
	var new_points := _get_snap_points_for(build_id, sz)
	if new_points.is_empty():
		return {}

	var new_ag := _get_roof_angle_group(build_id)

	var best_dist := 0.8
	var best_pos := Vector3.ZERO
	var best_rot := ghost_rot_y
	var found := false

	# If the player is looking directly at a structure, try snapping to it first
	# with a larger radius so edge-focused placement feels intentional
	var structures := get_tree().get_nodes_in_group(&"structures")
	if priority_structure and is_instance_valid(priority_structure):
		structures.erase(priority_structure)
		structures.push_front(priority_structure)
		best_dist = 2.0  # wider snap radius for the aimed-at structure
	for structure in structures:
		if not structure is Node3D:
			continue
		var s3d := structure as Node3D
		if found and s3d != priority_structure:
			break
		if not found and priority_structure and s3d != priority_structure and best_dist == 2.0:
			best_dist = 0.8
		if s3d.global_position.distance_to(ghost_pos) > 6.0:
			continue

		var exist_id: StringName = s3d.get_meta("build_id", &"") as StringName
		var exist_recipe := _get_build_recipe(exist_id)
		if exist_recipe.is_empty():
			continue

		var exist_ag := _get_roof_angle_group(exist_id)
		if new_ag != 0 and exist_ag != 0 and new_ag != exist_ag:
			continue

		var exist_sz: Vector3 = exist_recipe.get("size", Vector3.ONE) as Vector3
		var exist_points := _get_snap_points_for(exist_id, exist_sz)
		if exist_points.is_empty():
			continue
		var exist_basis := Basis(Vector3.UP, s3d.rotation.y)

		var rotations: Array[float] = [
			ghost_rot_y,
			s3d.rotation.y,
			s3d.rotation.y + PI * 0.5,
			s3d.rotation.y + PI,
			s3d.rotation.y + PI * 1.5,
		]

		for try_rot: float in rotations:
			var try_basis := Basis(Vector3.UP, try_rot)
			for np: Dictionary in new_points:
				var np_type: StringName = np["type"] as StringName
				var np_local: Vector3 = np["pos"] as Vector3
				var compat_list: Array = SNAP_COMPAT.get(np_type, []) as Array

				for ep: Dictionary in exist_points:
					var ep_type: StringName = ep["type"] as StringName
					if ep_type not in compat_list:
						continue
					var ep_world: Vector3 = s3d.global_position + exist_basis * (ep["pos"] as Vector3)
					var np_world: Vector3 = ghost_pos + try_basis * np_local
					var dist := ep_world.distance_to(np_world)
					if dist < best_dist:
						best_dist = dist
						best_pos = ep_world - try_basis * np_local
						best_rot = try_rot
						found = true

	if found:
		var is_roof_piece := str(build_id).begins_with("thatch_roof") or str(build_id).begins_with("slate_roof")
		if is_roof_piece:
			best_pos.y += Z_FIGHT_OFFSET
		return {"pos": best_pos, "rot_y": best_rot}
	return {}


func _update_ghost_snap_color(snapped: bool) -> void:
	if not _build_ghost:
		return
	var mi := _build_ghost.get_child(0) as MeshInstance3D
	if not mi:
		return
	var mat := mi.get_surface_override_material(0) as StandardMaterial3D
	if not mat:
		return
	if snapped:
		mat.albedo_color = Color(0.3, 0.9, 0.3, 0.5)
	else:
		var recipe := _get_build_recipe(_build_selected)
		var base_color: Color = recipe.get("color", Color(0.5, 0.4, 0.2)) as Color
		var bmat := _get_building_material(_build_selected)
		if bmat and bmat.albedo_texture:
			mat.albedo_color = Color(bmat.albedo_color.r, bmat.albedo_color.g, bmat.albedo_color.b, 0.45)
		else:
			mat.albedo_color = Color(base_color.r, base_color.g, base_color.b, 0.45)


func _update_snap_side_label() -> void:
	if not _build_snap_side_label:
		return
	const SIDE_NAMES := ["Forward", "Back", "Left", "Right", "Top", "Bottom"]
	_build_snap_side_label.text = "Side: " + SIDE_NAMES[_build_snap_side]

func _build_snap_label(root: Control) -> void:
	_snap_label = Label.new()
	_snap_label.name = "SnapLabel"
	_snap_label.visible = false
	_snap_label.text = "Snap: ON"
	_snap_label.add_theme_font_size_override("font_size", 14)
	_snap_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_snap_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_snap_label.add_theme_constant_override("shadow_offset_x", 1)
	_snap_label.add_theme_constant_override("shadow_offset_y", 1)
	_snap_label.set_anchors_preset(Control.PRESET_CENTER)
	_snap_label.offset_top = 40
	_snap_label.offset_bottom = 60
	_snap_label.offset_left = -60
	_snap_label.offset_right = 60
	_snap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_snap_label.z_index = 80
	_snap_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_snap_label)

	_build_snap_side_label = Label.new()
	_build_snap_side_label.name = "SnapSideLabel"
	_build_snap_side_label.visible = false
	_build_snap_side_label.add_theme_font_size_override("font_size", 14)
	_build_snap_side_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_build_snap_side_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	_build_snap_side_label.add_theme_constant_override("shadow_offset_x", 1)
	_build_snap_side_label.add_theme_constant_override("shadow_offset_y", 1)
	_build_snap_side_label.set_anchors_preset(Control.PRESET_CENTER)
	_build_snap_side_label.offset_top = 58
	_build_snap_side_label.offset_bottom = 78
	_build_snap_side_label.offset_left = -60
	_build_snap_side_label.offset_right = 60
	_build_snap_side_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_build_snap_side_label.z_index = 80
	_build_snap_side_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_build_snap_side_label)


func _build_build_crosshair(root: Control) -> void:
	_build_crosshair = Control.new()
	_build_crosshair.name = "BuildCrosshair"
	_build_crosshair.visible = false
	_build_crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_crosshair.z_index = 90
	_build_crosshair.draw.connect(func() -> void:
		var vp_size := _build_crosshair.get_viewport_rect().size
		var c := vp_size * 0.5
		var col := Color(1.0, 1.0, 1.0, 0.8)
		var outline := Color(0.0, 0.0, 0.0, 0.5)
		var arm := 10.0
		var gap := 3.0
		for off in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
			_build_crosshair.draw_line(c + Vector2(-arm - gap, 0) + off, c + Vector2(-gap, 0) + off, outline, 2.5)
			_build_crosshair.draw_line(c + Vector2(gap, 0) + off, c + Vector2(arm + gap, 0) + off, outline, 2.5)
			_build_crosshair.draw_line(c + Vector2(0, -arm - gap) + off, c + Vector2(0, -gap) + off, outline, 2.5)
			_build_crosshair.draw_line(c + Vector2(0, gap) + off, c + Vector2(0, arm + gap) + off, outline, 2.5)
		_build_crosshair.draw_line(c + Vector2(-arm - gap, 0), c + Vector2(-gap, 0), col, 1.5)
		_build_crosshair.draw_line(c + Vector2(gap, 0), c + Vector2(arm + gap, 0), col, 1.5)
		_build_crosshair.draw_line(c + Vector2(0, -arm - gap), c + Vector2(0, -gap), col, 1.5)
		_build_crosshair.draw_line(c + Vector2(0, gap), c + Vector2(0, arm + gap), col, 1.5)
		_build_crosshair.draw_circle(c, 1.5, col)
	)
	root.add_child(_build_crosshair)


func _add_building_glb(parent: Node3D, model_path: String, sz: Vector3, ghost_mat: Material = null, tint: Color = Color(-1, -1, -1)) -> bool:
	var scene: PackedScene = load(model_path) as PackedScene
	if not scene:
		return false
	var instance := scene.instantiate() as Node3D
	if not instance:
		return false

	var use_tint := tint.r >= 0.0 and not ghost_mat
	var tint_mat: StandardMaterial3D = null
	if use_tint:
		tint_mat = StandardMaterial3D.new()
		tint_mat.albedo_color = tint
		tint_mat.roughness = 0.85
		tint_mat.metallic = 0.0

	var aabb := AABB()
	var found_mesh := false
	for child in instance.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			aabb = aabb.merge(mi.get_aabb()) if found_mesh else mi.get_aabb()
			found_mesh = true
			var mat_to_apply: Material = ghost_mat if ghost_mat else (tint_mat if use_tint and _glb_surface_lacks_texture(mi) else null)
			if mat_to_apply:
				for s in mi.mesh.get_surface_count():
					mi.set_surface_override_material(s, mat_to_apply)
	if not found_mesh:
		if instance is MeshInstance3D:
			aabb = (instance as MeshInstance3D).get_aabb()
			found_mesh = true
			var mi := instance as MeshInstance3D
			var mat_to_apply: Material = ghost_mat if ghost_mat else (tint_mat if use_tint and _glb_surface_lacks_texture(mi) else null)
			if mat_to_apply:
				for s in mi.mesh.get_surface_count():
					mi.set_surface_override_material(s, mat_to_apply)
	if found_mesh and aabb.size.length() > 0.01:
		var scale_x := sz.x / maxf(aabb.size.x, 0.001)
		var scale_y := sz.y / maxf(aabb.size.y, 0.001)
		var scale_z := sz.z / maxf(aabb.size.z, 0.001)
		instance.scale = Vector3(scale_x, scale_y, scale_z)
		instance.position.y = sz.y * 0.5
	else:
		instance.position.y = sz.y * 0.5
	parent.add_child(instance)
	return true


func _glb_surface_lacks_texture(mi: MeshInstance3D) -> bool:
	if not mi.mesh:
		return true
	for s in mi.mesh.get_surface_count():
		var mat := mi.mesh.surface_get_material(s)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			if sm.albedo_texture:
				return false
			if sm.albedo_color != Color(1, 1, 1, 1) and sm.albedo_color != Color(0.8, 0.8, 0.8, 1):
				return false
		elif mat is ShaderMaterial:
			return false
	return true


func _add_torch_light(structure: Node3D, offset: Vector3) -> void:
	var light := OmniLight3D.new()
	light.name = "TorchLight"
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 2.0
	light.omni_range = 7.0
	light.shadow_enabled = true
	light.position = offset
	structure.add_child(light)


func _build_wall_torch_visual(structure: StaticBody3D) -> void:
	# Bracket (small box against the wall)
	var bracket := MeshInstance3D.new()
	var br_mesh := BoxMesh.new()
	br_mesh.size = Vector3(0.08, 0.15, 0.12)
	bracket.mesh = br_mesh
	var br_mat := StandardMaterial3D.new()
	br_mat.albedo_color = Color(0.3, 0.22, 0.1)
	br_mat.roughness = 0.9
	bracket.set_surface_override_material(0, br_mat)
	bracket.position = Vector3(0.0, 1.6, 0.0)
	structure.add_child(bracket)

	# Torch stick
	var stick := MeshInstance3D.new()
	var stick_mesh := CylinderMesh.new()
	stick_mesh.top_radius = 0.025
	stick_mesh.bottom_radius = 0.035
	stick_mesh.height = 0.5
	stick_mesh.radial_segments = 6
	stick.mesh = stick_mesh
	var stick_mat := StandardMaterial3D.new()
	stick_mat.albedo_color = Color(0.4, 0.28, 0.12)
	stick.set_surface_override_material(0, stick_mat)
	stick.position = Vector3(0.0, 1.85, 0.08)
	stick.rotation.x = deg_to_rad(-15.0)
	structure.add_child(stick)

	# Flame glow (small bright sphere)
	var flame := MeshInstance3D.new()
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.06
	flame_mesh.height = 0.14
	flame_mesh.radial_segments = 6
	flame_mesh.rings = 3
	flame.mesh = flame_mesh
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.6, 0.1)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.5, 0.1)
	flame_mat.emission_energy_multiplier = 3.0
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.albedo_color.a = 0.8
	flame.set_surface_override_material(0, flame_mat)
	flame.position = Vector3(0.0, 2.12, 0.12)
	structure.add_child(flame)

	# OmniLight3D for actual illumination
	var light := OmniLight3D.new()
	light.name = "TorchLight"
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 2.5
	light.omni_range = 8.0
	light.shadow_enabled = true
	light.position = Vector3(0.0, 2.15, 0.12)
	structure.add_child(light)


func _build_chest_visual(structure: Node3D, sz: Vector3) -> void:
	_ensure_building_materials()

	var mat_metal := StandardMaterial3D.new()
	mat_metal.albedo_color = Color(0.25, 0.22, 0.2)
	mat_metal.roughness = 0.5
	mat_metal.metallic = 0.4

	var body := MeshInstance3D.new()
	body.name = "Body"
	var body_mesh := BoxMesh.new()
	body_mesh.size = sz
	body.mesh = body_mesh
	body.set_surface_override_material(0, _bmat_wood)
	body.position.y = sz.y * 0.5
	structure.add_child(body)

	var lid := MeshInstance3D.new()
	lid.name = "Lid"
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(sz.x + 0.04, sz.y * 0.15, sz.z + 0.04)
	lid.mesh = lid_mesh
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.35, 0.22, 0.10)
	lid_mat.roughness = 0.85
	lid.set_surface_override_material(0, lid_mat)
	lid.position.y = sz.y + sz.y * 0.075
	structure.add_child(lid)

	var band_mat := mat_metal
	for bx in [-0.2, 0.2]:
		var band := MeshInstance3D.new()
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(0.04, sz.y * 1.15 + 0.02, sz.z + 0.06)
		band.mesh = band_mesh
		band.set_surface_override_material(0, band_mat)
		band.position = Vector3(bx * sz.x, sz.y * 0.575, 0.0)
		structure.add_child(band)

	var latch := MeshInstance3D.new()
	var latch_mesh := BoxMesh.new()
	latch_mesh.size = Vector3(0.08, 0.06, 0.04)
	latch.mesh = latch_mesh
	latch.set_surface_override_material(0, band_mat)
	latch.position = Vector3(0.0, sz.y * 0.7, sz.z * 0.5 + 0.03)
	structure.add_child(latch)


func _build_interaction_prompt(root: Control) -> void:
	_interact_prompt = Label.new()
	_interact_prompt.name = "InteractionPrompt"
	_interact_prompt.visible = false
	_interact_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_interact_prompt.add_theme_font_size_override("font_size", 20)
	_interact_prompt.add_theme_color_override("font_color", Color(1.0, 0.95, 0.8))
	_interact_prompt.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_interact_prompt.add_theme_constant_override("shadow_offset_x", 2)
	_interact_prompt.add_theme_constant_override("shadow_offset_y", 2)
	_interact_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_interact_prompt.offset_top = 60
	_interact_prompt.offset_bottom = 100
	_interact_prompt.offset_left = -200
	_interact_prompt.offset_right = 200
	_interact_prompt.z_index = 50
	root.add_child(_interact_prompt)


func _drop_item_on_ground(item_id: StringName, amount: int, despawn_time: float = 60.0) -> void:
	var parsed := ItemDatabase.parse_star_id(item_id)
	var stars: int = parsed["stars"]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var cam: Camera3D = _spring_arm.get_child(0) if _spring_arm.get_child_count() > 0 else null
	var forward := -cam.global_transform.basis.z if cam else Vector3.FORWARD
	var fwd_flat := Vector3(forward.x, 0.0, forward.z).normalized()
	var drop_pos := global_position + fwd_flat * 2.0 + Vector3.UP * 0.5
	drop_pos += Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))

	var my_peer := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	if NetworkManager.is_connected_to_game():
		var wss := _get_world_state_sync()
		if wss:
			if NetworkManager.is_server():
				wss.spawn_player_drop_synced(drop_pos, item_id, amount, stars, my_peer)
			else:
				wss.request_drop_item.rpc_id(1, str(item_id), amount, stars, drop_pos.x, drop_pos.y, drop_pos.z)
			return

	var drop := LootDrop.new()
	drop.item_id = item_id
	drop.star_level = stars
	drop.amount = amount
	drop.pickup_grace = 5.0
	drop.drop_owner_peer = my_peer
	get_tree().current_scene.add_child(drop)
	drop.global_position = drop_pos

	if despawn_time > 0.0:
		get_tree().create_timer(despawn_time).timeout.connect(func():
			if is_instance_valid(drop):
				drop.queue_free()
		)


func _make_gradient_tex(w: int, h: int, top: Color, bottom: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		var t := float(y) / float(h - 1)
		var c := bottom.lerp(top, t)
		for x in w:
			var noise := randf_range(-0.05, 0.05)
			img.set_pixel(x, y, Color(clampf(c.r + noise, 0, 1), clampf(c.g + noise, 0, 1), clampf(c.b + noise, 0, 1), c.a))
	return ImageTexture.create_from_image(img)


func _make_solid_tex(w: int, h: int, color: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


func _load_campfire_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path) or FileAccess.file_exists(path):
		var img := Image.new()
		if img.load(abs_path if FileAccess.file_exists(abs_path) else path) == OK:
			return ImageTexture.create_from_image(img)
	return null


func _build_campfire_visual(structure: StaticBody3D, sz: Vector3) -> void:
	var log_tex := _load_campfire_tex("res://textures/campfire/burning_log.png")
	var ember_tex := _load_campfire_tex("res://textures/campfire/ember_bed.png")
	var smoke_tex := _load_campfire_tex("res://textures/campfire/smoke.png")

	# Load animated flame frames (12-frame loop)
	var flame_anim_frames: Array[Texture2D] = []
	for fi in 12:
		var path := "res://textures/campfire/flame_frame_%d.png" % fi
		var ftex := _load_campfire_tex(path)
		if ftex:
			flame_anim_frames.append(ftex)
	if _DEBUG_LOG: print("[Campfire] Loaded %d flame animation frames" % flame_anim_frames.size())

	var fire_full_tex: Texture2D
	var fire_only_tex: Texture2D
	if flame_anim_frames.size() >= 2:
		fire_full_tex = flame_anim_frames[0]
		fire_only_tex = flame_anim_frames[1]
	else:
		fire_full_tex = _load_campfire_tex("res://textures/campfire/campfire_full.png")
		fire_only_tex = _load_campfire_tex("res://textures/campfire/flames_only.png")

	if not log_tex:
		log_tex = _make_gradient_tex(24, 8, Color(0.15, 0.08, 0.02), Color(0.4, 0.2, 0.05))
	if not ember_tex:
		ember_tex = _make_gradient_tex(24, 24, Color(1.0, 0.3, 0.0, 0.9), Color(0.6, 0.1, 0.0, 0.7))
	if not fire_full_tex:
		fire_full_tex = _make_gradient_tex(16, 32, Color(1.0, 1.0, 0.3, 0.0), Color(1.0, 0.4, 0.0, 0.95))
	if not fire_only_tex:
		fire_only_tex = _make_gradient_tex(16, 32, Color(1.0, 0.9, 0.2, 0.0), Color(1.0, 0.2, 0.0, 0.9))
	if not smoke_tex:
		smoke_tex = _make_solid_tex(16, 16, Color(0.6, 0.6, 0.65, 0.15))

	# â”€â”€ Static logs beneath the fire (3 crossing logs, flat and centered) â”€â”€
	for i in 3:
		var log_sp := Sprite3D.new()
		log_sp.texture = log_tex
		log_sp.pixel_size = 0.009
		log_sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		log_sp.shaded = true
		log_sp.transparent = true
		log_sp.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		var la := float(i) * TAU / 3.0
		log_sp.position = Vector3(0.0, 0.06, 0.0)
		log_sp.rotation.y = la
		log_sp.rotation.x = -PI * 0.5 + randf_range(-0.08, 0.08)
		structure.add_child(log_sp)

	# â”€â”€ Ember bed (glowing coal sprite flat on the ground) â”€â”€
	var ember_sp := Sprite3D.new()
	ember_sp.texture = ember_tex
	ember_sp.pixel_size = 0.012
	ember_sp.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	ember_sp.axis = Vector3.AXIS_Y
	ember_sp.rotation.x = -PI * 0.5
	ember_sp.position.y = 0.03
	ember_sp.transparent = true
	ember_sp.shaded = false
	structure.add_child(ember_sp)

	# Crop region to show only the flame portion (top 60%) of each frame,
	# hiding the log/base artwork baked into the bottom of the generated PNGs.
	var flame_region := Rect2(0, 0, 48, 30)

	# â”€â”€ Main campfire sprite (core flame â€” largest, always visible) â”€â”€
	var main_fire := Sprite3D.new()
	main_fire.name = "MainFire"
	main_fire.texture = fire_full_tex
	main_fire.region_enabled = true
	main_fire.region_rect = flame_region
	main_fire.pixel_size = 0.024
	main_fire.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	main_fire.position.y = 0.45
	main_fire.transparent = true
	main_fire.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	main_fire.shaded = false
	main_fire.modulate = Color(1.0, 0.95, 0.85, 0.95)
	structure.add_child(main_fire)

	# â”€â”€ Multiple overlapping flame layers for depth and movement â”€â”€
	var flame_sprites: Array[Sprite3D] = []
	flame_sprites.append(main_fire)

	var flame2 := Sprite3D.new()
	flame2.name = "FlameLayer2"
	flame2.texture = fire_only_tex
	flame2.region_enabled = true
	flame2.region_rect = flame_region
	flame2.pixel_size = 0.022
	flame2.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame2.position = Vector3(0.08, 0.40, 0.06)
	flame2.transparent = true
	flame2.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	flame2.shaded = false
	flame2.modulate = Color(1.0, 0.85, 0.6, 0.8)
	flame2.scale = Vector3(0.9, 1.15, 1.0)
	structure.add_child(flame2)
	flame_sprites.append(flame2)

	var flame3 := Sprite3D.new()
	flame3.name = "FlameLayer3"
	flame3.texture = fire_only_tex
	flame3.region_enabled = true
	flame3.region_rect = flame_region
	flame3.pixel_size = 0.020
	flame3.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame3.position = Vector3(-0.06, 0.50, -0.05)
	flame3.transparent = true
	flame3.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	flame3.shaded = false
	flame3.modulate = Color(1.0, 0.7, 0.4, 0.7)
	flame3.scale = Vector3(0.8, 1.0, 1.0)
	structure.add_child(flame3)
	flame_sprites.append(flame3)

	var flame4 := Sprite3D.new()
	flame4.name = "FlameLayer4"
	flame4.texture = fire_full_tex
	flame4.region_enabled = true
	flame4.region_rect = flame_region
	flame4.pixel_size = 0.017
	flame4.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame4.position = Vector3(0.0, 0.60, 0.0)
	flame4.transparent = true
	flame4.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	flame4.shaded = false
	flame4.modulate = Color(1.0, 1.0, 0.5, 0.5)
	flame4.scale = Vector3(0.6, 0.7, 1.0)
	structure.add_child(flame4)
	flame_sprites.append(flame4)

	# â”€â”€ Smoke wisps (2 layers rising above the fire) â”€â”€
	var smoke_sprites: Array[Sprite3D] = []
	for si in 2:
		var smoke := Sprite3D.new()
		smoke.name = "Smoke%d" % si
		smoke.texture = smoke_tex
		smoke.pixel_size = 0.014 + float(si) * 0.004
		smoke.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		smoke.position = Vector3(randf_range(-0.06, 0.06), 1.0 + float(si) * 0.4, randf_range(-0.06, 0.06))
		smoke.transparent = true
		smoke.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		smoke.shaded = false
		smoke.modulate = Color(0.7, 0.7, 0.75, 0.2 - float(si) * 0.06)
		structure.add_child(smoke)
		smoke_sprites.append(smoke)

	# â”€â”€ Main fire light â”€â”€
	var light := OmniLight3D.new()
	light.name = "FireLight"
	light.light_color = Color(1.0, 0.55, 0.15)
	light.light_energy = 3.0
	light.omni_range = 10.0
	light.omni_attenuation = 1.2
	light.shadow_enabled = true
	light.position.y = 0.8
	structure.add_child(light)

	# â”€â”€ Warm fill light at base â”€â”€
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.3, 0.05)
	fill.light_energy = 1.2
	fill.omni_range = 5.0
	fill.omni_attenuation = 2.0
	fill.shadow_enabled = false
	fill.position.y = 0.15
	structure.add_child(fill)

	# â”€â”€ Animate everything â”€â”€
	_start_campfire_animation(structure, light, flame_sprites, smoke_sprites, ember_sp, fire_full_tex, fire_only_tex, flame_anim_frames)

	# â”€â”€ Campfire looping sound (non-positional via AudioManager for reliability) â”€â”€
	_start_campfire_sound(structure)

	# â”€â”€ Distance culling â€” hide fire visuals beyond render distance â”€â”€
	_setup_campfire_distance_cull(structure)


func _setup_campfire_distance_cull(structure: StaticBody3D) -> void:
	const CAMPFIRE_RENDER_DIST := 30.0
	const CAMPFIRE_RENDER_DIST_SQ := CAMPFIRE_RENDER_DIST * CAMPFIRE_RENDER_DIST
	var cull_timer := Timer.new()
	cull_timer.name = "CampfireCullTimer"
	cull_timer.wait_time = 0.5
	cull_timer.autostart = true
	cull_timer.one_shot = false
	structure.add_child(cull_timer)
	var was_visible := [true]
	cull_timer.timeout.connect(func() -> void:
		if not is_instance_valid(structure):
			return
		var player := get_tree().get_first_node_in_group(&"player") as Node3D
		if not player:
			return
		var dx := structure.global_position.x - player.global_position.x
		var dz := structure.global_position.z - player.global_position.z
		var in_range := (dx * dx + dz * dz) < CAMPFIRE_RENDER_DIST_SQ
		if in_range == was_visible[0]:
			return
		was_visible[0] = in_range
		structure.set_meta(&"campfire_culled", not in_range)
		for child in structure.get_children():
			if child is Sprite3D or child is OmniLight3D:
				child.visible = in_range
			elif child.name == "FlameAnimTimer":
				child.paused = not in_range
	)


func _disable_structure_shadows(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var surf_count := maxi(mi.get_surface_override_material_count(), mi.mesh.get_surface_count() if mi.mesh else 0)
		for surf_idx in range(surf_count):
			var mat := mi.get_active_material(surf_idx)
			if mat is BaseMaterial3D:
				var m := mat.duplicate() as BaseMaterial3D
				m.set_flag(BaseMaterial3D.FLAG_DONT_RECEIVE_SHADOWS, true)
				if not m.emission_enabled:
					m.emission_enabled = true
					m.emission = m.albedo_color
					m.emission_energy_multiplier = 0.35
				mi.set_surface_override_material(surf_idx, m)
	for child in node.get_children():
		_disable_structure_shadows(child)


func _setup_structure_distance_cull(structure: StaticBody3D) -> void:
	const STRUCT_RENDER_DIST := 50.0
	const STRUCT_RENDER_DIST_SQ := STRUCT_RENDER_DIST * STRUCT_RENDER_DIST
	var cull_timer := Timer.new()
	cull_timer.name = "StructCullTimer"
	cull_timer.wait_time = 0.5
	cull_timer.autostart = true
	cull_timer.one_shot = false
	structure.add_child(cull_timer)
	var was_visible := [true]
	cull_timer.timeout.connect(func() -> void:
		if not is_instance_valid(structure):
			return
		var player := get_tree().get_first_node_in_group(&"player") as Node3D
		if not player:
			return
		var dx := structure.global_position.x - player.global_position.x
		var dz := structure.global_position.z - player.global_position.z
		var in_range := (dx * dx + dz * dz) < STRUCT_RENDER_DIST_SQ
		if in_range == was_visible[0]:
			return
		was_visible[0] = in_range
		for child in structure.get_children():
			if child is MeshInstance3D or child is OmniLight3D or child is Sprite3D:
				child.visible = in_range
	)


func _start_campfire_sound(structure: StaticBody3D) -> void:
	var sfx_paths := [
		"res://audio/sfx/campfire.wav",
		"res://audio/sfx/campfire_raging_1.wav",
		"res://audio/sfx/campfire_raging_2.wav",
	]
	var stream: AudioStream
	var paths_copy := sfx_paths.duplicate()
	paths_copy.shuffle()
	for p in paths_copy:
		if ResourceLoader.exists(p):
			stream = load(p) as AudioStream
			if stream:
				break
	if not stream:
		return

	# Use non-positional AudioStreamPlayer so volume is controlled manually
	# based on player-to-fire distance, not camera-to-fire distance
	var audio := AudioStreamPlayer.new()
	audio.name = "CampfireSound"
	audio.bus = &"SFX"
	audio.stream = stream
	audio.volume_db = -80.0
	audio.max_polyphony = 1
	structure.add_child(audio)
	audio.play()
	audio.finished.connect(audio.play)

	var max_dist := 20.0
	var full_vol_dist := 2.0
	var vol_max_db := 4.0
	var vol_min_db := -80.0

	var fade_timer := Timer.new()
	fade_timer.name = "CampfireFadeTimer"
	fade_timer.wait_time = 0.15
	fade_timer.autostart = true
	fade_timer.one_shot = false
	structure.add_child(fade_timer)
	fade_timer.timeout.connect(func() -> void:
		if not is_instance_valid(structure) or not is_instance_valid(audio):
			return
		var player := get_tree().get_first_node_in_group(&"player") as Node3D
		if not player:
			audio.volume_db = vol_min_db
			return
		var dist: float = player.global_position.distance_to(structure.global_position)
		if dist >= max_dist:
			audio.volume_db = vol_min_db
		elif dist <= full_vol_dist:
			audio.volume_db = vol_max_db
		else:
			var t: float = (dist - full_vol_dist) / (max_dist - full_vol_dist)
			audio.volume_db = lerpf(vol_max_db, vol_min_db, t * t)
	)


func _start_campfire_animation(
	structure: StaticBody3D,
	light: OmniLight3D,
	flames: Array[Sprite3D],
	smokes: Array[Sprite3D],
	ember: Sprite3D,
	tex_a: Texture2D,
	tex_b: Texture2D,
	anim_frames: Array[Texture2D] = [],
) -> void:
	var flame_base_x: Array[float] = []
	var flame_base_y: Array[float] = []
	for f in flames:
		flame_base_x.append(f.position.x)
		flame_base_y.append(f.position.y)

	# Copy frames into a plain Array so lambdas can capture it without type issues
	var frames_copy: Array = []
	for t in anim_frames:
		frames_copy.append(t)
	var has_anim := frames_copy.size() >= 3
	var frame_count := frames_copy.size()

	# â”€â”€ Frame-by-frame fire animation via a persistent Timer node â”€â”€
	if has_anim:
		var frame_idx := [0]
		# Each flame layer starts at a different offset for varied motion
		var offsets: Array[int] = []
		for fi in flames.size():
			offsets.append((fi * 2) % frame_count)

		var anim_timer := Timer.new()
		anim_timer.name = "FlameAnimTimer"
		anim_timer.wait_time = 0.12
		anim_timer.autostart = true
		anim_timer.one_shot = false
		structure.add_child(anim_timer)
		anim_timer.timeout.connect(func() -> void:
			if not is_instance_valid(structure):
				return
			frame_idx[0] = (frame_idx[0] + 1) % frame_count
			for fi in flames.size():
				if not is_instance_valid(flames[fi]):
					continue
				var idx: int = int((frame_idx[0] + offsets[fi]) % frame_count)
				flames[fi].texture = frames_copy[idx] as Texture2D
		)
		# Set initial textures immediately
		for fi in flames.size():
			if is_instance_valid(flames[fi]):
				flames[fi].texture = frames_copy[offsets[fi]] as Texture2D

	# â”€â”€ Flame dance + light flicker (runs every 0.08-0.2s) â”€â”€
	var _tick := [0]
	var _flicker_ref: Array[Callable] = [Callable()]
	_flicker_ref[0] = func() -> void:
		if not is_instance_valid(structure):
			return
		if structure.get_meta(&"campfire_culled", false):
			var retry_tw := structure.create_tween()
			retry_tw.tween_interval(0.5)
			retry_tw.tween_callback(_flicker_ref[0])
			return
		_tick[0] += 1
		var dur := randf_range(0.08, 0.2)
		var tw := structure.create_tween()

		var energy := randf_range(2.0, 5.0)
		var col_g := randf_range(0.3, 0.65)
		tw.tween_property(light, "light_energy", energy, dur)
		tw.parallel().tween_property(light, "light_color", Color(randf_range(0.9, 1.0), col_g, 0.08), dur)

		for fi in flames.size():
			if not is_instance_valid(flames[fi]):
				continue
			var sy := randf_range(0.7, 1.3)
			var sx := randf_range(0.8, 1.2)
			var sway := flame_base_x[fi] + randf_range(-0.12, 0.12)
			var bob := flame_base_y[fi] + randf_range(-0.04, 0.08)
			tw.parallel().tween_property(flames[fi], "scale", Vector3(sx, sy, 1.0), dur)
			tw.parallel().tween_property(flames[fi], "position:x", sway, dur)
			tw.parallel().tween_property(flames[fi], "position:y", bob, dur)
			var heat := randf_range(0.6, 1.0)
			var alpha := clampf(flames[fi].modulate.a + randf_range(-0.08, 0.08), 0.5, 1.0)
			tw.parallel().tween_property(flames[fi], "modulate", Color(1.0, heat, heat * 0.5, alpha), dur)

			if not has_anim and _tick[0] % 4 == fi and tex_a and tex_b:
				flames[fi].texture = tex_b if flames[fi].texture == tex_a else tex_a

		if is_instance_valid(ember):
			var ea := randf_range(0.6, 1.0)
			tw.parallel().tween_property(ember, "modulate", Color(1.0, randf_range(0.3, 0.6), randf_range(0.0, 0.15), ea), dur)

		tw.tween_callback(_flicker_ref[0])
	_flicker_ref[0].call()

	# â”€â”€ Smoke drift (continuous rising wisps) â”€â”€
	var _smoke_ref: Array[Callable] = [Callable()]
	_smoke_ref[0] = func() -> void:
		if not is_instance_valid(structure):
			return
		if structure.get_meta(&"campfire_culled", false):
			var retry_tw := structure.create_tween()
			retry_tw.tween_interval(0.5)
			retry_tw.tween_callback(_smoke_ref[0])
			return
		for si in smokes.size():
			if not is_instance_valid(smokes[si]):
				continue
			var stw := smokes[si].create_tween()
			var life := randf_range(2.0, 3.5)
			var start_y := 0.8 + float(si) * 0.3
			smokes[si].position = Vector3(randf_range(-0.06, 0.06), start_y, randf_range(-0.06, 0.06))
			smokes[si].modulate.a = 0.0
			smokes[si].scale = Vector3(0.7, 0.7, 1.0)
			stw.set_parallel(true)
			stw.tween_property(smokes[si], "position:y", start_y + randf_range(1.5, 2.5), life)
			stw.tween_property(smokes[si], "position:x", smokes[si].position.x + randf_range(-0.2, 0.2), life)
			stw.tween_property(smokes[si], "scale", Vector3(1.5, 1.8, 1.0), life)
			stw.set_parallel(false)
			stw.tween_property(smokes[si], "modulate:a", randf_range(0.12, 0.25), life * 0.2)
			stw.tween_property(smokes[si], "modulate:a", 0.0, life * 0.8)
		var timer := structure.get_tree().create_timer(randf_range(1.8, 3.0))
		timer.timeout.connect(_smoke_ref[0])
	_smoke_ref[0].call()

	# â”€â”€ Ember sparks (small bright particles rising and dying) â”€â”€
	var spark_pool: Array[Sprite3D] = []
	var spark_count := 6
	var spark_img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	spark_img.fill(Color(1.0, 0.7, 0.1))
	var spark_tex := ImageTexture.create_from_image(spark_img)

	for si in spark_count:
		var sp := Sprite3D.new()
		sp.texture = spark_tex
		sp.pixel_size = 0.005
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.transparent = true
		sp.shaded = false
		sp.modulate = Color(1.0, randf_range(0.4, 0.8), 0.0, 0.9)
		sp.visible = false
		structure.add_child(sp)
		spark_pool.append(sp)

	var _spark_idx := [0]
	var _spark_ref: Array[Callable] = [Callable()]
	_spark_ref[0] = func() -> void:
		if not is_instance_valid(structure):
			return
		var sp: Sprite3D = spark_pool[_spark_idx[0] % spark_count]
		_spark_idx[0] += 1
		sp.position = Vector3(randf_range(-0.1, 0.1), randf_range(0.3, 0.6), randf_range(-0.1, 0.1))
		sp.modulate.a = 0.9
		sp.visible = true
		var life := randf_range(0.3, 0.7)
		var tw := sp.create_tween()
		tw.set_parallel(true)
		tw.tween_property(sp, "position:y", sp.position.y + randf_range(0.5, 1.5), life)
		tw.tween_property(sp, "position:x", sp.position.x + randf_range(-0.2, 0.2), life)
		tw.tween_property(sp, "modulate:a", 0.0, life)
		tw.set_parallel(false)
		tw.tween_callback(func() -> void: sp.visible = false)
		var timer := structure.get_tree().create_timer(randf_range(0.2, 0.6))
		timer.timeout.connect(_spark_ref[0])
	_spark_ref[0].call()


func _build_door_visual(structure: StaticBody3D, sz: Vector3, build_id: StringName) -> void:
	_ensure_building_materials()
	var mat: StandardMaterial3D = _bmat_wood if build_id == &"wood_door" else _bmat_stone

	var pivot := AnimatableBody3D.new()
	pivot.name = "DoorPivot"
	pivot.collision_layer = 8
	pivot.collision_mask = 0
	pivot.position = Vector3(-sz.x * 0.5, 0.0, 0.0)
	structure.add_child(pivot)

	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = sz
	panel.mesh = panel_mesh
	panel.set_surface_override_material(0, mat)
	panel.position = Vector3(sz.x * 0.5, sz.y * 0.5, 0.0)
	pivot.add_child(panel)

	var col := CollisionShape3D.new()
	col.name = "DoorCollision"
	var col_box := BoxShape3D.new()
	col_box.size = sz
	col.shape = col_box
	col.position = Vector3(sz.x * 0.5, sz.y * 0.5, 0.0)
	pivot.add_child(col)

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.25, 0.15, 0.05) if build_id == &"wood_door" else Color(0.3, 0.3, 0.32)
	trim_mat.roughness = 0.9
	var trim_w := 0.08
	var trim_d := sz.z + 0.02
	for edge_x in [0.0, sz.x]:
		var trim := MeshInstance3D.new()
		var trim_mesh := BoxMesh.new()
		trim_mesh.size = Vector3(trim_w, sz.y, trim_d)
		trim.mesh = trim_mesh
		trim.set_surface_override_material(0, trim_mat)
		trim.position = Vector3(edge_x, sz.y * 0.5, 0.0)
		pivot.add_child(trim)
	var top_trim := MeshInstance3D.new()
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(sz.x, trim_w, trim_d)
	top_trim.mesh = top_mesh
	top_trim.set_surface_override_material(0, trim_mat)
	top_trim.position = Vector3(sz.x * 0.5, sz.y, 0.0)
	pivot.add_child(top_trim)

	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.4, 0.35, 0.25)
	handle_mat.roughness = 0.7
	handle_mat.metallic = 0.4
	var handle := MeshInstance3D.new()
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.06, 0.3, 0.12)
	handle.mesh = handle_mesh
	handle.set_surface_override_material(0, handle_mat)
	handle.position = Vector3(sz.x * 0.8, sz.y * 0.5, sz.z * 0.5 + 0.06)
	pivot.add_child(handle)


func _toggle_door(door: StaticBody3D) -> void:
	var is_open: bool = door.get_meta("door_open", false)
	var pivot := door.get_node_or_null("DoorPivot") as Node3D
	if not pivot:
		return
	var target_angle := 0.0 if is_open else -PI * 0.5
	var tw := door.create_tween()
	tw.tween_property(pivot, "rotation:y", target_angle, 0.35).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	door.set_meta("door_open", not is_open)
	AudioManager.play_sfx_at("wood_thud", door.global_position, -6.0, 0.15)


func _build_workbench_visual(structure: StaticBody3D, sz: Vector3, _color: Color) -> void:
	_ensure_building_materials()
	var wood_mat := _bmat_wood

	var top := MeshInstance3D.new()
	var top_box := BoxMesh.new()
	top_box.size = Vector3(sz.x, 0.12, sz.z)
	top.mesh = top_box
	top.set_surface_override_material(0, wood_mat)
	top.position.y = sz.y - 0.06
	structure.add_child(top)

	var leg_mat := StandardMaterial3D.new()
	leg_mat.albedo_color = Color(0.35, 0.22, 0.10)
	leg_mat.roughness = 0.9
	var leg_height := sz.y - 0.12
	var leg_mesh := BoxMesh.new()
	leg_mesh.size = Vector3(0.12, leg_height, 0.12)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var leg := MeshInstance3D.new()
		leg.mesh = leg_mesh
		leg.set_surface_override_material(0, leg_mat)
		leg.position = Vector3(corner.x * (sz.x * 0.43), leg_height * 0.5, corner.y * (sz.z * 0.43))
		structure.add_child(leg)

	var brace_mat := StandardMaterial3D.new()
	brace_mat.albedo_color = Color(0.38, 0.25, 0.12)
	brace_mat.roughness = 0.9
	for side_z in [-1.0, 1.0]:
		var brace := MeshInstance3D.new()
		var brace_mesh := BoxMesh.new()
		brace_mesh.size = Vector3(sz.x * 0.86, 0.08, 0.06)
		brace.mesh = brace_mesh
		brace.set_surface_override_material(0, brace_mat)
		brace.position = Vector3(0.0, leg_height * 0.35, side_z * sz.z * 0.43)
		structure.add_child(brace)


func _build_bed_visual(structure: Node3D, sz: Vector3) -> void:
	_ensure_building_materials()
	var frame_h := sz.y * 0.4
	var mattress_h := sz.y * 0.35
	var pillow_h := sz.y * 0.2
	var headboard_h := sz.y * 0.8

	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(sz.x, frame_h, sz.z)
	frame.mesh = frame_mesh
	frame.set_surface_override_material(0, _bmat_wood)
	frame.position.y = frame_h * 0.5
	structure.add_child(frame)

	var mattress_mat := StandardMaterial3D.new()
	mattress_mat.albedo_color = Color(0.75, 0.70, 0.60)
	mattress_mat.roughness = 0.95
	var mattress := MeshInstance3D.new()
	var mattress_mesh := BoxMesh.new()
	mattress_mesh.size = Vector3(sz.x * 0.9, mattress_h, sz.z * 0.92)
	mattress.mesh = mattress_mesh
	mattress.set_surface_override_material(0, mattress_mat)
	mattress.position.y = frame_h + mattress_h * 0.5
	structure.add_child(mattress)

	var blanket_mat := StandardMaterial3D.new()
	blanket_mat.albedo_color = Color(0.35, 0.18, 0.12)
	blanket_mat.roughness = 0.92
	var blanket := MeshInstance3D.new()
	var blanket_mesh := BoxMesh.new()
	blanket_mesh.size = Vector3(sz.x * 0.88, mattress_h * 0.3, sz.z * 0.55)
	blanket.mesh = blanket_mesh
	blanket.set_surface_override_material(0, blanket_mat)
	blanket.position = Vector3(0.0, frame_h + mattress_h + mattress_h * 0.15, -sz.z * 0.15)
	structure.add_child(blanket)

	var pillow_mat := StandardMaterial3D.new()
	pillow_mat.albedo_color = Color(0.85, 0.82, 0.75)
	pillow_mat.roughness = 0.95
	var pillow := MeshInstance3D.new()
	var pillow_mesh := BoxMesh.new()
	pillow_mesh.size = Vector3(sz.x * 0.6, pillow_h, sz.z * 0.15)
	pillow.mesh = pillow_mesh
	pillow.set_surface_override_material(0, pillow_mat)
	pillow.position = Vector3(0.0, frame_h + mattress_h + pillow_h * 0.5, sz.z * 0.38)
	structure.add_child(pillow)

	var headboard := MeshInstance3D.new()
	var headboard_mesh := BoxMesh.new()
	headboard_mesh.size = Vector3(sz.x + 0.06, headboard_h, 0.08)
	headboard.mesh = headboard_mesh
	headboard.set_surface_override_material(0, _bmat_wood)
	headboard.position = Vector3(0.0, headboard_h * 0.5, sz.z * 0.5)
	structure.add_child(headboard)

	var footboard := MeshInstance3D.new()
	var footboard_mesh := BoxMesh.new()
	footboard_mesh.size = Vector3(sz.x + 0.06, frame_h + mattress_h * 0.5, 0.06)
	footboard.mesh = footboard_mesh
	footboard.set_surface_override_material(0, _bmat_wood)
	footboard.position = Vector3(0.0, (frame_h + mattress_h * 0.5) * 0.5, -sz.z * 0.5)
	structure.add_child(footboard)


func _build_map_panel(root: Control) -> void:
	_map_panel = PanelContainer.new()
	_map_panel.name = "MapPanel"
	_map_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.02, 0.04, 0.94)
	_map_panel.add_theme_stylebox_override("panel", bg)
	_map_panel.visible = false
	_map_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "WORLD MAP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	_map_biome_label = Label.new()
	_map_biome_label.name = "BiomeLabel"
	_map_biome_label.text = ""
	_map_biome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_biome_label.add_theme_color_override("font_color", Color(0.7, 0.85, 0.6))
	_map_biome_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_map_biome_label)

	var map_container := Control.new()
	map_container.name = "MapContainer"
	map_container.custom_minimum_size = Vector2(MAP_PX, MAP_PX)

	_map_texture_rect = TextureRect.new()
	_map_texture_rect.name = "MapTexture"
	_map_texture_rect.custom_minimum_size = Vector2(MAP_PX, MAP_PX)
	_map_texture_rect.size = Vector2(MAP_PX, MAP_PX)
	_map_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_map_texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_map_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_container.add_child(_map_texture_rect)

	_add_compass_label(map_container, "N", Vector2(MAP_PX * 0.5 - 4, 10), Color(0.95, 0.85, 0.5))
	_add_compass_label(map_container, "S", Vector2(MAP_PX * 0.5 - 3, MAP_PX - 26), Color(0.6, 0.55, 0.45))
	_add_compass_label(map_container, "E", Vector2(MAP_PX - 22, MAP_PX * 0.5 - 8), Color(0.6, 0.55, 0.45))
	_add_compass_label(map_container, "W", Vector2(10, MAP_PX * 0.5 - 8), Color(0.6, 0.55, 0.45))

	vbox.add_child(map_container)

	var hint := Label.new()
	hint.text = "Scroll to zoom  |  [M] Close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.4, 0.38, 0.32))
	hint.add_theme_font_size_override("font_size", 12)
	vbox.add_child(hint)

	center.add_child(vbox)
	_map_panel.add_child(center)
	root.add_child(_map_panel)

	_map_image = Image.create(MAP_PX, MAP_PX, false, Image.FORMAT_RGBA8)
	_map_image_tex = ImageTexture.new()
	_build_circle_mask()

	_map_fog_noise = FastNoiseLite.new()
	_map_fog_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_map_fog_noise.frequency = 0.015
	_map_fog_noise.fractal_octaves = 3


func _add_compass_label(parent: Control, text: String, pos: Vector2, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)


func _build_circle_mask() -> void:
	_map_circle_mask = Image.create(MAP_PX, MAP_PX, false, Image.FORMAT_RGBA8)
	var half := float(MAP_PX) * 0.5
	var radius := half - 6.0
	var edge_width := 14.0
	var ring_outer := radius + 3.0
	var ring_inner := radius - 2.0
	for y in range(MAP_PX):
		for x in range(MAP_PX):
			var dx := float(x) - half
			var dy := float(y) - half
			var dist := sqrt(dx * dx + dy * dy)
			if dist > ring_outer:
				_map_circle_mask.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
			elif dist > radius:
				# Ornamental ring border
				var ring_t := 1.0 - (dist - radius) / (ring_outer - radius)
				var angle := atan2(dy, dx)
				var notch := absf(sin(angle * 32.0))
				var brightness := lerpf(0.25, 0.45, notch) * ring_t
				_map_circle_mask.set_pixel(x, y, Color(brightness, brightness * 0.9, brightness * 0.7, 1.0))
			elif dist > ring_inner:
				# Inner ring edge
				_map_circle_mask.set_pixel(x, y, Color(0.3, 0.27, 0.2, 1.0))
			elif dist > ring_inner - edge_width:
				var t := (dist - (ring_inner - edge_width)) / edge_width
				_map_circle_mask.set_pixel(x, y, Color(1.0, 1.0, 1.0, t * 0.15 + 0.85))
			else:
				_map_circle_mask.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))


func _refresh_map() -> void:
	if not _map_panel or not _map_image or not _map_texture_rect:
		return

	var transparent := Color(0, 0, 0, 0)
	_map_image.fill(transparent)

	var wg := _find_world_generator()
	if not wg:
		_map_image_tex.set_image(_map_image)
		if _map_texture_rect.texture != _map_image_tex:
			_map_texture_rect.texture = _map_image_tex
		return

	var player_pos := wg.get_world_position(self)
	var center_zone: Vector2i = wg.world_to_zone(player_pos)
	var half_px := MAP_PX / 2
	var explored: Dictionary = wg._explored_zones
	var cache: Dictionary = wg._zone_biome_cache
	var zone_size: float = wg.ZONE_SIZE

	if _map_biome_label:
		var current_biome: StringName = wg.get_biome_at(player_pos)
		var current_micro: StringName = wg.get_microbiome_at(player_pos)
		var display := _biome_display_name(current_biome)
		if current_micro != &"none":
			display += " - " + _microbiome_display_name(current_micro)
		_map_biome_label.text = display

	var zones_per_pixel: float = _map_zoom / float(half_px)
	var water_col := Color(0.12, 0.28, 0.52)
	var water_shallow := Color(0.18, 0.38, 0.55)
	var unexplored := Color(0.08, 0.08, 0.10, 1.0)

	var stride := 2
	var map_zone_cache: Dictionary = {}

	for py in range(0, MAP_PX, stride):
		for px in range(0, MAP_PX, stride):
			var mask_pixel := _map_circle_mask.get_pixel(px, py)
			if mask_pixel.a < 0.01:
				continue

			if mask_pixel.r < 0.9 and mask_pixel.g < 0.9 and mask_pixel.a > 0.5 and (mask_pixel.r > 0.05 or mask_pixel.g > 0.05):
				var ring_col := Color(mask_pixel.r, mask_pixel.g, mask_pixel.b, mask_pixel.a)
				for sy in stride:
					for sx in stride:
						if px + sx < MAP_PX and py + sy < MAP_PX:
							_map_image.set_pixel(px + sx, py + sy, ring_col)
				continue

			var zone_fx: float = float(px - half_px) * zones_per_pixel
			var zone_fz: float = float(py - half_px) * zones_per_pixel
			var zone_coord := Vector2i(
				center_zone.x + roundi(zone_fx),
				center_zone.y + roundi(zone_fz))

			var col: Color
			if map_zone_cache.has(zone_coord):
				col = map_zone_cache[zone_coord] as Color
			elif explored.has(zone_coord):
				var biome: StringName = cache.get(zone_coord, &"hearthlands") as StringName
				var micro := wg.get_microbiome_at_zone(zone_coord)
				var zx := (float(zone_coord.x) + 0.5) * zone_size
				var zz := (float(zone_coord.y) + 0.5) * zone_size
				var zh := wg.get_height_at(zx, zz)
				if wg._zone_has_water(zone_coord) or zh < wg.WATER_LEVEL:
					var depth := clampf((wg.WATER_LEVEL - zh) / 6.0, 0.0, 1.0)
					col = water_shallow.lerp(water_col, depth)
				else:
					col = _biome_map_color(biome, micro)
					var bright := clampf(lerpf(0.7, 1.25, (zh + 5.0) / 30.0), 0.0, 1.0)
					col = Color(
						clampf(col.r * bright, 0.0, 1.0),
						clampf(col.g * bright, 0.0, 1.0),
						clampf(col.b * bright, 0.0, 1.0))
				map_zone_cache[zone_coord] = col
			else:
				col = unexplored
				map_zone_cache[zone_coord] = col

			for sy in stride:
				for sx in stride:
					if px + sx < MAP_PX and py + sy < MAP_PX:
						_map_image.set_pixel(px + sx, py + sy, col)

	# â”€â”€ Structure markers â”€â”€
	_draw_structure_markers(half_px, zones_per_pixel, zone_size)

	# â”€â”€ Player marker â€” directional arrow â”€â”€
	_draw_player_arrow(half_px)

	_map_image_tex.set_image(_map_image)
	if _map_texture_rect.texture != _map_image_tex:
		_map_texture_rect.texture = _map_image_tex


func _draw_player_arrow(half_px: int) -> void:
	_draw_arrow_on_image(_map_image, half_px, 1.0)


func _point_in_arrow(pt: Vector2, verts: Array[Vector2], scale: float) -> bool:
	var s0 := verts[0] * scale
	var s1 := verts[1] * scale
	var s2 := verts[2] * scale
	var s3 := verts[3] * scale
	return _point_in_tri(pt, s0, s1, s2) or _point_in_tri(pt, s0, s2, s3)


func _point_in_tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
	var d1 := (p.x - b.x) * (a.y - b.y) - (a.x - b.x) * (p.y - b.y)
	var d2 := (p.x - c.x) * (b.y - c.y) - (b.x - c.x) * (p.y - c.y)
	var d3 := (p.x - a.x) * (c.y - a.y) - (c.x - a.x) * (p.y - a.y)
	var has_neg := (d1 < 0.0) or (d2 < 0.0) or (d3 < 0.0)
	var has_pos := (d1 > 0.0) or (d2 > 0.0) or (d3 > 0.0)
	return not (has_neg and has_pos)


func _draw_structure_markers(half_px: int, zones_per_pixel: float, zone_size: float) -> void:
	var marker_col := Color(0.9, 0.75, 0.3)
	var cave_col := Color(0.5, 0.35, 0.2)

	for node in get_tree().get_nodes_in_group(&"structures"):
		var n3d := node as Node3D
		if not n3d:
			continue
		_draw_map_dot(n3d.global_position, marker_col, 2, half_px, zones_per_pixel, zone_size)

	for node in get_tree().get_nodes_in_group(&"cave_entrances"):
		var n3d := node as Node3D
		if not n3d:
			continue
		_draw_map_dot(n3d.global_position, cave_col, 2, half_px, zones_per_pixel, zone_size)


func _draw_map_dot(world_pos: Vector3, color: Color, radius: int, half_px: int, zones_per_pixel: float, zone_size: float) -> void:
	if zones_per_pixel < 0.001:
		return
	var dx_world := world_pos.x - global_position.x
	var dz_world := world_pos.z - global_position.z
	var px_x := half_px + roundi(dx_world / (zones_per_pixel * zone_size))
	var px_y := half_px + roundi(dz_world / (zones_per_pixel * zone_size))
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var fx := px_x + dx
				var fy := px_y + dy
				if fx >= 0 and fx < MAP_PX and fy >= 0 and fy < MAP_PX:
					_map_image.set_pixel(fx, fy, color)


func _biome_map_color(biome: StringName, micro: StringName = &"none") -> Color:
	if biome == &"hearthlands" and micro != &"none":
		match micro:
			&"meadow":        return Color(0.42, 0.62, 0.28)
			&"forest":        return Color(0.2, 0.4, 0.15)
			&"birch_forest":  return Color(0.35, 0.55, 0.22)
			&"hills":         return Color(0.45, 0.52, 0.32)
			&"riverside":     return Color(0.32, 0.52, 0.35)
	if biome == &"ocean":
		return Color(0.1, 0.2, 0.4)
	return Color(0.35, 0.55, 0.25)


func _biome_display_name(biome: StringName) -> String:
	if biome == &"ocean":
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


var _cached_wg: WorldGenerator
func _find_world_generator() -> WorldGenerator:
	if is_instance_valid(_cached_wg):
		return _cached_wg
	var wgs := get_tree().get_nodes_in_group(&"world_generator")
	for n in wgs:
		if n is WorldGenerator:
			_cached_wg = n as WorldGenerator
			return _cached_wg
	var root := get_tree().current_scene
	for child in root.get_children():
		if child is WorldGenerator:
			_cached_wg = child as WorldGenerator
			return _cached_wg
	for child in root.get_children():
		for grandchild in child.get_children():
			if grandchild is WorldGenerator:
				_cached_wg = grandchild as WorldGenerator
				return _cached_wg
	return null


# ===================================================================
# TOOLTIP
# ===================================================================

func _show_tooltip_for_item(item_id: StringName) -> void:
	if item_id == &"" or not _tooltip_panel:
		_hide_tooltip()
		return
	var data: Dictionary = ItemDatabase.get_item(item_id)
	if data.is_empty():
		_hide_tooltip()
		return

	var display_name := ItemDatabase.get_display_name(item_id)
	var parsed_tip := ItemDatabase.parse_star_id(item_id)
	var tip_stars: int = parsed_tip["stars"]

	var text := ""
	if tip_stars > 0:
		var rc: Color = ItemDatabase.get_rarity_color(tip_stars)
		var hex := "#%02x%02x%02x" % [int(rc.r * 255), int(rc.g * 255), int(rc.b * 255)]
		var rarity_name: String = ItemDatabase.RARITY_NAMES[clampi(tip_stars, 0, 5)]
		text += "[color=%s][b]%s[/b] %s[/color]\n" % [hex, display_name, "*".repeat(tip_stars)]
		text += "[color=%s]%s[/color]\n" % [hex, rarity_name]
	elif data.has("quality_color"):
		var qc: Color = data["quality_color"] as Color
		var qhex := "#%02x%02x%02x" % [int(qc.r * 255), int(qc.g * 255), int(qc.b * 255)]
		var qname: String = data.get("quality_name", "Poor") as String
		text += "[color=%s][b]%s[/b][/color]\n" % [qhex, display_name]
		text += "[color=%s]%s[/color]\n" % [qhex, qname]
	else:
		text += "[b]%s[/b]\n" % display_name

	var item_type: String = data.get("type", "material") as String
	if item_type == "weapon" and data.has("weapon_class"):
		text += "Type: %s\n" % str(data["weapon_class"]).capitalize()
	elif item_type == "armor" and data.has("armor_slot"):
		text += "Type: %s Armor\n" % str(data["armor_slot"]).capitalize()
	else:
		text += "Type: %s\n" % item_type.capitalize()

	if data.has("damage"):
		text += "Damage: %.0f\n" % float(data["damage"])
	if data.has("attack_speed"):
		text += "Speed: %.2fs\n" % float(data["attack_speed"])
	if data.has("range"):
		text += "Range: %.1f\n" % float(data["range"])
	if data.has("stamina_cost"):
		text += "Stamina: %.0f\n" % float(data["stamina_cost"])
	if data.has("knockback"):
		text += "Knockback: %.0f\n" % float(data["knockback"])
	if data.has("hands"):
		text += "Hands: %s\n" % str(data["hands"])
	if data.has("armor"):
		var armor_f := float(data["armor"])
		text += "Armor: %.1f\n" % armor_f
	if data.has("description"):
		text += "\n%s" % str(data["description"])

	# Affixes section
	var tip_affixes: Array = parsed_tip.get("affixes", [])
	var tip_rolls: Dictionary = parsed_tip.get("affix_rolls", {})
	if not tip_affixes.is_empty():
		text += "\n\n[color=#666666]â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€[/color]"
		for affix_id in tip_affixes:
			var affix_data: Dictionary = ItemDatabase.get_affix_data(affix_id)
			if affix_data.is_empty():
				continue
			var affix_name: String = affix_data.get("name", str(affix_id)) as String
			var roll: float = float(tip_rolls.get(affix_id, 0.5))
			var affix_desc: String = ItemDatabase.format_affix_description(affix_id, roll)
			text += "\n[color=#ffd700]%s[/color]" % affix_name
			if affix_desc != "":
				text += "\n[color=#aaaaaa]%s[/color]" % affix_desc

	_tooltip_label.fit_content = true
	_tooltip_label.scroll_active = false
	_tooltip_label.custom_minimum_size.y = 0
	_tooltip_label.text = text.strip_edges()
	_tooltip_panel.reset_size()
	_tooltip_panel.visible = true
	_cap_tooltip_height()
	_tooltip_panel.position = _clamp_tooltip_pos(_hud_root.get_local_mouse_position())


func _show_grouped_tooltip(base_id: StringName, variants: Dictionary, display_id: StringName) -> void:
	if not _tooltip_panel:
		return
	var data: Dictionary = ItemDatabase.get_item(base_id)
	if data.is_empty():
		data = ItemDatabase.get_item(display_id)
	if data.is_empty():
		_hide_tooltip()
		return

	var display_name: String = str(data.get("name", str(base_id)))
	var item_type: String = str(data.get("type", "material"))

	var total := 0
	var max_stars := 0
	for sv in variants.keys():
		if int(sv) > max_stars:
			max_stars = int(sv)
		total += int(variants[sv])

	var text := "[b]%s[/b]  Ã—%d\n" % [display_name, total]
	text += "Type: %s\n" % item_type.capitalize()

	if data.has("damage"):
		text += "Damage: %.0f\n" % float(data["damage"])
	if data.has("armor"):
		text += "Armor: %.0f\n" % float(data["armor"])
	if data.has("armor_slot"):
		text += "Slot: %s\n" % str(data["armor_slot"]).capitalize()
	if Inventory.is_equipped(display_id):
		text += "â—† Equipped\n"
		text += "[color=#999999]Right-click to unequip[/color]\n"
	elif data.has("armor_slot"):
		text += "[color=#999999]Right-click to equip[/color]\n"

	if variants.size() > 1 or max_stars > 0:
		text += "\nQuality breakdown:\n"
		var star_keys: Array = variants.keys()
		star_keys.sort()
		for sv in star_keys:
			var s: int = int(sv)
			var amt: int = int(variants[sv])
			var rarity_name := ItemDatabase.get_rarity_name(s)
			var c: Color = ItemDatabase.get_rarity_color(s)
			var hex := "#%02x%02x%02x" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]
			if s == 0:
				text += "  [color=%s]Common: %d[/color]\n" % [hex, amt]
			else:
				text += "  [color=%s]%s %s: %d[/color]\n" % [hex, "*".repeat(s), rarity_name, amt]

	if data.has("description"):
		text += "\n%s" % str(data["description"])

	_tooltip_label.fit_content = true
	_tooltip_label.scroll_active = false
	_tooltip_label.custom_minimum_size.y = 0
	_tooltip_label.text = text.strip_edges()
	_tooltip_panel.reset_size()
	_tooltip_panel.visible = true
	_cap_tooltip_height()
	_tooltip_panel.position = _clamp_tooltip_pos(_hud_root.get_local_mouse_position())


func _clamp_tooltip_pos(mouse_pos: Vector2) -> Vector2:
	var vp_size := _hud_root.get_viewport_rect().size
	var tip_size := _tooltip_panel.size
	var margin := 8.0
	var pos := mouse_pos + Vector2(16, 8)
	if pos.x + tip_size.x + margin > vp_size.x:
		pos.x = mouse_pos.x - tip_size.x - 16
	if pos.y + tip_size.y + margin > vp_size.y:
		pos.y = vp_size.y - tip_size.y - margin
	pos.x = maxf(pos.x, margin)
	pos.y = maxf(pos.y, margin)
	return pos


func _hide_tooltip() -> void:
	if _tooltip_panel:
		_tooltip_panel.visible = false


func _on_hotbar_hover(slot_idx: int) -> void:
	var grouped: Array = Inventory.get_grouped_item_list()
	if slot_idx >= 0 and slot_idx < grouped.size():
		var entry: Dictionary = grouped[slot_idx]
		var base_id: StringName = entry["base_id"]
		var variants: Dictionary = entry["variants"]
		var display_id: StringName = entry.get("exact_id", base_id) as StringName
		if entry.get("is_grouped", false):
			_show_grouped_tooltip(base_id, variants, display_id)
		else:
			_show_tooltip_for_item(display_id)
		return
	_hide_tooltip()


# ===================================================================
# INVENTORY REFRESH â€” drag weapons, right-click armor
# ===================================================================

func _refresh_inventory_ui() -> void:
	if not _inventory_grid:
		return
	for child in _inventory_grid.get_children():
		_inventory_grid.remove_child(child)
		child.free()

	_cached_grouped = Inventory.get_grouped_item_list()
	var grouped: Array = _cached_grouped

	const TOTAL_SLOTS := 64

	for i in range(TOTAL_SLOTS):
		var slot := PanelContainer.new()
		slot.custom_minimum_size = Vector2(60, 60)
		var slot_style := StyleBoxFlat.new()
		slot_style.bg_color = Color(0.12, 0.12, 0.16, 0.8)
		slot_style.border_color = Color(0.25, 0.25, 0.3)
		slot_style.set_border_width_all(1)
		slot_style.set_corner_radius_all(3)
		slot_style.set_content_margin_all(2)

		if i < grouped.size():
			var entry: Dictionary = grouped[i]
			var base_id: StringName = entry["base_id"]
			var total: int = entry["total"]
			var variants: Dictionary = entry["variants"]
			var display_id: StringName = entry.get("exact_id", base_id) as StringName
			var item_equipped := Inventory.is_equipped(display_id)
			var is_grouped: bool = entry.get("is_grouped", false)

			# Rarity border for equipment (ungrouped items with stars)
			if not is_grouped:
				var parsed_slot := ItemDatabase.parse_star_id(display_id)
				var slot_stars: int = parsed_slot["stars"]
				if slot_stars > 0:
					var rarity_col: Color = ItemDatabase.get_rarity_color(slot_stars)
					slot_style.border_color = rarity_col
					slot_style.set_border_width_all(2)

			var stack := Control.new()
			stack.custom_minimum_size = Vector2(56, 56)
			stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var icon_rect := TextureRect.new()
			icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var icon_tex: Texture2D = ItemDatabase.get_icon(base_id)
			if not icon_tex:
				icon_tex = ItemDatabase.get_icon(display_id)
			if icon_tex:
				icon_rect.texture = icon_tex
			else:
				var placeholder := PlaceholderTexture2D.new()
				placeholder.size = Vector2(32, 32)
				icon_rect.texture = placeholder
				icon_rect.modulate = _get_item_fallback_color(base_id)
			stack.add_child(icon_rect)

			if total > 1:
				var amt_lbl := Label.new()
				amt_lbl.text = str(total)
				amt_lbl.add_theme_font_size_override("font_size", 11)
				amt_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.8))
				amt_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
				amt_lbl.add_theme_constant_override("shadow_offset_x", 1)
				amt_lbl.add_theme_constant_override("shadow_offset_y", 1)
				amt_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				amt_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
				amt_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				amt_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				stack.add_child(amt_lbl)

			slot.add_child(stack)
			if is_grouped:
				slot.mouse_entered.connect(_show_grouped_tooltip.bind(base_id, variants, display_id))
			else:
				slot.mouse_entered.connect(_show_tooltip_for_item.bind(display_id))
			slot.mouse_exited.connect(_hide_tooltip)

		slot.add_theme_stylebox_override("panel", slot_style)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.gui_input.connect(_on_inv_slot_gui_input.bind(i))
		_inventory_grid.add_child(slot)

	_recheck_inventory_tooltip()
	_refresh_crafting_ui()


func _refresh_crafting_ui() -> void:
	if not _crafting_grid:
		return
	for child in _crafting_grid.get_children():
		_crafting_grid.remove_child(child)
		child.free()

	var recipes: Array = ItemDatabase.get_hand_recipes()
	for recipe_entry in recipes:
		var item_id: StringName = recipe_entry["id"] as StringName
		var data: Dictionary = recipe_entry["data"] as Dictionary
		var hand_type: String = str(data.get("type", "material"))
		var hand_is_equip := hand_type in ["weapon", "armor"]
		var hand_max: int = 5 if hand_is_equip else 0
		var can_make: bool = ItemDatabase.can_craft(item_id, hand_max, 0)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(36, 36)
		icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_tex: Texture2D = ItemDatabase.get_icon(item_id)
		if icon_tex:
			icon_rect.texture = icon_tex
		else:
			var ph := PlaceholderTexture2D.new()
			ph.size = Vector2(32, 32)
			icon_rect.texture = ph
			icon_rect.modulate = _get_item_fallback_color(item_id)
		row.add_child(icon_rect)

		var info_vb := VBoxContainer.new()
		info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vb.add_theme_constant_override("separation", 0)

		var name_lbl := Label.new()
		name_lbl.text = data.get("name", str(item_id)) as String
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color.WHITE if can_make else Color(0.5, 0.45, 0.4))
		info_vb.add_child(name_lbl)

		var recipe_arr: Array = data.get("recipe", []) as Array
		var cost_text := ""
		for ingredient: Dictionary in recipe_arr:
			var req_id: StringName = StringName(ingredient.get("item_id", ""))
			var req_amt: int = int(ingredient.get("amount", 0))
			var req_data: Dictionary = ItemDatabase.get_item(req_id)
			var req_name: String = req_data.get("name", str(req_id)) as String
			var have: int = Inventory.get_amount_capped_star(req_id, hand_max, 0) if not hand_is_equip else Inventory.get_amount_any_star(req_id)
			var have_color := "aaffaa" if (have >= req_amt or Inventory.has_free_craft()) else "ff6666"
			if cost_text != "":
				cost_text += "  "
			cost_text += "[color=#%s]%s %d/%d[/color]" % [have_color, req_name, have, req_amt]

		var cost_lbl := RichTextLabel.new()
		cost_lbl.bbcode_enabled = true
		cost_lbl.text = cost_text
		cost_lbl.fit_content = true
		cost_lbl.scroll_active = false
		cost_lbl.custom_minimum_size.y = 16
		cost_lbl.add_theme_font_size_override("normal_font_size", 10)
		info_vb.add_child(cost_lbl)

		row.add_child(info_vb)

		var btn := Button.new()
		btn.text = "Craft"
		btn.disabled = not can_make
		btn.custom_minimum_size = Vector2(60, 30)
		btn.pressed.connect(_on_craft_pressed.bind(item_id))
		row.add_child(btn)

		_crafting_grid.add_child(row)


func _on_craft_pressed(item_id: StringName) -> void:
	var crafted_id: StringName = ItemDatabase.craft_item(item_id)
	if crafted_id != &"":
		_spawn_craft_text(crafted_id)
		_refresh_inventory_ui()


func _spawn_craft_text(crafted_id: StringName) -> void:
	var parsed := ItemDatabase.parse_star_id(crafted_id)
	var stars: int = parsed["stars"]
	var display := ItemDatabase.get_display_name(crafted_id)
	var data := ItemDatabase.get_item(crafted_id)
	var amount: int = int(data.get("craft_amount", 1))

	var num := DamageNumber.new()
	num.font_size = 28
	num.pixel_size = 0.01
	num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	num.no_depth_test = true
	num.modulate = Color.WHITE
	num.outline_modulate = Color.BLACK
	num.outline_size = 6
	num._velocity = Vector3(0, 2.0, 0)

	var prefix := "+%d " % amount if amount > 1 else ""
	if stars > 0:
		num.text = "%s%s " % [prefix, display]
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var star_lbl := Label3D.new()
		star_lbl.text = "★".repeat(stars)
		star_lbl.font_size = 28
		star_lbl.pixel_size = 0.01
		star_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		star_lbl.no_depth_test = true
		star_lbl.modulate = ItemDatabase.get_rarity_color(stars)
		star_lbl.outline_modulate = Color.BLACK
		star_lbl.outline_size = 6
		star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		num.add_child(star_lbl)
	else:
		num.text = "%s%s" % [prefix, display]

	get_tree().current_scene.add_child(num)
	var cam := get_viewport().get_camera_3d()
	var right_offset := cam.global_transform.basis.x * 5.1 if cam else Vector3(5.1, 0, 0)
	num.global_position = global_position + Vector3(0, 2.5, 0) + right_offset


func _on_inv_slot_gui_input(event: InputEvent, slot_idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if slot_idx >= _cached_grouped.size():
			return
		var entry: Dictionary = _cached_grouped[slot_idx]
		var raw_indices: Array = entry.get("raw_indices", []) as Array
		var is_grouped: bool = entry.get("is_grouped", false)
		var entry_id: StringName = entry.get("exact_id", entry["base_id"]) as StringName
		if _chest_open and _chest_node and _chest_node.has_meta("chest_contents") and mb.shift_pressed:
			if (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT) and mb.pressed:
				var half_only := mb.button_index == MOUSE_BUTTON_LEFT
				if is_grouped:
					var base: StringName = entry["base_id"]
					var variants: Dictionary = entry["variants"]
					for star_level in variants.keys():
						var vid: StringName = ItemDatabase.make_star_id(base, int(star_level))
						_interaction.deposit_item_to_chest(vid, half_only)
				elif not raw_indices.is_empty():
					_interaction.deposit_inv_slot_to_chest(int(raw_indices[0]), half_only)
				return
		if mb.shift_pressed and mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not _chest_open:
			_discard_inventory_slot.call_deferred(entry)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _dragging_item == &"":
				if not raw_indices.is_empty():
					var raw_idx: int = int(raw_indices[0])
					_start_drag(entry_id, raw_idx)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var data: Dictionary = ItemDatabase.get_item(entry_id)
			var item_type: String = str(data.get("type", ""))
			if data.has("armor_slot") and (item_type == "armor" or item_type == "weapon" or item_type == "tool"):
				_start_equip_progress(entry_id, slot_idx)
			else:
				_discard_inventory_slot.call_deferred(entry)


func _equip_item_deferred(entry_id: StringName) -> void:
	Inventory.equip_armor(entry_id)
	_refresh_inventory_ui()
	_refresh_equip_bar()

func _unequip_item_deferred(slot_name: String) -> void:
	Inventory.unequip_armor(slot_name)
	_refresh_inventory_ui()
	_refresh_equip_bar()

func _discard_inventory_slot(entry: Dictionary) -> void:
	var is_grouped: bool = entry.get("is_grouped", false)
	var base_id: StringName = entry["base_id"]
	if is_grouped:
		var variants: Dictionary = entry.get("variants", {})
		for star_level in variants.keys():
			var vid: StringName = ItemDatabase.make_star_id(base_id, int(star_level))
			var qty: int = int(variants[star_level])
			if qty > 0 and Inventory.remove_item(vid, qty):
				_drop_item_on_ground(vid, qty, 60.0)
	else:
		var exact_id: StringName = entry.get("exact_id", base_id) as StringName
		var qty: int = Inventory.get_amount(exact_id)
		if qty > 0 and Inventory.remove_item(exact_id, qty):
			_drop_item_on_ground(exact_id, qty, 60.0)
	_refresh_inventory_ui()


func _start_equip_progress(item_id: StringName, slot_idx: int) -> void:
	if _equip_progresses.has(slot_idx):
		_cancel_equip_slot(slot_idx)
	var entry := {"item": item_id, "progress": 0.0, "bar": null}
	if _inventory_grid and slot_idx < _inventory_grid.get_child_count():
		var slot_node: Control = _inventory_grid.get_child(slot_idx) as Control
		if slot_node:
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(56, 6)
			bar.max_value = 1.0
			bar.value = 0.0
			bar.show_percentage = false
			bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			bar.offset_top = -8
			bar.offset_bottom = -2
			bar.offset_left = 2
			bar.offset_right = -2
			var bg_style := StyleBoxFlat.new()
			bg_style.bg_color = Color(0.1, 0.1, 0.1, 0.8)
			bg_style.set_corner_radius_all(2)
			bar.add_theme_stylebox_override("background", bg_style)
			var fill_style := StyleBoxFlat.new()
			fill_style.bg_color = Color(0.9, 0.75, 0.3, 0.9)
			fill_style.set_corner_radius_all(2)
			bar.add_theme_stylebox_override("fill", fill_style)
			slot_node.add_child(bar)
			entry["bar"] = bar
	_equip_progresses[slot_idx] = entry


func _cancel_equip_slot(slot_idx: int) -> void:
	var entry: Dictionary = _equip_progresses.get(slot_idx, {})
	var bar = entry.get("bar")
	if bar and is_instance_valid(bar):
		bar.queue_free()
	_equip_progresses.erase(slot_idx)

func _cancel_equip_progress() -> void:
	for idx in _equip_progresses.keys():
		_cancel_equip_slot(idx)


func _tick_equip_progress(delta: float) -> void:
	if _equip_progresses.is_empty():
		return
	var finished: Array = []
	for idx in _equip_progresses:
		var entry: Dictionary = _equip_progresses[idx]
		entry["progress"] += delta
		var bar = entry.get("bar")
		if bar and is_instance_valid(bar):
			bar.value = clampf(entry["progress"] / EQUIP_HOLD_TIME, 0.0, 1.0)
		if entry["progress"] >= EQUIP_HOLD_TIME:
			finished.append(idx)
	for idx in finished:
		var item_id: StringName = StringName(_equip_progresses[idx]["item"])
		_cancel_equip_slot(idx)
		_equip_item_deferred.call_deferred(item_id)


func _recheck_inventory_tooltip() -> void:
	if not _inventory_panel or not _inventory_panel.visible:
		return
	if not _inventory_grid or not _hud_root:
		return
	var mouse_pos := _hud_root.get_local_mouse_position()
	for i in range(_inventory_grid.get_child_count()):
		var slot: Control = _inventory_grid.get_child(i) as Control
		if slot and i < _cached_grouped.size():
			var slot_rect: Rect2 = slot.get_global_rect()
			if slot_rect.has_point(mouse_pos):
				var entry: Dictionary = _cached_grouped[i]
				var display_id: StringName = entry.get("exact_id", entry["base_id"]) as StringName
				if entry.get("is_grouped", false):
					var variants: Dictionary = entry["variants"]
					_show_grouped_tooltip(entry["base_id"], variants, display_id)
				else:
					_show_tooltip_for_item(display_id)
				return
	_hide_tooltip()


func _on_inventory_hover(item_id: StringName) -> void:
	_show_tooltip_for_item(item_id)


func _start_drag(item_id: StringName, from_slot: int) -> void:
	_dragging_item = item_id
	_drag_from_slot = from_slot
	if _drag_icon:
		var icon_tex: Texture2D = ItemDatabase.get_icon(item_id)
		if icon_tex:
			_drag_icon.texture = icon_tex
		else:
			var ph := PlaceholderTexture2D.new()
			ph.size = Vector2(32, 32)
			_drag_icon.texture = ph
		_drag_icon.visible = true
		_drag_icon.position = _hud_root.get_local_mouse_position() - Vector2(16, 16)


func _cancel_drag() -> void:
	_dragging_item = &""
	_drag_from_slot = -1
	if _drag_icon:
		_drag_icon.visible = false


func _drop_dragged_item() -> void:
	var item_id := _dragging_item
	if item_id == &"":
		_cancel_drag()
		return
	var vis_slot := -1
	for i in range(_cached_grouped.size()):
		var e: Dictionary = _cached_grouped[i]
		var eid: StringName = e.get("exact_id", e["base_id"]) as StringName
		if eid == item_id:
			vis_slot = i
			break
	if vis_slot >= 0 and vis_slot < _cached_grouped.size():
		_discard_inventory_slot(_cached_grouped[vis_slot])
	else:
		var qty: int = Inventory.get_amount(item_id)
		if qty > 0 and Inventory.remove_item(item_id, qty):
			_drop_item_on_ground(item_id, qty, 60.0)
		_refresh_inventory_ui()
	_cancel_drag()


func _get_inv_slot_under_mouse() -> int:
	if not _inventory_grid or not _hud_root:
		return -1
	var mouse_pos := _hud_root.get_global_mouse_position()
	for i in range(_inventory_grid.get_child_count()):
		var slot: Control = _inventory_grid.get_child(i) as Control
		if slot and slot.get_global_rect().has_point(mouse_pos):
			return i
	return -1


func _finish_drag(to_visual_slot: int) -> void:
	if _drag_from_slot < 0:
		_cancel_drag()
		return
	if to_visual_slot < _cached_grouped.size():
		var to_entry: Dictionary = _cached_grouped[to_visual_slot]
		var to_raw: Array = to_entry.get("raw_indices", []) as Array
		var raw_to := to_visual_slot
		if not to_raw.is_empty():
			raw_to = int(to_raw[0])
		if _drag_from_slot != raw_to:
			Inventory.swap_slots(_drag_from_slot, raw_to)
			_refresh_inventory_ui()
			_update_hotbar_selection()
	else:
		var from_visual := -1
		for i in range(_cached_grouped.size()):
			var entry: Dictionary = _cached_grouped[i]
			var raw_indices: Array = entry.get("raw_indices", []) as Array
			for ri in raw_indices:
				if int(ri) == _drag_from_slot:
					from_visual = i
					break
			if from_visual >= 0:
				break
		if from_visual >= 0 and from_visual < _cached_grouped.size() - 1:
			var entry: Dictionary = _cached_grouped[from_visual]
			var raw_indices: Array = entry.get("raw_indices", []) as Array
			Inventory.move_group_to_end(raw_indices)
			_refresh_inventory_ui()
			_update_hotbar_selection()
	_cancel_drag()


var _pc_proc_timer := 0.0
var _pc_proc_max_total := 0.0
var _pc_proc_max_minimap := 0.0
var _pc_proc_max_physics := 0.0

func _process(delta: float) -> void:
	var _pc_t0 := Time.get_ticks_usec()

	if _fps_label:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()

	_tick_equip_progress(delta)
	if _hud_module:
		_hud_module.update_chat_fade(self, delta)

	# Phase 5: Clients report player data to host for save on disconnect
	if is_multiplayer_authority() and NetworkManager.is_connected_to_game() and not NetworkManager.is_server():
		_report_data_timer += delta
		if _report_data_timer >= _REPORT_DATA_INTERVAL:
			_report_data_timer = 0.0
			_report_player_data_to_host()

	if _chest_open and _chest_node:
		if global_position.distance_to(_chest_node.global_position) > 4.0:
			_interaction.close_chest()

	if _dragging_item != &"" and _hud_root:
		if _drag_icon and _drag_icon.visible:
			_drag_icon.position = _hud_root.get_local_mouse_position() - Vector2(16, 16)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var drop_slot := _get_inv_slot_under_mouse()
			if drop_slot >= 0:
				_finish_drag(drop_slot)
			elif _try_drop_on_equip_bar():
				pass
			else:
				var mouse_over_panel := false
				if _inventory_panel and _inventory_panel.visible:
					mouse_over_panel = _inventory_panel.get_global_rect().has_point(_hud_root.get_global_mouse_position())
				if not mouse_over_panel and _dragging_item != &"" and _drag_from_slot >= 0:
					_drop_dragged_item()
				else:
					_cancel_drag()

	if _tooltip_panel and _tooltip_panel.visible and _hud_root:
		_tooltip_panel.position = _clamp_tooltip_pos(_hud_root.get_local_mouse_position())

	# Minimap: longer interval when idle, shorter when moving
	var _pc_tmm := Time.get_ticks_usec()
	if not _minimap_paused:
		_minimap_refresh_timer += delta
		var refresh_interval := 0.8 if velocity.length_squared() > 1.0 else 2.0
		if _minimap_needs_refresh or _minimap_refresh_timer >= refresh_interval:
			_minimap_refresh_timer = 0.0
			_refresh_minimap()
	var _minimap_ms := float(Time.get_ticks_usec() - _pc_tmm) / 1000.0
	_pc_proc_max_minimap = maxf(_pc_proc_max_minimap, _minimap_ms)

	if _map_open:
		_map_fog_time += delta
		var prev_zoom := _map_zoom
		_map_zoom = lerpf(_map_zoom, _map_zoom_target, clampf(MAP_ZOOM_SPEED * delta, 0.0, 1.0))
		if absf(_map_zoom - _map_zoom_target) < 0.02:
			_map_zoom = _map_zoom_target
		var moved := global_position.distance_squared_to(_map_last_player_pos) > 0.5
		_map_refresh_timer += delta
		var periodic := _map_refresh_timer >= 0.5
		var zoom_changed := absf(_map_zoom - prev_zoom) > 0.03
		var needs_refresh := _map_dirty or moved or periodic or zoom_changed
		if needs_refresh and _map_refresh_timer >= 0.1:
			_map_last_player_pos = global_position
			_map_refresh_timer = 0.0
			_refresh_map()
			_map_dirty = false

	var _pc_total_ms := float(Time.get_ticks_usec() - _pc_t0) / 1000.0
	_pc_proc_max_total = maxf(_pc_proc_max_total, _pc_total_ms)
	_pc_proc_timer -= delta
	if _pc_proc_timer <= 0.0:
		_pc_proc_timer = 5.0
		_pc_proc_max_physics = maxf(_pc_proc_max_physics, 0.0)
		var _wp := global_position
		var _wg_ref := _find_world_generator()
		if _wg_ref:
			_wp = _wg_ref.get_world_position(self)
		print("[PC TIMING] process=%.2fms minimap=%.2fms physics=%.2fms scene=(%.0f, %.0f, %.0f) world=(%.0f, %.0f, %.0f)" % [
			_pc_proc_max_total, _pc_proc_max_minimap, _pc_proc_max_physics,
			global_position.x, global_position.y, global_position.z,
			_wp.x, _wp.y, _wp.z])
		_pc_proc_max_total = 0.0
		_pc_proc_max_minimap = 0.0
		_pc_proc_max_physics = 0.0


func _get_item_fallback_color(item_id: StringName) -> Color:
	var parsed := ItemDatabase.parse_star_id(item_id)
	var base_id: StringName = parsed["base_id"]
	match base_id:
		&"wood":       return Color(0.55, 0.35, 0.15)
		&"stone":      return Color(0.55, 0.55, 0.55)
		&"flint":      return Color(0.3, 0.3, 0.35)
		&"leather":    return Color(0.5, 0.35, 0.2)
		&"bone":       return Color(0.85, 0.82, 0.75)
		&"meat":       return Color(0.7, 0.2, 0.15)
		&"trophy_boar": return Color(0.6, 0.4, 0.2)
		&"trophy_skeleton": return Color(0.9, 0.9, 0.85)
		&"flint_axe":  return Color(0.4, 0.4, 0.45)
		&"bronze_sword": return Color(0.7, 0.55, 0.2)
		&"bronze_mace": return Color(0.65, 0.5, 0.15)
		&"iron_sword": return Color(0.5, 0.5, 0.55)
		&"gold":       return Color(0.95, 0.8, 0.2)
		&"thick_hide": return Color(0.4, 0.25, 0.12)
		&"fang":       return Color(0.9, 0.88, 0.82)
		&"ancient_bone": return Color(0.75, 0.7, 0.55)
		&"ember_stone": return Color(0.9, 0.4, 0.1)
		&"frost_shard": return Color(0.6, 0.85, 0.95)
		_:             return Color(0.6, 0.6, 0.3)


func _update_hotbar_selection() -> void:
	var hotbar := _get_hotbar_items()
	var grouped: Array = Inventory.get_grouped_item_list()
	for i in range(_hotbar_slots.size()):
		var slot: PanelContainer = _hotbar_slots[i]
		var s := StyleBoxFlat.new()
		s.set_corner_radius_all(4)
		s.set_content_margin_all(4)

		var item_id: StringName = hotbar[i]

		if i == _selected_slot:
			s.bg_color = Color(0.2, 0.18, 0.1, 0.95)
			s.border_color = Color(0.85, 0.7, 0.3)
			s.set_border_width_all(2)
		else:
			s.bg_color = Color(0.1, 0.1, 0.14, 0.85)
			s.border_color = Color(0.3, 0.3, 0.35)
			s.set_border_width_all(1)
		slot.add_theme_stylebox_override("panel", s)

		if i < _hotbar_icons.size():
			if item_id == &"":
				_hotbar_icons[i].texture = null
				_hotbar_icons[i].modulate = Color.WHITE
			else:
				var base_id: StringName = ItemDatabase.parse_star_id(item_id)["base_id"]
				var icon_tex: Texture2D = ItemDatabase.get_icon(base_id)
				if not icon_tex:
					icon_tex = ItemDatabase.get_icon(item_id)
				if icon_tex:
					_hotbar_icons[i].texture = icon_tex
					_hotbar_icons[i].modulate = Color.WHITE
				else:
					var ph := PlaceholderTexture2D.new()
					ph.size = Vector2(32, 32)
					_hotbar_icons[i].texture = ph
					_hotbar_icons[i].modulate = _get_item_fallback_color(item_id)

		if i < _hotbar_qty_labels.size():
			if item_id == &"" or i >= grouped.size():
				_hotbar_qty_labels[i].text = ""
			else:
				var amt: int = int(grouped[i]["total"])
				_hotbar_qty_labels[i].add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
				_hotbar_qty_labels[i].text = str(amt) if amt > 1 else ""


# ===================================================================
# WEAPON HELPERS
# ===================================================================

func _get_weapon_stat(stat: String, fallback: float) -> float:
	var data: Dictionary = ItemDatabase.get_item(equipped_weapon)
	if data.has(stat):
		return float(data[stat])
	return fallback


# ===================================================================
# COMBAT
# ===================================================================

const MELEE_HIT_DELAY := 0.18

func _get_active_affixes() -> Dictionary:
	if not _affix_cache_dirty:
		return _cached_affixes
	_cached_affixes.clear()
	var wpn_parsed := ItemDatabase.parse_star_id(equipped_weapon)
	var wpn_rolls: Dictionary = wpn_parsed.get("affix_rolls", {})
	for a: StringName in wpn_parsed.get("affixes", []):
		_cached_affixes[a] = float(wpn_rolls.get(a, 0.5))
	for slot: String in Inventory.EQUIPMENT_SLOTS:
		var eq_id: StringName = Inventory.get_equipped(slot)
		if eq_id == &"":
			continue
		var eq_parsed := ItemDatabase.parse_star_id(eq_id)
		var eq_rolls: Dictionary = eq_parsed.get("affix_rolls", {})
		for a: StringName in eq_parsed.get("affixes", []):
			_cached_affixes[a] = float(eq_rolls.get(a, 0.5))
	_affix_cache_dirty = false
	_regenerator_active = _cached_affixes.has(&"regenerator")
	_rally_cry_active = _cached_affixes.has(&"rally_cry")
	_fortress_active = _cached_affixes.has(&"fortress")
	return _cached_affixes

func _has_affix(affix_id: StringName) -> bool:
	return _get_active_affixes().has(affix_id)

func _affix_val(affix_id: StringName) -> float:
	var roll: float = float(_cached_affixes.get(affix_id, 0.5))
	return ItemDatabase.get_affix_value(affix_id, roll)

func _get_weapon_affixes() -> Array:
	var parsed := ItemDatabase.parse_star_id(equipped_weapon)
	return parsed.get("affixes", [])

func _invalidate_affix_cache() -> void:
	_affix_cache_dirty = true

func _apply_affix_stat_bonuses() -> void:
	var base_max_hp := 100.0
	var base_max_stam := 100.0
	var affixes := _get_active_affixes()
	var new_max_hp := base_max_hp
	var new_max_stam := base_max_stam
	if affixes.has(&"vitality"):
		new_max_hp += _affix_val(&"vitality")
	if affixes.has(&"endurance"):
		new_max_stam += _affix_val(&"endurance")
	if new_max_hp != max_health:
		var hp_ratio := current_health / max_health if max_health > 0 else 1.0
		max_health = new_max_hp
		current_health = max_health * hp_ratio
		GameEvents.player_health_changed.emit(current_health, max_health)
	if new_max_stam != max_stamina:
		var stam_ratio := current_stamina / max_stamina if max_stamina > 0 else 1.0
		max_stamina = new_max_stam
		current_stamina = max_stamina * stam_ratio
		GameEvents.player_stamina_changed.emit(current_stamina, max_stamina)

func _try_attack() -> void:
	if _is_blocking or _is_dodging:
		return
	if _bow_drawing:
		return
	if _mounted:
		return
	var wpn_speed: float = _get_weapon_stat("attack_speed", 0.6)
	if _has_affix(&"rapid_strikes"):
		wpn_speed *= (1.0 - _affix_val(&"rapid_strikes"))
	elif _has_affix(&"rapid_chop"):
		wpn_speed *= (1.0 - _affix_val(&"rapid_chop"))
	elif _has_affix(&"quick_strike"):
		wpn_speed *= (1.0 - _affix_val(&"quick_strike"))
	if _crushing_momentum_timer > 0.0:
		wpn_speed *= (1.0 - _affix_val(&"crushing_momentum"))
	var wpn_stamina: float = _get_weapon_stat("stamina_cost", 4.0)
	if _has_affix(&"efficient_miner"):
		wpn_stamina *= (1.0 - _affix_val(&"efficient_miner"))

	if _attack_cooldown > 0.0 or not _can_spend_stamina(wpn_stamina):
		return
	_spend_stamina(wpn_stamina)
	_attack_cooldown = wpn_speed
	_start_attack_animation()

	var wpn_data := ItemDatabase.get_item(equipped_weapon)
	var is_2h := str(wpn_data.get("hands", "1h")) == "2h"

	if _model:
		_model.position = Vector3.ZERO
		var tween := create_tween()
		if is_2h:
			tween.tween_property(_model, "position:z", -0.20, 0.10)
			tween.tween_property(_model, "position:z", 0.0, 0.20)
		else:
			tween.tween_property(_model, "position:z", -0.3, 0.05)
			tween.tween_property(_model, "position:z", 0.0, 0.15)

	var is_tool := str(wpn_data.get("type", "weapon")) == "tool"
	var is_unarmed := equipped_weapon == &"fists" or is_tool
	var fist_data: Dictionary = ItemDatabase.get_item(&"fists")
	var wpn_damage: float = float(fist_data.get("damage", 5.0)) if is_tool else _get_weapon_stat("damage", 5.0)
	var wpn_range: float = float(fist_data.get("range", 2.5)) if is_tool else _get_weapon_stat("range", 2.5)
	if _has_affix(&"reaching"):
		wpn_range *= (1.0 + _affix_val(&"reaching"))
	var wpn_knockback: float = float(fist_data.get("knockback", 10.0)) if is_tool else _get_weapon_stat("knockback", 10.0)
	var hit_delay := 0.30 if is_2h else MELEE_HIT_DELAY
	get_tree().create_timer(hit_delay).timeout.connect(
		_resolve_attack.bind(wpn_damage, wpn_range, wpn_knockback, is_unarmed, "auto")
	)


func _get_build_icon(recipe_id: StringName) -> Texture2D:
	if _building:
		return _building.get_build_icon(recipe_id)
	return null


func _get_world_state_sync() -> Node:
	var wss := get_tree().get_nodes_in_group(&"world_state_sync")
	if not wss.is_empty():
		return wss[0]
	return null


func _dismount_raft() -> void:
	if _interaction:
		_interaction.dismount_raft()


func _dismount() -> void:
	if _interaction:
		_interaction.dismount()


func _mount_raft(raft: Node3D) -> void:
	if _interaction:
		_interaction.mount_raft(raft)


func _mount(horse: Node3D) -> void:
	if _interaction:
		_interaction.mount(horse)


func _open_chest(chest_node: Node3D) -> void:
	if _interaction:
		_interaction.open_chest(chest_node)


func _apply_damage_to_creature(creature: Node3D, amount: float) -> void:
	## Apply damage to creature (host-authoritative).
	## Client routes through WorldStateSync to avoid RPC node-path mismatches
	## on dynamically generated creature nodes.
	if not creature.has_method("take_damage"):
		return
	if NetworkManager.is_connected_to_game() and not NetworkManager.is_server():
		var zone_root := creature.get_parent()
		if zone_root:
			var zone_name: String = zone_root.name
			var parts := zone_name.trim_prefix("Zone_").split("_")
			if parts.size() >= 2:
				var zx := int(parts[0])
				var zz := int(parts[1])
				var cidx := 0
				for child in zone_root.get_children():
					if child == creature:
						break
					if child is CreatureAI:
						cidx += 1
				var wss_nodes := get_tree().get_nodes_in_group(&"world_state_sync")
				if not wss_nodes.is_empty():
					var wss: WorldStateSync = wss_nodes[0] as WorldStateSync
					wss.request_creature_damage.rpc_id(1, zx, zz, cidx, amount, NetworkManager.get_peer_id())
				else:
					if _DEBUG_LOG: print("[COMBAT] WorldStateSync not found â€” damage not sent")
			else:
				if _DEBUG_LOG: print("[COMBAT] Could not parse zone name '%s' for creature '%s'" % [zone_name, creature.name])
	else:
		creature.take_damage(amount, self)


func _apply_damage_to_player(target: Node3D, amount: float) -> void:
	if not target.has_method("take_damage"):
		return
	if not NetworkManager.pvp_enabled:
		return
	var target_peer := target.get_multiplayer_authority()
	if not NetworkManager.is_connected_to_game() or target_peer == multiplayer.get_unique_id():
		target.take_damage(amount, self)
	else:
		NetworkManager.request_pvp_damage(target_peer, amount)


func _echoing_blade_hit(positions: Array[Vector3], echo_dmg: float) -> void:
	const ECHO_RADIUS := 2.5
	var already_hit: Array[Node3D] = []
	for origin in positions:
		for node: Node in get_tree().get_nodes_in_group(&"enemies"):
			var enemy := node as Node3D
			if not enemy or already_hit.has(enemy):
				continue
			if enemy.has_method("is_dead") and enemy.is_dead():
				continue
			if enemy.global_position.distance_to(origin) > ECHO_RADIUS:
				continue
			if enemy.has_method("take_damage"):
				_apply_damage_to_creature(enemy, echo_dmg)
				DamageNumber.spawn(get_tree(), enemy.global_position + Vector3.UP * 1.0, echo_dmg, false, "ability")
				already_hit.append(enemy)


func _resolve_attack(wpn_damage: float, wpn_range: float, wpn_knockback: float, single_target: bool = false, hit_type: String = "auto") -> void:
	var cam: Camera3D = _spring_arm.get_child(0) if _spring_arm.get_child_count() > 0 else null
	if not cam:
		return
	var forward := -cam.global_transform.basis.z
	var fwd_flat := Vector3(forward.x, 0.0, forward.z).normalized()
	var check_origin := global_position + Vector3.UP * 1.0

	var affixes := _get_active_affixes()

	var cone_threshold := 0.5 if single_target else 0.0
	if affixes.has(&"cleaving") and not single_target:
		cone_threshold = -0.3

	var base_roll := wpn_damage * randf_range(0.7, 1.3)

	var affix_bonus := 0.0
	if affixes.has(&"berserker"):
		var missing_pct := 1.0 - (current_health / max_health)
		var berserk_cap := _affix_val(&"berserker")
		affix_bonus += minf(missing_pct * berserk_cap, berserk_cap)
	if affixes.has(&"momentum"):
		affix_bonus += _momentum_stacks * _affix_val(&"momentum")
	if affixes.has(&"relentless_fury"):
		affix_bonus += _momentum_stacks * _affix_val(&"relentless_fury")
	if _retaliation_timer > 0.0:
		affix_bonus += _affix_val(&"retaliation")

	var dmg := base_roll * (1.0 + affix_bonus)

	var kb := wpn_knockback

	var crit_chance := 5.0 + base_dexterity * 0.5
	var crit_mult := (150.0 + base_strength * 2.0) / 100.0
	if affixes.has(&"sharpened"):
		crit_chance += _affix_val(&"sharpened")
	if affixes.has(&"savage"):
		crit_mult += _affix_val(&"savage")
	var did_crit := randf() < crit_chance / 100.0
	if did_crit:
		dmg *= crit_mult

	var hit_something := false
	var hit_enemies: Array[Node3D] = []
	var best_enemy: Node3D = null
	var best_dist := INF

	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var enemy: Node3D = node as Node3D
		if not enemy:
			continue
		if enemy.has_method("is_dead") and enemy.is_dead():
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
			var target_bonus := 0.0
			if affixes.has(&"executioner"):
				var ehp: float = enemy.get("current_health") if enemy.get("current_health") != null else 999.0
				var emhp: float = enemy.get("max_health") if enemy.get("max_health") != null else 999.0
				if emhp > 0.0 and ehp / emhp < 0.3:
					target_bonus += _affix_val(&"executioner")
			if affixes.has(&"skull_crusher") and enemy.has_method("is_stunned") and enemy.is_stunned():
				target_bonus += _affix_val(&"skull_crusher")
			if affixes.has(&"bane") and randf() < _affix_val(&"bane"):
				target_bonus += 1.0
			var final_dmg := dmg * (1.0 + target_bonus)
			if enemy.has_method("take_damage"):
				_apply_damage_to_creature(enemy, final_dmg)
				_set_target_creature(enemy)
				_DamageNumber.spawn(get_tree(), enemy.global_position + Vector3.UP * 1.0, final_dmg, did_crit, hit_type)
				hit_something = true
				hit_enemies.append(enemy)
			if kb > 0.0 and enemy is CharacterBody3D:
				var kb_dir: Vector3 = (enemy.global_position - global_position).normalized()
				kb_dir.y = 0.0
				(enemy as CharacterBody3D).velocity += kb_dir * kb * 0.1

	if single_target and best_enemy:
		var target_bonus := 0.0
		if affixes.has(&"executioner"):
			var ehp: float = best_enemy.get("current_health") if best_enemy.get("current_health") != null else 999.0
			var emhp: float = best_enemy.get("max_health") if best_enemy.get("max_health") != null else 999.0
			if emhp > 0.0 and ehp / emhp < 0.3:
				target_bonus += _affix_val(&"executioner")
		if affixes.has(&"skull_crusher") and best_enemy.has_method("is_stunned") and best_enemy.is_stunned():
			target_bonus += _affix_val(&"skull_crusher")
		if affixes.has(&"bane") and randf() < _affix_val(&"bane"):
			target_bonus += 1.0
		var final_dmg := dmg * (1.0 + target_bonus)
		if best_enemy.has_method("take_damage"):
			best_enemy.take_damage(final_dmg, self)
			_set_target_creature(best_enemy)
			_DamageNumber.spawn(get_tree(), best_enemy.global_position + Vector3.UP * 1.0, final_dmg, did_crit, hit_type)
			hit_something = true
			hit_enemies.append(best_enemy)
		if kb > 0.0 and best_enemy is CharacterBody3D:
			var kb_dir: Vector3 = (best_enemy.global_position - global_position).normalized()
			kb_dir.y = 0.0
			(best_enemy as CharacterBody3D).velocity += kb_dir * kb * 0.1

	# PvP melee hits
	if NetworkManager.pvp_enabled:
		var best_pvp: Node3D = null
		var best_pvp_dist := INF
		for node: Node in get_tree().get_nodes_in_group(&"player"):
			var other := node as CharacterBody3D
			if not other or other == self:
				continue
			if other.get("current_health") != null and float(other.current_health) <= 0.0:
				continue
			var to_other: Vector3 = other.global_position - check_origin
			to_other.y = 0.0
			var dist: float = to_other.length()
			if dist > wpn_range:
				continue
			var dir_to: Vector3 = to_other.normalized()
			var dot: float = dir_to.dot(fwd_flat)
			if dot < cone_threshold:
				continue
			if single_target:
				if dist < best_pvp_dist:
					best_pvp_dist = dist
					best_pvp = other
			else:
				_apply_damage_to_player(other, dmg)
				_DamageNumber.spawn(get_tree(), other.global_position + Vector3.UP * 1.0, dmg, did_crit, hit_type)
				hit_something = true
				if kb > 0.0:
					var kb_dir: Vector3 = (other.global_position - global_position).normalized()
					kb_dir.y = 0.0
					other.velocity += kb_dir * kb * 0.1
		if single_target and best_pvp:
			_apply_damage_to_player(best_pvp, dmg)
			_DamageNumber.spawn(get_tree(), best_pvp.global_position + Vector3.UP * 1.0, dmg, did_crit, hit_type)
			hit_something = true
			if kb > 0.0 and best_pvp is CharacterBody3D:
				var kb_dir: Vector3 = (best_pvp.global_position - global_position).normalized()
				kb_dir.y = 0.0
				(best_pvp as CharacterBody3D).velocity += kb_dir * kb * 0.1

	# Post-hit affix procs
	for enemy in hit_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.has_method("is_dead") and enemy.is_dead():
			continue
		# Lifesteal
		if affixes.has(&"lifesteal"):
			var heal_amt := dmg * _affix_val(&"lifesteal")
			var pre_hp := current_health
			current_health = minf(current_health + heal_amt, max_health)
			GameEvents.player_health_changed.emit(current_health, max_health)
			var actual_heal := current_health - pre_hp
			if actual_heal > 0.5 and _camera_pivot:
				DamageNumber.spawn_heal(get_tree(), global_position, actual_heal, _camera_pivot.global_transform.basis)
		# Siphon
		if affixes.has(&"siphon"):
			current_stamina = minf(current_stamina + _affix_val(&"siphon"), max_stamina)
			GameEvents.player_stamina_changed.emit(current_stamina, max_stamina)
		# Firebrand
		if affixes.has(&"firebrand") and randf() < _affix_val(&"firebrand"):
			var fire_dmg := wpn_damage * 0.5
			if enemy.has_method("take_damage"):
				enemy.take_damage(fire_dmg, self)
				DamageNumber.spawn(get_tree(), enemy.global_position + Vector3.UP * 1.0, fire_dmg, false, "ability")
		# Chain Lightning
		if affixes.has(&"chain_lightning") and randf() < _affix_val(&"chain_lightning"):
			var arc_dmg := wpn_damage * 0.4
			var nearest: Node3D = null
			var nearest_dist := 8.0
			for other: Node in get_tree().get_nodes_in_group(&"enemies"):
				var other_3d := other as Node3D
				if not other_3d or other_3d == enemy:
					continue
				if other_3d.has_method("is_dead") and other_3d.is_dead():
					continue
				var d := enemy.global_position.distance_to(other_3d.global_position)
				if d < nearest_dist:
					nearest_dist = d
					nearest = other_3d
			if nearest and nearest.has_method("take_damage"):
				nearest.take_damage(arc_dmg, self)
				DamageNumber.spawn(get_tree(), nearest.global_position + Vector3.UP * 1.0, arc_dmg, false, "ability")
		# Runic AoE
		if affixes.has(&"runic") and randf() < _affix_val(&"runic"):
			var aoe_dmg := wpn_damage * 0.25
			for other: Node in get_tree().get_nodes_in_group(&"enemies"):
				var other_3d := other as Node3D
				if not other_3d or other_3d == enemy:
					continue
				if other_3d.has_method("is_dead") and other_3d.is_dead():
					continue
				if enemy.global_position.distance_to(other_3d.global_position) < 5.0:
					if other_3d.has_method("take_damage"):
						_apply_damage_to_creature(other_3d, aoe_dmg)
						_DamageNumber.spawn(get_tree(), other_3d.global_position + Vector3.UP * 1.0, aoe_dmg, false, "ability")
		# Frostbite
		if affixes.has(&"frostbite") and randf() < _affix_val(&"frostbite"):
			if enemy.has_method("apply_slow"):
				enemy.apply_slow(0.6, 3.0)
		# Venomous
		if affixes.has(&"venomous") and randf() < _affix_val(&"venomous"):
			if enemy.has_method("apply_poison"):
				var max_hp: float = float(enemy.get("max_health")) if enemy.get("max_health") != null else 100.0
				enemy.apply_poison(max_hp * 0.03, 4.0, self)
		# Stunning Blow
		if affixes.has(&"stunning_blow") and randf() < _affix_val(&"stunning_blow"):
			if enemy.has_method("apply_stun"):
				enemy.apply_stun(1.5)
		# Concussive (mace): 20% chance to disorient
		if affixes.has(&"concussive") and randf() < _affix_val(&"concussive"):
			if enemy.has_method("apply_disorient"):
				enemy.apply_disorient(3.0)
		# Bone Breaker (mace): 10% chance to shred armor
		if affixes.has(&"bone_breaker") and randf() < _affix_val(&"bone_breaker"):
			if enemy.has_method("apply_armor_shred"):
				enemy.apply_armor_shred(0.30, 5.0)
		# Earthshaker (mace): 12% chance for ground slam AoE
		if affixes.has(&"earthshaker") and randf() < _affix_val(&"earthshaker"):
			var slam_dmg := wpn_damage * 0.30
			for aoe_node: Node in get_tree().get_nodes_in_group(&"enemies"):
				var aoe_e := aoe_node as Node3D
				if not aoe_e or aoe_e == enemy:
					continue
				if aoe_e.has_method("is_dead") and aoe_e.is_dead():
					continue
				if enemy.global_position.distance_to(aoe_e.global_position) < 3.0:
					if aoe_e.has_method("take_damage"):
						_apply_damage_to_creature(aoe_e, slam_dmg)
						_DamageNumber.spawn(get_tree(), aoe_e.global_position + Vector3.UP * 1.0, slam_dmg, false, "ability")
		# Staggering (mace): 18% chance to stun briefly
		if affixes.has(&"staggering") and randf() < _affix_val(&"staggering"):
			if enemy.has_method("apply_stun"):
				enemy.apply_stun(0.8)
		# Thunderclap (mace): 8% chance for lightning AoE
		if affixes.has(&"thunderclap") and randf() < _affix_val(&"thunderclap"):
			var thunder_dmg := wpn_damage * 0.25
			for t_node: Node in get_tree().get_nodes_in_group(&"enemies"):
				var t_e := t_node as Node3D
				if not t_e or t_e == enemy:
					continue
				if t_e.has_method("is_dead") and t_e.is_dead():
					continue
				if enemy.global_position.distance_to(t_e.global_position) < 3.0:
					if t_e.has_method("take_damage"):
						t_e.take_damage(thunder_dmg, self)
						DamageNumber.spawn(get_tree(), t_e.global_position + Vector3.UP * 1.0, thunder_dmg, false, "ability")

	# Momentum / Relentless Fury tracking
	if (affixes.has(&"momentum") or affixes.has(&"relentless_fury")) and not hit_enemies.is_empty():
		_momentum_stacks = mini(_momentum_stacks + 1, 5)
		_momentum_timer = 3.0

	# Windfury: 30% chance to trigger 2 extra attacks (no recursion)
	if affixes.has(&"windfury") and not _windfury_guard and not hit_enemies.is_empty():
		if randf() < _affix_val(&"windfury"):
			_windfury_guard = true
			_resolve_attack(wpn_damage, wpn_range, wpn_knockback, single_target, "ability")
			_resolve_attack(wpn_damage, wpn_range, wpn_knockback, single_target, "ability")
			_windfury_guard = false

	if affixes.has(&"echoing_blade") and not _windfury_guard and not hit_enemies.is_empty():
		var echo_positions: Array[Vector3] = []
		for e in hit_enemies:
			if is_instance_valid(e):
				echo_positions.append(e.global_position)
		var echo_dmg := wpn_damage * _affix_val(&"echoing_blade")
		get_tree().create_timer(0.5).timeout.connect(
			_echoing_blade_hit.bind(echo_positions, echo_dmg)
		)

	var harvestable_candidates: Array[Dictionary] = []
	for node: Node in get_tree().get_nodes_in_group(&"interactables"):
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
			res_node.interact(self)
			hit_something = true
		elif res_node.has_meta("harvestable"):
			harvestable_candidates.append({"node": res_node, "dist": dist})

	harvestable_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["dist"] < b["dist"])
	var max_harvestable_hits := 3 if _has_affix(&"timber_cleave") else 2
	for i in mini(harvestable_candidates.size(), max_harvestable_hits):
		var h_node: Node3D = harvestable_candidates[i]["node"] as Node3D
		var drop_id: StringName = h_node.get_meta("drop_id", &"wood") as StringName
		var harvest_slot := "pickaxe" if drop_id == &"stone" else "weapon"
		var harvest_id: StringName = Inventory.get_equipped(harvest_slot)
		var harvest_data: Dictionary = ItemDatabase.get_item(harvest_id) if harvest_id != &"" else {}
		var harvest_dmg: float = float(harvest_data.get("damage", 5.0)) * randf_range(0.7, 1.3)
		_hit_harvestable(h_node, harvest_dmg)
		hit_something = true


func _hit_harvestable(node: Node3D, damage: float) -> void:
	var drop_id: StringName = node.get_meta("drop_id", &"wood") as StringName

	var requires_tool: StringName = node.get_meta("requires_tool", &"") as StringName
	if requires_tool != &"":
		var pick_id: StringName = Inventory.get_equipped("pickaxe")
		var has_pickaxe := pick_id != &""
		if not has_pickaxe:
			# Bounce feedback - show "Need pickaxe" message
			_DamageNumber.spawn(get_tree(), node.global_position + Vector3.UP * 1.5, 0.0, false, "player")
			var msg := DamageNumber.new()
			msg.text = "Need Pickaxe"
			msg.font_size = 20
			msg.pixel_size = 0.008
			msg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			msg.no_depth_test = true
			msg.modulate = Color(1.0, 0.6, 0.2)
			msg.outline_modulate = Color.BLACK
			msg.outline_size = 5
			msg._velocity = Vector3(0, 1.5, 0)
			get_tree().current_scene.add_child(msg)
			msg.global_position = node.global_position + Vector3(0, 2.0, 0)
			AudioManager.play_sfx_at("stone_rubble", node.global_position, -8.0)
			return

	var hp: float = float(node.get_meta("hp", 0.0))
	var effective_dmg := damage
	if drop_id == &"wood" and _has_affix(&"deep_cut"):
		effective_dmg *= 1.5
	elif drop_id == &"stone" and _has_affix(&"stone_breaker"):
		effective_dmg *= 1.5
	hp -= effective_dmg
	node.set_meta("hp", hp)

	# Trunk: very subtle wobble at the base â€” it's anchored in the ground
	var mesh := node.get_node_or_null("MeshInstance3D")
	if not mesh:
		mesh = node.get_node_or_null("Trunk")
	if mesh:
		var tween := node.create_tween()
		tween.tween_property(mesh, "rotation:z", deg_to_rad(1.5), 0.06)
		tween.tween_property(mesh, "rotation:z", deg_to_rad(-1.0), 0.07)
		tween.tween_property(mesh, "rotation:z", deg_to_rad(0.4), 0.06)
		tween.tween_property(mesh, "rotation:z", 0.0, 0.1)

	# Canopy: big dramatic sway â€” momentum builds at the top
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
	_DamageNumber.spawn(get_tree(), node.global_position + Vector3.UP * 2.0, effective_dmg)

	# Frenzied Chop / Frenzied Mining: 25% chance to land 2 extra hits
	if drop_id == &"wood" and _has_affix(&"sharpened_edge") and randf() < _affix_val(&"sharpened_edge") and hp > 0.0:
		_hit_harvestable(node, effective_dmg)
		_hit_harvestable(node, effective_dmg)
	elif drop_id == &"stone" and _has_affix(&"precision_strike") and randf() < _affix_val(&"precision_strike") and hp > 0.0:
		_hit_harvestable(node, effective_dmg)
		_hit_harvestable(node, effective_dmg)

	if drop_id == &"wood":
		var sfx := "axe_chop" if equipped_weapon != &"fists" and equipped_weapon != &"" else "fist_hit_tree"
		AudioManager.play_sfx(sfx, -4.0)
	elif drop_id == &"stone":
		AudioManager.play_sfx("pickaxe_hit", -4.0)

	if hp <= 0.0:
		if drop_id == &"stone":
			_destroy_rock(node)
		else:
			_fell_tree(node)


func _destroy_rock(node: Node3D) -> void:
	# Network sync: get key before modifying node, then notify host
	var wss := _get_world_state_sync()
	var is_client_destroy := false
	if wss and NetworkManager.is_connected_to_game():
		var key := WorldStateSync.get_object_key_for_node(node)
		if not key.is_empty():
			if NetworkManager.is_server():
				wss.record_object_destroyed(node)
			else:
				wss.request_destroy_object.rpc_id(1, key)
				is_client_destroy = true

	var drop_id: StringName = node.get_meta("drop_id", &"stone") as StringName
	var drop_min: int = int(node.get_meta("drop_min", 2))
	var drop_max: int = int(node.get_meta("drop_max", 4))

	node.remove_from_group(&"interactables")
	node.set_meta("harvestable", false)
	var col := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col:
		col.disabled = true

	var rock_pos := node.global_position
	var rock_mi := node.get_node_or_null("MeshInstance3D") as MeshInstance3D
	var rock_scale := 1.0
	if rock_mi:
		rock_scale = rock_mi.scale.x

	_spawn_rock_explosion(rock_pos, rock_scale)

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var total := rng.randi_range(drop_min, drop_max)
	if drop_id == &"stone" and _has_affix(&"prospector"):
		total = ceili(total * (1.0 + _affix_val(&"prospector")))
	elif drop_id == &"copper_ore" and _has_affix(&"ore_seeker"):
		total = ceili(total * (1.0 + _affix_val(&"ore_seeker")))
	if _has_affix(&"rich_vein") and rng.randf() < _affix_val(&"rich_vein"):
		total *= 2
	var master_miner := _has_affix(&"heavy_swing")
	var use_sync := wss and NetworkManager.is_connected_to_game() and NetworkManager.is_server()
	const ROCK_LOOT_DELAY := 1.0
	if not is_client_destroy:
		for i in total:
			var angle := rng.randf_range(0.0, TAU)
			var dist := rng.randf_range(1.6, 5.0)
			var offset := Vector3(cos(angle) * dist, 0.5, sin(angle) * dist)
			var stars := ItemDatabase.roll_star_level(rng)
			if master_miner:
				var reroll := ItemDatabase.roll_star_level(rng)
				if reroll > stars:
					stars = reroll
				reroll = ItemDatabase.roll_star_level(rng)
				if reroll > stars:
					stars = reroll
			var pos := rock_pos + offset
			if use_sync:
				wss.spawn_loot_synced(pos, drop_id, 1, stars, ROCK_LOOT_DELAY)
			else:
				var drop := LootDrop.new()
				drop.item_id = drop_id
				drop.star_level = stars
				drop.amount = 1
				drop.spawn_delay = ROCK_LOOT_DELAY
				get_tree().current_scene.add_child(drop)
				drop.global_position = pos

		if rng.randf() < 0.4:
			var flint_stars := ItemDatabase.roll_star_level(rng)
			var flint_pos := rock_pos + Vector3(rng.randf_range(-2.0, 2.0), 0.5, rng.randf_range(-2.0, 2.0))
			if use_sync:
				wss.spawn_loot_synced(flint_pos, &"flint", rng.randi_range(1, 2), flint_stars, ROCK_LOOT_DELAY)
			else:
				var flint_drop := LootDrop.new()
				flint_drop.item_id = &"flint"
				flint_drop.star_level = flint_stars
				flint_drop.amount = rng.randi_range(1, 2)
				flint_drop.spawn_delay = ROCK_LOOT_DELAY
				get_tree().current_scene.add_child(flint_drop)
				flint_drop.global_position = flint_pos

		if _has_affix(&"vein_finder") and rng.randf() < _affix_val(&"vein_finder"):
			var ore_pos := rock_pos + Vector3(rng.randf_range(-2.0, 2.0), 0.5, rng.randf_range(-2.0, 2.0))
			if use_sync:
				wss.spawn_loot_synced(ore_pos, &"copper_ore", rng.randi_range(1, 2), ItemDatabase.roll_star_level(rng), ROCK_LOOT_DELAY)
			else:
				var ore_drop := LootDrop.new()
				ore_drop.item_id = &"copper_ore"
				ore_drop.star_level = ItemDatabase.roll_star_level(rng)
				ore_drop.amount = rng.randi_range(1, 2)
				ore_drop.spawn_delay = ROCK_LOOT_DELAY
				get_tree().current_scene.add_child(ore_drop)
				ore_drop.global_position = ore_pos

		if _has_affix(&"geologist") and rng.randf() < 0.20:
			var rare_items: Array[StringName] = [&"gemstone", &"ancient_bone", &"ember_stone"]
			var rare_id: StringName = rare_items[rng.randi_range(0, rare_items.size() - 1)]
			var rare_pos := rock_pos + Vector3(rng.randf_range(-2.0, 2.0), 0.5, rng.randf_range(-2.0, 2.0))
			if use_sync:
				wss.spawn_loot_synced(rare_pos, rare_id, 1, ItemDatabase.roll_star_level(rng), ROCK_LOOT_DELAY)
			else:
				var rare_drop := LootDrop.new()
				rare_drop.item_id = rare_id
				rare_drop.star_level = ItemDatabase.roll_star_level(rng)
				rare_drop.amount = 1
				rare_drop.spawn_delay = ROCK_LOOT_DELAY
				get_tree().current_scene.add_child(rare_drop)
				rare_drop.global_position = rare_pos

	AudioManager.play_sfx_at("rock_fall", rock_pos, 2.0)
	AudioManager.play_sfx_at("stone_rubble", rock_pos, -2.0)
	node.queue_free()


func _spawn_rock_explosion(rock_pos: Vector3, rock_scale: float) -> void:
	var scene_root := get_tree().current_scene
	if not scene_root:
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var chunk_count := clampi(int(8 + rock_scale * 2.0), 8, 20)
	var burst_pos := rock_pos + Vector3.UP * maxf(rock_scale * 0.3, 0.3)
	var spread := maxf(rock_scale * 0.25, 0.2)
	var chunk_base_size := clampf(rock_scale * 0.06, 0.05, 0.3)

	for i in chunk_count:
		var chunk := MeshInstance3D.new()
		var box := BoxMesh.new()
		var sz := rng.randf_range(chunk_base_size * 0.5, chunk_base_size * 1.5)
		box.size = Vector3(sz, sz * rng.randf_range(0.5, 1.2), sz * rng.randf_range(0.6, 1.0))
		chunk.mesh = box

		var grey := rng.randf_range(0.35, 0.6)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(grey, grey * rng.randf_range(0.92, 1.0), grey * rng.randf_range(0.88, 0.97))
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		chunk.set_surface_override_material(0, mat)

		chunk.global_position = burst_pos + Vector3(
			rng.randf_range(-spread, spread),
			rng.randf_range(-spread * 0.3, spread * 0.5),
			rng.randf_range(-spread, spread))
		scene_root.add_child(chunk)

		var angle := rng.randf_range(0.0, TAU)
		var horiz_speed := rng.randf_range(2.5, 6.0)
		var vert_speed := rng.randf_range(3.0, 7.0)
		var end_pos := chunk.global_position + Vector3(cos(angle) * horiz_speed, vert_speed, sin(angle) * horiz_speed) * 0.4 + Vector3.DOWN * 3.0

		var tw := chunk.create_tween()
		tw.set_parallel(true)
		tw.tween_property(chunk, "global_position", end_pos, 0.8) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(chunk, "rotation",
			Vector3(rng.randf_range(-10.0, 10.0), rng.randf_range(-10.0, 10.0), rng.randf_range(-10.0, 10.0)), 0.8)
		tw.chain().tween_callback(chunk.queue_free)


func _get_terrain_slope_dir(pos: Vector3) -> Vector3:
	var wg := _find_world_generator()
	if not wg:
		return Vector3.ZERO
	var sample_dist := 2.0
	var h_center := wg.get_height_at_scene(pos.x, pos.z)
	var h_px := wg.get_height_at_scene(pos.x + sample_dist, pos.z)
	var h_nx := wg.get_height_at_scene(pos.x - sample_dist, pos.z)
	var h_pz := wg.get_height_at_scene(pos.x, pos.z + sample_dist)
	var h_nz := wg.get_height_at_scene(pos.x, pos.z - sample_dist)
	var slope := Vector3(h_nx - h_px, 0.0, h_nz - h_pz)
	if slope.length_squared() < 0.001:
		return Vector3.ZERO
	return slope.normalized()


func _fell_tree(node: Node3D, override_angle: float = NAN, can_domino: bool = true) -> void:
	# Network sync: get key before modifying node, then notify host
	var wss := _get_world_state_sync()
	var is_client_destroy := false
	if wss and NetworkManager.is_connected_to_game():
		var key := WorldStateSync.get_object_key_for_node(node)
		if not key.is_empty():
			if NetworkManager.is_server():
				wss.record_object_destroyed(node)
			else:
				if _DEBUG_LOG: print("[FELL-CLIENT] Sending request_destroy_object key='%s' for node '%s'" % [key, node.name])
				wss.request_destroy_object.rpc_id(1, key)
				is_client_destroy = true
		else:
			if _DEBUG_LOG: print("[FELL-CLIENT] WARNING: could not compute key for node '%s' (parent='%s')" % [
				node.name, node.get_parent().name if node.get_parent() else "null"])

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

	# Fall direction: 60% player push + 40% terrain slope (downhill bias)
	var fall_angle: float
	if is_nan(override_angle):
		var to_tree := node.global_position - global_position
		to_tree.y = 0.0
		var player_dir := to_tree.normalized()

		var slope_dir := _get_terrain_slope_dir(tree_base)
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

	# Spawn a stump at the base before the tree falls
	_spawn_tree_stump(node, tree_base)

	var fall_tween := node.create_tween()
	fall_tween.set_ease(Tween.EASE_IN)
	fall_tween.set_trans(Tween.TRANS_QUART)

	node.rotation.y = fall_angle
	var fall_duration := (1.17 * (1.0 - _affix_val(&"splitter"))) if _has_affix(&"splitter") else 1.17
	fall_tween.tween_property(node, "rotation:x", deg_to_rad(-85.0), fall_duration)

	var fall_dir := Vector3(-sin(fall_angle), 0.0, -cos(fall_angle))
	fall_tween.tween_callback(func():
		if can_domino:
			_check_tree_domino(tree_base, fall_angle, trunk_h)
		AudioManager.play_sfx_at("tree_fall", tree_base + fall_dir * trunk_h * 0.5, 0.0)
	)
	fall_tween.tween_interval(0.4)
	fall_tween.tween_callback(func():
		node.queue_free()

		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var log_count := rng.randi_range(drop_min, drop_max)
		if _has_affix(&"lumberjack"):
			log_count = ceili(log_count * (1.0 + _affix_val(&"lumberjack")))
		if _has_affix(&"double_yield") and rng.randf() < _affix_val(&"double_yield"):
			log_count *= 2
		var master_woodsman := _has_affix(&"heavy_chop")
		var tree_wss := _get_world_state_sync()
		var use_sync := tree_wss and NetworkManager.is_connected_to_game() and NetworkManager.is_server()
		if not is_client_destroy:
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
				var pos := tree_base + offset
				if use_sync:
					tree_wss.spawn_loot_synced(pos, drop_id, 1, stars)
				else:
					var drop := LootDrop.new()
					drop.item_id = drop_id
					drop.star_level = stars
					drop.amount = 1
					get_tree().current_scene.add_child(drop)
					drop.global_position = pos

			if _has_affix(&"bark_stripper") and rng.randf() < _affix_val(&"bark_stripper"):
				var resin_pos := tree_base + Vector3(rng.randf_range(-1.0, 1.0), 0.5, rng.randf_range(-1.0, 1.0))
				if use_sync:
					tree_wss.spawn_loot_synced(resin_pos, &"resin", rng.randi_range(1, 2), ItemDatabase.roll_star_level(rng))
				else:
					var resin_drop := LootDrop.new()
					resin_drop.item_id = &"resin"
					resin_drop.star_level = ItemDatabase.roll_star_level(rng)
					resin_drop.amount = rng.randi_range(1, 2)
					get_tree().current_scene.add_child(resin_drop)
					resin_drop.global_position = resin_pos

			if _has_affix(&"sap_drinker") and rng.randf() < 0.20:
				var rare_items: Array[StringName] = [&"amber", &"living_wood", &"fairy_dust"]
				var rare_id: StringName = rare_items[rng.randi_range(0, rare_items.size() - 1)]
				var rare_pos := tree_base + Vector3(rng.randf_range(-1.0, 1.0), 0.5, rng.randf_range(-1.0, 1.0))
				if use_sync:
					tree_wss.spawn_loot_synced(rare_pos, rare_id, 1, ItemDatabase.roll_star_level(rng))
				else:
					var rare_drop := LootDrop.new()
					rare_drop.item_id = rare_id
					rare_drop.star_level = ItemDatabase.roll_star_level(rng)
					rare_drop.amount = 1
					get_tree().current_scene.add_child(rare_drop)
					rare_drop.global_position = rare_pos
	)


func _spawn_tree_stump(tree_node: Node3D, base_pos: Vector3) -> void:
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
	stump_root.set_meta("stump_radius", maxf(bot_r, top_r) + 0.1)
	stump_root.add_to_group(&"stumps")
	get_tree().current_scene.add_child(stump_root)
	stump_root.global_position = base_pos
	stump_root.add_child(stump_mi)
	if not is_sapling_stump:
		stump_root.add_child(col_shape)

	get_tree().create_timer(120.0).timeout.connect(stump_root.queue_free)


func _check_tree_domino(base_pos: Vector3, fall_angle: float, trunk_h: float = 15.0) -> void:
	var fall_dir := Vector3(-sin(fall_angle), 0.0, -cos(fall_angle))
	var hit_radius := maxf(1.5, trunk_h * 0.08)
	var faller_is_sapling := trunk_h < 8.0
	var felled: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group(&"interactables"):
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
		_fell_tree(n3d, push_angle, false)


func _check_tree_crush_player(base_pos: Vector3, fall_angle: float, trunk_h: float) -> void:
	var fall_dir := Vector3(sin(fall_angle), 0.0, cos(fall_angle))
	var player_pos := global_position
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
			velocity += knockback_dir * 8.0
			return


# ===================================================================
# INTERACT / LOOT PICKUP
# ===================================================================

func _update_interact_prompt() -> void:
	if not _interact_prompt:
		return
	if _inventory_open or _workbench_open or _build_menu_open or _build_mode or _chest_open or _map_open:
		_interact_prompt.visible = false
		if _world_name_label:
			_world_name_label.visible = false
		return

	# Check for nearby workbenches
	var closest_dist := 3.5
	var closest_name := ""
	for wb in get_tree().get_nodes_in_group(&"workbenches"):
		var wb3d := wb as Node3D
		if not wb3d:
			continue
		var d := global_position.distance_to(wb3d.global_position)
		if d < closest_dist:
			closest_dist = d
			closest_name = "Workbench"

	# Check for nearby doors
	for door in get_tree().get_nodes_in_group(&"doors"):
		var d3d := door as Node3D
		if not d3d:
			continue
		var d := global_position.distance_to(d3d.global_position)
		if d < closest_dist:
			closest_dist = d
			var is_open: bool = d3d.get_meta("door_open", false)
			closest_name = "Close Door" if is_open else "Open Door"

	# Check for nearby chests
	for ch in get_tree().get_nodes_in_group(&"chests"):
		var ch3d := ch as Node3D
		if not ch3d:
			continue
		var d := global_position.distance_to(ch3d.global_position)
		if d < closest_dist:
			closest_dist = d
			closest_name = "Chest"

	# Check for nearby horses/rafts (mount prompt) or show dismount
	if _on_raft:
		closest_name = "Dismount Raft"
	elif _mounted:
		closest_name = "Dismount"
	else:
		for horse in get_tree().get_nodes_in_group(&"horses"):
			var h3d := horse as Node3D
			if not h3d:
				continue
			var d := global_position.distance_to(h3d.global_position)
			if d < closest_dist:
				closest_dist = d
				closest_name = "Mount"
		for raft in get_tree().get_nodes_in_group(&"rafts"):
			var r3d := raft as Node3D
			if not r3d:
				continue
			var d := global_position.distance_to(r3d.global_position)
			if d < 4.0 and d < closest_dist:
				closest_dist = d
				closest_name = "Board Raft"

	# Show interactable name only when crosshair is aimed at it (raycast)
	var nearest_world_name := ""
	var cam: Camera3D = _spring_arm.get_child(0) if _spring_arm.get_child_count() > 0 else null
	if cam and cam.is_inside_tree() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var ray_origin := cam.global_position
		var ray_dir := -cam.global_transform.basis.z
		var ray_end := ray_origin + ray_dir * 20.0
		var space := get_world_3d().direct_space_state
		if space:
			var q := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 4)
			q.exclude = [get_rid()]
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var obj := hit["collider"] as Node3D
				if obj:
					if obj.has_meta("tree_name"):
						nearest_world_name = obj.get_meta("tree_name") as String
					elif obj.has_meta("rock_name"):
						nearest_world_name = obj.get_meta("rock_name") as String
					elif obj.has_meta("vein_name"):
						nearest_world_name = obj.get_meta("vein_name") as String
					elif obj.has_meta("cave_entrance"):
						nearest_world_name = "Cave"
					elif obj.has_meta("cave_exit"):
						nearest_world_name = "Exit"

	# Cave entrance / exit prompt
	if not _in_cave:
		for ce in get_tree().get_nodes_in_group(&"cave_entrances"):
			var ce3d := ce as Node3D
			if not ce3d:
				continue
			var d := global_position.distance_to(ce3d.global_position)
			if d < 4.0 and d < closest_dist:
				closest_dist = d
				closest_name = "Enter Cave"
	else:
		for node in get_tree().get_nodes_in_group(&"interactables"):
			var n3d := node as Node3D
			if not n3d or not n3d.has_meta("cave_exit"):
				continue
			var d := global_position.distance_to(n3d.global_position)
			if d < 4.0 and d < closest_dist:
				closest_dist = d
				closest_name = "Exit Cave"

	if closest_name != "":
		_interact_prompt.text = "[E] %s" % closest_name
		_interact_prompt.visible = true
	else:
		_interact_prompt.visible = false

	if _world_name_label:
		if nearest_world_name != "" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_world_name_label.text = nearest_world_name
			_world_name_label.visible = true
			var vp_center := get_viewport().get_visible_rect().size * 0.5
			_world_name_label.position = vp_center + Vector2(18, 16)
		else:
			_world_name_label.visible = false


func _try_interact() -> void:
	# Dismount raft
	if _on_raft:
		_dismount_raft()
		return
	# Dismount if mounted
	if _mounted:
		_dismount()
		return

	# Cave exit â€” check first if inside a cave
	if _in_cave:
		for node in get_tree().get_nodes_in_group(&"interactables"):
			var n3d := node as Node3D
			if not n3d or not n3d.has_meta("cave_exit"):
				continue
			if global_position.distance_to(n3d.global_position) < 4.0:
				_exit_cave()
				return

	# Cave entrances
	if not _in_cave:
		for node in get_tree().get_nodes_in_group(&"cave_entrances"):
			var n3d := node as Node3D
			if not n3d:
				continue
			if global_position.distance_to(n3d.global_position) < 4.0:
				_enter_cave(n3d)
				return

	var best_loot: Node3D
	var best_dist := 3.45
	var my_peer_e := multiplayer.get_unique_id() if multiplayer.has_multiplayer_peer() else 0
	for node in get_tree().get_nodes_in_group(&"loot"):
		var loot := node as Node3D
		if not loot:
			continue
		if "pickup_grace" in loot and loot.pickup_grace > 0.0:
			if "drop_owner_peer" in loot and loot.drop_owner_peer == my_peer_e:
				continue
		var d: float = global_position.distance_to(loot.global_position)
		if d < best_dist:
			best_dist = d
			best_loot = loot
	if best_loot and best_loot.has_method("pickup"):
		best_loot.pickup(self)
		return

	# Check rafts
	for raft in get_tree().get_nodes_in_group(&"rafts"):
		var r3d := raft as Node3D
		if r3d and global_position.distance_to(r3d.global_position) < 4.0:
			_mount_raft(r3d)
			return

	# Check horses
	for horse in get_tree().get_nodes_in_group(&"horses"):
		var h3d := horse as Node3D
		if h3d and global_position.distance_to(h3d.global_position) < 3.5:
			_mount(h3d)
			return

	# Check doors
	for door in get_tree().get_nodes_in_group(&"doors"):
		var d3d := door as StaticBody3D
		if not d3d:
			continue
		if global_position.distance_to(d3d.global_position) < 3.5:
			_toggle_door(d3d)
			return

	# Check chests
	for ch in get_tree().get_nodes_in_group(&"chests"):
		var ch3d := ch as Node3D
		if not ch3d:
			continue
		if global_position.distance_to(ch3d.global_position) < 3.0:
			_open_chest(ch3d)
			return

	# Check workbenches
	for wb in get_tree().get_nodes_in_group(&"workbenches"):
		var wb3d := wb as Node3D
		if not wb3d:
			continue
		if global_position.distance_to(wb3d.global_position) < 3.0:
			_workbench_ui.open_workbench()
			return


# ===================================================================
# CAVE TELEPORTATION
# ===================================================================

func _enter_cave(entrance: Node3D) -> void:
	if _in_cave:
		return
	_cave_return_pos = global_position
	_cave_entrance_node = entrance

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(entrance.global_position)
	_cave_instance = CaveGenerator.create_cave_instance(rng)
	get_tree().root.add_child(_cave_instance)

	var spawn_local: Vector3 = _cave_instance.get_meta("player_spawn", Vector3.ZERO)
	global_position = _cave_instance.global_position + spawn_local
	velocity = Vector3.ZERO
	_in_cave = true

	if _footstep_player and _footstep_player.playing:
		_footstep_player.stop()
	if _gallop_player and _gallop_player.playing:
		_gallop_player.stop()


func _exit_cave() -> void:
	if not _in_cave:
		return
	_in_cave = false
	global_position = _cave_return_pos + Vector3(0.0, 1.0, 0.0)
	velocity = Vector3.ZERO

	if is_instance_valid(_cave_instance):
		_cave_instance.queue_free()
	_cave_instance = null
	_cave_entrance_node = null


# ===================================================================
# DAMAGE / HEALTH
# ===================================================================

func take_damage(amount: float, _source: Node3D = null) -> void:
	if current_health <= 0.0:
		return
	if _is_dodging:
		return
	if _source and _source != self and _source.is_in_group(&"player"):
		if not NetworkManager.pvp_enabled:
			return
	if _source and _source.has_method("take_damage") and not _source.is_in_group(&"player"):
		_set_target_creature(_source)

	var pre_vel := velocity
	var affixes := _get_active_affixes()

	var proc_dr := 0.0
	if affixes.has(&"iron_skin") and randf() < _affix_val(&"iron_skin"):
		proc_dr = 0.85
		var absorb_num := DamageNumber.new()
		absorb_num.text = "Absorbed"
		absorb_num.font_size = 20
		absorb_num.pixel_size = 0.008
		absorb_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		absorb_num.no_depth_test = true
		absorb_num.modulate = Color(0.6, 0.8, 1.0)
		absorb_num.outline_modulate = Color.BLACK
		absorb_num.outline_size = 5
		absorb_num._velocity = Vector3(0, 2.0, 0)
		get_tree().current_scene.add_child(absorb_num)
		absorb_num.global_position = global_position + Vector3.UP * 2.5

	var dodge_roll := 0.0
	if affixes.has(&"evasion"):
		dodge_roll += _affix_val(&"evasion")
	if affixes.has(&"nimble") and _is_sprinting:
		dodge_roll += _affix_val(&"nimble")
	if proc_dr == 0.0 and dodge_roll > 0.0 and randf() < dodge_roll:
		proc_dr = 0.85
		var evade_num := DamageNumber.new()
		evade_num.text = "Evaded"
		evade_num.font_size = 20
		evade_num.pixel_size = 0.008
		evade_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		evade_num.no_depth_test = true
		evade_num.modulate = Color(0.5, 1.0, 0.5)
		evade_num.outline_modulate = Color.BLACK
		evade_num.outline_size = 5
		evade_num._velocity = Vector3(0, 2.0, 0)
		get_tree().current_scene.add_child(evade_num)
		evade_num.global_position = global_position + Vector3.UP * 2.5

	if proc_dr == 0.0 and affixes.has(&"deflection") and not _is_blocking and randf() < _affix_val(&"deflection"):
		if _source and _source.global_position.distance_to(global_position) > 5.0:
			proc_dr = 0.85
			var defl_num := DamageNumber.new()
			defl_num.text = "Deflected"
			defl_num.font_size = 20
			defl_num.pixel_size = 0.008
			defl_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			defl_num.no_depth_test = true
			defl_num.modulate = Color(0.7, 0.9, 1.0)
			defl_num.outline_modulate = Color.BLACK
			defl_num.outline_size = 5
			defl_num._velocity = Vector3(0, 2.0, 0)
			get_tree().current_scene.add_child(defl_num)
			defl_num.global_position = global_position + Vector3.UP * 2.5

	var final_amount := amount
	if proc_dr > 0.0:
		final_amount *= (1.0 - proc_dr)

	if affixes.has(&"shield_wall") and not _is_blocking and randf() < _affix_val(&"shield_wall"):
		final_amount *= 0.3

	if _aegis_shield > 0.0:
		var absorbed := minf(final_amount, _aegis_shield)
		_aegis_shield -= absorbed
		final_amount -= absorbed
	if affixes.has(&"aegis") and randf() < _affix_val(&"aegis") and _aegis_timer <= 0.0:
		_aegis_shield = max_health * 0.15
		_aegis_timer = 5.0

	var dr_bonus := 0.0
	if affixes.has(&"iron_will") and _is_attacking:
		dr_bonus += _affix_val(&"iron_will")
	if affixes.has(&"thick_skinned") and _thick_skinned_cooldown <= 0.0:
		dr_bonus += _affix_val(&"thick_skinned")
		_thick_skinned_cooldown = 10.0
	if affixes.has(&"fortified"):
		dr_bonus += _affix_val(&"fortified")
	if affixes.has(&"last_stand") and current_health / max_health < 0.25:
		dr_bonus += _affix_val(&"last_stand")
	if affixes.has(&"battle_hardened"):
		var nearby_count := 0
		for node: Node in get_tree().get_nodes_in_group(&"enemies"):
			var e := node as Node3D
			if e and global_position.distance_to(e.global_position) < 10.0:
				nearby_count += 1
				if nearby_count >= 3:
					break
		dr_bonus += nearby_count * _affix_val(&"battle_hardened")

	var did_block := _is_blocking
	if _is_blocking:
		if affixes.has(&"unbreakable") and current_health / max_health < 0.25:
			dr_bonus += 0.90
		elif affixes.has(&"guardian"):
			dr_bonus += _affix_val(&"guardian")
		else:
			dr_bonus += 0.70

	var armor_value := Inventory.get_total_armor()
	if affixes.has(&"bulwark"):
		armor_value += _affix_val(&"bulwark")
	if _fortress_active:
		armor_value += _affix_val(&"fortress")
	var armor_dr := minf(armor_value * 0.02, 0.80)
	dr_bonus += armor_dr

	var total_dr := minf(dr_bonus, 0.85)
	final_amount *= (1.0 - total_dr)

	current_health = maxf(current_health - final_amount, 0.0)
	_hp_pulse = 1.0
	var regen_delay := health_regen_delay
	if affixes.has(&"quick_recovery"):
		regen_delay -= _affix_val(&"quick_recovery")
	_health_regen_timer = regen_delay
	GameEvents.player_health_changed.emit(current_health, max_health)
	AudioManager.play_sfx("player_hurt", -2.0)

	if final_amount > 0.5:
		DamageNumber.spawn(get_tree(), global_position + Vector3.UP * 2.0, final_amount, false, "enemy")

	# Shield post-hit procs
	if did_block:
		if affixes.has(&"retaliation"):
			_retaliation_timer = 3.0
		if affixes.has(&"shield_bash") and randf() < _affix_val(&"shield_bash") and _source and _source.has_method("apply_stun"):
			_source.apply_stun(1.0)
	if not _gltf_all_meshes.is_empty():
		_gltf_flash(Color(1.0, 0.2, 0.2))
		get_tree().create_timer(0.15).timeout.connect(func():
			_gltf_clear_flash()
		)
	elif _player_model_3d:
		_player_model_3d.flash(Color(1.0, 0.2, 0.2))
		get_tree().create_timer(0.15).timeout.connect(func():
			if _player_model_3d:
				_player_model_3d.clear_flash()
		)

	# Steadfast: immune to knockback / Stalwart: -30% knockback
	if affixes.has(&"steadfast"):
		velocity = pre_vel
	elif affixes.has(&"stalwart"):
		var kb_change := velocity - pre_vel
		velocity = pre_vel + kb_change * (1.0 - _affix_val(&"stalwart"))

	if affixes.has(&"thorns") and _source and _source.has_method("take_damage"):
		_source.take_damage(amount * _affix_val(&"thorns"), self)

	if affixes.has(&"second_wind") and _second_wind_cooldown <= 0.0:
		if current_health > 0.0 and current_health / max_health < 0.20:
			var pre_hp := current_health
			current_health = minf(current_health + max_health * _affix_val(&"second_wind"), max_health)
			_second_wind_cooldown = 45.0
			GameEvents.player_health_changed.emit(current_health, max_health)
			var actual_heal := current_health - pre_hp
			if actual_heal > 0.5 and _camera_pivot:
				DamageNumber.spawn_heal(get_tree(), global_position, actual_heal, _camera_pivot.global_transform.basis)

	if current_health <= 0.0:
		# Undying: revive once (300s cooldown)
		if affixes.has(&"undying") and _undying_cooldown <= 0.0:
			current_health = max_health * _affix_val(&"undying")
			_undying_cooldown = 300.0
			GameEvents.player_health_changed.emit(current_health, max_health)
			var revive_num := DamageNumber.new()
			revive_num.text = "Undying!"
			revive_num.font_size = 26
			revive_num.pixel_size = 0.01
			revive_num.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			revive_num.no_depth_test = true
			revive_num.modulate = Color(1.0, 0.85, 0.2)
			revive_num.outline_modulate = Color.BLACK
			revive_num.outline_size = 6
			revive_num._velocity = Vector3(0, 2.5, 0)
			get_tree().current_scene.add_child(revive_num)
			revive_num.global_position = global_position + Vector3.UP * 2.5
		else:
			_on_death()


func _handle_health_regen(delta: float) -> void:
	_health_regen_timer -= delta
	if _health_regen_timer <= 0.0 and current_health < max_health:
		var regen := health_regen_rate
		if _has_affix(&"rejuvenation"):
			regen *= (1.0 + _affix_val(&"rejuvenation"))
		current_health = minf(current_health + regen * delta, max_health)
		GameEvents.player_health_changed.emit(current_health, max_health)
	# Regenerator: +1 HP/s even during combat (ignores regen delay)
	if _regenerator_active and current_health < max_health and _health_regen_timer > 0.0:
		current_health = minf(current_health + 1.0 * delta, max_health)
		GameEvents.player_health_changed.emit(current_health, max_health)

func _tick_affix_timers(delta: float) -> void:
	if _momentum_timer > 0.0:
		_momentum_timer -= delta
		if _momentum_timer <= 0.0:
			_momentum_stacks = 0
	if _second_wind_cooldown > 0.0:
		_second_wind_cooldown -= delta
	if _thick_skinned_cooldown > 0.0:
		_thick_skinned_cooldown -= delta
	if _undying_cooldown > 0.0:
		_undying_cooldown -= delta
	if _adrenaline_timer > 0.0:
		_adrenaline_timer -= delta
	if _crushing_momentum_timer > 0.0:
		_crushing_momentum_timer -= delta
	if _retaliation_timer > 0.0:
		_retaliation_timer -= delta
	if _aegis_timer > 0.0:
		_aegis_timer -= delta
		if _aegis_timer <= 0.0:
			_aegis_shield = 0.0
	if _rally_cry_active and current_health < max_health:
		current_health = minf(current_health + 2.0 * delta, max_health)
		GameEvents.player_health_changed.emit(current_health, max_health)

func _on_death() -> void:
	GameEvents.player_died.emit()
	AudioManager.play_sfx("player_death", 0.0, 0.0)
	if _footstep_player and _footstep_player.playing:
		_footstep_player.stop()
	if _gallop_player and _gallop_player.playing:
		_gallop_player.stop()
	if _mounted:
		_interaction.force_dismount()
	velocity = Vector3.ZERO
	set_physics_process(false)
	await get_tree().create_timer(2.0).timeout
	_respawn()
	set_physics_process(true)


func _respawn() -> void:
	if _in_cave:
		_interaction.exit_cave()
	if _mounted:
		_interaction.force_dismount()
	if _bow_drawing:
		_cancel_bow_draw()
	velocity = Vector3.ZERO
	current_health = max_health
	_last_safe_position = Vector3.ZERO
	_respawn_grace = 10.0
	var spawn_x := 0.0
	var spawn_z := 0.0
	var spawn_y := 0.5
	var wg := _find_world_generator()
	if wg:
		spawn_y = wg.get_height_at(spawn_x, spawn_z) + 0.2
	if spawn_y > 5.0 or spawn_y < -5.0:
		spawn_y = 0.5
	var spawn_world := Vector3(spawn_x, spawn_y, spawn_z)
	global_position = wg.world_to_scene_pos(spawn_world) if wg else spawn_world
	velocity = Vector3.ZERO
	_is_attacking = false
	_is_jumping = false
	_is_flipping = false
	_is_run_animating = false
	_is_dodging = false
	_is_swimming = false
	_swim_time = 0.0
	_swim_fatigue = 0.0
	_drown_tick_timer = 0.0
	if _player_sprite:
		_player_sprite.visible = true
		if not _gltf_all_meshes.is_empty():
			_gltf_clear_flash()
		elif _player_model_3d:
			_player_model_3d.clear_flash()
		_player_sprite.position.y = _base_sprite_y
		if _gltf_anim_player:
			var s := 4.0 if _is_lowpoly_viking else 0.7
			_player_sprite.scale = Vector3(s, s, s)
		else:
			_player_sprite.scale = Vector3.ONE
		_player_sprite.rotation = Vector3.ZERO
	if _model and _player_yaw_offset != 0.0:
		_model.rotation.y = _player_yaw_offset
	GameEvents.player_health_changed.emit(current_health, max_health)
	GameEvents.player_respawned.emit()


var _mount_anim_player: AnimationPlayer = null
var _mount_current_anim := ""

# ===================================================================
# GLTF MODEL HELPERS
# ===================================================================

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result := _find_anim_player(child)
		if result:
			return result
	return null


func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)


func _gltf_play(anim_name: String) -> void:
	if not _gltf_anim_player:
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
			if _gltf_anim_player.has_animation(candidate):
				if _gltf_current_anim != candidate:
					_gltf_current_anim = candidate
					synced_animation = candidate
					_gltf_playing_clip = candidate
					_gltf_playing_speed = speed
					_gltf_anim_player.speed_scale = speed
					_gltf_anim_player.play(candidate)
				return

	if anim_name == "run":
		for base in ["run", "walk"]:
			for candidate in ["animation." + base, "animation_" + base, base]:
				if _gltf_anim_player.has_animation(candidate):
					if _gltf_current_anim != candidate + "_fast":
						_gltf_current_anim = candidate + "_fast"
						var spd := 1.4 if base == "walk" else 1.0
						synced_animation = candidate
						_gltf_playing_clip = candidate
						_gltf_playing_speed = spd
						_gltf_anim_player.speed_scale = spd
						_gltf_anim_player.play(candidate)
					return

	if _gltf_anim_player.has_animation("NlaTrack"):
		if anim_name == "idle":
			if _gltf_current_anim != "NlaTrack_idle":
				_gltf_current_anim = "NlaTrack_idle"
				synced_animation = "NlaTrack"
				_gltf_playing_clip = "NlaTrack"
				_gltf_playing_speed = 0.0
				_gltf_anim_player.play("NlaTrack")
				_gltf_anim_player.seek(0.0, true)
				_gltf_anim_player.pause()
			return
		if anim_name in ["walk", "run"]:
			var was_paused := _gltf_current_anim == "NlaTrack_idle"
			_gltf_current_anim = "NlaTrack"
			synced_animation = "NlaTrack"
			_gltf_playing_clip = "NlaTrack"
			var spd := 1.4 if anim_name == "run" else 1.0
			_gltf_playing_speed = spd
			if was_paused or not _gltf_anim_player.is_playing():
				_gltf_anim_player.play("NlaTrack")
			_gltf_anim_player.speed_scale = spd
			return

	if not _gltf_play_warned.has(anim_name):
		_gltf_play_warned[anim_name] = true
		if _DEBUG_LOG: print("[PLAYER ANIM] '%s' not found. Available: %s" % [anim_name, _gltf_anim_player.get_animation_list()])


func _lock_torso_height() -> void:
	if _cached_torso_bones.is_empty():
		var rest_positions := {
			"hips": Vector3(0, 1.25, 0),
			"spine": Vector3(0, 0.25, 0),
			"chest": Vector3(0, 0.375, 0),
			"neck": Vector3(0, 0.25, 0),
			"head": Vector3(0, 0.125, 0),
		}
		for bone_name in rest_positions:
			var node := _find_node_recursive(_player_sprite, bone_name)
			if node and node is Node3D:
				_cached_torso_bones[bone_name] = {
					"node": node,
					"rest_pos": rest_positions[bone_name],
				}
	for bone_name in _cached_torso_bones:
		var info: Dictionary = _cached_torso_bones[bone_name]
		var node: Node3D = info["node"]
		node.position = info["rest_pos"]


const _UPPER_BODY_BONES: Array[String] = [
	"mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2",
	"mixamorig_Neck", "mixamorig_Head",
	"mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm", "mixamorig_LeftHand",
	"mixamorig_RightShoulder", "mixamorig_RightArm", "mixamorig_RightForeArm", "mixamorig_RightHand",
]


func _blend_upper_body_attack() -> void:
	if _gltf_attack_anim.is_empty() or not _gltf_anim_player:
		return
	var skel := _find_skeleton(_player_sprite)
	if not skel:
		return

	var anim_name := ""
	for candidate in ["animation." + _gltf_attack_anim, "animation_" + _gltf_attack_anim, _gltf_attack_anim]:
		if _gltf_anim_player.has_animation(candidate):
			anim_name = candidate
			break
	if anim_name.is_empty():
		return

	var anim: Animation = _gltf_anim_player.get_animation(anim_name)
	if not anim:
		return

	var speed_overrides: Dictionary = {
		"kick": 2.0, "punch": 2.5, "punch_alt": 2.0,
	}
	var speed: float = speed_overrides.get(_gltf_attack_anim, 1.0)
	var t := clampf(_unarmed_attack_time * speed, 0.0, anim.length)

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


func _update_2h_left_grip() -> void:
	if not _equipped_weapon_node or not _l_grip_marker:
		return
	if not _cached_l_upper_arm:
		_cached_l_upper_arm = _find_node_recursive(_player_sprite, "L_UpperArm")
	if not _cached_l_forearm:
		_cached_l_forearm = _find_node_recursive(_player_sprite, "L_Forearm")
	if not _cached_l_hand:
		_cached_l_hand = _find_node_recursive(_player_sprite, "L_Hand")
	if not _cached_l_upper_arm or not _cached_l_forearm or not _cached_l_hand:
		return

	var grip_world := _l_grip_marker.global_position
	var upper_world := _cached_l_upper_arm.global_position

	var upper_len := _cached_l_upper_arm.global_position.distance_to(_cached_l_forearm.global_position)
	var lower_len := _cached_l_forearm.global_position.distance_to(_cached_l_hand.global_position)
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

	var parent_upper := _cached_l_upper_arm.get_parent() as Node3D
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

	var anim_upper := _cached_l_upper_arm.quaternion
	_cached_l_upper_arm.quaternion = anim_upper.slerp(upper_quat, 0.6)

	var fore_parent := _cached_l_forearm.get_parent() as Node3D
	if not fore_parent:
		return

	var fore_grip_world := grip_world - _cached_l_forearm.global_position
	if fore_grip_world.length() < 0.001:
		return
	var fore_local_dir := (fore_parent.global_basis.inverse() * fore_grip_world.normalized()).normalized()
	var fore_quat: Quaternion
	if rest_dir.cross(fore_local_dir).length_squared() > 0.0001:
		fore_quat = Quaternion(rest_dir, fore_local_dir)
	else:
		fore_quat = Quaternion.IDENTITY

	var anim_fore := _cached_l_forearm.quaternion
	_cached_l_forearm.quaternion = anim_fore.slerp(fore_quat, 0.6)


func _rebuild_axe_swing_horizontal() -> void:
	if not _gltf_anim_player:
		return

	var old_name := ""
	for candidate in ["animation.axe_swing", "animation_axe_swing", "axe_swing"]:
		if _gltf_anim_player.has_animation(candidate):
			old_name = candidate
			break
	if old_name == "":
		return

	var old_anim := _gltf_anim_player.get_animation(old_name)

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

	var lib := _gltf_anim_player.get_animation_library("")
	if lib:
		if lib.has_animation(old_name):
			lib.remove_animation(old_name)
		lib.add_animation(old_name, new_anim)


func _rebuild_bow_draw_animation() -> void:
	if not _gltf_anim_player:
		return
	var ref_name := ""
	for candidate in ["animation.axe_swing", "animation_axe_swing", "axe_swing"]:
		if _gltf_anim_player.has_animation(candidate):
			ref_name = candidate
			break
	if ref_name == "":
		return
	var ref_anim := _gltf_anim_player.get_animation(ref_name)
	var bone_paths: Dictionary = {}
	for track_idx in ref_anim.get_track_count():
		var path := ref_anim.track_get_path(track_idx)
		var parts := path.get_concatenated_names().split("/")
		bone_paths[parts[-1] if parts.size() > 0 else path.get_concatenated_names()] = path

	# 5 phases: idle â†’ nock (reach to quiver) â†’ raise â†’ mid-draw â†’ full draw
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

	var lib := _gltf_anim_player.get_animation_library("")
	if lib:
		var anim_name := "animation.bow_draw"
		if lib.has_animation(anim_name):
			lib.remove_animation(anim_name)
		lib.add_animation(anim_name, anim)


func _rebuild_bow_release_animation() -> void:
	if not _gltf_anim_player:
		return
	var ref_name := ""
	for candidate in ["animation.axe_swing", "animation_axe_swing", "axe_swing"]:
		if _gltf_anim_player.has_animation(candidate):
			ref_name = candidate
			break
	if ref_name == "":
		return
	var ref_anim := _gltf_anim_player.get_animation(ref_name)
	var bone_paths: Dictionary = {}
	for track_idx in ref_anim.get_track_count():
		var path := ref_anim.track_get_path(track_idx)
		var parts := path.get_concatenated_names().split("/")
		bone_paths[parts[-1] if parts.size() > 0 else path.get_concatenated_names()] = path

	# Release: snap â†’ recoil â†’ hold follow-through â†’ return to idle
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

	var lib := _gltf_anim_player.get_animation_library("")
	if lib:
		var anim_name := "animation.bow_release"
		if lib.has_animation(anim_name):
			lib.remove_animation(anim_name)
		lib.add_animation(anim_name, anim)


func _build_melee_anim(anim_name: String, length: float, times: PackedFloat32Array, kf: Dictionary) -> void:
	if not _gltf_anim_player:
		return
	var ref_name := ""
	for candidate in ["animation.axe_swing", "animation_axe_swing", "axe_swing"]:
		if _gltf_anim_player.has_animation(candidate):
			ref_name = candidate
			break
	if ref_name == "":
		return
	var ref_anim := _gltf_anim_player.get_animation(ref_name)
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
	var lib := _gltf_anim_player.get_animation_library("")
	if lib:
		var full_name := "animation." + anim_name
		if lib.has_animation(full_name):
			lib.remove_animation(full_name)
		lib.add_animation(full_name, anim)


func _rebuild_club_smash_animation() -> void:
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
	_build_melee_anim("club_smash", 0.80, times, kf)


func _rebuild_sword_slash_animation() -> void:
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
	_build_melee_anim("sword_slash", 0.72, times, kf)


func _gltf_flash(col: Color) -> void:
	for mi in _gltf_all_meshes:
		var mat := mi.get_active_material(0)
		if mat is ShaderMaterial:
			mat.set_shader_parameter("rim_color", col)
			mat.set_shader_parameter("rim_intensity", 1.0)
			mat.set_shader_parameter("rim_power", 1.5)
		elif mat is StandardMaterial3D:
			mat.emission_enabled = true
			mat.emission = col
			mat.emission_energy_multiplier = 2.0


func _gltf_clear_flash() -> void:
	for mi in _gltf_all_meshes:
		var mat := mi.get_active_material(0)
		if mat is ShaderMaterial:
			mat.set_shader_parameter("rim_color", Color(1.0, 1.0, 1.0))
			mat.set_shader_parameter("rim_intensity", 0.0)
			mat.set_shader_parameter("rim_power", 2.0)
		elif mat is StandardMaterial3D:
			mat.emission_enabled = false
			mat.emission = Color.BLACK

func _apply_pahlevan_texture() -> void:
	var tex_path := "res://models/player/Pahlevan/Pahlevan_tripo_node_641e01bc-4c81-4461-be84-6538ef0e1a1a.jpg"
	if not ResourceLoader.exists(tex_path):
		if _DEBUG_LOG: print("[PLAYER MODEL] Pahlevan texture not found: ", tex_path)
		return
	var tex: Texture2D = load(tex_path)
	if not tex:
		return
	var shader_res: Shader = load("res://shaders/oathbound_character.gdshader") as Shader
	if shader_res:
		for mi in _gltf_all_meshes:
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
		for mi in _gltf_all_meshes:
			mi.material_override = mat
	if _DEBUG_LOG: print("[PLAYER MODEL] Applied Pahlevan texture+shader to %d meshes" % _gltf_all_meshes.size())


func _apply_tripo_player_texture() -> void:
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
	for mi in _gltf_all_meshes:
		mi.material_override = mat
		mi.visible = true
	if _DEBUG_LOG: print("[PLAYER MODEL] Applied Tripo barbarian texture to %d meshes" % _gltf_all_meshes.size())


func _apply_viking_texture() -> void:
	# Extract materials from the textured GLB and apply them to the FBX meshes.
	# The FBX meshes are skinned to the skeleton (so they animate), but Mixamo
	# strips material data. The GLB from Tripo has the correct materials.
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

	# Collect all materials from the GLB in surface order
	var glb_meshes: Array[MeshInstance3D] = []
	_collect_mesh_instances(glb_inst, glb_meshes)

	var glb_materials: Array[Material] = []
	for mi in glb_meshes:
		if not mi.mesh:
			continue
		for surf_idx in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(surf_idx)
			if mat:
				glb_materials.append(mat)

	if _DEBUG_LOG: print("[PLAYER MODEL] Extracted %d materials from GLB" % glb_materials.size())

	# Make FBX meshes visible and apply GLB materials
	var mat_idx := 0
	for mi in _gltf_all_meshes:
		mi.visible = true
		if not mi.mesh:
			continue
		for surf_idx in mi.mesh.get_surface_count():
			if mat_idx < glb_materials.size():
				mi.set_surface_override_material(surf_idx, glb_materials[mat_idx])
				mat_idx += 1
			else:
				# More FBX surfaces than GLB materials â€” reuse last material
				if not glb_materials.is_empty():
					mi.set_surface_override_material(surf_idx, glb_materials[glb_materials.size() - 1])

	if _DEBUG_LOG: print("[PLAYER MODEL] Applied %d materials to FBX meshes (%d surfaces)" % [glb_materials.size(), mat_idx])

	# Free the temporary GLB instance â€” we only needed its materials
	glb_inst.queue_free()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _get_mesh_height(meshes: Array[MeshInstance3D]) -> float:
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


func _get_mesh_center_y(meshes: Array[MeshInstance3D]) -> float:
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


func _apply_oathbound_shader() -> void:
	var shader_res := load("res://shaders/oathbound_character.gdshader")
	if not shader_res:
		return
	for mi in _gltf_all_meshes:
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


func _find_node_recursive(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var result := _find_node_recursive(child, target_name)
		if result:
			return result
	return null


func _print_node_tree(node: Node, depth: int) -> void:
	if depth > 6:
		return
	var indent := "  ".repeat(depth)
	if _DEBUG_LOG: print("%s%s (%s)" % [indent, node.name, node.get_class()])
	for child in node.get_children():
		_print_node_tree(child, depth + 1)


func _load_external_animations() -> void:
	if not _gltf_anim_player:
		return
	var lib := _gltf_anim_player.get_animation_library("")
	if not lib:
		lib = AnimationLibrary.new()
		_gltf_anim_player.add_animation_library("", lib)

	var base_dir := "res://models/player/Lowpolyviking/"
	if not ResourceLoader.exists(base_dir + "Warrior Idle.fbx"):
		base_dir = "res://models/player/Pahlevan/"
	var anim_files := {
		"idle": base_dir + "Warrior Idle.fbx",
		"walk": base_dir + "Slow Run.fbx",
		"run": base_dir + "Running.fbx",
		"jump": base_dir + "Jumping.fbx",
		"standing_jump": base_dir + "Jumping.fbx",
		"sit": base_dir + "Sitting.fbx",
		"swim": base_dir + "Swimming.fbx",
		"bow_draw": base_dir + "Standing Draw Arrow.fbx",
		"bow_hold": base_dir + "Standing Aim Overdraw.fbx",
		"sword_slash": base_dir + "Great Sword Slash.fbx",
		"spin_attack": base_dir + "Great Sword Kick.fbx",
		"jump_attack": base_dir + "Great Sword Kick.fbx",
		"heavy_swing": base_dir + "Heavy Weapon Swing.fbx",
		"punch": base_dir + "Hook Punch.fbx",
		"kick": base_dir + "Side Kick.fbx",
		"punch_alt": base_dir + "Punching.fbx",
	}

	for anim_name in anim_files:
		var path: String = anim_files[anim_name]
		if not ResourceLoader.exists(path):
			if _DEBUG_LOG: print("[PLAYER MODEL] External anim not found: ", path)
			continue
		var scene := load(path) as PackedScene
		if not scene:
			if _DEBUG_LOG: print("[PLAYER MODEL] Could not load: ", path)
			continue
		var inst := scene.instantiate()
		var ext_player: AnimationPlayer = _find_anim_player(inst)
		if ext_player:
			var ext_list := ext_player.get_animation_list()
			for ext_name in ext_list:
				var anim := ext_player.get_animation(ext_name)
				if anim:
					var copy := anim.duplicate()
					var lib_name: String = "animation." + anim_name
					if lib.has_animation(lib_name):
						lib.remove_animation(lib_name)
					lib.add_animation(lib_name, copy)
					if _DEBUG_LOG: print("[PLAYER MODEL] Loaded external: %s -> %s (%.2fs)" % [path.get_file(), lib_name, copy.length])
					break
		else:
			if _DEBUG_LOG: print("[PLAYER MODEL] No AnimationPlayer in: ", path)
		inst.queue_free()


var _nla_debug_index := -1
var _nla_debug_names: Array[String] = []

func _rename_nla_tracks() -> void:
	if not _gltf_anim_player:
		return
	var anim_list := _gltf_anim_player.get_animation_list()
	var has_nla := false
	for a in anim_list:
		if a.begins_with("NlaTrack"):
			has_nla = true
			break
	if not has_nla:
		return

	_nla_debug_names.clear()
	for a in anim_list:
		if a.begins_with("NlaTrack"):
			_nla_debug_names.append(a)
	_nla_debug_names.sort()

	var nla_order := ["sit", "chop", "afraid", "stand", "walk", "stand_alt", "run", "kick", "swim"]

	for i in _nla_debug_names.size():
		var a := _nla_debug_names[i]
		var logical: String = nla_order[i] if i < nla_order.size() else "unknown_%d" % i
		var anim := _gltf_anim_player.get_animation(a)
		if anim:
			if _DEBUG_LOG: print("[PLAYER MODEL] Track %d: %s -> %s (%.2fs)" % [i, a, logical, anim.length])

	var lib := _gltf_anim_player.get_animation_library("")
	if not lib:
		if _DEBUG_LOG: print("[PLAYER MODEL] No default animation library found, checking all libraries...")
		var lib_names := _gltf_anim_player.get_animation_library_list()
		if _DEBUG_LOG: print("[PLAYER MODEL] Available libraries: ", lib_names)
		if lib_names.size() > 0:
			lib = _gltf_anim_player.get_animation_library(lib_names[0])
			if _DEBUG_LOG: print("[PLAYER MODEL] Using library: ", lib_names[0])
		if not lib:
			if _DEBUG_LOG: print("[PLAYER MODEL] ERROR: Could not find any animation library!")
			return

	for i in _nla_debug_names.size():
		if i >= nla_order.size():
			break
		var old_name: String = _nla_debug_names[i]
		var new_name: String = nla_order[i]
		if old_name == new_name:
			continue
		if lib.has_animation(old_name):
			var anim := lib.get_animation(old_name)
			lib.remove_animation(old_name)
			if lib.has_animation(new_name):
				lib.remove_animation(new_name)
			lib.add_animation(new_name, anim)
			if _DEBUG_LOG: print("[PLAYER MODEL] Renamed %s -> %s" % [old_name, new_name])
		else:
			if _DEBUG_LOG: print("[PLAYER MODEL] WARNING: Track '%s' not found in library" % old_name)

	var final_anims := _gltf_anim_player.get_animation_list()
	if _DEBUG_LOG: print("[PLAYER MODEL] Final animation list: ", final_anims)


func _strip_root_motion(anim: Animation) -> void:
	var root_bones := ["Root", "Hip", "Pelvis", "Hips", "root", "hip"]
	for i in range(anim.get_track_count() - 1, -1, -1):
		var path := anim.track_get_path(i)
		var path_str := str(path)
		var bone_part := path_str.get_slice(":", 1) if ":" in path_str else path_str.split("/")[-1]
		if bone_part in root_bones and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			anim.remove_track(i)
			if _DEBUG_LOG: print("[PLAYER MODEL] Stripped root motion track: ", path_str)


func _create_bone_attachment(label: String, bone_names: Array) -> Node3D:
	var skel := _find_skeleton(_player_sprite)
	if not skel:
		if _DEBUG_LOG: print("[PLAYER MODEL] No Skeleton3D found for bone attachment: ", label)
		return null
	if _DEBUG_LOG: print("[PLAYER MODEL] Skeleton3D bones: ", _get_bone_names(skel))
	for bname in bone_names:
		var bone_idx := skel.find_bone(bname)
		if bone_idx >= 0:
			var attachment := BoneAttachment3D.new()
			attachment.name = "Attach_" + label
			attachment.bone_name = bname
			attachment.bone_idx = bone_idx
			skel.add_child(attachment)
			if _DEBUG_LOG: print("[PLAYER MODEL] Attached ", label, " to bone: ", bname, " (idx ", bone_idx, ")")
			return attachment
	if _DEBUG_LOG: print("[PLAYER MODEL] No matching bone for ", label, " tried: ", bone_names)
	return null


func _get_bone_names(skel: Skeleton3D) -> Array:
	var names := []
	for i in skel.get_bone_count():
		names.append(skel.get_bone_name(i))
	return names


func _enhance_character_model() -> void:
	if not _player_sprite:
		return
	_add_character_eyes()
	_apply_natural_posture()


func _add_character_eyes() -> void:
	var head_node := _find_node_recursive(_player_sprite, "head")
	if not head_node:
		return

	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.08, 0.06, 0.05)
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var white_mat := StandardMaterial3D.new()
	white_mat.albedo_color = Color(0.85, 0.82, 0.78)
	white_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for side in [-1.0, 1.0]:
		var eye_white := MeshInstance3D.new()
		eye_white.name = "EyeWhite_L" if side < 0 else "EyeWhite_R"
		var white_box := BoxMesh.new()
		white_box.size = Vector3(0.065, 0.04, 0.02)
		eye_white.mesh = white_box
		eye_white.set_surface_override_material(0, white_mat)
		eye_white.position = Vector3(side * 0.075, 0.25, -0.19)
		head_node.add_child(eye_white)

		var pupil := MeshInstance3D.new()
		pupil.name = "Pupil_L" if side < 0 else "Pupil_R"
		var pupil_box := BoxMesh.new()
		pupil_box.size = Vector3(0.035, 0.035, 0.025)
		pupil.mesh = pupil_box
		pupil.set_surface_override_material(0, eye_mat)
		pupil.position = Vector3(side * 0.075, 0.25, -0.195)
		head_node.add_child(pupil)


func _apply_natural_posture() -> void:
	var _set_rot := func(node_name: String, x_deg: float, y_deg: float, z_deg: float) -> void:
		var node := _find_node_recursive(_player_sprite, node_name)
		if node and node is Node3D:
			(node as Node3D).rotation.x += deg_to_rad(x_deg)
			(node as Node3D).rotation.y += deg_to_rad(y_deg)
			(node as Node3D).rotation.z += deg_to_rad(z_deg)

	_set_rot.call("spine", 3.0, 0.0, 0.0)
	_set_rot.call("chest", -1.5, 0.0, 0.0)
	_set_rot.call("neck", -2.0, 0.0, 0.0)
	_set_rot.call("L_Shoulder", 0.0, 0.0, -6.0)
	_set_rot.call("R_Shoulder", 0.0, 0.0, 6.0)
	_set_rot.call("L_UpperArm", 5.0, 0.0, -4.0)
	_set_rot.call("R_UpperArm", 5.0, 0.0, 4.0)
	_set_rot.call("L_Forearm", 8.0, 0.0, 0.0)
	_set_rot.call("R_Forearm", 8.0, 0.0, 0.0)
	_set_rot.call("L_Thigh", -2.0, 0.0, 0.0)
	_set_rot.call("R_Thigh", 2.0, 2.0, 0.0)
	_set_rot.call("head", -2.0, 3.0, 0.0)


var _weapon_is_glb := false


func _compute_glb_weapon_scale(wpn_node: Node3D, target_torso_multiplier: float) -> float:
	var skel := _find_skeleton(_player_sprite)
	if not skel:
		return 0.002
	var hips_idx := skel.find_bone("mixamorig_Hips")
	var head_idx := skel.find_bone("mixamorig_Head")
	if hips_idx < 0 or head_idx < 0:
		return 0.002
	var torso_h: float = (skel.get_bone_global_rest(head_idx).origin - skel.get_bone_global_rest(hips_idx).origin).length()
	var target_len: float = torso_h * target_torso_multiplier
	var aabb: AABB = _get_armor_aabb(wpn_node)
	var model_max: float = maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z)
	if model_max < 0.0001:
		return 0.002
	var base_scale := target_len / model_max
	var sprite_scale := _player_sprite.scale.x if _player_sprite else 1.0
	if sprite_scale > 1.0:
		base_scale /= sprite_scale
	return base_scale


func _try_load_weapon_glb(path: String) -> Node3D:
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path) as PackedScene
		if scene:
			_weapon_is_glb = true
			return scene.instantiate() as Node3D
	return null

func _get_weapon_model_for_class(wclass: String) -> Node3D:
	var glb_paths := {
		"axe": ["res://models/weapons/2h_axe/2h_axe.glb", "res://models/weapons/2h_labrys/2h_labrys.glb"],
		"bow": ["res://models/weapons/bow/bow.glb"],
		"sword": ["res://models/weapons/sword/sword.glb"],
	}
	if glb_paths.has(wclass):
		for path in glb_paths[wclass]:
			var glb := _try_load_weapon_glb(path)
			if glb:
				return glb
	match wclass:
		"axe":   return _create_stone_axe_2h()
		"bow":   return _create_crude_bow()
		"sword": return _create_sword_model()
	return null


func _update_equipped_weapon_model() -> void:
	if _equipped_weapon_node:
		_equipped_weapon_node.queue_free()
		_equipped_weapon_node = null
	if _bow_arrow_node:
		_bow_arrow_node.queue_free()
		_bow_arrow_node = null
	if _quiver_node:
		_quiver_node.queue_free()
		_quiver_node = null
	_l_grip_marker = null
	_cached_l_upper_arm = null
	_cached_l_forearm = null
	_cached_l_hand = null
	_cached_torso_bones.clear()
	_weapon_drawn = false
	_weapon_is_glb = false
	_weapon_back_transform.clear()
	_weapon_hand_transform.clear()

	if not _r_hand_anchor:
		for bone_name in ["Anchor_R_Hand", "RightHand", "mixamorig_RightHand", "right_hand", "Hand_R", "hand_r"]:
			_r_hand_anchor = _find_node_recursive(_player_sprite, bone_name)
			if _r_hand_anchor:
				break
	if not _r_hand_anchor:
		_r_hand_anchor = _create_bone_attachment("RightHand", ["R_Hand", "RightHand", "mixamorig_RightHand", "right_hand", "Hand_R", "hand.R", "Hand.R"])
	if not _r_hand_anchor:
		if _DEBUG_LOG: print("[PLAYER MODEL] WARNING: No right hand anchor found!")
		return

	if not _back_anchor:
		var spine_node: Node3D = null
		for bone_name in ["spine", "Spine", "Spine1", "mixamorig_Spine", "spine_01"]:
			spine_node = _find_node_recursive(_player_sprite, bone_name)
			if spine_node:
				break
		if not spine_node:
			spine_node = _create_bone_attachment("Spine", ["Spine01", "Spine02", "Waist", "Spine", "spine", "Spine1", "mixamorig_Spine", "spine_01"])
		if spine_node and spine_node is Node3D:
			_back_anchor = Node3D.new()
			_back_anchor.name = "BackAnchor"
			_back_anchor.position = Vector3(0, 0.05, 0.08)
			spine_node.add_child(_back_anchor)

	var wpn_data := ItemDatabase.get_item(equipped_weapon)
	var is_2h := str(wpn_data.get("hands", "1h")) == "2h"
	var wclass := ItemDatabase.get_weapon_class(equipped_weapon)

	if wclass == "bow":
		if not _l_hand_anchor:
			for bone_name in ["Anchor_L_Hand", "LeftHand", "mixamorig_LeftHand", "left_hand", "Hand_L", "hand_l"]:
				_l_hand_anchor = _find_node_recursive(_player_sprite, bone_name)
				if _l_hand_anchor:
					break
		if not _l_hand_anchor:
			_l_hand_anchor = _create_bone_attachment("LeftHand", ["L_Hand", "LeftHand", "mixamorig_LeftHand", "left_hand", "Hand_L", "hand.L", "Hand.L"])
		if not _l_hand_anchor:
			return
		_equipped_weapon_node = _get_weapon_model_for_class("bow")
		_equipped_weapon_node.name = "EquippedWeapon"
		var fallback_bow_s := 1.2 / (_player_sprite.scale.x / 200.0) if _player_sprite else 1.2
		var bow_s := _compute_glb_weapon_scale(_equipped_weapon_node, 1.0) if _weapon_is_glb else fallback_bow_s
		_weapon_hand_transform = {
			"parent": _l_hand_anchor,
			"scale": Vector3(bow_s, bow_s, bow_s),
			"pos": Vector3(0, -0.02, 0),
			"rot": Vector3(deg_to_rad(90), 0, 0),
		}
		_weapon_back_transform = {
			"scale": Vector3(bow_s, bow_s, bow_s),
			"pos": Vector3(0.0, 0.1, 0.0) if _weapon_is_glb else Vector3(0.10, 0.0, -0.04),
			"rot": Vector3(0, deg_to_rad(90), deg_to_rad(15)),
		}

		_quiver_node = _create_quiver()
		_quiver_node.name = "Quiver"
		_quiver_node.position = Vector3(-0.12, 0.0, -0.02)
		if _back_anchor:
			_back_anchor.add_child(_quiver_node)

		_bow_arrow_node = _create_bow_arrow()
		_bow_arrow_node.name = "BowArrow"
		_bow_arrow_node.rotation = Vector3(deg_to_rad(90), 0, 0)
		_bow_arrow_node.position = Vector3(0, -0.02, 0)
		_bow_arrow_node.visible = false
		_r_hand_anchor.add_child(_bow_arrow_node)
	elif wclass == "fists":
		return
	else:
		_equipped_weapon_node = _get_weapon_model_for_class(wclass)
		if not _equipped_weapon_node:
			return
		_equipped_weapon_node.name = "EquippedWeapon"
		if _weapon_is_glb:
			var target_len := 3.0 if is_2h else 1.5
			var wpn_s := _compute_glb_weapon_scale(_equipped_weapon_node, target_len)
			if is_2h:
				_weapon_hand_transform = {
					"parent": _r_hand_anchor,
					"scale": Vector3(wpn_s, wpn_s, wpn_s),
					"pos": Vector3(0, -0.02, 0),
					"rot": Vector3(deg_to_rad(90), 0, 0),
				}
				_weapon_back_transform = {
					"scale": Vector3(wpn_s, wpn_s, wpn_s),
					"pos": Vector3(0.0, 0.1, 0.0),
					"rot": Vector3(deg_to_rad(10), 0, deg_to_rad(180)),
				}
			else:
				_weapon_hand_transform = {
					"parent": _r_hand_anchor,
					"scale": Vector3(wpn_s, wpn_s, wpn_s),
					"pos": Vector3(0, -0.02, 0),
					"rot": Vector3(deg_to_rad(90), 0, 0),
				}
				_weapon_back_transform = {
					"scale": Vector3(wpn_s, wpn_s, wpn_s),
					"pos": Vector3(0.0, 0.1, 0.0),
					"rot": Vector3(deg_to_rad(10), 0, deg_to_rad(180)),
				}
		else:
			var scale_adj := 200.0 / _player_sprite.scale.x if _player_sprite else 1.0
			if is_2h:
				var s2h := 2.0 * scale_adj
				_weapon_hand_transform = {
					"parent": _r_hand_anchor,
					"scale": Vector3(s2h, s2h, s2h),
					"pos": Vector3(0, -0.14, 0),
					"rot": Vector3(deg_to_rad(180), deg_to_rad(180), 0),
				}
				_weapon_back_transform = {
					"scale": Vector3(s2h, s2h, s2h),
					"pos": Vector3(0.15, 0.0, -0.04),
					"rot": Vector3(deg_to_rad(10), deg_to_rad(180), 0),
				}
			else:
				var s1h_v := 1.4 * scale_adj
				var s1h := Vector3(s1h_v, s1h_v, s1h_v)
				_weapon_hand_transform = {
					"parent": _r_hand_anchor,
					"scale": s1h,
					"pos": Vector3(0, -0.06, 0),
					"rot": Vector3(deg_to_rad(180), deg_to_rad(180), 0),
				}
				_weapon_back_transform = {
					"scale": s1h,
					"pos": Vector3(0.12, 0.0, -0.04),
					"rot": Vector3(deg_to_rad(10), deg_to_rad(180), 0),
				}

	if _equipped_weapon_node:
		if _back_anchor:
			_stow_weapon()
		else:
			_draw_weapon()
		for mi in _get_all_mesh_instances(_equipped_weapon_node):
			if mi.mesh:
				for si in mi.mesh.get_surface_count():
					var mat := mi.get_active_material(si)
					if mat is StandardMaterial3D:
						(mat as StandardMaterial3D).texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST


func _stow_weapon() -> void:
	if not _equipped_weapon_node or not _back_anchor:
		return
	if not _weapon_drawn and _equipped_weapon_node.get_parent() == _back_anchor:
		return
	if _equipped_weapon_node.get_parent():
		_equipped_weapon_node.get_parent().remove_child(_equipped_weapon_node)
	_equipped_weapon_node.scale = _weapon_back_transform.get("scale", Vector3.ONE)
	_equipped_weapon_node.position = _weapon_back_transform.get("pos", Vector3.ZERO)
	_equipped_weapon_node.rotation = _weapon_back_transform.get("rot", Vector3.ZERO)
	_back_anchor.add_child(_equipped_weapon_node)
	_weapon_drawn = false
	_l_grip_marker = null


func _draw_weapon() -> void:
	if not _equipped_weapon_node:
		return
	if _weapon_drawn:
		return
	var hand_parent: Node3D = _weapon_hand_transform.get("parent", _r_hand_anchor)
	if _equipped_weapon_node.get_parent():
		_equipped_weapon_node.get_parent().remove_child(_equipped_weapon_node)
	_equipped_weapon_node.scale = _weapon_hand_transform.get("scale", Vector3.ONE)
	_equipped_weapon_node.position = _weapon_hand_transform.get("pos", Vector3.ZERO)
	_equipped_weapon_node.rotation = _weapon_hand_transform.get("rot", Vector3.ZERO)
	hand_parent.add_child(_equipped_weapon_node)
	_weapon_drawn = true
	var wpn_data := ItemDatabase.get_item(equipped_weapon)
	var is_2h := str(wpn_data.get("hands", "1h")) == "2h"
	if is_2h and not _l_grip_marker:
		var grip := Node3D.new()
		grip.name = "LeftGrip"
		grip.position = Vector3(0, -0.22, 0)
		_equipped_weapon_node.add_child(grip)
		_l_grip_marker = grip


func _create_stone_axe_2h() -> Node3D:
	var root := Node3D.new()

	var wood_mat := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.45, 0.32, 0.18)
	wood_mat.roughness = 0.9
	wood_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.52, 0.50, 0.48)
	stone_mat.roughness = 0.95
	stone_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	var leather_mat := StandardMaterial3D.new()
	leather_mat.albedo_color = Color(0.35, 0.22, 0.12)
	leather_mat.roughness = 0.85
	leather_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	var edge_mat := StandardMaterial3D.new()
	edge_mat.albedo_color = Color(0.62, 0.60, 0.56)
	edge_mat.roughness = 0.80
	edge_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	# Long handle shaft
	_add_box_part(root, "shaft", Vector3(0.028, 0.80, 0.028), Vector3(0, -0.05, 0), wood_mat)
	# Pommel knob
	_add_box_part(root, "knob", Vector3(0.042, 0.025, 0.042), Vector3(0, -0.46, 0), wood_mat)

	# Lower grip wraps (bottom hand)
	_add_box_part(root, "grip_lo1", Vector3(0.037, 0.022, 0.037), Vector3(0, -0.38, 0), leather_mat)
	_add_box_part(root, "grip_lo2", Vector3(0.037, 0.022, 0.037), Vector3(0, -0.33, 0), leather_mat)
	_add_box_part(root, "grip_lo3", Vector3(0.037, 0.022, 0.037), Vector3(0, -0.28, 0), leather_mat)
	# Upper grip wraps (top hand)
	_add_box_part(root, "grip_hi1", Vector3(0.035, 0.020, 0.035), Vector3(0, -0.08, 0), leather_mat)
	_add_box_part(root, "grip_hi2", Vector3(0.035, 0.020, 0.035), Vector3(0, -0.03, 0), leather_mat)

	# â”€â”€ Axe head â€” single-edge crescent blade â”€â”€
	# Core block where head meets handle
	_add_box_part(root, "head_core", Vector3(0.09, 0.11, 0.034), Vector3(0.04, 0.33, 0), stone_mat)
	# Main blade body
	_add_box_part(root, "blade_body", Vector3(0.07, 0.16, 0.024), Vector3(0.10, 0.33, 0), stone_mat)
	# Blade edge â€” taller crescent profile
	_add_box_part(root, "blade_edge", Vector3(0.05, 0.20, 0.016), Vector3(0.155, 0.33, 0), edge_mat)
	# Blade tip â€” thin crescent point
	_add_box_part(root, "blade_tip", Vector3(0.025, 0.17, 0.010), Vector3(0.19, 0.33, 0), edge_mat)
	# Poll (back of head, small counterweight)
	_add_box_part(root, "poll", Vector3(0.03, 0.06, 0.028), Vector3(-0.025, 0.33, 0), stone_mat)
	# Head top/bottom caps
	_add_box_part(root, "head_top", Vector3(0.07, 0.018, 0.030), Vector3(0.06, 0.40, 0), stone_mat)
	_add_box_part(root, "head_bot", Vector3(0.07, 0.018, 0.030), Vector3(0.06, 0.26, 0), stone_mat)

	# Leather bindings at headâ€“shaft junction
	_add_box_part(root, "bind1", Vector3(0.044, 0.013, 0.044), Vector3(0, 0.26, 0), leather_mat)
	_add_box_part(root, "bind2", Vector3(0.044, 0.013, 0.044), Vector3(0, 0.28, 0), leather_mat)
	_add_box_part(root, "bind_x", Vector3(0.013, 0.06, 0.044), Vector3(0.005, 0.30, 0), leather_mat)

	return root


func _add_box_part(parent: Node3D, part_name: String, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mi.mesh = box
	mi.position = pos
	parent.add_child(mi)


func _create_crude_bow() -> Node3D:
	var root := Node3D.new()
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.50, 0.36, 0.20)
	wood.roughness = 0.9
	wood.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var dark_wood := StandardMaterial3D.new()
	dark_wood.albedo_color = Color(0.35, 0.24, 0.14)
	dark_wood.roughness = 0.85
	dark_wood.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var string_mat := StandardMaterial3D.new()
	string_mat.albedo_color = Color(0.82, 0.78, 0.68)
	string_mat.roughness = 0.7
	string_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	_add_box_part(root, "grip", Vector3(0.035, 0.10, 0.045), Vector3(0, 0, 0), dark_wood)
	_add_box_part(root, "upper1", Vector3(0.028, 0.18, 0.038), Vector3(0, 0.14, 0), wood)
	_add_box_part(root, "upper2", Vector3(0.024, 0.16, 0.032), Vector3(0, 0.30, -0.02), wood)
	_add_box_part(root, "upper3", Vector3(0.020, 0.12, 0.026), Vector3(0, 0.44, -0.05), wood)
	_add_box_part(root, "nock_u", Vector3(0.016, 0.025, 0.016), Vector3(0, 0.52, -0.06), dark_wood)
	_add_box_part(root, "lower1", Vector3(0.028, 0.18, 0.038), Vector3(0, -0.14, 0), wood)
	_add_box_part(root, "lower2", Vector3(0.024, 0.16, 0.032), Vector3(0, -0.30, -0.02), wood)
	_add_box_part(root, "lower3", Vector3(0.020, 0.12, 0.026), Vector3(0, -0.44, -0.05), wood)
	_add_box_part(root, "nock_l", Vector3(0.016, 0.025, 0.016), Vector3(0, -0.52, -0.06), dark_wood)
	_add_box_part(root, "string", Vector3(0.006, 1.04, 0.006), Vector3(0, 0, -0.06), string_mat)
	_add_box_part(root, "wrap1", Vector3(0.040, 0.018, 0.050), Vector3(0, 0.04, 0), dark_wood)
	_add_box_part(root, "wrap2", Vector3(0.040, 0.018, 0.050), Vector3(0, -0.04, 0), dark_wood)
	return root


func _create_quiver() -> Node3D:
	var root := Node3D.new()
	var leather := StandardMaterial3D.new()
	leather.albedo_color = Color(0.38, 0.26, 0.14)
	leather.roughness = 0.85
	leather.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var leather_dark := StandardMaterial3D.new()
	leather_dark.albedo_color = Color(0.28, 0.18, 0.10)
	leather_dark.roughness = 0.9
	leather_dark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.albedo_color = Color(0.55, 0.40, 0.25)
	shaft_mat.roughness = 0.85
	shaft_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var fletch_mat := StandardMaterial3D.new()
	fletch_mat.albedo_color = Color(0.78, 0.72, 0.60)
	fletch_mat.roughness = 0.8
	fletch_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(0.50, 0.48, 0.44)
	tip_mat.roughness = 0.6
	tip_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	_add_box_part(root, "body", Vector3(0.06, 0.32, 0.05), Vector3(-0.10, 0.12, 0.0), leather)
	_add_box_part(root, "rim_top", Vector3(0.065, 0.015, 0.055), Vector3(-0.10, 0.28, 0.0), leather_dark)
	_add_box_part(root, "rim_bot", Vector3(0.065, 0.015, 0.055), Vector3(-0.10, -0.04, 0.0), leather_dark)
	_add_box_part(root, "strap", Vector3(0.012, 0.40, 0.012), Vector3(-0.04, 0.10, 0.02), leather_dark)

	for i in 5:
		var y_off := 0.30 + float(i) * 0.015
		var x_off := -0.10 + (float(i) - 2.0) * 0.012
		_add_box_part(root, "arrow_shaft_%d" % i,
			Vector3(0.010, 0.14, 0.010),
			Vector3(x_off, y_off, 0.0), shaft_mat)
		_add_box_part(root, "arrow_tip_%d" % i,
			Vector3(0.016, 0.025, 0.016),
			Vector3(x_off, y_off + 0.08, 0.0), tip_mat)
		_add_box_part(root, "arrow_fletch_%d" % i,
			Vector3(0.018, 0.03, 0.004),
			Vector3(x_off, y_off - 0.06, 0.0), fletch_mat)

	root.scale = Vector3(1.2, 1.2, 1.2)
	root.rotation = Vector3(0, 0, deg_to_rad(10))
	return root


func _create_bow_arrow() -> Node3D:
	var root := Node3D.new()
	var shaft_mat := StandardMaterial3D.new()
	shaft_mat.albedo_color = Color(0.55, 0.40, 0.25)
	shaft_mat.roughness = 0.85
	shaft_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(0.50, 0.48, 0.44)
	tip_mat.roughness = 0.9
	tip_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var fletch_mat := StandardMaterial3D.new()
	fletch_mat.albedo_color = Color(0.78, 0.72, 0.60)
	fletch_mat.roughness = 0.8
	fletch_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	_add_box_part(root, "shaft", Vector3(0.018, 0.018, 0.55), Vector3(0, 0, 0), shaft_mat)
	_add_box_part(root, "tip", Vector3(0.028, 0.028, 0.05), Vector3(0, 0, -0.30), tip_mat)
	_add_box_part(root, "fletch_h", Vector3(0.032, 0.004, 0.07), Vector3(0, 0, 0.22), fletch_mat)
	_add_box_part(root, "fletch_v", Vector3(0.004, 0.032, 0.07), Vector3(0, 0, 0.22), fletch_mat)
	return root



func _create_sword_model() -> Node3D:
	var root := Node3D.new()
	var blade := StandardMaterial3D.new()
	blade.albedo_color = Color(0.62, 0.60, 0.56)
	blade.roughness = 0.4
	blade.metallic = 0.6
	blade.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var guard := StandardMaterial3D.new()
	guard.albedo_color = Color(0.40, 0.35, 0.25)
	guard.roughness = 0.7
	guard.metallic = 0.3
	guard.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var grip := StandardMaterial3D.new()
	grip.albedo_color = Color(0.30, 0.20, 0.12)
	grip.roughness = 0.9
	grip.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_add_box_part(root, "blade_lo", Vector3(0.05, 0.22, 0.015), Vector3(0, 0.14, 0), blade)
	_add_box_part(root, "blade_hi", Vector3(0.045, 0.20, 0.013), Vector3(0, 0.34, 0), blade)
	_add_box_part(root, "blade_tip", Vector3(0.035, 0.10, 0.012), Vector3(0, 0.50, 0), blade)
	_add_box_part(root, "crossguard", Vector3(0.12, 0.025, 0.03), Vector3(0, 0.01, 0), guard)
	_add_box_part(root, "grip", Vector3(0.032, 0.14, 0.032), Vector3(0, -0.08, 0), grip)
	_add_box_part(root, "pommel", Vector3(0.04, 0.03, 0.04), Vector3(0, -0.17, 0), guard)
	_add_box_part(root, "wrap1", Vector3(0.036, 0.015, 0.036), Vector3(0, -0.04, 0), grip)
	_add_box_part(root, "wrap2", Vector3(0.036, 0.015, 0.036), Vector3(0, -0.12, 0), grip)
	return root



func _get_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node)
	for child in node.get_children():
		result.append_array(_get_all_mesh_instances(child))
	return result
