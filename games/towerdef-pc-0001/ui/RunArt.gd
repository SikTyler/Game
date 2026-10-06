extends RefCounted
## Procedural neon icons for run content without a texture (V2 P7d): the new
## weapons, support / eco buildings, troop huts, specials, stat packs and
## gold perks. Kit.icon falls back here when ArtDB has no texture for an id
## this table (or its prefix rule) knows. A dark rounded tile, a neon rim in
## the id's colour and a glyph drawn from primitives.
##   draw(ci, id, r, mod) -> bool (false = unknown id, nothing drawn)

## id -> [glyph, colour]
const GLYPH: Dictionary = {
	# weapons (P7d)
	"pulse": ["rings", "39e6ff"], "missile": ["missile", "ff9b3d"], "spike": ["spikes", "e8c48f"], "mines": ["mine", "ff4d6d"],
	"scatter": ["pellets", "ffd34d"], "laser": ["beam", "ff3ea5"], "saw": ["saw", "e8f0ff"], "arcproj": ["bolt", "8fb8ff"],
	"sonic": ["wave", "a78bfa"], "harpoon": ["hook", "4ade80"], "plasma": ["fence", "ff5fb8"], "flakburst": ["burst", "ffb347"],
	# support / eco (P7d)
	"amp": ["chevrons", "ff4d6d"], "ocrelay": ["gear", "ff9b3d"], "uplink": ["eye", "39e6ff"], "critlens": ["lens", "ff5fb8"],
	"coolant": ["snow", "9fe0ff"], "ammodepot": ["box", "e8c48f"], "lure": ["target", "ff3ea5"], "shieldpylon": ["shield", "6e9bff"],
	"bank": ["bank", "ffd34d"], "capacitor": ["battery", "a3e635"], "market": ["coin", "ffd34d"], "xpsiphon": ["drop", "39e6ff"],
	"magnet": ["magnet", "ff4d6d"], "salvager": ["gear", "d9b98a"], "totem": ["star", "c084fc"], "slots": ["slot", "ffd34d"],
	"gate": ["spikes", "ff4d6d"], "watchtower": ["eye", "4ade80"], "medbay": ["cross", "4ade80"], "taxoffice": ["coin", "a3e635"],
	"insurance": ["shield", "ffd34d"], "forge": ["chevrons", "ff9b3d"],
	# troop huts (P7d)
	"hut_sniper": ["target", "4ade80"], "hut_guard": ["shield", "6e9bff"], "hut_medic": ["cross", "4ade80"], "hut_engineer": ["gear", "ffd34d"],
	# specials (P7d)
	"sp_nuke": ["burst", "ff4d6d"], "sp_shield": ["shield", "39e6ff"], "sp_frenzy": ["chevrons", "ff9b3d"], "sp_blackhole": ["rings", "a78bfa"],
	"sp_meteor": ["missile", "ff9b3d"], "sp_jackpot": ["slot", "ffd34d"],
}
## Prefix rules for families with many ids (packs / gold perks / evolutions).
const PREFIX: Array = [["pk_", "chevrons", "e8c26a"], ["perk_", "star", "ffd34d"], ["evo_", "star", "ffd34d"], ["dr_", "rings", "ff3ea5"]]


static func knows(id: String) -> bool:
	if GLYPH.has(id):
		return true
	for p in PREFIX:
		if id.begins_with(String((p as Array)[0])):
			return true
	return false


static func _spec(id: String) -> Array:
	if GLYPH.has(id):
		return GLYPH[id]
	for p in PREFIX:
		if id.begins_with(String((p as Array)[0])):
			return [String((p as Array)[1]), String((p as Array)[2])]
	return ["rings", "8a9bbd"]


static func draw(ci: CanvasItem, id: String, r: Rect2, mod: Color = Color.WHITE) -> bool:
	if not knows(id):
		return false
	var sp: Array = _spec(id)
	var col: Color = Color(String(sp[1])) * mod
	col.a = mod.a
	var a: float = mod.a
	var s: float = minf(r.size.x, r.size.y)
	var sq := Rect2(r.get_center() - Vector2(s, s) * 0.5, Vector2(s, s))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.13, 0.92 * a)
	sb.border_color = Color(col, 0.85 * a)
	sb.set_border_width_all(maxi(1, int(s * 0.04)))
	sb.set_corner_radius_all(int(s * 0.18))
	ci.draw_style_box(sb, sq.grow(-s * 0.04))
	var g: Vector2 = sq.get_center()
	var R: float = s * 0.30
	_glyph(ci, String(sp[0]), g, R, col, a, hash(id))
	return true


static func _P(g: Vector2, R: float, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(g + (p as Vector2) * R)
	return out


static func _glyph(ci: CanvasItem, kind: String, g: Vector2, R: float, col: Color, a: float, seed_v: int) -> void:
	var lw: float = maxf(1.5, R * 0.16)
	var dark := Color(0.05, 0.07, 0.13, a)
	var hi := Color(1, 1, 1, 0.8 * a)
	match kind:
		"rings":
			for k in 3:
				ci.draw_arc(g, R * (0.35 + 0.32 * float(k)), 0.0, TAU, 32, Color(col, a * (1.0 - 0.25 * float(k))), lw, true)
			ci.draw_circle(g, R * 0.16, col)
		"missile":
			var body: Array = [Vector2(-0.18, 0.7), Vector2(-0.18, -0.35), Vector2(0.0, -0.85), Vector2(0.18, -0.35), Vector2(0.18, 0.7)]
			ci.draw_colored_polygon(_P(g, R, body), col)
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.18, 0.3), Vector2(-0.48, 0.75), Vector2(-0.18, 0.7)]), col.darkened(0.3))
			ci.draw_colored_polygon(_P(g, R, [Vector2(0.18, 0.3), Vector2(0.48, 0.75), Vector2(0.18, 0.7)]), col.darkened(0.3))
			ci.draw_circle(g + Vector2(0, 0.95) * R, R * 0.14, Color(1.0, 0.85, 0.3, a))
		"spikes":
			for k in 5:
				var x: float = -0.8 + 0.4 * float(k)
				ci.draw_colored_polygon(_P(g, R, [Vector2(x - 0.17, 0.7), Vector2(x, -0.75), Vector2(x + 0.17, 0.7)]), col if k % 2 == 0 else col.darkened(0.25))
		"mine":
			ci.draw_circle(g, R * 0.55, col.darkened(0.2))
			for k in 8:
				var an: float = TAU * float(k) / 8.0
				ci.draw_line(g + Vector2(cos(an), sin(an)) * R * 0.5, g + Vector2(cos(an), sin(an)) * R * 0.9, col, lw)
			ci.draw_circle(g, R * 0.18, hi)
		"pellets":
			for k in 6:
				var an2: float = -PI * 0.5 + (float(k) - 2.5) * 0.28
				var d: float = 0.45 + 0.4 * float((seed_v >> k) & 1)
				ci.draw_circle(g + Vector2(cos(an2), sin(an2)) * R * d + Vector2(0, 0.55) * R, R * 0.13, col)
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.2, 0.9), Vector2(0.2, 0.9), Vector2(0.12, 0.45), Vector2(-0.12, 0.45)]), col.darkened(0.3))
		"beam":
			ci.draw_line(g + Vector2(-0.9, 0.6) * R, g + Vector2(0.9, -0.6) * R, Color(col, 0.35 * a), lw * 3.0)
			ci.draw_line(g + Vector2(-0.9, 0.6) * R, g + Vector2(0.9, -0.6) * R, col, lw * 1.2)
			ci.draw_line(g + Vector2(-0.9, 0.6) * R, g + Vector2(0.9, -0.6) * R, hi, lw * 0.4)
		"saw":
			var pts := PackedVector2Array()
			for k in 16:
				var an3: float = TAU * float(k) / 16.0
				pts.append(g + Vector2(cos(an3), sin(an3)) * R * (0.9 if k % 2 == 0 else 0.65))
			ci.draw_colored_polygon(pts, col)
			ci.draw_circle(g, R * 0.25, dark)
		"bolt":
			ci.draw_colored_polygon(_P(g, R, [Vector2(0.15, -0.95), Vector2(-0.5, 0.1), Vector2(-0.05, 0.1), Vector2(-0.2, 0.95), Vector2(0.5, -0.15), Vector2(0.05, -0.15)]), col)
		"wave":
			for k in 3:
				ci.draw_arc(g + Vector2(-0.6, 0) * R, R * (0.45 + 0.35 * float(k)), -0.7, 0.7, 12, Color(col, a * (1.0 - 0.25 * float(k))), lw, true)
		"hook":
			ci.draw_line(g + Vector2(0, -0.9) * R, g + Vector2(0, 0.3) * R, col, lw * 1.2)
			ci.draw_arc(g + Vector2(-0.3, 0.3) * R, R * 0.3, 0.0, PI, 12, col, lw * 1.2, true)
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.6, 0.3), Vector2(-0.75, 0.0), Vector2(-0.45, 0.15)]), col)
		"fence":
			for k in 3:
				var x2: float = -0.6 + 0.6 * float(k)
				ci.draw_line(g + Vector2(x2, -0.8) * R, g + Vector2(x2, 0.8) * R, col, lw)
			for y in [-0.35, 0.35]:
				ci.draw_line(g + Vector2(-0.8, y) * R, g + Vector2(0.8, y) * R, Color(1, 1, 1, 0.7 * a), lw * 0.6)
		"burst":
			for k in 10:
				var an4: float = TAU * float(k) / 10.0
				ci.draw_line(g + Vector2(cos(an4), sin(an4)) * R * 0.25, g + Vector2(cos(an4), sin(an4)) * R * (0.95 if k % 2 == 0 else 0.6), col, lw)
			ci.draw_circle(g, R * 0.25, hi)
		"chevrons":
			for k in 3:
				var y2: float = 0.55 - 0.5 * float(k)
				ci.draw_polyline(_P(g, R, [Vector2(-0.65, y2 + 0.25), Vector2(0.0, y2 - 0.2), Vector2(0.65, y2 + 0.25)]), col, lw * 1.3, true)
		"gear":
			for k in 8:
				var an5: float = TAU * float(k) / 8.0
				var dv := Vector2(cos(an5), sin(an5))
				ci.draw_line(g + dv * R * 0.6, g + dv * R * 0.92, col, lw * 1.6)
			ci.draw_circle(g, R * 0.62, col)
			ci.draw_circle(g, R * 0.28, dark)
		"eye":
			var lens := PackedVector2Array()
			for k in 13:
				var x3: float = -1.0 + 2.0 * float(k) / 12.0
				lens.append(g + Vector2(x3 * 0.9, -0.5 * (1.0 - x3 * x3)) * R)
			for k in range(11, 0, -1):
				var x4: float = -1.0 + 2.0 * float(k) / 12.0
				lens.append(g + Vector2(x4 * 0.9, 0.5 * (1.0 - x4 * x4)) * R)
			ci.draw_colored_polygon(lens, dark)
			ci.draw_polyline(lens + PackedVector2Array([lens[0]]), col, lw * 0.8, true)
			ci.draw_circle(g, R * 0.3, col)
		"lens":
			ci.draw_arc(g, R * 0.7, 0.0, TAU, 32, col, lw, true)
			ci.draw_line(g + Vector2(0.5, 0.5) * R, g + Vector2(0.95, 0.95) * R, col, lw * 1.5)
			ci.draw_circle(g + Vector2(-0.2, -0.2) * R, R * 0.12, hi)
		"snow":
			for k in 3:
				var an6: float = PI * float(k) / 3.0
				var dv2 := Vector2(cos(an6), sin(an6))
				ci.draw_line(g - dv2 * R * 0.85, g + dv2 * R * 0.85, col, lw)
		"box":
			ci.draw_rect(Rect2(g - Vector2(0.7, 0.55) * R, Vector2(1.4, 1.1) * R), col.darkened(0.35))
			ci.draw_rect(Rect2(g - Vector2(0.7, 0.55) * R, Vector2(1.4, 1.1) * R), col, false, lw)
			ci.draw_line(g + Vector2(-0.7, -0.1) * R, g + Vector2(0.7, -0.1) * R, col, lw * 0.8)
		"target":
			ci.draw_arc(g, R * 0.8, 0.0, TAU, 32, col, lw, true)
			ci.draw_arc(g, R * 0.45, 0.0, TAU, 24, col, lw, true)
			ci.draw_circle(g, R * 0.14, hi)
		"shield":
			var sh: Array = [Vector2(-0.7, -0.75), Vector2(0.7, -0.75), Vector2(0.7, 0.05), Vector2(0.0, 0.9), Vector2(-0.7, 0.05)]
			ci.draw_colored_polygon(_P(g, R, sh), col.darkened(0.45))
			ci.draw_polyline(_P(g, R, sh + [sh[0]]), col, lw, true)
		"bank":
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.85, -0.3), Vector2(0.0, -0.85), Vector2(0.85, -0.3)]), col)
			for k in 3:
				var x5: float = -0.55 + 0.55 * float(k)
				ci.draw_rect(Rect2(g + Vector2(x5 - 0.1, -0.2) * R, Vector2(0.2, 0.8) * R), col.darkened(0.15))
			ci.draw_rect(Rect2(g + Vector2(-0.85, 0.65) * R, Vector2(1.7, 0.18) * R), col)
		"battery":
			ci.draw_rect(Rect2(g + Vector2(-0.45, -0.7) * R, Vector2(0.9, 1.5) * R), col, false, lw)
			ci.draw_rect(Rect2(g + Vector2(-0.18, -0.88) * R, Vector2(0.36, 0.18) * R), col)
			for k in 3:
				ci.draw_rect(Rect2(g + Vector2(-0.3, 0.38 - 0.38 * float(k)) * R, Vector2(0.6, 0.26) * R), col)
		"coin":
			ci.draw_circle(g, R * 0.8, col)
			ci.draw_arc(g, R * 0.6, 0.0, TAU, 28, dark, lw * 0.8, true)
			ci.draw_rect(Rect2(g + Vector2(-0.08, -0.4) * R, Vector2(0.16, 0.8) * R), dark)
		"drop":
			var dp: Array = [Vector2(0, -0.9), Vector2(0.55, 0.15), Vector2(0.45, 0.55), Vector2(0, 0.8), Vector2(-0.45, 0.55), Vector2(-0.55, 0.15)]
			ci.draw_colored_polygon(_P(g, R, dp), col)
			ci.draw_circle(g + Vector2(-0.15, 0.2) * R, R * 0.12, hi)
		"magnet":
			ci.draw_arc(g + Vector2(0, -0.05) * R, R * 0.55, 0.0, PI, 16, col, lw * 2.2, false)
			ci.draw_line(g + Vector2(-0.55, -0.05) * R, g + Vector2(-0.55, -0.75) * R, col, lw * 2.2)
			ci.draw_line(g + Vector2(0.55, -0.05) * R, g + Vector2(0.55, -0.75) * R, col, lw * 2.2)
			ci.draw_line(g + Vector2(-0.55, -0.55) * R, g + Vector2(-0.55, -0.8) * R, hi, lw * 2.2)
			ci.draw_line(g + Vector2(0.55, -0.55) * R, g + Vector2(0.55, -0.8) * R, hi, lw * 2.2)
		"star":
			ci.draw_colored_polygon(_P(g, R, [Vector2(0, -0.95), Vector2(0.22, 0), Vector2(0, 0.95), Vector2(-0.22, 0)]), col)
			ci.draw_colored_polygon(_P(g, R, [Vector2(-0.95, 0), Vector2(0, -0.22), Vector2(0.95, 0), Vector2(0, 0.22)]), col)
			ci.draw_circle(g, R * 0.14, hi)
		"slot":
			ci.draw_rect(Rect2(g + Vector2(-0.85, -0.55) * R, Vector2(1.7, 1.1) * R), col.darkened(0.5))
			ci.draw_rect(Rect2(g + Vector2(-0.85, -0.55) * R, Vector2(1.7, 1.1) * R), col, false, lw)
			for k in 3:
				ci.draw_circle(g + Vector2(-0.52 + 0.52 * float(k), 0.0) * R, R * 0.18, col)
		"cross":
			ci.draw_rect(Rect2(g + Vector2(-0.22, -0.75) * R, Vector2(0.44, 1.5) * R), col)
			ci.draw_rect(Rect2(g + Vector2(-0.75, -0.22) * R, Vector2(1.5, 0.44) * R), col)
		_:
			ci.draw_circle(g, R * 0.5, col)
