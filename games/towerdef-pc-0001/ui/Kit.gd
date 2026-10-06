extends RefCounted
## Shared desktop widgets for the native 1920x1080 view (REDESIGN_SPEC §5),
## V2 neon-casino skin (P2). Static helpers; `m` is the Main node (untyped:
## Main has no class_name and a preload here would be cyclic). Buttons are
## added to m.ui (one unscaled Control layer); draw helpers are only called
## from inside Main._draw().
## Every button: ACTION_MODE_BUTTON_PRESS, a tooltip, >= 40 px tall, a "key"
## meta for tests, and FOCUS_ALL when a controller is in use.
## Text: Inter for body copy, Chakra Petch for headings, buttons and numbers
## (sizes >= 22 switch to it automatically). No drawn text below MIN_TEXT px:
## smaller requests are logged in `small_text` and uitest fails on them.

const Art := preload("res://ArtDB.gd")
const RunArt := preload("res://ui/RunArt.gd")
const Keybinds := preload("res://Keybinds.gd")
const Fonts := preload("res://ui/Fonts.gd")
const Beam := preload("res://vfx/Beam.gd")

# ---- V2 palette. The V1 token names stay so every screen restyles by token.
const BG: Color = Color("070a12")
const BG2: Color = Color("0d1220")
const PANEL: Color = Color(0.0667, 0.0941, 0.1529, 0.92)   # #111827 @ 0.92
const PANEL2: Color = Color("162036")
const CARD: Color = Color("1a2540")
const EDGE: Color = Color("1f2a44")
const EDGE2: Color = Color("2c3a5e")
const CYAN: Color = Color("39e6ff")
const MAGENTA: Color = Color("ff3ea5")
const RUST: Color = CYAN                 # V1 accent name: the V2 primary accent
const ENEMY: Color = Color("ff6680")   # V2 P9 audit: lighter so red text clears 4.5:1 at small sizes
const TEXT: Color = Color("e8f0ff")
const DIM: Color = Color("a9b8d6")     # V2 P9 audit: secondary text (was 8a9bbd, ~3.9:1 when anti-aliased)
const GOLD: Color = Color("ffd34d")
const GEM: Color = Color("5b8cff")
const GREEN: Color = Color("4ade80")
const MAG: Color = MAGENTA
const LAB: Color = Color("a78bfa")
const SCRAP: Color = Color("d9b98a")
const SHARD: Color = Color("9fe0ff")
const NEUTRAL: Color = Color("33446b")   # outline of neutral buttons (never text)
const RARITIES: Array = ["common", "uncommon", "rare", "epic", "legendary", "mythic", "exotic"]
const RARITY: Dictionary = {
	"common": Color("9aa4b2"), "uncommon": Color("4ade80"), "rare": Color("38bdf8"),
	"epic": Color("b26bff"), "legendary": Color("f59e0b"), "mythic": Color("ff3e6c"),
	"exotic": Color("f0f6ff"), "special": Color("ff5f8a"), "insight": Color("7ff0e0"),
}
const SLOT_COL: Dictionary = {"F": Color("4ade80"), "B": Color("ff4d6d"), "C": Color("39e6ff"), "E": Color("ffd34d"), "S": Color("ff5f8a")}
## Text tokens and the surfaces they sit on: WCAG contrast must be >= 4.5
## (uitest P2 audit).
const TEXT_TOKENS: Array = ["TEXT", "DIM", "CYAN", "MAGENTA", "GOLD", "GEM", "GREEN", "ENEMY", "LAB", "SCRAP", "SHARD"]
const SURFACES: Array = ["BG", "BG2", "PANEL2", "CARD"]
const MIN_TEXT: int = 14

## Drawn text requests below MIN_TEXT since the last frame_begin() (audit).
static var small_text: Array = []
static var frames: int = 0
static var _sb_cache: Dictionary = {}
static var _glow_tex: GradientTexture2D


static func token(n: String) -> Color:
	match n:
		"TEXT": return TEXT
		"DIM": return DIM
		"CYAN": return CYAN
		"MAGENTA": return MAGENTA
		"GOLD": return GOLD
		"GEM": return GEM
		"GREEN": return GREEN
		"ENEMY": return ENEMY
		"LAB": return LAB
		"SCRAP": return SCRAP
		"SHARD": return SHARD
		"BG": return BG
		"BG2": return BG2
		"PANEL": return PANEL
		"PANEL2": return PANEL2
		"CARD": return CARD
	return Color.MAGENTA


## WCAG 2.x relative luminance / contrast ratio (alpha ignored).
static func luminance(c: Color) -> float:
	var ch: Array = []
	for v in [c.r, c.g, c.b]:
		var x: float = float(v)
		ch.append(x / 12.92 if x <= 0.03928 else pow((x + 0.055) / 1.055, 2.4))
	return 0.2126 * float(ch[0]) + 0.7152 * float(ch[1]) + 0.0722 * float(ch[2])


static func contrast(a: Color, b: Color) -> float:
	var la: float = luminance(a)
	var lb: float = luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func rarity_col(r: String) -> Color:
	return RARITY.get(r, DIM)


## V2 P9 audit: a rarity colour lifted toward white for TEXT (the full colour
## stays for rims and fills); small Epic / Mythic words read >= 4.5:1.
static func rarity_text(r: String) -> Color:
	return rarity_col(r).lerp(TEXT, 0.3)


## Rarity colour with the Exotic prismatic cycle (t = animation clock).
static func rarity_col_t(r: String, t: float) -> Color:
	if r == "exotic":
		return Color.from_hsv(fposmod(t * 0.18, 1.0), 0.55, 1.0)
	return rarity_col(r)


## 0 (common) .. 6 (exotic); -1 for non-gear rarities.
static func rarity_rank(r: String) -> int:
	return RARITIES.find(r)


## Clears the per-frame audit log (Main._draw calls it first).
static func frame_begin() -> void:
	small_text.clear()
	frames += 1


static func _note_size(s: String, size: int, col: Color) -> void:
	if size < MIN_TEXT and col.a > 0.05 and s != "" and small_text.size() < 32:
		small_text.append("%s@%d" % [s.substr(0, 24), size])


## Neon stylebox: fill, border, rounded corners and an optional coloured glow
## (StyleBoxFlat shadow). Cached by value: draw passes ask for the same few.
static func sb(col: Color, fill: Color, bw: int = 2, radius: int = 8, glow: float = 0.0) -> StyleBoxFlat:
	var key: String = "%s|%s|%d|%d|%.2f" % [col.to_html(), fill.to_html(), bw, radius, glow]
	var c: Variant = _sb_cache.get(key)
	if c != null:
		return c
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = col
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if glow > 0.0:
		s.shadow_color = Color(col, clampf(0.32 * glow, 0.0, 0.8))
		s.shadow_size = int(round(10.0 * glow))
	if _sb_cache.size() > 512:
		_sb_cache.clear()
	_sb_cache[key] = s
	return s


static func tip_style() -> StyleBoxFlat:
	var s: StyleBoxFlat = sb(CYAN, Color(0.035, 0.05, 0.09, 0.97), 1, 8, 1.2).duplicate()
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


## Button fill for an accent colour: a dark tint of it over the background.
static func tint(col: Color, k: float) -> Color:
	return Color(BG2.lerp(col, k), 0.94)


## Standard text button: dark accent tint, accent outline, glow on hover.
## Labels use Chakra Petch.
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
	b.add_theme_font_override("font", Fonts.head())
	b.add_theme_font_size_override("font_size", maxi(MIN_TEXT, fsize))
	b.add_theme_stylebox_override("normal", sb(Color(col, 0.85), tint(col, 0.16), 2, 8, 0.35))
	b.add_theme_stylebox_override("hover", sb(col.lightened(0.2), tint(col, 0.28), 2, 8, 1.0))
	b.add_theme_stylebox_override("pressed", sb(col.lightened(0.35), tint(col, 0.38), 2, 8, 1.4))
	b.add_theme_stylebox_override("focus", sb(Color.WHITE, Color(0, 0, 0, 0), 2, 8, 0.8))
	b.add_theme_stylebox_override("disabled", sb(EDGE2, Color(BG2, 0.9), 1, 8))
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(DIM, 0.75))
	if icon != "":
		var tx: Texture2D = Art.tex(icon)
		if tx != null:
			b.icon = tx
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
	b.add_theme_stylebox_override("hover", sb(Color(col, 0.95), Color(1, 1, 1, 0.04), 2, 8, 1.0))
	b.add_theme_stylebox_override("pressed", sb(Color(col, 0.95), Color(1, 1, 1, 0.08), 2, 8, 1.4))
	return b


## V2 P9 audit: `s` shortened with an ellipsis so it fits `width` px at
## `size` (body font; heading faces run a little wider, so pass a margin).
static func fit(m, s: String, size: int, width: float, f: Font = null) -> String:
	var fo: Font = f if f != null else m.font
	if width <= 0.0 or fo.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
		return s
	var lo: int = 0
	var hi: int = s.length()
	while lo < hi:
		var mid: int = (lo + hi + 1) / 2
		if fo.get_string_size(s.left(mid).strip_edges() + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= width:
			lo = mid
		else:
			hi = mid - 1
	return s.left(lo).strip_edges() + "…"


## V2 P9 audit: text with a 1 px dark outline (numbers on bright bars).
static func t_outline(m, s: String, pos: Vector2, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = 400.0) -> void:
	var f: Font = Fonts.bold() if size >= 22 else m.font
	_note_size(s, size, col)
	var p: Vector2 = pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= width
	m.draw_string_outline(f, p, s, align, width, size, 4, Color(0.02, 0.03, 0.07, 0.95 * col.a))
	m.draw_string(f, p, s, align, width, size, col)


## Text whose baseline sits at pos.y. Sizes >= 22 use Chakra Petch Bold.
static func t(m, s: String, pos: Vector2, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = 400.0) -> void:
	_str(m, Fonts.bold() if size >= 22 else m.font, s, pos, size, col, align, width)


## Heading-face text (Chakra Petch SemiBold) at any size: labels, readouts.
static func th(m, s: String, pos: Vector2, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = 400.0) -> void:
	_str(m, Fonts.head() if size < 22 else Fonts.bold(), s, pos, size, col, align, width)


static func _str(m, f: Font, s: String, pos: Vector2, size: int, col: Color, align: int, width: float) -> void:
	_note_size(s, size, col)
	var p: Vector2 = pos
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= width
	if size >= 26 and col.a > 0.3:
		# neon bloom: two soft offset copies in the text colour
		m.draw_string(f, p + Vector2(0, 1), s, align, width, size, Color(col, 0.22 * col.a))
		m.draw_string(f, p + Vector2(0, -1), s, align, width, size, Color(col, 0.12 * col.a))
	m.draw_string(f, p + Vector2(1, 2), s, align, width, size, Color(0, 0, 0, 0.6 * col.a))
	m.draw_string(f, p, s, align, width, size, col)


## Word-wrapped text with its top edge at pos.y; returns the drawn height.
static func wrap(m, s: String, pos: Vector2, size: int, col: Color, width: float, max_lines: int = 6, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> float:
	_note_size(s, size, col)
	var p: Vector2 = pos + Vector2(0, m.font.get_ascent(size))
	m.draw_multiline_string(m.font, p + Vector2(1, 2), s, align, width, size, max_lines, Color(0, 0, 0, 0.5 * col.a))
	m.draw_multiline_string(m.font, p, s, align, width, size, max_lines, col)
	return m.font.get_multiline_string_size(s, align, width, size, max_lines).y


## Panel: rounded, translucent navy, thin edge. An accent border (anything
## brighter than the edge tokens) also glows.
static func panel(m, r: Rect2, border: Color = EDGE, fill: Color = PANEL, bw: int = 2) -> void:
	var accent: bool = border != EDGE and border != EDGE2 and border.v > 0.45 and border.a > 0.3
	m.draw_style_box(sb(border, fill, mini(bw, 2) if not accent else bw, 10, 0.9 if accent else 0.0), r)
	if r.size.x > 40.0 and r.size.y > 30.0:
		# top sheen
		m.draw_line(r.position + Vector2(10, 1.5), Vector2(r.end.x - 10, r.position.y + 1.5), Color(1, 1, 1, 0.06 * fill.a), 1.0)


## Panel with an explicit glow strength (0 none .. 2 hot).
static func panel_glow(m, r: Rect2, col: Color, fill: Color = PANEL, glow: float = 1.0, bw: int = 2) -> void:
	m.draw_style_box(sb(col, fill, bw, 10, glow), r)
	m.draw_line(r.position + Vector2(10, 1.5), Vector2(r.end.x - 10, r.position.y + 1.5), Color(col, 0.25), 1.0)


static func bar(m, r: Rect2, frac: float, col: Color, back: Color = Color("0a0f1c")) -> void:
	var f: float = clampf(frac, 0.0, 1.0)
	var rad: int = int(minf(4.0, r.size.y * 0.5))
	m.draw_style_box(sb(Color(EDGE2, 0.8), back, 1, rad), r)
	if f > 0.0:
		var fr := Rect2(r.position, Vector2(maxf(2.0, r.size.x * f), r.size.y))
		m.draw_style_box(sb(Color(col, 0), col, 0, rad), fr)
		m.draw_rect(Rect2(fr.position, Vector2(fr.size.x, maxf(1.0, fr.size.y * 0.35))), Color(1, 1, 1, 0.18))


## Glowing progress bar: gradient fill, bright leading edge, optional ticks.
static func bar_glow(m, r: Rect2, frac: float, col: Color, ticks: int = 0, back: Color = Color("0a0f1c")) -> void:
	var f: float = clampf(frac, 0.0, 1.0)
	var rad: int = int(minf(6.0, r.size.y * 0.5))
	m.draw_style_box(sb(Color(col, 0.35), back, 1, rad), r)
	if f > 0.0:
		var w: float = maxf(3.0, r.size.x * f)
		var fr := Rect2(r.position, Vector2(w, r.size.y))
		m.draw_style_box(sb(Color(col, 0), Color(col, 0.0), 0, rad, 0.8), fr)
		var dk: Color = col.darkened(0.45)
		m.draw_polygon(PackedVector2Array([fr.position, Vector2(fr.end.x, fr.position.y), fr.end, Vector2(fr.position.x, fr.end.y)]), PackedColorArray([dk, col, col, dk]))
		m.draw_rect(Rect2(fr.position + Vector2(0, 1), Vector2(w, maxf(1.0, r.size.y * 0.3))), Color(1, 1, 1, 0.22))
		m.draw_line(Vector2(fr.end.x, r.position.y - 2), Vector2(fr.end.x, r.end.y + 2), col.lightened(0.6), 2.0)
	# ticks are notches on the top and bottom edges, so a centred label
	# (the Core's "HP 221 / 221") is never struck through
	var nl: float = maxf(3.0, r.size.y * 0.22)
	for k in range(1, ticks):
		var x: float = r.position.x + r.size.x * float(k) / float(ticks)
		m.draw_line(Vector2(x, r.position.y + 1), Vector2(x, r.position.y + 1 + nl), Color(0, 0, 0, 0.5), 1.0)
		m.draw_line(Vector2(x, r.end.y - 1 - nl), Vector2(x, r.end.y - 1), Color(0, 0, 0, 0.5), 1.0)


## Draws an ArtDB texture; false (nothing drawn) when it is missing.
static func icon(m, id: String, r: Rect2, mod: Color = Color.WHITE) -> bool:
	var tx: Texture2D = Art.tex(id)
	if tx == null:
		return RunArt.draw(m, id, r, mod)   # V2 P7d: procedural icons for new run content
	m.draw_texture_rect(tx, r, false, mod)
	return true


## Section header: Chakra Petch caps + a glowing underline that fades out.
static func head(m, s: String, pos: Vector2, width: float, col: Color = RUST) -> void:
	th(m, s.to_upper(), pos, 17, col, HORIZONTAL_ALIGNMENT_LEFT, width)
	var y: float = pos.y + 8.0
	var w: float = minf(width, 420.0)
	m.draw_polygon(PackedVector2Array([Vector2(pos.x, y), Vector2(pos.x + w, y), Vector2(pos.x + w, y + 2), Vector2(pos.x, y + 2)]), PackedColorArray([Color(col, 0.8), Color(col, 0.0), Color(col, 0.0), Color(col, 0.8)]))
	if width > w:
		m.draw_line(Vector2(pos.x + w, y + 1), Vector2(pos.x + width, y + 1), Color(EDGE2, 0.5), 1.0)


## Label / value row; registers a tooltip region when `tip` is given.
static func row(m, label: String, value: String, pos: Vector2, width: float, col: Color = TEXT, tip: String = "", size: int = 17) -> void:
	t(m, label, pos, size, DIM, HORIZONTAL_ALIGNMENT_LEFT, width * 0.62)
	th(m, value, pos + Vector2(width, 0), size, col, HORIZONTAL_ALIGNMENT_RIGHT, width * 0.5)
	if tip != "":
		m.stat_tips.append([Rect2(pos.x, pos.y - size - 2, width, size + 8), tip])


## Big glowing number / title in Chakra Petch Bold; `sc` scales it (roll pop).
static func big_number(m, s: String, pos: Vector2, size: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER, width: float = 400.0, sc: float = 1.0) -> void:
	var sz: int = int(round(float(size) * sc))
	var p: Vector2 = pos
	var f: Font = Fonts.bold()
	_note_size(s, sz, col)
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		p.x -= width * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		p.x -= width
	for o in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
		m.draw_string(f, p + o, s, align, width, sz, Color(col, 0.16 * col.a))
	m.draw_string(f, p + Vector2(0, 3), s, align, width, sz, Color(0, 0, 0, 0.6 * col.a))
	m.draw_string(f, p, s, align, width, sz, col)


## Gear / draft card frame: dark card, rarity-tinted gradient, rarity border
## whose glow grows with rarity, a top band, and a shimmer from Legendary up
## (Exotic cycles its hue).
static func card_frame(m, r: Rect2, rarity: String, t: float = 0.0, hover: bool = false) -> void:
	var rk: int = maxi(0, rarity_rank(rarity))
	var col: Color = rarity_col_t(rarity, t)
	var glow: float = 0.25 + 0.22 * float(rk) + (0.5 if hover else 0.0)
	m.draw_style_box(sb(col, CARD, 2, 10, glow), r)
	var top := Color(col, 0.22)
	var bot := Color(col, 0.0)
	var g := r.grow(-2.0)
	m.draw_polygon(PackedVector2Array([g.position, Vector2(g.end.x, g.position.y), Vector2(g.end.x, g.position.y + g.size.y * 0.55), Vector2(g.position.x, g.position.y + g.size.y * 0.55)]), PackedColorArray([top, top, bot, bot]))
	m.draw_rect(Rect2(r.position.x + 10, r.position.y + 2, r.size.x - 20, 4), col)
	if rk >= 4:
		Beam.shimmer(m, g, t + r.position.x * 0.01, Color(1, 1, 1, 0.07 + 0.03 * float(rk - 4)))


## Loot beam in a rarity colour standing on `base` (P5 loot, LootReveal).
static func rarity_beam(m, base: Vector2, rarity: String, h: float, t: float, w: float = 26.0) -> void:
	var rk: int = maxi(0, rarity_rank(rarity))
	Beam.draw(m, base, rarity_col_t(rarity, t), h, w, t, 0.35 + 0.11 * float(rk))


## A loot beam in any colour (LootReveal's white -> rarity climb).
static func beam_col(m, base: Vector2, col: Color, h: float, w: float, t: float, alpha: float) -> void:
	Beam.draw(m, base, col, h, w, t, alpha)


## Requirement chip (P6): a button that jumps to what is missing. Green when
## met, red when not. Key: "req:<kind>:<id>".
static func req_chip(m, rect: Rect2, kind: String, id: String, label: String, met: bool, cb: Callable, tip: String = "", icon_id: String = "") -> Button:
	var col: Color = GREEN if met else ENEMY
	# V2 P9 audit: state is not hue-only (unmet = a lock icon, met = "DONE"),
	# the chip is an outline (quieter than a buyable card's price) and
	# its text is inset from the border.
	var b: Button = btn(m, ("DONE  " if met else "") + label, rect, cb, tip if tip != "" else ("%s — done" % label if met else "%s — click to go there" % label), true, col, "req:%s:%s" % [kind, id], icon_id if icon_id != "" else ("" if met else "icon_lock"), 15)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if met:
		b.add_theme_color_override("font_color", GREEN.lerp(TEXT, 0.35))
	for st in ["normal", "hover", "pressed"]:
		var sbx: StyleBoxFlat = (b.get_theme_stylebox(st) as StyleBoxFlat).duplicate()
		sbx.content_margin_left = 10.0
		sbx.content_margin_right = 8.0
		if st == "normal":
			sbx.bg_color = Color(BG2, 0.85)
			sbx.border_color = Color(col, 0.7)
		b.add_theme_stylebox_override(st, sbx)
	b.add_theme_constant_override("h_separation", 8)
	return b


## Tab strip: one button per [id, label, icon, tip]; the active tab is filled
## with a bright underline. `disabled` ids are shown but locked. Each button
## calls cb.call(id); keys are key_prefix + label.
static func tabs(m, r: Rect2, items: Array, active: String, cb: Callable, key_prefix: String = "TAB ", disabled: Array = [], fsize: int = 17) -> Array:
	var out: Array = []
	var n: int = maxi(1, items.size())
	var gap: float = 6.0
	var w: float = (r.size.x - gap * float(n - 1)) / float(n)
	for k in items.size():
		var it: Array = items[k]
		var id: String = String(it[0])
		var on: bool = id == active
		var b: Button = btn(m, String(it[1]), Rect2(r.position.x + float(k) * (w + gap), r.position.y, w, r.size.y), func() -> void: cb.call(id), String(it[3]), not (id in disabled), CYAN if on else NEUTRAL, key_prefix + String(it[1]), String(it[2]), fsize)
		if on:
			var st: StyleBoxFlat = sb(CYAN, tint(CYAN, 0.22), 2, 8, 1.1).duplicate()
			st.border_width_bottom = 4
			b.add_theme_stylebox_override("normal", st)
			b.add_theme_stylebox_override("hover", st)
		else:
			var nt: StyleBoxFlat = sb(Color(EDGE2, 0.9), Color(BG2, 0.7), 1, 8)
			b.add_theme_stylebox_override("normal", nt)
			b.add_theme_color_override("font_color", DIM)
		out.append(b)
	return out


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


## Currency chip: a pill with icon + amount (Chakra Petch) + tooltip region.
## `sc` scales the number (roll-up landing pop).
static func chip(m, icon_id: String, txt: String, pos: Vector2, col: Color, tip: String, w: float = 120.0, sc: float = 1.0) -> void:
	var pr := Rect2(pos.x - 4, pos.y - 30, w, 38)
	m.draw_style_box(sb(Color(col, 0.35), Color(BG2, 0.85), 1, 19), pr)
	icon(m, icon_id, Rect2(pos.x + 2, pos.y - 26, 30, 30))
	var sz: int = int(round(20.0 * sc))
	th(m, txt, pos + Vector2(38, 0), sz, col, HORIZONTAL_ALIGNMENT_LEFT, w - 42.0)
	m.stat_tips.append([Rect2(pos.x, pos.y - 30, w, 40), tip])


## Thin pulsing focus outline used for armed / selected items.
static func outline(m, r: Rect2, col: Color, wdt: float = 3.0) -> void:
	m.draw_style_box(sb(col, Color(0, 0, 0, 0), int(wdt), 6, 0.8), r)


## App background: navy vertical gradient, a faint blueprint grid and a
## vignette (drawn first in Main._draw).
static func bg(m, r: Rect2, t: float = 0.0) -> void:
	m.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]), PackedColorArray([BG, BG, BG2, BG2]))
	var step: float = 64.0
	var gc := Color(CYAN, 0.025)
	var x: float = r.position.x + fposmod(-t * 4.0, step)
	while x < r.end.x:
		m.draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), gc, 1.0)
		x += step
	var y: float = r.position.y
	while y < r.end.y:
		m.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), gc, 1.0)
		y += step
	# soft magenta / cyan corner haze
	var hz: float = minf(r.size.x, r.size.y)
	glow(m, r.position + Vector2(r.size.x * 0.88, r.size.y * 0.05), hz * 0.55, MAGENTA, 0.07)
	glow(m, r.position + Vector2(r.size.x * 0.08, r.size.y * 0.98), hz * 0.65, CYAN, 0.06)


## Soft radial glow (a cached white radial gradient, tinted): neon halos
## behind the Core, rewards and the background haze.
static func glow(m, c: Vector2, rad: float, col: Color, alpha: float = 0.3) -> void:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.35))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = g
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128
		_glow_tex.height = 128
	m.draw_texture_rect(_glow_tex, Rect2(c - Vector2(rad, rad), Vector2(rad, rad) * 2.0), false, Color(col, alpha))


## Key / pad glyph text for an action ("" when unbound).
static func hint(m, action: String) -> String:
	var pad: bool = String(m.last_device) == "pad"
	var h: String = Keybinds.hint(action, pad)
	if h == "" and pad:
		h = Keybinds.hint(action, false)
	return h


## Owner feedback #1 tooltip layout: the first line is a bold gold header; the
## rest splits into one stat line per row (" · " / ". " separators), each led
## by a related icon (damage, HP, rate, range, cash, coins, ...).
const TIP_ICONS: Array = [
	["cooldown", "ui_cooldown"], ["dmg", "in_dmg"], ["damage", "in_dmg"], ["crit", "in_dmg"],
	["hp", "in_hp"], ["regen", "in_hp"], ["armor", "pk_fort"], ["shield", "elite_shield"],
	["rate", "in_rate"], ["speed", "icon_speed"], ["range", "pk_optics"], ["cell", "pk_optics"],
	["coin", "cur_coin"], ["cash", "cur_cash"], ["$", "cur_cash"], ["interest", "cur_cash"],
	["scrap", "cur_scrap"], ["key", "cur_key"], ["level", "icon_tier"], ["lv", "icon_tier"],
	["click", "icon_info"], ["drag", "icon_info"], ["wave", "icon_clock"], ["kill", "mis_kill"],
]


static func tip_icon(line: String) -> String:
	var l: String = line.to_lower()
	for e in TIP_ICONS:
		var a: Array = e
		if l.contains(String(a[0])):
			return String(a[1])
	return ""


static func tip_bbcode(t: String) -> String:
	var lines: PackedStringArray = t.split("\n")
	if lines.is_empty():
		return ""
	var head: String = lines[0].replace("[", "(").replace("]", ")")
	var out: String = "[b][color=#%s]%s[/color][/b]" % [GOLD.to_html(false), head]
	var rows: Array = []
	for k in range(1, lines.size()):
		for part in lines[k].split("  ·  "):
			var p: String = String(part).strip_edges()
			if p != "":
				rows.append(p.replace("[", "(").replace("]", ")"))
	for r in rows:
		var row: String = String(r)
		var ic: String = tip_icon(row)
		var lead: String = "[img=18x18]res://art/%s.svg[/img] " % ic if ic != "" and Art.tex(ic) != null else "[color=#%s]•[/color] " % DIM.to_html(false)
		out += "\n" + lead + row
	return out
