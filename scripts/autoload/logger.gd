extends Node
## Structured logging for KulturIV.
##
## Levels (low → high): TRACE, DEBUG, INFO, WARN, ERROR.
## Each entry is tagged with a category (e.g. "combat", "save", "data") so categories can be
## filtered independently. The most recent N entries are kept in a ring buffer for an in-game
## debug console (planned). For now, entries above the configured per-category level are also
## printed via Godot's print/push_warning/push_error.
##
## Usage:
##     Logger.info("combat", "resolved %s vs %s" % [a, b])
##     Logger.warn("save", "version mismatch %d -> %d" % [from, to])
##
## Per-category levels can be set via data/tunables/logging.json:
##     { "default_level": "INFO", "categories": { "combat": "DEBUG" } }

enum Level { TRACE, DEBUG, INFO, WARN, ERROR }

const _LEVEL_NAMES := {
	Level.TRACE: "TRACE",
	Level.DEBUG: "DEBUG",
	Level.INFO: "INFO",
	Level.WARN: "WARN",
	Level.ERROR: "ERROR",
}

const _NAME_TO_LEVEL := {
	"TRACE": Level.TRACE,
	"DEBUG": Level.DEBUG,
	"INFO": Level.INFO,
	"WARN": Level.WARN,
	"ERROR": Level.ERROR,
}

const RING_CAPACITY := 1000

var _default_level: int = Level.INFO
var _category_levels: Dictionary = {}
var _ring: Array = []  # entries: {time, level, category, message}
var _ring_head: int = 0
var _ring_size: int = 0

signal entry_logged(entry: Dictionary)

func _ready() -> void:
	# Load per-category levels lazily — DataManager isn't guaranteed loaded yet.
	# We re-attempt on the first log call if needed.
	call_deferred("_load_config_from_tunables")

func _load_config_from_tunables() -> void:
	if not is_instance_valid(DataManager):
		return
	var conf = DataManager.get_tunable("logging", null)
	if not (conf is Dictionary):
		return
	var default_name = String(conf.get("default_level", "INFO"))
	if _NAME_TO_LEVEL.has(default_name):
		_default_level = _NAME_TO_LEVEL[default_name]
	var cats = conf.get("categories", {})
	if cats is Dictionary:
		for cat in cats.keys():
			var lvl_name = String(cats[cat])
			if _NAME_TO_LEVEL.has(lvl_name):
				_category_levels[String(cat)] = _NAME_TO_LEVEL[lvl_name]

## Set the level for a category at runtime (overrides tunables config).
func set_category_level(category: String, level: int) -> void:
	_category_levels[category] = level

## Set the default level for categories without an explicit override.
func set_default_level(level: int) -> void:
	_default_level = level

func trace(category: String, message: String) -> void: _log(Level.TRACE, category, message)
func debug(category: String, message: String) -> void: _log(Level.DEBUG, category, message)
func info(category: String, message: String) -> void: _log(Level.INFO, category, message)
func warn(category: String, message: String) -> void: _log(Level.WARN, category, message)
func error(category: String, message: String) -> void: _log(Level.ERROR, category, message)

## Return the most recent N entries in chronological order.
func tail(count: int = 100) -> Array:
	if _ring_size == 0:
		return []
	var n = min(count, _ring_size)
	var result: Array = []
	var start = (_ring_head - n + RING_CAPACITY) % RING_CAPACITY
	for i in range(n):
		var idx = (start + i) % RING_CAPACITY
		result.append(_ring[idx])
	return result

# ---- internals ----

func _log(level: int, category: String, message: String) -> void:
	var threshold: int = _category_levels.get(category, _default_level)
	if level < threshold:
		return

	var entry := {
		"time": Time.get_ticks_msec(),
		"level": level,
		"level_name": _LEVEL_NAMES[level],
		"category": category,
		"message": message,
	}
	_push_ring(entry)
	entry_logged.emit(entry)

	# Mirror to Godot's console so existing tooling still sees it.
	var formatted := "[%s][%s] %s" % [_LEVEL_NAMES[level], category, message]
	match level:
		Level.ERROR:
			push_error(formatted)
		Level.WARN:
			push_warning(formatted)
		_:
			print(formatted)

func _push_ring(entry: Dictionary) -> void:
	if _ring.size() < RING_CAPACITY:
		_ring.append(entry)
	else:
		_ring[_ring_head] = entry
	_ring_head = (_ring_head + 1) % RING_CAPACITY
	_ring_size = min(_ring_size + 1, RING_CAPACITY)
