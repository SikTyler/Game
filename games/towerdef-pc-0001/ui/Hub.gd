extends RefCounted
## The hub between runs (REDESIGN_SPEC §5): a nav row of tabs under the top
## bar — Play, Core Bay, Crates, Outpost, Research, Cards, Missions, Reforge —
## and START RUN. This file owns the nav, the Play tab (active Core, tier
## select, mode, Outpost / research / mission summaries) and the Research,
## Cards and Missions tabs; the other tabs live in CoreBay / CrateView /
## FactoryView / ReforgeView. View only: buttons call pure modules and hand
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
const FactoryView := preload("res://ui/FactoryView.gd")
const Factory := preload("res://Factory.gd")
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
			return FactoryView._bank_total(s) >= 1.0
		"missions":
			return Missions.has_claimable(s) or Missions.streak_available(s, t)
		"reforge":
			return Reforge.can_reforge(s)
		"bay":
			return Cores.can_level(s, Cores.active(s))
	return false


## FB1: the home screen IS the Outpost ("play" and "outpost" both show it).
static func is_home(tab: String) -> bool:
	return tab == "play" or tab == "outpost"


## Screens reached from the Outpost's buildings: [tab, title, icon].
const SCREENS: Dictionary = {
	"bay": ["Core Bay", "core_open"], "crates": ["Crates", "crate_field"], "research": ["Research Lab", "icon_lab"],
	"cards": ["Card Hall", "tab_cards"], "missions": ["Missions", "tab_missions"], "reforge": ["Reforge", "rf_root"],
}


## Small nav buttons (left): home, Missions, Reforge.
static func nav_rect(m, k: int) -> Rect2:
	var w: float = 190.0 if k == 0 else 160.0
	var x: float = 8.0 + (0.0 if k == 0 else 198.0 + float(k - 1) * 168.0)
	return Rect2(x, m.TOP_H + 8.0, w, m.NAV_H - 14.0)


static func start_rect(m) -> Rect2:
	return Rect2(m.vw - START_W - 8.0, m.TOP_H + 6.0, START_W, m.NAV_H - 10.0)


static func build(m) -> void:
	var home: bool = is_home(String(m.tab))
	Kit.btn(m, "Outpost" if home else "Back to Outpost", nav_rect(m, 0), func() -> void: m.set_tab("play"), "Your Outpost: build, collect, and click the Core Bay, Crates, Research and Card Hall buildings", true, Kit.RUST if home else Kit.NEUTRAL, "DTAB Outpost", "op_relay_1", 16)
	Kit.btn(m, "Missions", nav_rect(m, 1), func() -> void: m.set_tab("missions"), "Daily missions and the login streak", true, Kit.RUST if m.tab == "missions" else Kit.NEUTRAL, "DTAB Missions", "tab_missions", 15)
	Kit.btn(m, "Reforge", nav_rect(m, 2), func() -> void: m.set_tab("reforge"), "Core Reforge: reset for Shards and permanent nodes", true, Kit.RUST if m.tab == "reforge" else Kit.NEUTRAL, "DTAB Reforge", "rf_root", 15)
	# deploy cluster (right): tier < T > · Modes · START RUN
	var sr: Rect2 = start_rect(m)
	var ny: float = m.TOP_H + 8.0
	var nh: float = m.NAV_H - 14.0
	Kit.btn(m, "<", Rect2(sr.position.x - 330, ny, 46, nh), func() -> void: m.shift_tier(-1), "Previous tier", m.view_tier > 1, Kit.NEUTRAL, "<", "", 22)
	Kit.btn(m, ">", Rect2(sr.position.x - 194, ny, 46, nh), func() -> void: m.shift_tier(1), "Next tier (tougher enemies, more coins)", m.view_tier < mini(Tiers.tier_max(), Tiers.highest(m.save) + 1), Kit.NEUTRAL, ">", "", 22)
	Kit.btn(m, "Modes", Rect2(sr.position.x - 140, ny, 130, nh), func() -> void: m.set_overlay("modes"), "Pick Normal or Endless and stack challenge modifiers for bonus coins", true, Kit.MAG, "MODES", "icon_mod", 15)
	Kit.btn(m, "PLAY  T%d" % m.view_tier, sr, func() -> void: m.start_run(), "Start a run on Tier %d with the %s Core" % [m.view_tier, String(CoreDB.get_def(Cores.active(m.save))["name"])], Tiers.is_unlocked(m.save, m.view_tier), Kit.RUST, "DSTART", "", 20)
	if home:
		FactoryView.build(m)
		return
	match String(m.tab):
		"bay":
			CoreBay.build(m)
		"crates":
			CrateView.build(m)
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
	var home0: bool = is_home(String(m.tab))
	if home0:
		FactoryView.draw(m, cr)   # first: the nav row below paints over any map overdraw
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
	if not home and SCREENS.has(String(m.tab)):
		var sc: Array = SCREENS[String(m.tab)]
		var cx: float = (nav_rect(m, 2).end.x + sr.position.x - 330.0) * 0.5
		Kit.icon(m, String(sc[1]), Rect2(cx - 120, m.TOP_H + 12, 34, 34))
		Kit.t(m, String(sc[0]).to_upper(), Vector2(cx - 78, m.TOP_H + 38), 22, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
	if home:
		for id in ["bay", "crates", "research", "cards"]:
			var lr: Rect2 = FactoryView.landmark_rect(m, String(id))
			if m.overlay == "" and m.offline_offer.is_empty() and badge(m, String(id)) and FactoryView.map_rect(m).has_point(lr.position + Vector2(lr.size.x - 12, 12)):
				m.draw_circle(lr.position + Vector2(lr.size.x - 12, 12), 8.0, Kit.ENEMY)
	else:
		match String(m.tab):
			"bay":
				CoreBay.draw(m, cr)
			"crates":
				CrateView.draw(m, cr)
			"research":
				_draw_research(m, cr)
			"cards":
				_draw_cards(m, cr)
			"missions":
				_draw_missions(m, cr)
			"reforge":
				ReforgeView.draw(m, cr)
	var nb: Array = [["outpost", 0], ["missions", 1], ["reforge", 2]]
	for e in nb:
		if m.overlay == "" and m.offline_offer.is_empty() and badge(m, String((e as Array)[0])):
			var r: Rect2 = nav_rect(m, int((e as Array)[1]))
			m.draw_circle(Vector2(r.end.x - 10, r.position.y + 10), 6.0, Kit.ENEMY)


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


## WP3: factory technology lives in the Research Lab too (a row under the projects).
static func _tech_rect(m, k: int) -> Rect2:
	var cr: Rect2 = m.content_rect()
	var cols: int = 5
	var w: float = (cr.size.x - 40.0 - float(cols - 1) * 10.0) / float(cols)
	var top: float = _lab_rect(m, LabDB.IDS.size() - 1).end.y + 52.0
	return Rect2(cr.position.x + 20.0 + float(k % cols) * (w + 10.0), top + float(k / cols) * 52.0, w, 46.0)


static func _build_research(m) -> void:
	var s: Dictionary = m.save
	for k in Factory.DB.TECH_IDS.size():
		var tid: String = Factory.DB.TECH_IDS[k]
		var td: Dictionary = Factory.DB.TECH[tid]
		var have: bool = Factory.has_tech(s, tid)
		var label: String = ("%s  (done)" % String(td["name"])) if have else ("%s  %s%s" % [String(td["name"]), Kit.fmt(float(td["coins"])), (" + %d data" % int(td["data"])) if int(td["data"]) > 0 else ""])
		var tip: String = "%s\n%s%s" % [String(td["name"]), String(td["desc"]), ("\nRequires %s" % String((Factory.DB.TECH[String(td["req"])] as Dictionary)["name"])) if String(td["req"]) != "" else ""]
		Kit.btn(m, label, _tech_rect(m, k), func() -> void: m.meta_act(Factory.research(m.save, tid)), tip, Factory.tech_can(s, tid), Kit.GREEN if have else Kit.LAB, "FTECH " + tid, "", 14)
	var t: int = m.now()
	var run: Array = Labs.running(s)
	for k in run.size():
		var slot: int = k
		var _qr: Rect2 = _queue_rect(m, slot)
	for k in LabDB.IDS.size():
		var id: String = LabDB.IDS[k]
		var d: Dictionary = LabDB.DEFS[id]
		var lvl: int = Labs.level(s, id)
		var tip: String = "%s  Lv%d/%d\n%s\nNext: %s coins (instant)" % [String(d["name"]), lvl, LabDB.max_of(id), String(d["effect"]), Kit.fmt(float(Labs.cost(id, lvl)))]
		Kit.hit(m, _lab_rect(m, k), func() -> void: m.meta_act(Labs.start(m.save, id, m.now())), tip, "LAB " + id, Labs.can_start(s, id), Kit.LAB)


static func _draw_research(m, cr: Rect2) -> void:
	var s: Dictionary = m.save
	var t: int = m.now()
	var run: Array = Labs.running(s)
	Kit.t(m, "RESEARCH HALL", Vector2(cr.position.x + 20, cr.position.y + 40), 26, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 500.0)
	Kit.t(m, "Queues follow the Research Lab's level (upgrade it at the factory's Core Relay: 1 / 2 / 3 queues at Lv1 / 4 / 8).", Vector2(cr.position.x + 300, cr.position.y + 38), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 320)
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
	var tr0: Rect2 = _tech_rect(m, 0)
	Kit.head(m, "FACTORY TECHNOLOGY  ·  %d research data (Data Cards at the Core Relay)" % int(Factory._f(s).get("data", 0)), Vector2(cr.position.x + 20, tr0.position.y - 14), cr.size.x - 40, Kit.LAB)
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
		var status: String = "%s coins  ·  instant" % Kit.fmt(float(Labs.cost(id2, lvl)))
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
			Kit.btn(m, "Buy slot\n%s coins" % Kit.fmt(float(Cards.slot_cost(s))), _eq_rect(m, k), func() -> void: m.meta_act(Cards.buy_slot(m.save)), "Unlock another card slot", int(s["coins"]) >= Cards.slot_cost(s), Kit.GOLD, "CSLOT", "cur_coin", 18)
	for k in CardDB.IDS.size():
		var id2: String = CardDB.IDS[k]
		if own.has(id2):
			var is_eq: bool = eq.has(id2)
			var cb: Callable = func() -> void: m.meta_act(Cards.unequip(m.save, id2) if Cards.equipped(m.save).has(id2) else Cards.equip(m.save, id2))
			Kit.hit(m, _card_rect(m, k), cb, "%s\n%s\nClick to %s" % [String((CardDB.DEFS[id2] as Dictionary)["name"]), CardDB.describe(id2, Cards.level(s, id2)), "unequip" if is_eq else "equip"], "CARD " + id2, is_eq or eq.size() < n)
	var cr: Rect2 = m.content_rect()
	Kit.btn(m, "Open Chest  ·  %s coins" % Kit.fmt(float(Cards.chest_cost())), Rect2(cr.get_center().x - 220, cr.end.y - 84, 440, 64), func() -> void: m.meta_act(Cards.open_chest(m.save, m.meta_rng)), "Open a card chest (new card or a copy)", int(s["coins"]) >= Cards.chest_cost(), Kit.GOLD, "Open Chest", "chest", 22)


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
