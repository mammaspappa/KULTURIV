class_name GameState
extends RefCounted
## Holds the complete game state for save/load functionality.

var turn_number: int = 1
var year: int = -4000
var difficulty: int = 4
var game_speed: int = 1
var map_width: int = 80
var map_height: int = 50

# Victory tracking
var victory_achieved: bool = false
var victory_type: String = ""
var winner_player_id: int = -1

# Religion tracking
var founded_religions: Dictionary = {}  # religion_id -> holy_city_id
var religion_founder: Dictionary = {}   # religion_id -> player_id

# Great people counter (for scaling cost)
var great_people_born: Dictionary = {}  # player_id -> count

func _init() -> void:
	pass

func to_dict() -> Dictionary:
	return {
		"turn_number": turn_number,
		"year": year,
		"difficulty": difficulty,
		"game_speed": game_speed,
		"map_width": map_width,
		"map_height": map_height,
		"victory_achieved": victory_achieved,
		"victory_type": victory_type,
		"winner_player_id": winner_player_id,
		"founded_religions": founded_religions,
		"religion_founder": religion_founder,
		"great_people_born": great_people_born,
	}

func from_dict(data: Dictionary) -> void:
	turn_number = data.get("turn_number", 1)
	year = data.get("year", -4000)
	difficulty = data.get("difficulty", 4)
	game_speed = data.get("game_speed", 1)
	map_width = data.get("map_width", 80)
	map_height = data.get("map_height", 50)
	victory_achieved = data.get("victory_achieved", false)
	victory_type = data.get("victory_type", "")
	winner_player_id = data.get("winner_player_id", -1)
	founded_religions = data.get("founded_religions", {})
	religion_founder = data.get("religion_founder", {})
	great_people_born = data.get("great_people_born", {})
