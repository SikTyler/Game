extends RefCounted
## V2 neon-casino Godot Theme (P2), built once at boot and set on Main's
## Control layers (ui, tipbox). It covers the stock Controls the screens use
## directly (Label, RichTextLabel, ScrollContainer, LineEdit, PanelContainer,
## tooltips); Kit.btn styles its own buttons on top of it. Colours come from
## Kit tokens, fonts from Fonts. Named NeonTheme: `Theme` is a Godot class.

const Kit := preload("res://ui/Kit.gd")
const Fonts := preload("res://ui/Fonts.gd")

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme


static func build() -> Theme:
	var th := Theme.new()
	th.default_font = Fonts.body()
	th.default_font_size = 17
	# Buttons (Kit.btn overrides per accent; this is the stock fallback)
	th.set_font("font", "Button", Fonts.head())
	th.set_stylebox("normal", "Button", Kit.sb(Kit.NEUTRAL, Kit.tint(Kit.NEUTRAL, 0.2), 2, 8))
	th.set_stylebox("hover", "Button", Kit.sb(Kit.CYAN, Kit.tint(Kit.CYAN, 0.24), 2, 8, 1.0))
	th.set_stylebox("pressed", "Button", Kit.sb(Kit.CYAN, Kit.tint(Kit.CYAN, 0.34), 2, 8, 1.4))
	th.set_stylebox("disabled", "Button", Kit.sb(Kit.EDGE2, Color(Kit.BG2, 0.9), 1, 8))
	th.set_stylebox("focus", "Button", Kit.sb(Color.WHITE, Color(0, 0, 0, 0), 2, 8, 0.8))
	th.set_color("font_color", "Button", Kit.TEXT)
	th.set_color("font_disabled_color", "Button", Color(Kit.DIM, 0.75))
	# Labels
	th.set_color("font_color", "Label", Kit.TEXT)
	th.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	th.set_constant("shadow_offset_x", "Label", 1)
	th.set_constant("shadow_offset_y", "Label", 2)
	# Rich text: bold runs use Chakra Petch
	th.set_font("normal_font", "RichTextLabel", Fonts.body())
	th.set_font("bold_font", "RichTextLabel", Fonts.head())
	th.set_color("default_color", "RichTextLabel", Kit.TEXT)
	# Panels and tooltips
	var pnl: StyleBoxFlat = Kit.sb(Kit.EDGE2, Kit.PANEL, 1, 10).duplicate()
	pnl.set_content_margin_all(12)
	th.set_stylebox("panel", "PanelContainer", pnl)
	th.set_stylebox("panel", "TooltipPanel", Kit.tip_style())
	th.set_color("font_color", "TooltipLabel", Kit.TEXT)
	th.set_font("font", "TooltipLabel", Fonts.body())
	# Scrolling
	var grab: StyleBoxFlat = Kit.sb(Color(Kit.CYAN, 0.0), Color(Kit.CYAN, 0.45), 0, 4)
	var grab_hi: StyleBoxFlat = Kit.sb(Color(Kit.CYAN, 0.0), Color(Kit.CYAN, 0.8), 0, 4)
	var track: StyleBoxFlat = Kit.sb(Color(0, 0, 0, 0), Color(Kit.BG2, 0.6), 0, 4)
	for sc in ["VScrollBar", "HScrollBar"]:
		th.set_stylebox("grabber", sc, grab)
		th.set_stylebox("grabber_highlight", sc, grab_hi)
		th.set_stylebox("grabber_pressed", sc, grab_hi)
		th.set_stylebox("scroll", sc, track)
	# Text entry
	var le: StyleBoxFlat = Kit.sb(Kit.EDGE2, Color(Kit.BG, 0.9), 1, 6).duplicate()
	le.set_content_margin_all(8)
	var lef: StyleBoxFlat = Kit.sb(Kit.CYAN, Color(Kit.BG, 0.9), 2, 6, 0.8).duplicate()
	lef.set_content_margin_all(8)
	th.set_stylebox("normal", "LineEdit", le)
	th.set_stylebox("focus", "LineEdit", lef)
	th.set_color("font_color", "LineEdit", Kit.TEXT)
	th.set_color("caret_color", "LineEdit", Kit.CYAN)
	th.set_color("selection_color", "LineEdit", Color(Kit.CYAN, 0.35))
	return th
