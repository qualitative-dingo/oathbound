extends Node
## ChatManager — simple text chat for LAN multiplayer.
## Sends messages via RPC; displays in chat log. Add as autoload for global access.

signal message_received(sender: String, text: String)

const MAX_MESSAGES := 20
const MESSAGE_FADE_TIME := 5.0

var _messages: Array[Dictionary] = []  # {sender, text, timestamp}


func _ready() -> void:
	pass


func _get_my_display_name() -> String:
	return str(SaveManager.current_character.get("name", "Player"))


func send_message(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	if not multiplayer.multiplayer_peer:
		_receive_message(_get_my_display_name(), trimmed)
		return
	if multiplayer.is_server():
		_receive_message(_get_my_display_name(), trimmed)
		_broadcast_message.rpc(_get_my_display_name(), trimmed)
	else:
		_send_chat_message.rpc_id(1, _get_my_display_name(), trimmed)


@rpc("any_peer", "reliable")
func _send_chat_message(sender_name: String, text: String) -> void:
	if multiplayer.is_server():
		_receive_message(sender_name, text)
		_broadcast_message.rpc(sender_name, text)


@rpc("authority", "reliable")
func _broadcast_message(sender_name: String, text: String) -> void:
	_receive_message(sender_name, text)


func _receive_message(sender_name: String, text: String) -> void:
	_messages.append({
		"sender": sender_name,
		"text": text,
		"timestamp": Time.get_ticks_msec() / 1000.0
	})
	while _messages.size() > MAX_MESSAGES:
		_messages.pop_front()
	message_received.emit(sender_name, text)


func get_messages() -> Array[Dictionary]:
	return _messages.duplicate()


func get_message_fade_time() -> float:
	return MESSAGE_FADE_TIME
