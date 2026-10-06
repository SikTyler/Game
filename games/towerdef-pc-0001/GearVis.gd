extends RefCounted
## Procedural gear visuals (V2 P4c): every Weapon, Module and the Core is
## drawn from primitives - no sprites - so the billions of rolls each look
## like what they are. `parts()` is the pure description (also the test's
## uniqueness signature); the draw functions only render it.
##   Weapon: frame body / barrel / muzzle (FrameDB look) + seeded stock, sight,
##     decal and fin style; perk-driven parts (crit -> scope, multishot -> twin
##     barrel, splash -> drum, chain -> coil, burn -> canister, pierce -> long
##     rail, slow -> frost vanes); masterwork fins + lights; level trims at
##     10 / 20 / 30; an animated rim for Legendary and up; the item's paint
##     (primary, secondary, glow) and pattern.
##   Module: a pod (ModuleDB look -> shell + glyph), rarity tint, paint.
##   Core: shell (8) x inner trim (5) x pattern (8) in the player's colours,
##     a pod per socket around it and the Weapon turret in the middle.
## Draw calls take the canvas `ci` and its current transform `base` (Battle
## draws the world through a camera transform) and restore it after.

const FrameDB := preload("res://data/FrameDB.gd")
const ModuleDB := preload("res://data/ModuleDB.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const AffixDB := preload("res://data/AffixDB.gd")

const STOCKS: int = 6
const SIGHTS: int = 5
const DECALS: int = 8
const FINS: int = 4
const SHELLS: Array = [6, 8, 12, 5, 7, 10, 16, 4]    # Core shell polygon sides
const RARITY_COL: Dictionary = {"common": Color("9aa4b2"), "uncommon": Color("4ade80"), "rare": Color("38bdf8"),
	"epic": Color("b26bff"), "legendary": Color("f59e0b"), "mythic": Color("ff3e6c"), "exotic": Color("ffffff")}
## perk key -> the part it grows on a weapon
const PERK_PARTS: Dictionary = {"crit": "scope", "crit_dmg": "scope", "multishot": "twin", "splash": "drum",
	"chain": "coil", "chain_dmg": "coil", "burn": "canister", "pierce": "rail", "slow_hit": "vanes", "bounce": "twin"}


# ------------------------------------------------------------------ parts

## The full visual description of an item (pure, deterministic).
static func parts(it: Dictionary) -> Dictionary:
	var sd: int = absi(int(it.get("seed", 0)))
	var pa: Dictionary = it.get("paint", {})
	var out: Dictionary = {
		"kind": String(it.get("kind", "weapon")), "base": String(it.get("base", "")),
		"rar": String(it.get("rar", "common")), "mw": mini(6, int(it.get("mw", 0))),
		"trim": 3 if int(it.get("lvl", 1)) >= 30 else (2 if int(it.get("lvl", 1)) >= 20 else (1 if int(it.get("lvl", 1)) >= 10 else 0)),
		"rim": RarityDB.rank(String(it.get("rar", "common"))) >= RarityDB.rank("legendary"),
		"p": String(pa.get("p", "5a6788")), "s": String(pa.get("s", "39e6ff")), "g": String(pa.get("g", "e8f0ff")), "pat": int(pa.get("pat", 0)),
		"stock": sd % STOCKS, "sight": (sd / STOCKS) % SIGHTS, "decal": (sd / (STOCKS * SIGHTS)) % DECALS, "fin": (sd / (STOCKS * SIGHTS * DECALS)) % FINS,
	}
	if String(out["kind"]) == "weapon":
		var lk: Dictionary = FrameDB.get_def(String(out["base"]))["look"]
		out["body"] = int(lk["body"])
		out["barrel"] = int(lk["barrel"])
		out["muzzle"] = int(lk["muzzle"])
		var grown: Array = []
		for p in it.get("perks", []):
			var key: String = String((AffixDB.get_def(String((p as Dictionary).get("id", ""))) as Dictionary).get("key", ""))
			var part: String = String(PERK_PARTS.get(key, ""))
			if part != "" and not grown.has(part):
				grown.append(part)
		grown.sort()
		out["grown"] = grown
	else:
		out["look"] = int(ModuleDB.get_def(String(out["base"])).get("look", 0))
	return out


## A stable string of parts() (the uniqueness test hashes these).
static func signature(it: Dictionary) -> String:
	return JSON.stringify(parts(it))


static func _c(hex: String, fallback: Color = Color.WHITE) -> Color:
	return Color.html(hex) if Color.html_is_valid(hex) else fallback


# ------------------------------------------------------------------ transforms

## Push a local frame (origin, angle, units -> px scale) on top of `base`.
static func _push(ci: CanvasItem, base: Transform2D, origin: Vector2, angle: float, sc: float) -> void:
	ci.draw_set_transform_matrix(base * Transform2D(angle, Vector2(sc, sc), 0.0, origin))


static func _pop(ci: CanvasItem, base: Transform2D) -> void:
	ci.draw_set_transform_matrix(base)


# ------------------------------------------------------------------ weapon

## Draw a Weapon centred on `center`, `size` px long, pointing along `angle`.
## Local units: the gun spans x -50..+50, y -20..+20 (muzzle at +x).
static func draw_weapon(ci: CanvasItem, it: Dictionary, center: Vector2, size: float, angle: float = 0.0, t: float = 0.0, base: Transform2D = Transform2D.IDENTITY) -> void:
	var P: Dictionary = parts(it)
	var pc: Color = _c(String(P["p"]), Color("5a6788"))
	var sc: Color = _c(String(P["s"]), Color("39e6ff"))
	var gc: Color = _c(String(P["g"]), Color("e8f0ff"))
	var dark: Color = pc.darkened(0.55)
	var rc: Color = _rar_col(String(P["rar"]), t)
	var grown: Array = P.get("grown", [])
	_push(ci, base, center, angle, size / 100.0)
	# rarity under-glow
	if bool(P["rim"]):
		var a: float = 0.25 + 0.15 * sin(t * 4.0)
		ci.draw_circle(Vector2(0, 0), 46.0, Color(rc, a * 0.35))
	# stock (left)
	_stock(ci, int(P["stock"]), pc, dark)
	# barrel(s)
	var bl: float = 34.0 + 3.0 * float(int(P["barrel"]) % 5) + (10.0 if grown.has("rail") else 0.0)
	var bw: float = 5.0 + float(int(P["barrel"]) / 5) * 2.0
	if grown.has("twin"):
		_barrel(ci, Vector2(8, -5.0), bl, bw * 0.8, sc, dark)
		_barrel(ci, Vector2(8, 5.0), bl, bw * 0.8, sc, dark)
	else:
		_barrel(ci, Vector2(8, 0), bl, bw, sc, dark)
	if grown.has("coil"):
		for k in 4:
			var x: float = 14.0 + float(k) * 7.0
			ci.draw_arc(Vector2(x, 0), bw + 2.0, 0.0, TAU, 12, gc, 1.6)
	if grown.has("rail"):
		ci.draw_line(Vector2(6, -bw - 4.0), Vector2(8 + bl + 6.0, -bw - 4.0), gc, 1.5)
	# muzzle
	_muzzle(ci, int(P["muzzle"]), Vector2(8 + bl, 0), bw, gc, dark, t)
	# body (on top of the barrel root)
	var body: PackedVector2Array = _body_poly(int(P["body"]))
	ci.draw_colored_polygon(body, pc)
	_pattern(ci, int(P["pat"]), body, sc, Rect2(-26, -14, 46, 28))
	_outline(ci, body, dark, 2.0)
	# decal
	_decal(ci, int(P["decal"]), sc, gc)
	# perk parts
	if grown.has("drum"):
		ci.draw_circle(Vector2(-4, 15), 8.0, dark)
		ci.draw_circle(Vector2(-4, 15), 5.5, sc)
		ci.draw_circle(Vector2(-4, 15), 2.0, dark)
	if grown.has("canister"):
		ci.draw_rect(Rect2(10, 8, 14, 7), Color("ff8a3d"))
		ci.draw_rect(Rect2(10, 8, 14, 7), dark, false, 1.2)
	if grown.has("vanes"):
		for k in 3:
			var vx: float = -14.0 + float(k) * 9.0
			ci.draw_colored_polygon(PackedVector2Array([Vector2(vx, 14), Vector2(vx + 6, 14), Vector2(vx + 3, 21)]), Color("9be8ff"))
	# sight / scope
	if grown.has("scope"):
		ci.draw_rect(Rect2(-12, -24, 26, 7), dark)
		ci.draw_circle(Vector2(14, -20.5), 3.5, gc)
		ci.draw_circle(Vector2(14, -20.5), 1.6, Color(gc, 0.5 + 0.5 * sin(t * 3.0)))
	else:
		_sight(ci, int(P["sight"]), dark, gc)
	# masterwork fins + lights
	for k in int(P["mw"]):
		var fx: float = -18.0 + float(k) * 6.5
		var tri: PackedVector2Array = _fin(int(P["fin"]), fx)
		ci.draw_colored_polygon(tri, Color("ffd34d"))
		ci.draw_circle(Vector2(fx + 2.5, -10.0), 1.4, Color(gc, 0.6 + 0.4 * sin(t * 5.0 + float(k))))
	# level trims
	for k in int(P["trim"]):
		var y: float = 11.0 - float(k) * 3.0
		ci.draw_line(Vector2(-22, y), Vector2(16, y), Color("ffd34d") if k == 2 else Color("e8f0ff", 0.8), 1.2)
	# rim
	if bool(P["rim"]):
		_outline(ci, body, rc, 1.5 + 0.8 * (0.5 + 0.5 * sin(t * 4.0)))
	_pop(ci, base)


static func _rar_col(r: String, t: float) -> Color:
	if r == "exotic":
		return Color.from_hsv(fposmod(t * 0.18, 1.0), 0.55, 1.0)
	return RARITY_COL.get(r, Color("9aa4b2"))


static func _outline(ci: CanvasItem, poly: PackedVector2Array, col: Color, w: float) -> void:
	var pts: PackedVector2Array = poly.duplicate()
	pts.append(poly[0])
	ci.draw_polyline(pts, col, w, true)


## Five body silhouettes: box, wedge, round pod, hex, long slab.
static func _body_poly(k: int) -> PackedVector2Array:
	match k % 5:
		1:
			return PackedVector2Array([Vector2(-26, -10), Vector2(14, -14), Vector2(22, 0), Vector2(14, 12), Vector2(-26, 12)])
		2:
			var o: PackedVector2Array = PackedVector2Array()
			for i in 14:
				var a: float = TAU * float(i) / 14.0
				o.append(Vector2(cos(a) * 22.0 - 4.0, sin(a) * 13.0))
			return o
		3:
			return PackedVector2Array([Vector2(-24, 0), Vector2(-14, -14), Vector2(12, -14), Vector2(22, 0), Vector2(12, 14), Vector2(-14, 14)])
		4:
			return PackedVector2Array([Vector2(-30, -8), Vector2(24, -10), Vector2(24, 9), Vector2(-30, 11)])
	return PackedVector2Array([Vector2(-24, -13), Vector2(18, -13), Vector2(20, -10), Vector2(20, 12), Vector2(-24, 12)])


static func _barrel(ci: CanvasItem, root: Vector2, ln: float, w: float, col: Color, dark: Color) -> void:
	ci.draw_rect(Rect2(root - Vector2(0, w * 0.5), Vector2(ln, w)), dark)
	ci.draw_rect(Rect2(root - Vector2(0, w * 0.5) + Vector2(0, 1), Vector2(ln, w - 2.0)), col.darkened(0.15))
	ci.draw_line(root + Vector2(2, -w * 0.5 + 1.5), root + Vector2(ln - 2.0, -w * 0.5 + 1.5), Color(1, 1, 1, 0.35), 1.0)


static func _muzzle(ci: CanvasItem, k: int, tip: Vector2, w: float, gc: Color, dark: Color, t: float) -> void:
	match k % 9:
		0:   # brake
			ci.draw_rect(Rect2(tip + Vector2(-2, -w * 0.9), Vector2(6, w * 1.8)), dark)
		1:   # lens
			ci.draw_circle(tip + Vector2(2, 0), w * 0.8, gc)
		2:   # bell
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -w * 0.5), tip + Vector2(8, -w * 1.2), tip + Vector2(8, w * 1.2), tip + Vector2(0, w * 0.5)]), dark)
		3:   # ring emitter
			ci.draw_arc(tip + Vector2(3, 0), w, 0.0, TAU, 16, gc, 2.0)
		4:   # flared choke
			ci.draw_colored_polygon(PackedVector2Array([tip + Vector2(0, -w * 0.5), tip + Vector2(6, -w), tip + Vector2(6, w), tip + Vector2(0, w * 0.5)]), gc.darkened(0.3))
		5:   # prongs
			ci.draw_line(tip + Vector2(0, -w * 0.5), tip + Vector2(8, -w * 1.1), gc, 2.0)
			ci.draw_line(tip + Vector2(0, w * 0.5), tip + Vector2(8, w * 1.1), gc, 2.0)
		6:   # nozzle with a pilot light
			ci.draw_rect(Rect2(tip + Vector2(0, -w * 0.6), Vector2(5, w * 1.2)), dark)
			ci.draw_circle(tip + Vector2(6, 0), 2.0, Color("ff8a3d", 0.6 + 0.4 * sin(t * 9.0)))
		7:   # pod rack
			for i in 3:
				ci.draw_circle(tip + Vector2(3, (float(i) - 1.0) * w * 0.8), w * 0.35, gc)
		_:   # blade guard
			ci.draw_arc(tip + Vector2(2, 0), w * 1.3, -PI * 0.5, PI * 0.5, 10, gc, 2.0)


static func _stock(ci: CanvasItem, k: int, pc: Color, dark: Color) -> void:
	match k:
		0:
			ci.draw_rect(Rect2(-46, -6, 22, 12), dark)
		1:
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-24, -8), Vector2(-48, -12), Vector2(-48, 12), Vector2(-24, 8)]), dark)
		2:
			ci.draw_rect(Rect2(-44, -9, 4, 18), dark)
			ci.draw_line(Vector2(-42, 0), Vector2(-24, 0), dark, 3.0)
		3:
			ci.draw_circle(Vector2(-34, 0), 9.0, dark)
			ci.draw_circle(Vector2(-34, 0), 4.0, pc)
		4:
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-24, -6), Vector2(-40, -6), Vector2(-46, 10), Vector2(-24, 6)]), dark)
		_:
			pass   # stockless


static func _sight(ci: CanvasItem, k: int, dark: Color, gc: Color) -> void:
	match k:
		0:
			ci.draw_rect(Rect2(-4, -19, 10, 5), dark)
		1:
			ci.draw_arc(Vector2(2, -17), 4.0, PI, TAU, 8, dark, 2.0)
		2:
			ci.draw_circle(Vector2(0, -17), 2.5, gc)
		3:
			ci.draw_line(Vector2(-10, -16), Vector2(10, -16), dark, 3.0)
		_:
			pass


static func _decal(ci: CanvasItem, k: int, sc: Color, gc: Color) -> void:
	match k:
		0:
			ci.draw_line(Vector2(-18, -4), Vector2(-6, -4), sc, 2.0)
		1:
			ci.draw_polyline(PackedVector2Array([Vector2(-16, -6), Vector2(-11, 0), Vector2(-16, 6)]), sc, 2.0)
		2:
			for i in 3:
				ci.draw_circle(Vector2(-18 + float(i) * 5.0, 4), 1.5, gc)
		3:
			ci.draw_rect(Rect2(-18, -3, 6, 6), sc)
		4:
			ci.draw_line(Vector2(-20, 6), Vector2(-8, -6), sc, 2.0)
		5:
			ci.draw_arc(Vector2(-12, 0), 5.0, 0.0, TAU, 10, sc, 1.5)
		6:
			ci.draw_line(Vector2(-20, 0), Vector2(10, 0), Color(sc, 0.6), 1.0)
		_:
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-16, -5), Vector2(-10, 0), Vector2(-16, 5), Vector2(-14, 0)]), gc)


static func _fin(style: int, x: float) -> PackedVector2Array:
	match style:
		1:
			return PackedVector2Array([Vector2(x, -12), Vector2(x + 5, -12), Vector2(x + 5, -19)])
		2:
			return PackedVector2Array([Vector2(x, -12), Vector2(x + 5, -12), Vector2(x + 2.5, -20)])
		3:
			return PackedVector2Array([Vector2(x, -12), Vector2(x + 4, -12), Vector2(x + 6, -17), Vector2(x + 2, -17)])
	return PackedVector2Array([Vector2(x, -12), Vector2(x + 5, -12), Vector2(x, -18)])


## Paint pattern over a shape's bounding rect (0 solid .. 7).
static func _pattern(ci: CanvasItem, pat: int, poly: PackedVector2Array, col: Color, r: Rect2) -> void:
	var c: Color = Color(col, 0.55)
	match pat:
		1:   # stripes
			for i in 4:
				var x: float = r.position.x + 6.0 + float(i) * 10.0
				ci.draw_line(Vector2(x, r.position.y + 3.0), Vector2(x, r.end.y - 3.0), c, 2.0)
		2:   # chevrons
			for i in 3:
				var x: float = r.position.x + 8.0 + float(i) * 12.0
				ci.draw_polyline(PackedVector2Array([Vector2(x, r.position.y + 4.0), Vector2(x + 6.0, r.get_center().y), Vector2(x, r.end.y - 4.0)]), c, 2.0)
		3:   # dots
			for i in 4:
				for j in 2:
					ci.draw_circle(Vector2(r.position.x + 6.0 + float(i) * 10.0, r.position.y + 8.0 + float(j) * 12.0), 1.8, c)
		4:   # split two-tone
			var top: PackedVector2Array = PackedVector2Array()
			for p in poly:
				top.append(Vector2(p.x, minf(p.y, r.get_center().y)))
			ci.draw_colored_polygon(top, Color(col, 0.35))
		5:   # tiger
			for i in 4:
				var x: float = r.position.x + 5.0 + float(i) * 10.0
				ci.draw_line(Vector2(x, r.position.y + 2.0), Vector2(x + 6.0, r.get_center().y), c, 2.5)
		6:   # checker
			for i in 4:
				for j in 2:
					if (i + j) % 2 == 0:
						ci.draw_rect(Rect2(r.position.x + 4.0 + float(i) * 9.0, r.position.y + 4.0 + float(j) * 9.0, 8, 8), Color(col, 0.35))
		7:   # band
			ci.draw_rect(Rect2(r.position.x + 2.0, r.get_center().y - 3.0, r.size.x - 4.0, 6.0), Color(col, 0.45))
		_:
			pass


# ------------------------------------------------------------------ module

## Draw a Module pod centred on `center`, `size` px across.
static func draw_module(ci: CanvasItem, it: Dictionary, center: Vector2, size: float, t: float = 0.0, base: Transform2D = Transform2D.IDENTITY) -> void:
	var P: Dictionary = parts(it)
	var pc: Color = _c(String(P["p"]), Color("5a6788"))
	var sc: Color = _c(String(P["s"]), Color("39e6ff"))
	var gc: Color = _c(String(P["g"]), Color("e8f0ff"))
	var rc: Color = _rar_col(String(P["rar"]), t)
	var look: int = int(P.get("look", 0))
	_push(ci, base, center, 0.0, size / 40.0)
	var shell: PackedVector2Array = _ngon(Vector2.ZERO, 17.0, [6, 8, 4, 12][look % 4], 0.0 if look % 2 == 0 else PI / 8.0)
	ci.draw_colored_polygon(shell, pc)
	_pattern(ci, int(P["pat"]), shell, sc, Rect2(-15, -12, 30, 24))
	_outline(ci, shell, rc, 2.0 + (0.8 * (0.5 + 0.5 * sin(t * 4.0)) if bool(P["rim"]) else 0.0))
	_glyph(ci, look, gc, sc)
	for k in int(P["mw"]):
		var a: float = -PI * 0.5 + float(k - int(P["mw"]) / 2) * 0.35
		ci.draw_circle(Vector2.from_angle(a) * 19.0, 1.6, Color("ffd34d"))
	_pop(ci, base)


static func _ngon(c: Vector2, r: float, n: int, rot: float) -> PackedVector2Array:
	var o: PackedVector2Array = PackedVector2Array()
	for i in n:
		o.append(c + Vector2.from_angle(rot + TAU * float(i) / float(n)) * r)
	return o


## 23 module glyphs: 8 base strokes x 3 accents.
static func _glyph(ci: CanvasItem, look: int, gc: Color, sc: Color) -> void:
	match look % 8:
		0:
			ci.draw_line(Vector2(-7, -3), Vector2(7, -3), gc, 2.5)
			ci.draw_line(Vector2(-7, 3), Vector2(7, 3), gc, 2.5)
		1:
			ci.draw_arc(Vector2.ZERO, 6.0, 0.0, TAU, 14, gc, 2.0)
			ci.draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 18, Color(gc, 0.5), 1.0)
		2:
			ci.draw_circle(Vector2.ZERO, 6.5, gc)
		3:
			ci.draw_line(Vector2(-9, 0), Vector2(9, 0), gc, 3.0)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(9, -4), Vector2(14, 0), Vector2(9, 4)]), gc)
		4:
			ci.draw_polyline(PackedVector2Array([Vector2(-8, 6), Vector2(-2, -6), Vector2(3, 4), Vector2(8, -6)]), gc, 2.0)
		5:
			ci.draw_polyline(PackedVector2Array([Vector2(-7, -7), Vector2(0, -1), Vector2(-4, 1), Vector2(7, 8)]), gc, 2.5)
		6:
			ci.draw_line(Vector2(-7, 0), Vector2(7, 0), gc, 2.0)
			ci.draw_line(Vector2(0, -7), Vector2(0, 7), gc, 2.0)
		_:
			ci.draw_colored_polygon(_ngon(Vector2.ZERO, 7.0, 3, -PI * 0.5), gc)
	match look / 8:
		1:
			ci.draw_circle(Vector2(0, 10), 1.8, sc)
		2:
			ci.draw_line(Vector2(-6, -10), Vector2(6, -10), sc, 1.5)


# ------------------------------------------------------------------ core

## Draw the Core: shell + trim + pattern in `look` colours, a pod per socket
## (`pods`: items or {} for an empty socket) and the Weapon turret at
## `aim` radians. `r` = shell radius in px.
static func draw_core(ci: CanvasItem, look: Dictionary, pods: Array, weapon: Dictionary, center: Vector2, r: float, aim: float = -PI * 0.5, t: float = 0.0, base: Transform2D = Transform2D.IDENTITY) -> void:
	var pc: Color = _c(String(look.get("p", "1b2440")), Color("1b2440"))
	var sc: Color = _c(String(look.get("s", "39e6ff")), Color("39e6ff"))
	var gc: Color = _c(String(look.get("g", "ff3ea5")), Color("ff3ea5"))
	var sh: int = clampi(int(look.get("shell", 0)), 0, SHELLS.size() - 1)
	_push(ci, base, center, 0.0, r / 50.0)
	var n: int = int(SHELLS[sh])
	var shell: PackedVector2Array = PackedVector2Array()
	for i in n * 2:
		var notch: bool = sh >= 4 and i % 2 == 1
		var a: float = TAU * float(i) / float(n * 2) - PI * 0.5
		shell.append(Vector2.from_angle(a) * (44.0 if notch else 50.0))
	ci.draw_circle(Vector2.ZERO, 58.0, Color(gc, 0.10 + 0.05 * sin(t * 2.0)))
	ci.draw_colored_polygon(shell, pc)
	_pattern(ci, int(look.get("pat", 0)), _ngon(Vector2.ZERO, 30.0, n, -PI * 0.5), sc, Rect2(-24, -24, 48, 48))
	_outline(ci, shell, sc, 3.0)
	_trim(ci, int(look.get("trim", 0)), sc, gc, t)
	# sockets
	var k: int = pods.size()
	for i in k:
		var a2: float = -PI * 0.5 + TAU * float(i) / float(maxi(1, k))
		var pp: Vector2 = Vector2.from_angle(a2) * 50.0
		var it: Dictionary = pods[i] if pods[i] is Dictionary else {}
		if it.is_empty():
			ci.draw_circle(pp, 7.0, Color(0.05, 0.07, 0.12, 0.9))
			ci.draw_arc(pp, 7.0, 0.0, TAU, 14, Color(sc, 0.5), 1.5)
		else:
			ci.draw_circle(pp, 9.0, _rar_col(String(it.get("rar", "common")), t))
			ci.draw_circle(pp, 6.5, _c(String((it.get("paint", {}) as Dictionary).get("p", "5a6788"))))
	_pop(ci, base)
	# the turret, on top, turned to its aim
	if not weapon.is_empty():
		draw_weapon(ci, weapon, center, r * 1.05, aim, t, base)


static func _trim(ci: CanvasItem, k: int, sc: Color, gc: Color, t: float) -> void:
	match k:
		1:
			ci.draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 32, sc, 2.0)
			ci.draw_arc(Vector2.ZERO, 36.0, 0.0, TAU, 32, Color(sc, 0.5), 1.5)
		2:
			for i in 12:
				var a: float = TAU * float(i) / 12.0 + t * 0.4
				ci.draw_arc(Vector2.ZERO, 33.0, a, a + 0.3, 4, gc, 2.5)
		3:
			for i in 8:
				var a: float = TAU * float(i) / 8.0
				ci.draw_line(Vector2.from_angle(a) * 18.0, Vector2.from_angle(a) * 38.0, Color(sc, 0.7), 2.0)
		4:
			_outline(ci, _ngon(Vector2.ZERO, 32.0, 6, 0.0), gc, 2.0)
		_:
			ci.draw_arc(Vector2.ZERO, 32.0, 0.0, TAU, 32, sc, 2.0)
	ci.draw_circle(Vector2.ZERO, 14.0, Color(gc, 0.25 + 0.15 * sin(t * 3.0)))
