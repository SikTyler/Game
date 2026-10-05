extends RefCounted
## V2 typefaces (P2). Inter (variable, OFL) for body text; Chakra Petch (OFL)
## for headings, buttons and numbers. Loaded once and cached; each face falls
## back to Inter, then Godot's built-in font, for glyphs it lacks (Chakra
## Petch has no arrows or box symbols). Licenses: fonts/OFL.txt.

const INTER: String = "res://fonts/Inter.ttf"
const CHAKRA_SEMI: String = "res://fonts/ChakraPetch-SemiBold.ttf"
const CHAKRA_BOLD: String = "res://fonts/ChakraPetch-Bold.ttf"
const BODY_WGHT: int = 500   # Inter Medium: reads cleanly on the dark panels

static var _body: Font
static var _head: Font
static var _bold: Font


static func _file(path: String) -> FontFile:
	if not ResourceLoader.exists(path):
		return null
	var f: FontFile = load(path)
	return f


## Inter Medium (variable font pinned to wght 500).
static func body() -> Font:
	if _body == null:
		var f: FontFile = _file(INTER)
		if f == null:
			_body = ThemeDB.fallback_font
		else:
			f.fallbacks = [ThemeDB.fallback_font]
			var v := FontVariation.new()
			v.base_font = f
			v.variation_opentype = {"wght": BODY_WGHT}
			_body = v
	return _body


## Chakra Petch SemiBold: headings, button labels, small numbers.
static func head() -> Font:
	if _head == null:
		_head = _chakra(CHAKRA_SEMI)
	return _head


## Chakra Petch Bold: titles and big numbers.
static func bold() -> Font:
	if _bold == null:
		_bold = _chakra(CHAKRA_BOLD)
	return _bold


static func _chakra(path: String) -> Font:
	var f: FontFile = _file(path)
	if f == null:
		return body()
	f.fallbacks = [body(), ThemeDB.fallback_font]
	return f
