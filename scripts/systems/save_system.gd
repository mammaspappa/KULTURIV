extends Node
## Handles saving and loading game state to files.

const GameStateClass = preload("res://scripts/core/game_state.gd")
const PlayerClass = preload("res://scripts/core/player.gd")
const UnitClass = preload("res://scripts/entities/unit.gd")
const CityClass = preload("res://scripts/entities/city.gd")

const SAVE_DIR = "user://saves/"
const AUTOSAVE_FILE = "autosave.json"
const QUICKSAVE_FILE = "quicksave.json"
const SAVE_VERSION = "1.0"

func _ready() -> void:
	# Ensure save directory exists
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	# Connect to turn events for autosave
	EventBus.all_turns_completed.connect(_on_turn_completed)

## Save the current game to a file
func save_game(filename: String = "") -> bool:
	if filename == "":
		filename = "save_%d.json" % Time.get_unix_time_from_system()

	var save_data = _collect_save_data()
	var json_string = JSON.stringify(save_data, "\t")

	var full_path = SAVE_DIR + filename
	var file = FileAccess.open(full_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: Failed to save game: " + str(FileAccess.get_open_error()))
		return false

	file.store_string(json_string)
	file.close()

	EventBus.game_saved.emit()
	print("SaveSystem: Game saved to " + full_path)
	return true

## Load a game from a file
func load_game(filename: String) -> bool:
	var full_path = SAVE_DIR + filename
	var file = FileAccess.open(full_path, FileAccess.READ)
	if file == null:
		push_error("SaveSystem: Failed to load game: " + str(FileAccess.get_open_error()))
		return false

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("SaveSystem: Failed to parse save file: " + json.get_error_message())
		return false

	var success = _restore_save_data(json.data)
	if success:
		EventBus.game_loaded.emit()
		print("SaveSystem: Game loaded from " + full_path)
	return success

## Quick save
func quicksave() -> bool:
	return save_game(QUICKSAVE_FILE)

## Quick load
func quickload() -> bool:
	return load_game(QUICKSAVE_FILE)

## Auto save (called every turn)
func autosave() -> void:
	save_game(AUTOSAVE_FILE)

## Get list of available save files
func get_save_files() -> Array:
	var files = []
	var dir = DirAccess.open(SAVE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".json"):
				var info = {
					"filename": file_name,
					"path": SAVE_DIR + file_name,
					"modified": FileAccess.get_modified_time(SAVE_DIR + file_name)
				}
				files.append(info)
			file_name = dir.get_next()
		dir.list_dir_end()

	# Sort by modification time, newest first
	files.sort_custom(func(a, b): return a.modified > b.modified)
	return files

## Delete a save file
func delete_save(filename: String) -> bool:
	var full_path = SAVE_DIR + filename
	var dir = DirAccess.open(SAVE_DIR)
	if dir:
		var err = dir.remove(filename)
		return err == OK
	return false

## Collect all game data for saving
func _collect_save_data() -> Dictionary:
	var data = {
		"version": SAVE_VERSION,
		"save_time": Time.get_datetime_string_from_system(),
		"settings": {
			"map_width": GameManager.map_width,
			"map_height": GameManager.map_height,
			"difficulty": GameManager.difficulty,
			"game_speed": GameManager.game_speed
		},
		"turn": TurnManager.current_turn,
		"year": TurnManager.current_year,
		"current_player_index": GameManager.current_player_index,
		"players": [],
		"units": [],
		"cities": [],
	}

	# Save game state
	if GameManager.current_game_state:
		data["game_state"] = GameManager.current_game_state.to_dict()

	# Save map
	if GameManager.hex_grid:
		data["map"] = _collect_map_data()

	# Save players
	for player in GameManager.players:
		data.players.append(player.to_dict())

	# Save units (separately for easier reconstruction)
	for player in GameManager.players:
		for unit in player.units:
			var unit_data = unit.to_dict()
			data.units.append(unit_data)

	# Save cities (separately for easier reconstruction)
	for player in GameManager.players:
		for city in player.cities:
			var city_data = city.to_dict()
			data.cities.append(city_data)

	return data

func _collect_map_data() -> Dictionary:
	var map_data = {
		"width": GameManager.hex_grid.width,
		"height": GameManager.hex_grid.height,
		"tiles": []
	}

	for x in range(GameManager.hex_grid.width):
		for y in range(GameManager.hex_grid.height):
			var tile = GameManager.hex_grid.get_tile(Vector2i(x, y))
			if tile:
				map_data.tiles.append(tile.to_dict())

	return map_data

## Restore game data from save
func _restore_save_data(data: Dictionary) -> bool:
	# Check version
	var version = data.get("version", "")
	if version != SAVE_VERSION:
		push_warning("SaveSystem: Save version mismatch. Expected %s, got %s" % [SAVE_VERSION, version])

	# Restore settings
	var settings = data.get("settings", {})
	GameManager.map_width = settings.get("map_width", 80)
	GameManager.map_height = settings.get("map_height", 50)
	GameManager.difficulty = settings.get("difficulty", 4)
	GameManager.game_speed = settings.get("game_speed", 1)

	# Restore turn info
	TurnManager.current_turn = data.get("turn", 1)
	TurnManager.current_year = data.get("year", -4000)
	GameManager.current_player_index = data.get("current_player_index", 0)

	# Restore game state
	if GameManager.current_game_state == null:
		GameManager.current_game_state = GameStateClass.new()
	if data.has("game_state"):
		GameManager.current_game_state.from_dict(data.game_state)

	# Restore players (without units/cities for now)
	GameManager.players.clear()
	GameManager.human_player = null

	for player_data in data.get("players", []):
		var player = PlayerClass.new()
		player.from_dict(player_data)
		GameManager.players.append(player)
		if player.is_human:
			GameManager.human_player = player

	# Restore map if we have a game world
	if GameManager.game_world and data.has("map"):
		_restore_map_data(data.map)

	# Restore units
	for unit_data in data.get("units", []):
		var owner_id = unit_data.get("owner_id", -1)
		var owner = GameManager.get_player(owner_id)
		if owner:
			var unit = UnitClass.new()
			unit.from_dict(unit_data)
			owner.add_unit(unit)
			if GameManager.game_world:
				var entity_layer = GameManager.game_world.get_node_or_null("EntityLayer")
				if entity_layer:
					entity_layer.add_child(unit)

	# Restore cities
	for city_data in data.get("cities", []):
		var owner_id = city_data.get("owner_id", -1)
		var owner = GameManager.get_player(owner_id)
		if owner:
			var city = CityClass.new()
			city.from_dict(city_data)
			owner.add_city(city)
			if GameManager.game_world:
				var entity_layer = GameManager.game_world.get_node_or_null("EntityLayer")
				if entity_layer:
					entity_layer.add_child(city)

			# Restore tile ownership
			for tile_pos in city.territory:
				var tile = GameManager.hex_grid.get_tile(tile_pos) if GameManager.hex_grid else null
				if tile:
					tile.owner = owner
					tile.city_owner = city
					tile.update_visuals()

	return true

func _restore_map_data(map_data: Dictionary) -> void:
	if GameManager.hex_grid == null:
		return

	for tile_data in map_data.get("tiles", []):
		var pos = Vector2i(tile_data.grid_position.x, tile_data.grid_position.y)
		var tile = GameManager.hex_grid.get_tile(pos)
		if tile:
			tile.from_dict(tile_data)

func _on_turn_completed(turn: int) -> void:
	# Autosave every 5 turns
	if turn % 5 == 0:
		autosave()
