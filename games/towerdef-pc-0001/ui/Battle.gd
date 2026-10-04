extends RefCounted
## Run screen (REDESIGN_SPEC §5 battlefield): centred field (Core + 7x7
## roguelite grid + troops + enemies + fx), left panel (draft / place / info,
## ui/DraftPanel.gd), right panel (Core portrait, HP, cash, stats and the 5
## cash tracks), bottom hotbar (specials 1-4, ui/Hotbar.gd) and the results
## modal. Every value is shown once. View only: reads TowerState, replays its
## events (core_attack, special_cast, troop_*), never decides outcomes.

const TowerState := preload("res://TowerState.gd")
const PickDB := preload("res://data/PickDB.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const PartDB := preload("res://data/PartDB.gd")
const Tiers := preload("res://Tiers.gd")
const Kit := preload("res://ui/Kit.gd")
const DraftPanel := preload("res://ui/DraftPanel.gd")
const Hotbar := preload("res://ui/Hotbar.gd")

const ENEMY2: Color = Color("e04bc0")
const SHIELD: Color = Color("7fd8ff")
const QUAD_NAMES: Array = ["North-east", "South-east", "South-west", "North-west"]
const TRACK_ICON: Dictionary = {"dmg": "pk_arsenal", "rate": "pk_overclock", "range": "pk_optics", "eco": "pk_ledger", "armor": "pk_fort"}
const TRACK_TIP: Dictionary = {
	"dmg": "Damage track: x1.08 Core and building damage per level",
	"rate": "Rate track: +3% Core attack rate per level",
	"range": "Range track: +0.1 cell Core range per level",
	"eco": "Eco track: +0.4 cash/s and +5 interest cap per level",
	"armor": "Armor track: +5% Core HP, +0.2 regen and +0.5 armor per level",
}


static func speed_str(v: float) -> String:
	return str(int(v)) if absf(v - roundf(v)) < 0.01 else "%.1f" % v


static func quad_dir(q: int) -> Vector2:
	return Vector2.from_angle(deg_to_rad(-67.5 + 90.0 * float(q)))


static func pick_name(id: String) -> String:
	return String(PickDB.get_def(id).get("name", id))


# ===================================================================== build
static func build(m) -> void:
	var S = m.S
	if S == null:
		return
	DraftPanel.build(m)
	Hotbar.build(m)
	var rr: Rect2 = m.right_rect()
	var x: float = rr.position.x + 16.0
	var w: float = rr.size.x - 32.0
	var ty: float = track_y(m)
	var th: float = track_h(m)
	for k in TowerState.TRACK_IDS.size():
		var tid: String = TowerState.TRACK_IDS[k]
		var c: int = S.track_cost(tid)
		var td: Dictionary = TowerState.TRACKS[tid]
		var tip: String = "%s\nLevel %d / %d  ·  next $%d  [%s]" % [String(TRACK_TIP[tid]), int(S.tracks[tid]), int(S.track_cap(tid)), maxi(0, c), Kit.hint(m, "track_%d" % (k + 1))]
		Kit.hit(m, Rect2(x, ty + k * (th + 6.0), w, th), func() -> void: m.buy_track(tid), tip, "TRACK " + String(td["name"]), c >= 0 and S.cash >= float(c), Kit.GREEN)
	if m.sel >= 0 and S.is_weapon_slot(m.sel) and m.sel != TowerState.CORE_SLOT:
		var lr: Rect2 = m.left_rect()
		var i: int = m.sel
		Kit.btn(m, "Target: %s" % String(S.target_modes[i]).capitalize(), Rect2(lr.position.x + 16, lr.end.y - 60, lr.size.x - 32, 46), func() -> void: m._handle(S.cycle_target_mode(i)); m._rebuild_ui(), "Cycle this weapon's targeting mode (nearest / first / strongest / weakest)", true, Kit.ENEMY, "Target:")


static func track_h(m) -> float:
	return clampf((m.vh - 1080.0) * 0.05 + 62.0, 50.0, 66.0)


static func track_y(m) -> float:
	var rr: Rect2 = m.right_rect()
	return rr.end.y - 5.0 * (track_h(m) + 6.0) - 46.0


static func build_results(m) -> void:
	var r: Rect2 = results_rect(m)
	var bw: float = (r.size.x - 72.0) * 0.5
	Kit.btn(m, "Back to base", Rect2(r.position.x + 24, r.end.y - 76, bw, 56), m.go_base, "Return to the hub to spend your loot", true, Kit.RUST, "DBACK", "", 22)
	Kit.btn(m, "Retry seed %d [%s]" % [int(m.last_seed), Kit.hint(m, "retry")], Rect2(r.position.x + 48 + bw, r.end.y - 76, bw, 56), func() -> void: m.start_run(m.last_seed), "Replay this exact run (same seed, tier and modifiers)", true, Kit.GEM, "RETRY SEED", "", 18)


static func results_rect(m) -> Rect2:
	var fr: Rect2 = m.field_rect()
	var w: float = minf(fr.size.x - 40.0, 780.0)
	var h: float = minf(fr.size.y - 40.0, 760.0)
	return Rect2(fr.get_center().x - w * 0.5, fr.get_center().y - h * 0.5, w, h)


## Why `id` cannot go on cell `i` right now ("" when it can).
static func place_reason(m, i: int, id: String) -> String:
	var S = m.S
	if i < 0:
		return "Not a cell"
	if i == TowerState.CORE_SLOT:
		return "The Core"
	if not bool(S.unlocked[i]):
		return "Ring %d is closed (buy Core tracks)" % TowerState.ring_of(i)
	if S.id_at(i) != "":
		return "Occupied"
	if not S.can_place(i, id):
		return "Ring 2+ only" if id == "railgun" else ("Build cap reached" if S.at_cap() else "Can't place here")
	return ""


# ====================================================================== fx
static func core_attack_fx(m, ev: Dictionary) -> void:
	var S = m.S
	if S == null:
		return
	var c: Vector2 = TowerState.CENTER
	var kind: String = String(ev.get("kind", "cannon"))
	var tg: Array = ev.get("targets", [])
	match kind:
		"pulse":
			var cw: Dictionary = (S.stats["weapons"] as Array).back()
			m._ring(c, float(cw.get("range", 200.0)), 0.35, Color("b48cff"))
		"beam":
			pass   # drawn continuously from S.beam_eid
		_:
			for eid in tg:
				var p: Variant = m.enemy_pos(int(eid))
				if p == null:
					continue
				var col: Color = Color("ffd36b") if kind == "cannon" else Color("ff8a3a")
				m._tracer(c, p as Vector2, col, 3.0 if kind == "cannon" else 5.0, 0.14)
				m._ring(p as Vector2, 22.0 if kind == "cannon" else 40.0, 0.25, col)


static func special_fx(m, ev: Dictionary) -> void:
	var c: Vector2 = TowerState.CENTER
	var id: String = String(ev.get("id", ""))
	match id:
		"sp_emp":
			m._ring(c, 420.0, 0.6, Color("5ad1f0"))
			m._ring(c, 260.0, 0.45, Color("5ad1f0"))
		"sp_repair":
			m.heal_flash = 0.6
		"sp_overdrive":
			m._ring(c, 80.0, 0.5, Kit.GOLD)
		"sp_magnet":
			m._pop(c + Vector2(0, -90), "CASH x2", 1.2, Kit.GREEN, 24)
		"sp_timewarp":
			m._ring(c, 460.0, 0.8, Color.WHITE)
	m._pop(c + Vector2(0, -120), pick_name(id).to_upper(), 1.0, Kit.GEM, 22)


# ================================================================ tooltips
static func world_tip(m, p: Vector2) -> String:
	var S = m.S
	if S == null:
		return ""
	var wp: Vector2 = m.s2w(p)
	var best: float = 22.0
	var found: Dictionary = {}
	for e in S.enemies:
		var ed: Dictionary = e
		var dd: float = (ed["pos"] as Vector2).distance_to(wp)
		if dd < maxf(best, float(ed["size"])):
			best = dd
			found = ed
	if not found.is_empty():
		return "%s\nHP %d / %d" % [String(found["kind"]).capitalize(), int(ceil(float(found["hp"]))), int(float(found["max_hp"]))]
	for t in S.troops:
		var td: Dictionary = t
		if String(td.get("state", "")) != "dead" and (td["pos"] as Vector2).distance_to(wp) < 14.0:
			return "%s (troop)\nHP %d / %d" % [String(td["kind"]).capitalize(), int(ceil(float(td["hp"]))), int(float(td["max_hp"]))]
	var i: int = m.slot_at(wp)
	if i >= 0:
		return cell_text(m, i)
	return ""


static func cell_text(m, i: int) -> String:
	var S = m.S
	var ring: int = TowerState.ring_of(i)
	if i == TowerState.CORE_SLOT:
		var cd: Dictionary = CoreDB.get_def(S.core_id)
		return "%s Core  Lv%d\n%s: %s\nTrait %s: %s" % [String(cd["name"]), int(S.core_lvl), String(cd["attack_name"]), String(cd["attack_desc"]), String(cd["trait_name"]), String(cd["trait_desc"])]
	if not bool(S.unlocked[i]):
		return "Closed cell (ring %d)\nOpens when your Core track levels total %d" % [ring, S.ring_threshold(ring)]
	var id: String = S.id_at(i)
	if id == "":
		return "Empty cell (ring %d)\nDraft a building and drop it here" % ring
	var d: Dictionary = PickDB.get_def(id)
	return "%s  Lv%d / %d  (%s)\n%s" % [String(d["name"]), S.lvl_at(i), PickDB.max_of(id), String(d["rarity"]).capitalize(), String(d["desc"])]


# ===================================================================== draw
static func draw(m, off: Vector2) -> void:
	var S = m.S
	var fr: Rect2 = m.field_rect()
	_draw_field_bg(m, fr)
	if S != null:
		m.draw_set_transform_matrix(Transform2D(0.0, off) * m.world_xform())
		_draw_grid(m)
		_draw_world(m)
		_draw_fx(m)
		m.draw_set_transform(Vector2.ZERO)
		_draw_lanes(m, fr)
		_draw_field_hud(m, fr)
	if m.flash > 0.0:
		m.draw_rect(fr, Color(0.9, 0.15, 0.2, m.flash * 0.35))
	if m.heal_flash > 0.0:
		m.draw_rect(fr, Color(0.4, 0.9, 0.4, m.heal_flash * 0.3))
	if S != null:
		DraftPanel.draw(m)
		_draw_right(m)
		Hotbar.draw(m)
		_draw_ghost(m)
	if m.screen == "results":
		_draw_results(m)


static func _draw_field_bg(m, fr: Rect2) -> void:
	m.draw_rect(fr, Color("12161b"))
	var gc := Color(1, 1, 1, 0.025)
	var x: float = fr.position.x
	while x <= fr.end.x:
		m.draw_line(Vector2(x, fr.position.y), Vector2(x, fr.end.y), gc, 1.0)
		x += 48.0
	var y: float = fr.position.y
	while y <= fr.end.y:
		m.draw_line(Vector2(fr.position.x, y), Vector2(fr.end.x, y), gc, 1.0)
		y += 48.0


static func _draw_grid(m) -> void:
	var S = m.S
	var C: Vector2 = TowerState.CENTER
	var c: float = TowerState.CELL
	# spawn ring + lane wedges
	m.draw_arc(C, TowerState.SPAWN_R, 0, TAU, 128, Color(1, 1, 1, 0.07), 2.0)
	for q in 4:
		var on: bool = S.active_quads.has(q)
		var dir: Vector2 = quad_dir(q)
		m.draw_line(C + dir * (3.6 * c), C + dir * TowerState.SPAWN_R, Color(Kit.ENEMY, 0.16 if on else 0.05), 26.0)
	var hs: float = float(TowerState.SIDE) * 0.5
	var plate := Rect2(C - Vector2(hs * c + 8, hs * c + 8), Vector2(2.0 * hs * c + 16, 2.0 * hs * c + 16))
	m.draw_rect(plate, Color("0d1014"))
	m.draw_rect(plate, Color(Kit.RUST, 0.55), false, 3.0)
	var placing: bool = S.pending_place != "" or m.drag_card >= 0
	for i in TowerState.N:
		var p: Vector2 = TowerState.slot_pos(i)
		var sc: float = 1.0
		if m.slot_pop.has(i):
			sc = 1.0 + 0.3 * float(m.slot_pop[i]) / 0.3
		var half: float = (c * 0.5 - 3.0) * sc
		var r := Rect2(p - Vector2(half, half), Vector2(half * 2, half * 2))
		if i == TowerState.CORE_SLOT:
			continue
		if not bool(S.unlocked[i]):
			m.draw_rect(r, Color("15191e"))
			m.draw_rect(r.grow(-6), Color(1, 1, 1, 0.025), false, 1.0)
			continue
		var id: String = S.id_at(i)
		if id == "":
			var oc := Color("3d4752")
			var fill := Color("1d232a")
			if placing and (S.pending_place == "" or S.can_place(i, S.pending_place)):
				# Floor the pulse so valid cells always read as "glowing".
				oc = Color(Kit.GREEN, 0.7 + 0.25 * sin(m.t_anim * 8.0))
				fill = Color("1d232a").lerp(Kit.GREEN, 0.12)
			m.draw_rect(r, fill)
			m.draw_rect(r, oc, false, 2.0)
		else:
			var rc: Color = Kit.rarity_col(PickDB.rarity_of(id))
			m.draw_rect(r, Color(rc, 0.12))
			if not Kit.icon(m, id, r.grow(2)):
				m.draw_rect(r.grow(-6), rc)
			var lv: int = S.lvl_at(i)
			for k in lv:
				m.draw_rect(Rect2(r.position + Vector2(4 + k * 7, r.size.y - 7), Vector2(5, 4)), Kit.GOLD)
		if i == m.sel:
			m.draw_rect(r.grow(4), Color(1, 1, 1, 0.9), false, 3.0)
	# ring outlines
	for ring in [1, 2]:
		var rh: float = (float(ring) + 0.5) * c + 2.0
		m.draw_rect(Rect2(C - Vector2(rh, rh), Vector2(rh * 2.0, rh * 2.0)), Color(Kit.RUST, 0.25 if ring == 1 else 0.15), false, 2.0)
	# Core
	var cw: Dictionary = (S.stats["weapons"] as Array).back() if (S.stats.get("weapons", []) as Array).size() > 0 else {}
	if m.sel == TowerState.CORE_SLOT or m.mouse_pos.distance_to(m.w2s(C)) < c * m.world_scale():
		m.draw_circle(C, float(cw.get("range", 200.0)), Color(Kit.GEM, 0.05))
		m.draw_arc(C, float(cw.get("range", 200.0)), 0, TAU, 96, Color(Kit.GEM, 0.5), 2.0)
	var pulse: float = 0.5 + 0.5 * sin(m.t_anim * 3.0)
	var cr: float = c * 0.78
	m.draw_circle(C, cr + 8.0 + 4.0 * pulse, Color(1, 1, 1, 0.06))
	if not Kit.icon(m, "core_" + String(S.core_id), Rect2(C - Vector2(cr, cr), Vector2(cr, cr) * 2.0)):
		m.draw_circle(C, cr, Kit.RUST)
	if float(S.shield) > 0.0:
		var smax: float = maxf(1.0, float(S.stats.get("shield_max", 1.0)))
		m.draw_arc(C, cr + 6.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(float(S.shield) / smax, 0.0, 1.0), 48, SHIELD, 3.0)


static func _draw_world(m) -> void:
	var S = m.S
	# walls
	for q in S.walls.keys():
		var wd: Dictionary = S.walls[q]
		if float(wd.get("hp", 0.0)) <= 0.0:
			continue
		var dir: Vector2 = quad_dir(int(q))
		var a: float = dir.angle()
		m.draw_arc(TowerState.CENTER, TowerState.STOP_R + 30.0, a - 0.35, a + 0.35, 16, Color(Kit.SCRAP, 0.4 + 0.5 * float(wd["hp"]) / maxf(1.0, float(wd["max"]))), 8.0)
	# Lance beam
	if S.core_id == "lance" and int(S.beam_eid) >= 0:
		var bp: Variant = m.enemy_pos(int(S.beam_eid))
		if bp != null:
			var ramp: float = clampf(float(S.beam_t) / 6.0, 0.0, 1.0)
			m.draw_line(TowerState.CENTER, bp as Vector2, Color(0.5, 0.95, 1.0, 0.25), 10.0 + 8.0 * ramp)
			m.draw_line(TowerState.CENTER, bp as Vector2, Color(0.85, 1.0, 1.0, 0.9), 2.0 + 3.0 * ramp)
	# pending Orbital Strikes
	for o in S.orbitals:
		var od: Dictionary = o
		var op: Vector2 = od["pos"]
		m.draw_arc(op, float(od["r"]), 0, TAU, 40, Color(Kit.GOLD, 0.8), 2.0)
		m.draw_circle(op, float(od["r"]) * (1.0 - clampf(float(od["t"]) / 0.8, 0.0, 1.0)), Color(Kit.GOLD, 0.18))
	# troops
	for t in S.troops:
		var td: Dictionary = t
		if String(td.get("state", "")) == "dead":
			continue
		var tp: Vector2 = td["pos"]
		var tk: String = String(td.get("kind", "rifleman"))
		var tr := Rect2(tp - Vector2(11, 11), Vector2(22, 22))
		if not Kit.icon(m, "troop_" + tk, tr):
			m.draw_circle(tp, 7.0, Kit.GREEN)
		var hf: float = float(td["hp"]) / maxf(1.0, float(td["max_hp"]))
		if hf < 1.0:
			m.draw_rect(Rect2(tp + Vector2(-9, 12), Vector2(18, 3)), Color(0, 0, 0, 0.6))
			m.draw_rect(Rect2(tp + Vector2(-9, 12), Vector2(18 * hf, 3)), Kit.GREEN)
	# enemies
	for e in S.enemies:
		var ed: Dictionary = e
		var p: Vector2 = ed["pos"]
		var s: float = float(ed["size"])
		var kind: String = ed["kind"]
		var col: Color = ENEMY2 if kind in ["skitter", "boss", "mite", "splitter"] else Kit.ENEMY
		var hitr := Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0)
		if not Kit.icon(m, kind, hitr):
			m.draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), col)
		if bool(ed.get("marked", false)):
			m.draw_arc(p, s * 1.3, 0, TAU, 24, Kit.GOLD, 2.0)
		if float(ed["slow_t"]) > 0.0:
			m.draw_arc(p, s * 0.9, 0, TAU, 20, Color("8fe3ff"), 2.0)
		var sh: int = int(ed.get("shield", 0))
		if sh > 0:
			if not Kit.icon(m, "elite_shield", hitr.grow(s * 0.3)):
				m.draw_arc(p, s * 1.2, 0, TAU, 24, SHIELD, 3.0)
		var ht: float = float(ed.get("hit_t", 0.0))
		if ht > 0.0:
			m.draw_circle(p, s * 0.75, Color(1, 1, 1, 0.7 * ht / TowerState.HIT_FLASH))
		var frac: float = float(ed["hp"]) / float(ed["max_hp"])
		if frac < 1.0:
			m.draw_rect(Rect2(p + Vector2(-s * 0.6, s * 0.85), Vector2(s * 1.2, 4)), Color(0, 0, 0, 0.6))
			m.draw_rect(Rect2(p + Vector2(-s * 0.6, s * 0.85), Vector2(s * 1.2 * frac, 4)), col.lightened(0.3))


static func _draw_fx(m) -> void:
	for bd in m.bolts.items:
		if float(bd["t"]) <= 0.0:
			continue
		var bp: Vector2 = (bd["a"] as Vector2).lerp(TowerState.CENTER, 1.0 - float(bd["t"]) / 0.25)
		if not Kit.icon(m, "bolt", Rect2(bp - Vector2(12, 12), Vector2(24, 24))):
			m.draw_circle(bp, 5.0, Kit.ENEMY)
	for fd in m.tracers.items:
		if float(fd["t"]) <= 0.0:
			continue
		var a: float = float(fd["t"]) / maxf(0.01, float(fd["life"]))
		var tc: Color = fd["color"]
		m.draw_line(fd["a"], fd["b"], Color(tc, 0.25 * a), float(fd["w"]) * 3.0)
		m.draw_line(fd["a"], fd["b"], Color(tc, a), float(fd["w"]))
	for fd2 in m.rings.items:
		if float(fd2["t"]) <= 0.0:
			continue
		var rc: Color = fd2["color"]
		var k: float = 1.0 - float(fd2["t"]) / maxf(0.01, float(fd2["life"]))
		m.draw_arc(fd2["pos"], float(fd2["r"]) * (0.3 + 0.7 * k), 0, TAU, 40, Color(rc, minf(1.0, float(fd2["t"]) * 4.0)), 3.0)
	if m.level_burst > 0.0:
		var k2: float = 1.0 - m.level_burst / 0.6
		m.draw_arc(TowerState.CENTER, 40.0 + 300.0 * k2, 0, TAU, 96, Color(Kit.GREEN, 1.0 - k2), 6.0)
	for dn in m.dmgnums.items:
		var dt: float = float(dn["t"])
		if dt <= 0.0:
			continue
		var age: float = float(dn["life"]) - dt
		var dsz: int = int(dn["size"])
		var pun: float = 1.0 + maxf(0.0, 0.12 - age) * 3.0
		var dc: Color = Color("fff2c0") if dsz >= 24 else Color(1, 1, 1)
		Kit.t(m, Kit.fmt(float(dn["amt"])), (dn["pos"] as Vector2) + Vector2(float(int(dn["eid"]) * 37 % 31) - 15.0, -18.0 - age * 50.0), int(float(dsz) * pun), Color(dc, minf(1.0, dt * 3.0)), HORIZONTAL_ALIGNMENT_CENTER, 120.0)
	for fd3 in m.pops.items:
		if float(fd3["t"]) <= 0.0:
			continue
		var pp: Vector2 = fd3["pos"]
		var lift: float = (1.0 - float(fd3["t"])) * 30.0
		var pc: Color = fd3["color"]
		Kit.t(m, String(fd3["text"]), pp - Vector2(0, lift), int(fd3["size"]), Color(pc, minf(1.0, float(fd3["t"]) * 2.5)), HORIZONTAL_ALIGNMENT_CENTER, 600.0)


## Lane telegraphs at the field edge + the incoming-wave banner (screen space).
static func _draw_lanes(m, fr: Rect2) -> void:
	var S = m.S
	var c: Vector2 = m.w2s(TowerState.CENTER)
	var tele: bool = not S.next_plan.is_empty()
	var quads: Array = (S.next_plan.get("quads", []) as Array) if tele else S.active_quads
	var counts: Dictionary = S.next_plan.get("counts", {}) if tele else S.wave_spawned
	var bd: int = int(S.next_plan.get("boss_dir", -1)) if tele else S.boss_dir
	var inner: Rect2 = fr.grow(-40.0)
	for q in range(4):
		var dir: Vector2 = quad_dir(q)
		var tx: float = (inner.end.x - c.x) / dir.x if dir.x > 0.0 else (inner.position.x - c.x) / dir.x
		var ty: float = (inner.end.y - c.y) / dir.y if dir.y > 0.0 else (inner.position.y - c.y) / dir.y
		var p: Vector2 = c + dir * minf(tx, ty)
		var on: bool = quads.has(q)
		var col: Color = (ENEMY2 if bd == q else Kit.ENEMY) if on else Color(1, 1, 1, 0.12)
		if on and tele:
			col = Color(col, 0.55 + 0.45 * sin(m.t_anim * 8.0))
		var tip: Vector2 = p - dir * 30.0
		var side: Vector2 = dir.orthogonal() * 18.0
		m.draw_colored_polygon(PackedVector2Array([tip, p + side, p - side]), col)
		if q == S.focus_quad:
			m.draw_arc(p, 28.0, 0, TAU, 32, Kit.GEM, 2.0)
		if on and (int(counts.get(q, 0)) > 0 or bd == q):
			Kit.t(m, "%d%s" % [int(counts.get(q, 0)), " BOSS" if bd == q else ""], p - dir * 54.0 + Vector2(0, 8), 18, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 120.0)
		m.stat_tips.append([Rect2(p - Vector2(30, 30), Vector2(60, 60)), "%s lane%s. %s/%s move the lane focus (Orbital auto-target)." % [String(QUAD_NAMES[q]), " — focused" if q == S.focus_quad else "", Kit.hint(m, "lane_prev"), Kit.hint(m, "lane_next")]])


## Field banners: incoming wave, placement / aim prompts, Insight fanfare.
static func _draw_field_hud(m, fr: Rect2) -> void:
	var S = m.S
	var cx: float = fr.get_center().x
	if not S.next_plan.is_empty():
		var quads: Array = S.next_plan.get("quads", [])
		var txt: String = "WAVE %d INCOMING  ·  %d lane%s%s" % [int(S.next_plan.get("wave", 0)), quads.size(), "" if quads.size() == 1 else "s", "  ·  BOSS" if int(S.next_plan.get("boss_dir", -1)) >= 0 else ""]
		Kit.panel(m, Rect2(cx - 230, fr.position.y + 12, 460, 40), Kit.ENEMY, Color(0.16, 0.06, 0.07, 0.9))
		Kit.t(m, txt, Vector2(cx, fr.position.y + 39), 18, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 440.0)
	var prompt: String = ""
	if m.aim_special >= 0 and m.aim_special < S.specials.size():
		prompt = "Click the field to drop %s  ·  %s again = auto-target  ·  right-click cancels" % [pick_name(String((S.specials[m.aim_special] as Dictionary)["id"])), Kit.hint(m, "hotbar_%d" % (m.aim_special + 1))]
		if fr.has_point(m.mouse_pos):
			var rr: float = 1.5 * TowerState.cpx() * m.world_scale()
			m.draw_arc(m.mouse_pos, rr, 0, TAU, 48, Kit.GOLD, 2.0)
			m.draw_circle(m.mouse_pos, rr, Color(Kit.GOLD, 0.1))
	elif S.pending_place != "":
		prompt = "Place %s: click a glowing cell  ·  %s cancels" % [pick_name(S.pending_place), Kit.hint(m, "cancel")]
	elif m.banish_mode:
		prompt = "Banish: click a draft card to remove it from this run"
	if prompt != "":
		var pw: float = minf(fr.size.x - 20.0, 24.0 + m.font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x)
		Kit.panel(m, Rect2(cx - pw * 0.5, fr.end.y - 54, pw, 40), Kit.GOLD, Color(0.14, 0.12, 0.06, 0.92))
		Kit.t(m, prompt, Vector2(cx, fr.end.y - 27), 17, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, pw - 16.0)
	if m.insight_t > 0.0:
		var a: float = clampf(m.insight_t, 0.0, 1.0)
		var s: float = 1.0 + maxf(0.0, m.insight_t - 2.0) * 0.6
		var r := Rect2(cx - 260 * s, fr.get_center().y - 230, 520 * s, 92)
		Kit.panel(m, r, Color(Kit.RARITY["insight"], a), Color(0.04, 0.12, 0.12, 0.92 * a), 3)
		Kit.icon(m, "insight", Rect2(r.position.x + 14, r.position.y + 10, 72, 72), Color(1, 1, 1, a))
		Kit.t(m, "INSIGHT FOUND", Vector2(r.position.x + 100, r.position.y + 38), 26, Color(Kit.RARITY["insight"], a), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 110)
		Kit.t(m, "%s — banked permanently at run end" % m.insight_name, Vector2(r.position.x + 100, r.position.y + 68), 17, Color(Kit.TEXT, a), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 110)


## Drag ghost for a draft card over the grid (green / red with the reason).
static func _draw_ghost(m) -> void:
	var S = m.S
	if m.drag_card < 0 or m.drag_card >= S.draft.size() or m.mouse_pos.distance_to(m.drag_start) <= 12.0:
		return
	var id: String = String((S.draft[m.drag_card] as Dictionary)["id"])
	var reason: String = "Drop on a cell"
	if m.field_rect().has_point(m.mouse_pos):
		var i: int = m.slot_at(m.s2w(m.mouse_pos))
		if i >= 0:
			reason = place_reason(m, i, id) if String((S.draft[m.drag_card] as Dictionary).get("kind", "")) == "new" else "Release to take this pick"
			var cs: float = TowerState.CELL * m.world_scale()
			var cp: Vector2 = m.w2s(TowerState.slot_pos(i))
			var cr := Rect2(cp - Vector2(cs, cs) * 0.5, Vector2(cs, cs))
			var ok: bool = reason == "" or reason.begins_with("Release")
			m.draw_rect(cr, Color(Kit.GREEN, 0.25) if ok else Color(Kit.ENEMY, 0.25))
			m.draw_rect(cr, Kit.GREEN if ok else Kit.ENEMY, false, 3.0)
	Kit.icon(m, id, Rect2(m.mouse_pos - Vector2(30, 30), Vector2(60, 60)), Color(1, 1, 1, 0.85))
	if reason != "":
		Kit.panel(m, Rect2(m.mouse_pos + Vector2(36, -16), Vector2(300, 34)), Kit.ENEMY, Color(0.1, 0.05, 0.05, 0.92))
		Kit.t(m, reason, m.mouse_pos + Vector2(48, 8), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 280.0)
	m.set_meta("ghost_reason", reason)


static func _draw_right(m) -> void:
	var S = m.S
	var rr: Rect2 = m.right_rect()
	m.draw_rect(rr, Kit.PANEL)
	m.draw_line(rr.position, Vector2(rr.position.x, rr.end.y), Kit.EDGE, 2.0)
	var x: float = rr.position.x + 16.0
	var w: float = rr.size.x - 32.0
	var y: float = rr.position.y + 14.0
	var cd: Dictionary = CoreDB.get_def(S.core_id)
	# portrait
	Kit.panel(m, Rect2(x, y, 96, 96), Kit.RUST, Color("12161b"))
	Kit.icon(m, "core_" + String(S.core_id), Rect2(x + 6, y + 6, 84, 84))
	Kit.t(m, "%s Core" % String(cd["name"]), Vector2(x + 110, y + 26), 22, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 110)
	Kit.t(m, "Lv %d  ·  %s" % [int(S.core_lvl), String(cd["arch"]).capitalize()], Vector2(x + 110, y + 50), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 110)
	Kit.t(m, String(cd["attack_name"]), Vector2(x + 110, y + 74), 16, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w - 110)
	m.stat_tips.append([Rect2(x, y, w, 96), "%s: %s\nTrait %s: %s" % [String(cd["attack_name"]), String(cd["attack_desc"]), String(cd["trait_name"]), String(cd["trait_desc"])]])
	y += 108.0
	# HP + shield
	var mhp: float = maxf(1.0, float(S.stats["max_hp"]))
	Kit.bar(m, Rect2(x, y, w, 24), float(S.hp) / mhp, Color("e8434f"))
	Kit.t(m, "HP %d / %d" % [clampi(int(ceil(float(S.hp))), 0, int(mhp)), int(mhp)], Vector2(x + w * 0.5, y + 19), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
	m.stat_tips.append([Rect2(x, y, w, 24), "Core HP. The run ends at 0."])
	y += 28.0
	var smax: float = float(S.stats.get("shield_max", 0.0))
	if smax > 0.0:
		Kit.bar(m, Rect2(x, y, w, 10), float(S.shield) / smax, SHIELD)
		m.stat_tips.append([Rect2(x, y - 2, w, 14), "Aegis shield %d / %d" % [int(S.shield), int(smax)]])
		y += 14.0
	# cash
	y += 34.0
	Kit.icon(m, "cur_cash", Rect2(x, y - 30, 36, 36))
	Kit.t(m, "$%s" % Kit.fmt(float(S.cash)), Vector2(x + 44, y), 30, Kit.GREEN, HORIZONTAL_ALIGNMENT_LEFT, w * 0.55)
	var st: Dictionary = S.stats
	Kit.t(m, "+%.1f/s" % float(st.get("cash_ps", 0.0)), Vector2(x + w, y - 12), 15, Kit.GREEN, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.4)
	Kit.t(m, "interest %d%% (cap %d)" % [int(round(float(st.get("interest_rate", 0.0)) * 100.0)), int(float(st.get("interest_cap", 0.0)))], Vector2(x + w, y + 6), 13, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5)
	m.stat_tips.append([Rect2(x, y - 34, w, 44), "Run cash: buys Core tracks and rerolls. Earned per second, per kill (x1.10 per wave) and as interest each wave on banked cash up to the cap."])
	y += 30.0
	# stats
	var cw: Dictionary = (st["weapons"] as Array).back()
	var rows: Array = [
		["Damage", Kit.fmt(float(cw.get("dmg", 0.0))), "Core damage per hit (all multipliers)"],
		["Attack rate", "%.2f/s" % float(cw.get("rate", 0.0)), "Core attacks per second"],
		["Range", "%.1f cells" % float(cw.get("range_cells", 0.0)), "Core attack range"],
		["Regen", "%.1f/s" % float(st.get("regen", 0.0)), "HP the Core regenerates per second"],
		["Armor", "%.1f" % float(st.get("armor", 0.0)), "Flat damage removed from each enemy hit"],
		["Base DPS", Kit.fmt(float(S.dps())), "Estimated damage per second of the Core and every building"],
		["Coins this run", Kit.fmt(float(S.coins_run)), "Coins banked when the run ends (x tier, x modifiers)"],
		["Crit chance", "%d%%" % int(round(minf(1.0, float(st.get("crit", 0.0)) + float(cw.get("crit", 0.0))) * 100.0)), "Chance a Core hit deals critical damage"],
		["Best wave", "%d" % int(m.save.get("best_wave", 0)), "Your best wave on any tier — beat it to push the frontier"],
	]
	var sh: float = clampf((track_y(m) - 74.0 - y) / float(rows.size()), 20.0, 30.0)
	for k in rows.size():
		var rw: Array = rows[k]
		Kit.row(m, String(rw[0]), String(rw[1]), Vector2(x, y + sh * float(k)), w, Kit.TEXT, String(rw[2]), 16)
	# tracks
	var ty: float = track_y(m)
	var th: float = track_h(m)
	var tot: int = S.track_total()
	var nxt: int = S.ring_threshold(S.rings_open + 1) if S.rings_open < 3 else 0
	Kit.head(m, "CORE TRACKS  (cash, this run)", Vector2(x, ty - 30), w)
	if nxt > 0:
		Kit.bar(m, Rect2(x, ty - 18, w, 8), float(tot) / float(nxt), Color(Kit.GREEN, 0.7))
		m.stat_tips.append([Rect2(x, ty - 22, w, 14), "Track levels total %d — ring %d of the grid opens at %d" % [tot, S.rings_open + 1, nxt]])
	for k in TowerState.TRACK_IDS.size():
		var tid: String = TowerState.TRACK_IDS[k]
		var td: Dictionary = TowerState.TRACKS[tid]
		var r := Rect2(x, ty + k * (th + 6.0), w, th)
		var c: int = S.track_cost(tid)
		var can: bool = c >= 0 and S.cash >= float(c)
		Kit.panel(m, r, Kit.GREEN if can else Kit.EDGE, Color("1a2a1e") if can else Color("1b2027"))
		Kit.icon(m, String(TRACK_ICON[tid]), Rect2(r.position.x + 8, r.position.y + (th - 36) * 0.5, 36, 36), Color.WHITE if can else Color(1, 1, 1, 0.5))
		Kit.t(m, "%s  Lv %d" % [String(td["name"]), int(S.tracks[tid])], Vector2(r.position.x + 52, r.position.y + th * 0.45), 18, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 150)
		Kit.t(m, String(td["desc"]), Vector2(r.position.x + 52, r.position.y + th * 0.45 + 18), 13, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 150)
		Kit.t(m, ("$%s" % Kit.fmt(float(c))) if c >= 0 else "MAX", Vector2(r.end.x - 34, r.position.y + th * 0.45), 18, Kit.GREEN if can else Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 100.0)
		Kit.panel(m, Rect2(r.end.x - 30, r.position.y + th * 0.5 - 2, 24, 22), Kit.EDGE, Color("101317"), 1)
		Kit.t(m, "%d" % (k + 1), Vector2(r.end.x - 18, r.position.y + th * 0.5 + 15), 13, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, 24.0)


static func _draw_results(m) -> void:
	m.draw_rect(m.field_rect(), Color(0, 0, 0, 0.55))
	var r: Rect2 = results_rect(m)
	Kit.panel(m, r, Kit.ENEMY, Color(0.09, 0.11, 0.14, 0.97), 3)
	var cx: float = r.get_center().x
	var lr: Dictionary = m.last_result
	Kit.t(m, "CORE DESTROYED", Vector2(cx, r.position.y + 58), 40, Kit.ENEMY, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	Kit.t(m, "Wave %d   ·   %d kills   ·   Tier %d" % [int(lr.get("wave", 0)), int(lr.get("kills", 0)), int(m.S.tier) if m.S != null else 1], Vector2(cx, r.position.y + 96), 20, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var bd: Dictionary = lr.get("breakdown", {})
	var x: float = r.position.x + 40.0
	var w: float = r.size.x * 0.5 - 60.0
	var y: float = r.position.y + 150.0
	Kit.head(m, "COINS", Vector2(x, y), w)
	var rows: Array = [
		["Wave coins", Kit.fmt(float(bd.get("wave", 0)))], ["Kill coins", Kit.fmt(float(bd.get("kills", 0)))],
		["Boss bounty", Kit.fmt(float(bd.get("boss", 0)))], ["Cash-out", Kit.fmt(float(bd.get("cashout", 0)))],
		["x Tier %d" % int(bd.get("tier", 1)), "x%.1f" % Tiers.coin_mult(int(bd.get("tier", 1)))],
		["x Bonuses", "x%.2f" % (float(bd.get("mult", 1.0)) / maxf(0.01, Tiers.coin_mult(int(bd.get("tier", 1)))))],
	]
	for k in rows.size():
		var rw: Array = rows[k]
		Kit.row(m, String(rw[0]), String(rw[1]), Vector2(x, y + 34 + k * 30.0), w, Kit.TEXT, "", 17)
	var yb: float = y + 34 + rows.size() * 30.0 + 20.0
	Kit.icon(m, "cur_coin", Rect2(x, yb - 4, 40, 40))
	Kit.t(m, "+%s coins" % Kit.fmt(float(lr.get("coins", 0))), Vector2(x + 48, yb + 28), 28, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w)
	if int(bd.get("gems", 0)) > 0:
		Kit.icon(m, "cur_gem", Rect2(x, yb + 46, 32, 32))
		Kit.t(m, "+%d gems" % int(bd.get("gems", 0)), Vector2(x + 44, yb + 70), 20, Kit.GEM, HORIZONTAL_ALIGNMENT_LEFT, w)
	Kit.t(m, "%d missions completed" % m.run_missions, Vector2(x, yb + 104), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
	# loot
	var lx: float = r.get_center().x + 20.0
	Kit.head(m, "LOOT", Vector2(lx, y), w)
	var ly: float = y + 24.0
	var any: bool = false
	for e in m.run_loot:
		var ev: Dictionary = e
		var et: String = String(ev["t"])
		if et == "loot_banked":
			var bits: Array = []
			if int(ev.get("scrap", 0)) > 0:
				bits.append("+%d Scrap" % int(ev["scrap"]))
			if int(ev.get("keys", 0)) > 0:
				bits.append("+%d Keys" % int(ev["keys"]))
			if int(ev.get("core_cores", 0)) > 0:
				bits.append("+%d Core Cores" % int(ev["core_cores"]))
			if not bits.is_empty():
				Kit.t(m, "  ·  ".join(bits), Vector2(lx, ly + 22), 17, Kit.SCRAP, HORIZONTAL_ALIGNMENT_LEFT, w)
				ly += 30.0
				any = true
			continue
		if ly > r.end.y - 130.0:
			break
		var icon_id: String = String(ev.get("id", ""))
		var label: String = ""
		var col: Color = Kit.TEXT
		match et:
			"part_new":
				label = "NEW  " + String(PartDB.get_def(icon_id).get("name", icon_id))
				col = Kit.rarity_col(PartDB.rarity_of(icon_id))
			"part_star":
				label = "%s  star %d" % [String(PartDB.get_def(icon_id).get("name", icon_id)), int(ev["stars"])]
				col = Kit.GOLD
			"part_dup_salvaged":
				label = "%s  -> %d Scrap" % [String(PartDB.get_def(icon_id).get("name", icon_id)), int(ev["scrap"])]
				col = Kit.SCRAP
			"insight_banked":
				label = "%s banked" % pick_name(icon_id)
				col = Kit.RARITY["insight"]
		if label == "":
			continue
		Kit.icon(m, icon_id, Rect2(lx, ly, 36, 36))
		Kit.t(m, label, Vector2(lx + 44, ly + 25), 17, col, HORIZONTAL_ALIGNMENT_LEFT, w - 44)
		ly += 42.0
		any = true
	if not any:
		Kit.t(m, "No parts this run — bosses, marked elites and Couriers drop them.", Vector2(lx, ly + 22), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
	Kit.t(m, "Spend loot in the Core Bay, Crates and Outpost", Vector2(cx, r.end.y - 96), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
