extends Node

## Autoload. Creates the ENet peer from user command-line arguments.
## Local play leaves the peer unset so Milestone 1 stays single-process.

const MODE_LOCAL := NetConfig.MODE_LOCAL
const MODE_SERVER := NetConfig.MODE_SERVER
const MODE_CLIENT := NetConfig.MODE_CLIENT

var mode := MODE_LOCAL
var address := NetConfig.DEFAULT_ADDRESS
var port := NetConfig.DEFAULT_PORT
var window_x := -1
var window_y := -1
var bot := false
var expect_peers := 2
var status_file := ""
var status_text := "local"
var last_error := ""

var _attempt := 0
var _attempt_open := false
var _ever_connected := false
var _attempt_timer: Timer
var _retry_timer: Timer


func _ready() -> void:
	var parsed := NetConfig.parse(OS.get_cmdline_user_args())
	if bool(parsed.help):
		print(NetConfig.usage())
		get_tree().quit(0)
		return
	if str(parsed.error) != "":
		last_error = str(parsed.error)
		status_text = last_error
		printerr(last_error)
		print(NetConfig.usage())
		get_tree().quit(1)
		return
	mode = int(parsed.mode)
	address = str(parsed.address)
	port = int(parsed.port)
	window_x = int(parsed.window_x)
	window_y = int(parsed.window_y)
	bot = bool(parsed.bot)
	expect_peers = int(parsed.expect_peers)
	status_file = str(parsed.status_file)
	if mode == MODE_LOCAL:
		status_text = "local"
		return
	_configure_window()
	if mode == MODE_SERVER:
		_start_server()
	else:
		_start_client()


func _start_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, NetConfig.MAX_CLIENTS)
	if err != OK:
		last_error = "create_server port=%d error=%s" % [port, error_string(err)]
		status_text = last_error
		var line := "SERVER_FAILED %s" % last_error
		printerr(line)
		NetConfig.append_line(status_file, line)
		get_tree().quit(1)
		return
	multiplayer.multiplayer_peer = peer
	status_text = "listening %d" % port
	print("[server] listening port=%d max_clients=%d" % [port, NetConfig.MAX_CLIENTS])


func _start_client() -> void:
	status_text = "connecting"
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_attempt_timer = Timer.new()
	_attempt_timer.one_shot = true
	_attempt_timer.wait_time = 3.0
	_attempt_timer.timeout.connect(_on_attempt_timeout)
	add_child(_attempt_timer)
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.wait_time = 0.5
	_retry_timer.timeout.connect(_begin_attempt)
	add_child(_retry_timer)
	_begin_attempt()


func _begin_attempt() -> void:
	if _ever_connected:
		return
	_attempt += 1
	if _attempt > 8:
		_give_up()
		return
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		last_error = "connection to %s:%d failed (create_client %s)" % [address, port, error_string(err)]
		status_text = last_error
		print("[client] ", last_error)
		NetConfig.append_line(status_file, "[client] " + last_error)
		_retry_or_give_up()
		return
	_attempt_open = true
	multiplayer.multiplayer_peer = peer
	status_text = "connecting %s:%d attempt %d" % [address, port, _attempt]
	print("[client] connecting to %s:%d attempt %d" % [address, port, _attempt])
	_attempt_timer.start()


func _on_connected() -> void:
	_ever_connected = true
	_attempt_open = false
	if _attempt_timer != null:
		_attempt_timer.stop()
	if _retry_timer != null:
		_retry_timer.stop()
	var peer_id := multiplayer.get_unique_id()
	status_text = "connected peer %d" % peer_id
	last_error = ""
	print("[client] connected peer=%d" % peer_id)
	NetConfig.append_line(status_file, "[client] connected peer=%d" % peer_id)
	_set_title("Survival Sandbox — peer %d" % peer_id)


func _on_connection_failed() -> void:
	_fail_attempt("connection_failed")


func _on_attempt_timeout() -> void:
	if _ever_connected or not _attempt_open:
		return
	var peer := multiplayer.multiplayer_peer
	if peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_fail_attempt("timeout")


func _on_server_disconnected() -> void:
	status_text = "server disconnected"
	last_error = status_text
	print("[client] server disconnected")
	NetConfig.append_line(status_file, "[client] server disconnected")


func _fail_attempt(reason: String) -> void:
	if not _attempt_open:
		return
	_attempt_open = false
	if _attempt_timer != null:
		_attempt_timer.stop()
	last_error = "connection to %s:%d failed (%s)" % [address, port, reason]
	status_text = last_error
	print("[client] ", last_error)
	NetConfig.append_line(status_file, "[client] " + last_error)
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	_retry_or_give_up()


func _retry_or_give_up() -> void:
	if _attempt >= 8:
		_give_up()
		return
	if _retry_timer != null:
		_retry_timer.start()


func _give_up() -> void:
	var line := "CLIENT_FAILED %s" % last_error
	print(line)
	NetConfig.append_line(status_file, line)
	if bot:
		NetConfig.append_line(status_file, "BOT_FAIL %s" % last_error)
		get_tree().quit(1)


func _configure_window() -> void:
	if _headless():
		return
	if window_x >= 0 and window_y >= 0:
		DisplayServer.window_set_position(Vector2i(window_x, window_y))
	elif window_x >= 0:
		DisplayServer.window_set_position(Vector2i(window_x, 40))
	if mode == MODE_CLIENT:
		_set_title("Survival Sandbox — client")


func _set_title(title: String) -> void:
	if _headless():
		return
	DisplayServer.window_set_title(title)


func _headless() -> bool:
	return DisplayServer.get_name() == "headless"
