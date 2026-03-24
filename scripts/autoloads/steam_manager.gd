extends Node
## SteamManager autoload — initializes the Steamworks SDK, pumps callbacks,
## and handles Steam friend-list join requests / command-line lobby invites.
##
## Must be loaded BEFORE NetworkManager in the autoload order so that
## Steam is ready when NetworkManager checks `SteamManager.is_steam_ready`.

const _DEBUG_LOG := false

signal join_lobby_requested(lobby_id: int)

var is_steam_ready := false
var steam_id: int = 0
var steam_name: String = ""


func _ready() -> void:
	if not ClassDB.class_exists(&"Steam"):
		push_warning("[STEAM] GodotSteam not available — Steam features disabled")
		return

	var init: Dictionary = Steam.steamInit()
	if _DEBUG_LOG:
		print("[STEAM] steamInit result: %s" % str(init))

	if init.get("status", -1) != 1:
		push_warning("[STEAM] Steam init failed: %s" % init.get("verbal", "unknown"))
		return

	is_steam_ready = true
	steam_id = Steam.getSteamID()
	steam_name = Steam.getPersonaName()

	Steam.join_requested.connect(_on_join_requested)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)

	if _DEBUG_LOG:
		print("[STEAM] Initialized — id=%d name=%s" % [steam_id, steam_name])

	_check_command_line()


func _process(_delta: float) -> void:
	if is_steam_ready:
		Steam.run_callbacks()


func _on_join_requested(this_lobby_id: int, friend_id: int) -> void:
	var friend_name: String = Steam.getFriendPersonaName(friend_id) if is_steam_ready else str(friend_id)
	if _DEBUG_LOG:
		print("[STEAM] Join requested — lobby=%d from=%s" % [this_lobby_id, friend_name])
	join_lobby_requested.emit(this_lobby_id)


func _on_lobby_chat_update(_this_lobby_id: int, change_id: int, _making_change_id: int, chat_state: int) -> void:
	if not is_steam_ready:
		return
	var changer_name: String = Steam.getFriendPersonaName(change_id)
	match chat_state:
		Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
			if _DEBUG_LOG: print("[STEAM] %s joined the lobby" % changer_name)
		Steam.CHAT_MEMBER_STATE_CHANGE_LEFT:
			if _DEBUG_LOG: print("[STEAM] %s left the lobby" % changer_name)
		Steam.CHAT_MEMBER_STATE_CHANGE_KICKED:
			if _DEBUG_LOG: print("[STEAM] %s was kicked" % changer_name)
		Steam.CHAT_MEMBER_STATE_CHANGE_BANNED:
			if _DEBUG_LOG: print("[STEAM] %s was banned" % changer_name)


func _check_command_line() -> void:
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "+connect_lobby" and i + 1 < args.size():
			var lobby_arg := args[i + 1]
			if lobby_arg.is_valid_int():
				var cmd_lobby_id := int(lobby_arg)
				if cmd_lobby_id > 0:
					if _DEBUG_LOG:
						print("[STEAM] Command-line lobby join: %d" % cmd_lobby_id)
					call_deferred("_deferred_cmd_join", cmd_lobby_id)
				return


func _deferred_cmd_join(lobby_id: int) -> void:
	await get_tree().create_timer(1.0).timeout
	join_lobby_requested.emit(lobby_id)
