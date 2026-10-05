extends RefCounted
## The hub between runs (V2): a nav row under the top bar — Outpost (home),
## Core, Research, Missions, Reforge — and the deploy cluster (tier, modes,
## PLAY). This file owns the nav and the Research and Missions tabs; the
## Outpost lives in OutpostView, the Core in CoreView, Reforge in
## ReforgeView. View only: buttons call pure modules and hand the returned
## events to Main.meta_act().

const TowerState := preload("res://TowerState.gd")
const BaseMeta := preload("res://BaseMeta.gd")
const Tiers := preload("res://Tiers.gd")
const Labs := preload("res://Labs.gd")
const Missions := preload("res://Missions.gd")
const Cores := preload("res://Cores.gd")
const Outpost := preload("res://Outpost.gd")
const Reforge := preload("res://Reforge.gd")
const CoreDB := preload("res://data/CoreDB.gd")
const LabDB := preload("res://data/LabDB.gd")
const MissionDB := preload("res://data/MissionDB.gd")
const ModifierDB := preload("res://data/ModifierDB.gd")
const TuneRef := preload("res://Tune.gd")
const Kit := preload("res://ui/Kit.gd")
const ReforgeView := preload("res://ui/ReforgeView.gd")
const OutpostView := preload("res://ui/OutpostView.gd")
const CoreView := preload("res://ui/CoreView.gd")

## Tab hotkeys: [action, tab].
const TAB_KEYS: Array = [["tab_base", "play"], ["tab_outpost", "outpost"], ["tab_core", "core"], ["tab_labs", "research"], ["tab_missions", "missions"], ["tab_reforge", "reforge"]]
const START_W: float = 250.0


static func badge(m, id: String) -> bool:
	var s: Dictionary = m.save
	var t: int = m.now()
	match id:
		"research":
			return Labs.any_done(s, t)
		"missions":
			return Missions.has_claimable(s) or Missions.streak_available(s, t)
		"reforge":
			return Reforge.can_reforge(s)
		"core":
			return Cores.can_level(s)
	return false


## FB1: the home screen IS the Outpost ("play" and "outpost" both show it).
static func is_home(tab: String) -> bool:
	return tab == "play" or tab == "outpost"


## Top menu (left): Outpost (home), then Core, Research, Missions, Reforge.
## Widths shrink to stay clear of the deploy cluster on narrow windows.
const NAV: Array = [
	["core", "Core", "core_open", "The Core: level, stats (and soon its Weapon, Modules and look)"],
	["research", "Research", "icon_lab", "Research: permanent upgrades (instant)"],
	["missions", "Missions", "tab_missions", "Daily missions and the login streak"],
	["reforge", "Reforge", "rf_root", "Core Reforge: reset for Shards and permanent nodes"],
]


static func nav_w(m) -> float:
	var avail: float = start_rect(m).position.x - 340.0 - 206.0
	return clampf(avail / float(NAV.size()) - 8.0, 96.0, 160.0)


static func nav_rect(m, k: int) -> Rect2:
	var w: float = 190.0 if k == 0 else nav_w(m)
	var x: float = 8.0 + (0.0 if k == 0 else 198.0 + float(k - 1) * (nav_w(m) + 8.0))
	return Rect2(x, m.TOP_H + 8.0, w, m.NAV_H - 14.0)


static func start_rect(m) -> Rect2:
	return Rect2(m.vw - START_W - 8.0, m.TOP_H + 6.0, START_W, m.NAV_H - 10.0)


static func build(m) -> void:
	var home: bool = is_home(String(m.tab))
	Kit.btn(m, "Outpost" if home else "Back to Outpost", nav_rect(m, 0), func() -> void: m.set_tab("play"), "Your Outpost: build, upgrade and collect", true, Kit.RUST if home else Kit.NEUTRAL, "DTAB Outpost", "op_relay_1", 16)
	for k in NAV.size():
		var nv: Array = NAV[k]
		var tid: String = String(nv[0])
		Kit.btn(m, String(nv[1]), nav_rect(m, k + 1), func() -> void: m.set_tab(tid), String(nv[3]), true, Kit.RUST if m.tab == tid else Kit.NEUTRAL, "DTAB " + String(nv[1]), String(nv[2]), 15 if nav_w(m) >= 140.0 else 13)
	# deploy cluster (right): tier < T > · Modes · START RUN
	var sr: Rect2 = start_rect(m)
	var ny: float = m.TOP_H + 8.0
	var nh: float = m.NAV_H - 14.0
	Kit.btn(m, "<", Rect2(sr.position.x - 330, ny, 46, nh), func() -> void: m.shift_tier(-1), "Previous tier", m.view_tier > 1, Kit.NEUTRAL, "<", "", 22)
	Kit.btn(m, ">", Rect2(sr.position.x - 194, ny, 46, nh), func() -> void: m.shift_tier(1), "Next tier (tougher enemies, more coins)", m.view_tier < mini(Tiers.tier_max(), Tiers.highest(m.save) + 1), Kit.NEUTRAL, ">", "", 22)
	Kit.btn(m, "Modes", Rect2(sr.position.x - 140, ny, 130, nh), func() -> void: m.set_overlay("modes"), "Pick Normal or Endless and stack challenge modifiers for bonus coins", true, Kit.MAG, "MODES", "icon_mod", 15)
	Kit.btn(m, "PLAY  T%d" % m.view_tier, sr, func() -> void: m.start_run(), "Start a run on Tier %d (Core Lv%d)" % [m.view_tier, Cores.level(m.save)], Tiers.is_unlocked(m.save, m.view_tier), Kit.RUST, "DSTART", "", 20)
	if home:
		OutpostView.build(m)
		return
	match String(m.tab):
		"core":
			CoreView.build(m)
		"research":
			_build_research(m)
		"missions":
			_build_missions(m)
		"reforge":
			ReforgeView.build(m)


static func draw(m) -> void:
	var cr: Rect2 = m.content_rect()
	var home0: bool = is_home(String(m.tab))
	if home0:
		OutpostView.draw(m, cr)   # first: the nav row below paints over any map overdraw
	m.draw_rect(Rect2(0, m.TOP_H, m.vw, m.NAV_H), Color("1a1f26"))
	m.draw_line(Vector2(0, m.TOP_H + m.NAV_H), Vector2(m.vw, m.TOP_H + m.NAV_H), Kit.EDGE, 2.0)
	var home: bool = is_home(String(m.tab))
	# tier readout between < and >
	var sr: Rect2 = start_rect(m)
	var tx: float = sr.position.x - 239.0
	var vt: int = m.view_tier
	Kit.t(m, "TIER %d" % vt, Vector2(tx, m.TOP_H + 30), 20, Kit.TEXT if Tiers.is_unlocked(m.save, vt) else Color("ff8a8a"), HORIZONTAL_ALIGNMENT_CENTER, 90.0)
	Kit.t(m, ("x%.1f coins" % Tiers.coin_mult(vt)) if Tiers.is_unlocked(m.save, vt) else "locked", Vector2(tx, m.TOP_H + 49), 13, Kit.GOLD if Tiers.is_unlocked(m.save, vt) else Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, 90.0)
	m.stat_tips.append([Rect2(tx - 45, m.TOP_H + 8, 90, m.NAV_H - 14), ("Tier %d: coins x%.1f, enemy HP x%.1f" % [vt, Tiers.coin_mult(vt), Tiers.hp_mult(vt)]) if Tiers.is_unlocked(m.save, vt) else Tiers.requirement(vt)])
	if not home:
		match String(m.tab):
			"core":
				CoreView.draw(m, cr)
			"research":
				_draw_research(m, cr)
			"missions":
				_draw_missions(m, cr)
			"reforge":
				ReforgeView.draw(m, cr)
	var nb: Array = [["outpost", 0]]
	for k in NAV.size():
		nb.append([String((NAV[k] as Array)[0]), k + 1])
	for e in nb:
		if m.overlay == "" and m.offline_offer.is_empty() and badge(m, String((e as Array)[0])):
			var r: Rect2 = nav_rect(m, int((e as Array)[1]))
			m.draw_circle(Vector2(r.end.x - 10, r.position.y + 10), 6.0, Kit.ENEMY)


# ================================================================= RESEARCH
static func _lab_rect(m, k: int) -> Rect2:
	var cr: Rect2 = m.content_rect()
	var cols: int = 4
	var w: float = (cr.size.x - 40.0 - float(cols - 1) * 14.0) / float(cols)
	var top: float = cr.position.y + 90.0
	var h: float = minf(150.0, (cr.end.y - top - 20.0 - 2.0 * 14.0) / 3.0)
	return Rect2(cr.position.x + 20.0 + float(k % cols) * (w + 14.0), top + float(k / cols) * (h + 14.0), w, h)


static func _build_research(m) -> void:
	var s: Dictionary = m.save
	for k in LabDB.IDS.size():
		var id: String = LabDB.IDS[k]
		var d: Dictionary = LabDB.DEFS[id]
		var lvl: int = Labs.level(s, id)
		var tip: String = "%s  Lv%d/%d\n%s\nNext: %s coins (instant)" % [String(d["name"]), lvl, LabDB.max_of(id), String(d["effect"]), Kit.fmt(float(Labs.cost(id, lvl)))]
		Kit.hit(m, _lab_rect(m, k), func() -> void: m.meta_act(Labs.start(m.save, id, m.now())), tip, "LAB " + id, Labs.can_start(s, id), Kit.LAB)


static func _draw_research(m, cr: Rect2) -> void:
	var s: Dictionary = m.save
	Kit.t(m, "RESEARCH", Vector2(cr.position.x + 20, cr.position.y + 40), 26, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 500.0)
	Kit.t(m, "Instant, permanent upgrades. Needs a Research Hall in the Outpost.", Vector2(cr.position.x + 220, cr.position.y + 38), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 240)
	for k in LabDB.IDS.size():
		var id2: String = LabDB.IDS[k]
		var d2: Dictionary = LabDB.DEFS[id2]
		var r2: Rect2 = _lab_rect(m, k)
		var lvl: int = Labs.level(s, id2)
		var mx: int = LabDB.max_of(id2)
		var ok: bool = Labs.can_start(s, id2)
		Kit.panel(m, r2, Kit.LAB if ok else Kit.EDGE, Kit.PANEL2 if ok else Color("1c2128"))
		if not Kit.icon(m, "lab_" + id2, Rect2(r2.position.x + 12, r2.position.y + 14, 52, 52), Color.WHITE if ok or lvl >= mx else Color(1, 1, 1, 0.5)):
			Kit.icon(m, "icon_lab", Rect2(r2.position.x + 12, r2.position.y + 14, 52, 52), Color.WHITE if ok else Color(1, 1, 1, 0.5))
		Kit.t(m, String(d2["name"]), Vector2(r2.position.x + 76, r2.position.y + 34), 19, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, r2.size.x - 90)
		Kit.t(m, "Lv %d / %d" % [lvl, mx], Vector2(r2.end.x - 12, r2.position.y + 34), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 100.0)
		Kit.wrap(m, String(d2["effect"]), Vector2(r2.position.x + 76, r2.position.y + 48), 14, Kit.DIM, r2.size.x - 90, 2)
		var status: String = "%s coins  ·  instant" % Kit.fmt(float(Labs.cost(id2, lvl)))
		var sc: Color = Kit.GOLD
		if lvl >= mx:
			status = "MAX"
			sc = Kit.GREEN
		Kit.t(m, status, Vector2(r2.position.x + 76, r2.end.y - 14), 16, sc, HORIZONTAL_ALIGNMENT_LEFT, r2.size.x - 90)


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
		Kit.btn(m, "Done" if claimed else "Claim +%d" % int(e.get("coins", 0)), Rect2(r.end.x - 200, r.position.y + 26, 180, 50), func() -> void: m.meta_act(Missions.claim(m.save, idx)), "Claim the mission's coin reward", Missions.is_done(e) and not claimed, Kit.GOLD, "MCLAIM %d" % k, "cur_coin")
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
		var icon_id: String = "chest" if bool(rw.get("chest", false)) else "cur_coin"
		Kit.icon(m, icon_id, Rect2(r.get_center().x - 22, r.position.y + 38, 44, 44))
		Kit.t(m, Kit.fmt(float(rw["coins"])), Vector2(r.get_center().x, r.end.y - 16), 19, Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
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
	Kit.t(m, "+%d coins when all 3 are claimed" % TuneRef.int_of("mission_bonus_coins", 200), Vector2(br.position.x + 90, br.position.y + 72), 16, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, 500.0)
	var day: int = Missions.day_of(t)
	Kit.t(m, "New missions in %s" % Kit.dur((day + 1) * 86400 - t), Vector2(cr.end.x - 20, cr.position.y + 274), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 400.0)
