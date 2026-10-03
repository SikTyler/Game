extends RefCounted
## Run screen drawing for Main.gd (arena world, synergy links, run HUD and the
## death / results breakdown). View only: reads TowerState + save, never
## mutates them. `m` is the Main node (untyped: Main has no class_name and a
## preload here would be cyclic). Called only from inside Main._draw().

const TowerState := preload("res://TowerState.gd")
const BuildingDB := preload("res://data/BuildingDB.gd")
const TuneRef := preload("res://Tune.gd")
const Tiers := preload("res://Tiers.gd")

const PANEL: Color = Color("232a33")
const RUST: Color = Color("d9773a")
const ENEMY: Color = Color("e8434f")
const ENEMY2: Color = Color("e04bc0")
const TEXT: Color = Color("e9edf2")
const DIM: Color = Color("9aa6b2")
const GOLD: Color = Color("f2c94c")
const GEM: Color = Color("5ad1f0")
const SHIELD: Color = Color("7fd8ff")
const W: float = 720.0
const H: float = 1280.0
const ARENA_BOTTOM: float = 860.0
const LINK_COLORS: Dictionary = {"S1": Color("f2a93b"), "S2": Color("b48cff"), "S3": Color("6bd46b"), "S4": Color("3fd8e8"), "S5": Color("ff8a5c"), "S6": Color("ffd166"), "S7": Color("e07a5f")}


## Synergy links (TowerState.compute_stats().links): flowing dots src -> dst.
static func draw_links(m) -> void:
	var links: Array = m.S.stats.get("links", [])
	for l in links:
		var la: Array = l
		var a: Vector2 = TowerState.slot_pos(int(la[0]))
		var b: Vector2 = TowerState.slot_pos(int(la[1]))
		var col: Color = LINK_COLORS.get(String(la[2]), Color.WHITE)
		m.draw_line(a, b, Color(col, 0.35), 6.0)
		m.draw_line(a, b, Color(col, 0.85), 2.0)
		var f: float = fmod(m.t_anim * 1.2 + float(int(la[0]) * 7 % 10) * 0.1, 1.0)
		m.draw_circle(a.lerp(b, f), 4.0, col.lightened(0.4))


static func draw_world(m) -> void:
	for e in m.S.enemies:
		var ed: Dictionary = e
		var p: Vector2 = ed["pos"]
		var s: float = float(ed["size"])
		var kind: String = ed["kind"]
		var col: Color = ENEMY2 if kind in ["skitter", "boss", "mite", "splitter"] else ENEMY
		var hit: Rect2 = Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0)
		if not m._icon(kind, hit):
			m.draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), col)
		if float(ed["slow_t"]) > 0.0:
			m.draw_arc(p, s * 0.9, 0, TAU, 20, Color("b48cff"), 2.0)
		var sh: int = int(ed.get("shield", 0))
		if sh > 0:
			if not m._icon("elite_shield", hit.grow(s * 0.3)):
				m.draw_arc(p, s * 1.2, 0, TAU, 24, SHIELD, 3.0)
			for k in mini(sh, 8):
				m.draw_circle(p + Vector2((float(k) - float(mini(sh, 8) - 1) * 0.5) * 9.0, -s - 10.0), 3.5, SHIELD)
		var frac: float = float(ed["hp"]) / float(ed["max_hp"])
		if frac < 1.0:
			m.draw_rect(Rect2(p + Vector2(-s * 0.6, s * 0.85), Vector2(s * 1.2, 4)), Color(0, 0, 0, 0.6))
			m.draw_rect(Rect2(p + Vector2(-s * 0.6, s * 0.85), Vector2(s * 1.2 * frac, 4)), col.lightened(0.3))
	for f in m.bolts:
		var bd: Dictionary = f
		var bp: Vector2 = (bd["a"] as Vector2).lerp(TowerState.CENTER, 1.0 - float(bd["t"]) / 0.25)
		if not m._icon("bolt", Rect2(bp - Vector2(12, 12), Vector2(24, 24))):
			m.draw_circle(bp, 5.0, ENEMY)
	for f in m.tracers:
		var fd: Dictionary = f
		var a: float = float(fd["t"]) / 0.12
		var tc: Color = fd["color"]
		m.draw_line(fd["a"], fd["b"], Color(tc, 0.25 * a), float(fd["w"]) * 3.0)
		m.draw_line(fd["a"], fd["b"], Color(tc, a), float(fd["w"]))
	for f in m.rings:
		var fd2: Dictionary = f
		var rc: Color = fd2["color"]
		m.draw_arc(fd2["pos"], float(fd2["r"]) * (1.3 - float(fd2["t"])), 0, TAU, 32, Color(rc, minf(1.0, float(fd2["t"]) * 4.0)), 3.0)
	if m.level_burst > 0.0:
		var k2: float = 1.0 - m.level_burst / 0.6
		m.draw_arc(TowerState.CENTER, 40.0 + 420.0 * k2, 0, TAU, 96, Color(BuildingDB.cat_color("eco"), 1.0 - k2), 8.0)
	for f in m.pops:
		var fd3: Dictionary = f
		var pp: Vector2 = fd3["pos"]
		var lift: float = (1.0 - float(fd3["t"])) * 30.0
		var pc: Color = fd3["color"]
		m._text(String(fd3["text"]), pp - Vector2(0, lift), int(fd3["size"]), Color(pc, minf(1.0, float(fd3["t"]) * 2.5)))


## Icon + number counter; falls back to a coloured dot.


static func draw_hud(m) -> void:
	m.draw_rect(Rect2(0, ARENA_BOTTOM + 30, W, H - ARENA_BOTTOM - 30), PANEL)
	m.draw_line(Vector2(0, ARENA_BOTTOM + 30), Vector2(W, ARENA_BOTTOM + 30), RUST, 3.0)
	if m.S == null:
		return
	# top HUD
	m.draw_rect(Rect2(0, 0, W, 190), Color(0.08, 0.1, 0.12, 0.55))
	m._text("WAVE %d" % m.S.wave, Vector2(360, 48), 40, TEXT)
	m._text("T%d" % m.S.tier, Vector2(470, 44), 20, DIM, HORIZONTAL_ALIGNMENT_LEFT, 60.0)
	m._bar(Rect2(160, 62, 400, 14), m.S.wave_t / m.S.wave_time, Color(1, 1, 1, 0.35))
	m._counter("icon_cash", "$%d" % int(m.S.cash), Vector2(6, 50), 30, BuildingDB.cat_color("eco"), 44.0)
	m._counter("icon_coin", m.fmt_num(int(m.S.coins_run)), Vector2(572, 50), 26, GOLD, 44.0)
	var mhp: float = float(m.S.stats["max_hp"])
	m._bar(Rect2(160, 88, 400, 24), m.S.hp / mhp, Color("e8434f"))
	m._text("%d / %d" % [clampi(int(ceil(m.S.hp)), 0, int(mhp)), int(mhp)], Vector2(360, 108), 18, TEXT)
	# perk icon row (under the HP bar) + gems
	for k in m.S.perks_taken.size():
		var pid: String = m.S.perks_taken[k]
		var pr := Rect2(14 + k * 40, 130, 36, 36)
		if not m._icon("perk_" + pid.substr(2), pr):
			m.draw_rect(pr, GOLD, false, 2.0)
	m._counter("icon_gem", str(int(m.save["gems"]) + m.S.gems_run), Vector2(462, 166), 22, GEM, 40.0)
	# xp bar
	m._bar(Rect2(20, ARENA_BOTTOM - 4, 680, 20), m.S.xp / m.S.xp_need(), Color("6bd46b"))
	m._text("LV %d" % m.S.level, Vector2(360, ARENA_BOTTOM + 13), 18, TEXT)
	if m.screen == "results":
		draw_results(m)
		return
	if m.S.perk_offer.size() > 0:
		m._text("PERK — wave %d" % m.S.wave, Vector2(360, 918), 28, GOLD)
		return
	if m.S.draft.size() > 0:
		m._text("LEVEL UP — pick a building", Vector2(360, 918), 26, TEXT)
		if m.S.rerolls_left <= 0:
			m._text("Eco grows faster · weapons survive longer", Vector2(360, 1230), 20, DIM)
		return
	if m.S.pending_place != "":
		var d2: Dictionary = BuildingDB.get_def(m.S.pending_place)
		m._text("Tap a free slot to place", Vector2(360, 950), 26, TEXT)
		m._text(String(d2["name"]), Vector2(360, 995), 34, BuildingDB.cat_color(String(d2["cat"])))
		m._text("(time slowed)", Vector2(360, 1035), 20, DIM)
		return
	var info: String = "Tap a building to upgrade it with cash"
	if m.sel == TowerState.CORE_SLOT:
		info = "Core — %.0f dmg" % float((m.S.stats["weapons"] as Array).back()["dmg"])
	elif m.sel >= 0 and m.S.id_at(m.sel) != "":
		var d3: Dictionary = BuildingDB.get_def(m.S.id_at(m.sel))
		info = "%s Lv%d — %s" % [String(d3["name"]), m.S.lvl_at(m.sel), String(d3["desc"])]
	elif m.sel >= 0 and not bool(m.S.unlocked[m.sel]):
		info = "Locked plot — unlock for this run"
	m._text(info, Vector2(360, 925), 20, TEXT)
	var st: Dictionary = m.S.stats
	m._text("$%.1f/s   XP x%.2f   Bounty x%.2f   Regen %.1f/s" % [float(st["cash_ps"]), float(st["xp_mult"]), float(st["bounty_mult"]), float(st["regen"])], Vector2(360, 1090), 19, DIM)
	var dr: float = float(st.get("dr", 0.0))
	var nl: int = (st.get("links", []) as Array).size()
	m._text("Damage reduction %d%%   ·   Synergy links %d" % [int(round(dr * 100.0)), nl], Vector2(360, 1126), 19, DIM)
	if m.S.perks_taken.size() > 0:
		m._text("Perks: %d   ·   Next perk wave %d" % [m.S.perks_taken.size(), (m.S.wave / maxi(1, TuneRef.int_of("perk_every", 5)) + 1) * TuneRef.int_of("perk_every", 5)], Vector2(360, 1162), 19, DIM)


static func draw_results(m) -> void:
	m.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.55))
	m._panel(Rect2(40, 150, 640, 940), ENEMY, Color(0.1, 0.12, 0.15, 0.96))
	m._text("CORE DESTROYED", Vector2(360, 222), 44, ENEMY)
	m._text("Reached wave %d   ·   %d kills" % [int(m.last_result.get("wave", 0)), int(m.last_result.get("kills", 0))], Vector2(360, 272), 26, TEXT)
	var bd: Dictionary = m.last_result.get("breakdown", {})
	var rows: Array = [
		["Wave coins", str(int(bd.get("wave", 0)))],
		["Kill coins", str(int(bd.get("kills", 0)))],
		["Boss bounty", str(int(bd.get("boss", 0)))],
		["Cash-out", str(int(bd.get("cashout", 0)))],
		["x Tier %d" % int(bd.get("tier", 1)), "x%.1f" % Tiers.coin_mult(int(bd.get("tier", 1)))],
		["x Lab / card / perk", "x%.2f" % (float(bd.get("mult", 1.0)) / maxf(0.01, Tiers.coin_mult(int(bd.get("tier", 1)))))],
	]
	var y: float = 340.0
	for r in rows:
		var ra: Array = r
		m._text(String(ra[0]), Vector2(90, y), 24, DIM, HORIZONTAL_ALIGNMENT_LEFT, 360.0)
		m._text(String(ra[1]), Vector2(630, y), 24, TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 200.0)
		m.draw_line(Vector2(90, y + 14), Vector2(630, y + 14), Color(1, 1, 1, 0.08), 1.0)
		y += 52.0
	m._icon("icon_coin", Rect2(150, y + 8, 52, 52))
	m._text("+%s coins banked" % m.fmt_num(int(m.last_result.get("coins", 0))), Vector2(212, y + 50), 34, GOLD, HORIZONTAL_ALIGNMENT_LEFT, 440.0)
	y += 100.0
	m._icon("icon_gem", Rect2(150, y - 30, 40, 40))
	m._text("+%d gems from bosses" % int(bd.get("gems", 0)), Vector2(202, y), 24, GEM, HORIZONTAL_ALIGNMENT_LEFT, 440.0)
	y += 50.0
	m._icon("icon_mission", Rect2(150, y - 30, 40, 40))
	m._text("%d missions completed" % m.run_missions, Vector2(202, y), 24, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 440.0)
	y += 50.0
	var perks: Array = m.last_breakdown.get("perks", [])
	m._text("%d perks taken this run" % perks.size(), Vector2(360, y), 20, DIM)
	m._text("Spend coins on your base, labs & tiers", Vector2(360, 1060), 20, DIM)
