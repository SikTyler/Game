extends RefCounted
## Outpost building art (V2 P6c): every building is drawn procedurally in the
## neon casino style instead of the V1 rust sprites -
##   a chamfered dark plate with a soft top light,
##   a neon rim in its palette category's colour (Production gold, Core cyan,
##     Scavenge magenta, Support violet),
##   a per-building glyph in its stat / resource colour over a soft halo,
##   level-band trims: Lv4+ corner studs, Lv8+ a gold inner rim and corner
##     caps, max level a light travelling round the rim.
## Unlinked buildings fade to grey; ghosts, moves and builds draw translucent.
## Decor and Conduits keep their textures (OutpostView._art).
##   draw(ci, id, lvl, r, t, opt)   opt: {linked = true, alpha = 1, max = 10}

const Kit := preload("res://ui/Kit.gd")
const OutpostDB := preload("res://data/OutpostDB.gd")

## Neon rim per palette category (OutpostDB def "cat").
const CAT_COL: Dictionary = {
	"production": Color("ffd34d"), "core": Color("39e6ff"), "scavenge": Color("ff3ea5"),
	"support": Color("a78bfa"), "links": Color("39e6ff"),
}
## Glyph colour per building: its stat or resource.
const COL: Dictionary = {
	"relay": Color("39e6ff"), "mill": Color("ffd34d"), "refinery": Color("e8c48f"), "gemmine": Color("6e9bff"),
	"arsenal": Color("ff4d6d"), "reactor": Color("ff9b3d"), "bulwark_w": Color("4ade80"), "aegis_a": Color("6e9bff"),
	"optics": Color("ff5fb8"), "rangefinder": Color("39e6ff"), "treasury": Color("ffd34d"), "training": Color("a3e635"),
	"shrine": Color("c084fc"), "forgeworks": Color("ff9b3d"),
	"scav_post": Color("ff5fb8"), "scav_den": Color("f472b6"), "scav_deep": Color("e879f9"),
	"fabricator": Color("39e6ff"), "smelter": Color("ff9b3d"),
	"research": Color("b69cff"), "barracks": Color("4ade80"), "archive": Color("9fe0ff"), "warehouse": Color("e8c48f"),
	"scrapyard": Color("e8c48f"), "beaconpost": Color("39e6ff"), "pylon": Color("ffd34d"),
}
const DEFAULT_COL: Color = Color("8a9bbd")


static func has_art(id: String) -> bool:
	return COL.has(id)


## Rim colour of a building id.
static func rim_col(id: String) -> Color:
	if id == "relay":
		return Color("39e6ff")
	return CAT_COL.get(String(OutpostDB.get_def(id).get("cat", "")), DEFAULT_COL)


static func glyph_col(id: String) -> Color:
	return COL.get(id, DEFAULT_COL)


static func _dim(c: Color) -> Color:
	var g: Color = c.lerp(Color(0.42, 0.45, 0.52), 0.7)
	g.a = c.a * 0.8
	return g


## A rect with its corners cut by `ch` (8 points, clockwise).
static func _chamfer(r: Rect2, ch: float) -> PackedVector2Array:
	var a: Vector2 = r.position
	var b: Vector2 = r.end
	return PackedVector2Array([
		Vector2(a.x + ch, a.y), Vector2(b.x - ch, a.y), Vector2(b.x, a.y + ch), Vector2(b.x, b.y - ch),
		Vector2(b.x - ch, b.y), Vector2(a.x + ch, b.y), Vector2(a.x, b.y - ch), Vector2(a.x, a.y + ch)])


static func _loop(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	var p2: PackedVector2Array = pts.duplicate()
	p2.append(pts[0])
	ci.draw_polyline(p2, col, w, true)


## Vertical gradient colours for a polygon inside `r`.
static func _grad(pts: PackedVector2Array, r: Rect2, top: Color, bot: Color) -> PackedColorArray:
	var out := PackedColorArray()
	for p in pts:
		out.append(top.lerp(bot, clampf((p.y - r.position.y) / maxf(1.0, r.size.y), 0.0, 1.0)))
	return out


## Point on a closed polyline at fraction f of its length.
static func _along(pts: PackedVector2Array, f: float) -> Vector2:
	var total: float = 0.0
	for k in pts.size():
		total += pts[k].distance_to(pts[(k + 1) % pts.size()])
	var want: float = fposmod(f, 1.0) * total
	for k in pts.size():
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % pts.size()]
		var l: float = a.distance_to(b)
		if want <= l:
			return a.lerp(b, want / maxf(0.001, l))
		want -= l
	return pts[0]


# ================================================================== frame
static func draw(ci: CanvasItem, id: String, lvl: int, r: Rect2, t: float = 0.0, opt: Dictionary = {}) -> void:
	var linked: bool = bool(opt.get("linked", true))
	var a: float = float(opt.get("alpha", 1.0))
	var mx: int = int(opt.get("max", 10))
	var rim: Color = rim_col(id)
	var gc: Color = glyph_col(id)
	if not linked:
		rim = _dim(rim)
		gc = _dim(gc)
	rim.a *= a
	gc.a *= a
	var s: float = minf(r.size.x, r.size.y)
	var ch: float = s * 0.16
	var plate: PackedVector2Array = _chamfer(r, ch)
	ci.draw_polygon(plate, _grad(plate, r, Color(0.10, 0.14, 0.25, 0.97 * a), Color(0.035, 0.05, 0.09, 0.97 * a)))
	# inner deck: tinted, hairline rim, two panel seams
	var inner: Rect2 = r.grow(-s * 0.11)
	var ip: PackedVector2Array = _chamfer(inner, ch * 0.6)
	ci.draw_colored_polygon(ip, Color(rim.r, rim.g, rim.b, 0.08 * a))
	_loop(ci, ip, Color(rim, 0.28 * a), 1.0)
	if r.size.x > r.size.y * 1.4:
		var sx: float = inner.position.x + inner.size.x * 0.5
		ci.draw_line(Vector2(sx, inner.position.y + 3), Vector2(sx, inner.end.y - 3), Color(rim, 0.10 * a), 1.0)
	# neon rim: wide soft pass + crisp line
	_loop(ci, plate, Color(rim, 0.22 * a), maxf(3.0, s * 0.06))
	_loop(ci, plate, rim, maxf(1.5, s * 0.022))
	# level trims
	if lvl >= 4:
		var st: float = maxf(2.0, s * 0.045)
		for k in [0, 2, 4, 6]:
			var c0: Vector2 = plate[k].lerp(plate[(k + 7) % 8], 0.5)
			ci.draw_rect(Rect2(c0 - Vector2(st, st), Vector2(st, st) * 2.0), rim.lightened(0.35))
	if lvl >= 8:
		var gold := Color(Kit.GOLD, 0.85 * a * (1.0 if linked else 0.5))
		_loop(ci, _chamfer(r.grow(-s * 0.055), ch * 0.8), gold, maxf(1.0, s * 0.012))
		var cap: float = s * 0.12
		ci.draw_colored_polygon(PackedVector2Array([r.position, r.position + Vector2(cap, 0), r.position + Vector2(0, cap)]), gold)
		ci.draw_colored_polygon(PackedVector2Array([r.end, r.end - Vector2(cap, 0), r.end - Vector2(0, cap)]), gold)
	if mx > 1 and lvl >= mx and linked:
		var head: Vector2 = _along(plate, t * 0.35)
		Kit.glow(ci, head, s * 0.16, Kit.GOLD, 0.7 * a)
		ci.draw_circle(head, maxf(1.5, s * 0.025), Color(1, 1, 1, 0.9 * a))
	# glyph over a halo
	var g: Vector2 = inner.get_center()
	var R: float = minf(inner.size.x, inner.size.y) * 0.40
	Kit.glow(ci, g, R * 1.9, gc, (0.30 if linked else 0.10) * a)
	_glyph(ci, id, g, R, gc, t if linked else 0.0, lvl, a)


# ================================================================= glyphs
static func _P(g: Vector2, R: float, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(g + (p as Vector2) * R)
	return out


static func _ngon(c: Vector2, r: float, n: int, rot: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in n:
		var an: float = rot + TAU * float(k) / float(n)
		out.append(c + Vector2(cos(an), sin(an)) * r)
	return out


static func _ellipse(c: Vector2, rx: float, ry: float, rot: float, n: int = 28) -> PackedVector2Array:
	var out := PackedVector2Array()
	var tr := Transform2D(rot, c)
	for k in n:
		var an: float = TAU * float(k) / float(n)
		out.append(tr * Vector2(cos(an) * rx, sin(an) * ry))
	return out


static func _quad(ci: CanvasItem, g: Vector2, R: float, x0: float, y0: float, x1: float, y1: float, col: Color) -> void:
	ci.draw_rect(Rect2(g + Vector2(x0, y0) * R, Vector2(x1 - x0, y1 - y0) * R), col)


static func _ring(ci: CanvasItem, c: Vector2, r: float, col: Color, w: float) -> void:
	ci.draw_arc(c, r, 0.0, TAU, 40, col, w, true)


static func _glyph(ci: CanvasItem, id: String, g: Vector2, R: float, gc: Color, t: float, lvl: int, a: float) -> void:
	var dark := Color(0.04, 0.06, 0.11, 0.95 * a)
	var lw: float = maxf(1.5, R * 0.10)
	var hi := Color(1, 1, 1, 0.85 * a)
	match id:
		"relay":
			_ring(ci, g, R * 0.95, gc, lw)
			for k in 10:
				var a0: float = -PI * 0.5 + TAU * float(k) / 10.0 + 0.06
				var on: bool = k < lvl
				ci.draw_arc(g, R * 0.78, a0, a0 + TAU / 10.0 - 0.12, 6, Color(Kit.GOLD, a) if on else Color(gc, 0.22 * a), lw * 1.4, true)
			_loop(ci, _ngon(g, R * 0.52, 6, t * 0.5), gc, lw)
			Kit.glow(ci, g, R * 0.6, Color.WHITE, 0.45 * a)
			ci.draw_circle(g, R * 0.24, gc.lightened(0.5))
		"mill":
			var rot: float = t * 0.6
			for k in 8:
				var an: float = rot + TAU * float(k) / 8.0
				var d := Vector2(cos(an), sin(an))
				var nn := Vector2(-d.y, d.x)
				var c0: Vector2 = g + d * R * 0.82
				ci.draw_colored_polygon(PackedVector2Array([c0 - d * R * 0.16 - nn * R * 0.12, c0 + d * R * 0.14 - nn * R * 0.09, c0 + d * R * 0.14 + nn * R * 0.09, c0 - d * R * 0.16 + nn * R * 0.12]), gc.darkened(0.15))
			ci.draw_circle(g, R * 0.72, dark)
			_ring(ci, g, R * 0.72, gc, lw)
			ci.draw_circle(g, R * 0.44, gc)
			_ring(ci, g, R * 0.32, dark, lw * 0.8)
			_quad(ci, g, R, -0.05, -0.22, 0.05, 0.22, dark)
		"refinery":
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.75, -0.25), Vector2(0.75, -0.25), Vector2(0.48, 0.8), Vector2(-0.48, 0.8)]), dark)
			_loop(ci, _P(g, R, [Vector2(-0.75, -0.25), Vector2(0.75, -0.25), Vector2(0.48, 0.8), Vector2(-0.48, 0.8)]), gc, lw)
			ci.draw_colored_polygon(_ellipse(g + Vector2(0, -0.25) * R, R * 0.66, R * 0.16, 0.0, 18), Color(Kit.GOLD, 0.9 * a))
			_quad(ci, g, R, -0.5, 0.2, 0.5, 0.32, Color(gc, 0.5 * a))
			for k in 3:
				var ph: float = fposmod(t * 0.8 + float(k) * 0.33, 1.0)
				ci.draw_circle(g + Vector2(-0.35 + 0.35 * float(k), -0.45 - 0.45 * ph) * R, R * 0.07 * (1.0 - ph * 0.6), Color(Kit.GOLD, (1.0 - ph) * a))
		"gemmine":
			var gem: Array = [Vector2(-0.45, -0.6), Vector2(0.45, -0.6), Vector2(0.85, -0.15), Vector2(0.0, 0.88), Vector2(-0.85, -0.15)]
			ci.draw_polygon(_P(g, R, gem), PackedColorArray([gc.lightened(0.3), gc, gc.darkened(0.2), gc.darkened(0.5), gc.darkened(0.1)]))
			var fl: Color = Color(1, 1, 1, 0.5 * a)
			ci.draw_line(g + Vector2(-0.85, -0.15) * R, g + Vector2(0.85, -0.15) * R, fl, 1.0)
			ci.draw_polyline(_P(g, R, [Vector2(-0.45, -0.6), Vector2(-0.22, -0.15), Vector2(0.0, 0.88), Vector2(0.22, -0.15), Vector2(0.45, -0.6)]), fl, 1.0, true)
			_loop(ci, _P(g, R, gem), gc.lightened(0.4), lw * 0.8)
			var tw: float = 0.5 + 0.5 * sin(t * 3.0)
			_sparkle(ci, g + Vector2(0.55, -0.7) * R, R * 0.22 * tw, Color(1, 1, 1, tw * a))
		"arsenal":
			for k in 3:
				var x: float = -0.55 + 0.55 * float(k)
				var hh: float = 0.0 if k == 1 else 0.12
				ci.draw_colored_polygon(_P(g, R, [Vector2(x - 0.16, -0.2 + hh), Vector2(x - 0.12, -0.48 + hh), Vector2(x, -0.72 + hh), Vector2(x + 0.12, -0.48 + hh), Vector2(x + 0.16, -0.2 + hh)]), gc.lightened(0.25))
				_quad(ci, g, R, x - 0.16, -0.2 + hh, x + 0.16, 0.78, gc)
				_quad(ci, g, R, x - 0.16, 0.48, x + 0.16, 0.58, dark)
		"reactor":
			for k in 3:
				var orb: PackedVector2Array = _ellipse(g, R * 0.92, R * 0.32, float(k) * PI / 3.0 + t * 0.4)
				_loop(ci, orb, Color(gc, 0.85 * a), lw * 0.8)
				ci.draw_circle(_along(orb, t * 0.5 + float(k) * 0.33), R * 0.09, hi)
			Kit.glow(ci, g, R * 0.55, gc, 0.6 * a)
			ci.draw_circle(g, R * 0.24, gc.lightened(0.4))
		"bulwark_w":
			var sh: Array = [Vector2(-0.72, -0.78), Vector2(0.72, -0.78), Vector2(0.72, 0.05), Vector2(0.0, 0.9), Vector2(-0.72, 0.05)]
			ci.draw_colored_polygon(_P(g, R, sh), gc.darkened(0.6))
			_loop(ci, _P(g, R, sh), gc, lw * 1.2)
			_quad(ci, g, R, -0.12, -0.52, 0.12, 0.38, gc)
			_quad(ci, g, R, -0.42, -0.19, 0.42, 0.05, gc)
		"aegis_a":
			var pu: float = 0.5 + 0.5 * sin(t * 2.0)
			_loop(ci, _ngon(g, R * 0.95, 6, PI / 6.0), gc, lw * 1.2)
			_loop(ci, _ngon(g, R * 0.66, 6, PI / 6.0), Color(gc, (0.5 + 0.4 * pu) * a), lw)
			ci.draw_colored_polygon(_ngon(g, R * 0.36, 6, PI / 6.0), gc)
		"optics":
			var lens := PackedVector2Array()
			for k in 13:
				var x: float = -1.0 + 2.0 * float(k) / 12.0
				lens.append(g + Vector2(x * 0.92, -0.55 * (1.0 - x * x)) * R)
			for k in range(11, 0, -1):
				var x2: float = -1.0 + 2.0 * float(k) / 12.0
				lens.append(g + Vector2(x2 * 0.92, 0.55 * (1.0 - x2 * x2)) * R)
			ci.draw_colored_polygon(lens, dark)
			_loop(ci, lens, gc, lw)
			ci.draw_circle(g, R * 0.34, gc)
			ci.draw_circle(g, R * 0.15, dark)
			ci.draw_circle(g + Vector2(-0.12, -0.12) * R, R * 0.07, hi)
		"rangefinder":
			_ring(ci, g, R * 0.75, gc, lw)
			for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				ci.draw_line(g + (d as Vector2) * R * 0.42, g + (d as Vector2) * R * 1.0, gc, lw)
			ci.draw_circle(g, R * 0.1, hi)
			var sw: float = t * 1.5
			ci.draw_arc(g, R * 0.75, sw, sw + 0.9, 10, Color(1, 1, 1, 0.75 * a), lw * 1.8, true)
		"treasury":
			var sq: PackedVector2Array = _chamfer(Rect2(g - Vector2(R, R) * 0.8, Vector2(R, R) * 1.6), R * 0.2)
			ci.draw_colored_polygon(sq, dark)
			_loop(ci, sq, gc, lw)
			_ring(ci, g, R * 0.48, gc, lw)
			for k in 6:
				var an: float = t * 0.3 + TAU * float(k) / 6.0
				ci.draw_line(g + Vector2(cos(an), sin(an)) * R * 0.14, g + Vector2(cos(an), sin(an)) * R * 0.48, Color(gc, 0.8 * a), lw * 0.8)
			ci.draw_circle(g, R * 0.14, gc)
		"training":
			for k in 3:
				var y: float = -0.5 + 0.48 * float(k)
				var lit: float = 0.45 + 0.55 * clampf(sin(t * 3.0 - float(k) * 0.9) * 0.5 + 0.5, 0.0, 1.0)
				ci.draw_polyline(_P(g, R, [Vector2(-0.62, y + 0.26), Vector2(0.0, y - 0.18), Vector2(0.62, y + 0.26)]), Color(gc, lit * a), R * 0.18, true)
		"shrine":
			var tw2: float = 0.85 + 0.15 * sin(t * 2.5)
			ci.draw_colored_polygon(_P(g, R * tw2, [Vector2(0, -0.95), Vector2(0.2, 0), Vector2(0, 0.95), Vector2(-0.2, 0)]), gc)
			ci.draw_colored_polygon(_P(g, R * tw2, [Vector2(-0.95, 0), Vector2(0, -0.2), Vector2(0.95, 0), Vector2(0, 0.2)]), gc)
			ci.draw_circle(g, R * 0.12, hi)
			for k in 3:
				var ph: float = 0.5 + 0.5 * sin(t * 3.0 + float(k) * 2.1)
				var pos: Vector2 = g + Vector2(cos(float(k) * 2.1 + 0.6), sin(float(k) * 2.1 + 0.6)) * R * 0.75
				_sparkle(ci, pos, R * 0.16 * ph, Color(1, 1, 1, ph * a))
		"forgeworks":
			_quad(ci, g, R, -0.85, -0.3, 0.85, -0.06, gc)
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.85, -0.3), Vector2(-1.0, -0.3), Vector2(-0.85, -0.12)]), gc)
			_quad(ci, g, R, -0.28, -0.06, 0.28, 0.36, gc.darkened(0.25))
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.38, 0.36), Vector2(0.38, 0.36), Vector2(0.62, 0.7), Vector2(-0.62, 0.7)]), gc.darkened(0.1))
			var sp: float = fposmod(t * 1.2, 1.0)
			for k in 4:
				var an: float = -PI * 0.5 + (float(k) - 1.5) * 0.45
				var d2 := Vector2(cos(an), sin(an))
				var o0: Vector2 = g + Vector2(0, -0.4) * R
				ci.draw_line(o0 + d2 * R * (0.15 + 0.35 * sp), o0 + d2 * R * (0.3 + 0.4 * sp), Color(Kit.GOLD, (1.0 - sp) * a), lw)
		"fabricator":
			# V3: an assembly arm swinging over a part on the bench
			_quad(ci, g, R, -0.85, 0.45, 0.85, 0.7, gc.darkened(0.35))
			_loop(ci, _P(g, R, [Vector2(-0.85, 0.45), Vector2(0.85, 0.45), Vector2(0.85, 0.7), Vector2(-0.85, 0.7)]), gc, lw)
			var sw: float = sin(t * 1.6) * 0.35
			var base_p: Vector2 = g + Vector2(-0.6, 0.45) * R
			var elbow: Vector2 = base_p + Vector2.from_angle(-PI * 0.5 + 0.5 + sw * 0.4) * R * 0.75
			var tip: Vector2 = elbow + Vector2.from_angle(0.35 + sw) * R * 0.6
			ci.draw_line(base_p, elbow, gc, lw * 1.4)
			ci.draw_line(elbow, tip, gc, lw * 1.2)
			ci.draw_circle(elbow, R * 0.08, hi)
			var part_c: Vector2 = g + Vector2(0.3, 0.25) * R
			_loop(ci, _P(part_c, R * 0.22, [Vector2(-1, -0.6), Vector2(1, -0.6), Vector2(1.2, 0.6), Vector2(-1.2, 0.6)]), Color(Kit.GOLD, a), lw)
			var sp2: float = 0.5 + 0.5 * sin(t * 6.0)
			_sparkle(ci, tip + Vector2(0, R * 0.08), R * 0.14 * sp2, Color(1, 1, 1, sp2 * a))
		"smelter":
			# V3: a crucible pouring molten Scrap
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.7, -0.45), Vector2(0.7, -0.45), Vector2(0.5, 0.45), Vector2(-0.5, 0.45)]), dark)
			_loop(ci, _P(g, R, [Vector2(-0.7, -0.45), Vector2(0.7, -0.45), Vector2(0.5, 0.45), Vector2(-0.5, 0.45)]), gc, lw)
			var glow: float = 0.6 + 0.4 * sin(t * 2.4)
			_quad(ci, g, R, -0.55, -0.4, 0.55, -0.18, Color(gc.lightened(0.2), glow * a))
			var dr: float = fposmod(t * 1.4, 1.0)
			ci.draw_line(g + Vector2(0.62, -0.42) * R, g + Vector2(0.78, 0.55) * R, Color(Kit.GOLD, 0.85 * a), lw * 1.2)
			ci.draw_circle(g + Vector2(0.78, 0.55 + 0.25 * dr) * R, R * 0.07 * (1.0 - dr), Color(Kit.GOLD, (1.0 - dr) * a))
			_quad(ci, g, R, 0.55, 0.62, 0.95, 0.82, gc.darkened(0.3))
			for k in 3:
				var fl: float = fposmod(t * 1.1 + float(k) * 0.33, 1.0)
				ci.draw_line(g + Vector2(-0.35 + 0.35 * float(k), 0.62) * R, g + Vector2(-0.35 + 0.35 * float(k), 0.62 - 0.2 * fl) * R, Color(gc, (1.0 - fl) * a), lw)
		"scav_post":
			ci.draw_line(g + Vector2(-0.25, 0.85) * R, g + Vector2(-0.25, 0.0) * R, gc, lw * 1.3)
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.6, 0.85), Vector2(0.1, 0.85), Vector2(-0.05, 0.6), Vector2(-0.45, 0.6)]), gc.darkened(0.2))
			ci.draw_arc(g + Vector2(-0.25, -0.05) * R, R * 0.48, PI * 0.25, PI * 1.25, 14, gc, lw * 1.3, true)
			for k in 3:
				var ph2: float = fposmod(t * 0.9 - float(k) * 0.33, 1.0)
				ci.draw_arc(g + Vector2(-0.25, -0.05) * R, R * (0.55 + 0.45 * float(k) * 0.5 + 0.2 * ph2), -PI * 0.5, 0.0, 10, Color(gc, (1.0 - ph2) * a), lw, true)
		"scav_den":
			_quad(ci, g, R, -0.78, -0.3, 0.78, 0.72, dark)
			_loop(ci, _P(g, R, [Vector2(-0.78, -0.3), Vector2(0.78, -0.3), Vector2(0.78, 0.72), Vector2(-0.78, 0.72)]), gc, lw)
			_quad(ci, g, R, -0.85, -0.68, 0.85, -0.3, gc.darkened(0.25))
			_quad(ci, g, R, -0.12, -0.42, 0.12, -0.1, Color(Kit.GOLD, a))
			var bm: float = 0.5 + 0.5 * sin(t * 2.2)
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.4, -0.7), Vector2(0.4, -0.7), Vector2(0.2, -1.0), Vector2(-0.2, -1.0)]), Color(gc, 0.35 * bm * a))
		"scav_deep":
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.52, -0.25), Vector2(0.52, -0.25), Vector2(0.0, 0.95)]), gc.darkened(0.45))
			_loop(ci, _P(g, R, [Vector2(-0.52, -0.25), Vector2(0.52, -0.25), Vector2(0.0, 0.95)]), gc, lw)
			for k in 3:
				var f: float = fposmod(float(k) / 3.0 + t * 0.7, 1.0)
				var y2: float = -0.25 + 1.2 * f
				var hw: float = 0.52 * (1.0 - f)
				ci.draw_line(g + Vector2(-hw, y2) * R, g + Vector2(hw * 0.6, y2 + 0.14) * R, Color(gc, a), lw * 0.8)
			_quad(ci, g, R, -0.68, -0.78, 0.68, -0.28, dark)
			_loop(ci, _P(g, R, [Vector2(-0.68, -0.78), Vector2(0.68, -0.78), Vector2(0.68, -0.28), Vector2(-0.68, -0.28)]), gc, lw)
			ci.draw_circle(g + Vector2(0, -0.53) * R, R * 0.1, Color(Kit.GOLD, a))
		"research":
			_quad(ci, g, R, -0.17, -0.85, 0.17, -0.32, dark)
			_loop(ci, _P(g, R, [Vector2(-0.17, -0.85), Vector2(0.17, -0.85), Vector2(0.17, -0.32), Vector2(-0.17, -0.32)]), gc, lw * 0.8)
			var fk: Array = [Vector2(-0.17, -0.32), Vector2(0.17, -0.32), Vector2(0.78, 0.78), Vector2(-0.78, 0.78)]
			ci.draw_colored_polygon(_P(g, R, fk), dark)
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.48, 0.22), Vector2(0.48, 0.22), Vector2(0.78, 0.78), Vector2(-0.78, 0.78)]), Color(gc, 0.85 * a))
			_loop(ci, _P(g, R, fk), gc, lw)
			for k in 3:
				var ph3: float = fposmod(t * 0.6 + float(k) * 0.37, 1.0)
				ci.draw_circle(g + Vector2(-0.25 + 0.25 * float(k), 0.6 - 0.9 * ph3) * R, R * 0.06 + R * 0.04 * ph3, Color(1, 1, 1, (1.0 - ph3) * 0.8 * a))
		"barracks":
			for k in 3:
				var x3: float = -0.58 + 0.58 * float(k)
				var big: float = 1.15 if k == 1 else 0.95
				var col: Color = gc if k == 1 else gc.darkened(0.25)
				ci.draw_circle(g + Vector2(x3, -0.35 * big) * R, R * 0.17 * big, col)
				ci.draw_colored_polygon(_P(g, R, [Vector2(x3 - 0.17 * big, 0.0), Vector2(x3 + 0.17 * big, 0.0), Vector2(x3 + 0.26 * big, 0.7), Vector2(x3 - 0.26 * big, 0.7)]), col)
		"archive":
			var hs: Array = [0.8, 0.62, 0.9, 0.7]
			for k in 4:
				var x4: float = -0.72 + 0.37 * float(k)
				var top: float = 0.7 - 1.4 * float(hs[k])
				_quad(ci, g, R, x4, top, x4 + 0.3, 0.7, gc if k % 2 == 0 else gc.darkened(0.35))
				_quad(ci, g, R, x4 + 0.04, top + 0.12, x4 + 0.26, top + 0.18, dark)
			_quad(ci, g, R, -0.85, 0.7, 0.85, 0.82, gc.lightened(0.2))
		"warehouse":
			for bx in [[-0.88, 0.0, -0.04, 0.82], [0.04, 0.0, 0.88, 0.82], [-0.42, -0.86, 0.42, -0.04]]:
				var q: Array = bx
				_quad(ci, g, R, q[0], q[1], q[2], q[3], gc.darkened(0.5))
				_loop(ci, _P(g, R, [Vector2(q[0], q[1]), Vector2(q[2], q[1]), Vector2(q[2], q[3]), Vector2(q[0], q[3])]), gc, lw * 0.8)
				var my: float = (float(q[1]) + float(q[3])) * 0.5
				ci.draw_line(g + Vector2(q[0], my) * R, g + Vector2(q[2], my) * R, Color(gc, 0.6 * a), lw * 0.7)
		"scrapyard":
			var hx: PackedVector2Array = _ngon(g, R * 0.85, 6, t * 0.4)
			ci.draw_colored_polygon(hx, gc.darkened(0.45))
			_loop(ci, hx, gc, lw)
			_ring(ci, g, R * 0.36, gc, lw)
			ci.draw_circle(g, R * 0.14, dark)
		"beaconpost":
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.38, 0.9), Vector2(0.38, 0.9), Vector2(0.0, -0.3)]), gc.darkened(0.35))
			var pb: float = 0.5 + 0.5 * sin(t * 4.0)
			Kit.glow(ci, g + Vector2(0, -0.45) * R, R * (0.6 + 0.3 * pb), gc, 0.7 * a)
			ci.draw_circle(g + Vector2(0, -0.45) * R, R * 0.2, gc.lightened(0.5))
			ci.draw_arc(g + Vector2(0, -0.45) * R, R * (0.5 + 0.2 * pb), -PI * 0.85, -PI * 0.15, 10, Color(gc, (1.0 - pb) * a), lw, true)
		"pylon":
			var dm: Array = [Vector2(0, -0.95), Vector2(0.5, 0), Vector2(0, 0.95), Vector2(-0.5, 0)]
			ci.draw_colored_polygon(_P(g, R, dm), dark)
			_loop(ci, _P(g, R, dm), gc, lw)
			var zz: float = 0.7 + 0.3 * sin(t * 6.0)
			ci.draw_polyline(_P(g, R, [Vector2(0.12, -0.55), Vector2(-0.14, 0.04), Vector2(0.14, 0.04), Vector2(-0.12, 0.58)]), Color(1, 1, 1, zz * a), lw, true)
		_:
			ci.draw_circle(g, R * 0.5, gc)


static func _sparkle(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	if r < 0.5:
		return
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.22, 0), c + Vector2(0, r), c + Vector2(-r * 0.22, 0)]), col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r, 0), c + Vector2(0, -r * 0.22), c + Vector2(r, 0), c + Vector2(0, r * 0.22)]), col)
