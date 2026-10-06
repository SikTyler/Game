extends RefCounted
## Loot beam / shimmer (P2 widget, used by P5 loot): a vertical light column
## in a rarity colour with a bright core, a ground ring and rising sparks.
## Static draw helpers called from inside a CanvasItem's _draw(); sparks are
## a pure function of (index, t), so a frame is reproducible.

const SPARKS: int = 7


## Draws a beam standing on `base`. `h` is the column height, `w` its width,
## `t` the animation clock (seconds), `power` 0..1 scales glow and sparks.
static func draw(ci: CanvasItem, base: Vector2, col: Color, h: float, w: float, t: float, power: float = 1.0) -> void:
	var pw: float = clampf(power, 0.0, 1.0)
	var flick: float = 0.85 + 0.15 * sin(t * 9.0)
	# outer haze: a wide column fading upward
	_column(ci, base, w * 1.8, h * 0.85, Color(col, 0.22 * pw * flick))
	# main column
	_column(ci, base, w, h, Color(col, 0.55 * flick))
	# white-hot core
	_column(ci, base, w * 0.28, h * 0.92, Color(1, 1, 1, 0.75 * flick))
	# ground ring
	var rr: float = w * (1.3 + 0.25 * sin(t * 4.0))
	ci.draw_arc(base, rr, 0.0, TAU, 28, Color(col, 0.7 * pw), 2.0)
	ci.draw_circle(base, w * 0.5, Color(col, 0.35))
	# rising sparks
	for k in int(round(SPARKS * pw)):
		var ph: float = fposmod(t * (0.45 + 0.07 * float(k)) + float(k) * 0.37, 1.0)
		var x: float = sin(float(k) * 12.9898 + t * 1.3) * w * 0.9
		var p: Vector2 = base + Vector2(x, -ph * h)
		ci.draw_circle(p, 1.5 + 1.5 * (1.0 - ph), Color(col.lightened(0.4), 0.9 * (1.0 - ph)))


## A column `cw` wide and `ch` tall, solid at the base and clear at the top.
static func _column(ci: CanvasItem, base: Vector2, cw: float, ch: float, col: Color) -> void:
	var hw: float = cw * 0.5
	var pts := PackedVector2Array([base + Vector2(-hw, 0), base + Vector2(hw, 0), base + Vector2(hw * 0.6, -ch), base + Vector2(-hw * 0.6, -ch)])
	var top := Color(col, 0.0)
	ci.draw_polygon(pts, PackedColorArray([col, col, top, top]))


## A soft vertical glint sweeping across `r` every `period` seconds (card
## shimmer): two gradient quads, clear at the edges and bright in the middle.
static func shimmer(ci: CanvasItem, r: Rect2, t: float, col: Color = Color(1, 1, 1, 0.16), period: float = 2.6) -> void:
	var ph: float = fposmod(t, period) / period
	var bw: float = minf(40.0, r.size.x * 0.2)
	var xm: float = lerpf(r.position.x - bw, r.end.x + bw, ph)
	var clear := Color(col, 0.0)
	_quad(ci, maxf(r.position.x, xm - bw), minf(r.end.x, xm), r, clear, col)
	_quad(ci, maxf(r.position.x, xm), minf(r.end.x, xm + bw), r, col, clear)


static func _quad(ci: CanvasItem, x0: float, x1: float, r: Rect2, c0: Color, c1: Color) -> void:
	if x1 - x0 < 1.0:
		return
	var pts := PackedVector2Array([Vector2(x0, r.position.y), Vector2(x1, r.position.y), Vector2(x1, r.end.y), Vector2(x0, r.end.y)])
	ci.draw_polygon(pts, PackedColorArray([c0, c1, c1, c0]))
