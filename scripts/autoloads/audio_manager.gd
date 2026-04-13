extends Node
## Singleton that manages all game audio: SFX with random variation and background music.

const SFX_PATH := "res://audio/sfx/"
const VOICE_PATH := "res://audio/voice/"
const MUSIC_PATH := "res://audio/music/"
const MAX_SFX_PLAYERS := 16

var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_3d_pool: Array[AudioStreamPlayer3D] = []
var _pool_idx := 0
var _pool_3d_idx := 0
var _speech_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _music_playlist: Array[String] = []
var _music_shuffle_queue: Array[String] = []

# Preloaded sound groups: key -> Array[AudioStream]
var _sounds: Dictionary = {}


func _ready() -> void:
	_ensure_buses()

	for i in MAX_SFX_PLAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_sfx_pool.append(p)

		var p3d := AudioStreamPlayer3D.new()
		p3d.bus = &"SFX"
		p3d.max_distance = 40.0
		p3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
		add_child(p3d)
		_sfx_3d_pool.append(p3d)

	_speech_player = AudioStreamPlayer.new()
	_speech_player.bus = &"SFX"
	add_child(_speech_player)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = &"Music"
	_music_player.volume_db = -2.0
	add_child(_music_player)

	# Default music volume to 0% for testing — drag the slider up in-game to hear it
	var music_idx := AudioServer.get_bus_index(&"Music")
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, linear_to_db(0.0))

	_preload_sounds()


func _ensure_buses() -> void:
	if AudioServer.get_bus_index(&"SFX") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, &"SFX")
		AudioServer.set_bus_send(idx, &"Master")
	if AudioServer.get_bus_index(&"Music") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, &"Music")
		AudioServer.set_bus_send(idx, &"Master")
		AudioServer.set_bus_volume_db(idx, linear_to_db(0.91))
	if AudioServer.get_bus_index(&"SFX") != -1:
		var idx := AudioServer.get_bus_index(&"SFX")
		if AudioServer.get_bus_volume_db(idx) == 0.0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(0.7))


func _preload_sounds() -> void:
	_load_group("axe_chop", ["axe_chop_1.wav", "axe_chop_2.wav", "axe_chop_3.wav"])
	_load_group("fist_hit_tree", ["fist_hit_tree.wav"])
	_load_group("tree_fall", ["tree_fall_1.wav", "tree_fall_2.wav"])
	_load_group("pickaxe_hit", ["pickaxe_hit_1.wav", "pickaxe_hit_2.wav", "pickaxe_hit_3.wav"])
	_load_group("rock_fall", ["rock_fall_1.wav", "rock_fall_2.wav", "rock_fall_3.wav"])
	_load_group("wood_thud", ["wood_thud_1.wav", "wood_thud_2.wav", "wood_thud_3.wav"])
	_load_group("campfire", ["campfire.wav", "campfire_raging_1.wav", "campfire_raging_2.wav"])
	_load_group("player_hurt", ["player_hurt_1.wav", "player_hurt_2.wav"])
	_load_group("player_death", ["player_death.wav"])
	_load_group("stone_rubble", ["stone_rubble_1.wav", "stone_rubble_2.wav"])
	_load_group("wind_ambient", ["wind_ambient.wav"])
	_load_group("arrow_fire", ["arrow_fire_1.wav", "arrow_fire_2.wav"])
	_load_group("arrow_swoosh", ["arrow_swoosh_1.wav", "arrow_swoosh_2.wav", "arrow_swoosh_3.wav"])
	_load_group("boar_hurt", ["boar_hurt_1.wav"])
	_load_group("lion_hurt", ["lion_hurt_1.wav"])
	_load_group("lion_death", ["lion_death_1.wav"])
	_load_group("lion_roar", ["lion_roar_1.wav"])
	_load_group("wood_pickup", ["wood_pickup_1.wav", "wood_pickup_2.wav"])
	_load_group("horse_gallop", ["horse_gallop_1.wav"])
	_load_group("horse_gallop_fast", ["horse_gallop_fast_1.wav"])
	_load_group("grass_step", ["grass_step_1.wav"])
	_load_group("stone_step", ["stone_step_1.mp3", "stone_step_2.mp3", "stone_step_3.mp3"])
	_load_group("till_ground", ["till_ground_1.mp3", "till_ground_2.mp3"])
	_load_group("bow_creak", ["bow_creak_1.wav", "bow_creak_2.wav"])
	_load_group("flowing_water", ["flowing_water.mp3"])

	# Voice lines (speech barks) — loaded from voice/ folder
	_load_group("speech_dark", [
		"M_dark_getting_dark_need_light.mp3", "M_dark_shadows_growing_long.mp3",
		"M_dark_hard_to_see_path.mp3", "M_dark_sun_abandoning_me.mp3",
		"M_dark_darkness_takes_over.mp3",
	], VOICE_PATH)
	_load_group("speech_inv_full", [
		"M_inv_full_pack_screaming_mercy.mp3", "M_inv_full_more_loot_than_sense.mp3",
		"M_inv_full_something_stays_dirt.mp3", "M_inv_full_carrying_village_worth.mp3",
	], VOICE_PATH)
	_load_group("speech_drowning", [
		"M_drowning_arms_getting_heavy.mp3", "M_drowning_deep_water_no_place.mp3",
	], VOICE_PATH)
	_load_group("speech_shelter", [
		"M_shelter_place_to_rest.mp3", "M_shelter_rain_hitting_roof.mp3",
		"M_shelter_cold_cant_follow.mp3", "M_shelter_breathe_air.mp3",
	], VOICE_PATH)
	_load_group("speech_first_light", [
		"M_first_light_sun_returns_chase_shadows.mp3", "M_first_light_nights_grip_loosens.mp3",
		"M_first_light_light_breaks_horizon.mp3", "M_first_light_clear_skies_fresh.mp3",
		"M_first_light_shadows_retreat.mp3", "M_first_light_golden_light_world_kind.mp3",
	], VOICE_PATH)
	_load_group("speech_killing_spree", [
		"M_killing_spree_let_them_come.mp3", "M_killing_spree_is_that_all.mp3",
		"M_killing_spree_fall_like_wheat.mp3", "M_killing_spree_paint_woods_red.mp3",
		"M_killing_spree_none_shall_stand.mp3", "M_killing_spree_havent_felt_alive.mp3",
	], VOICE_PATH)
	_load_group("speech_village", [
		"M_village_ghost_town.mp3", "M_village_empty_homes_cold_hearths.mp3",
		"M_village_silence_only_living.mp3", "M_village_dust_and_echoes.mp3",
		"M_village_be_quick_wrong_sort.mp3", "M_village_see_what_left_behind.mp3",
	], VOICE_PATH)
	_load_group("speech_close_call", [
		"M_close_call_closer_to_grave.mp3", "M_close_call_abyss_blinked_first.mp3",
		"M_close_call_blood_stays_inside.mp3", "M_close_call_few_inches_closer.mp3",
		"M_close_call_ancestors_not_ready.mp3",
	], VOICE_PATH)
	_load_group("speech_craft_weapon", [
		"M_craft_weapon_legends_weapon.mp3", "M_craft_weapon_symphony_metal.mp3",
		"M_craft_weapon_world_not_ready.mp3", "M_craft_weapon_catches_light.mp3",
		"M_craft_weapon_power_thrumming.mp3", "M_craft_weapon_kings_hall.mp3",
	], VOICE_PATH)
	_load_group("speech_craft_tool", [
		"M_craft_tool_geometry_flawless.mp3", "M_craft_tool_perfectly_balanced.mp3",
		"M_craft_tool_absolute_masterpiece.mp3", "M_craft_tool_glow_struck_gold.mp3",
		"M_craft_tool_by_the_gods.mp3",
	], VOICE_PATH)
	_load_group("speech_loot_drop", [
		"M_loot_drop_scars_worth_it.mp3", "M_loot_drop_prize_blood_spilled.mp3",
		"M_loot_drop_luck_favors_bold.mp3", "M_loot_drop_diamond_in_rough.mp3",
		"M_loot_drop_fate_smiled.mp3", "M_loot_drop_ancestors_watching.mp3",
		"M_loot_drop_hunted_whole_life.mp3", "M_loot_drop_never_seen_exquisite.mp3",
		"M_loot_drop_songs_will_be_sung.mp3", "M_loot_drop_steady_dont_drop.mp3",
		"M_loot_drop_beyond_wildest_dreams.mp3", "M_loot_drop_beaten_the_odds.mp3",
	], VOICE_PATH)
	_load_group("speech_halvard", [
		"M_proximity_halvard_almost_there.mp3", "M_proximity_halvard_closing_in.mp3",
		"M_proximity_halvard_old_fart.mp3", "M_proximity_halvard_hasnt_showered.mp3",
	], VOICE_PATH)
	_load_group("speech_signpost", [
		"M_signpost_camp_nearby_visit.mp3", "M_signpost_settled_camp_offer.mp3",
		"M_signpost_camping_survive_night.mp3", "M_signpost_pitched_tent_coin.mp3",
		"M_signpost_camp_pay_old_man.mp3",
	], VOICE_PATH)
	_load_group("dialogue_quest", [
		"H_quest_grindstone_crumbled_to_dust.mp3", "M_quest_stone_thousand_winters.mp3",
		"H_quest_outlasted_the_men.mp3", "H_quest_edge_not_common_pebbles.mp3",
		"M_quest_deep_bone_different.mp3", "H_quest_surface_stones_brittle.mp3",
		"M_quest_reason_havent_gone.mp3", "H_quest_river_silt_home_goblins.mp3",
		"M_quest_tell_where_to_look.mp3", "H_quest_follow_stream_water_black.mp3",
		"M_quest_not_ready_tangle_goblins.mp3", "H_quest_natures_cruel_smith.mp3",
		"M_quest_return_with_shards.mp3", "H_quest_watch_shadows_reeds.mp3",
		"M_quest_find_my_bearings.mp3", "H_quest_suit_yerself_dull_axe.mp3",
		"M_quest_without_grindstone_fog.mp3",
	], VOICE_PATH)
	_load_group("dialogue_turnin", [
		"H_turnin_fog_took_yeh.mp3", "M_turnin_have_what_you_asked.mp3",
		"M_turnin_fix_grindstone_with_this.mp3", "H_turnin_indeed_deep_bone.mp3",
		"H_turnin_give_me_a_moment.mp3",
	], VOICE_PATH)
	_load_group("halvard_greet", [
		"H_greet_blimey_youve_grown.mp3", "H_greet_kindness_goes_further.mp3",
		"H_greet_pull_up_a_stump.mp3",
	], VOICE_PATH)
	_load_group("halvard_farewell", [
		"H_farewell_goodbye_to_you.mp3", "H_farewell_hope_see_you_soon.mp3",
		"H_farewell_safe_journey_friend.mp3", "H_farewell_shadows_have_teeth.mp3",
		"H_farewell_dont_go_dyin.mp3", "H_farewell_old_bones_need_quiet.mp3",
		"H_farewell_stones_have_ears.mp3",
	], VOICE_PATH)
	_load_group("player_grunt", ["M_grunt_1.mp3", "M_grunt_2.mp3"], VOICE_PATH)


func _load_group(group_name: String, filenames: Array, base_path: String = SFX_PATH) -> void:
	var streams: Array[AudioStream] = []
	for fname: String in filenames:
		var path := base_path + fname
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream:
				streams.append(stream)
	if not streams.is_empty():
		_sounds[group_name] = streams


## Return the first stream from a named group, or null if not found.
func get_stream(group_name: String) -> AudioStream:
	if not _sounds.has(group_name):
		return null
	var streams: Array = _sounds[group_name] as Array
	if streams.is_empty():
		return null
	return streams[0] as AudioStream


## Return a random stream from a named group, or null if not found.
func get_random_stream(group_name: String) -> AudioStream:
	if not _sounds.has(group_name):
		return null
	var streams: Array = _sounds[group_name] as Array
	if streams.is_empty():
		return null
	return streams[randi() % streams.size()] as AudioStream


func get_group_size(group_name: String) -> int:
	if not _sounds.has(group_name):
		return 0
	return (_sounds[group_name] as Array).size()


func get_stream_duration(group_name: String, idx: int) -> float:
	if not _sounds.has(group_name):
		return 0.0
	var streams: Array = _sounds[group_name] as Array
	if idx < 0 or idx >= streams.size():
		return 0.0
	var s: AudioStream = streams[idx] as AudioStream
	return s.get_length() if s else 0.0


func play_speech(group_name: String, idx: int, volume_db: float = -2.0) -> void:
	if not _sounds.has(group_name):
		return
	var streams: Array = _sounds[group_name] as Array
	if idx < 0 or idx >= streams.size():
		return
	_speech_player.stream = streams[idx] as AudioStream
	_speech_player.volume_db = volume_db
	_speech_player.pitch_scale = 1.0
	_speech_player.play()


func play_sfx_indexed(group_name: String, idx: int, volume_db: float = 0.0) -> void:
	if not _sounds.has(group_name):
		return
	var streams: Array = _sounds[group_name] as Array
	if idx < 0 or idx >= streams.size():
		return
	var player := _sfx_pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _sfx_pool.size()
	player.stream = streams[idx] as AudioStream
	player.volume_db = volume_db
	player.pitch_scale = 1.0
	player.play()


## Play a random sound from a named group (non-positional, 2D).
func play_sfx(group_name: String, volume_db: float = 0.0, pitch_variance: float = 0.1) -> void:
	if not _sounds.has(group_name):
		return
	var streams: Array = _sounds[group_name] as Array
	var stream: AudioStream = streams[randi() % streams.size()] as AudioStream
	var player := _sfx_pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _sfx_pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	player.play()


## Play a random sound from a named group at a 3D position.
func play_sfx_at(group_name: String, world_pos: Vector3, volume_db: float = 0.0, pitch_variance: float = 0.1) -> void:
	if not _sounds.has(group_name):
		return
	var streams: Array = _sounds[group_name] as Array
	var stream: AudioStream = streams[randi() % streams.size()] as AudioStream
	var player := _sfx_3d_pool[_pool_3d_idx]
	_pool_3d_idx = (_pool_3d_idx + 1) % _sfx_3d_pool.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = randf_range(1.0 - pitch_variance, 1.0 + pitch_variance)
	player.global_position = world_pos
	player.play()


## Start a single background music track (loops).
func play_music(filename: String, fade_in: float = 2.0) -> void:
	_music_playlist.clear()
	_music_shuffle_queue.clear()
	_play_track(filename, fade_in)


## Start a shuffled playlist. Plays all tracks before repeating any.
func play_music_playlist(filenames: Array[String], fade_in: float = 4.0) -> void:
	_music_playlist = filenames.duplicate()
	_music_shuffle_queue.clear()
	_play_next_shuffle(fade_in)


func _play_next_shuffle(fade_in: float = 3.0) -> void:
	if _music_playlist.is_empty():
		return
	if _music_shuffle_queue.is_empty():
		_music_shuffle_queue = _music_playlist.duplicate()
		_music_shuffle_queue.shuffle()
	var next := _music_shuffle_queue.pop_back() as String
	_play_track(next, fade_in)


func _play_track(filename: String, fade_in: float = 2.0) -> void:
	var path := filename if filename.begins_with("res://") else MUSIC_PATH + filename
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if not stream:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	_music_player.stream = stream
	_music_player.volume_db = -40.0
	_music_player.play()
	if not _music_player.finished.is_connected(_on_music_finished):
		_music_player.finished.connect(_on_music_finished)
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -5.0, fade_in)


func _on_music_finished() -> void:
	if not _music_playlist.is_empty():
		_play_next_shuffle(3.0)
	elif _music_player.stream:
		_music_player.play()


func stop_music(fade_out: float = 2.0) -> void:
	if not _music_player.playing:
		return
	_music_playlist.clear()
	_music_shuffle_queue.clear()
	var tween := create_tween()
	tween.tween_property(_music_player, "volume_db", -40.0, fade_out)
	tween.tween_callback(_music_player.stop)
