extends RefCounted
## Shared desktop widgets for the native 1920x1080 view (REDESIGN_SPEC §5).
## Static helpers; `m` is the Main node (untyped: Main has no class_name and a
## preload here would be cyclic). Buttons are added to m.ui (one unscaled
## Control layer); draw helpers are only called from inside Main._draw().
## Every button: ACTION_MODE_BUTTON_PRESS, a tooltip, >= 40 px tall, a "key"
## meta for tests, and FOCUS_ALL when a controller is in use.

const Art := preload("res://ArtDB.gd")
const Keybinds := preload("res://Keybinds.gd")

const BG: Color = Color("161a20")
const PANEL: Color = Color("20262e")
const PANEL2: Color = Color("29313b")
const EDGE: Color = Color("3a434e")
const RUST: Color = Color("d9773a")
const ENEMY: Color = Color("e8434f")
const TEXT: Color = Color("e9edf2")
const DIM: Color = Color("9aa6b2")
const GOLD: Color = Color("f2c94c")
const GEM: Color = Color("5ad1f0")
const GREEN: Color = Color("6bd46b")
const MAG: Color = Color("e04bc0")
const LAB: Color = Color("b48cff")
const SCRAP: Color = Color("c0a888")
const KEYC: Color = Color("ffb454")
const CORECORE: Color = Color("ff7b54")
const SHARD: Color = Color("9fe0ff")
const NEUTRAL: Color = Color("4a525c")
const RARITY: Dictionary = {"common": Color("a7b1bc"), "rare": Color("4fa3ff"), "epic": Color("b46cff"), "legendary": Color("ffb43a"), "special": Color("ff5f8a"), "insight": Color("7ff0e0")}
const SLOT_COL: Dictionary = {"F": Color("6bd46b"), "B": Color("e8434f"), "C": Color("5ad1f0"), "E": Color("f2c94c"), "S": Color("ff5f8a")}


static func rarity_col(r: String) -> Color:
	return RARITY.get(r, DIM)


static func sb(col: Color, fill: Color, bw: int = 2, radius: int = 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = col
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s


static func tip_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = sb(RUST, Color(0.07, 0.08, 0.1, 0.97), 2, 6)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


## Standard text button.
static func btn(m, text: String, rect: Rect2, cb: Callable, tip: String, enabled: bool = true, col: Color = RUST, key: String = "", icon: String = "", fsize: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = Vector2(rect.size.x, maxf(40.0, rect.size.y))
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	# Keyboard/mouse: no focus (Space/Enter stay hotkeys). Pad: full focus chain.
	b.focus_mode = Control.FOCUS_ALL if String(m.last_device) == "pad" else Control.FOCUS_NONE
	b.disabled = not enabled
	b.clip_text = true
	b.tooltip_text = tip if tip != "" else text
	b.set_meta("key", key if key != "" else text)
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_stylebox_override("normal", sb(col, col.darkened(0.62)))
	b.add_theme_stylebox_override("hover", sb(col.lightened(0.25), col.darkened(0.42)))
	b.add_theme_stylebox_override("pressed", sb(col.lightened(0.25), col.darkened(0.42)))
	b.add_theme_stylebox_override("focus", sb(Color.WHITE, Color(0, 0, 0, 0), 3))
	b.add_theme_stylebox_override("disabled", sb(Color("3a414a"), Color("1f242b")))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(DIM, 0.7))
	if icon != "":
		var t: Texture2D = Art.tex(icon)
		if t != null:
			b.icon = t
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", int(minf(32.0, b.size.y - 10.0)))
	b.pressed.connect(func() -> void: m.sfx_play("click"))
	b.pressed.connect(cb)
	m.ui.add_child(b)
	return b


## Invisible hit-area button over art drawn in _draw(): hover/focus outline
## only. Visuals stay in the draw pass so cards can be rich.
static func hit(m, rect: Rect2, cb: Callable, tip: String, key: String, enabled: bool = true, col: Color = GOLD) -> Button:
	var b: Button = btn(m, "", rect, cb, tip, enabled, col, key)
	var clear: StyleBoxFlat = sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0)
	b.add_theme_stylebox_override("normal", clear)
	b.add_theme_stylebox_override("disabled", clear)
	b.add_theme_stylebox_override("hover", sb(Color(col, 0.9), Color(1, 1, 1, 0.04), 2))
	b.add_theme_stylebox_override("pressed", sb(Color(col, 0.9), Color(1, 1, 1, 0.08), 2))
	return b


static func t(m, s: String, pos: Vector2, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = 400.0) -> void:
	var p: Vector2 = pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= width
	m.draw_string(m.font, p + Vector2(1, 2), s, align, width, size, Color(0, 0, 0, 0.55 * col.a))
	m.draw_string(m.font, p, s, align, width, size, col)


## Word-wrapped text with its top edge at pos.y; returns the drawn height.
static func wrap(m, s: String, pos: Vector2, size: int, col: Color, width: float, max_lines: int = 6, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> float:
	var p: Vector2 = pos + Vector2(0, m.font.get_ascent(size))
	m.draw_multiline_string(m.font, p + Vector2(1, 2), s, align, width, size, max_lines, Color(0, 0, 0, 0.5 * col.a))
	m.draw_multiline_string(m.font, p, s, align, width, size, max_lines, col)
	return m.font.get_multiline_string_size(s, align, width, size, max_lines).y


static func panel(m, r: Rect2, border: Color = EDGE, fill: Color = PANEL, bw: int = 2) -> void:
	m.draw_style_box(sb(border, fill, bw), r)


static func bar(m, r: Rect2, frac: float, col: Color, back: Color = Color("0e1115")) -> void:
	m.draw_rect(r, back)
	m.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(frac, 0.0, 1.0), r.size.y)), col)
	m.draw_rect(r, Color(1, 1, 1, 0.16), false, 1.0)


## Draws an ArtDB texture; false (nothing drawn) when it is missing.
static func icon(m, id: String, r: Rect2, mod: Color = Color.WHITE) -> bool:
	var tx: Texture2D = Art.tex(id)
	if tx == null:
		return false
	m.draw_texture_rect(tx, r, false, mod)
	return true


## Section header: rust caps + underline.
static func head(m, s: String, pos: Vector2, width: float, col: Color = RUST) -> void:
	t(m, s, pos, 17, col, HORIZONTAL_ALIGNMENT_LEFT, width)
	m.draw_line(pos + Vector2(0, 8), pos + Vector2(width, 8), Color(col, 0.35), 1.0)


## Label / value row; registers a tooltip region when `tip` is given.
static func row(m, label: String, value: String, pos: Vector2, width: float, col: Color = TEXT, tip: String = "", size: int = 17) -> void:
	t(m, label, pos, size, DIM, HORIZONTAL_ALIGNMENT_LEFT, width * 0.62)
	t(m, value, pos + Vector2(width, 0), size, col, HORIZONTAL_ALIGNMENT_RIGHT, width * 0.5)
	if tip != "":
		m.stat_tips.append([Rect2(pos.x, pos.y - size - 2, width, size + 8), tip])


## PartDB.lines() entries read "+ +29% Core HP"; show "+29% Core HP".
static func fx_line(s: String) -> String:
	if s.begins_with("+ ") or s.begins_with("- "):
		var rest: String = s.substr(2)
		if rest.begins_with("+") or rest.begins_with("-"):
			return rest
		return s.substr(0, 1) + rest
	return s


static func fmt(v: float) -> String:
	var a: float = absf(v)
	if a >= 1.0e9:
		return "%.2fB" % (v / 1.0e9)
	if a >= 1.0e6:
		return "%.2fM" % (v / 1.0e6)
	if a >= 1.0e4:
		return "%.1fk" % (v / 1000.0)
	return str(int(round(v)))


static func dur(sec: int) -> String:
	var s: int = maxi(0, sec)
	if s >= 86400:
		return "%dd %02dh" % [s / 86400, (s % 86400) / 3600]
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm %02ds" % [s / 60, s % 60]
	return "%ds" % s


## Currency chip: icon + amount (drawn) + tooltip region.
static func chip(m, icon_id: String, txt: String, pos: Vector2, col: Color, tip: String, w: float = 120.0) -> void:
	icon(m, icon_id, Rect2(pos.x, pos.y - 26, 32, 32))
	t(m, txt, pos + Vector2(38, 0), 20, col, HORIZONTAL_ALIGNMENT_LEFT, w - 38.0)
	m.stat_tips.append([Rect2(pos.x, pos.y - 30, w, 40), tip])


## Thin pulsing focus outline used for armed / selected items.
static func outline(m, r: Rect2, col: Color, wdt: float = 3.0) -> void:
	m.draw_rect(r, col, false, wdt)


## Key / pad glyph text for an action ("" when unbound).
static func hint(m, action: String) -> String:
	var pad: bool = String(m.last_device) == "pad"
	var h: String = Keybinds.hint(action, pad)
	if h == "" and pad:
		h = Keybinds.hint(action, false)
	return h
