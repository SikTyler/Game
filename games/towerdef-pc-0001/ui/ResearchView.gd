extends RefCounted
## Research tab (V2 P8): category tabs (LabDB.CATS) over a grid of project
## cards. A card shows its neon glyph, name, level, effect and the price after
## Lab Discount; clicking an open, affordable card researches it instantly
## (key "LAB <id>"). A locked card names what it needs with a jump chip:
## the Research Hall level ("req:bld:research") or the prerequisite research
## ("req:res:<id>", which switches category and pulses it). Main.jump_to and
## the Core requirement chips focus a project here (m.res_focus): the view
## opens its category. Tabs "RTAB <name>". View only.

const Labs := preload("res://Labs.gd")
const LabDB := preload("res://data/LabDB.gd")
const Outpost := preload("res://Outpost.gd")
const Kit := preload("res://ui/Kit.gd")
const RunArt := preload("res://ui/RunArt.gd")

const COLS: int = 4
const GAP: float = 14.0
## Category colours (tab underline / card accent).
const CAT_COL: Dictionary = {"core": "39e6ff", "enemy": "ff4d6d", "economy": "ffd34d", "loot": "f59e0b", "forge": "ff3ea5", "run": "a855f7", "qol": "4ade80"}


static func cat_col(cat: String) -> Color:
	return Color(String(CAT_COL.get(cat, "39e6ff")))


## The category shown: the focused project's while its pulse runs.
static func cat_of(m) -> String:
	var f: String = String(m.res_focus)
	if f != "" and LabDB.DEFS.has(f) and float(m.t_anim) - float(m.res_focus_t) < 0.4:
		m.res_cat = String(LabDB.get_def(f)["cat"])
	return String(m.res_cat)


static func tab_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	return Rect2(cr.position.x + 20.0, cr.position.y + 66.0, cr.size.x - 40.0, 44.0)


static func card_rect(m, k: int, n: int) -> Rect2:
	var cr: Rect2 = m.content_rect()
	var w: float = (cr.size.x - 40.0 - float(COLS - 1) * GAP) / float(COLS)
	var top: float = cr.position.y + 126.0
	var rows: int = maxi(1, int(ceil(float(n) / float(COLS))))
	var h: float = minf(168.0, (cr.end.y - top - 16.0 - float(rows - 1) * GAP) / float(rows))
	return Rect2(cr.position.x + 20.0 + float(k % COLS) * (w + GAP), top + float(k / COLS) * (h + GAP), w, h)


## The jump chip along a locked card's bottom edge.
static func chip_rect(r: Rect2) -> Rect2:
	return Rect2(r.position.x + 10.0, r.end.y - 50.0, r.size.x - 20.0, 42.0)


## What a locked card's chip points at: [kind, id, label] ([] when open).
static func lock_target(s: Dictionary, id: String) -> Array:
	if Outpost.level_of(s, "research") < Labs.hall_req(id):
		return ["bld", "research", "Research Hall Lv %d" % Labs.hall_req(id)]
	var mr: Array = Labs.missing_reqs(s, id)
	if not mr.is_empty():
		var r: Array = mr[0]
		return ["res", String(r[0]), "%s Lv %d" % [String(LabDB.get_def(String(r[0]))["name"]), int(r[1])]]
	return []


static func tip(s: Dictionary, id: String) -> String:
	var d: Dictionary = LabDB.get_def(id)
	var lv: int = Labs.level(s, id)
	var mx: int = LabDB.max_of(id)
	var lines: Array = ["%s  Lv %d / %d" % [String(d["name"]), lv, mx], String(d["effect"])]
	if lv >= mx:
		lines.append("Maxed")
	else:
		var why: String = Labs.why_locked(s, id)
		if why != "":
			lines.append("LOCKED: " + why)
		var c: int = Labs.price(s, id)
		var disc: String = "" if Labs.discount(s) <= 0.0 else "  (Lab Discount -%d%%)" % int(round(Labs.discount(s) * 100.0))
		lines.append("Next: %s coins, instant%s" % [Kit.fmt(float(c)), disc])
	return "\n".join(PackedStringArray(lines))


static func build(m) -> void:
	var s: Dictionary = m.save
	var items: Array = []
	for c in LabDB.CATS:
		var cid: String = String((c as Array)[0])
		items.append([cid, String((c as Array)[1]), "", "Research: %s projects (%d)" % [String((c as Array)[1]), LabDB.cat_ids(cid).size()]])
	var cat: String = cat_of(m)
	Kit.tabs(m, tab_rect(m), items, cat, func(id: String) -> void:
		m.res_cat = id
		m.res_focus = ""
		m._rebuild_ui(), "RTAB ", [], 16)
	var ids: Array = LabDB.cat_ids(cat)
	for k in ids.size():
		var id: String = String(ids[k])
		var r: Rect2 = card_rect(m, k, ids.size())
		var lt: Array = lock_target(s, id) if Labs.level(s, id) < LabDB.max_of(id) else []
		var hr: Rect2 = r
		if not lt.is_empty():
			hr = Rect2(r.position, Vector2(r.size.x, r.size.y - 56.0))
			var kind: String = String(lt[0])
			var rid: String = String(lt[1])
			Kit.req_chip(m, chip_rect(r), kind, rid, String(lt[2]), false, func() -> void: m.jump_to(kind, rid),
				"Needs %s - click to go there" % String(lt[2]), "icon_lab")
		Kit.hit(m, hr, func() -> void: m.meta_act(Labs.start(m.save, id, m.now())), tip(s, id), "LAB " + id, Labs.can_start(s, id), cat_col(cat))


static func draw(m, cr: Rect2) -> void:
	var s: Dictionary = m.save
	var cat: String = cat_of(m)
	var cc: Color = cat_col(cat)
	Kit.t(m, "RESEARCH", Vector2(cr.position.x + 20, cr.position.y + 44), 28, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
	Kit.t(m, "Instant, permanent upgrades. Higher Research Hall levels open new rows.", Vector2(cr.position.x + 210, cr.position.y + 40), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cr.size.x - 760.0)
	# header chips: Hall level, Lab Discount, projects maxed
	var maxed: int = 0
	for id in LabDB.IDS:
		if Labs.level(s, String(id)) >= LabDB.max_of(String(id)):
			maxed += 1
	var hx: float = cr.end.x - 520.0
	Kit.chip(m, "icon_lab", "Hall Lv %d" % Outpost.level_of(s, "research"), Vector2(hx, cr.position.y + 50), Kit.CYAN, "Research Hall level: rows open at Lv %s" % " / ".join(PackedStringArray(LabDB.HALL_ROWS.map(func(x: Variant) -> String: return str(x)))), 160.0, 0.8)
	Kit.chip(m, "cur_coin", "-%d%%" % int(round(Labs.discount(s) * 100.0)), Vector2(hx + 172.0, cr.position.y + 50), Kit.GREEN, "Lab Discount: every research price -3% per level", 150.0, 0.8)
	Kit.chip(m, "", "%d / %d maxed" % [maxed, LabDB.IDS.size()], Vector2(hx + 334.0, cr.position.y + 50), Kit.GOLD, "Research projects at their max level", 186.0, 0.8)
	var ids: Array = LabDB.cat_ids(cat)
	for k in ids.size():
		var id: String = String(ids[k])
		var d: Dictionary = LabDB.get_def(id)
		var r: Rect2 = card_rect(m, k, ids.size())
		var lv: int = Labs.level(s, id)
		var mx: int = LabDB.max_of(id)
		var done: bool = lv >= mx
		var open: bool = done or Labs.is_open(s, id)
		var ok: bool = Labs.can_start(s, id)
		var border: Color = cc if ok else (Kit.GREEN if done else Kit.EDGE)
		var ft: float = float(m.t_anim) - float(m.res_focus_t)
		if String(m.res_focus) == id and ft < 2.5:
			# focus pulse under the card (its glow shadow would tint a translucent fill)
			Kit.panel_glow(m, r.grow(3.0), Kit.GOLD, Color(Kit.BG2, 1.0), 1.0 + 1.5 * (0.5 + 0.5 * sin(ft * 9.0)), 3)
		Kit.panel(m, r, border, Kit.CARD if open else Color(Kit.PANEL, 0.75), 2 if ok else 1)
		var isz: float = minf(56.0, r.size.y - 60.0)
		RunArt.draw_spec(m, d.get("icon", ["rings", "8a9bbd"]), Rect2(r.position.x + 12, r.position.y + 12, isz, isz), Color.WHITE if open else Color(1, 1, 1, 0.45), hash(id))
		var tx: float = r.position.x + 22.0 + isz
		var tw: float = r.end.x - tx - 10.0
		Kit.th(m, String(d["name"]), Vector2(tx, r.position.y + 30), 18, Kit.TEXT if open else Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, tw - 70.0)
		Kit.t(m, "%d / %d" % [lv, mx], Vector2(r.end.x - 12, r.position.y + 30), 15, Kit.GOLD if done else Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 70.0)
		# level pips (or a bar for long tracks)
		var py: float = r.position.y + 40.0
		if mx <= 10:
			var pw: float = minf(16.0, (tw - 4.0 * float(mx - 1)) / float(mx))
			for p in mx:
				m.draw_rect(Rect2(tx + float(p) * (pw + 4.0), py, pw, 5.0), cc if p < lv else Color(Kit.EDGE2, 0.8))
		else:
			Kit.bar(m, Rect2(tx, py, tw, 5.0), float(lv) / float(mx), cc)
		var lines: int = 2 if r.size.y >= 140.0 else 1
		Kit.wrap(m, String(d["effect"]), Vector2(tx, py + 10.0), 14, Kit.DIM if open else Color(Kit.DIM, 0.7), tw, lines)
		if not open:
			continue   # the jump chip (a button) fills the bottom strip
		var by: float = r.end.y - 14.0
		if done:
			Kit.th(m, "MAXED", Vector2(r.position.x + 14, by), 16, Kit.GREEN, HORIZONTAL_ALIGNMENT_LEFT, 120.0)
		else:
			var c: int = Labs.price(s, id)
			Kit.icon(m, "cur_coin", Rect2(r.position.x + 12, by - 18, 22, 22))
			Kit.th(m, Kit.fmt(float(c)), Vector2(r.position.x + 40, by), 18, Kit.GOLD if int(s["coins"]) >= c else Kit.ENEMY, HORIZONTAL_ALIGNMENT_LEFT, 140.0)
			Kit.t(m, "Hall %d" % Labs.hall_req(id), Vector2(r.end.x - 12, by), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 90.0)
