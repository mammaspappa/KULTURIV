class_name BaseUIScreen
extends Control
## Common base class for all top-level UI screens (city, tech tree, civics, diplomacy, …).
##
## Provides a standard show / hide / refresh lifecycle so callers can swap screens without
## knowing each one's individual conventions.
##
## Concrete screens override the `_on_*` hooks instead of re-implementing show/hide.
##
## Migration is opportunistic: existing screens can be migrated one at a time by changing
## `extends Control` to `extends BaseUIScreen` and moving any visibility / refresh logic
## from ad-hoc methods into the appropriate hook. Until a screen is migrated, it can still
## coexist with screens that already inherit from BaseUIScreen.

signal screen_shown(screen: BaseUIScreen)
signal screen_hidden(screen: BaseUIScreen)

## Set to true if the screen should pause game input while visible.
@export var pauses_game: bool = false

func _ready() -> void:
	# Default to hidden so screens don't accidentally appear on game start.
	# Override in subclasses if a screen should be visible immediately.
	visible = false

## Public entry point: show the screen and refresh its contents.
## Subclasses should NOT override this — override `_on_show()` instead.
func show_screen() -> void:
	visible = true
	refresh()
	_on_show()
	screen_shown.emit(self)

## Public entry point: hide the screen.
func hide_screen() -> void:
	_on_hide()
	visible = false
	screen_hidden.emit(self)

## Toggle visibility, refreshing on show.
func toggle_screen() -> void:
	if visible:
		hide_screen()
	else:
		show_screen()

## Re-render the screen from current game state. Subclasses should override this to refresh
## labels, buttons, lists, etc. Default is a no-op so screens that don't need refresh logic
## still work.
func refresh() -> void:
	pass

# ---- Lifecycle hooks for subclasses ----

## Called after the screen becomes visible. Override for animations, focus grabs, etc.
func _on_show() -> void:
	pass

## Called just before the screen becomes hidden. Override to release focus, stop tweens, etc.
func _on_hide() -> void:
	pass
