extends RefCounted
## Bottom hotbar of the run screen (REDESIGN_SPEC §5): specials 1-4 with the
## cooldown sweep, copies and key label, flanked by the field
## count (left) and the draft cadence (right). Cast = key or click; a targeted
## special (Orbital) arms the aim cursor first.

const PickDB := preload("res://data/PickDB.gd")
const Specials := preload("res://Specials.gd")
const Kit := preload("res://ui/Kit.gd")
const TuneRef := preload("res://Tune.gd")

const SLOT: float = 76.0
const GAP: float = 14.0


static func slot_rect(m, k: int) -> Rect2:
	var hr: Rect2 = m.hot_rect()
	var tot: float = 4.0 * SLOT + 3.0 * GAP
	return Rect2(hr.get_center().x - tot * 0.5 + float(k) * (SLOT + GAP), hr.position.y + (hr.size.y - SLOT) * 0.5, SLOT, SLOT)


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
			tip = "%s  x%d  [%s]\n%s\nCooldown %.0f s%s" % [String(d["name"]), int(sd["copies"]), Kit.hint(m, "hotbar_%d" % (k + 1)), String(d["desc"]), Specials.cooldown(String(sd["id"]), int(sd["copies"])), "\nTargeted: click the field after pressing" if Specials.is_targeted(String(sd["id"])) else ""]
		Kit.hit(m, r, func() -> void: m.cast(idx), tip, "SPECIAL %d" % (k + 1), has, Kit.GEM)


static func draw(m) -> void:
	var S = m.S
	var hr: Rect2 = m.hot_rect()
	m.draw_rect(hr, Kit.PANEL)
	m.draw_line(hr.position, Vector2(hr.end.x, hr.position.y), Kit.RUST, 2.0)
	for k in 4:
		var r: Rect2 = slot_rect(m, k)
		var has: bool = k < S.specials.size()
		var armed: bool = m.aim_special == k
		Kit.panel(m, r, Kit.GOLD if armed else (Kit.GEM if has else Kit.EDGE), Color("101418") if has else Color("181c22"), 3 if armed else 2)
		if has:
			var sd: Dictionary = S.specials[k]
			var id: String = String(sd["id"])
			Kit.icon(m, id, r.grow(-8))
			var cd: float = float(sd["cd"])
			if cd > 0.0:
				var full: float = maxf(0.1, Specials.cooldown(id, int(sd["copies"])))
				var frac: float = clampf(cd / full, 0.0, 1.0)
				var c: Vector2 = r.get_center()
				var pts := PackedVector2Array([c])
				var steps: int = 32
				for j in steps + 1:
					var a: float = -PI * 0.5 + TAU * frac * float(j) / float(steps)
					pts.append(c + Vector2.from_angle(a) * SLOT * 0.72)
				m.draw_set_transform(Vector2.ZERO)
				_clip_poly(m, pts, r)
				Kit.t(m, "%d" % int(ceil(cd)), c + Vector2(0, 9), 24, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, SLOT)
			for j in int(sd["copies"]):
				m.draw_circle(r.position + Vector2(r.size.x - 10 - j * 10, r.size.y - 9), 3.5, Kit.GOLD)
		else:
			Kit.t(m, "empty", r.get_center() + Vector2(0, 6), 14, Color(Kit.DIM, 0.6), HORIZONTAL_ALIGNMENT_CENTER, SLOT)
		Kit.panel(m, Rect2(r.position.x - 6, r.position.y - 8, 24, 22), Kit.EDGE, Color("0d1013"), 1)
		Kit.t(m, Kit.hint(m, "hotbar_%d" % (k + 1)), Vector2(r.position.x + 6, r.position.y + 9), 14, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 24.0)
	# left: field
	var lx: float = hr.position.x + 20.0
	var lw: float = slot_rect(m, 0).position.x - lx - 30.0
	Kit.t(m, "FIELD", Vector2(lx, hr.position.y + 30), 14, Kit.RUST, HORIZONTAL_ALIGNMENT_LEFT, lw)
	Kit.t(m, "%d enemies on the field  ·  %d kills" % [S.enemy_count(), int(S.kills)], Vector2(lx, hr.position.y + 78), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, lw)
	# right: draft cadence
	var rx: float = slot_rect(m, 3).end.x + 30.0
	var rw: float = hr.end.x - rx - 20.0
	Kit.t(m, "NEXT DRAFT", Vector2(rx, hr.position.y + 30), 14, Kit.RUST, HORIZONTAL_ALIGNMENT_LEFT, rw)
	Kit.t(m, _next_draft(S), Vector2(rx, hr.position.y + 54), 17, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, rw)
	Kit.t(m, "Banked rerolls %d  ·  banish %d" % [int(S.rerolls_left), int(S.banish_left)], Vector2(rx, hr.position.y + 78), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, rw)
	m.stat_tips.append([Rect2(rx, hr.position.y + 10, rw, 76), "Drafts arrive after waves 1, 2, 3, then every 2nd wave; boss waves add an Epic+ draft. XP level-ups bank free rerolls."])


static func _next_draft(S) -> String:
	if S.draft.size() > 0:
		return "open now"
	var every: int = maxi(1, TuneRef.int_of("pc_draft_every", 2))
	for c in range(int(S.wave), int(S.wave) + 12):
		if c <= 3 or c % every == 0 or c % maxi(1, int(S.boss_every)) == 0:
			return "after wave %d%s" % [c, "  (Epic+)" if c % maxi(1, int(S.boss_every)) == 0 else ""]
	return "—"


## Darken the un-recharged part of a slot (a pie wedge clipped to the slot).
static func _clip_poly(m, pts: PackedVector2Array, r: Rect2) -> void:
	var clipped: Array = Geometry2D.intersect_polygons(pts, PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]))
	for poly in clipped:
		m.draw_colored_polygon(poly as PackedVector2Array, Color(0, 0, 0, 0.62))
