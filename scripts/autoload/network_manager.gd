extends Node
## Manages multiplayer networking for Pitboss-style simultaneous turns.
## Supports both WebSocket (firewall-friendly, default) and ENet (low-latency LAN).
## Server is authoritative — clients send actions, server validates and executes.

const MpAction = preload("res://scripts/multiplayer/mp_action.gd")
const StateSync = preload("res://scripts/multiplayer/state_sync.gd")

# --- Network state ---
var is_server: bool = false
var is_multiplayer: bool = false
var is_connected: bool = false

# Transport: "websocket" (default, firewall-friendly) or "enet" (low-latency LAN)
var transport: String = "websocket"
var server_port: int = 7878

# Peer tracking
var peer_to_player: Dictionary = {}   # peer_id -> player_id
var player_to_peer: Dictionary = {}   # player_id -> peer_id
var peer_info: Dictionary = {}        # peer_id -> {name, civ, leader, ready}

# Turn timer
var turn_timer: float = 0.0
var turn_time_limit: float = 300.0    # seconds, 0 = unlimited
var turn_timer_active: bool = false

# Turn tracking (server-side)
var players_ended_turn: Array[int] = []  # player_ids who ended their turn
var max_players: int = 8
var game_started: bool = false

# Server game settings (set before hosting)
var server_settings: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Check for headless server CLI args
	_check_cli_args()

func _process(delta: float) -> void:
	if not is_server or not turn_timer_active or turn_time_limit <= 0:
		return

	turn_timer += delta
	if turn_timer >= turn_time_limit:
		_force_end_all_turns()

	# Broadcast timer update every second
	if int(turn_timer) != int(turn_timer - delta):
		var remaining = max(0, turn_time_limit - turn_timer)
		_broadcast_timer_update.rpc(remaining)

# =============================================================================
# HOST / JOIN
# =============================================================================

func host_game(port: int, settings: Dictionary, use_transport: String = "websocket") -> Error:
	server_port = port
	transport = use_transport
	server_settings = settings
	max_players = settings.get("num_players", 4)

	var peer: MultiplayerPeer
	if transport == "enet":
		var enet_peer = ENetMultiplayerPeer.new()
		var err = enet_peer.create_server(port, max_players)
		if err != OK:
			push_error("NetworkManager: Failed to create ENet server on port %d: %s" % [port, error_string(err)])
			return err
		peer = enet_peer
	else:
		var ws_peer = WebSocketMultiplayerPeer.new()
		var err = ws_peer.create_server(port)
		if err != OK:
			push_error("NetworkManager: Failed to create WebSocket server on port %d: %s" % [port, error_string(err)])
			return err
		peer = ws_peer

	multiplayer.multiplayer_peer = peer
	is_server = true
	is_multiplayer = true
	is_connected = true

	print("NetworkManager: Server started on port %d (%s)" % [port, transport])
	EventBus.notification_added.emit("Server started on port %d (%s)" % [port, transport], "")
	return OK

func join_game(address: String, port: int, use_transport: String = "websocket") -> Error:
	transport = use_transport
	server_port = port

	var peer: MultiplayerPeer
	if transport == "enet":
		var enet_peer = ENetMultiplayerPeer.new()
		var err = enet_peer.create_client(address, port)
		if err != OK:
			push_error("NetworkManager: Failed to connect to %s:%d via ENet: %s" % [address, port, error_string(err)])
			return err
		peer = enet_peer
	else:
		var ws_peer = WebSocketMultiplayerPeer.new()
		var url = "ws://%s:%d" % [address, port]
		var err = ws_peer.create_client(url)
		if err != OK:
			push_error("NetworkManager: Failed to connect to %s via WebSocket: %s" % [url, error_string(err)])
			return err
		peer = ws_peer

	multiplayer.multiplayer_peer = peer
	is_multiplayer = true

	print("NetworkManager: Connecting to %s:%d (%s)..." % [address, port, transport])
	return OK

## Client: register with the server after picking a civilization
func register_with_server(player_info_dict: Dictionary) -> void:
	_register_player.rpc_id(1, player_info_dict)

func disconnect_from_game() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_server = false
	is_multiplayer = false
	is_connected = false
	game_started = false
	peer_to_player.clear()
	player_to_peer.clear()
	peer_info.clear()
	players_ended_turn.clear()
	turn_timer_active = false
	turn_timer = 0.0

# =============================================================================
# CONNECTION CALLBACKS
# =============================================================================

func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: Peer %d connected" % peer_id)
	if is_server:
		# Collect civs already taken by connected players
		var taken_civs: Array[String] = []
		for pid in peer_info:
			var civ_id = peer_info[pid].get("civ", "")
			if civ_id != "":
				taken_civs.append(civ_id)

		# Server: send current game info to new peer
		_send_server_info.rpc_id(peer_id, {
			"max_players": max_players,
			"settings": server_settings,
			"connected_players": peer_info,
			"game_started": game_started,
			"taken_civs": taken_civs,
		})
	EventBus.mp_player_connected.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkManager: Peer %d disconnected" % peer_id)
	if is_server:
		var player_id = peer_to_player.get(peer_id, -1)
		peer_to_player.erase(peer_id)
		if player_id >= 0:
			player_to_peer.erase(player_id)
		peer_info.erase(peer_id)

		# If player had ended turn, keep it; otherwise auto-end if game in progress
		if game_started and player_id >= 0 and player_id not in players_ended_turn:
			players_ended_turn.append(player_id)
			_check_all_turns_ended()

		# Notify all remaining peers
		_broadcast_player_list.rpc(_collect_player_list())

	EventBus.mp_player_disconnected.emit(peer_id)

func _on_connected_to_server() -> void:
	print("NetworkManager: Connected to server")
	is_connected = true
	EventBus.mp_connected_to_server.emit()

func _on_connection_failed() -> void:
	print("NetworkManager: Connection failed")
	is_connected = false
	is_multiplayer = false
	EventBus.mp_connection_failed.emit()

func _on_server_disconnected() -> void:
	print("NetworkManager: Server disconnected")
	is_connected = false
	EventBus.mp_server_disconnected.emit()

# =============================================================================
# RPCs: REGISTRATION & LOBBY
# =============================================================================

@rpc("authority", "reliable")
func _send_server_info(info: Dictionary) -> void:
	# Client receives server info upon connection
	server_settings = info.get("settings", {})
	max_players = info.get("max_players", 4)
	EventBus.mp_server_info_received.emit(info)

@rpc("any_peer", "reliable")
func _register_player(info: Dictionary) -> void:
	if not is_server:
		return
	var peer_id = multiplayer.get_remote_sender_id()

	if game_started:
		# Allow reconnection: find if this player was previously assigned
		var reconnect_player_id = -1
		for pid in player_to_peer:
			if player_to_peer[pid] == -1:  # Disconnected slot
				reconnect_player_id = pid
				break
		if reconnect_player_id >= 0:
			peer_to_player[peer_id] = reconnect_player_id
			player_to_peer[reconnect_player_id] = peer_id
			peer_info[peer_id] = info
			# Send full state sync for reconnection
			_send_reconnect_state(peer_id, reconnect_player_id)
			return
		else:
			_registration_rejected.rpc_id(peer_id, "Game already in progress")
			return

	if peer_info.size() >= max_players:
		_registration_rejected.rpc_id(peer_id, "Server full")
		return

	# Check if the chosen civ is already taken
	var chosen_civ = info.get("civ", "")
	if chosen_civ != "":
		for pid in peer_info:
			if peer_info[pid].get("civ", "") == chosen_civ:
				_registration_rejected.rpc_id(peer_id, "Civilization already taken")
				return

	peer_info[peer_id] = info
	print("NetworkManager: Player registered: peer=%d name=%s civ=%s" % [peer_id, info.get("name", "?"), info.get("civ", "?")])

	# Broadcast updated player list
	_broadcast_player_list.rpc(_collect_player_list())

@rpc("authority", "reliable")
func _registration_rejected(reason: String) -> void:
	push_warning("NetworkManager: Registration rejected: %s" % reason)
	EventBus.mp_registration_rejected.emit(reason)

@rpc("authority", "reliable", "call_local")
func _broadcast_player_list(player_list: Array) -> void:
	EventBus.mp_player_list_updated.emit(player_list)

func _collect_player_list() -> Array:
	var result = []
	for pid in peer_info:
		var info = peer_info[pid].duplicate()
		info["peer_id"] = pid
		info["player_id"] = peer_to_player.get(pid, -1)
		result.append(info)
	return result

# =============================================================================
# RPCs: GAME START
# =============================================================================

## Server: start the multiplayer game (called by host)
func server_start_game() -> void:
	if not is_server:
		return

	# Assign player IDs to peers
	var player_id = 0
	for pid in peer_info:
		peer_to_player[pid] = player_id
		player_to_peer[player_id] = pid
		player_id += 1

	game_started = true

	# Configure GameManager for multiplayer
	var settings = server_settings.duplicate()
	settings["multiplayer"] = true
	settings["human_player_ids"] = peer_to_player.values()
	settings["peer_to_player"] = peer_to_player.duplicate()
	settings["player_to_peer"] = player_to_peer.duplicate()
	settings["peer_info"] = peer_info.duplicate()

	# Notify all clients to start
	_start_game_on_clients.rpc(settings, peer_to_player)

@rpc("authority", "reliable", "call_local")
func _start_game_on_clients(settings: Dictionary, peer_player_map: Dictionary) -> void:
	peer_to_player = peer_player_map
	# Invert map
	player_to_peer.clear()
	for pid in peer_to_player:
		player_to_peer[peer_to_player[pid]] = pid

	game_started = true
	EventBus.mp_game_starting.emit(settings)

# =============================================================================
# RPCs: ACTIONS (client → server → all clients)
# =============================================================================

## Client sends an action to the server for validation and execution
@rpc("any_peer", "reliable")
func request_action(action_data: Dictionary) -> void:
	if not is_server:
		return

	var peer_id = multiplayer.get_remote_sender_id()
	var player_id = peer_to_player.get(peer_id, -1)
	if player_id < 0:
		return

	var player = GameManager.get_player(player_id)
	if player == null:
		return

	# Don't allow actions after player ended turn
	if player_id in players_ended_turn:
		_action_rejected.rpc_id(peer_id, action_data, "Turn already ended")
		return

	# Validate action
	if not MpAction.is_valid(action_data, player):
		_action_rejected.rpc_id(peer_id, action_data, "Invalid action")
		return

	# Execute on server
	var result = MpAction.execute(action_data, player)

	# Broadcast result to clients who can see it
	_broadcast_action_result(action_data, result, player)

func _broadcast_action_result(action_data: Dictionary, result: Dictionary, acting_player) -> void:
	# Always send to the acting player
	var acting_peer = player_to_peer.get(acting_player.player_id, -1)
	if acting_peer > 0:
		_receive_action_result.rpc_id(acting_peer, action_data, result)

	# Send to other players who can see the affected tiles
	var affected_positions: Array = result.get("affected_positions", [])
	for peer_id in peer_to_player:
		if peer_id == acting_peer:
			continue
		var other_player_id = peer_to_player[peer_id]
		var other_player = GameManager.get_player(other_player_id)
		if other_player == null:
			continue

		# Check if any affected position is visible to this player
		var can_see = false
		for pos_dict in affected_positions:
			var pos = Vector2i(pos_dict.get("x", 0), pos_dict.get("y", 0))
			if VisibilitySystem.is_tile_visible_to_player(pos, other_player):
				can_see = true
				break

		if can_see:
			# Filter result to only include visible information
			var filtered = StateSync.filter_result_for_player(result, other_player)
			_receive_action_result.rpc_id(peer_id, action_data, filtered)

@rpc("authority", "reliable")
func _receive_action_result(action_data: Dictionary, result: Dictionary) -> void:
	# Client applies the result from the server
	StateSync.apply_action_result(action_data, result)

@rpc("authority", "reliable")
func _action_rejected(action_data: Dictionary, reason: String) -> void:
	EventBus.mp_action_rejected.emit(action_data, reason)

# =============================================================================
# RPCs: END TURN
# =============================================================================

@rpc("any_peer", "reliable")
func request_end_turn() -> void:
	if not is_server:
		return

	var peer_id = multiplayer.get_remote_sender_id()
	var player_id = peer_to_player.get(peer_id, -1)
	if player_id < 0:
		return

	if player_id not in players_ended_turn:
		players_ended_turn.append(player_id)
		print("NetworkManager: Player %d ended turn (%d/%d)" % [player_id, players_ended_turn.size(), peer_to_player.size()])

		# Broadcast who has ended turn
		_broadcast_turn_status.rpc(players_ended_turn.duplicate())

		_check_all_turns_ended()

@rpc("authority", "reliable")
func _broadcast_turn_status(ended_players: Array) -> void:
	EventBus.mp_turn_status_updated.emit(ended_players)

@rpc("authority", "reliable")
func _broadcast_timer_update(remaining: float) -> void:
	EventBus.mp_turn_timer_updated.emit(remaining)

func _check_all_turns_ended() -> void:
	# Check if all human players have ended their turn
	var all_ended = true
	for player_id in player_to_peer:
		if player_id not in players_ended_turn:
			all_ended = false
			break

	if all_ended:
		_process_between_turns()

func _force_end_all_turns() -> void:
	# Timer expired — force end for all players who haven't
	for player_id in player_to_peer:
		if player_id not in players_ended_turn:
			players_ended_turn.append(player_id)
	_broadcast_turn_status.rpc(players_ended_turn.duplicate())
	_process_between_turns()

func _process_between_turns() -> void:
	turn_timer_active = false
	turn_timer = 0.0

	# Server processes between-turn logic
	TurnManager.process_between_turns_mp()

	# Reset for next turn
	players_ended_turn.clear()

	# Collect per-player state and send turn start
	for peer_id in peer_to_player:
		var player_id = peer_to_player[peer_id]
		var player = GameManager.get_player(player_id)
		if player == null:
			continue
		var state = StateSync.collect_turn_state_for_player(player)
		_receive_turn_start.rpc_id(peer_id, TurnManager.current_turn, state)

	turn_timer_active = true

@rpc("authority", "reliable")
func _receive_turn_start(turn: int, state: Dictionary) -> void:
	# Client: apply new turn state from server
	StateSync.apply_turn_state(state)
	EventBus.mp_turn_started.emit(turn)

# =============================================================================
# RECONNECTION
# =============================================================================

func _send_reconnect_state(peer_id: int, player_id: int) -> void:
	var player = GameManager.get_player(player_id)
	if player == null:
		return
	var state = StateSync.collect_turn_state_for_player(player)
	_receive_reconnect_state.rpc_id(peer_id, player_id, TurnManager.current_turn, state)

@rpc("authority", "reliable")
func _receive_reconnect_state(player_id: int, turn: int, state: Dictionary) -> void:
	StateSync.apply_turn_state(state)
	EventBus.mp_reconnected.emit(player_id, turn)

# =============================================================================
# CLI ARGS (Pitboss headless mode)
# =============================================================================

func _check_cli_args() -> void:
	var args = OS.get_cmdline_user_args()
	var is_headless_server = false
	var cli_port = 7878
	var cli_players = 4
	var cli_timer = 300.0
	var cli_map_width = 80
	var cli_map_height = 50
	var cli_transport = "websocket"

	var i = 0
	while i < args.size():
		match args[i]:
			"--server":
				is_headless_server = true
			"--port":
				if i + 1 < args.size():
					cli_port = int(args[i + 1])
					i += 1
			"--players":
				if i + 1 < args.size():
					cli_players = int(args[i + 1])
					i += 1
			"--turn-timer":
				if i + 1 < args.size():
					cli_timer = float(args[i + 1])
					i += 1
			"--map-size":
				if i + 1 < args.size():
					var parts = args[i + 1].split("x")
					if parts.size() == 2:
						cli_map_width = int(parts[0])
						cli_map_height = int(parts[1])
					i += 1
			"--transport":
				if i + 1 < args.size():
					cli_transport = args[i + 1]
					i += 1
		i += 1

	if is_headless_server:
		print("NetworkManager: Starting Pitboss headless server...")
		turn_time_limit = cli_timer
		var settings = {
			"map_width": cli_map_width,
			"map_height": cli_map_height,
			"num_players": cli_players,
			"difficulty": 4,
			"game_speed": 1,
		}
		# Defer to allow other autoloads to initialize
		call_deferred("_start_headless_server", cli_port, settings, cli_transport)

func _start_headless_server(port: int, settings: Dictionary, use_transport: String) -> void:
	var err = host_game(port, settings, use_transport)
	if err != OK:
		push_error("NetworkManager: Failed to start headless server")
		get_tree().quit(1)
		return
	print("NetworkManager: Pitboss server ready. Waiting for %d players on port %d (%s)..." % [
		settings.get("num_players", 4), port, use_transport])
	print("NetworkManager: Turn timer: %s" % (
		"%ds" % int(turn_time_limit) if turn_time_limit > 0 else "unlimited"))

# =============================================================================
# UTILITY
# =============================================================================

func get_local_player_id() -> int:
	if not is_multiplayer:
		return 0
	var my_peer = multiplayer.get_unique_id()
	return peer_to_player.get(my_peer, -1)

func is_local_player(player_id: int) -> bool:
	if not is_multiplayer:
		return player_id == 0
	return get_local_player_id() == player_id

func get_connected_player_count() -> int:
	return peer_info.size()
