@tool
extends Node

## WebSocket CLIENT half of the bridge (SPEC §2).
##
## The bridge (Node) LISTENS on 6505..6509; the editor addon DIALS OUT to every port in
## that range, redialing every 3s. One editor can therefore serve several concurrent
## Claude sessions, and a bridge may restart freely without the addon caring.

signal port_connected(port: int)
signal port_disconnected(port: int)
signal command_completed(method: String, success: bool, port: int)

const BASE_PORT := 6505
const MAX_PORT := 6509
const RECONNECT_INTERVAL := 3.0
const PING_INTERVAL := 5.0
const INACTIVITY_TIMEOUT := 30.0
const BUFFER_SIZE := 16 * 1024 * 1024

## Stall guard: blocking handlers (OS.execute exports, long editor scripts) freeze _process,
## so the next frame's delta spikes. Clamp the delta fed to the inactivity/ping timers,
## otherwise one slow command force-closes a healthy socket and drops its own reply.
const MAX_DELTA := 1.0

var command_router: Node

var _running: bool = false
var _peers: Dictionary = {}  # port:int -> WebSocketPeer
var _connected: Dictionary = {}  # port:int -> bool
var _reconnect_timers: Dictionary = {}  # port:int -> float
var _last_activity: Dictionary = {}  # port:int -> float (seconds since last received frame)
var _ping_timers: Dictionary = {}  # port:int -> float (seconds since last ping sent)


func _ready() -> void:
	# NOT `set_process(false)`: when the plugin add_child()s us from _enter_tree the parent is
	# not in the tree yet, so _ready() lands AFTER start() — hard-disabling here would kill
	# _process for good. Mirror _running instead, whichever order the two calls arrive in.
	set_process(_running)


func start() -> void:
	if _running:
		return
	_running = true
	for port: int in range(BASE_PORT, MAX_PORT + 1):
		_peers[port] = null
		_connected[port] = false
		_reconnect_timers[port] = RECONNECT_INTERVAL  # dial immediately on the first frame
		_last_activity[port] = 0.0
		_ping_timers[port] = 0.0
	set_process(true)
	print("[MCP] WebSocket client started — dialing ports %d..%d" % [BASE_PORT, MAX_PORT])


func stop() -> void:
	if not _running:
		return
	_running = false
	set_process(false)
	for port: int in _peers.keys():
		var peer: WebSocketPeer = _peers[port]
		if peer != null:
			peer.close()
		_peers[port] = null
		_connected[port] = false


func get_connected_ports() -> Array[int]:
	var out: Array[int] = []
	for port: int in _connected.keys():
		if bool(_connected[port]):
			out.append(port)
	out.sort()
	return out


func is_connected_to_bridge() -> bool:
	return not get_connected_ports().is_empty()


func _exit_tree() -> void:
	stop()


func _process(delta: float) -> void:
	if not _running:
		return
	var d: float = minf(delta, MAX_DELTA)  # stall guard (1)
	for port: int in range(BASE_PORT, MAX_PORT + 1):
		_process_port(port, d)


func _process_port(port: int, d: float) -> void:
	var peer: WebSocketPeer = _peers.get(port)

	if peer == null:
		_reconnect_timers[port] = float(_reconnect_timers[port]) + d
		if float(_reconnect_timers[port]) >= RECONNECT_INTERVAL:
			_reconnect_timers[port] = 0.0
			_dial(port)
		return

	peer.poll()
	var state: int = peer.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not bool(_connected[port]):
				_connected[port] = true
				_last_activity[port] = 0.0
				_ping_timers[port] = 0.0
				print("[MCP] connected on port %d" % port)
				port_connected.emit(port)

			_last_activity[port] = float(_last_activity[port]) + d
			_ping_timers[port] = float(_ping_timers[port]) + d

			while peer.get_available_packet_count() > 0:
				var packet: PackedByteArray = peer.get_packet()
				_last_activity[port] = 0.0
				_dispatch(packet.get_string_from_utf8(), port)

			if float(_last_activity[port]) > INACTIVITY_TIMEOUT:
				push_warning(
					"[MCP] no traffic on port %d for %.0fs — reconnecting" % [port, INACTIVITY_TIMEOUT]
				)
				peer.close(4000, "inactivity")
				_drop_peer(port)
				return

			if float(_ping_timers[port]) >= PING_INTERVAL:
				_ping_timers[port] = 0.0
				_send(port, {"jsonrpc": "2.0", "method": "ping", "params": {}})

		WebSocketPeer.STATE_CLOSED:
			_drop_peer(port)

		_:
			# CONNECTING / CLOSING — keep polling.
			pass


func _dial(port: int) -> void:
	var peer := WebSocketPeer.new()
	peer.inbound_buffer_size = BUFFER_SIZE
	peer.outbound_buffer_size = BUFFER_SIZE
	peer.max_queued_packets = 4096
	var err: int = peer.connect_to_url("ws://127.0.0.1:%d" % port)
	if err != OK:
		_peers[port] = null
		return
	_peers[port] = peer
	_last_activity[port] = 0.0
	_ping_timers[port] = 0.0


func _drop_peer(port: int) -> void:
	var was_connected: bool = bool(_connected.get(port, false))
	_peers[port] = null
	_connected[port] = false
	_reconnect_timers[port] = 0.0
	_last_activity[port] = 0.0
	_ping_timers[port] = 0.0
	if was_connected:
		print("[MCP] disconnected from port %d" % port)
		port_disconnected.emit(port)


func _send(port: int, message: Dictionary) -> void:
	var peer: WebSocketPeer = _peers.get(port)
	if peer == null or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	peer.send_text(JSON.stringify(message))


func _send_error(port: int, id: Variant, code: int, message: String, data: Dictionary = {}) -> void:
	var err: Dictionary = {"code": code, "message": message}
	if not data.is_empty():
		err["data"] = data
	_send(port, {"jsonrpc": "2.0", "id": id, "error": err})


func _dispatch(text: String, source_port: int) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_send_error(source_port, null, -32700, "Parse error")
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		_send_error(source_port, null, -32600, "Invalid request: expected a JSON object")
		return

	var msg: Dictionary = parsed
	var method: String = str(msg.get("method", ""))

	if method == "ping":
		_send(source_port, {"jsonrpc": "2.0", "method": "pong", "params": {}})
		return
	if method == "pong":
		return

	var id: Variant = msg.get("id", null)
	if typeof(id) != TYPE_INT and typeof(id) != TYPE_FLOAT:
		# Notifications other than ping/pong are ignored silently (SPEC §2).
		return
	var request_id: int = int(id)

	if method.is_empty():
		_send_error(source_port, request_id, -32600, "Invalid request: missing method")
		return
	if command_router == null:
		_send_error(source_port, request_id, -32603, "Internal error: command router unavailable")
		return

	var params: Variant = msg.get("params", {})
	var params_dict: Dictionary = params if typeof(params) == TYPE_DICTIONARY else {}

	# Deferred so the handler runs on the main thread, outside the socket poll.
	_execute.call_deferred(source_port, request_id, method, params_dict)


func _execute(port: int, id: int, method: String, params: Dictionary) -> void:
	var out: Dictionary = {}
	out = await command_router.execute(method, params)

	var ok: bool = not out.has("error")
	if ok:
		_send(port, {"jsonrpc": "2.0", "id": id, "result": out.get("result", {})})
	else:
		_send(port, {"jsonrpc": "2.0", "id": id, "error": out["error"]})

	# Stall guard (2): a successful send proves the link is alive. A handler may have
	# blocked the main loop for minutes; do not let that stale time close the socket.
	if _last_activity.has(port):
		_last_activity[port] = 0.0
		_ping_timers[port] = 0.0

	command_completed.emit(method, ok, port)
