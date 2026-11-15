## MainMenu.gd — Title screen.
##
## The whole scene (Earth limb, launch pad, astronaut, lunar horizon, moon,
## header, title, HUD panel, mission pipeline, version badges) is carried by a
## single background plate so the screen reads exactly like the approved
## concept art.  Only the five menu buttons are live controls; they are
## positioned with fractional anchors measured off the plate, so they sit on
## top of their painted counterparts at any window size and stay invisible
## until hovered.
##
## If the plate is missing (not imported yet, or stripped from a build) the
## buttons fall back to self-drawn styling so the menu never becomes unusable.

extends Control

# ─── Palette ──────────────────────────────────────────────────────────────────
const C_NAVY   := Color(0.015, 0.03, 0.08)
const C_CYAN   := Color(0.15, 0.85, 1.0)
const C_ORANGE := Color(1.0, 0.62, 0.14)
const C_RED    := Color(1.0, 0.45, 0.45)
const C_TEXT   := Color(0.92, 0.96, 1.0)
const C_DIM    := Color(0.55, 0.66, 0.8)

const BG_URL := "res://assets/images/menu_background.png"
const HOWTO_SCRIPT := "res://scripts/ui/HowToPlayOverlay.gd"

# Hit areas as fractions of the plate (left, top, right, bottom), measured from
# the border lines of the painted buttons in menu_background.png (1672x941).
const BTN_START    := [0.3680, 0.3430, 0.6490, 0.4145]
const BTN_LOAD     := [0.3774, 0.4240, 0.6423, 0.4857]
const BTN_HOWTO    := [0.3774, 0.4995, 0.6423, 0.5611]
const BTN_SETTINGS := [0.3774, 0.5749, 0.6423, 0.6366]
const BTN_QUIT     := [0.3774, 0.6504, 0.6423, 0.7120]

var _bg_ok := false
var _start_btn: Button
var _load_btn: Button
var _howto_btn: Button
var _settings_btn: Button
var _quit_btn: Button
var _howto: Control
var _settings: Control

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_buttons()
	_build_howto_overlay()
	_build_settings_overlay()
	_wire()
	# Fade the whole screen in.
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.7)

# ─── Background plate ─────────────────────────────────────────────────────────
func _build_background() -> void:
	# Letterbox safety: the plate is 16:9, so any other aspect shows navy bars
	# rather than a stretched photograph.
	var base := ColorRect.new()
	base.color = C_NAVY
	_full(base)
	add_child(base)

	var tex: Texture2D = load(BG_URL) if ResourceLoader.exists(BG_URL) else null
	_bg_ok = tex != null
	if not _bg_ok:
		return

	var plate := TextureRect.new()
	plate.texture = tex
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(plate)
	add_child(plate)

# ─── Buttons ─────────────────────────────────────────────────────────────────
func _build_buttons() -> void:
	_start_btn    = _menu_button("START NEW MISSION",    BTN_START,    C_ORANGE)
	_load_btn     = _menu_button("LOAD SAVED MISSION",   BTN_LOAD,     C_CYAN)
	_howto_btn    = _menu_button("HOW TO PLAY",          BTN_HOWTO,    C_CYAN)
	_settings_btn = _menu_button("SETTINGS",             BTN_SETTINGS, C_CYAN)
	_quit_btn     = _menu_button("QUIT",                 BTN_QUIT,     C_RED)
	add_child(_start_btn)
	add_child(_load_btn)
	add_child(_howto_btn)
	add_child(_settings_btn)
	add_child(_quit_btn)

func _menu_button(label: String, rect: Array, accent: Color) -> Button:
	var b := Button.new()
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# NOTE: no clip_contents here - it would cut off the hover glow shadow that
	# is drawn outside the button rect.
	# Fractional anchors keep the hit area glued to the painted button.
	b.anchor_left = rect[0]
	b.anchor_top = rect[1]
	b.anchor_right = rect[2]
	b.anchor_bottom = rect[3]
	b.offset_left = 0.0
	b.offset_top = 0.0
	b.offset_right = 0.0
	b.offset_bottom = 0.0
	b.grow_horizontal = Control.GROW_DIRECTION_BOTH
	b.grow_vertical = Control.GROW_DIRECTION_BOTH

	if _bg_ok:
		# The plate already draws icon + label + frame, so the live button is a
		# transparent hit area that only lights up on interaction.
		b.text = ""
		b.add_theme_stylebox_override("normal", _ghost_style(accent, false))
		b.add_theme_stylebox_override("hover", _ghost_style(accent, true))
		b.add_theme_stylebox_override("pressed", _ghost_style(accent, true, 0.22))
		b.add_theme_stylebox_override("focus", _ghost_style(accent, true))
		b.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	else:
		# Fallback: no plate, so the buttons must carry their own look.
		b.text = label
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", C_TEXT)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_stylebox_override("normal", _solid_style(accent))
		b.add_theme_stylebox_override("hover", _solid_style(accent.lightened(0.25)))
		b.add_theme_stylebox_override("pressed", _solid_style(accent.lightened(0.35)))
		b.add_theme_stylebox_override("focus", _solid_style(accent))
		b.add_theme_stylebox_override("disabled", _solid_style(Color(0.25, 0.3, 0.35)))
	return b

func _ghost_style(accent: Color, hot: bool, strength: float = -1.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	var a := strength if strength >= 0.0 else (0.12 if hot else 0.0)
	s.bg_color = Color(accent.r, accent.g, accent.b, a)
	s.border_color = Color(accent.r, accent.g, accent.b, 0.9 if hot else 0.0)
	s.set_border_width_all(2)
	s.corner_radius_top_left = 6; s.corner_radius_bottom_left = 6
	s.corner_radius_top_right = 16; s.corner_radius_bottom_right = 16
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.55 if hot else 0.0)
	s.shadow_size = 18 if hot else 0
	s.shadow_offset = Vector2(0, 0)
	return s

func _solid_style(accent: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.08, 0.15, 0.9)
	s.border_color = accent
	s.set_border_width_all(2)
	s.border_width_left = 5
	s.corner_radius_top_left = 3; s.corner_radius_bottom_left = 3
	s.corner_radius_top_right = 14; s.corner_radius_bottom_right = 14
	s.content_margin_left = 20; s.content_margin_right = 20
	s.shadow_color = Color(accent.r, accent.g, accent.b, 0.25)
	s.shadow_size = 6
	s.shadow_offset = Vector2(0, 2)
	return s

# ─── How-to overlay ───────────────────────────────────────────────────────────
func _build_howto_overlay() -> void:
	# Full modal with its own tab rail and pages; see HowToPlayOverlay.gd.
	_howto = load(HOWTO_SCRIPT).new()
	_howto.name = "HowToPlayOverlay"
	add_child(_howto)

# ─── Settings overlay ─────────────────────────────────────────────────────────
func _build_settings_overlay() -> void:
	_settings = _overlay()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_settings.add_child(v)

	var title := _label("SETTINGS", 30, C_CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var fs := CheckBox.new()
	fs.text = "Fullscreen"
	fs.button_pressed = (get_window().mode == Window.MODE_FULLSCREEN)
	fs.add_theme_color_override("font_color", C_TEXT)
	fs.toggled.connect(func(on):
		get_window().mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED)
	v.add_child(fs)

	v.add_child(_label("Master Volume", 16, C_DIM))
	var vol := HSlider.new()
	vol.min_value = 0; vol.max_value = 1.0; vol.step = 0.01
	vol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lin := pow(10.0, AudioServer.get_bus_volume_db(0) / 20.0)
	vol.value = clampf(lin, 0.0, 1.0)
	vol.value_changed.connect(func(val):
		AudioServer.set_bus_volume_db(0, linear_to_db(val))
		AudioServer.set_bus_mute(0, val <= 0.001))
	v.add_child(vol)

	v.add_child(_overlay_close(_settings))

func _overlay() -> Control:
	var dim := Control.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	_full(bg)
	dim.add_child(bg)
	dim.hide()
	add_child(dim)
	return dim

func _overlay_close(target: Control) -> Button:
	var b := Button.new()
	b.text = "Close"
	b.custom_minimum_size = Vector2(150, 44)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("normal", _solid_style(C_CYAN))
	b.add_theme_stylebox_override("hover", _solid_style(C_CYAN.lightened(0.25)))
	b.pressed.connect(func(): target.hide())
	return b

# Esc dismisses whichever modal is currently up, matching the X and Close
# buttons without stealing the key from the Settings overlay.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _howto.visible:
		_howto.close()
		get_viewport().set_input_as_handled()
	elif _settings.visible:
		_settings.hide()
		get_viewport().set_input_as_handled()

# ─── Wiring ───────────────────────────────────────────────────────────────────
func _wire() -> void:
	_load_btn.disabled = not FileAccess.file_exists("user://savegame.json")
	_start_btn.pressed.connect(func(): GameManager.go_to_scene("res://scenes/ui/mission_select.tscn"))
	_load_btn.pressed.connect(func():
		if GameManager.load_game(): GameManager.go_to_builder())
	_howto_btn.pressed.connect(func(): _howto.open())
	_settings_btn.pressed.connect(func(): _settings.show())
	_quit_btn.pressed.connect(func(): get_tree().quit())

# ─── Small helpers ────────────────────────────────────────────────────────────
func _full(c: Control) -> void:
	# Use the anchors *and* offsets preset - set_anchors_preset alone preserves
	# the current (still zero) rect as offsets, which pins the child to 0x0.
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
