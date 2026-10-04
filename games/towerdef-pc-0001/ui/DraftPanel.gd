extends RefCounted
## Left panel of the run screen (REDESIGN_SPEC §5 draft panel): the open draft
## (3-4 cards: rarity frame, family icon, name, effect, tags, "Lv N->N+1" for
## duplicates; reroll with its cost; banish), perk / mutation offers, the
## placement prompt, or — when nothing is offered — build / info for the
## hovered or selected cell plus this run's picks and loot. Cards are hit
## buttons over drawn art; press + drag a NEW building card onto a cell to
## place it in one motion.

const TowerState := preload("res://TowerState.gd")
const PickDB := preload("res://data/PickDB.gd")
const PerkDB := preload("res://data/PerkDB.gd")
const ModifierDB := preload("res://data/ModifierDB.gd")
const Kit := preload("res://ui/Kit.gd")

const FAM_LABEL: Dictionary = {"building": "BUILDING", "hut": "TROOP HUT", "pack": "UPGRADE PACK", "special": "SPECIAL ATTACK", "insight": "INSIGHT"}


static func _offer(m) -> Dictionary:
	var S = m.S
	if S.mutation_offer.size() > 0:
		return {"kind": "mutation", "ids": S.mutation_offer}
	if S.perk_offer.size() > 0:
		return {"kind": "perk", "ids": S.perk_offer}
	if S.draft.size() > 0:
		return {"kind": "draft", "ids": S.draft}
	return {}


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
			var key: String = Kit.hint(m, "ability_%d" % (k + 1))
			match String(off["kind"]):
				"draft":
					var cd: Dictionary = ids[k]
					var tip: String = "%s\n%s\n[%s] take  ·  drag a new building onto a cell" % [String(PickDB.get_def(String(cd["id"])).get("name", "")), String(PickDB.get_def(String(cd["id"])).get("desc", "")), key]
					var hb: Button = Kit.hit(m, r, func() -> void: _press_card(m, idx), tip, "DCARD %d %s" % [k, String(cd["id"])], true, Kit.ENEMY if m.banish_mode else Kit.GOLD)
					hb.set_meta("card", k)
				"perk":
					var pid: String = String(ids[k])
					var d: Dictionary = PerkDB.get_def(pid)
					Kit.hit(m, r, func() -> void: m._handle(S.choose_perk(idx)); m._rebuild_ui(), "%s\n%s [%s]" % [String(d["name"]), String(d["desc"]), key], "DPERK " + String(d["name"]))
				"mutation":
					var mid: String = String(ids[k])
					var md: Dictionary = ModifierDB.MUTATIONS.get(mid, {})
					Kit.hit(m, r, func() -> void: m._handle(S.choose_mutation(idx)); m._rebuild_ui(), "%s\n%s [%s]" % [String(md.get("name", mid)), String(md.get("desc", "")), key], "DMUT " + String(md.get("name", mid)), true, Kit.MAG)
		if String(off["kind"]) == "draft":
			var by: float = lr.end.y - 112.0
			var bw: float = (lr.size.x - 40.0) * 0.5
			var rc: int = S.reroll_cost()
			var rl: String = "Reroll (free)" if rc == 0 else "Reroll  $%d" % rc
			Kit.btn(m, "%s [%s]" % [rl, Kit.hint(m, "reroll")], Rect2(lr.position.x + 14, by, bw, 48), m.reroll, "Re-roll the whole hand: 1 free per draft, then cash that doubles", rc == 0 or S.cash >= float(rc), Kit.GEM, "Reroll", "ui_reroll", 16)
			Kit.btn(m, "Banish (%d) [%s]" % [S.banish_left, Kit.hint(m, "banish")], Rect2(lr.position.x + 26 + bw, by, bw, 48), m.toggle_banish, "Banish mode: the next card you click leaves this run's pool and is replaced", S.banish_left > 0, Kit.ENEMY if m.banish_mode else Kit.NEUTRAL, "Banish", "ui_banish", 16)
		return
	if S.pending_place != "":
		Kit.btn(m, "Cancel placement [%s]" % Kit.hint(m, "cancel"), Rect2(lr.position.x + 14, lr.position.y + 250, lr.size.x - 28, 48), func() -> void: m._handle(S.cancel_place()); m._rebuild_ui(), "Skip placing this building (the pick is spent)", true, Kit.NEUTRAL, "CANCEL PLACE")


## Card press: pad = take immediately; mouse = start a drag (release in place
## takes the card; release over a cell places a NEW building there).
static func _press_card(m, k: int) -> void:
	if String(m.last_device) == "pad" or m.banish_mode:
		m.pick_card(k)
		return
	m.begin_drag_card(k)


static func draw(m) -> void:
	var S = m.S
	var lr: Rect2 = m.left_rect()
	m.draw_rect(lr, Kit.PANEL)
	m.draw_line(Vector2(lr.end.x, lr.position.y), Vector2(lr.end.x, lr.end.y), Kit.EDGE, 2.0)
	var x: float = lr.position.x + 16.0
	var w: float = lr.size.x - 32.0
	var off: Dictionary = _offer(m)
	if not off.is_empty():
		var kind: String = String(off["kind"])
		var title: String = "DRAFT — wave %d" % int(S.wave)
		if kind == "perk":
			title = "PERK — wave %d" % int(S.wave)
		elif kind == "mutation":
			title = "ENDLESS MUTATION"
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
		if kind == "draft":
			Kit.t(m, "Time is held while you choose", Vector2(x, lr.end.y - 22), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w)
		return
	if S.pending_place != "":
		var d2: Dictionary = PickDB.get_def(S.pending_place)
		Kit.t(m, "PLACE BUILDING", Vector2(x, lr.position.y + 34), 22, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, w)
		Kit.panel(m, Rect2(x, lr.position.y + 54, w, 180), Kit.rarity_col(String(d2["rarity"])), Kit.PANEL2)
		Kit.icon(m, S.pending_place, Rect2(x + 14, lr.position.y + 70, 80, 80))
		Kit.t(m, String(d2["name"]), Vector2(x + 108, lr.position.y + 100), 22, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 120)
		Kit.wrap(m, String(d2["desc"]), Vector2(x + 14, lr.position.y + 176), 15, Kit.DIM, w - 28, 3)
		Kit.wrap(m, "Click a glowing cell on the grid. Ring 1 hugs the Core; outer rings open as your Core tracks grow.", Vector2(x, lr.position.y + 330), 15, Kit.DIM, w, 4)
		return
	_draw_info(m, lr, x, w)


static func _draw_card(m, r: Rect2, cd: Dictionary, k: int) -> void:
	var S = m.S
	var id: String = String(cd["id"])
	var d: Dictionary = PickDB.get_def(id)
	var fam: String = String(cd.get("fam", d.get("fam", "")))
	var rar: String = String(cd.get("rarity", d.get("rarity", "common")))
	var rc: Color = Kit.rarity_col(rar)
	var dragging: bool = m.drag_card == k and m.mouse_pos.distance_to(m.drag_start) > 12.0
	var fill: Color = Color(rc.darkened(0.82), 0.95)
	if fam == "insight":
		var g: float = 0.5 + 0.5 * sin(m.t_anim * 4.0)
		m.draw_rect(r.grow(4.0 + 3.0 * g), Color(rc, 0.18))
	Kit.panel(m, r, Kit.ENEMY if m.banish_mode else rc, fill, 3)
	if dragging:
		m.draw_rect(r, Color(0, 0, 0, 0.45))
	var isz: float = minf(r.size.y - 44.0, 92.0)
	Kit.panel(m, Rect2(r.position.x + 10, r.position.y + 34, isz, isz), Color(rc, 0.5), Color("101418"), 1)
	Kit.icon(m, id, Rect2(r.position.x + 14, r.position.y + 38, isz - 8, isz - 8))
	var head: String = String(FAM_LABEL.get(fam, fam.to_upper()))
	if String(cd.get("kind", "")) == "plus":
		head = "LEVEL UP  Lv%d -> %d" % [int(cd.get("lvl", 1)), int(cd.get("to", 2))]
	elif String(cd.get("kind", "")) == "new" and fam == "building":
		head = "NEW BUILDING"
	elif fam == "special" and S.specials.any(func(s: Variant) -> bool: return String((s as Dictionary)["id"]) == id):
		head = "SPECIAL  +1 copy"
	elif fam == "pack":
		head = "UPGRADE PACK  %d/%d" % [S.pack_n(id) + 1, PickDB.max_of(id)]
	Kit.t(m, head, Vector2(r.position.x + 12, r.position.y + 24), 14, rc, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 70)
	Kit.t(m, rar.capitalize(), Vector2(r.end.x - 46, r.position.y + 24), 13, rc, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)
	var tx: float = r.position.x + 22.0 + isz
	var tw: float = r.end.x - tx - 10.0
	Kit.t(m, String(d.get("name", id)), Vector2(tx, r.position.y + 58), 21, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, tw)
	Kit.wrap(m, String(d.get("desc", "")), Vector2(tx, r.position.y + 70), 15, Kit.DIM, tw, int(maxf(1.0, (r.size.y - 104.0) / 18.0)))
	# tag chips
	var cx: float = tx
	for tg in (d.get("tags", []) as Array):
		var tag: String = String(tg)
		var cw: float = 22.0 + float(tag.length()) * 8.0
		if cx + cw > r.end.x - 8.0:
			break
		var cr := Rect2(cx, r.end.y - 28, cw, 20)
		Kit.panel(m, cr, Kit.EDGE, Color("14181d"), 1)
		Kit.icon(m, "tag_" + tag, Rect2(cx + 2, r.end.y - 27, 18, 18))
		Kit.t(m, tag, Vector2(cx + 20, r.end.y - 13), 12, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, cw - 20)
		cx += cw + 4.0
	# hotkey badge
	var hk: String = Kit.hint(m, "ability_%d" % (k + 1))
	Kit.panel(m, Rect2(r.end.x - 36, r.position.y + 6, 28, 24), Kit.EDGE, Color("101317"), 1)
	Kit.t(m, hk, Vector2(r.end.x - 22, r.position.y + 24), 15, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 28.0)


static func _draw_simple(m, r: Rect2, icon_id: String, head: String, name: String, desc: String, col: Color, k: int) -> void:
	Kit.panel(m, r, col, Color(col.darkened(0.82), 0.95), 3)
	var isz: float = minf(r.size.y - 44.0, 80.0)
	Kit.icon(m, icon_id, Rect2(r.position.x + 12, r.position.y + 36, isz, isz))
	Kit.t(m, head, Vector2(r.position.x + 12, r.position.y + 24), 14, col, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 60)
	var tx: float = r.position.x + 24.0 + isz
	Kit.t(m, name, Vector2(tx, r.position.y + 58), 21, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, r.end.x - tx - 10)
	Kit.wrap(m, desc, Vector2(tx, r.position.y + 70), 15, Kit.DIM, r.end.x - tx - 10, 4)
	Kit.t(m, Kit.hint(m, "ability_%d" % (k + 1)), Vector2(r.end.x - 22, r.position.y + 24), 15, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER, 28.0)


## No offer: hovered / selected cell info, then this run's build and loot.
static func _draw_info(m, lr: Rect2, x: float, w: float) -> void:
	var S = m.S
	var y: float = lr.position.y + 34.0
	Kit.t(m, "BUILD / INFO", Vector2(x, y), 20, Kit.RUST, HORIZONTAL_ALIGNMENT_LEFT, w)
	var focus: int = m.sel
	if m.field_rect().has_point(m.mouse_pos):
		var hv: int = m.slot_at(m.s2w(m.mouse_pos))
		if hv >= 0:
			focus = hv
	y += 16.0
	if focus >= 0:
		var id: String = "core_" + String(S.core_id) if focus == TowerState.CORE_SLOT else S.id_at(focus)
		var lines: PackedStringArray = load("res://ui/Battle.gd").cell_text(m, focus).split("\n")
		Kit.panel(m, Rect2(x, y, w, 176), Kit.EDGE, Kit.PANEL2)
		if id != "":
			Kit.icon(m, id, Rect2(x + 12, y + 12, 64, 64))
		Kit.t(m, lines[0], Vector2(x + 88, y + 40), 19, Kit.TEXT, HORIZONTAL_ALIGNMENT_LEFT, w - 96)
		Kit.wrap(m, "\n".join(lines.slice(1)), Vector2(x + 12, y + 96), 15, Kit.DIM, w - 24, 4)
		y += 190.0
	else:
		Kit.wrap(m, "Hover a cell for details. Drafts arrive after waves 1, 2, 3, then every 2nd wave (plus an Epic+ draft on boss waves). Cash buys Core tracks on the right.", Vector2(x, y + 10), 15, Kit.DIM, w, 5)
		y += 110.0
	# run build summary
	Kit.head(m, "THIS RUN", Vector2(x, y + 10), w)
	y += 22.0
	var blds: int = S.building_count()
	Kit.row(m, "Buildings / huts", "%d / %d" % [blds, S.hut_count()], Vector2(x, y + 18), w, Kit.TEXT, "Buildings on the grid (huts included) — duplicates level them to L5", 15)
	Kit.row(m, "Rings open", "%d / 3" % int(S.rings_open), Vector2(x, y + 40), w, Kit.TEXT, "Outer rings open as Core track levels grow", 15)
	Kit.row(m, "Troops", str(S.troops.filter(func(t: Variant) -> bool: return String((t as Dictionary).get("state", "")) != "dead").size()), Vector2(x, y + 62), w, Kit.TEXT, "Troops roaming the lanes from your huts", 15)
	y += 76.0
	# packs owned
	var px: float = x
	for pid in S.packs.keys():
		if px + 40.0 > x + w:
			break
		Kit.icon(m, String(pid), Rect2(px, y, 34, 34))
		Kit.t(m, "x%d" % int(S.packs[pid]), Vector2(px + 20, y + 36), 12, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, 30.0)
		m.stat_tips.append([Rect2(px, y, 34, 34), "%s x%d\n%s" % [String(PickDB.get_def(String(pid)).get("name", "")), int(S.packs[pid]), String(PickDB.get_def(String(pid)).get("desc", ""))]])
		px += 40.0
	if not S.packs.is_empty():
		y += 46.0
	for iid in S.insight_found:
		Kit.icon(m, String(iid), Rect2(x, y, 26, 26))
		Kit.t(m, String(PickDB.get_def(String(iid)).get("name", "")), Vector2(x + 32, y + 19), 14, Kit.RARITY["insight"], HORIZONTAL_ALIGNMENT_LEFT, w - 32)
		y += 28.0
	# loot so far
	var lt: Dictionary = S.loot
	var parts: int = (lt.get("parts", []) as Array).size()
	var bits: Array = []
	if parts > 0:
		bits.append("%d part%s" % [parts, "" if parts == 1 else "s"])
	if int(lt.get("scrap", 0)) > 0:
		bits.append("%d Scrap" % int(lt["scrap"]))
	if int(lt.get("keys", 0)) > 0:
		bits.append("%d Keys" % int(lt["keys"]))
	if int(lt.get("core_cores", 0)) > 0:
		bits.append("%d Core Cores" % int(lt["core_cores"]))
	Kit.row(m, "Loot", ", ".join(bits) if not bits.is_empty() else "none yet", Vector2(x, y + 20), w, Kit.SCRAP, "Banked when the run ends: bosses, marked elites and Couriers drop parts", 15)
	# hotkey legend
	var leg: Array = [["hotbar_1", "Specials (1-4)"], ["ability_1", "Draft picks (Q W E R)"], ["track_1", "Core tracks (Shift+1-5)"], ["reroll", "Reroll"], ["pause", "Pause"], ["lane_next", "Lane focus"]]
	var ly: float = lr.end.y - 22.0 * float(leg.size()) - 12.0
	if ly > y + 40.0:
		Kit.head(m, "HOTKEYS", Vector2(x, ly - 8), w, Kit.DIM)
		for k in leg.size():
			var a: Array = leg[k]
			Kit.t(m, Kit.hint(m, String(a[0])), Vector2(x, ly + 16 + k * 22.0), 14, Kit.GOLD, HORIZONTAL_ALIGNMENT_LEFT, 100.0)
			Kit.t(m, String(a[1]), Vector2(x + 104, ly + 16 + k * 22.0), 14, Kit.DIM, HORIZONTAL_ALIGNMENT_LEFT, w - 104)
