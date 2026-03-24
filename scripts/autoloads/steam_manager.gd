extends Node
## SteamManager autoload — initializes the Steamworks SDK, pumps callbacks,
## and handles Steam friend-list join requests / command-line lobby invites.
##
## All access to the Steam singleton goes through the `_s` variable so the
## script parses cleanly in standard Godot (where the Steam class doesn't exist).
## Must be loaded BEFORE NetworkManager in the autoload order.

const _DEBUG_LOG := false

signal join_lobby_requested(lobby_id: int)

var is_steam_ready := false
var steam_id: int = 0
var steam_name: String = ""

## The Steam singleton, accessed dynamically so this script loads in any editor.
var _s: Object = null


func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		push_warning("[STEAM] GodotSteam not available — Steam features disabled")
		return

	_s = Engine.get_singleton("Steam")
	var init = _s.steamInit()
	if _DEBUG_LOG:
		print("[STEAM] steamInit result: %s" % str(init))

	if init is Dictionary:
		if init.get("status", -1) != 1:
			push_warning("[STEAM] Steam init failed: %s" % init.get("verbal", "unknown"))
			_s = null
			return
	elif init is bool:
		if not init:
			push_warning("[STEAM] Steam init failed (returned false)")
			_s = null
			return

	is_steam_ready = true
	steam_id = _s.getSteamID()
	steam_name = _s.getPersonaName()

	_s.join_requested.connect(_on_join_requested)
	_s.lobby_chat_update.connect(_on_lobby_chat_update)

	if _DEBUG_LOG:
		print("[STEAM] Initialized — id=%d name=%s" % [steam_id, steam_name])

	_check_command_line()


func _process(_delta: float) -> void:
	if is_steam_ready and _s:
		_s.run_callbacks()


func get_steam() -> Object:
	return _s


func open_invite_dialog() -> void:
	if not _s or not is_steam_ready:
		return
	var lobby_id := NetworkManager.steam_lobby_id
	if lobby_id > 0:
		_s.activateGameOverlayInviteDialog(lobby_id)


func _on_join_requested(this_lobby_id: int, friend_id: int) -> void:
	var friend_name: String = _s.getFriendPersonaName(friend_id) if _s else str(friend_id)
	if _DEBUG_LOG:
		print("[STEAM] Join requested — lobby=%d from=%s" % [this_lobby_id, friend_name])
	join_lobby_requested.emit(this_lobby_id)


func _on_lobby_chat_update(_this_lobby_id: int, change_id: int, _making_change_id: int, chat_state: int) -> void:
	if not _s:
		return
	var changer_name: String = _s.getFriendPersonaName(change_id)
	if chat_state == 0x0001:
		if _DEBUG_LOG: print("[STEAM] %s joined the lobby" % changer_name)
	elif chat_state == 0x0002:
		if _DEBUG_LOG: print("[STEAM] %s left the lobby" % changer_name)
	elif chat_state == 0x0008:
		if _DEBUG_LOG: print("[STEAM] %s was kicked" % changer_name)
	elif chat_state == 0x0010:
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
