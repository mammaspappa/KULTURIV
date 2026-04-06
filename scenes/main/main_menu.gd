extends Control
## Civ4 BTS-style main menu with animated background, golden styling, and atmospheric effects.

# Colors
const GOLD = Color(0.85, 0.7, 0.3)
const GOLD_LIGHT = Color(0.9, 0.8, 0.5)
const GOLD_BRIGHT = Color(1.0, 0.9, 0.6)
const GOLD_DIM = Color(0.7, 0.6, 0.35)
const BUTTON_BG = Color(0.12, 0.1, 0.08, 0.8)
const BUTTON_HOVER = Color(0.18, 0.15, 0.1, 0.85)
const BUTTON_BORDER = Color(0.6, 0.5, 0.2)

# Loading screen quotes
const QUOTES = [
	"\"The whole is greater than the sum of its parts.\" - Aristotle",
	"\"I came, I saw, I conquered.\" - Julius Caesar",
	"\"The art of war is of vital importance to the state.\" - Sun Tzu",
	"\"In the middle of difficulty lies opportunity.\" - Albert Einstein",
	"\"Those who cannot remember the past are condemned to repeat it.\" - George Santayana",
	"\"Give me liberty, or give me death!\" - Patrick Henry",
	"\"Knowledge is power.\" - Sir Francis Bacon",
	"\"The only thing we have to fear is fear itself.\" - Franklin D. Roosevelt",
]

# UI references
var background_tex: TextureRect
var fog_layers: Array[ColorRect] = []
var main_menu_container: VBoxContainer
var submenu_container: VBoxContainer
var loading_screen: ColorRect

# Sub-screens
var new_game_screen: Control
var load_game_screen: Control
var options_screen: Control

func _ready() -> void:
	_build_background()
	_build_fog()
	_build_title()
	_build_main_menu()
	_build_submenu()
	_build_version()
	_build_loading_screen()
	_create_screens()
	_start_animations()

# --- BACKGROUND ---
func _build_background() -> void:
	# Dark base
	var base = ColorRect.new()
	base.set_anchors_preset(PRESET_FULL_RECT)
	base.color = Color(0.05, 0.07, 0.1)
	add_child(base)

	# Procedural terrain image
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.015
	noise.fractal_octaves = 4
	noise.seed = randi()

	var moisture_noise = FastNoiseLite.new()
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.frequency = 0.025
	moisture_noise.seed = randi()

	var img_w = 320
	var img_h = 200
	var img = Image.create(img_w, img_h, false, Image.FORMAT_RGB8)

	for y in range(img_h):
		for x in range(img_w):
			var elevation = noise.get_noise_2d(x, y) * 0.5 + 0.5
			var moisture = moisture_noise.get_noise_2d(x, y) * 0.5 + 0.5

			var color: Color
			if elevation < 0.35:
				color = Color(0.08, 0.18, 0.28)  # Deep ocean
			elif elevation < 0.42:
				color = Color(0.15, 0.30, 0.40)  # Coast
			elif elevation > 0.82:
				color = Color(0.3, 0.28, 0.25)  # Mountains
			elif elevation > 0.7:
				color = Color(0.35, 0.3, 0.2)  # Hills
			elif moisture > 0.55:
				color = Color(0.18, 0.32, 0.12)  # Forest/grassland
			elif moisture < 0.3:
				color = Color(0.45, 0.38, 0.22)  # Desert/plains
			else:
				color = Color(0.25, 0.35, 0.15)  # Plains

			# Sepia/warm tone overlay
			color = color.lerp(Color(0.3, 0.22, 0.1), 0.3)
			img.set_pixel(x, y, color)

	var tex = ImageTexture.create_from_image(img)
	background_tex = TextureRect.new()
	background_tex.texture = tex
	background_tex.set_anchors_preset(PRESET_FULL_RECT)
	background_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background_tex.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(background_tex)

	# Dark vignette overlay (darker edges)
	var vignette = ColorRect.new()
	vignette.set_anchors_preset(PRESET_FULL_RECT)
	vignette.color = Color(0, 0, 0, 0.4)
	add_child(vignette)

	# Top gradient (darker at top for title readability)
	var top_grad = ColorRect.new()
	top_grad.set_anchors_preset(PRESET_TOP_WIDE)
	top_grad.custom_minimum_size = Vector2(0, 300)
	top_grad.color = Color(0, 0, 0, 0.5)
	add_child(top_grad)

# --- FOG EFFECT ---
func _build_fog() -> void:
	for i in range(3):
		var fog = ColorRect.new()
		fog.set_anchors_preset(PRESET_FULL_RECT)
		fog.color = Color(0.8, 0.75, 0.6, 0.03 + i * 0.01)
		fog.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(fog)
		fog_layers.append(fog)

func _start_animations() -> void:
	# Animate fog layers drifting
	for i in range(fog_layers.size()):
		var fog = fog_layers[i]
		var speed = 0.3 + i * 0.15
		var tween = create_tween().set_loops()
		tween.tween_property(fog, "position:x", 50.0 + i * 20, 8.0 + i * 3).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(fog, "position:x", -30.0 - i * 15, 10.0 + i * 2).set_ease(Tween.EASE_IN_OUT)

	# Subtle background drift
	if background_tex:
		var bg_tween = create_tween().set_loops()
		bg_tween.tween_property(background_tex, "position:x", -20.0, 30.0).set_ease(Tween.EASE_IN_OUT)
		bg_tween.tween_property(background_tex, "position:x", 20.0, 30.0).set_ease(Tween.EASE_IN_OUT)

# --- TITLE ---
func _build_title() -> void:
	var title_container = VBoxContainer.new()
	title_container.set_anchors_preset(PRESET_CENTER_TOP)
	title_container.offset_top = 120
	title_container.offset_left = -250
	title_container.offset_right = 250
	title_container.add_theme_constant_override("separation", 8)

	# Shadow title
	var shadow = Label.new()
	shadow.text = "KULTUR IV"
	shadow.add_theme_font_size_override("font_size", 64)
	shadow.add_theme_color_override("font_color", Color(0.05, 0.03, 0.0, 0.8))
	shadow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shadow.position = Vector2(3, 3)
	title_container.add_child(shadow)

	# Main title (overlaps shadow)
	var title = Label.new()
	title.text = "KULTUR IV"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 0)
	title_container.add_child(title)

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Beyond the Sword"
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", GOLD_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_container.add_child(subtitle)

	add_child(title_container)

# --- MAIN MENU BUTTONS ---
func _build_main_menu() -> void:
	main_menu_container = VBoxContainer.new()
	main_menu_container.set_anchors_preset(PRESET_CENTER)
	main_menu_container.offset_left = 50
	main_menu_container.offset_right = 300
	main_menu_container.offset_top = 50
	main_menu_container.offset_bottom = 300
	main_menu_container.add_theme_constant_override("separation", 12)

	_add_menu_button(main_menu_container, "Single Player", _on_single_player_pressed)
	_add_menu_button(main_menu_container, "Options", _on_options_pressed)
	_add_menu_button(main_menu_container, "Exit", _on_quit_pressed)

	add_child(main_menu_container)

func _build_submenu() -> void:
	submenu_container = VBoxContainer.new()
	submenu_container.set_anchors_preset(PRESET_CENTER)
	submenu_container.offset_left = 50
	submenu_container.offset_right = 300
	submenu_container.offset_top = 50
	submenu_container.offset_bottom = 300
	submenu_container.add_theme_constant_override("separation", 12)
	submenu_container.visible = false

	_add_menu_button(submenu_container, "New Game", _on_new_game_pressed)
	_add_menu_button(submenu_container, "Load Game", _on_load_game_pressed)
	_add_menu_button(submenu_container, "Back", _on_submenu_back)

	add_child(submenu_container)

func _add_menu_button(container: VBoxContainer, text: String, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(250, 45)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	# Normal style
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = BUTTON_BG
	normal_style.border_color = BUTTON_BORDER
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(4)
	normal_style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", normal_style)

	# Hover style
	var hover_style = normal_style.duplicate()
	hover_style.bg_color = BUTTON_HOVER
	hover_style.border_color = GOLD
	btn.add_theme_stylebox_override("hover", hover_style)

	# Pressed style
	var pressed_style = normal_style.duplicate()
	pressed_style.bg_color = Color(0.08, 0.06, 0.04, 0.9)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	# Text color
	btn.add_theme_color_override("font_color", GOLD_LIGHT)
	btn.add_theme_color_override("font_hover_color", GOLD_BRIGHT)
	btn.add_theme_color_override("font_pressed_color", GOLD)
	btn.add_theme_font_size_override("font_size", 18)

	btn.pressed.connect(callback)
	container.add_child(btn)
	return btn

# --- VERSION ---
func _build_version() -> void:
	var version = Label.new()
	version.text = "v0.1.0"
	version.set_anchors_preset(PRESET_BOTTOM_LEFT)
	version.offset_left = 15
	version.offset_bottom = -10
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", Color(0.5, 0.5, 0.4, 0.6))
	add_child(version)

	var clone_label = Label.new()
	clone_label.text = "A Civilization IV: Beyond the Sword Clone"
	clone_label.set_anchors_preset(PRESET_BOTTOM_RIGHT)
	clone_label.offset_right = -15
	clone_label.offset_bottom = -10
	clone_label.add_theme_font_size_override("font_size", 11)
	clone_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.4, 0.4))
	clone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(clone_label)

# --- LOADING SCREEN ---
func _build_loading_screen() -> void:
	loading_screen = ColorRect.new()
	loading_screen.set_anchors_preset(PRESET_FULL_RECT)
	loading_screen.color = Color(0.03, 0.03, 0.05)
	loading_screen.visible = false
	loading_screen.mouse_filter = MOUSE_FILTER_STOP

	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(PRESET_CENTER)
	vbox.offset_left = -300
	vbox.offset_right = 300
	vbox.offset_top = -100
	vbox.offset_bottom = 100
	vbox.add_theme_constant_override("separation", 20)

	var loading_label = Label.new()
	loading_label.name = "LoadingText"
	loading_label.text = "Loading..."
	loading_label.add_theme_font_size_override("font_size", 32)
	loading_label.add_theme_color_override("font_color", GOLD)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(loading_label)

	var leader_label = Label.new()
	leader_label.name = "LeaderText"
	leader_label.text = ""
	leader_label.add_theme_font_size_override("font_size", 18)
	leader_label.add_theme_color_override("font_color", GOLD_LIGHT)
	leader_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(leader_label)

	var quote_label = Label.new()
	quote_label.name = "QuoteText"
	quote_label.text = QUOTES[randi() % QUOTES.size()]
	quote_label.add_theme_font_size_override("font_size", 14)
	quote_label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.4))
	quote_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(quote_label)

	loading_screen.add_child(vbox)
	add_child(loading_screen)

# --- SUBSCREENS ---
func _create_screens() -> void:
	var NewGameScreenClass = load("res://scripts/ui/new_game_screen.gd")
	if NewGameScreenClass:
		new_game_screen = Control.new()
		new_game_screen.set_script(NewGameScreenClass)
		new_game_screen.name = "NewGameScreen"
		new_game_screen.back_pressed.connect(_on_subscreen_back)
		new_game_screen.start_game.connect(_on_start_game)
		add_child(new_game_screen)

	var LoadGameScreenClass = load("res://scripts/ui/load_game_screen.gd")
	if LoadGameScreenClass:
		load_game_screen = Control.new()
		load_game_screen.set_script(LoadGameScreenClass)
		load_game_screen.name = "LoadGameScreen"
		load_game_screen.back_pressed.connect(_on_subscreen_back)
		add_child(load_game_screen)

	var OptionsScreenClass = load("res://scripts/ui/options_screen.gd")
	if OptionsScreenClass:
		options_screen = Control.new()
		options_screen.set_script(OptionsScreenClass)
		options_screen.name = "OptionsScreen"
		options_screen.back_pressed.connect(_on_subscreen_back)
		add_child(options_screen)

# --- BUTTON HANDLERS ---
func _on_single_player_pressed() -> void:
	main_menu_container.visible = false
	submenu_container.visible = true

func _on_submenu_back() -> void:
	submenu_container.visible = false
	main_menu_container.visible = true

func _on_new_game_pressed() -> void:
	if new_game_screen:
		main_menu_container.visible = false
		submenu_container.visible = false
		new_game_screen.show_screen()

func _on_load_game_pressed() -> void:
	if load_game_screen:
		main_menu_container.visible = false
		submenu_container.visible = false
		load_game_screen.show_screen()

func _on_options_pressed() -> void:
	if options_screen:
		main_menu_container.visible = false
		options_screen.show_screen()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_subscreen_back() -> void:
	main_menu_container.visible = true
	submenu_container.visible = false

func _on_start_game(settings: Dictionary) -> void:
	# Show loading screen
	_show_loading_screen(settings)
	# Defer the scene change to allow loading screen to render
	await get_tree().process_frame
	await get_tree().process_frame
	GameManager.start_new_game(settings)
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")

func _show_loading_screen(settings: Dictionary) -> void:
	loading_screen.visible = true

	# Update leader info
	var leader_text = loading_screen.get_node("VBoxContainer/LeaderText") if loading_screen.has_node("VBoxContainer/LeaderText") else null
	if leader_text == null:
		# Find by name
		for child in loading_screen.get_children():
			if child is VBoxContainer:
				for label in child.get_children():
					if label.name == "LeaderText":
						leader_text = label

	if leader_text:
		var civ_data = DataManager.get_civ(settings.get("human_civ", "rome"))
		var leader_data = DataManager.get_leader(settings.get("human_leader", ""))
		var civ_name = civ_data.get("name", "Unknown")
		var leader_name = leader_data.get("name", settings.get("player_name", "Player"))
		leader_text.text = "You are %s of the %s" % [leader_name, civ_name]

	# Random quote
	var quote_text = null
	for child in loading_screen.get_children():
		if child is VBoxContainer:
			for label in child.get_children():
				if label.name == "QuoteText":
					quote_text = label
	if quote_text:
		quote_text.text = QUOTES[randi() % QUOTES.size()]

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if submenu_container.visible:
			_on_submenu_back()
