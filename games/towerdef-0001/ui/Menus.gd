extends RefCounted
## Modal overlays for Main.gd: Options (music/SFX sliders + mute), Pause
## (Resume / Options / Abandon run) and Credits. Pattern adapted from Maaack's
## Godot-Game-Template (MIT) — options_menu, pause_menu, credits — rebuilt for
## Corehold's portrait UI with no autoloads/scenes. View only: every action
## calls Main's API (set_audio / toggle_mute / abandon_run / set_overlay),
## which persists via BaseMeta save["settings"] or replays engine events.
## `m` is the Main node (untyped: a preload of Main here would be cyclic).

const CreditsDB := preload("res://data/CreditsDB.gd")
const Art := preload("res://ArtDB.gd")

const TEXT: Color = Color("e9edf2")
const DIM: Color = Color("9aa6b2")
const RUST: Color = Color("d9773a")
const GOLD: Color = Color("f2c94c")
const GEM: Color = Color("5ad1f0")
const ENEMY: Color = Color("e8434f")
const PANEL2: Color = Color("2b333d")
const W: float = 720.0
const H: float = 1280.0
const PANEL_RECT: Rect2 = Rect2(40, 200, 640, 820)
const SLIDER_X: float = 80.0
const SLIDER_W: float = 560.0
const MUSIC_Y: float = 380.0
const SFX_Y: float = 540.0


static func build(m) -> void:
	match String(m.overlay):
		"options":
			_build_options(m)
		"pause":
			_build_pause(m)
		"credits":
			_build_credits(m)


static func draw(m) -> void:
	m.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.72))
	m._panel(PANEL_RECT, RUST, PANEL2)
	match String(m.overlay):
		"options":
			var st: Dictionary = m.save["settings"]
			m._text("OPTIONS", Vector2(360, 278), 38, TEXT)
			m._text("Music  %d%%" % int(round(float(st["music"]) * 100.0)), Vector2(SLIDER_X, MUSIC_Y - 16), 24, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
			m._text("Sound effects  %d%%" % int(round(float(st["sfx"]) * 100.0)), Vector2(SLIDER_X, SFX_Y - 16), 24, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
		"pause":
			m._text("PAUSED", Vector2(360, 300), 44, TEXT)
			if m.S != null:
				m._text("Wave %d  ·  %s coins this run" % [m.S.wave, m.fmt_num(int(m.S.coins_run))], Vector2(360, 350), 22, DIM)
			m._text("Abandoning banks this run's coins", Vector2(360, 900), 20, DIM)
		"credits":
			m._text("CREDITS", Vector2(360, 278), 38, TEXT)


static func _slider(m, y: float, key: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.position = Vector2(SLIDER_X, y)
	s.size = Vector2(SLIDER_W, 88)
	s.focus_mode = Control.FOCUS_NONE
	s.set_meta("key", "SLIDER " + key)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("161a1f")
	track.border_color = Color("4a525c")
	track.set_border_width_all(2)
	track.set_corner_radius_all(8)
	track.content_margin_top = 8.0
	track.content_margin_bottom = 8.0
	var fill := StyleBoxFlat.new()
	fill.bg_color = RUST.darkened(0.2)
	fill.set_corner_radius_all(8)
	fill.content_margin_top = 8.0
	fill.content_margin_bottom = 8.0
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob: Texture2D = Art.tex("slider_knob")
	if knob != null:
		s.add_theme_icon_override("grabber", knob)
		s.add_theme_icon_override("grabber_highlight", knob)
	s.value = float((m.save["settings"] as Dictionary)[key])
	s.value_changed.connect(func(v: float) -> void: m.set_audio(key, v))
	m.ui.add_child(s)
	return s


static func _build_options(m) -> void:
	_slider(m, MUSIC_Y, "music")
	_slider(m, SFX_Y, "sfx")
	var muted: bool = bool((m.save["settings"] as Dictionary)["mute"])
	var mb: Button = m._btn("Sound: OFF (tap to unmute)" if muted else "Sound: ON (tap to mute)", Rect2(80, 664, 560, 96), m.toggle_mute_ui, true, ENEMY if muted else GEM)
	mb.set_meta("key", "MUTE")
	m._btn("Credits", Rect2(80, 780, 560, 96), func() -> void: m.set_overlay("credits"), true, DIM)
	m._btn("Back", Rect2(80, 896, 560, 96), func() -> void: m.set_overlay("pause" if m.screen == "run" else ""), true, RUST)


static func _build_pause(m) -> void:
	m._btn("Resume", Rect2(80, 420, 560, 110), func() -> void: m.set_overlay(""), true, GEM).add_theme_font_size_override("font_size", 32)
	m._btn("Options", Rect2(80, 560, 560, 96), func() -> void: m.set_overlay("options"), true, DIM)
	m._btn("Abandon run", Rect2(80, 760, 560, 96), m.abandon_run, true, ENEMY)


static func _build_credits(m) -> void:
	var sc := ScrollContainer.new()
	sc.position = Vector2(64, 310)
	sc.size = Vector2(592, 560)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.set_meta("key", "CREDITS_SCROLL")
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(570, 0)
	box.add_theme_constant_override("separation", 6)
	for ln in CreditsDB.LINES:
		var la: Array = ln
		var lb := Label.new()
		lb.text = String(la[0])
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.custom_minimum_size = Vector2(570, 0)
		var head: bool = String(la[1]) == "h"
		lb.add_theme_font_size_override("font_size", 24 if head else 19)
		lb.add_theme_color_override("font_color", GOLD if head else TEXT)
		box.add_child(lb)
	sc.add_child(box)
	m.ui.add_child(sc)
	m._btn("Back", Rect2(80, 896, 560, 96), func() -> void: m.set_overlay("options"), true, RUST)
