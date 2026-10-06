extends RefCounted
## Floating ability icons (owner feedback #1: no bottom bar): specials 1-4
## float over the bottom of the battlefield as round icons with a cooldown
## sweep and copy pips — no bar, no hotkey callouts, no side text. Cast = key or
## click; a targeted special (Orbital) arms the aim cursor first.

const PickDB := preload("res://data/PickDB.gd")
const Specials := preload("res://Specials.gd")
const Kit := preload("res://ui/Kit.gd")
const TuneRef := preload("res://Tune.gd")

const SLOT: float = 76.0
const GAP: float = 14.0


static func slot_rect(m, k: int) -> Rect2:
	var hr: Rect2 = m.hot_rect()
	var tot: float = 4.0 * SLOT + 3.0 * GAP
	return Rect2(hr.get_center().x - tot * 0.5 + float(k) * (SLOT + GAP), hr.position.y + (hr.size.y - SLOT) * 0.5 - 6.0, SLOT, SLOT)


static func build(m) -> void:
	var S = m.S
	for k in 4:
		var idx: int = k
		var r: Rect2 = slot_rect(m, k)
		var has: bool = k < S.specials.size()
		var tip: String = "Special slot %d — draft Special Attacks to fill it" % (k + 1)
		if has:
			var sd: Dictionary = S.specials[k]
			var d: Dictionary = PickDB.get_def(String(sd["id"]))
			tip = "%s  x%d\n%s\nCooldown %.0f s%s" % [String(d["name"]), int(sd["copies"]), String(d["desc"]), Specials.cooldown(String(sd["id"]), int(sd["copies"])), "\nTargeted: click the field after casting" if Specials.is_targeted(String(sd["id"])) else ""]
		Kit.hit(m, r, func() -> void: m.cast(idx), tip, "SPECIAL %d" % (k + 1), has, Kit.GEM)


static func draw(m) -> void:
	var S = m.S
	for k in 4:
		var r: Rect2 = slot_rect(m, k)
		var has: bool = k < S.specials.size()
		var armed: bool = m.aim_special == k
		var c: Vector2 = r.get_center()
		var rad: float = SLOT * 0.5
		m.draw_circle(c + Vector2(0, 4), rad, Color(0, 0, 0, 0.45))
		m.draw_circle(c, rad, Kit.BG2 if has else Color(Kit.BG2, 0.55))
		m.draw_arc(c, rad, 0, TAU, 48, Kit.GOLD if armed else (Kit.GEM if has else Color(Kit.EDGE, 0.6)), 4.0 if armed else 2.5)
		if not has:
			# V2 P9 audit: an empty slot reads as a socket (its key number), not missing art
			Kit.th(m, "%d" % (k + 1), c + Vector2(0, 7), 18, Color(Kit.DIM, 0.8), HORIZONTAL_ALIGNMENT_CENTER, SLOT)
		if has:
			var sd: Dictionary = S.specials[k]
			var id: String = String(sd["id"])
			Kit.icon(m, id, r.grow(-12))
			var cd: float = float(sd["cd"])
			if cd > 0.0:
				var full: float = maxf(0.1, Specials.cooldown(id, int(sd["copies"])))
				var frac: float = clampf(cd / full, 0.0, 1.0)
				var pts := PackedVector2Array([c])
				var steps: int = 32
				for j in steps + 1:
					var a: float = -PI * 0.5 + TAU * frac * float(j) / float(steps)
					pts.append(c + Vector2.from_angle(a) * (rad - 1.0))
				m.draw_colored_polygon(pts, Color(0, 0, 0, 0.62))
				Kit.t(m, "%d" % int(ceil(cd)), c + Vector2(0, 9), 24, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, SLOT)
			for j in int(sd["copies"]):
				m.draw_circle(c + Vector2(float(j) * 10.0 - float(int(sd["copies"]) - 1) * 5.0, rad + 8.0), 3.5, Kit.GOLD)


static func _next_draft(S) -> String:
	if S.draft.size() > 0:
		return "open now"
	var every: int = maxi(1, TuneRef.int_of("pc_draft_every", 2))
	for c in range(int(S.wave), int(S.wave) + 12):
		if c <= 3 or c % every == 0 or c % maxi(1, int(S.boss_every)) == 0:
			return "after wave %d%s" % [c, "  (Epic+)" if c % maxi(1, int(S.boss_every)) == 0 else ""]
	return "—"
