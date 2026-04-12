extends Node
## Singleton that manages all game audio: SFX with random variation and background music.

const SFX_PATH := "res://audio/sfx/"
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
	_load_group("player_grunt", ["player_grunt_1.mp3", "player_grunt_2.mp3"])
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
	_load_group("flowing_water", ["flowing_water_#1-1775592827594.mp3"])

	# Voice lines (speech barks)
	_load_group("speech_dark", ["speech_dark_1.mp3", "speech_dark_2.mp3", "speech_dark_3.mp3", "speech_dark_4.mp3", "speech_dark_5.mp3"])
	_load_group("speech_inv_full", ["speech_inv_full_1.mp3", "speech_inv_full_2.mp3", "speech_inv_full_3.mp3", "speech_inv_full_4.mp3"])
	_load_group("speech_drowning", ["speech_drowning_1.mp3", "speech_drowning_2.mp3"])
	_load_group("speech_shelter", ["speech_shelter_1.mp3", "speech_shelter_2.mp3", "speech_shelter_3.mp3", "speech_shelter_4.mp3"])
	_load_group("speech_first_light", ["speech_first_light_1.mp3", "speech_first_light_2.mp3", "speech_first_light_3.mp3", "speech_first_light_4.mp3", "speech_first_light_5.mp3", "speech_first_light_6.mp3"])
	_load_group("speech_killing_spree", ["speech_killing_spree_1.mp3", "speech_killing_spree_2.mp3", "speech_killing_spree_3.mp3", "speech_killing_spree_4.mp3", "speech_killing_spree_5.mp3", "speech_killing_spree_6.mp3"])
	_load_group("speech_village", ["speech_village_1.mp3", "speech_village_2.mp3", "speech_village_3.mp3", "speech_village_4.mp3", "speech_village_5.mp3", "speech_village_6.mp3"])
	_load_group("speech_close_call", ["speech_close_call_1.mp3", "speech_close_call_2.mp3", "speech_close_call_3.mp3", "speech_close_call_4.mp3", "speech_close_call_5.mp3"])
	_load_group("speech_craft_weapon", ["speech_craft_weapon_1.mp3", "speech_craft_weapon_2.mp3", "speech_craft_weapon_3.mp3", "speech_craft_weapon_4.mp3", "speech_craft_weapon_5.mp3", "speech_craft_weapon_6.mp3"])
	_load_group("speech_craft_tool", ["speech_craft_tool_1.mp3", "speech_craft_tool_2.mp3", "speech_craft_tool_3.mp3", "speech_craft_tool_4.mp3", "speech_craft_tool_5.mp3"])
	_load_group("speech_loot_drop", ["speech_loot_drop_1.mp3", "speech_loot_drop_2.mp3", "speech_loot_drop_3.mp3", "speech_loot_drop_4.mp3", "speech_loot_drop_5.mp3", "speech_loot_drop_6.mp3", "speech_loot_drop_7.mp3", "speech_loot_drop_8.mp3", "speech_loot_drop_9.mp3", "speech_loot_drop_10.mp3", "speech_loot_drop_11.mp3", "speech_loot_drop_12.mp3"])
	_load_group("speech_halvard", ["speech_halvard_1.mp3", "speech_halvard_2.mp3", "speech_halvard_3.mp3"])
	_load_group("dialogue_quest", [
		"dialogue_quest_1.mp3", "dialogue_quest_2.mp3", "dialogue_quest_3.mp3", "dialogue_quest_4.mp3",
		"dialogue_quest_5.mp3", "dialogue_quest_6.mp3", "dialogue_quest_7.mp3", "dialogue_quest_8.mp3",
		"dialogue_quest_9.mp3", "dialogue_quest_10.mp3", "dialogue_quest_11.mp3", "dialogue_quest_12.mp3",
		"dialogue_quest_13.mp3", "dialogue_quest_14.mp3", "dialogue_quest_15.mp3", "dialogue_quest_16.mp3",
	])
	_load_group("dialogue_turnin", [
		"dialogue_turnin_1.mp3", "dialogue_turnin_2.mp3", "dialogue_turnin_3.mp3",
		"dialogue_turnin_4.mp3", "dialogue_turnin_5.mp3",
	])
	_load_group("halvard_greet", [
		"halvard_greet_1.mp3", "halvard_greet_2.mp3", "halvard_greet_3.mp3",
	])
	_load_group("halvard_farewell", [
		"halvard_farewell_1.mp3", "halvard_farewell_2.mp3", "halvard_farewell_3.mp3",
		"halvard_farewell_4.mp3", "halvard_farewell_5.mp3", "halvard_farewell_6.mp3",
		"halvard_farewell_7.mp3",
	])


func _load_group(group_name: String, filenames: Array) -> void:
	var streams: Array[AudioStream] = []
	for fname: String in filenames:
		var path := SFX_PATH + fname
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
