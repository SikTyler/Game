extends RefCounted
## The hub between runs (V2): a nav row under the top bar — Outpost (home),
## Core, Forge, Research, Reforge — and the deploy cluster (tier, modes,
## PLAY); Missions is a top-bar button. This file owns the nav and the Research and Missions tabs; the
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
const ForgeView := preload("res://ui/ForgeView.gd")
const Gear := preload("res://Gear.gd")

## Tab hotkeys: [action, tab].
const TAB_KEYS: Array = [["tab_base", "play"], ["tab_outpost", "outpost"], ["tab_core", "core"], ["tab_forge", "forge"], ["tab_labs", "research"], ["tab_missions", "missions"], ["tab_reforge", "reforge"]]
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
		"forge":
			return Gear.new_count(s) > 0
	return false


## FB1: the home screen IS the Outpost ("play" and "outpost" both show it).
static func is_home(tab: String) -> bool:
	return tab == "play" or tab == "outpost"


## Top menu (left): OUTPOST (home), CORE, FORGE, RESEARCH, REFORGE; the
## deploy cluster (tier, Modes, PLAY) sits right. Missions moved to the top
## bar (Desktop).
const NAV: Array = [
	["core", "CORE", "core_open", "The Core: its Weapon, Module sockets, look and level"],
	["forge", "FORGE", "icon_gear", "The Forge: forge, upgrade, merge, reroll and lock your Weapons and Modules"],
	["research", "RESEARCH", "icon_lab", "Research: permanent upgrades (instant)"],
	["reforge", "REFORGE", "rf_root", "Core Reforge: reset for Shards and permanent nodes"],
]
## Tabs not playable yet (shown locked).
const LOCKED: Array = []
const OUTPOST_W: float = 172.0


static func nav_w(m) -> float:
	var avail: float = start_rect(m).position.x - 340.0 - (OUTPOST_W + 20.0)
	return clampf(avail / float(NAV.size()) - 8.0, 96.0, 156.0)


static func nav_rect(m, k: int) -> Rect2:
	var w: float = OUTPOST_W if k == 0 else nav_w(m)
	var x: float = 12.0 + (0.0 if k == 0 else OUTPOST_W + 8.0 + float(k - 1) * (nav_w(m) + 8.0))
	return Rect2(x, m.TOP_H + 8.0, w, m.NAV_H - 16.0)


static func start_rect(m) -> Rect2:
	return Rect2(m.vw - START_W - 12.0, m.TOP_H + 6.0, START_W, m.NAV_H - 12.0)


## Tab button styling: the active tab is filled cyan with a bright underline.
static func _tab(m, label: String, r: Rect2, id: String, tip: String, key: String, icon_id: String, on: bool, fsize: int) -> void:
	var b: Button = Kit.btn(m, label, r, func() -> void: m.set_tab(id), tip, not (id in LOCKED), Kit.CYAN if on else Kit.NEUTRAL, key, icon_id, fsize)
	if on:
		var st: StyleBoxFlat = Kit.sb(Kit.CYAN, Kit.tint(Kit.CYAN, 0.2), 2, 8, 1.1).duplicate()
		st.border_width_bottom = 4
		b.add_theme_stylebox_override("normal", st)
		b.add_theme_stylebox_override("hover", st)
		b.add_theme_color_override("font_color", Color.WHITE)
	else:
		b.add_theme_stylebox_override("normal", Kit.sb(Color(Kit.EDGE2, 0.9), Color(Kit.BG2, 0.75), 1, 8))
		b.add_theme_color_override("font_color", Kit.DIM)
	if id in LOCKED:
		# "SOON" pill on the locked tab (a child Label so it draws over the button)
		var tag := Label.new()
		tag.text = "SOON"
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_theme_font_override("font", Kit.Fonts.head())
		tag.add_theme_font_size_override("font_size", 14)
		tag.add_theme_color_override("font_color", Color.WHITE)
		var st2: StyleBoxFlat = Kit.sb(Kit.MAGENTA, Kit.tint(Kit.MAGENTA, 0.45), 1, 8, 0.5).duplicate()
		st2.content_margin_left = 6
		st2.content_margin_right = 6
		tag.add_theme_stylebox_override("normal", st2)
		tag.position = Vector2(r.size.x - 52.0, -8.0)
		tag.size = Vector2(48, 20)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(tag)


static func build(m) -> void:
	var home: bool = is_home(String(m.tab))
	var fs: int = 16 if nav_w(m) >= 140.0 else 14
	_tab(m, "OUTPOST", nav_rect(m, 0), "play", "Your Outpost: build, upgrade and collect", "DTAB Outpost", "op_relay_1", home, 16)
	for k in NAV.size():
		var nv: Array = NAV[k]
		var tid: String = String(nv[0])
		_tab(m, String(nv[1]), nav_rect(m, k + 1), tid, String(nv[3]), "DTAB " + String(nv[1]).capitalize(), String(nv[2]), m.tab == tid, fs)
	# deploy cluster (right): < TIER > · Modes · PLAY
	var sr: Rect2 = start_rect(m)
	var ny: float = m.TOP_H + 8.0
	var nh: float = m.NAV_H - 16.0
	Kit.btn(m, "<", Rect2(sr.position.x - 330, ny, 46, nh), func() -> void: m.shift_tier(-1), "Previous tier", m.view_tier > 1, Kit.NEUTRAL, "<", "", 22)
	Kit.btn(m, ">", Rect2(sr.position.x - 194, ny, 46, nh), func() -> void: m.shift_tier(1), "Next tier (tougher enemies, more coins)", m.view_tier < mini(Tiers.tier_max(), Tiers.highest(m.save) + 1), Kit.NEUTRAL, ">", "", 22)
	Kit.btn(m, "Modes", Rect2(sr.position.x - 140, ny, 128, nh), func() -> void: m.set_overlay("modes"), "Pick Normal or Endless and stack challenge modifiers for bonus coins", true, Kit.MAGENTA, "MODES", "icon_mod", 15)
	var ok: bool = Tiers.is_unlocked(m.save, m.view_tier)
	var pb: Button = Kit.btn(m, "PLAY  T%d" % m.view_tier, sr, func() -> void: m.start_run(), "Start a run on Tier %d (Core Lv%d)" % [m.view_tier, Cores.level(m.save)], ok, Kit.GOLD, "DSTART", "", 24)
	pb.add_theme_font_override("font", Kit.Fonts.bold())
	pb.add_theme_stylebox_override("normal", Kit.sb(Kit.GOLD, Kit.MAGENTA.darkened(0.45), 2, 10, 1.2))
	pb.add_theme_stylebox_override("hover", Kit.sb(Color.WHITE, Kit.MAGENTA.darkened(0.25), 2, 10, 2.0))
	pb.add_theme_stylebox_override("pressed", Kit.sb(Color.WHITE, Kit.MAGENTA.darkened(0.1), 2, 10, 2.2))
	if home:
		OutpostView.build(m)
		return
	match String(m.tab):
		"core":
			CoreView.build(m)
		"forge":
			ForgeView.build(m)
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
	var nr := Rect2(0, m.TOP_H, m.vw, m.NAV_H)
	m.draw_polygon(PackedVector2Array([nr.position, Vector2(nr.end.x, nr.position.y), nr.end, Vector2(nr.position.x, nr.end.y)]), PackedColorArray([Kit.BG2, Kit.BG2, Kit.BG, Kit.BG]))
	m.draw_line(Vector2(0, nr.end.y), Vector2(m.vw, nr.end.y), Kit.EDGE2, 1.0)
	var home: bool = is_home(String(m.tab))
	# PLAY: pulsing magenta halo behind the button (the button draws on top)
	var sr: Rect2 = start_rect(m)
	var pulse: float = 0.5 + 0.5 * sin(m.t_anim * 2.4)
	if Tiers.is_unlocked(m.save, m.view_tier):
		Kit.panel_glow(m, sr.grow(1.0 + 2.0 * pulse), Color(Kit.MAGENTA, 0.5 + 0.4 * pulse), Color(0, 0, 0, 0), 0.8 + 1.0 * pulse, 1)
	# tier readout between < and >
	var tx: float = sr.position.x - 239.0
	var vt: int = m.view_tier
	var unlocked: bool = Tiers.is_unlocked(m.save, vt)
	Kit.th(m, "TIER %d" % vt, Vector2(tx, m.TOP_H + 29), 20, Kit.TEXT if unlocked else Kit.ENEMY, HORIZONTAL_ALIGNMENT_CENTER, 90.0)
	Kit.t(m, ("x%.1f coins" % Tiers.coin_mult(vt)) if unlocked else "locked", Vector2(tx, m.TOP_H + 48), 14, Kit.GOLD if unlocked else Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, 92.0)
	m.stat_tips.append([Rect2(tx - 45, m.TOP_H + 8, 90, m.NAV_H - 14), ("Tier %d: coins x%.1f, enemy HP x%.1f" % [vt, Tiers.coin_mult(vt), Tiers.hp_mult(vt)]) if unlocked else Tiers.requirement(vt)])
	if not home:
		match String(m.tab):
			"core":
				CoreView.draw(m, cr)
			"forge":
				ForgeView.draw(m, cr)
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
			badge_dot(m, Vector2(r.end.x - 9, r.position.y + 9))


## Notification dot: a magenta pip with a soft halo.
static func badge_dot(m, p: Vector2) -> void:
	m.draw_circle(p, 9.0, Color(Kit.MAGENTA, 0.25 + 0.15 * sin(m.t_anim * 4.0)))
	m.draw_circle(p, 5.5, Kit.MAGENTA)
	m.draw_circle(p + Vector2(-1.5, -1.5), 1.8, Color(1, 1, 1, 0.8))


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
		Kit.panel(m, r2, Kit.LAB if ok else Kit.EDGE, Kit.CARD if ok else Kit.PANEL)
		var ft: float = float(m.t_anim) - float(m.res_focus_t)
		if String(m.res_focus) == id2 and ft < 2.5:
			Kit.panel_glow(m, r2.grow(3.0), Kit.GOLD, Color(Kit.GOLD, 0.08), 1.0 + 1.5 * (0.5 + 0.5 * sin(ft * 9.0)), 3)
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
		Kit.panel(m, r, Kit.GOLD if is_next else (Kit.GREEN if done else Kit.EDGE), Kit.tint(Kit.GREEN, 0.16) if done else Kit.PANEL)
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
