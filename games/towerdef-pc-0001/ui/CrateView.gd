extends RefCounted
## Crates (REDESIGN_SPEC §5): crate cards with price options, disclosed odds
## and pity counters; opening plays a reveal driven by the `crate_open` /
## `part_*` events Crates.open returns (shake -> burst -> cards flip in by
## rarity) and leaves a results row. Odds shown are Crates.odds (Crate Luck
## and Insight included). View only.

const Crates := preload("res://Crates.gd")
const Parts := preload("res://Parts.gd")
const CrateDB := preload("res://data/CrateDB.gd")
const PartDB := preload("res://data/PartDB.gd")
const Kit := preload("res://ui/Kit.gd")

const SHAKE: float = 0.7
const BURST: float = 0.35
const FLIP: float = 0.35
const PAY_LABEL: Dictionary = {"coins": "cur_coin", "keys": "cur_key", "token": "crate_field"}


static func card_rect(m, k: int) -> Rect2:
	var cr: Rect2 = m.content_rect()
	var w: float = minf(520.0, (cr.size.x - 80.0) / 3.0)
	var tot: float = 3.0 * w + 40.0
	return Rect2(cr.get_center().x - tot * 0.5 + float(k) * (w + 20.0), cr.position.y + 20, w, minf(560.0, cr.size.y * 0.6))


static func stage_rect(m) -> Rect2:
	var cr: Rect2 = m.content_rect()
	var top: float = card_rect(m, 0).end.y + 16.0
	return Rect2(cr.position.x + 20, top, cr.size.x - 40, cr.end.y - top - 16)


static func _pays(crate: String) -> Array:
	var d: Dictionary = CrateDB.get_def(crate)
	var out: Array = []
	if crate == "field":
		out.append("token")
	for p in ["coins", "keys"]:
		if int(d.get(p, 0)) > 0:
			out.append(p)
	return out


static func price(m, crate: String, pay: String) -> String:
	var d: Dictionary = CrateDB.get_def(crate)
	match pay:
		"coins":
			return "%s coins" % Kit.fmt(float(Crates.coin_cost(m.save, crate)))
		"keys":
			return "%d Key%s" % [int(d["keys"]), "" if int(d["keys"]) == 1 else "s"]
		"token":
			return "Free token (%d)" % Crates.tokens(m.save)
	return ""


static func open(m, crate: String, pay: String) -> void:
	var ev: Array = Crates.open(m.save, crate, pay, m.meta_rng)
	if ev.is_empty():
		return
	var items: Array = []
	for e in ev:
		var ed: Dictionary = e
		if String(ed["t"]) in ["part_new", "part_star", "part_dup_salvaged"]:
			items.append(ed)
	m.crate_anim = {"crate": crate, "t": 0.0, "items": items}
	m.meta_act(ev)


static func build(m) -> void:
	var s: Dictionary = m.save
	for k in CrateDB.IDS.size():
		var crate: String = CrateDB.IDS[k]
		var r: Rect2 = card_rect(m, k)
		var pays: Array = _pays(crate)
		var bw: float = (r.size.x - 24.0 - 8.0 * float(pays.size() - 1)) / float(pays.size())
		for j in pays.size():
			var pay: String = pays[j]
			if pay == "token" and Crates.tokens(s) <= 0:
				continue
			Kit.btn(m, price(m, crate, pay), Rect2(r.position.x + 12 + j * (bw + 8.0), r.end.y - 58, bw, 46), func() -> void: open(m, crate, pay), "Open a %s with %s" % [String(CrateDB.get_def(crate)["name"]), pay], Crates.can_pay(s, crate, pay), Kit.GOLD if pay == "coins" else Kit.KEYC, "CRATE %s %s" % [crate.to_upper(), pay.to_upper()], String(PAY_LABEL[pay]), 15)
	if m.crate_anim.has("crate"):
		var st: Rect2 = stage_rect(m)
		if _done(m):
			Kit.btn(m, "Close", Rect2(st.end.x - 180, st.end.y - 56, 160, 44), func() -> void: m.crate_anim = {}; m._rebuild_ui(), "Close the reveal", true, Kit.NEUTRAL, "CRATE CLOSE")
		else:
			Kit.btn(m, "Skip", Rect2(st.end.x - 180, st.end.y - 56, 160, 44), func() -> void: m.crate_anim["t"] = 99.0; m._rebuild_ui(), "Reveal everything now", true, Kit.NEUTRAL, "CRATE SKIP")


static func _done(m) -> bool:
	var a: Dictionary = m.crate_anim
	return float(a.get("t", 0.0)) >= SHAKE + BURST + FLIP * float((a.get("items", []) as Array).size()) + 0.2


static func draw(m, _cr: Rect2) -> void:
	var s: Dictionary = m.save
	for k in CrateDB.IDS.size():
		var crate: String = CrateDB.IDS[k]
		var d: Dictionary = CrateDB.get_def(crate)
		var r: Rect2 = card_rect(m, k)
		Kit.panel(m, r, Kit.GOLD if k == 2 else (Kit.GEM if k == 1 else Kit.RUST), Kit.PANEL, 2)
		var isz: float = minf(170.0, r.size.y * 0.32)
		Kit.icon(m, "crate_" + crate, Rect2(r.get_center().x - isz * 0.5, r.position.y + 16, isz, isz))
		Kit.t(m, String(d["name"]), Vector2(r.get_center().x, r.position.y + isz + 50), 26, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		Kit.t(m, "%d part%s per crate%s" % [int(d["parts"]), "" if int(d["parts"]) == 1 else "s", "  ·  at least one Rare+" if int(d.get("rare_plus", 0)) > 0 else ""], Vector2(r.get_center().x, r.position.y + isz + 76), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		var odds: Dictionary = Crates.odds(s, crate)
		var y: float = r.position.y + isz + 100.0
		for rr in CrateDB.RARITIES:
			var pc: float = float(odds.get(rr, 0.0))
			var col: Color = Kit.rarity_col(String(rr))
			Kit.t(m, String(rr).capitalize(), Vector2(r.position.x + 24, y + 14), 15, col, HORIZONTAL_ALIGNMENT_LEFT, 120.0)
			Kit.bar(m, Rect2(r.position.x + 130, y + 2, r.size.x - 230, 12), pc / 100.0, col)
			Kit.t(m, "%.1f%%" % pc, Vector2(r.end.x - 24, y + 14), 15, Kit.TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 80.0)
			y += 22.0
		var pt: Dictionary = Crates.pity(s, crate)
		var py: float = y + 12.0
		for pr in (d.get("pity", {}) as Dictionary).keys():
			var need: int = int((d["pity"] as Dictionary)[pr])
			var have: int = int(pt.get(pr, 0))
			Kit.t(m, "%s guaranteed in %d" % [String(pr).capitalize(), maxi(1, need - have)], Vector2(r.position.x + 24, py + 12), 14, Kit.rarity_col(String(pr)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x * 0.6)
			Kit.bar(m, Rect2(r.end.x - 24 - r.size.x * 0.32, py + 2, r.size.x * 0.32, 10), float(have) / float(maxi(1, need)), Kit.rarity_col(String(pr)))
			m.stat_tips.append([Rect2(r.position.x + 20, py - 6, r.size.x - 40, 22), "Pity: %d / %d opens without a %s+ — the next %d guarantee one" % [have, need, String(pr), maxi(1, need - have)]])
			py += 22.0
	# stage
	var st: Rect2 = stage_rect(m)
	Kit.panel(m, st, Kit.EDGE, Color("13171c"))
	if not m.crate_anim.has("crate"):
		Kit.t(m, "Open a crate to reveal parts. Duplicates add a star (max 2), then turn into Scrap.", Vector2(st.get_center().x, st.get_center().y + 6), 18, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, st.size.x)
		var tot: int = Parts.items(s).size()
		Kit.t(m, "You own %d parts  ·  %d Keys  ·  %d free tokens" % [tot, int(s.get("keys", 0)), Crates.tokens(s)], Vector2(st.get_center().x, st.get_center().y + 36), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_CENTER, st.size.x)
		return
	_draw_reveal(m, st)


static func _draw_reveal(m, st: Rect2) -> void:
	var a: Dictionary = m.crate_anim
	var t: float = float(a["t"])
	var crate: String = String(a["crate"])
	var items: Array = a["items"]
	var cs: float = minf(st.size.y - 60.0, 180.0)
	var cx: float = st.position.x + 60.0 + cs * 0.7
	var cy: float = st.get_center().y
	if t < SHAKE:
		var j: float = sin(t * 60.0) * 6.0 * (t / SHAKE)
		Kit.icon(m, "crate_" + crate, Rect2(cx - cs * 0.5 + j, cy - cs * 0.5, cs, cs))
		Kit.t(m, "Opening...", Vector2(st.get_center().x, st.position.y + 36), 20, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, 300.0)
		return
	var bt: float = clampf((t - SHAKE) / BURST, 0.0, 1.0)
	var fs: float = cs * (1.0 + bt * 0.35)
	Kit.icon(m, "crate_open_fx", Rect2(cx - fs * 0.5, cy - fs * 0.5, fs, fs), Color(1, 1, 1, 1.0 - bt * 0.6))
	Kit.icon(m, "crate_%s_open" % crate, Rect2(cx - cs * 0.5, cy - cs * 0.5, cs, cs))
	var x0: float = cx + cs * 0.7 + 40.0
	var cw: float = minf(220.0, (st.end.x - 200.0 - x0) / float(maxi(1, items.size())) - 16.0)
	for k in items.size():
		var ft: float = (t - SHAKE - BURST - FLIP * float(k)) / FLIP
		if ft <= 0.0:
			continue
		var e: Dictionary = items[k]
		var id: String = String(e["id"])
		var rar: String = PartDB.rarity_of(id)
		var col: Color = Kit.rarity_col(rar)
		var sx: float = clampf(ft, 0.0, 1.0)
		var r := Rect2(x0 + float(k) * (cw + 16.0) + cw * 0.5 * (1.0 - sx), st.position.y + 20, cw * sx, st.size.y - 40)
		if rar in ["epic", "legendary", "special"]:
			m.draw_rect(r.grow(6.0), Color(col, 0.18 + 0.1 * sin(m.t_anim * 6.0)))
		Kit.panel(m, r, col, Color(col.darkened(0.82), 1.0), 3)
		if sx < 0.6:
			continue
		var isz: float = minf(cw - 40.0, r.size.y - 110.0)
		Kit.icon(m, id, Rect2(r.get_center().x - isz * 0.5, r.position.y + 14, isz, isz))
		Kit.t(m, String(PartDB.get_def(id).get("name", id)), Vector2(r.get_center().x, r.position.y + isz + 40), 17, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8)
		var sub: String = rar.capitalize()
		match String(e["t"]):
			"part_new":
				sub = "NEW  " + sub
			"part_star":
				sub = "star %d" % int(e["stars"])
			"part_dup_salvaged":
				sub = "+%d Scrap" % int(e["scrap"])
		Kit.t(m, sub, Vector2(r.get_center().x, r.position.y + isz + 62), 15, col, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8)
		m.stat_tips.append([r, String(PartDB.get_def(id).get("name", id)) + "\n" + "\n".join(PackedStringArray((PartDB.lines(id, 1)["plus"] as Array) + (PartDB.lines(id, 1)["minus"] as Array)))])
