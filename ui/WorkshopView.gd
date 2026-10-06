extends RefCounted
## The Outpost part workshops (V3 parts, design/V3_PARTS.md §3), modals over
## the Outpost opened from a selected building:
##   FABRICATOR  a rotating shop of parts for Scrap (fab:buy:<k>), restocked
##               every few hours or on demand (fab:reroll). Its level adds
##               offers, shortens the restock, lowers prices and lifts rarity.
##   SMELTER     parts melting into Scrap (queued from the Weapon / Core
##               screens' SMELT); finished melts pay out on their own, CLAIM
##               (smelt:claim) does it now.
## Close: ws:close. View only: buttons call Parts and hand events to
## Main.meta_act().

const Parts := preload("res://Parts.gd")
const PartDB := preload("res://data/PartDB.gd")
const PartVis := preload("res://PartVis.gd")
const RarityDB := preload("res://data/RarityDB.gd")
const AffixDB := preload("res://data/AffixDB.gd")
const Cores := preload("res://Cores.gd")
const Kit := preload("res://ui/Kit.gd")

const CARD: Vector2 = Vector2(300, 330)


static func modal(m) -> Rect2:
	var w: float = minf(1180.0, m.vw - 16.0)
	var h: float = minf(900.0, m.vh - 16.0)
	return Rect2(floorf((m.vw - w) * 0.5), floorf((m.vh - h) * 0.5), w, h)


## Offer cards: 3 a row; two rows fit above the bottom bar.
static func offer_rect(m, k: int) -> Rect2:
	var r: Rect2 = modal(m)
	var cols: int = 3
	var gap: float = (r.size.x - 48.0 - float(cols) * CARD.x) / float(cols - 1)
	var h: float = minf(CARD.y, (r.size.y - 112.0 - 92.0) * 0.5 - 62.0)
	return Rect2(r.position.x + 24.0 + float(k % cols) * (CARD.x + gap), r.position.y + 112.0 + float(k / cols) * (h + 62.0), CARD.x, h)


static func _close_rect(m) -> Rect2:
	var r: Rect2 = modal(m)
	return Rect2(r.end.x - 224.0, r.end.y - 70.0, 200.0, 54.0)


# ------------------------------------------------------------------ build

static func build(m) -> void:
	var s: Dictionary = m.save
	var r: Rect2 = modal(m)
	if String(m.overlay) == "fabricator":
		var of: Array = Parts.fab_offers(s, m.now())
		for k in of.size():
			var kk: int = k
			var o: Dictionary = of[k]
			var cr: Rect2 = offer_rect(m, k)
			var why: String = Parts.why_fab_buy(s, k, m.now())
			Kit.btn(m, "SOLD" if bool(o.get("sold", false)) else "BUY  ·  %s" % Kit.fmt(float(Parts.fab_price(s, o))), Rect2(cr.position.x, cr.end.y + 10.0, cr.size.x, 46.0), func() -> void: m.meta_act(Parts.fab_buy(m.save, kk, m.now())),
				"Buy %s for %d Scrap%s" % [String(o["name"]), Parts.fab_price(s, o), "" if why == "" else "\n" + why], why == "", Kit.GOLD, "fab:buy:%d" % k, "cur_scrap", 16)
		Kit.btn(m, "RESTOCK  ·  %d" % Parts.FAB_REROLL, Rect2(r.position.x + 24.0, r.end.y - 70.0, 260.0, 54.0), func() -> void: m.meta_act(Parts.fab_reroll(m.save, m.now())),
			"Roll a fresh stock now for %d Scrap (the timer restarts)" % Parts.FAB_REROLL, int(s.get("scrap", 0)) >= Parts.FAB_REROLL, Kit.MAGENTA, "fab:reroll", "cur_scrap", 17)
	else:
		Kit.btn(m, "CLAIM", Rect2(r.position.x + 24.0, r.end.y - 70.0, 260.0, 54.0), func() -> void: m.meta_act(Parts.smelt_claim(m.save, m.now())),
			"Collect the Scrap of every finished melt (it also pays out on its own)", _ready_scrap(s, m.now()) > 0, Kit.GOLD, "smelt:claim", "cur_scrap", 17)
		Kit.btn(m, "WEAPON PARTS", Rect2(r.position.x + 300.0, r.end.y - 70.0, 240.0, 54.0), func() -> void:
			m.set_overlay("")
			m.set_tab("weapon"), "Pick parts to smelt on the Weapon screen (SMELT)", true, Kit.NEUTRAL, "smelt:weapon", "", 16)
		Kit.btn(m, "CORE PARTS", Rect2(r.position.x + 556.0, r.end.y - 70.0, 240.0, 54.0), func() -> void:
			m.set_overlay("")
			m.set_tab("core"), "Pick parts to smelt on the Core screen (SMELT)", true, Kit.NEUTRAL, "smelt:core", "", 16)
	Kit.btn(m, "CLOSE", _close_rect(m), func() -> void: m.set_overlay(""), "Back to the Outpost", true, Kit.NEUTRAL, "ws:close", "", 18)


static func _ready_scrap(s: Dictionary, now: int) -> int:
	var n: int = 0
	for e in (Parts.block(s)["smelt"] as Array):
		if int((e as Dictionary)["done"]) <= now:
			n += int((e as Dictionary)["scrap"])
	return n


# ------------------------------------------------------------------ draw

static func draw(m) -> void:
	var s: Dictionary = m.save
	var r: Rect2 = modal(m)
	if String(m.overlay) == "fabricator":
		_draw_fab(m, s, r)
	else:
		_draw_smelt(m, s, r)


static func _draw_fab(m, s: Dictionary, r: Rect2) -> void:
	Kit.panel_glow(m, r, Kit.CYAN, Kit.PANEL2, 1.2, 2)
	var lv: int = Parts.fab_level(s)
	Kit.th(m, "FABRICATOR  ·  Lv %d" % lv, Vector2(r.position.x + 28, r.position.y + 50), 30, Kit.CYAN)
	var left: int = maxi(0, Parts.fab_next_refresh(s) - m.now())
	Kit.t(m, "Restocks in %s  ·  %d offers every %.1f h  ·  -%d%% prices  ·  Scrap %s" % [Kit.dur(left), Parts.fab_slots(s), Parts.fab_period_h(s), int(round((1.0 - float(Parts.fab_price(s, {"rar": "common"})) / float(Parts.FAB_PRICE["common"])) * 100.0)), Kit.fmt(float(s.get("scrap", 0)))],
		Vector2(r.position.x + 28, r.position.y + 80), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 56.0)
	var of: Array = Parts.fab_offers(s, m.now())
	var look: Dictionary = Cores.look(s)
	for k in of.size():
		_offer(m, offer_rect(m, k), of[k], look)
	m.stat_tips.append([Rect2(r.position.x + 20.0, r.position.y + 20.0, r.size.x - 40.0, 70.0), "Upgrade the Fabricator in the Outpost for more offers (3 -> 6), a faster restock (8 h -> 2.6 h), lower prices (-4% a level) and rarer stock. Forge Works buildings cut prices too."])


static func _offer(m, cr: Rect2, o: Dictionary, look: Dictionary) -> void:
	var rar: String = String(o["rar"])
	var sold: bool = bool(o.get("sold", false))
	Kit.card_frame(m, cr, rar, m.t_anim, false)
	if sold:
		m.draw_rect(cr, Color(0, 0, 0, 0.55))
	PartVis.draw_part(m, o, look, Vector2(cr.get_center().x, cr.position.y + 74.0), 120.0, m.t_anim)
	Kit.th(m, "%s %s" % [String(RarityDB.get_def(rar)["name"]).to_upper(), String(PartDB.SLOTS[String(o["slot"])]["name"]).to_upper()], Vector2(cr.get_center().x, cr.position.y + 154.0), 15, Kit.rarity_text(rar), HORIZONTAL_ALIGNMENT_CENTER, cr.size.x - 16.0)
	Kit.th(m, Kit.fit(m, String(o["name"]), 16, cr.size.x - 20.0), Vector2(cr.get_center().x, cr.position.y + 178.0), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x - 20.0)
	var y: float = cr.position.y + 204.0
	for ln in Parts.fx_lines(Parts.base_fx(o)):
		Kit.t(m, Kit.fit(m, String(ln), 14, cr.size.x - 24.0), Vector2(cr.position.x + 12.0, y), 14, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 24.0)
		y += 18.0
		if y > cr.position.y + 240.0:
			break
	for p in o["perks"]:
		if y > cr.end.y - 8.0:
			break
		var t: int = int((p as Dictionary)["t"])
		var tr: String = String(RarityDB.IDS[clampi(t - 1, 0, RarityDB.IDS.size() - 1)])
		Kit.t(m, Kit.fit(m, "T%d %s" % [t, AffixDB.text(String(p["id"]), t, float(p["q"]))], 14, cr.size.x - 24.0), Vector2(cr.position.x + 12.0, y), 14, Kit.rarity_text(tr) if t >= 3 else Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 24.0)
		y += 18.0
	if sold:
		Kit.th(m, "SOLD", Vector2(cr.get_center().x, cr.get_center().y), 34, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)


static func _draw_smelt(m, s: Dictionary, r: Rect2) -> void:
	Kit.panel_glow(m, r, Color("ff9b3d"), Kit.PANEL2, 1.2, 2)
	var lv: int = Parts.smelt_level(s)
	var q: Array = Parts.block(s)["smelt"]
	Kit.th(m, "SMELTER  ·  Lv %d" % lv, Vector2(r.position.x + 28, r.position.y + 50), 30, Color("ff9b3d"))
	Kit.t(m, "%d / %d furnaces busy  ·  %s a part  ·  +%d%% Scrap  ·  Scrap %s" % [Parts.smelt_busy(s, m.now()), Parts.smelt_slots(s), Kit.dur(Parts.smelt_secs(s)), int(round(6.0 * float(maxi(0, lv - 1)))), Kit.fmt(float(s.get("scrap", 0)))],
		Vector2(r.position.x + 28, r.position.y + 80), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 56.0)
	var x: float = r.position.x + 28.0
	var w: float = r.size.x - 56.0
	var y: float = r.position.y + 124.0
	if q.is_empty():
		Kit.wrap(m, "The furnaces are cold. On the Weapon or Core screen pick a part you don't need and press SMELT: it melts here into Scrap (more for rarer, higher-level parts). Upgrade the Smelter for more furnaces, faster melts and more Scrap.", Vector2(x, y + 20.0), 17, Kit.DIM, w, 4)
	for k in q.size():
		var e: Dictionary = q[k]
		if y > r.end.y - 120.0:
			break
		var left: int = int(e["done"]) - m.now()
		var tot: float = float(maxi(1, Parts.smelt_secs(s)))
		var row: Rect2 = Rect2(x, y, w, 58.0)
		Kit.panel(m, row, Color("ff9b3d") if left > 0 else Kit.GOLD, Kit.CARD, 1)
		Kit.th(m, Kit.fit(m, String(e["name"]), 17, w * 0.45), Vector2(x + 16.0, y + 26.0), 17, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w * 0.45)
		Kit.t(m, ("READY" if left <= 0 else "%s left" % Kit.dur(left)), Vector2(x + 16.0, y + 48.0), 14, Kit.GOLD if left <= 0 else Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, 200.0)
		Kit.bar_glow(m, Rect2(x + w * 0.48, y + 22.0, w * 0.34, 12.0), clampf(1.0 - float(left) / tot, 0.0, 1.0), Color("ff9b3d"))
		Kit.th(m, "+%d Scrap" % int(e["scrap"]), Vector2(row.end.x - 16.0, y + 34.0), 17, Kit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT, 160.0)
		y += 66.0
