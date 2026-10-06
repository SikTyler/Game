extends RefCounted
## Left panel of the run screen (REDESIGN_SPEC §5 draft panel): the open draft
## (3-4 cards: rarity frame, family icon, name, effect, tags, "Lv N->N+1" for
## duplicates; reroll with its cost; banish), perk / mutation offers, the
## placement prompt, or — when nothing is offered — the PERKS menu: every
## stat buff taken this run (gold perks, upgrade packs, insights, mutations).
## Owner feedback #1: no Build/Info block and no hotkey callouts here. Cards are hit
## buttons over drawn art; press + drag a NEW building card onto a cell to
## place it in one motion.

const TowerState := preload("res://TowerState.gd")
const PickDB := preload("res://data/PickDB.gd")
const PerkDB := preload("res://data/PerkDB.gd")
const ModifierDB := preload("res://data/ModifierDB.gd")
const MergeDB := preload("res://data/MergeDB.gd")
const DirectiveDB := preload("res://data/DirectiveDB.gd")
const EvoDB := preload("res://data/EvoDB.gd")
const Kit := preload("res://ui/Kit.gd")

const FAM_LABEL: Dictionary = {"building": "BUILDING", "hut": "TROOP HUT", "pack": "UPGRADE PACK", "special": "SPECIAL ATTACK", "insight": "INSIGHT"}


static func _offer(m) -> Dictionary:
	var S = m.S
	if S.mutation_offer.size() > 0:
		return {"kind": "mutation", "ids": S.mutation_offer}
	if S.directive_offer.size() > 0:
		return {"kind": "directive", "ids": S.directive_offer}
	if not S.merge_offer.is_empty():
		return {"kind": "mod", "ids": MergeDB.offer(String(S.merge_offer["id"]), int(S.merge_offer["tier"]))}
	if S.perk_offer.size() > 0:
		return {"kind": "perk", "ids": S.perk_offer}
	if S.draft.size() > 0:
		return {"kind": "draft", "ids": S.draft}
	return {}


## Display def of a draft card (PickDB, or the EvoDB evolution).
static func card_def(cd: Dictionary) -> Dictionary:
	if String(cd.get("kind", "")) == "evo":
		var e: Dictionary = EvoDB.get_def(String(cd.get("weapon", "")))
		return {"name": String(e.get("name", "")), "desc": "EVOLVES your T3 %s: %s" % [String(PickDB.get_def(String(cd.get("weapon", ""))).get("name", "")), String(e.get("desc", ""))], "tags": ["dps"], "rarity": "legendary", "fam": "evolution"}
	return PickDB.get_def(String(cd.get("id", "")))


static func card_rect(m, k: int, n: int) -> Rect2:
	var lr: Rect2 = m.left_rect()
	var top: float = lr.position.y + 54.0
	var avail: float = lr.size.y - 54.0 - 120.0
	var h: float = minf(196.0, (avail - 10.0 * float(n - 1)) / float(maxi(1, n)))
	return Rect2(lr.position.x + 14, top + float(k) * (h + 10.0), lr.size.x - 28, h)


static func build(m) -> void:
	var S = m.S
	var lr: Rect2 = m.left_rect()
	var off: Dictionary = _offer(m)
	if not off.is_empty():
		var ids: Array = off["ids"]
		for k in ids.size():
			var idx: int = k
			var r: Rect2 = card_rect(m, k, ids.size())
			match String(off["kind"]):
				"draft":
					var cd: Dictionary = ids[k]
					var cdef: Dictionary = card_def(cd)
					var tip: String = "%s\n%s\n%s" % [String(cdef.get("name", "")), String(cdef.get("desc", "")), String(card_type(m, cd)["how"])]
					var hb: Button = Kit.hit(m, r, func() -> void: _press_card(m, idx), tip, "DCARD %d %s" % [k, String(cd["id"])], true, Kit.ENEMY if m.banish_mode else Kit.GOLD)
					hb.set_meta("card", k)
					# V2 P7c: lock toggle (kept by rerolls, carried to the next hand)
					if String(cd.get("kind", "")) != "evo":
						var locked: bool = bool(cd.get("lock", false))
						Kit.btn(m, "", lock_rect(r), func() -> void: m._handle(S.toggle_lock(idx)); m._rebuild_ui(), "Unlock this card" if locked else "Lock this card: rerolls keep it, and it waits for your next hand if you take another (max %d)" % TowerState.MAX_LOCKS, true, Kit.GOLD if locked else Kit.NEUTRAL, "DLOCK %d" % k, "slot_locked", 14)
				"directive":
					var did: String = String(ids[k])
					var dd: Dictionary = DirectiveDB.get_def(did)
					Kit.hit(m, r, func() -> void: m._handle(S.choose_directive(idx)); m._rebuild_ui(), "%s\n%s\nCOST: %s\nClick to take this Directive for the rest of the run" % [String(dd["name"]), String(dd["desc"]), String(dd["cost"])], "DDIR %d" % k, true, Kit.MAGENTA)
				"perk":
					var pid: String = String(ids[k])
					var d: Dictionary = PerkDB.get_def(pid)
					Kit.hit(m, r, func() -> void: m._handle(S.choose_perk(idx)); m._rebuild_ui(), "%s\n%s\nClick to take this perk" % [String(d["name"]), String(d["desc"])], "DPERK " + String(d["name"]))
				"mutation":
					var mid: String = String(ids[k])
					var md: Dictionary = ModifierDB.MUTATIONS.get(mid, {})
					Kit.hit(m, r, func() -> void: m._handle(S.choose_mutation(idx)); m._rebuild_ui(), "%s\n%s" % [String(md.get("name", mid)), String(md.get("desc", ""))], "DMUT " + String(md.get("name", mid)), true, Kit.MAG)
				"mod":
					var mo: Dictionary = ids[k]
					Kit.hit(m, r, func() -> void: m._handle(S.choose_mod(idx)); m._rebuild_ui(), "%s\n%s\nClick to fit this mod" % [String(mo.get("name", "")), String(mo.get("desc", ""))], "DMOD %d" % k, true, Kit.CYAN)
		if String(off["kind"]) == "draft":
			var by: float = lr.end.y - 112.0
			var bw: float = (lr.size.x - 40.0) * 0.5
			var rc: int = S.reroll_cost()
			var rl: String = "Reroll (free)" if rc == 0 else "Reroll  $%d" % rc
			Kit.btn(m, rl, Rect2(lr.position.x + 14, by, bw, 48), m.reroll, "Re-roll the whole hand: 1 free per draft, then cash that doubles", rc == 0 or S.cash >= float(rc), Kit.GEM, "Reroll", "ui_reroll", 16)
			Kit.btn(m, "Banish (%d)" % S.banish_left, Rect2(lr.position.x + 26 + bw, by, bw, 48), m.toggle_banish, "Banish mode: the next card you click leaves this run's pool and is replaced", S.banish_left > 0, Kit.ENEMY if m.banish_mode else Kit.NEUTRAL, "Banish", "ui_banish", 16)
		return
	if S.pending_place != "":
		Kit.btn(m, "Cancel placement", Rect2(lr.position.x + 14, lr.position.y + 250, lr.size.x - 28, 48), func() -> void: m._handle(S.cancel_place()); m._rebuild_ui(), "Skip placing this building (the pick is spent)", true, Kit.NEUTRAL, "CANCEL PLACE")


## Card press: pad = take immediately; mouse = start a drag (release in place
## takes the card; release over a cell places a NEW building there).
## Owner feedback #1: what a draft card GIVES, impossible to misread —
## BUILDING (placed on the grid), UPGRADE (drag onto / click an existing
## building), PERK (instant stat buff, listed under Perks) or ABILITY.
static func card_type(m, cd: Dictionary) -> Dictionary:
	var S = m.S
	var id: String = String(cd.get("id", ""))
	var nm: String = String(PickDB.get_def(id).get("name", id))
	var kind: String = String(cd.get("kind", ""))
	var rw: String = String(cd.get("reward", ""))
	if kind == "evo":
		return {"type": "EVOLUTION", "col": Kit.GOLD, "icon": "icon_tier",
			"sub": "Your T3 %s evolves" % String(PickDB.get_def(String(cd.get("weapon", ""))).get("name", "")),
			"how": "EVOLUTION: click to evolve that weapon now"}
	if kind == "new":
		var dup: bool = bool(cd.get("dup", false))
		if bool(cd.get("merge", false)):
			return {"type": "BUILDING", "col": Kit.GOLD, "icon": "icon_tier",
				"sub": "Merge -> T2 %s" % nm,
				"how": "BUILDING: drop on your T1 %s to merge it into a T2, or on an empty cell" % nm}
		return {"type": "BUILDING", "col": Kit.RARITY["rare"], "icon": "ui_blueprint",
			"sub": "Place another" if dup else "Place on the grid",
			"how": "BUILDING: drag onto an empty cell (or click, then click a cell)"}
	if rw == "ability" or kind == "special":
		var have: bool = S != null and S.specials.any(func(s: Variant) -> bool: return String((s as Dictionary)["id"]) == id)
		return {"type": "ABILITY", "col": Kit.GEM, "icon": "ui_cooldown",
			"sub": "+1 copy (faster)" if have else "New ability",
			"how": "ABILITY: click to add it to your floating abilities"}
	var sub: String = "Instant stat buff"
	if kind == "pack" and S != null:
		sub = "Stat buff  ·  %d/%d" % [S.pack_n(id) + 1, PickDB.max_of(id)]
	elif kind == "insight":
		sub = "Permanent insight"
	return {"type": "PERK", "col": Kit.GOLD, "icon": "icon_streak", "sub": sub,
		"how": "PERK: click to take it now (no placing)"}


static func lock_rect(r: Rect2) -> Rect2:
	return Rect2(r.end.x - 40, r.position.y + 32, 32, 30)


static func _press_card(m, k: int) -> void:
	if String(m.last_device) == "pad" or m.banish_mode:
		m.pick_card(k)
		return
	m.begin_drag_card(k)


static func draw(m) -> void:
	var S = m.S
	var lr: Rect2 = m.left_rect()
	m.draw_rect(lr, Color(Kit.PANEL, 1.0))   # V2 P9 audit: opaque side panel
	m.draw_line(Vector2(lr.end.x, lr.position.y), Vector2(lr.end.x, lr.end.y), Kit.EDGE, 2.0)
	var x: float = lr.position.x + 16.0
	var w: float = lr.size.x - 32.0
	# V2 P9 audit: the run is over on the results screen, so no live offer
	# (draft cards / Reroll / Banish) is shown there, only this run's perks
	var off: Dictionary = _offer(m) if m.screen != "results" else {}
	if not off.is_empty():
		var kind: String = String(off["kind"])
		var title: String = "DRAFT — wave %d" % int(S.wave)
		if kind == "perk":
			title = "GOLD PERK — level %d" % int(S.level)
		elif kind == "mutation":
			title = "ENDLESS MUTATION"
		elif kind == "directive":
			title = "BOSS DOWN: PICK A DIRECTIVE"
		elif kind == "mod":
			title = "MERGED: %s T%d" % [String(PickDB.get_def(String(S.merge_offer["id"])).get("name", "")).to_upper(), int(S.merge_offer["tier"])]
		elif kind == "draft":
			title = "DRAFT — level %d" % int(S.level)
		Kit.t(m, title, Vector2(x, lr.position.y + 34), 22, Kit.GOLD if kind != "mutation" else Kit.MAG, HORIZONTAL_ALIGNMENT_LEFT, w)
		if kind == "draft" and m.banish_mode:
			Kit.t(m, "BANISH: pick a card", Vector2(x + w, lr.position.y + 34), 15, Kit.ENEMY, HORIZONTAL_ALIGNMENT_RIGHT, w * 0.5)
		var ids: Array = off["ids"]
		for k in ids.size():
			var r: Rect2 = card_rect(m, k, ids.size())
			match kind:
				"draft":
					_draw_card(m, r, ids[k] as Dictionary, k)
				"perk":
					var d: Dictionary = PerkDB.get_def(String(ids[k]))
					var lines: String = String(d["desc"]) + ("\nCOST: " + String(d["cost"]) if bool(d.get("tradeoff", false)) else "")
					_draw_simple(m, r, "perk_" + String(ids[k]).substr(2), "PERK", String(d["name"]), lines, Kit.GOLD, k)
				"mutation":
					var md: Dictionary = ModifierDB.MUTATIONS.get(String(ids[k]), {})
					_draw_simple(m, r, "icon_endless", "MUTATION", String(md.get("name", "")), String(md.get("desc", "")), Kit.MAG, k)
				"directive":
					var dd2: Dictionary = DirectiveDB.get_def(String(ids[k]))
					_draw_simple(m, r, "icon_endless", "DIRECTIVE  ·  rest of the run", String(dd2["name"]), "%s\nCOST: %s" % [String(dd2["desc"]), String(dd2["cost"])], Kit.MAGENTA, k)
				"mod":
					var mo2: Dictionary = ids[k]
					var t3: bool = int(S.merge_offer["tier"]) >= 3
					_draw_simple(m, r, String(S.merge_offer["id"]), "T3 CAPSTONE" if t3 else "T2 MOD", String(mo2.get("name", "")), String(mo2.get("desc", "")), Kit.GOLD if t3 else Kit.CYAN, k)
		if kind == "draft":
			Kit.t(m, "The battle keeps running while you choose", Vector2(x, lr.end.y - 22), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
		return
	if S.pending_place != "":
		var d2: Dictionary = PickDB.get_def(S.pending_place)
		Kit.t(m, "PLACE BUILDING", Vector2(x, lr.position.y + 34), 22, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w)
		Kit.panel(m, Rect2(x, lr.position.y + 54, w, 180), Kit.rarity_col(String(d2["rarity"])), Kit.PANEL2)
		Kit.icon(m, S.pending_place, Rect2(x + 14, lr.position.y + 70, 80, 80))
		Kit.t(m, String(d2["name"]), Vector2(x + 108, lr.position.y + 100), 22, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 120)
		Kit.wrap(m, String(d2["desc"]), Vector2(x + 14, lr.position.y + 176), 15, Kit.DIM, w - 28, 3)
		var merge_txt: String = "" if S.card_merge_targets(S.pending_place).is_empty() else " Or click your glowing T1 %s to MERGE it into a T2 (a mod pick follows)." % String(d2["name"])
		Kit.wrap(m, "Click a glowing cell on the grid.%s Enemies never attack buildings: they flow around them, or squeeze slowly through a sealed wall." % merge_txt, Vector2(x, lr.position.y + 330), 15, Kit.DIM, w, 5)
		return
	_draw_info(m, lr, x, w)


static func _draw_card(m, r: Rect2, cd: Dictionary, k: int) -> void:
	var S = m.S
	var id: String = String(cd["id"])
	var d: Dictionary = card_def(cd)
	var evo: bool = String(cd.get("kind", "")) == "evo"
	var fam: String = String(cd.get("fam", d.get("fam", "")))
	var rar: String = String(cd.get("rarity", d.get("rarity", "common")))
	var rc: Color = Kit.rarity_col(rar)
	var dragging: bool = m.drag_card == k and m.mouse_pos.distance_to(m.drag_start) > 12.0
	var fill: Color = Color(rc.darkened(0.82), 0.95)
	if fam == "insight" or evo:
		var g: float = 0.5 + 0.5 * sin(m.t_anim * 4.0)
		m.draw_rect(r.grow(4.0 + 3.0 * g), Color(rc, 0.18))
	if bool(cd.get("lock", false)) and not evo:
		m.draw_rect(r.grow(5.0), Color(Kit.GOLD, 0.35), false, 3.0)
	Kit.panel(m, r, Kit.ENEMY if m.banish_mode else rc, fill, 3)
	if dragging:
		m.draw_rect(r, Color(0, 0, 0, 0.45))
	var isz: float = minf(r.size.y - 44.0, 92.0)
	Kit.panel(m, Rect2(r.position.x + 10, r.position.y + 34, isz, isz), Color(rc, 0.5), Kit.BG2, 1)
	Kit.icon(m, String(cd.get("weapon", id)) if evo else id, Rect2(r.position.x + 14, r.position.y + 38, isz - 8, isz - 8))
	# Owner feedback #1: a type banner (icon + colour + label) on every card.
	var ct: Dictionary = card_type(m, cd)
	var tcol: Color = ct["col"]
	var br := Rect2(r.position.x + 3, r.position.y + 3, r.size.x - 6, 26)
	m.draw_rect(br, Color(tcol, 0.28))
	m.draw_rect(Rect2(br.position, Vector2(6, br.size.y)), tcol)
	Kit.icon(m, String(ct["icon"]), Rect2(br.position.x + 10, br.position.y + 2, 22, 22))
	Kit.t(m, String(ct["type"]), Vector2(br.position.x + 38, br.position.y + 20), 16, tcol.lightened(0.25), HORIZONTAL_ALIGNMENT_LEFT, 110.0)
	Kit.t(m, Kit.fit(m, String(ct["sub"]), 14, br.size.x - 160.0 - 74.0), Vector2(br.position.x + 38 + 110, br.position.y + 19), 14, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, br.size.x - 160.0 - 74.0)
	# V2 P9 audit: the rarity word on a dark pill in a lifted tint (>= 4.5:1)
	var rw: float = m.font.get_string_size(rar.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 14.0
	m.draw_style_box(Kit.sb(Color(rc, 0.7), Color(Kit.BG, 0.92), 1, 9), Rect2(br.end.x - rw - 4, br.position.y + 3, rw, 20))
	Kit.t(m, rar.capitalize(), Vector2(br.end.x - 11, br.position.y + 18), 14, Kit.rarity_text(rar), HORIZONTAL_ALIGNMENT_RIGHT, 70.0)
	var tx: float = r.position.x + 22.0 + isz
	var tw: float = r.end.x - tx - 10.0
	Kit.t(m, String(d.get("name", id)), Vector2(tx, r.position.y + 58), 21, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, tw)
	Kit.wrap(m, String(d.get("desc", "")), Vector2(tx, r.position.y + 70), 15, Kit.DIM, tw, int(maxf(1.0, (r.size.y - 104.0) / 18.0)))
	# tag chips
	var cx: float = tx
	for tg in (d.get("tags", []) as Array):
		var tag: String = String(tg)
		var cw: float = 30.0 + float(tag.length()) * 8.0
		if cx + cw > r.end.x - 8.0:
			break
		var cr := Rect2(cx, r.end.y - 28, cw, 20)
		Kit.panel(m, cr, Kit.EDGE, Kit.BG2, 1)
		Kit.icon(m, "tag_" + tag, Rect2(cx + 2, r.end.y - 27, 18, 18))
		Kit.t(m, tag, Vector2(cx + 25, r.end.y - 13), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 27)
		cx += cw + 4.0
	

static func _draw_simple(m, r: Rect2, icon_id: String, head: String, name: String, desc: String, col: Color, k: int) -> void:
	Kit.panel(m, r, col, Color(col.darkened(0.82), 0.95), 3)
	var isz: float = minf(r.size.y - 44.0, 80.0)
	Kit.icon(m, icon_id, Rect2(r.position.x + 12, r.position.y + 36, isz, isz))
	Kit.t(m, head, Vector2(r.position.x + 12, r.position.y + 24), 14, col, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 60)
	var tx: float = r.position.x + 24.0 + isz
	Kit.t(m, name, Vector2(tx, r.position.y + 58), 21, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, r.end.x - tx - 10)
	Kit.wrap(m, desc, Vector2(tx, r.position.y + 70), 15, Kit.DIM, r.end.x - tx - 10, 4)
	

## No offer: the PERKS menu (owner feedback #1) — every stat buff this run.
static func _draw_info(m, lr: Rect2, x: float, w: float) -> void:
	var y: float = lr.position.y + 34.0
	Kit.icon(m, "icon_streak", Rect2(x, y - 24, 30, 30))
	Kit.t(m, "PERKS", Vector2(x + 38, y), 22, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w - 38)
	var rows: Array = perk_rows(m)
	Kit.t(m, "%d taken" % rows.size(), Vector2(x + w, y), 15, Kit.DIM, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)
	y += 16.0
	if rows.is_empty():
		Kit.wrap(m, "No perks yet. PERK cards (gold banner) and the gold perk picks every few waves are instant stat buffs — they gather here.", Vector2(x, y + 10), 15, Kit.DIM, w, 5)
		return
	var sec: String = ""
	var rh: float = clampf((lr.end.y - y - 30.0) / float(rows.size() + 4), 30.0, 52.0)
	for rv in rows:
		var row: Dictionary = rv
		if String(row["sec"]) != sec:
			sec = String(row["sec"])
			Kit.head(m, sec, Vector2(x, y + 22), w, row["col"])
			y += 30.0
		if y + rh > lr.end.y - 8.0:
			Kit.t(m, "...", Vector2(x, y + 16), 16, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
			break
		var rr := Rect2(x, y, w, rh - 4.0)
		Kit.panel(m, rr, Color(row["col"] as Color, 0.6), Kit.PANEL2, 1)
		Kit.icon(m, String(row["icon"]), Rect2(x + 4, y + 2, rh - 8.0, rh - 8.0))
		Kit.t(m, String(row["name"]), Vector2(x + rh + 2.0, y + rh * 0.5 + 2.0), 16, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - rh - 50.0)
		if String(row["n"]) != "":
			Kit.t(m, String(row["n"]), Vector2(rr.end.x - 8, y + rh * 0.5 + 2.0), 16, row["col"], HORIZONTAL_ALIGNMENT_RIGHT, 50.0)
		m.stat_tips.append([rr, "%s\n%s" % [String(row["name"]), String(row["desc"])]])
		y += rh


## Rows for the Perks menu: gold perks, stat perks (packs), insights, mutations.
static func perk_rows(m) -> Array:
	var S = m.S
	var out: Array = []
	var seen: Dictionary = {}
	for pid in S.perks_taken:
		var id: String = String(pid)
		seen[id] = int(seen.get(id, 0)) + 1
	for id in seen.keys():
		var d: Dictionary = PerkDB.get_def(String(id))
		var dsc: String = String(d.get("desc", "")) + ("\nCost: " + String(d["cost"]) if bool(d.get("tradeoff", false)) else "")
		out.append({"sec": "GOLD PERKS", "col": Kit.GOLD, "icon": "perk_" + String(id).substr(2), "name": String(d.get("name", id)), "n": "x%d" % int(seen[id]) if int(seen[id]) > 1 else "", "desc": dsc})
	for pid in S.packs.keys():
		var pd: Dictionary = PickDB.get_def(String(pid))
		out.append({"sec": "STAT PERKS", "col": Color("e8c26a"), "icon": String(pid), "name": String(pd.get("name", pid)), "n": "x%d" % int(S.packs[pid]), "desc": String(pd.get("desc", ""))})
	for iid in S.insight_found:
		var idf: Dictionary = PickDB.get_def(String(iid))
		out.append({"sec": "INSIGHTS", "col": Kit.RARITY["insight"], "icon": String(iid), "name": String(idf.get("name", iid)), "n": "", "desc": String(idf.get("desc", "")) + "\nBanked permanently at run end"})
	var dn: Dictionary = {}   # V2 P9 audit: repeats stack as one row (xN)
	for did in S.directives:
		dn[String(did)] = int(dn.get(String(did), 0)) + 1
	for did in dn.keys():
		var ddf: Dictionary = DirectiveDB.get_def(String(did))
		out.append({"sec": "DIRECTIVES", "col": Kit.MAGENTA, "icon": "icon_endless", "name": String(ddf.get("name", did)), "n": ("x%d" % int(dn[did])) if int(dn[did]) > 1 else "", "desc": "%s\nCost: %s" % [String(ddf.get("desc", "")), String(ddf.get("cost", ""))]})
	for mid in S.mutations_taken:
		var md: Dictionary = ModifierDB.MUTATIONS.get(String(mid), {})
		out.append({"sec": "MUTATIONS", "col": Kit.MAG, "icon": "icon_endless", "name": String(md.get("name", mid)), "n": "", "desc": String(md.get("desc", ""))})
	return out
