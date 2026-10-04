extends RefCounted
## Base-screen meta tabs (Labs / Cards / Missions) for Main.gd. View only:
## every button calls a Labs / Cards / Missions action and hands the returned
## events to Main.meta_act(). `m` is the Main node (left untyped on purpose:
## Main is not a class_name and preloading it here would be cyclic). Draw
## functions are only called from inside Main._draw().
## Layout band: tab content y 150-1004 (SYSTEMS §13).

const Labs := preload("res://Labs.gd")
const Cards := preload("res://Cards.gd")
const Missions := preload("res://Missions.gd")
const LabDB := preload("res://data/LabDB.gd")
const CardDB := preload("res://data/CardDB.gd")
const MissionDB := preload("res://data/MissionDB.gd")
const TuneRef := preload("res://Tune.gd")

const TEXT: Color = Color("e9edf2")
const DIM: Color = Color("9aa6b2")
const GOLD: Color = Color("f2c94c")
const GEM: Color = Color("5ad1f0")
const GREEN: Color = Color("6bd46b")
const LAB_COL: Color = Color("b48cff")
const SLOT_Y: float = 196.0
const SLOT_H: float = 78.0
const TRACK_Y: float = 524.0


# ------------------------------------------------------------------ LABS
static func build_labs(m) -> void:
	var s: Dictionary = m.save
	var t: int = m.now()
	var run: Array = Labs.running(s)
	for k in Labs.MAX_SLOTS:
		var y: float = SLOT_Y + float(k) * SLOT_H
		if k < run.size():
			var rc: int = Labs.rush_cost(s, k, t)
			var slot: int = k
			if rc > 0:
				m._btn("Rush %d gem%s" % [rc, "" if rc == 1 else "s"], Rect2(548, y + 4, 156, 66), func() -> void: m.meta_act(Labs.rush(m.save, slot, m.now())), int(s["gems"]) >= rc, GEM).add_theme_font_size_override("font_size", 20)
	for k in LabDB.IDS.size():
		var id: String = LabDB.IDS[k]
		var d: Dictionary = LabDB.DEFS[id]
		var lvl: int = Labs.level(s, id)
		var mx: int = LabDB.max_of(id)
		var status: String = "%d coins  ·  %s" % [Labs.cost(id, lvl), m.fmt_dur(Labs.duration(s, id, lvl))]
		var sc: Color = GOLD
		if Labs.is_running(s, id):
			status = "RESEARCHING"
			sc = LAB_COL
		elif lvl >= mx:
			status = "MAX"
			sc = GREEN
		var r := Rect2(16.0 + float(k % 2) * 348.0, TRACK_Y + float(k / 2) * 96.0, 340, 90)
		var b: Button = m._card(r, [["%s  Lv%d/%d" % [String(d["name"]), lvl, mx], 20, TEXT], [String(d["effect"]), 18, DIM], [status, 18, sc]], "lab_" + id, func() -> void: m.meta_act(Labs.start(m.save, id, m.now())), Labs.can_start(s, id), LAB_COL, "LAB " + id, "row", 44.0)
		for c in b.get_children():
			if c is Label:
				(c as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
				(c as Label).clip_text = true


static func draw_labs(m, t: int) -> void:
	var s: Dictionary = m.save
	var run: Array = Labs.running(s)
	m._text("RESEARCH HALL — research runs in real time", Vector2(360, 182), 22, TEXT)
	for k in Labs.MAX_SLOTS:
		var y: float = SLOT_Y + float(k) * SLOT_H
		var r := Rect2(16, y, 688, 72)
		if k < run.size():
			var e: Dictionary = run[k]
			var id: String = String(e["track"])
			var d: Dictionary = LabDB.DEFS.get(id, {})
			m._panel(r, LAB_COL)
			if not m._icon("lab_" + id, Rect2(26, y + 12, 48, 48)):
				m.draw_circle(Vector2(50, y + 36), 18.0, LAB_COL)
			m._text("%s -> Lv%d" % [String(d.get("name", id)), int(e["to_lvl"])], Vector2(86, y + 30), 20, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
			var rem: int = maxi(0, int(e["end"]) - t)
			m._text("DONE" if rem <= 0 else m.fmt_dur(rem), Vector2(536, y + 30), 20, GREEN if rem <= 0 else GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 140.0)
			m._bar(Rect2(86, y + 42, 450, 16), Labs.progress(s, k, t), LAB_COL)
		elif k < Labs.slots(s):
			m._panel(r, Color("3a434e"))
			m._text("Empty slot — tap a track below", Vector2(360, y + 44), 20, DIM)
		else:
			m._panel(r, Color("2a3038"), Color("1a1f25"))
			m._icon("icon_lock", Rect2(28, y + 16, 40, 40), Color(1, 1, 1, 0.6))
			m._text("Research Hall L%d opens this queue" % (4 if k == 1 else 8), Vector2(84, y + 44), 20, DIM, HORIZONTAL_ALIGNMENT_LEFT, 420.0)
	m._text("RESEARCH TRACKS", Vector2(360, TRACK_Y - 6), 18, DIM)


# ----------------------------------------------------------------- CARDS
static func build_cards(m) -> void:
	var s: Dictionary = m.save
	var eq: Array = Cards.equipped(s)
	var own: Dictionary = Cards.owned(s)
	var n: int = Cards.slots(s)
	for k in Cards.MAX_SLOTS:
		var r := Rect2(16.0 + float(k) * 140.0, 200, 130, 150)
		if k < eq.size():
			var id: String = String(eq[k])
			var d: Dictionary = CardDB.DEFS[id]
			m._card(r, [[String(d["name"]), 18, TEXT], ["Lv%d" % Cards.level(s, id), 18, GOLD]], "card_" + id.substr(2), func() -> void: m.meta_act(Cards.unequip(m.save, id)), true, GOLD, "EQ " + id, "tall", 56.0)
		elif k == n:
			m._card(r, [["Buy slot", 18, TEXT], ["%d gems" % Cards.slot_cost(s), 18, GEM]], "icon_lock", func() -> void: m.meta_act(Cards.buy_slot(m.save)), int(s["gems"]) >= Cards.slot_cost(s), GEM, "CSLOT", "tall", 48.0)
	for k in CardDB.IDS.size():
		var id2: String = CardDB.IDS[k]
		var r2 := Rect2(16.0 + float(k % 4) * 174.0, 404.0 + float(k / 4) * 206.0, 166, 198)
		if own.has(id2):
			var d2: Dictionary = CardDB.DEFS[id2]
			var e: Dictionary = own[id2]
			var lvl: int = int(e["lvl"])
			var is_eq: bool = eq.has(id2)
			var prog: String = "MAX" if lvl >= CardDB.MAX_LVL else "%d/%d copies" % [int(e["copies"]), lvl]
			var cb: Callable = func() -> void: m.meta_act(Cards.unequip(m.save, id2) if Cards.equipped(m.save).has(id2) else Cards.equip(m.save, id2))
			m._card(r2, [[String(d2["name"]) + ("  ✓" if is_eq else ""), 20, GOLD if is_eq else TEXT], [CardDB.describe(id2, lvl), 18, DIM], ["Lv%d  ·  %s" % [lvl, prog], 18, GOLD]], "card_" + id2.substr(2), cb, is_eq or eq.size() < n, GOLD if is_eq else Color("4a525c"), "CARD " + id2, "tall", 60.0)
		else:
			m._card(r2, [["Not found yet", 18, DIM]], "card_back", func() -> void: pass, false, Color("4a525c"), "LOCKED " + id2, "tall", 72.0)
	m._card(Rect2(150, 824, 420, 96), [["Open Chest", 24, TEXT], ["%d gems" % Cards.chest_cost(), 20, GEM]], "chest", func() -> void: m.meta_act(Cards.open_chest(m.save, m.meta_rng)), int(s["gems"]) >= Cards.chest_cost(), GEM, "Open Chest", "row", 64.0)


static func draw_cards(m) -> void:
	var s: Dictionary = m.save
	var eq: Array = Cards.equipped(s)
	var n: int = Cards.slots(s)
	m._text("EQUIPPED  %d / %d slots" % [eq.size(), n], Vector2(360, 186), 22, TEXT)
	for k in Cards.MAX_SLOTS:
		var r := Rect2(16.0 + float(k) * 140.0, 200, 130, 150)
		if k >= eq.size() and k < n:
			m._panel(r, Color("4a525c"), Color("1a1f25"))
			m._text("Empty", Vector2(r.get_center().x, r.get_center().y + 8), 20, DIM)
		elif k > n:
			m._panel(r, Color("2a3038"), Color("161a1f"))
			m._icon("icon_lock", Rect2(r.get_center() - Vector2(20, 20), Vector2(40, 40)), Color(1, 1, 1, 0.35))
	m._text("COLLECTION — tap a card to equip / unequip", Vector2(360, 390), 20, DIM)
	m._text("Gems come from bosses, missions & streaks", Vector2(360, 954), 18, DIM)


# -------------------------------------------------------------- MISSIONS
static func _streak_done(s: Dictionary, k: int, t: int) -> bool:
	var st: Dictionary = s["streak"]
	if Missions.streak_available(s, t):
		return k < Missions.streak_next_day(s, t) - 1
	return k < int(st["day_idx"])


static func build_missions(m) -> void:
	var s: Dictionary = m.save
	var t: int = m.now()
	var avail: bool = Missions.streak_available(s, t)
	var lbl: String = "Claim Day %d" % Missions.streak_next_day(s, t) if avail else "Claimed — come back tomorrow"
	m._btn(lbl, Rect2(150, 318, 420, 88), func() -> void: m.meta_act(Missions.streak_claim(m.save, m.now())), avail, Color("ff9f5a"))
	var lst: Array = Missions.list(s)
	for k in lst.size():
		var e: Dictionary = lst[k]
		var y: float = 466.0 + float(k) * 122.0
		var idx: int = k
		var done: bool = Missions.is_done(e)
		var claimed: bool = bool(e["claimed"])
		m._btn("Done" if claimed else "Claim", Rect2(548, y + 12, 156, 90), func() -> void: m.meta_act(Missions.claim(m.save, idx)), done and not claimed, GEM).set_meta("key", "MCLAIM %d" % k)
	var bonus: bool = Missions.all_claimed(s) and not bool((s["missions"] as Dictionary)["bonus_claimed"])
	var bdone: bool = bool((s["missions"] as Dictionary)["bonus_claimed"])
	m._btn("Done" if bdone else "Claim", Rect2(548, 840, 156, 90), func() -> void: m.meta_act(Missions.claim_bonus(m.save)), bonus, GEM).set_meta("key", "BONUS")


static func draw_missions(m, t: int) -> void:
	var s: Dictionary = m.save
	m._text("LOGIN STREAK", Vector2(360, 184), 22, TEXT)
	var nxt: int = Missions.streak_next_day(s, t)
	var avail: bool = Missions.streak_available(s, t)
	for k in 7:
		var r := Rect2(16.0 + float(k) * 99.0, 198, 92, 110)
		var done: bool = _streak_done(s, k, t)
		var is_next: bool = avail and k == nxt - 1
		m._panel(r, GOLD if is_next else (GREEN if done else Color("3a434e")), Color(0.15, 0.25, 0.15) if done else Color("1f252c"))
		m._text("Day %d" % (k + 1), Vector2(r.get_center().x, 222), 18, TEXT if (done or is_next) else DIM)
		var rw: Dictionary = MissionDB.STREAK[k]
		var icon: String = "chest" if bool(rw.get("chest", false)) else ("icon_gem" if int(rw["gems"]) > 0 else "icon_coin")
		m._icon(icon, Rect2(r.get_center().x - 18, 230, 36, 36))
		var amt: String = "%d" % int(rw["gems"]) if int(rw["gems"]) > 0 else "%d" % int(rw["coins"])
		m._text(amt, Vector2(r.get_center().x, 294), 20, GEM if int(rw["gems"]) > 0 else GOLD)
	m._text("DAILY MISSIONS", Vector2(360, 452), 22, TEXT)
	var lst: Array = Missions.list(s)
	for k in lst.size():
		var e: Dictionary = lst[k]
		var y: float = 466.0 + float(k) * 122.0
		var tpl: String = String(e["tpl"])
		var done: bool = Missions.is_done(e)
		m._panel(Rect2(16, y, 688, 114), GREEN if done else Color("3a434e"))
		if not m._icon("mis_" + tpl, Rect2(28, y + 30, 52, 52)):
			m.draw_circle(Vector2(54, y + 56), 20.0, GEM)
		m._text(MissionDB.text(tpl, int(e["target"])), Vector2(94, y + 36), 20, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 440.0)
		m._bar(Rect2(94, y + 50, 430, 18), float(e["prog"]) / float(maxi(1, int(e["target"]))), GREEN if done else GEM)
		m._text("%d / %d" % [int(e["prog"]), int(e["target"])], Vector2(94, y + 96), 18, DIM, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
		m._icon("icon_gem", Rect2(410, y + 76, 26, 26))
		m._text("+%d" % int(e["gems"]), Vector2(442, y + 96), 20, GEM, HORIZONTAL_ALIGNMENT_LEFT, 80.0)
	m._panel(Rect2(16, 834, 688, 102), GOLD if Missions.all_claimed(s) else Color("3a434e"))
	m._icon("chest", Rect2(28, 853, 60, 60))
	m._text("All-clear bonus", Vector2(100, 876), 22, TEXT, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
	m._text("+%d gems when all 3 are claimed" % TuneRef.int_of("mission_bonus_gems", 5), Vector2(100, 910), 18, GEM, HORIZONTAL_ALIGNMENT_LEFT, 440.0)
	var day: int = Missions.day_of(t)
	m._text("New missions in %s" % m.fmt_dur((day + 1) * 86400 - t), Vector2(360, 976), 18, DIM)

