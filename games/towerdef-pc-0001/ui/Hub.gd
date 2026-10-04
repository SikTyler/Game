extends RefCounted
## The hub between runs (REDESIGN_SPEC §5): a nav row of tabs under the top
## bar — Play, Core Bay, Crates, Outpost, Research, Cards, Missions, Reforge —
## and START RUN. This file owns the nav, the Play tab (active Core, tier
## select, mode, Outpost / research / mission summaries) and the Research,
## Cards and Missions tabs; the other tabs live in CoreBay / CrateView /
## OutpostView / ReforgeView. View only: buttons call pure modules and hand
## the returned events to Main.meta_act().

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const Tiers := preload("res://Tiers.gd")
const Labs := preload("res://Labs.gd")
const Cards := preload("res://Cards.gd")
const Missions := preload("res://Missions.gd")
const Cores := preload("res://Cores.gd")
const Parts := preload("res://Parts.gd")
const Crates := preload("res://Crates.gd")
const Outpost := preload("res://Outpost.gd")
const Reforge := preload("res://Reforge.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const PartDB := preload("res://data/PartDB.gd")
const LabDB := preload("res://data/LabDB.gd")
const CardDB := preload("res://data/CardDB.gd")
const MissionDB := preload("res://data/MissionDB.gd")
const ModifierDB := preload("res://data/ModifierDB.gd")
const TuneRef := preload("res://Tune.gd")
const Kit := preload("res://ui/Kit.gd")
const CoreBay := preload("res://ui/CoreBay.gd")
const CrateView := preload("res://ui/CrateView.gd")
const OutpostView := preload("res://ui/OutpostView.gd")
const ReforgeView := preload("res://ui/ReforgeView.gd")

## [id, label, hotkey action, icon]
const TABS: Array = [
	["play", "Play", "tab_base", "tab_base"],
	["bay", "Core Bay", "tab_bay", "core_open"],
	["crates", "Crates", "tab_crates", "crate_field"],
	["outpost", "Outpost", "tab_outpost", "op_relay_1"],
	["research", "Research", "tab_labs", "icon_lab"],
	["cards", "Cards", "tab_cards", "tab_cards"],
	["missions", "Missions", "tab_missions", "tab_missions"],
	["reforge", "Reforge", "tab_reforge", "rf_root"],
]
const TAB_KEYS: Array = [["tab_base", "play"], ["tab_bay", "bay"], ["tab_crates", "crates"], ["tab_outpost", "outpost"], ["tab_labs", "research"], ["tab_cards", "cards"], ["tab_missions", "missions"], ["tab_reforge", "reforge"]]
const START_W: float = 250.0


static func badge(m, id: String) -> bool:
	var s: Dictionary = m.save
	var t: int = m.now()
	match id:
		"research":
			return Labs.any_done(s, t)
		"crates":
			return Crates.tokens(s) > 0 or Crates.can_pay(s, "field", "coins") or Crates.can_pay(s, "supply", "keys")
		"outpost":
			var p: Dictionary = Outpost.pending(s, t)
			return float(p["coins"]) >= 1.0 or float(p["gems"]) >= 1.0 or float(p["scrap"]) >= 1.0 or float(p["keys"]) >= 1.0
		"missions":
			return Missions.has_claimable(s) or Missions.streak_available(s, t)
		"reforge":
			return Reforge.can_reforge(s)
		"bay":
			return Cores.can_level(s, Cores.active(s))
	return false


static func nav_rect(m, k: int) -> Rect2:
	var w: float = (m.vw - START_W - 24.0) / float(TABS.size())
	return Rect2(8.0 + float(k) * w, m.TOP_H + 8.0, w - 6.0, m.NAV_H - 14.0)


static func build(m) -> void:
	for k in TABS.size():
		var tb: Array = TABS[k]
		var id: String = tb[0]
		var on: bool = m.tab == id
		Kit.btn(m, "%s  [%s]" % [String(tb[1]), Kit.hint(m, String(tb[2]))], nav_rect(m, k), func() -> void: m.set_tab(id), "Open %s" % String(tb[1]), true, Kit.RUST if on else Kit.NEUTRAL, "DTAB " + String(tb[1]), String(tb[3]), 16)
	var sr := Rect2(m.vw - START_W - 8.0, m.TOP_H + 6.0, START_W, m.NAV_H - 10.0)
	Kit.btn(m, "START RUN  T%d [%s]" % [m.view_tier, Kit.hint(m, "confirm")], sr, func() -> void: m.start_run(), "Start a run on Tier %d with the %s Core" % [m.view_tier, String(CoreDB.get_def(Cores.active(m.save))["name"])], Tiers.is_unlocked(m.save, m.view_tier), Kit.RUST, "DSTART", "", 20)
	match String(m.tab):
		"play":
			_build_play(m)
		"bay":
			CoreBay.build(m)
		"crates":
			CrateView.build(m)
		"outpost":
			OutpostView.build(m)
		"research":
			_build_research(m)
		"cards":
			_build_cards(m)
		"missions":
			_build_missions(m)
		"reforge":
			ReforgeView.build(m)


static func draw(m) -> void:
	var cr: Rect2 = m.content_rect()
	m.draw_rect(Rect2(0, m.TOP_H, m.vw, m.NAV_H), Color("1a1f26"))
	m.draw_line(Vector2(0, m.TOP_H + m.NAV_H), Vector2(m.vw, m.TOP_H + m.NAV_H), Kit.EDGE, 2.0)
	match String(m.tab):
		"play":
			_draw_play(m, cr)
		"bay":
			CoreBay.draw(m, cr)
		"crates":
			CrateView.draw(m, cr)
		"outpost":
			OutpostView.draw(m, cr)
		"research":
			_draw_research(m, cr)
		"cards":
			_draw_cards(m, cr)
		"missions":
			_draw_missions(m, cr)
		"reforge":
			ReforgeView.draw(m, cr)
	for k in TABS.size():
		if m.overlay == "" and m.offline_offer.is_empty() and badge(m, String((TABS[k] as Array)[0])):
			var r: Rect2 = nav_rect(m, k)
			m.draw_circle(Vector2(r.end.x - 10, r.position.y + 10), 6.0, Kit.ENEMY)


# ===================================================================== PLAY
static func _cols(m) -> Array:
	var cr: Rect2 = m.content_rect()
	var pad: float = 20.0
	var w: float = (cr.size.x - pad * 4.0) / 3.0
	var out: Array = []
	for k in 3:
		out.append(Rect2(cr.position.x + pad + float(k) * (w + pad), cr.position.y + pad, w, cr.size.y - pad * 2.0))
	return out


static func _build_play(m) -> void:
	var c: Array = _cols(m)
	var lc: Rect2 = c[0]
	var mc: Rect2 = c[1]
	var rc: Rect2 = c[2]
	Kit.btn(m, "Open Core Bay [%s]" % Kit.hint(m, "tab_bay"), Rect2(lc.position.x + 20, lc.end.y - 70, lc.size.x - 40, 50), func() -> void: m.set_tab("bay"), "Choose a Core, install parts, compare and level them", true, Kit.RUST, "PLAY BAY", "core_open")
	var cx: float = mc.get_center().x
	Kit.btn(m, "<", Rect2(mc.position.x + 20, mc.position.y + 70, 70, 70), func() -> void: m.shift_tier(-1), "Previous tier", m.view_tier > 1, Kit.NEUTRAL, "<", "", 30)
	Kit.btn(m, ">", Rect2(mc.end.x - 90, mc.position.y + 70, 70, 70), func() -> void: m.shift_tier(1), "Next tier (tougher enemies, more coins)", m.view_tier < mini(Tiers.tier_max(), Tiers.highest(m.save) + 1), Kit.NEUTRAL, ">", "", 30)
	Kit.btn(m, "START RUN", Rect2(cx - 180, mc.position.y + 270, 360, 74), func() -> void: m.start_run(), "Start a run with the current Core, tier, mode and modifiers", Tiers.is_unlocked(m.save, m.view_tier), Kit.RUST, "START RUN", "", 32)
	Kit.btn(m, "Mode & challenges", Rect2(cx - 180, mc.position.y + 360, 360, 50), func() -> void: m.set_overlay("modes"), "Pick Normal or Endless and stack challenge modifiers for bonus coins", true, Kit.MAG, "MODES", "icon_mod")
	var y: float = rc.position.y + 60.0
	Kit.btn(m, "Outpost [%s]" % Kit.hint(m, "tab_outpost"), Rect2(rc.end.x - 200, y - 46, 180, 42), func() -> void: m.set_tab("outpost"), "Open the Outpost builder", true, Kit.NEUTRAL, "PLAY OUTPOST", "op_relay_1", 16)
	Kit.btn(m, "Research [%s]" % Kit.hint(m, "tab_labs"), Rect2(rc.end.x - 200, y + 214, 180, 42), func() -> void: m.set_tab("research"), "Open the Research Hall", true, Kit.NEUTRAL, "PLAY RESEARCH", "icon_lab", 16)


static func _draw_play(m, _cr: Rect2) -> void:
	var s: Dictionary = m.save
	var c: Array = _cols(m)
	var lc: Rect2 = c[0]
	var mc: Rect2 = c[1]
	var rc: Rect2 = c[2]
	for col in c:
		Kit.panel(m, col as Rect2, Kit.EDGE, Kit.PANEL)
	# --- left: the active Core
	var cid: String = Cores.active(s)
	var cd: Dictionary = CoreDB.get_def(cid)
	var lv: int = Cores.level(s, cid)
	var x: float = lc.position.x + 24.0
	var w: float = lc.size.x - 48.0
	Kit.head(m, "ACTIVE CORE", Vector2(x, lc.position.y + 34), w)
	var g: float = 0.5 + 0.5 * sin(m.t_anim * 2.0)
	m.draw_circle(Vector2(lc.get_center().x, lc.position.y + 160), 96.0 + 6.0 * g, Color(Kit.RUST, 0.08))
	Kit.icon(m, "core_" + cid, Rect2(lc.get_center().x - 84, lc.position.y + 76, 168, 168))
	Kit.t(m, "%s Core" % String(cd["name"]), Vector2(lc.get_center().x, lc.position.y + 278), 30, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
	Kit.t(m, "Level %d / %d  ·  %s" % [lv, Cores.max_level(s), String(cd["arch"]).capitalize()], Vector2(lc.get_center().x, lc.position.y + 306), 17, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
	var y: float = lc.position.y + 344.0
	Kit.t(m, String(cd["attack_name"]), Vector2(x, y), 19, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w)
	y += Kit.wrap(m, String(cd["attack_desc"]), Vector2(x, y + 8), 15, Kit.DIM, w, 2) + 18.0
	Kit.t(m, "Trait: " + String(cd["trait_name"]), Vector2(x, y + 8), 17, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w)
	y += Kit.wrap(m, String(cd["trait_desc"]), Vector2(x, y + 16), 15, Kit.DIM, w, 2) + 34.0
	var stats: Array = [
		["Damage", "%.1f" % (float(cd["dmg"]) * CoreDB.lvl_mult("dmg", lv))], ["Attack rate", "%.2f/s" % float(cd["rate"])],
		["Range", "%.1f cells" % float(cd["range"])], ["Core HP", "%d" % int(float(cd["hp"]) * CoreDB.lvl_mult("hp", lv))],
		["Regen", "%.1f/s" % (float(cd["regen"]) * CoreDB.lvl_mult("regen", lv))], ["Cash / s", "%.1f" % (float(cd["cash"]) * CoreDB.lvl_mult("cash", lv))],
	]
	for k in stats.size():
		var rw: Array = stats[k]
		Kit.row(m, String(rw[0]), String(rw[1]), Vector2(x + float(k % 2) * (w * 0.5 + 10.0), y + float(k / 2) * 26.0), w * 0.5 - 10.0, Kit.TEXT, "", 15)
	y += 3.0 * 26.0 + 14.0
	Kit.t(m, "Installed parts", Vector2(x, y), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
	var eq: Array = Parts.equipped(s, cid)
	var px: float = x
	for e in eq:
		var ed: Dictionary = e
		var pr := Rect2(px, y + 10, 44, 44)
		Kit.panel(m, pr, Kit.rarity_col(PartDB.rarity_of(String(ed["id"]))), Color("101418"), 2)
		Kit.icon(m, String(ed["id"]), pr.grow(-3))
		m.stat_tips.append([pr, "%s  Lv%d" % [String(PartDB.get_def(String(ed["id"])).get("name", "")), int(ed["lvl"])]])
		px += 50.0
	if eq.is_empty():
		Kit.t(m, "none — open crates and install parts in the Core Bay", Vector2(x, y + 36), 14, Color(Kit.DIM, 0.7), HORIZONTAL_ALIGNMENT_LEFT, w)
	# --- middle: tier + start
	var cx: float = mc.get_center().x
	Kit.head(m, "DEPLOY", Vector2(mc.position.x + 24, mc.position.y + 34), mc.size.x - 48)
	var vt: int = m.view_tier
	if Tiers.is_unlocked(s, vt):
		Kit.t(m, "TIER %d" % vt, Vector2(cx, mc.position.y + 118), 44, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 300.0)
		Kit.t(m, "coins x%.1f  ·  enemy HP x%.1f" % [Tiers.coin_mult(vt), Tiers.hp_mult(vt)], Vector2(cx, mc.position.y + 158), 17, Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, mc.size.x - 180)
		var bwt: Dictionary = s.get("best_wave_by_tier", {})
		Kit.t(m, "Best wave on this tier: %d" % int(bwt.get(str(vt), 0)), Vector2(cx, mc.position.y + 186), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, mc.size.x - 40)
	else:
		Kit.icon(m, "icon_lock", Rect2(cx - 20, mc.position.y + 84, 40, 40), Color(1, 1, 1, 0.7))
		Kit.t(m, Tiers.requirement(vt), Vector2(cx, mc.position.y + 160), 19, Color("ff8a8a"), HORIZONTAL_ALIGNMENT_CENTER, mc.size.x - 180)
	var mode: String = String(m.run_opts.get("mode", "normal"))
	var mods: Array = m.run_opts.get("modifiers", [])
	var names: Array = []
	for id in mods:
		names.append(String(ModifierDB.get_def(String(id))["name"]))
	Kit.t(m, "%s run%s" % [mode.capitalize(), ("  ·  " + ", ".join(names)) if not names.is_empty() else ""], Vector2(cx, mc.position.y + 236), 16, Kit.MAG if mode == "endless" else Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, mc.size.x - 40)
	var ty: float = mc.position.y + 450.0
	Kit.head(m, "HOW A RUN WORKS", Vector2(mc.position.x + 24, ty), mc.size.x - 48)
	var how: String = "Your Core fights and earns cash. Spend cash on the 5 Core tracks (right panel). The grid starts empty: every draft offers buildings, troop huts, upgrade packs, special attacks — and, rarely, an Insight that improves you permanently. Bosses, marked elites and Couriers drop parts for the Core Bay."
	Kit.wrap(m, how, Vector2(mc.position.x + 24, ty + 26), 16, Kit.DIM, mc.size.x - 48, 9)
	var lr2: Array = s.get("history", [])
	if not lr2.is_empty():
		var e: Dictionary = lr2[lr2.size() - 1]
		Kit.t(m, "Last run: Tier %d, wave %d, +%s coins" % [int(e["tier"]), int(e["wave"]), Kit.fmt(float(e["coins"]))], Vector2(cx, mc.end.y - 24), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, mc.size.x - 40)
	# --- right: Outpost / research / missions / reforge
	x = rc.position.x + 24.0
	w = rc.size.x - 48.0
	y = rc.position.y + 34.0
	Kit.head(m, "OUTPOST", Vector2(x, y), w - 200.0)
	var prod: Dictionary = Outpost.production(s)
	var pend: Dictionary = Outpost.pending(s, m.now())
	var res: Array = [["cur_coin", "coins", Kit.GOLD], ["cur_scrap", "scrap", Kit.SCRAP], ["cur_gem", "gems", Kit.GEM], ["cur_key", "keys", Kit.KEYC]]
	for k in res.size():
		var a: Array = res[k]
		var ry: float = y + 40.0 + float(k) * 42.0
		Kit.icon(m, String(a[0]), Rect2(x, ry - 4, 30, 30))
		var r: float = float(prod[String(a[1])])
		Kit.t(m, ("%s/h" % Kit.fmt(r)) if r >= 10.0 else ("%.2f/h" % r), Vector2(x + 40, ry + 20), 18, a[2], HORIZONTAL_ALIGNMENT_LEFT, 140.0)
		Kit.t(m, "stored %s" % Kit.fmt(floorf(float(pend[String(a[1])]))), Vector2(x + w, ry + 20), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 200.0)
	y += 220.0
	Kit.head(m, "RESEARCH HALL", Vector2(x, y + 6), w - 200.0)
	var run: Array = Labs.running(s)
	if run.is_empty():
		Kit.t(m, "%d queue%s idle — start a project" % [Labs.slots(s), "" if Labs.slots(s) == 1 else "s"], Vector2(x, y + 44), 16, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w)
	for k in run.size():
		var e2: Dictionary = run[k]
		var ry2: float = y + 30.0 + float(k) * 34.0
		Kit.t(m, "%s -> Lv%d" % [String((LabDB.DEFS[String(e2["track"])] as Dictionary)["name"]), int(e2["to_lvl"])], Vector2(x, ry2 + 16), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w * 0.55)
		Kit.bar(m, Rect2(x + w * 0.58, ry2 + 4, w * 0.42, 14), Labs.progress(s, k, m.now()), Kit.LAB)
	y += 150.0
	Kit.head(m, "MISSIONS", Vector2(x, y), w)
	var ml: Array = Missions.list(s)
	for k in ml.size():
		var me: Dictionary = ml[k]
		var ry3: float = y + 30.0 + float(k) * 30.0
		Kit.t(m, MissionDB.text(String(me["tpl"]), int(me["target"])), Vector2(x, ry3), 15, Kit.TEXT if not Missions.is_done(me) else Kit.GREEN, HORIZONTAL_ALIGNMENT_LEFT, w - 70)
		Kit.t(m, "%d/%d" % [int(me["prog"]), int(me["target"])], Vector2(x + w, ry3), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 70.0)
	y += 30.0 + float(ml.size()) * 30.0 + 16.0
	Kit.head(m, "CORE REFORGE", Vector2(x, y), w)
	var pv: Dictionary = Reforge.preview(s)
	var rtxt: String = "Ready: +%d shards  [%s]" % [int(pv["shards"]), Kit.hint(m, "tab_reforge")] if bool(pv["ok"]) else "Unlocks at best wave %d (or 1M coins since the last Reforge)" % int(pv["gate_wave"])
	Kit.wrap(m, rtxt, Vector2(x, y + 22), 15, Kit.SHARD if bool(pv["ok"]) else Kit.DIM, w, 2)


# ================================================================= RESEARCH
static func _lab_rect(m, k: int) -> Rect2:
	var cr: Rect2 = m.content_rect()
	var cols: int = 4
	var w: float = (cr.size.x - 40.0 - float(cols - 1) * 14.0) / float(cols)
	var top: float = cr.position.y + 220.0
	var h: float = minf(150.0, (cr.end.y - top - 20.0 - 2.0 * 14.0) / 3.0)
	return Rect2(cr.position.x + 20.0 + float(k % cols) * (w + 14.0), top + float(k / cols) * (h + 14.0), w, h)


static func _queue_rect(m, k: int) -> Rect2:
	var cr: Rect2 = m.content_rect()
	var w: float = (cr.size.x - 40.0 - 28.0) / 3.0
	return Rect2(cr.position.x + 20.0 + float(k) * (w + 14.0), cr.position.y + 62.0, w, 110.0)


static func _build_research(m) -> void:
	var s: Dictionary = m.save
	var t: int = m.now()
	var run: Array = Labs.running(s)
	for k in run.size():
		var slot: int = k
		var rc: int = Labs.rush_cost(s, k, t)
		var qr: Rect2 = _queue_rect(m, k)
		if rc > 0:
			Kit.btn(m, "Rush %d gem%s" % [rc, "" if rc == 1 else "s"], Rect2(qr.end.x - 170, qr.end.y - 52, 156, 42), func() -> void: m.meta_act(Labs.rush(m.save, slot, m.now())), "Finish this research now for gems", int(s["gems"]) >= rc, Kit.GEM, "Rush", "cur_gem", 16)
	for k in LabDB.IDS.size():
		var id: String = LabDB.IDS[k]
		var d: Dictionary = LabDB.DEFS[id]
		var lvl: int = Labs.level(s, id)
		var tip: String = "%s  Lv%d/%d\n%s\nNext: %s coins, %s" % [String(d["name"]), lvl, LabDB.max_of(id), String(d["effect"]), Kit.fmt(float(Labs.cost(id, lvl))), Kit.dur(Labs.duration(s, id, lvl))]
		Kit.hit(m, _lab_rect(m, k), func() -> void: m.meta_act(Labs.start(m.save, id, m.now())), tip, "LAB " + id, Labs.can_start(s, id), Kit.LAB)


static func _draw_research(m, cr: Rect2) -> void:
	var s: Dictionary = m.save
	var t: int = m.now()
	var run: Array = Labs.running(s)
	Kit.t(m, "RESEARCH HALL", Vector2(cr.position.x + 20, cr.position.y + 40), 26, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 500.0)
	Kit.t(m, "Queues follow the Research Hall's level in the Outpost (1 / 2 / 3 at Hall L1 / L4 / L8). Research runs in real time.", Vector2(cr.position.x + 300, cr.position.y + 38), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 320)
	for k in Labs.MAX_SLOTS:
		var r: Rect2 = _queue_rect(m, k)
		if k < run.size():
			var e: Dictionary = run[k]
			var id: String = String(e["track"])
			var d: Dictionary = LabDB.DEFS.get(id, {})
			Kit.panel(m, r, Kit.LAB, Kit.PANEL2)
			Kit.icon(m, "lab_" + id, Rect2(r.position.x + 12, r.position.y + 12, 56, 56))
			Kit.t(m, "%s -> Lv%d" % [String(d.get("name", id)), int(e["to_lvl"])], Vector2(r.position.x + 80, r.position.y + 36), 19, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 90)
			var rem: int = maxi(0, int(e["end"]) - t)
			Kit.t(m, "DONE" if rem <= 0 else Kit.dur(rem), Vector2(r.position.x + 80, r.position.y + 62), 17, Kit.GREEN if rem <= 0 else Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
			Kit.bar(m, Rect2(r.position.x + 12, r.end.y - 20, r.size.x - 200, 10), Labs.progress(s, k, t), Kit.LAB)
		elif k < Labs.slots(s):
			Kit.panel(m, r, Kit.EDGE, Color("1c2128"))
			Kit.t(m, "Queue %d idle — pick a project below" % (k + 1), r.get_center() + Vector2(0, 6), 18, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		else:
			Kit.panel(m, r, Color("2a3038"), Color("15191e"))
			Kit.icon(m, "icon_lock", Rect2(r.position.x + 16, r.get_center().y - 18, 36, 36), Color(1, 1, 1, 0.5))
			Kit.t(m, "Research Hall L%d opens this queue" % (4 if k == 1 else 8), Vector2(r.position.x + 64, r.get_center().y + 6), 17, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 70)
	Kit.head(m, "PROJECTS", Vector2(cr.position.x + 20, cr.position.y + 202), cr.size.x - 40)
	for k in LabDB.IDS.size():
		var id2: String = LabDB.IDS[k]
		var d2: Dictionary = LabDB.DEFS[id2]
		var r2: Rect2 = _lab_rect(m, k)
		var lvl: int = Labs.level(s, id2)
		var mx: int = LabDB.max_of(id2)
		var ok: bool = Labs.can_start(s, id2)
		Kit.panel(m, r2, Kit.LAB if ok else Kit.EDGE, Kit.PANEL2 if ok else Color("1c2128"))
		if not Kit.icon(m, "lab_" + id2, Rect2(r2.position.x + 12, r2.position.y + 14, 52, 52), Color.WHITE if ok or lvl >= mx else Color(1, 1, 1, 0.5)):
			Kit.icon(m, "cur_scrap" if id2 == "part_analysis" else ("crate_field" if id2 == "crate_theory" else "icon_lab"), Rect2(r2.position.x + 12, r2.position.y + 14, 52, 52), Color.WHITE if ok else Color(1, 1, 1, 0.5))
		Kit.t(m, String(d2["name"]), Vector2(r2.position.x + 76, r2.position.y + 34), 19, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, r2.size.x - 90)
		Kit.t(m, "Lv %d / %d" % [lvl, mx], Vector2(r2.end.x - 12, r2.position.y + 34), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 100.0)
		Kit.wrap(m, String(d2["effect"]), Vector2(r2.position.x + 76, r2.position.y + 48), 14, Kit.DIM, r2.size.x - 90, 2)
		var status: String = "%s coins  ·  %s" % [Kit.fmt(float(Labs.cost(id2, lvl))), Kit.dur(Labs.duration(s, id2, lvl))]
		var sc: Color = Kit.GOLD
		if Labs.is_running(s, id2):
			status = "RESEARCHING"
			sc = Kit.LAB
		elif lvl >= mx:
			status = "MAX"
			sc = Kit.GREEN
		Kit.t(m, status, Vector2(r2.position.x + 76, r2.end.y - 14), 16, sc, HORIZONTAL_ALIGNMENT_LEFT, r2.size.x - 90)


# ==================================================================== CARDS
static func _card_rect(m, k: int) -> Rect2:
	var cr: Rect2 = m.content_rect()
	var cols: int = 6
	var w: float = (cr.size.x - 40.0 - float(cols - 1) * 12.0) / float(cols)
	var top: float = cr.position.y + 280.0
	var h: float = minf(220.0, (cr.end.y - top - 110.0) / 2.0)
	return Rect2(cr.position.x + 20.0 + float(k % cols) * (w + 12.0), top + float(k / cols) * (h + 12.0), w, h)


static func _eq_rect(m, k: int) -> Rect2:
	var cr: Rect2 = m.content_rect()
	return Rect2(cr.position.x + 20.0 + float(k) * 172.0, cr.position.y + 66.0, 160, 170)


static func _build_cards(m) -> void:
	var s: Dictionary = m.save
	var eq: Array = Cards.equipped(s)
	var own: Dictionary = Cards.owned(s)
	var n: int = Cards.slots(s)
	for k in Cards.MAX_SLOTS:
		if k < eq.size():
			var id: String = String(eq[k])
			Kit.hit(m, _eq_rect(m, k), func() -> void: m.meta_act(Cards.unequip(m.save, id)), "%s — click to unequip" % String((CardDB.DEFS[id] as Dictionary)["name"]), "EQ " + id)
		elif k == n:
			Kit.btn(m, "Buy slot\n%d gems" % Cards.slot_cost(s), _eq_rect(m, k), func() -> void: m.meta_act(Cards.buy_slot(m.save)), "Unlock another card slot", int(s["gems"]) >= Cards.slot_cost(s), Kit.GEM, "CSLOT", "", 18)
	for k in CardDB.IDS.size():
		var id2: String = CardDB.IDS[k]
		if own.has(id2):
			var is_eq: bool = eq.has(id2)
			var cb: Callable = func() -> void: m.meta_act(Cards.unequip(m.save, id2) if Cards.equipped(m.save).has(id2) else Cards.equip(m.save, id2))
			Kit.hit(m, _card_rect(m, k), cb, "%s\n%s\nClick to %s" % [String((CardDB.DEFS[id2] as Dictionary)["name"]), CardDB.describe(id2, Cards.level(s, id2)), "unequip" if is_eq else "equip"], "CARD " + id2, is_eq or eq.size() < n)
	var cr: Rect2 = m.content_rect()
	Kit.btn(m, "Open Chest  ·  %d gems" % Cards.chest_cost(), Rect2(cr.get_center().x - 220, cr.end.y - 84, 440, 64), func() -> void: m.meta_act(Cards.open_chest(m.save, m.meta_rng)), "Open a card chest (new card or a copy)", int(s["gems"]) >= Cards.chest_cost(), Kit.GEM, "Open Chest", "chest", 22)


static func _draw_cards(m, cr: Rect2) -> void:
	var s: Dictionary = m.save
	var eq: Array = Cards.equipped(s)
	var own: Dictionary = Cards.owned(s)
	var n: int = Cards.slots(s)
	Kit.t(m, "CARDS  —  equipped %d / %d" % [eq.size(), n], Vector2(cr.position.x + 20, cr.position.y + 44), 24, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 600.0)
	for k in Cards.MAX_SLOTS:
		var r: Rect2 = _eq_rect(m, k)
		if k < eq.size():
			var id: String = String(eq[k])
			Kit.panel(m, r, Kit.GOLD, Kit.PANEL2)
			Kit.icon(m, "card_" + id.substr(2), Rect2(r.get_center().x - 40, r.position.y + 14, 80, 80))
			Kit.t(m, String((CardDB.DEFS[id] as Dictionary)["name"]), Vector2(r.get_center().x, r.position.y + 124), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 10)
			Kit.t(m, "Lv%d" % Cards.level(s, id), Vector2(r.get_center().x, r.position.y + 150), 15, Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		elif k < n:
			Kit.panel(m, r, Kit.NEUTRAL, Color("1a1f25"))
			Kit.t(m, "Empty", r.get_center() + Vector2(0, 6), 18, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		elif k > n:
			Kit.panel(m, r, Color("2a3038"), Color("15191e"))
			Kit.icon(m, "icon_lock", Rect2(r.get_center() - Vector2(18, 18), Vector2(36, 36)), Color(1, 1, 1, 0.35))
	Kit.head(m, "COLLECTION — click a card to equip / unequip", Vector2(cr.position.x + 20, cr.position.y + 266), cr.size.x - 40)
	for k in CardDB.IDS.size():
		var id2: String = CardDB.IDS[k]
		var r2: Rect2 = _card_rect(m, k)
		if own.has(id2):
			var e: Dictionary = own[id2]
			var lvl: int = int(e["lvl"])
			var is_eq: bool = eq.has(id2)
			Kit.panel(m, r2, Kit.GOLD if is_eq else Kit.EDGE, Kit.PANEL2)
			Kit.icon(m, "card_" + id2.substr(2), Rect2(r2.get_center().x - 36, r2.position.y + 12, 72, 72))
			Kit.t(m, String((CardDB.DEFS[id2] as Dictionary)["name"]) + ("  (on)" if is_eq else ""), Vector2(r2.get_center().x, r2.position.y + 108), 17, Kit.GOLD if is_eq else Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r2.size.x - 10)
			Kit.wrap(m, CardDB.describe(id2, lvl), Vector2(r2.position.x + 10, r2.position.y + 128), 14, Kit.DIM, r2.size.x - 20, 3, HORIZONTAL_ALIGNMENT_CENTER)
			var prog: String = "MAX" if lvl >= CardDB.MAX_LVL else "%d/%d copies" % [int(e["copies"]), lvl]
			Kit.t(m, "Lv%d  ·  %s" % [lvl, prog], Vector2(r2.get_center().x, r2.end.y - 12), 14, Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, r2.size.x)
		else:
			Kit.panel(m, r2, Color("2a3038"), Color("15191e"))
			Kit.icon(m, "card_back", Rect2(r2.get_center().x - 36, r2.position.y + 20, 72, 72), Color(1, 1, 1, 0.5))
			Kit.t(m, "Not found yet", Vector2(r2.get_center().x, r2.position.y + 120), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, r2.size.x)


# ================================================================= MISSIONS
static func _mission_rect(m, k: int) -> Rect2:
	var cr: Rect2 = m.content_rect()
	return Rect2(cr.position.x + 20.0, cr.position.y + 290.0 + float(k) * 112.0, cr.size.x - 40.0, 100.0)


static func _streak_done(s: Dictionary, k: int, t: int) -> bool:
	var st: Dictionary = s["streak"]
	if Missions.streak_available(s, t):
		return k < Missions.streak_next_day(s, t) - 1
	return k < int(st["day_idx"])


static func _build_missions(m) -> void:
	var s: Dictionary = m.save
	var t: int = m.now()
	var cr: Rect2 = m.content_rect()
	var avail: bool = Missions.streak_available(s, t)
	var lbl: String = "Claim Day %d" % Missions.streak_next_day(s, t) if avail else "Claimed — come back tomorrow"
	Kit.btn(m, lbl, Rect2(cr.end.x - 360, cr.position.y + 200, 340, 54), func() -> void: m.meta_act(Missions.streak_claim(m.save, m.now())), "Daily login streak reward", avail, Color("ff9f5a"), "Claim Day" if avail else "STREAK DONE", "icon_streak", 20)
	var lst: Array = Missions.list(s)
	for k in lst.size():
		var e: Dictionary = lst[k]
		var idx: int = k
		var r: Rect2 = _mission_rect(m, k)
		var claimed: bool = bool(e["claimed"])
		Kit.btn(m, "Done" if claimed else "Claim +%d" % int(e["gems"]), Rect2(r.end.x - 200, r.position.y + 26, 180, 50), func() -> void: m.meta_act(Missions.claim(m.save, idx)), "Claim the mission's gem reward", Missions.is_done(e) and not claimed, Kit.GEM, "MCLAIM %d" % k, "cur_gem")
	var br: Rect2 = _mission_rect(m, lst.size())
	var bonus: bool = Missions.all_claimed(s) and not bool((s["missions"] as Dictionary)["bonus_claimed"])
	var bdone: bool = bool((s["missions"] as Dictionary)["bonus_claimed"])
	Kit.btn(m, "Done" if bdone else "Claim bonus", Rect2(br.end.x - 200, br.position.y + 26, 180, 50), func() -> void: m.meta_act(Missions.claim_bonus(m.save)), "All-clear bonus when all 3 missions are claimed", bonus, Kit.GEM, "BONUS", "chest")


static func _draw_missions(m, cr: Rect2) -> void:
	var s: Dictionary = m.save
	var t: int = m.now()
	Kit.t(m, "LOGIN STREAK", Vector2(cr.position.x + 20, cr.position.y + 44), 24, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
	var nxt: int = Missions.streak_next_day(s, t)
	var avail: bool = Missions.streak_available(s, t)
	var dw: float = minf(150.0, (cr.size.x - 440.0) / 7.0)
	for k in 7:
		var r := Rect2(cr.position.x + 20.0 + float(k) * (dw + 8.0), cr.position.y + 66, dw, 130)
		var done: bool = _streak_done(s, k, t)
		var is_next: bool = avail and k == nxt - 1
		Kit.panel(m, r, Kit.GOLD if is_next else (Kit.GREEN if done else Kit.EDGE), Color(0.15, 0.25, 0.15) if done else Color("1f252c"))
		Kit.t(m, "Day %d" % (k + 1), Vector2(r.get_center().x, r.position.y + 26), 17, Kit.TEXT if (done or is_next) else Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var rw: Dictionary = MissionDB.STREAK[k]
		var icon_id: String = "chest" if bool(rw.get("chest", false)) else ("cur_gem" if int(rw["gems"]) > 0 else "cur_coin")
		Kit.icon(m, icon_id, Rect2(r.get_center().x - 22, r.position.y + 38, 44, 44))
		var amt: String = "%d" % int(rw["gems"]) if int(rw["gems"]) > 0 else Kit.fmt(float(rw["coins"]))
		Kit.t(m, amt, Vector2(r.get_center().x, r.end.y - 16), 19, Kit.GEM if int(rw["gems"]) > 0 else Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	Kit.head(m, "DAILY MISSIONS", Vector2(cr.position.x + 20, cr.position.y + 274), cr.size.x - 40)
	var lst: Array = Missions.list(s)
	for k in lst.size():
		var e: Dictionary = lst[k]
		var r2: Rect2 = _mission_rect(m, k)
		var tpl: String = String(e["tpl"])
		var done2: bool = Missions.is_done(e)
		Kit.panel(m, r2, Kit.GREEN if done2 else Kit.EDGE, Kit.PANEL2)
		Kit.icon(m, "mis_" + tpl, Rect2(r2.position.x + 16, r2.position.y + 22, 56, 56))
		Kit.t(m, MissionDB.text(tpl, int(e["target"])), Vector2(r2.position.x + 90, r2.position.y + 38), 20, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, r2.size.x - 330)
		Kit.bar(m, Rect2(r2.position.x + 90, r2.position.y + 52, r2.size.x - 330, 16), float(e["prog"]) / float(maxi(1, int(e["target"]))), Kit.GREEN if done2 else Kit.GEM)
		Kit.t(m, "%d / %d" % [int(e["prog"]), int(e["target"])], Vector2(r2.position.x + 90, r2.position.y + 90), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
	var br: Rect2 = _mission_rect(m, lst.size())
	Kit.panel(m, br, Kit.GOLD if Missions.all_claimed(s) else Kit.EDGE, Kit.PANEL2)
	Kit.icon(m, "chest", Rect2(br.position.x + 16, br.position.y + 20, 60, 60))
	Kit.t(m, "All-clear bonus", Vector2(br.position.x + 90, br.position.y + 42), 21, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 400.0)
	Kit.t(m, "+%d gems when all 3 are claimed" % TuneRef.int_of("mission_bonus_gems", 5), Vector2(br.position.x + 90, br.position.y + 72), 16, Kit.GEM, HORIZONTAL_ALIGNMENT_LEFT, 500.0)
	var day: int = Missions.day_of(t)
	Kit.t(m, "New missions in %s" % Kit.dur((day + 1) * 86400 - t), Vector2(cr.end.x - 20, cr.position.y + 274), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 400.0)
